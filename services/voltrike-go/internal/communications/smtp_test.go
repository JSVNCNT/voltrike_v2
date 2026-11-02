package communications

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"math/big"
	"mime"
	"mime/multipart"
	"net"
	"net/mail"
	"net/textproto"
	"strings"
	"testing"
	"time"
)

type smtpCapture struct {
	commands []string
	message  []byte
	version  uint16
	err      error
}

func testSender(t *testing.T, startTLS, rejectRecipient bool) (*Sender, <-chan smtpCapture) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	certificate := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "localhost"}, DNSNames: []string{"localhost"}, NotBefore: time.Now().Add(-time.Minute), NotAfter: time.Now().Add(time.Hour), KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	der, err := x509.CreateCertificate(rand.Reader, certificate, certificate, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	parsed, err := x509.ParseCertificate(der)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(parsed)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = listener.Close() })
	captured := make(chan smtpCapture, 1)
	go func() {
		result := smtpCapture{}
		defer func() { captured <- result }()
		connection, err := listener.Accept()
		if err != nil {
			result.err = err
			return
		}
		defer connection.Close()
		_ = connection.SetDeadline(time.Now().Add(5 * time.Second))
		protocol := textproto.NewConn(connection)
		if err := protocol.PrintfLine("220 localhost SMTP"); err != nil {
			result.err = err
			return
		}
		encrypted := false
		for {
			line, err := protocol.ReadLine()
			if err != nil {
				if !errors.Is(err, io.EOF) {
					result.err = err
				}
				return
			}
			// Never capture credentials, even the fake ones, in failure output.
			command, _, _ := strings.Cut(line, " ")
			result.commands = append(result.commands, command)
			switch command {
			case "EHLO":
				if startTLS && !encrypted {
					err = protocol.PrintfLine("250-localhost\r\n250-STARTTLS\r\n250 AUTH PLAIN")
				} else {
					err = protocol.PrintfLine("250-localhost\r\n250 AUTH PLAIN")
				}
			case "STARTTLS":
				if err = protocol.PrintfLine("220 Ready for TLS"); err == nil {
					secured := tls.Server(connection, &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: key}}})
					if err = secured.Handshake(); err == nil {
						result.version = secured.ConnectionState().Version
						protocol, encrypted = textproto.NewConn(secured), true
					}
				}
			case "AUTH":
				if !encrypted {
					err = fmt.Errorf("authentication attempted before TLS")
					break
				}
				fields := strings.Fields(line)
				if len(fields) != 3 {
					err = fmt.Errorf("invalid authentication exchange")
					break
				}
				payload, decodeErr := base64.StdEncoding.DecodeString(fields[2])
				if decodeErr != nil || !bytes.Equal(payload, []byte("\x00test-login\x00test-key")) {
					err = fmt.Errorf("unexpected authentication credentials")
					break
				}
				err = protocol.PrintfLine("235 Authenticated")
			case "MAIL":
				err = protocol.PrintfLine("250 Sender accepted")
			case "RCPT":
				if rejectRecipient {
					err = protocol.PrintfLine("550 rejected recipient@example.test")
				} else {
					err = protocol.PrintfLine("250 Recipient accepted")
				}
			case "DATA":
				if err = protocol.PrintfLine("354 End with a dot"); err == nil {
					result.message, err = io.ReadAll(protocol.DotReader())
					if err == nil {
						err = protocol.PrintfLine("250 Message queued")
					}
				}
			case "QUIT":
				result.err = protocol.PrintfLine("221 Goodbye")
				return
			default:
				err = fmt.Errorf("unexpected SMTP command %s", command)
			}
			if err != nil {
				result.err = err
				return
			}
		}
	}()
	sender := NewSender(Settings{Login: "test-login", Key: "test-key", SenderEmail: "sender@example.test", SenderName: "VolTrike"})
	sender.address = listener.Addr().String()
	sender.tlsConfig = &tls.Config{ServerName: "localhost", RootCAs: roots, MinVersion: tls.VersionTLS12}
	return sender, captured
}

