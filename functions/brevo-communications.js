'use strict';

const nodemailer = require('nodemailer');

const BREVO_SMTP_HOST = 'smtp-relay.brevo.com';
const BREVO_SMTP_PORT = 587;

let cachedTransport;
let cachedTransportLogin;

function escapeHtml(value) {
  return String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');
}

function validEmail(value) {
  return typeof value === 'string' &&
    /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim()) &&
    value.trim().length <= 254;
}

function plainTextEmail({
  title,
  greeting,
  paragraphs,
  facts = [],
  actionLabel,
  actionUrl,
  footer,
}) {
  const lines = [
    title,
    '',
    greeting,
    '',
    ...paragraphs.flatMap((paragraph) => [paragraph, '']),
  ];
  for (const fact of facts.filter((entry) => entry?.label && entry?.value)) {
    lines.push(`${fact.label}: ${fact.value}`);
  }
  if (facts.length > 0) lines.push('');
  if (actionLabel && actionUrl) {
    lines.push(`${actionLabel}:`, actionUrl, '');
  }
  lines.push(footer);
  return lines.join('\n').trim();
}

function emailShell({
  eyebrow,
  title,
  greeting,
  paragraphs,
  facts = [],
  actionLabel,
  actionUrl,
  footer,
  logoUrl,
}) {
  const factRows = facts
    .filter((entry) => entry?.label && entry?.value)
    .map((entry) => `
      <tr>
        <td style="padding:7px 12px;color:#607778;font-size:13px">${escapeHtml(entry.label)}</td>
        <td style="padding:7px 12px;color:#123a3a;font-size:13px;font-weight:600;text-align:right">${escapeHtml(entry.value)}</td>
      </tr>`)
    .join('');
  const button = actionLabel && actionUrl
    ? `<p style="margin:28px 0">
        <a href="${escapeHtml(actionUrl)}" style="display:inline-block;background:#087f83;color:#fff;text-decoration:none;padding:13px 22px;border-radius:10px;font-weight:700">${escapeHtml(actionLabel)}</a>
      </p>`
    : '';
  const logo = logoUrl
    ? `<td style="padding-right:16px">
        <img src="${escapeHtml(logoUrl)}" width="64" height="64" alt="VolTrike" style="display:block;width:64px;height:64px;border:0;border-radius:12px">
      </td>`
    : '';
  return `<!doctype html>
  <html lang="en">
  <head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
  <body style="margin:0;background:#f3f7f7;font-family:Arial,Helvetica,sans-serif;color:#173b3b">
    <div style="display:none;max-height:0;overflow:hidden">${escapeHtml(title)}</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f3f7f7">
      <tr><td align="center" style="padding:28px 12px">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:620px;background:#fff;border:1px solid #d8e5e5;border-radius:18px;overflow:hidden">
          <tr><td style="background:#064c4d;padding:22px 30px;color:#fff">
            <table role="presentation" cellspacing="0" cellpadding="0">
              <tr>
                ${logo}
                <td>
                  <div style="font-size:25px;font-weight:800;letter-spacing:.3px">VolTrike</div>
                  <div style="margin-top:4px;color:#cbe5e5;font-size:13px">Clean Community Mobility</div>
                </td>
              </tr>
            </table>
          </td></tr>
          <tr><td style="padding:32px 30px">
            <div style="color:#087f83;font-size:12px;font-weight:800;letter-spacing:1.4px;text-transform:uppercase">${escapeHtml(eyebrow)}</div>
            <h1 style="margin:10px 0 18px;font-size:27px;line-height:1.25;color:#123a3a">${escapeHtml(title)}</h1>
            <p style="font-size:16px;line-height:1.6;margin:0 0 14px">${escapeHtml(greeting)}</p>
            ${paragraphs.map((paragraph) => `<p style="font-size:15px;line-height:1.65;color:#405f60;margin:0 0 14px">${escapeHtml(paragraph)}</p>`).join('')}
            ${factRows ? `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="margin:22px 0;background:#f5f9f9;border-radius:12px">${factRows}</table>` : ''}
            ${button}
            <p style="font-size:12px;line-height:1.55;color:#718687;margin:26px 0 0">${escapeHtml(footer)}</p>
          </td></tr>
        </table>
      </td></tr>
    </table>
  </body>
  </html>`;
}

function transactionalMessage({
  subject,
  eyebrow,
  content,
  logoUrl,
  tags,
}) {
  return {
    subject,
    htmlContent: emailShell({ eyebrow, ...content, logoUrl }),
    textContent: plainTextEmail(content),
    tags,
  };
}

function verificationEmail({ name, verificationLink, logoUrl }) {
  return transactionalMessage({
    subject: 'Verify your VolTrike email address',
    eyebrow: 'Account verification',
    logoUrl,
    tags: ['account-verification'],
    content: {
      title: 'Confirm your email address',
      greeting: `Hello ${name || 'VolTrike user'},`,
      paragraphs: [
        'Confirm that this email address belongs to you before using your VolTrike account.',
        'This secure Firebase verification link expires automatically. If you did not create this account, you can ignore this message.',
      ],
      actionLabel: 'Verify email address',
      actionUrl: verificationLink,
      footer: 'This is a required transactional account email, not a promotional message. VolTrike will never ask for your password by email.',
    },
  });
}

