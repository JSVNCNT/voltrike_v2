// Package communications contains VolTrike's transactional email presentation
// and SMTP transport. Firebase Authentication remains the authority for action
// links; this package only renders and delivers the messages.
package communications

import (
	"fmt"
	"html"
	"strings"
)

type Message struct {
	Subject string
	HTML    string
	Text    string
}

type fact struct{ label, value string }
type content struct {
	eyebrow, title, greeting, actionLabel, actionURL, footer, logoURL string
	paragraphs                                                        []string
	facts                                                             []fact
}

func transactional(subject string, value content) Message {
	lines := []string{value.title, "", value.greeting, ""}
	var paragraphs, rows strings.Builder
	for _, paragraph := range value.paragraphs {
		lines = append(lines, paragraph, "")
		fmt.Fprintf(&paragraphs, `<p style="font-size:15px;line-height:1.65;color:#405f60;margin:0 0 14px">%s</p>`, html.EscapeString(paragraph))
	}
	for _, item := range value.facts {
		if item.label == "" || item.value == "" {
			continue
		}
		lines = append(lines, item.label+": "+item.value)
		fmt.Fprintf(&rows, `<tr><td style="padding:7px 12px;color:#607778;font-size:13px">%s</td><td style="padding:7px 12px;color:#123a3a;font-size:13px;font-weight:600;text-align:right">%s</td></tr>`, html.EscapeString(item.label), html.EscapeString(item.value))
	}
	if len(value.facts) > 0 {
		lines = append(lines, "")
	}
	button, logo, facts := "", "", ""
	if value.actionLabel != "" && value.actionURL != "" {
		lines = append(lines, value.actionLabel+":", value.actionURL, "")
		button = fmt.Sprintf(`<p style="margin:28px 0"><a href="%s" style="display:inline-block;background:#087f83;color:#fff;text-decoration:none;padding:13px 22px;border-radius:10px;font-weight:700">%s</a></p>`, html.EscapeString(value.actionURL), html.EscapeString(value.actionLabel))
	}
	if value.logoURL != "" {
		logo = fmt.Sprintf(`<td style="padding-right:16px"><img src="%s" width="64" height="64" alt="VolTrike" style="display:block;width:64px;height:64px;border:0;border-radius:12px"></td>`, html.EscapeString(value.logoURL))
	}
	if rows.Len() > 0 {
		facts = `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:22px 0;background:#f5f9f9;border-radius:12px">` + rows.String() + `</table>`
	}
	lines = append(lines, value.footer)
	body := fmt.Sprintf(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
<body style="margin:0;background:#f3f7f7;font-family:Arial,Helvetica,sans-serif;color:#173b3b">
<div style="display:none;max-height:0;overflow:hidden">%s</div>
<table role="presentation" width="100%%" cellspacing="0" cellpadding="0" style="background:#f3f7f7"><tr><td align="center" style="padding:28px 12px">
<table role="presentation" width="100%%" cellspacing="0" cellpadding="0" style="max-width:620px;background:#fff;border:1px solid #d8e5e5;border-radius:18px;overflow:hidden">
<tr><td style="background:#064c4d;padding:22px 30px;color:#fff"><table role="presentation" cellspacing="0" cellpadding="0"><tr>%s<td><div style="font-size:25px;font-weight:800;letter-spacing:.3px">VolTrike</div><div style="margin-top:4px;color:#cbe5e5;font-size:13px">Clean Community Mobility</div></td></tr></table></td></tr>
<tr><td style="padding:32px 30px"><div style="color:#087f83;font-size:12px;font-weight:800;letter-spacing:1.4px;text-transform:uppercase">%s</div>
<h1 style="margin:10px 0 18px;font-size:27px;line-height:1.25;color:#123a3a">%s</h1><p style="font-size:16px;line-height:1.6;margin:0 0 14px">%s</p>%s%s%s
<p style="font-size:12px;line-height:1.55;color:#718687;margin:26px 0 0">%s</p></td></tr></table></td></tr></table></body></html>`,
		html.EscapeString(value.title), logo, html.EscapeString(value.eyebrow), html.EscapeString(value.title), html.EscapeString(value.greeting), paragraphs.String(), facts, button, html.EscapeString(value.footer))
	return Message{Subject: subject, HTML: body, Text: strings.TrimSpace(strings.Join(lines, "\n"))}
}

func VerificationEmail(name, link, logo string) Message {
	return transactional("Verify your VolTrike email address", content{
		eyebrow: "Account verification", title: "Confirm your email address", greeting: "Hello " + fallback(name, "VolTrike user") + ",", logoURL: logo,
		paragraphs:  []string{"Confirm that this email address belongs to you before using your VolTrike account.", "This secure Firebase verification link expires automatically. If you did not create this account, you can ignore this message."},
		actionLabel: "Verify email address", actionURL: link,
		footer: "This is a required transactional account email, not a promotional message. VolTrike will never ask for your password by email.",
	})
}

func PasswordResetEmail(name, link, logo string) Message {
	return transactional("Reset your VolTrike password", content{
		eyebrow: "Password assistance", title: "Reset your VolTrike password", greeting: "Hello " + fallback(name, "VolTrike user") + ",", logoURL: logo,
		paragraphs:  []string{"A password reset was requested for your VolTrike account.", "Use the secure Firebase link below to choose a new password. If you did not request this, ignore this email and your password will remain unchanged."},
		actionLabel: "Reset password", actionURL: link,
		footer: "For your security, VolTrike will never ask you to reply with your password or verification code.",
	})
}

type SafetyAlert struct {
	RecipientName, EventLabel, AdminPortalURL, LogoURL string
	Incident                                           map[string]any
}

func SafetyAlertEmail(alert SafetyAlert) Message {
	read := func(key string) string {
		value := alert.Incident[key]
		if value == nil {
			return ""
		}
		return fmt.Sprint(value)
	}
	level := 0
	switch value := alert.Incident["escalationLevel"].(type) {
	case int:
		level = value
	case int64:
		level = int(value)
	case float64:
		level = int(value)
	}
	prefix, eyebrow := "", "New safety incident"
	if level > 0 {
		prefix, eyebrow = "Escalated ", fmt.Sprintf("Safety escalation level %d", level)
	}
	return transactional(prefix+"VolTrike SOS - "+read("bookingId"), content{
		eyebrow: eyebrow, title: alert.EventLabel, greeting: "Hello " + fallback(alert.RecipientName, "administrator") + ",", logoURL: alert.LogoURL,
		paragraphs:  []string{"A VolTrike ride safety incident requires administrator acknowledgement. Check the map, attempt contact, and call 911 when there is immediate danger.", "Cancelling the booking is an operational safeguard and does not resolve the emergency record."},
		facts:       []fact{{"Booking", read("bookingId")}, {"Reported by", read("reporterRole")}, {"TODA", fallback(read("todaName"), fallback(read("todaId"), "Unassigned"))}, {"Ride status", fallback(read("bookingStatus"), "Unknown")}, {"Pickup", fallback(read("pickupAddress"), "Unavailable")}, {"Destination", fallback(read("destinationAddress"), "Unavailable")}},
		actionLabel: "Open Safety Incidents", actionURL: alert.AdminPortalURL,
		footer: "You are receiving this transactional safety email because your active administrator account is responsible for this incident. Notification preferences can be edited on the Safety Incidents page.",
	})
}

type TodaApplication struct {
	AdministratorName, TodaName, Status, AdminPortalURL, LogoURL string
}

func TodaApplicationEmail(application TodaApplication) (Message, error) {
	var eyebrow, title, paragraph string
	switch application.Status {
	case "submitted":
		eyebrow, title, paragraph = "TODA registration", "Application received", "Your legal registration information and evidence are queued for Developer Admin review."
	case "approved":
		eyebrow, title, paragraph = "TODA registration approved", "Administrator access approved", "Your TODA administrator role is approved. Sign in again to refresh your administrator permissions."
	case "declined":
		eyebrow, title, paragraph = "TODA registration decision", "Application requires follow-up", "Your TODA application was declined. Contact the Developer Admin for the review details before submitting corrected information."
	default:
		return Message{}, fmt.Errorf("unsupported TODA application status")
	}
	return transactional("VolTrike TODA application - "+title, content{
		eyebrow: eyebrow, title: title, greeting: "Hello " + fallback(application.AdministratorName, "administrator") + ",", logoURL: application.LogoURL,
		paragraphs: []string{paragraph}, facts: []fact{{"TODA", application.TodaName}}, actionLabel: "Open VolTrike Admin", actionURL: application.AdminPortalURL,
		footer: "This is a transactional registration message related to your VolTrike administrator application.",
	}), nil
}

func PlainEmail(subject, body string) Message {
	return Message{Subject: subject, Text: body, HTML: "<p>" + html.EscapeString(body) + "</p>"}
}

func fallback(value, otherwise string) string {
	if value == "" {
		return otherwise
	}
	return value
}
