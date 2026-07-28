'use strict';

const BREVO_EMAIL_ENDPOINT = 'https://api.brevo.com/v3/smtp/email';

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

function emailShell({
  eyebrow,
  title,
  greeting,
  paragraphs,
  facts = [],
  actionLabel,
  actionUrl,
  footer,
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
  return `<!doctype html>
  <html lang="en">
  <head><meta charset="utf-8"><meta name="viewport" content="width=device-width"></head>
  <body style="margin:0;background:#f3f7f7;font-family:Arial,Helvetica,sans-serif;color:#173b3b">
    <div style="display:none;max-height:0;overflow:hidden">${escapeHtml(title)}</div>
    <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f3f7f7">
      <tr><td align="center" style="padding:28px 12px">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:620px;background:#fff;border:1px solid #d8e5e5;border-radius:18px;overflow:hidden">
          <tr><td style="background:#064c4d;padding:24px 30px;color:#fff">
            <div style="font-size:25px;font-weight:800;letter-spacing:.3px">VolTrike</div>
            <div style="margin-top:4px;color:#cbe5e5;font-size:13px">Clean Community Mobility</div>
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

function verificationEmail({ name, verificationLink }) {
  return {
    subject: 'Verify your VolTrike email address',
    htmlContent: emailShell({
      eyebrow: 'Account verification',
      title: 'Confirm your email address',
      greeting: `Hello ${name || 'VolTrike user'},`,
      paragraphs: [
        'Confirm that this email address belongs to you before using your VolTrike account.',
        'This secure Firebase verification link expires automatically. If you did not create this account, you can ignore this message.',
      ],
      actionLabel: 'Verify email address',
      actionUrl: verificationLink,
      footer: 'This is a required transactional account email, not a promotional message. VolTrike will never ask for your password by email.',
    }),
    tags: ['account-verification'],
  };
}

function safetyAlertEmail({
  recipientName,
  eventLabel,
  incident,
  adminPortalUrl,
}) {
  const level = Number(incident.escalationLevel || 0);
  return {
    subject: `${level > 0 ? 'Escalated ' : ''}VolTrike SOS · ${incident.bookingId}`,
    htmlContent: emailShell({
      eyebrow: level > 0 ? `Safety escalation level ${level}` : 'New safety incident',
      title: eventLabel,
      greeting: `Hello ${recipientName || 'administrator'},`,
      paragraphs: [
        'A VolTrike ride safety incident requires administrator acknowledgement. Check the map, attempt contact, and call 911 when there is immediate danger.',
        'Cancelling the booking is an operational safeguard and does not resolve the emergency record.',
      ],
      facts: [
        { label: 'Booking', value: incident.bookingId },
        { label: 'Reported by', value: incident.reporterRole },
        { label: 'TODA', value: incident.todaName || incident.todaId || 'Unassigned' },
        { label: 'Ride status', value: incident.bookingStatus || 'Unknown' },
        { label: 'Pickup', value: incident.pickupAddress || 'Unavailable' },
        { label: 'Destination', value: incident.destinationAddress || 'Unavailable' },
      ],
      actionLabel: 'Open Safety Incidents',
      actionUrl: adminPortalUrl,
      footer: 'You are receiving this transactional safety email because your active administrator account is responsible for this incident. Notification preferences can be edited on the Safety Incidents page.',
    }),
    tags: ['safety-incident', `escalation-${level}`],
  };
}

function todaApplicationEmail({
  administratorName,
  todaName,
  status,
  adminPortalUrl,
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
  return {
    subject: `VolTrike TODA application · ${copy.title}`,
    htmlContent: emailShell({
      eyebrow: copy.eyebrow,
      title: copy.title,
      greeting: `Hello ${administratorName || 'administrator'},`,
      paragraphs: [copy.paragraph],
      facts: [{ label: 'TODA', value: todaName }],
      actionLabel: 'Open VolTrike Admin',
      actionUrl: adminPortalUrl,
      footer: 'This is a transactional registration message related to your VolTrike administrator application.',
    }),
    tags: ['toda-registration', status],
  };
}

async function brevoRequest({ apiKey, endpoint, body }) {
  if (!apiKey) throw new Error('BREVO_API_KEY is not configured.');
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      accept: 'application/json',
      'api-key': apiKey,
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(
      `Brevo request failed with HTTP ${response.status}.`,
    );
    error.status = response.status;
    error.payload = payload;
    throw error;
  }
  return payload;
}

function sendBrevoEmail({
  apiKey,
  senderEmail,
  senderName,
  to,
  name,
  subject,
  htmlContent,
  tags = [],
}) {
  if (!validEmail(senderEmail) || !validEmail(to)) {
    throw new Error('A valid sender and recipient email are required.');
  }
  return brevoRequest({
    apiKey,
    endpoint: BREVO_EMAIL_ENDPOINT,
    body: {
      sender: { email: senderEmail.trim(), name: senderName || 'VolTrike' },
      to: [{ email: to.trim(), name: name || undefined }],
      subject,
      htmlContent,
      tags,
    },
  });
}

module.exports = {
  emailShell,
  safetyAlertEmail,
  sendBrevoEmail,
  todaApplicationEmail,
  validEmail,
  verificationEmail,
};