function passwordResetEmail({ name, resetLink, logoUrl }) {
  return transactionalMessage({
    subject: 'Reset your VolTrike password',
    eyebrow: 'Password assistance',
    logoUrl,
    tags: ['password-reset'],
    content: {
      title: 'Reset your VolTrike password',
      greeting: `Hello ${name || 'VolTrike user'},`,
      paragraphs: [
        'A password reset was requested for your VolTrike account.',
        'Use the secure Firebase link below to choose a new password. If you did not request this, ignore this email and your password will remain unchanged.',
      ],
      actionLabel: 'Reset password',
      actionUrl: resetLink,
      footer: 'For your security, VolTrike will never ask you to reply with your password or verification code.',
    },
  });
}

function safetyAlertEmail({
  recipientName,
  eventLabel,
  incident,
  adminPortalUrl,
  logoUrl,
}) {
  const level = Number(incident.escalationLevel || 0);
  return transactionalMessage({
    subject: `${level > 0 ? 'Escalated ' : ''}VolTrike SOS - ${incident.bookingId}`,
    eyebrow: level > 0
      ? `Safety escalation level ${level}`
      : 'New safety incident',
    logoUrl,
    tags: ['safety-incident', `escalation-${level}`],
    content: {
      title: eventLabel,
      greeting: `Hello ${recipientName || 'administrator'},`,
      paragraphs: [
        'A VolTrike ride safety incident requires administrator acknowledgement. Check the map, attempt contact, and call 911 when there is immediate danger.',
        'Cancelling the booking is an operational safeguard and does not resolve the emergency record.',
      ],
      facts: [
        { label: 'Booking', value: incident.bookingId },
        { label: 'Reported by', value: incident.reporterRole },
        {
          label: 'TODA',
          value: incident.todaName || incident.todaId || 'Unassigned',
        },
        {
          label: 'Ride status',
          value: incident.bookingStatus || 'Unknown',
        },
        { label: 'Pickup', value: incident.pickupAddress || 'Unavailable' },
        {
          label: 'Destination',
          value: incident.destinationAddress || 'Unavailable',
        },
      ],
      actionLabel: 'Open Safety Incidents',
      actionUrl: adminPortalUrl,
      footer: 'You are receiving this transactional safety email because your active administrator account is responsible for this incident. Notification preferences can be edited on the Safety Incidents page.',
    },
  });
}

function todaApplicationEmail({
  administratorName,
  todaName,
  status,
  adminPortalUrl,
  logoUrl,
}) {
  const copy = {
    submitted: {
      eyebrow: 'TODA registration',
      title: 'Application received',
      paragraph: 'Your legal registration information and evidence are queued for Developer Admin review.',
    },
    approved: {
      eyebrow: 'TODA registration approved',
      title: 'Administrator access approved',
      paragraph: 'Your TODA administrator role is approved. Sign in again to refresh your administrator permissions.',
    },
    declined: {
      eyebrow: 'TODA registration decision',
      title: 'Application requires follow-up',
      paragraph: 'Your TODA application was declined. Contact the Developer Admin for the review details before submitting corrected information.',
    },
  }[status];
  return transactionalMessage({
    subject: `VolTrike TODA application - ${copy.title}`,
    eyebrow: copy.eyebrow,
    logoUrl,
    tags: ['toda-registration', status],
    content: {
      title: copy.title,
      greeting: `Hello ${administratorName || 'administrator'},`,
      paragraphs: [copy.paragraph],
      facts: [{ label: 'TODA', value: todaName }],
      actionLabel: 'Open VolTrike Admin',
      actionUrl: adminPortalUrl,
      footer: 'This is a transactional registration message related to your VolTrike administrator application.',
    },
  });
}

function brevoTransport({ smtpLogin, smtpKey }) {
  if (!smtpLogin || !smtpKey) {
    throw new Error('Brevo SMTP credentials are not configured.');
  }
  if (!cachedTransport || cachedTransportLogin !== smtpLogin) {
    cachedTransport = nodemailer.createTransport({
      host: BREVO_SMTP_HOST,
      port: BREVO_SMTP_PORT,
      secure: false,
      requireTLS: true,
      pool: true,
      maxConnections: 3,
      maxMessages: 100,
      auth: {
        user: smtpLogin,
        pass: smtpKey,
      },
      tls: {
        minVersion: 'TLSv1.2',
      },
    });
    cachedTransportLogin = smtpLogin;
  }
  return cachedTransport;
}

async function sendBrevoEmail({
  smtpLogin,
  smtpKey,
  senderEmail,
  senderName,
  to,
  name,
  subject,
  htmlContent,
  textContent,
}) {
  if (!validEmail(senderEmail) || !validEmail(to)) {
    throw new Error('A valid sender and recipient email are required.');
  }
  const transport = brevoTransport({ smtpLogin, smtpKey });
  const response = await transport.sendMail({
    from: {
      name: senderName || 'VolTrike',
      address: senderEmail.trim(),
    },
    to: {
      name: name || undefined,
      address: to.trim(),
    },
    replyTo: senderEmail.trim(),
    subject,
    text: textContent,
    html: htmlContent,
  });
  return {
    messageId: response.messageId,
    accepted: response.accepted,
    rejected: response.rejected,
  };
}

module.exports = {
  emailShell,
  passwordResetEmail,
  plainTextEmail,
  safetyAlertEmail,
  sendBrevoEmail,
  todaApplicationEmail,
  validEmail,
  verificationEmail,
};
