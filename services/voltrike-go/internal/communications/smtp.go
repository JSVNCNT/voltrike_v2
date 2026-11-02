package communications

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"encoding/hex"
	"fmt"
	"mime"
	"mime/multipart"
	"mime/quotedprintable"
	"net"
	"net/mail"
	"net/smtp"
	"net/textproto"
	"regexp"
	"strings"
	"time"
)

const smtpHost = "smtp-relay.brevo.com"

var emailPattern = regexp.MustCompile(`^[^\s@]+@[^\s@]+\.[^\s@]+$`)
var smtpSlots = make(chan struct{}, 3)

type Settings struct {
	Login, Key, SenderEmail, SenderName string
}

type Sender struct {
	settings  Settings
	address   string
	tlsConfig *tls.Config
}

func NewSender(settings Settings) *Sender {
	settings.SenderEmail = strings.TrimSpace(settings.SenderEmail)
	settings.SenderName = fallback(settings.SenderName, "VolTrike")
	return &Sender{settings: settings, address: net.JoinHostPort(smtpHost, "587"), tlsConfig: &tls.Config{ServerName: smtpHost, MinVersion: tls.VersionTLS12}}
}

func ValidEmail(value string) bool {
	value = strings.TrimSpace(value)
	if len(value) > 254 || !emailPattern.MatchString(value) {
		return false
	}
	address, err := mail.ParseAddress(value)
	return err == nil && address.Address == value && address.Name == ""
}

// Send requires STARTTLS before authenticating and observes the request's
// deadline during SMTP greeting, authentication, and DATA transfer. A returned
// message ID means SMTP acceptance, not confirmed delivery to an inbox.
func (sender *Sender) Send(ctx context.Context, to, name string, message Message) (string, error) {
	if sender.settings.Login == "" || sender.settings.Key == "" {
		return "", fmt.Errorf("Brevo SMTP credentials are not configured")
	}
	to = strings.TrimSpace(to)
	if !ValidEmail(sender.settings.SenderEmail) || !ValidEmail(to) {
		return "", fmt.Errorf("a valid sender and recipient email are required")
	}
	if strings.ContainsAny(message.Subject, "\r\n") {
		return "", fmt.Errorf("email subject contains invalid header characters")
	}
	select {
	case smtpSlots <- struct{}{}:
		defer func() { <-smtpSlots }()
	case <-ctx.Done():
		return "", ctx.Err()
	}
	ctx, cancel := context.WithTimeout(ctx, 25*time.Second)
	defer cancel()
	connection, err := (&net.Dialer{}).DialContext(ctx, "tcp", sender.address)
	if err != nil {
		return "", fmt.Errorf("connect to Brevo SMTP: %w", err)
	}
	defer connection.Close()
	stop := context.AfterFunc(ctx, func() { _ = connection.Close() })
	defer stop()
	if deadline, ok := ctx.Deadline(); ok {
		if err := connection.SetDeadline(deadline); err != nil {
			return "", err
		}
	}
	client, err := smtp.NewClient(connection, sender.tlsConfig.ServerName)
	if err != nil {
		return "", smtpFailure(ctx, "greeting", err)
	}
	defer client.Close()
	if ok, _ := client.Extension("STARTTLS"); !ok {
		return "", fmt.Errorf("Brevo SMTP did not offer required STARTTLS")
	}
	if err := client.StartTLS(sender.tlsConfig.Clone()); err != nil {
		return "", smtpFailure(ctx, "STARTTLS", err)
	}
	if err := client.Auth(smtp.PlainAuth("", sender.settings.Login, sender.settings.Key, sender.tlsConfig.ServerName)); err != nil {
		return "", smtpFailure(ctx, "authentication", err)
	}
	if err := client.Mail(sender.settings.SenderEmail); err != nil {
		return "", smtpFailure(ctx, "sender", err)
	}
	if err := client.Rcpt(to); err != nil {
		return "", smtpFailure(ctx, "recipient", err)
	}
	encoded, messageID, err := sender.encode(to, name, message)
	if err != nil {
		return "", err
	}
	writer, err := client.Data()
	if err != nil {
		return "", smtpFailure(ctx, "DATA", err)
	}
	if _, err := writer.Write(encoded); err != nil {
		_ = writer.Close()
		return "", smtpFailure(ctx, "message transfer", err)
	}
	if err := writer.Close(); err != nil {
		return "", smtpFailure(ctx, "message acceptance", err)
	}
	// Acceptance has already happened. A connection closing during QUIT must not
	// cause a caller to retry and send the accepted message a second time.
	_ = client.Quit()
	return messageID, nil
}

func smtpFailure(ctx context.Context, stage string, err error) error {
	if ctx.Err() != nil {
		return ctx.Err()
	}
	if failure, ok := err.(net.Error); ok && failure.Timeout() {
		if deadline, exists := ctx.Deadline(); exists && !time.Now().Before(deadline) {
			return context.DeadlineExceeded
		}
	}
	// Provider replies can contain recipient addresses. Keep those out of normal
	// request errors while preserving a useful SMTP status code for operations.
	if failure, ok := err.(*textproto.Error); ok {
		return fmt.Errorf("Brevo SMTP %s failed (status %d)", stage, failure.Code)
	}
	return fmt.Errorf("Brevo SMTP %s failed", stage)
}

func (sender *Sender) encode(to, name string, message Message) ([]byte, string, error) {
	var body bytes.Buffer
	multipartWriter := multipart.NewWriter(&body)
	for _, part := range []struct{ kind, value string }{{"text/plain", message.Text}, {"text/html", message.HTML}} {
		header := textproto.MIMEHeader{}
		header.Set("Content-Type", part.kind+`; charset="utf-8"`)
		header.Set("Content-Transfer-Encoding", "quoted-printable")
		writer, err := multipartWriter.CreatePart(header)
		if err != nil {
			return nil, "", err
		}
		encoder := quotedprintable.NewWriter(writer)
		if _, err := encoder.Write([]byte(part.value)); err != nil {
			return nil, "", err
		}
		if err := encoder.Close(); err != nil {
			return nil, "", err
		}
	}
	if err := multipartWriter.Close(); err != nil {
		return nil, "", err
	}
	var identifier [16]byte
	if _, err := rand.Read(identifier[:]); err != nil {
		return nil, "", err
	}
	domain := strings.SplitN(sender.settings.SenderEmail, "@", 2)[1]
	messageID := "<" + hex.EncodeToString(identifier[:]) + "@" + domain + ">"
	var result bytes.Buffer
	fmt.Fprintf(&result, "From: %s\r\nTo: %s\r\nReply-To: %s\r\nSubject: %s\r\nDate: %s\r\nMessage-ID: %s\r\nMIME-Version: 1.0\r\nContent-Type: multipart/alternative; boundary=%q\r\n\r\n",
		(&mail.Address{Name: sender.settings.SenderName, Address: sender.settings.SenderEmail}).String(),
		(&mail.Address{Name: name, Address: to}).String(), sender.settings.SenderEmail,
		mime.QEncoding.Encode("utf-8", message.Subject), time.Now().UTC().Format(time.RFC1123Z), messageID, multipartWriter.Boundary())
	result.Write(body.Bytes())
	return result.Bytes(), messageID, nil
}
