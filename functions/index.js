const { onDocumentCreated, onDocumentUpdated } = require('firebase-functions/v2/firestore');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { logger } = require('firebase-functions');
const { defineSecret, defineString } = require('firebase-functions/params');
const admin = require('firebase-admin');
const { AccessToken, RoomServiceClient } = require('livekit-server-sdk');

admin.initializeApp();
const db = admin.firestore();
const liveKitApiKey = defineSecret('LIVEKIT_API_KEY');
const liveKitApiSecret = defineSecret('LIVEKIT_API_SECRET');
const liveKitUrl = defineString('LIVEKIT_URL');

async function sendToUser(userId, title, body, data) {
  const devices = await db.collection('users').doc(userId).collection('devices').get();
  const deviceTokens = devices.docs
    .map((doc) => ({ doc, token: doc.data().token }))
    .filter((entry) => typeof entry.token === 'string' && entry.token.length > 0);
  const tokens = deviceTokens.map((entry) => entry.token);
  if (tokens.length === 0) return;
  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    android: { priority: 'high' },
  });
  await Promise.all(response.responses.map((result, index) => {
    if (!result.success && ['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(result.error?.code)) {
      return deviceTokens[index].doc.ref.delete();
    }
    return null;
  }));
}

// The Firebase-authenticated caller receives a short-lived LiveKit token only
// when they are the passenger or assigned driver for an active booking.
exports.createBookingCallToken = onCall(
  {
    region: 'asia-southeast1',
    secrets: [liveKitApiKey, liveKitApiSecret],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before starting a call.');
    }
    const bookingId = request.data?.bookingId;
    if (typeof bookingId !== 'string' || bookingId.length === 0) {
      throw new HttpsError('invalid-argument', 'A booking ID is required.');
    }
    const bookingSnapshot = await db.collection('bookings').doc(bookingId).get();
    if (!bookingSnapshot.exists) {
      throw new HttpsError('not-found', 'Booking not found.');
    }
    const booking = bookingSnapshot.data();
    const activeStatuses = ['driverAssigned', 'driverArriving', 'passengerOnBoard'];
    if (!activeStatuses.includes(booking.status)) {
      throw new HttpsError('failed-precondition', 'Voice calls are only available during an active ride.');
    }
    if (![booking.passengerId, booking.driverId].includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this booking.');
    }
    const url = liveKitUrl.value();
    if (!url) {
      throw new HttpsError('failed-precondition', 'Voice calling is not configured.');
    }
    const roomName = `booking_${bookingId}`;
    const token = new AccessToken(liveKitApiKey.value(), liveKitApiSecret.value(), {
      identity: request.auth.uid,
      ttl: '2m',
    });
    token.addGrant({ roomJoin: true, room: roomName, canPublish: true, canSubscribe: true });
    return { serverUrl: url, token: await token.toJwt(), roomName };
  },
);

// Either participant can deliberately end an active booking call. Deleting the
// room disconnects both sides, and is also invoked by the two-minute UI timer.
exports.endBookingCall = onCall(
  {
    region: 'asia-southeast1',
    secrets: [liveKitApiKey, liveKitApiSecret],
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in before ending a call.');
    }
    const bookingId = request.data?.bookingId;
    if (typeof bookingId !== 'string' || bookingId.length === 0) {
      throw new HttpsError('invalid-argument', 'A booking ID is required.');
    }
    const bookingSnapshot = await db.collection('bookings').doc(bookingId).get();
    const booking = bookingSnapshot.data();
    if (!bookingSnapshot.exists || !booking ||
        ![booking.passengerId, booking.driverId].includes(request.auth.uid)) {
      throw new HttpsError('permission-denied', 'You are not part of this booking.');
    }
    const url = liveKitUrl.value();
    if (!url) {
      throw new HttpsError('failed-precondition', 'Voice calling is not configured.');
    }
    const roomName = `booking_${bookingId}`;
    const serviceUrl = url.replace(/^wss:/, 'https:').replace(/^ws:/, 'http:');
    const rooms = new RoomServiceClient(
      serviceUrl,
      liveKitApiKey.value(),
      liveKitApiSecret.value(),
    );
    try {
      await rooms.deleteRoom(roomName);
    } catch (error) {
      // A room may already be empty/deleted; ending a call remains idempotent.
      logger.info('LiveKit room already absent while ending call', {
        bookingId,
        error: String(error),
      });
    }
    return { ended: true };
  },
);

// Drivers receive only their own offer documents. Geo-ranking from RTDB is a
// later enhancement; this bounded dispatcher is intentionally server-owned.
exports.dispatchBookingOffers = onDocumentCreated('bookings/{bookingId}', async (event) => {
  const booking = event.data.data();
  if (!booking || booking.status !== 'pending') return;

  const drivers = await db.collection('drivers')
    .where('driverStatus', '==', 'approved')
    .where('isOnline', '==', true)
    .where('isAvailable', '==', true)
    .limit(10)
    .get();
  const expiresAt = admin.firestore.Timestamp.fromMillis(Date.now() + 30000);
  const batch = db.batch();
  drivers.docs.forEach((driver) => {
    batch.set(db.doc(`drivers/${driver.id}/bookingOffers/${event.params.bookingId}`), {
      bookingId: event.params.bookingId,
      status: 'offered',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
    });
  });
  await batch.commit();
  await Promise.all(drivers.docs.map((driver) => sendToUser(
    driver.id,
    'New VolTrike booking',
    'A nearby passenger is requesting a ride.',
    { bookingId: event.params.bookingId, target: 'driver', type: 'booking_offer' },
  )));
  logger.info('Booking offers dispatched', { bookingId: event.params.bookingId, count: drivers.size });
});

exports.notifyBookingLifecycle = onDocumentUpdated('bookings/{bookingId}', async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (before.status === after.status) return;
  const bookingId = event.params.bookingId;
  const passenger = after.passengerId;
  const driver = after.driverId;
  const passengerMessages = {
    driverAssigned: ['Driver assigned', 'Your driver accepted the booking.'],
    driverArriving: ['Driver arriving', 'Your driver has arrived at pickup.'],
    passengerOnBoard: ['Trip started', 'You are on the way to your destination.'],
    completed: ['Trip completed', 'Your receipt is ready.'],
    cancelled: ['Booking cancelled', 'Your booking was cancelled.'],
  };
  const driverMessages = {
    passengerOnBoard: ['Trip started', 'Navigate to the destination.'],
    cancelled: ['Trip cancelled', 'The passenger cancelled the trip.'],
  };
  const passengerMessage = passengerMessages[after.status];
  const driverMessage = driverMessages[after.status];
  const tasks = [];
  if (passenger && passengerMessage) tasks.push(sendToUser(passenger, passengerMessage[0], passengerMessage[1], { bookingId, target: 'passenger', type: after.status }));
  if (driver && driverMessage) tasks.push(sendToUser(driver, driverMessage[0], driverMessage[1], { bookingId, target: 'driver', type: after.status }));
  await Promise.all(tasks);
});
