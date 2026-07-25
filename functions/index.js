const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { logger } = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

// Drivers receive only their own offer documents. Geo-ranking from RTDB is a
// later enhancement; this bounded dispatcher is intentionally server-owned.
exports.dispatchBookingOffers = onDocumentCreated('bookings/{bookingId}', async (event) => {
  const booking = event.data.data();
  if (!booking || booking.status !== 'pending') return;

  const drivers = await db.collection('drivers')
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
  logger.info('Booking offers dispatched', { bookingId: event.params.bookingId, count: drivers.size });
});
