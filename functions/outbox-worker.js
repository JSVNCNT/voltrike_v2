'use strict';

const { createHash } = require('node:crypto');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const { defineSecret, defineString } = require('firebase-functions/params');
const {
  safetyAlertEmail,
  sendBrevoEmail,
  validEmail,
} = require('./brevo-communications');

const brevoSmtpLogin = defineSecret('BREVO_SMTP_LOGIN');
const brevoSmtpKey = defineSecret('BREVO_SMTP_KEY');
const brevoSenderEmail = defineSecret('BREVO_SENDER_EMAIL');
const adminPortalUrl = defineString('ADMIN_PORTAL_URL', {
  default: 'https://voltrike-v2.web.app',
});
const emailLogoUrl = defineString('EMAIL_LOGO_URL', {
  default: 'https://voltrike-v2.web.app/images/appLogo.png',
});

const BOOKING_MESSAGES = {
  driverAssigned: ['Driver assigned', 'Your driver accepted the booking.'],
  driverArriving: ['Driver arrived', 'Your driver has arrived at pickup.'],
  passengerOnBoard: ['Trip started', 'You are on the way to your destination.'],
  paymentConfirmation: ['Payment confirmation', 'Waiting for the driver to confirm cash received.'],
  completed: ['Trip completed', 'Your receipt is ready.'],
  cancelled: ['Booking cancelled', 'Your booking was cancelled.'],
};

const LIVE_NOTIFICATION_MAX_AGE_MS = 15 * 60 * 1000;
const CALL_NOTIFICATION_MAX_AGE_MS = 2 * 60 * 1000;
const ADMIN_NOTIFICATION_MAX_AGE_MS = 60 * 60 * 1000;

function timestampMillis(value) {
  if (typeof value?.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'string') {
    const parsed = Date.parse(value);
    return Number.isNaN(parsed) ? null : parsed;
  }
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return null;
}

function notificationMaxAgeMs(type) {
  if (type === 'call.ringing') return CALL_NOTIFICATION_MAX_AGE_MS;
  if (type.startsWith('booking.') || type === 'chat.message.created') {
    return LIVE_NOTIFICATION_MAX_AGE_MS;
  }
  if (type === 'safety.sos.safe' || type === 'safety.sos.emergency_call_attempted') {
    return LIVE_NOTIFICATION_MAX_AGE_MS;
  }
  if (type === 'report.created' || type.startsWith('violation.')) {
    return ADMIN_NOTIFICATION_MAX_AGE_MS;
  }
  return null;
}

function staleNotificationReason(event, now = Date.now()) {
  const type = String(event?.type || '');
  const maximumAge = notificationMaxAgeMs(type);
  if (maximumAge == null) return null;
  const createdAt = timestampMillis(event?.createdAt);
  if (createdAt == null || createdAt > now) return null;
  return now - createdAt > maximumAge ? 'stale-notification-event' : null;
}

function bookingNotificationStatus(event) {
  const payloadStatus = String(event?.payload?.status || '');
  if (BOOKING_MESSAGES[payloadStatus]) return payloadStatus;
  const eventStatus = String(event?.type || '').replace(/^booking\./, '');
  return BOOKING_MESSAGES[eventStatus] ? eventStatus : '';
}

function actionableSafetyEvent(type, incident) {
  if (!incident || typeof incident !== 'object') return false;
  if (type === 'safety.sos.safe') {
    return incident.responseStatus === 'resolved';
  }
  return incident.status === 'open' &&
    (!incident.responseStatus || incident.responseStatus === 'reported');
}

function firestore() {
  return admin.firestore();
}

