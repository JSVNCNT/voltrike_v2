'use strict';

const assert = require('node:assert/strict');
const {
  db,
  projectId,
  realtime,
} = require('./emulator-admin');

const authBase = 'http://127.0.0.1:9099';
const functionsBase =
  `http://127.0.0.1:5001/${projectId}/asia-southeast1`;
const firestoreBase =
  `http://127.0.0.1:8080/v1/projects/${projectId}` +
  '/databases/(default)/documents';
const realtimeBase =
  'http://127.0.0.1:9000';
const realtimeNamespace = `${projectId}-default-rtdb`;
const password = 'VolTrike123!';

async function signIn(email) {
  const response = await fetch(
    `${authBase}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword` +
      '?key=demo-voltrike-api-key',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email,
        password,
        returnSecureToken: true,
      }),
    },
  );
  const payload = await response.json();
  if (!response.ok || !payload.idToken) {
    throw new Error(`Emulator sign-in failed for ${email}: ${JSON.stringify(payload)}`);
  }
  return payload.idToken;
}

async function callable(name, token, data, { expectError } = {}) {
  const response = await fetch(`${functionsBase}/${name}`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ data }),
  });
  const payload = await response.json();
  if (payload.error) {
    if (expectError) {
      assert.equal(
        payload.error.status,
        expectError,
        `${name} returned ${JSON.stringify(payload.error)}`,
      );
      return payload.error;
    }
    throw new Error(`${name} failed: ${JSON.stringify(payload.error)}`);
  }
  if (expectError) {
    throw new Error(`${name} unexpectedly succeeded.`);
  }
  return payload.result ?? payload.data;
}

async function expectHttpStatus(
  description,
  url,
  token,
  expectedStatuses,
  options = {},
) {
  const response = await fetch(url, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(options.headers || {}),
    },
  });
  assert.ok(
    expectedStatuses.includes(response.status),
    `${description}: expected ${expectedStatuses.join('/')} but received ` +
      `${response.status}: ${await response.text()}`,
  );
  return response;
}

function firestoreDocument(path) {
  return `${firestoreBase}/${path}`;
}

function realtimeDocument(path, token) {
  return `${realtimeBase}/${path}.json?ns=${realtimeNamespace}` +
    `&auth=${encodeURIComponent(token)}`;
}

async function waitFor(getValue, description, timeoutMs = 15000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const value = await getValue();
    if (value) return value;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error(`Timed out waiting for ${description}.`);
}

async function setFreshDriverLocation(driverId, latitude, longitude) {
  await realtime.ref(`driver_locations/${driverId}`).set({
    latitude,
    longitude,
    accuracy: 5,
    timestamp: Date.now(),
    online: true,
  });
}

function operation(prefix, index) {
  return `${prefix}-${String(index).padStart(3, '0')}`;
}

