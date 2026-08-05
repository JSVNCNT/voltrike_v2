'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');
const { defineSecret } = require('firebase-functions/params');
const { sendBrevoEmail, validEmail } = require('./brevo-communications');

const brevoSmtpLogin = defineSecret('BREVO_SMTP_LOGIN');
const brevoSmtpKey = defineSecret('BREVO_SMTP_KEY');
const brevoSenderEmail = defineSecret('BREVO_SENDER_EMAIL');

const BOOKING_MESSAGES = {
  driverAssigned: ['Driver assigned', 'Your driver accepted the booking.'],
  driverArriving: ['Driver arrived', 'Your driver has arrived at pickup.'],
  passengerOnBoard: ['Trip started', 'You are on the way to your destination.'],
  paymentConfirmation: ['Payment confirmation', 'Waiting for the driver to confirm cash received.'],
  completed: ['Trip completed', 'Your receipt is ready.'],
  cancelled: ['Booking cancelled', 'Your booking was cancelled.'],
};

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
  }, { merge: true });
}

async function processBookingEvent(eventId, event) {
  const bookingId = typeof event.aggregateId === 'string' ? event.aggregateId : '';
  if (!bookingId) return { skipped: true, reason: 'missing-aggregate' };
  const booking = await firestore().collection('bookings').doc(bookingId).get();
  if (!booking.exists) return { skipped: true, reason: 'booking-not-found' };
  const data = booking.data() || {};
  const status = typeof data.status === 'string' ? data.status : '';
  const message = BOOKING_MESSAGES[status];
  if (!message) return { skipped: true, reason: 'status-not-notifiable' };
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

async function sendToScopedAdmins(title, body, data, todaId = '') {
  const roles = await firestore().collection('users')
    .where('role', 'in', ['developer_admin', 'toda_admin'])
    .where('isActive', '==', true)
    .limit(100)
    .get();
  const recipients = roles.docs.filter((entry) => {
    const profile = entry.data();
    return profile.role === 'developer_admin' || !todaId || profile.todaId === todaId;
  });
  const deliveries = await Promise.all(recipients.map((entry) =>
    sendToUser(entry.id, title, body, data)));
  return deliveries.reduce((summary, delivery) => ({
    attempted: summary.attempted + delivery.attempted,
    succeeded: summary.succeeded + delivery.succeeded,
  }), { attempted: 0, succeeded: 0 });
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
    const title = type === 'safety.escalated' ? 'Unacknowledged VolTrike SOS' : 'VolTrike safety alert';
    const body = `Safety incident for booking ${data.bookingId || 'unknown'} requires review.`;
    return sendToScopedAdmins(title, body, {
      type: 'safety_incident', incidentId: event.aggregateId,
      bookingId: data.bookingId || '', escalationLevel: data.escalationLevel || 0,
    }, data.todaId || '');
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
  BOOKING_MESSAGES,
  processBookingEvent,
  processDomainEvent,
  processGoOutbox,
};
