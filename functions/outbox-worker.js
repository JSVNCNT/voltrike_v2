'use strict';

const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

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

const processGoOutbox = onDocumentCreated('outbox/{eventId}', async (event) => {
  const eventId = event.params.eventId;
  const claimed = await claim(eventId);
  if (!claimed) return;
  try {
    const result = String(claimed.type || '').startsWith('booking.')
      ? await processBookingEvent(eventId, claimed)
      : { skipped: true, reason: 'unsupported-event' };
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
  processGoOutbox,
};