async function main() {
  const [
    passengerToken,
    driverToken,
    secondDriverToken,
    developerToken,
    todaAdminToken,
  ] = await Promise.all([
    signIn('passenger@voltrike.test'),
    signIn('driver@voltrike.test'),
    signIn('driver2@voltrike.test'),
    signIn('developer@voltrike.test'),
    signIn('toda.admin@voltrike.test'),
  ]);

  await Promise.all([
    callable('setDriverOnlineStatus', driverToken, { isOnline: true }),
    callable('setDriverOnlineStatus', secondDriverToken, { isOnline: true }),
  ]);
  await Promise.all([
    setFreshDriverLocation('driver-test-001', 10.6765, 122.9509),
    setFreshDriverLocation('driver-test-002', 10.6770, 122.9512),
  ]);

  const bookingId = 'booking-test-main-001';
  const created = await callable('createBookingLifecycle', passengerToken, {
    bookingId,
    operationId: operation('create-main', 1),
    pickup: { latitude: 10.6762, longitude: 122.9506 },
    destination: { latitude: 10.6848, longitude: 122.9560 },
    pickupAddress: 'Bacolod Test Pickup',
    destinationAddress: 'Bacolod Test Destination',
    additionalPassengers: 0,
    baggageCount: 0,
    isOutsideToda: false,
    distanceMeters: 1,
    estimatedFare: 1,
  });
  assert.match(created.pickupPin, /^\d{4}$/);
  assert.ok(created.distanceMeters > 1);
  assert.ok(created.estimatedFare >= 20);

  const offer = await waitFor(
    async () => {
      const snapshot = await db.doc(
        `drivers/driver-test-001/bookingOffers/${bookingId}`,
      ).get();
      return snapshot.exists && snapshot.data().status === 'offered'
        ? snapshot.data()
        : null;
    },
    'distance-ranked driver offer',
  );
  assert.ok(offer.distanceMeters <= 5000);
  await expectHttpStatus(
    'offered driver may read the pending booking',
    firestoreDocument(`bookings/${bookingId}`),
    secondDriverToken,
    [200],
  );
  await expectHttpStatus(
    'passenger cannot directly change booking lifecycle state',
    `${firestoreDocument(`bookings/${bookingId}`)}` +
      '?updateMask.fieldPaths=status',
    passengerToken,
    [403],
    {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        fields: { status: { stringValue: 'completed' } },
      }),
    },
  );

  const accepted = await callable(
    'acceptBookingLifecycle',
    driverToken,
    {
      bookingId,
      operationId: operation('accept-main', 1),
    },
  );
  assert.equal(accepted.status, 'driverAssigned');

  let booking = (await db.doc(`bookings/${bookingId}`).get()).data();
  assert.equal(booking.driverId, 'driver-test-001');
  assert.equal(booking.status, 'driverAssigned');
  assert.equal(booking.clientEstimate.estimatedFare, 1);
  assert.notEqual(booking.estimatedFare, 1);
  assert.equal(
    (await realtime.ref(
      'driver_tracking_access/passenger-test-001/driver-test-001',
    ).get()).val().bookingId,
    bookingId,
  );
  await expectHttpStatus(
    'expired competing offer no longer grants booking access',
    firestoreDocument(`bookings/${bookingId}`),
    secondDriverToken,
    [403],
  );
  await expectHttpStatus(
    'assigned passenger may read driver tracking location',
    realtimeDocument(
      'driver_locations/driver-test-001',
      passengerToken,
    ),
    passengerToken,
    [200],
  );
  await expectHttpStatus(
    'passenger cannot overwrite driver tracking location',
    realtimeDocument(
      'driver_locations/driver-test-001',
      passengerToken,
    ),
    passengerToken,
    [401, 403],
    {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        latitude: 10.6762,
        longitude: 122.9506,
        accuracy: 5,
        timestamp: Date.now(),
        online: true,
      }),
    },
  );

  await callable('transitionBookingLifecycle', driverToken, {
    bookingId,
    operationId: operation('arrive-main', 1),
    action: 'arrived',
  });
  await callable('createSafetyIncident', passengerToken, {
    bookingId,
    incidentId: 'incident-test-main-001',
  });
  const shared = await callable(
    'getShareTripInformation',
    passengerToken,
    { bookingId },
  );
  assert.equal(shared.driverName, 'Dario Driver');

  await callable('confirmBookingPickup', driverToken, {
    bookingId,
    operationId: operation('pickup-main', 1),
    pin: created.pickupPin,
  });
  await callable('transitionBookingLifecycle', driverToken, {
    bookingId,
    operationId: operation('start-main', 1),
    action: 'start',
  });
  await callable('confirmCashPayment', passengerToken, {
    bookingId,
    operationId: operation('paid-main', 1),
    confirmation: 'paid',
  });
  const settlement = await callable(
    'confirmCashPayment',
    driverToken,
    {
      bookingId,
      operationId: operation('received-main', 1),
      confirmation: 'received',
    },
  );
  assert.equal(settlement.settled, true);
  assert.match(settlement.receiptNumber, /^VT-/);

  await callable('transitionBookingLifecycle', driverToken, {
    bookingId,
    operationId: operation('complete-main', 1),
    action: 'complete',
  });
  await callable('submitDriverRating', passengerToken, {
    bookingId,
    rating: 5,
    comment: 'Local emulator lifecycle.',
  });
  await callable('createRideReport', passengerToken, {
    bookingId,
    reportId: 'report-test-main-001',
    category: 'test_follow_up',
    details: 'Local emulator verification report.',
  });

  booking = (await db.doc(`bookings/${bookingId}`).get()).data();
  assert.equal(booking.status, 'completed');
  assert.equal(booking.settlementStatus, 'settled');
  const driver = (await db.doc('drivers/driver-test-001').get()).data();
  assert.equal(driver.currentBookingId, null);
  assert.equal(driver.isAvailable, true);
  assert.ok(driver.completedTrips >= 25);
  assert.ok(driver.totalEarnings > 3200);
  assert.equal(
    (await realtime.ref(
      'driver_tracking_access/passenger-test-001/driver-test-001',
    ).get()).exists(),
    false,
  );
  await expectHttpStatus(
    'completed booking removes passenger tracking access',
    realtimeDocument(
      'driver_locations/driver-test-001',
      passengerToken,
    ),
    passengerToken,
    [401, 403],
  );

  const cancelledBookingId = 'booking-test-cancel-001';
  await callable('createBookingLifecycle', passengerToken, {
    bookingId: cancelledBookingId,
    operationId: operation('create-cancel', 1),
    pickup: { latitude: 10.6762, longitude: 122.9506 },
    destination: { latitude: 10.6800, longitude: 122.9530 },
    pickupAddress: 'Cancellation Pickup',
    destinationAddress: 'Cancellation Destination',
    additionalPassengers: 0,
    baggageCount: 0,
    isOutsideToda: false,
    distanceMeters: 1,
    estimatedFare: 1,
  });
  await callable('transitionBookingLifecycle', passengerToken, {
    bookingId: cancelledBookingId,
    operationId: operation('cancel-passenger', 1),
    action: 'cancel',
    reasonCode: 'changed_plans',
  });
  assert.equal(
    (await db.doc(`bookings/${cancelledBookingId}`).get()).data().status,
    'cancelled',
  );

  const developerBookings = await callable(
    'adminListBookings',
    developerToken,
    { pageSize: 20 },
  );
  assert.ok(
    developerBookings.items.some((item) => item.bookingId === bookingId),
  );
  const todaBookings = await callable(
    'adminListBookings',
    todaAdminToken,
    { pageSize: 20 },
  );
  assert.ok(
    todaBookings.items.every(
      (item) => item.todaId === 'test-toda-bacolod',
    ),
  );
  await callable(
    'adminUpdateFare',
    todaAdminToken,
    {
      fare: {
        baseFare: 21,
        includedMeters: 1000,
        distanceStepMeters: 500,
        distanceStepPrice: 5,
        additionalPassengerFee: 40,
        baggageFee: 20,
        outsideTodaSurcharge: 20,
      },
    },
    { expectError: 'PERMISSION_DENIED' },
  );

  console.log('Verified isolated VolTrike lifecycle:');
  console.log('- trusted booking/fare creation and 5 km dispatch');
  console.log('- driver acceptance, tracking grant, arrival, SOS, and sharing');
  console.log('- pickup PIN, start, cash settlement, completion, and rating');
  console.log('- report creation, cancellation cleanup, and admin/TODA scope');
  console.log('- Firestore and RTDB participant/offer security rules');
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);