async function sendToUser(userId, title, body, data) {
  const devices = await firestore().collection('users').doc(userId).collection('devices').get();
  const entries = devices.docs
    .map((device) => ({ device, token: device.data().token }))
    .filter((entry) => typeof entry.token === 'string' && entry.token.length > 0);
  if (entries.length === 0) return { attempted: 0, succeeded: 0 };
  const response = await admin.messaging().sendEachForMulticast({
    tokens: entries.map((entry) => entry.token),
    notification: { title, body },
    data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    android: {
      priority: 'high',
      notification: { channelId: 'booking_updates', sound: 'booking_ringtone' },
    },
  });
  await Promise.all(response.responses.map((result, index) => {
    const code = result.error?.code;
    if (!result.success && ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code)) {
      return entries[index].device.ref.delete();
    }
    return null;
  }));
  return { attempted: entries.length, succeeded: response.successCount };
}

async function claim(eventId) {
  const ref = firestore().collection('outbox').doc(eventId);
  return firestore().runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    if (!snapshot.exists) return null;
    const data = snapshot.data() || {};
    const status = data.consumerStatus?.notifications;
    const startedAt = data.consumerStatus?.notificationsStartedAt;
    const startedMillis = typeof startedAt?.toMillis === 'function'
      ? startedAt.toMillis()
      : Number(startedAt || 0);
    const processingLeaseActive = status === 'processing' &&
      Number.isFinite(startedMillis) &&
      startedMillis > Date.now() - 5 * 60 * 1000;
    if (status === 'completed' || processingLeaseActive) return null;
    transaction.update(ref, {
      'consumerStatus.notifications': 'processing',
      'consumerStatus.notificationsStartedAt': admin.firestore.FieldValue.serverTimestamp(),
    });
    return data;
  });
}

async function complete(eventId, status, details = {}) {
  await firestore().collection('outbox').doc(eventId).set({
    consumerStatus: {
      notifications: status,
      notificationsFinishedAt: admin.firestore.FieldValue.serverTimestamp(),
      notificationsDetails: details,
    },
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 86_400_000),
  }, { merge: true });
}

async function processBookingEvent(eventId, event) {
  const bookingId = typeof event.aggregateId === 'string' ? event.aggregateId : '';
  if (!bookingId) return { skipped: true, reason: 'missing-aggregate' };
  const booking = await firestore().collection('bookings').doc(bookingId).get();
  if (!booking.exists) return { skipped: true, reason: 'booking-not-found' };
  const data = booking.data() || {};
  const status = bookingNotificationStatus(event);
  const message = BOOKING_MESSAGES[status];
  if (!message) return { skipped: true, reason: 'event-transition-not-notifiable' };
  const tasks = [];
  if (typeof data.passengerId === 'string') {
    tasks.push(sendToUser(data.passengerId, message[0], message[1], {
      bookingId,
      target: 'passenger',
      type: status,
    }));
  }
  if (typeof data.driverId === 'string') {
    tasks.push(sendToUser(data.driverId, message[0], message[1], {
      bookingId,
      target: 'driver',
      type: status,
    }));
  }
  const deliveries = await Promise.all(tasks);
  return {
    attempted: deliveries.reduce((total, item) => total + item.attempted, 0),
    succeeded: deliveries.reduce((total, item) => total + item.succeeded, 0),
  };
}

async function scopedAdmins(todaId = '') {
  const roles = await firestore().collection('users')
    .where('role', 'in', ['developer_admin', 'toda_admin'])
    .where('isActive', '==', true)
    .limit(100)
    .get();
  return roles.docs.filter((entry) => {
    const profile = entry.data();
    return profile.role === 'developer_admin' || !todaId || profile.todaId === todaId;
  });
}

async function sendToScopedAdmins(title, body, data, todaId = '', entries) {
  const recipients = entries || await scopedAdmins(todaId);
  const deliveries = await Promise.all(recipients.map((entry) =>
    sendToUser(entry.id, title, body, data)));
  return deliveries.reduce((summary, delivery) => ({
    attempted: summary.attempted + delivery.attempted,
    succeeded: summary.succeeded + delivery.succeeded,
  }), { attempted: 0, succeeded: 0 });
}