func TestSMTPSendRequiresTLSAndPreservesAlternativeBodies(t *testing.T) {
	sender, captured := testSender(t, true, false)
	message := VerificationEmail("Ana & 李", "https://example.test/action?oobCode=secret&mode=verifyEmail", "")
	messageID, err := sender.Send(context.Background(), "recipient@example.test", "Ana\r\nBcc: stolen@example.test", message)
	if err != nil {
		t.Fatal(err)
	}
	result := <-captured
	if result.err != nil {
		t.Fatal(result.err)
	}
	if result.version < tls.VersionTLS12 {
		t.Fatal("SMTP did not negotiate TLS 1.2 or newer")
	}
	wantCommands := "EHLO STARTTLS EHLO AUTH MAIL RCPT DATA QUIT"
	if strings.Join(result.commands, " ") != wantCommands {
		t.Fatalf("SMTP exchange = %v", result.commands)
	}
	parsed, err := mail.ReadMessage(bytes.NewReader(result.message))
	if err != nil {
		t.Fatal(err)
	}
	if parsed.Header.Get("Message-ID") != messageID || parsed.Header.Get("Bcc") != "" {
		t.Fatal("message ID was lost or an injected Bcc header was accepted")
	}
	kind, params, err := mime.ParseMediaType(parsed.Header.Get("Content-Type"))
	if err != nil || kind != "multipart/alternative" {
		t.Fatalf("content type = %s, %v", kind, err)
	}
	reader := multipart.NewReader(parsed.Body, params["boundary"])
	for index, expected := range []string{message.Text, message.HTML} {
		part, err := reader.NextPart()
		if err != nil {
			t.Fatal(err)
		}
		body, err := io.ReadAll(part)
		// MIME readers normalize CRLF; content remains unchanged.
		if err != nil || strings.ReplaceAll(string(body), "\r\n", "\n") != expected {
			t.Fatalf("MIME part %d did not preserve its original UTF-8 content: %v", index, err)
		}
	}
	if _, err := reader.NextPart(); !errors.Is(err, io.EOF) {
		t.Fatal("unexpected extra MIME part")
	}
}

func TestSMTPNeverAuthenticatesWithoutSTARTTLS(t *testing.T) {
	sender, captured := testSender(t, false, false)
	if _, err := sender.Send(context.Background(), "recipient@example.test", "", PlainEmail("Test", "Test")); err == nil || !strings.Contains(err.Error(), "STARTTLS") {
		t.Fatalf("missing STARTTLS error = %v", err)
	}
	result := <-captured
	if strings.Join(result.commands, " ") != "EHLO" {
		t.Fatalf("sent commands before required TLS: %v", result.commands)
	}
}

func TestSMTPRecipientFailureDoesNotDiscloseAddress(t *testing.T) {
	sender, captured := testSender(t, true, true)
	_, err := sender.Send(context.Background(), "recipient@example.test", "", PlainEmail("Test", "Test"))
	if err == nil || !strings.Contains(err.Error(), "550") || strings.Contains(err.Error(), "recipient@example.test") {
		t.Fatalf("provider failure was not safely classified: %v", err)
	}
	if result := <-captured; result.err != nil {
		t.Fatal(result.err)
	}
}

func TestSMTPCancellationInterruptsUnresponsiveGreeting(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	closed := make(chan struct{})
	go func() {
		defer close(closed)
		connection, err := listener.Accept()
		if err == nil {
			defer connection.Close()
			_, _ = io.Copy(io.Discard, connection)
		}
	}()
	sender := NewSender(Settings{Login: "test-login", Key: "test-key", SenderEmail: "sender@example.test"})
	sender.address = listener.Addr().String()
	ctx, cancel := context.WithTimeout(context.Background(), 75*time.Millisecond)
	defer cancel()
	started := time.Now()
	_, err = sender.Send(ctx, "recipient@example.test", "", PlainEmail("Test", "Test"))
	if !errors.Is(err, context.DeadlineExceeded) || time.Since(started) > time.Second {
		t.Fatalf("SMTP did not honor cancellation promptly: %v", err)
	}
	<-closed
}

func TestSMTPRejectsHeaderInjectionBeforeDialing(t *testing.T) {
	sender := NewSender(Settings{Login: "test-login", Key: "test-key", SenderEmail: "sender@example.test"})
	for _, recipient := range []string{"invalid", "a@example.test\r\nBcc: b@example.test", "Someone <a@example.test>"} {
		if _, err := sender.Send(context.Background(), recipient, "", PlainEmail("Test", "Test")); err == nil {
			t.Fatalf("accepted invalid recipient %q", recipient)
		}
	}
	if _, err := sender.Send(context.Background(), "recipient@example.test", "", PlainEmail("Test\r\nBcc: b@example.test", "Test")); err == nil {
		t.Fatal("accepted injected subject header")
	}
}