function safetyEmailDeliveryId(eventId, recipientId) {
  return createHash('sha256')
    .update(`${eventId}:${recipientId}:email`)
    .digest('hex');
}

async function administratorEmail(entry) {
  const profile = entry.data() || {};
  const preferred = String(profile.safetyContactEmail || profile.email || '').trim();
  if (validEmail(preferred)) return preferred;
  const user = await admin.auth().getUser(entry.id).catch(() => null);
  return validEmail(user?.email) ? user.email.trim() : '';
}

async function sendSafetyEmailOnce({ eventId, incidentId, entry, message }) {
  const email = await administratorEmail(entry);
  const profile = entry.data() || {};
  if (profile.safetyEmailEnabled === false || !email) {
    return { skipped: true, reason: 'email-disabled-or-missing' };
  }
  const deliveryId = safetyEmailDeliveryId(eventId, entry.id);
  const delivery = firestore().collection('communicationDeliveries').doc(deliveryId);
  const claimed = await firestore().runTransaction(async (transaction) => {
    const existing = await transaction.get(delivery);
    if (existing.exists) return false;
    transaction.create(delivery, {
      recipientId: entry.id,
      incidentId,
      outboxEventId: eventId,
      purpose: 'administrator_safety_alert',
      channel: 'email',
      provider: 'brevo',
      status: 'sending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 86_400_000),
    });
    return true;
  });
  if (!claimed) return { skipped: true, reason: 'already-claimed' };
  try {
    const name = [profile.firstName, profile.lastName].filter(Boolean).join(' ') ||
      profile.displayName || 'Administrator';
    const result = await sendBrevoEmail({
      smtpLogin: brevoSmtpLogin.value(),
      smtpKey: brevoSmtpKey.value(),
      senderEmail: brevoSenderEmail.value(),
      senderName: 'VolTrike',
      to: email,
      name,
      ...message,
    });
    await delivery.update({
      status: 'accepted',
      providerMessageId: String(result.messageId || ''),
      acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { sent: true };
  } catch (error) {
    await delivery.update({
      status: 'failed',
      errorCode: String(error?.code || 'provider_error'),
      failedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    throw error;
  }
}

async function sendTransactionalEmail(uid, title, body) {
  if (!brevoSmtpLogin.value() || !brevoSmtpKey.value() || !brevoSenderEmail.value()) {
    return { skipped: true, reason: 'email-not-configured' };
  }
  const user = await admin.auth().getUser(uid).catch(() => null);
  if (!user?.email || !validEmail(user.email)) return { skipped: true, reason: 'no-email' };
  const result = await sendBrevoEmail({
    smtpLogin: brevoSmtpLogin.value(), smtpKey: brevoSmtpKey.value(),
    senderEmail: brevoSenderEmail.value(), senderName: 'VolTrike',
    to: user.email, name: user.displayName || 'VolTrike user', subject: title,
    textContent: body,
    htmlContent: `<p>${String(body).replaceAll('&', '&amp;').replaceAll('<', '&lt;')}</p>`,
  });
  return { sent: true, providerMessageId: String(result.messageId || '') };
}

async function processDomainEvent(eventId, event) {
  const type = String(event.type || '');
  const payload = event.payload || {};
  const staleReason = staleNotificationReason(event);
  if (staleReason) return { skipped: true, reason: staleReason };
  if (type.startsWith('booking.')) return processBookingEvent(eventId, event);
  if (type === 'call.ringing' && payload.recipientId) {
    return sendToUser(payload.recipientId, 'Incoming VolTrike call', 'Your ride participant is calling.', {
      bookingId: payload.bookingId, callId: payload.callId, type: 'incoming_call',
    });
  }
  if (type === 'chat.message.created') {
    const booking = await firestore().collection('bookings').doc(payload.bookingId).get();
    const message = await firestore().collection('chat').doc(payload.bookingId)
      .collection('messages').doc(payload.messageId).get();
    if (!booking.exists || !message.exists) return { skipped: true, reason: 'projection-not-found' };
    const bookingData = booking.data() || {};
    const recipientId = bookingData.passengerId === payload.senderId
      ? bookingData.driverId : bookingData.passengerId;
    return sendToUser(recipientId, 'New ride message', String(message.data()?.text || '').slice(0, 120), {
      bookingId: payload.bookingId, type: 'chat_message',
    });
  }
  if (type.startsWith('safety.')) {
    const incident = await firestore().collection('safetyIncidents').doc(event.aggregateId).get();
    const data = incident.data() || payload;
    if (!actionableSafetyEvent(type, data)) {
      return { skipped: true, reason: 'safety-incident-not-actionable' };
    }
    const title = type === 'safety.escalated' ? 'Unacknowledged VolTrike SOS' : 'VolTrike safety alert';
    const body = `Safety incident for booking ${data.bookingId || 'unknown'} requires review.`;
    const recipients = await scopedAdmins(data.todaId || '');
    const push = await sendToScopedAdmins(title, body, {
      type: 'safety_incident', incidentId: event.aggregateId,
      bookingId: data.bookingId || '', escalationLevel: data.escalationLevel || 0,
    }, data.todaId || '', recipients);
    const emailResults = await Promise.all(recipients.map(async (entry) => {
      const profile = entry.data() || {};
      const recipientName = [profile.firstName, profile.lastName]
        .filter(Boolean).join(' ') || profile.displayName || 'Administrator';
      const message = safetyAlertEmail({
        recipientName,
        eventLabel: title,
        adminPortalUrl: adminPortalUrl.value(),
        logoUrl: emailLogoUrl.value(),
        incident: {
          ...data,
          bookingId: data.bookingId || 'unknown',
          escalationLevel: data.escalationLevel || 0,
        },
      });
      return sendSafetyEmailOnce({
        eventId,
        incidentId: event.aggregateId,
        entry,
        message,
      });
    }));
    return {
      ...push,
      emailSent: emailResults.filter((result) => result.sent).length,
      emailSkipped: emailResults.filter((result) => result.skipped).length,
    };
  }
  if (type === 'report.created') {
    const report = await firestore().collection('reports').doc(event.aggregateId).get();
    const data = report.data() || payload;
    return sendToScopedAdmins('New ride report', 'A ride report requires administrator review.', {
      type: 'ride_report', reportId: event.aggregateId, bookingId: data.bookingId || '',
    }, data.todaId || '');
  }
  if (type.startsWith('violation.')) {
    const violationId = payload.violationId || event.aggregateId;
    const violation = await firestore().collection('driverViolations').doc(violationId).get();
    const data = violation.data() || payload;
    if (type === 'violation.created' && data.driverId) {
      await sendTransactionalEmail(data.driverId, 'VolTrike route safety case', 'A route restriction case was recorded. Open the driver app for details.');
    }
    return sendToScopedAdmins('Route restriction case', 'A driver restriction case has new activity.', {
      type: 'driver_violation', violationId,
    }, data.ownerTodaId || data.todaId || '');
  }
  return { skipped: true, reason: 'non-notifiable-event' };
}

const processGoOutbox = onDocumentCreated({
  document: 'outbox/{eventId}',
  secrets: [brevoSmtpLogin, brevoSmtpKey, brevoSenderEmail],
}, async (event) => {
  const eventId = event.params.eventId;
  const claimed = await claim(eventId);
  if (!claimed) return;
  try {
    const result = await processDomainEvent(eventId, claimed);
    await complete(eventId, 'completed', result);
  } catch (error) {
    await complete(eventId, 'failed', { message: error?.message || String(error) });
    logger.error('Go outbox notification failed', { eventId, error });
    throw error;
  }
});

module.exports = {
  actionableSafetyEvent,
  BOOKING_MESSAGES,
  bookingNotificationStatus,
  processBookingEvent,
  processDomainEvent,
  processGoOutbox,
  safetyEmailDeliveryId,
  staleNotificationReason,
};
