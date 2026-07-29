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

  const coveragePolygon = [
    [122.94, 10.66],
    [122.97, 10.66],
    [122.97, 10.69],
    [122.94, 10.69],
  ];
  const submittedZone = await callable(
    'adminSubmitZoneRequest',
    todaAdminToken,
    {
      todaId: 'test-toda-bacolod',
      polygon: coveragePolygon,
      areas: [coveragePolygon],
      notes: 'Local Barangay 40 coverage verification.',
    },
  );
  await callable('adminUpdateZoneRequest', todaAdminToken, {
    zoneRequestId: submittedZone.zoneRequestId,
    polygon: coveragePolygon,
    areas: [coveragePolygon],
    notes: 'TODA administrator verified the pending geometry.',
  });
  await callable('adminReviewZoneRequest', developerToken, {
    zoneRequestId: submittedZone.zoneRequestId,
    status: 'approved',
  });
  const geofence = (await db.doc(
    'geofences/test-toda-bacolod',
  ).get()).data();
  assert.equal(geofence.geometryVersion, 2);
  assert.equal(geofence.areas[0].points.length, 4);
  assert.deepEqual(geofence.polygon[0], {
    latitude: 10.66,
    longitude: 122.94,
  });

  const blockingArea = [
    [122.953, 10.681],
    [122.955, 10.681],
    [122.955, 10.683],
    [122.953, 10.683],
  ];
  const restriction = await callable(
    'adminCreateRouteRestriction',
    developerToken,
    {
      name: 'Emulator closed terminal',
      type: 'no_service_area',
      geometryType: 'polygon',
      polygon: blockingArea,
      areas: [blockingArea],
      bufferMeters: 0,
      notes: 'Validates server-side endpoint rejection.',
    },
  );
  const storedRestriction = (await db.doc(
    `routeRestrictions/${restriction.restrictionId}`,
  ).get()).data();
  assert.equal(storedRestriction.geometryVersion, 2);
  assert.equal(storedRestriction.areas[0].points.length, 4);
  await callable('createBookingLifecycle', passengerToken, {
    bookingId: 'booking-test-restricted-001',
    operationId: operation('create-restricted', 1),
    pickup: { latitude: 10.6762, longitude: 122.9506 },
    destination: { latitude: 10.6820, longitude: 122.9540 },
    pickupAddress: 'Allowed Pickup',
    destinationAddress: 'Closed Terminal',
    additionalPassengers: 0,
    baggageCount: 0,
    isOutsideToda: false,
    distanceMeters: 1,
    estimatedFare: 1,
  }, { expectError: 'FAILED_PRECONDITION' });
  await callable(
    'adminSetRouteRestrictionStatus',
    developerToken,
    {
      restrictionId: restriction.restrictionId,
      isActive: false,
    },
  );

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
  const startedCall = await callable(
    'startBookingCall',
    passengerToken,
    { bookingId },
  );
  assert.equal(startedCall.status, 'ringing');
  assert.ok(startedCall.callId.startsWith('call_'));
  await Promise.all([
    expectHttpStatus(
      'passenger may read the booking call before acceptance',
      firestoreDocument(`bookingCalls/${bookingId}`),
      passengerToken,
      [200],
    ),
    expectHttpStatus(
      'assigned driver may read the booking call before acceptance',
      firestoreDocument(`bookingCalls/${bookingId}`),
      driverToken,
      [200],
    ),
    expectHttpStatus(
      'unassigned driver cannot read the booking call',
      firestoreDocument(`bookingCalls/${bookingId}`),
      secondDriverToken,
      [403],
    ),
  ]);
  await expectHttpStatus(
    'recipient may discover a ringing call through the durable query',
    `${firestoreBase}:runQuery`,
    driverToken,
    [200],
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: 'bookingCalls' }],
          where: {
            compositeFilter: {
              op: 'AND',
              filters: [
                {
                  fieldFilter: {
                    field: { fieldPath: 'recipientId' },
                    op: 'EQUAL',
                    value: { stringValue: 'driver-test-001' },
                  },
                },
                {
                  fieldFilter: {
                    field: { fieldPath: 'status' },
                    op: 'EQUAL',
                    value: { stringValue: 'ringing' },
                  },
                },
                {
                  fieldFilter: {
                    field: { fieldPath: 'expiresAt' },
                    op: 'GREATER_THAN',
                    value: {
                      timestampValue: new Date().toISOString(),
                    },
                  },
                },
              ],
            },
          },
          orderBy: [
            {
              field: { fieldPath: 'expiresAt' },
              direction: 'DESCENDING',
            },
          ],
          limit: 1,
        },
      }),
    },
  );
  await callable(
    'respondBookingCall',
    passengerToken,
    {
      bookingId,
      callId: startedCall.callId,
      response: 'accepted',
    },
    { expectError: 'PERMISSION_DENIED' },
  );
  const acceptedCall = await callable(
    'respondBookingCall',
    driverToken,
    {
      bookingId,
      callId: startedCall.callId,
      response: 'accepted',
    },
  );
  assert.equal(acceptedCall.status, 'accepted');
  assert.ok(acceptedCall.endsAtMillis > Date.now());
  const callCredentials = await callable(
    'createBookingCallToken',
    passengerToken,
    {
      bookingId,
      callId: startedCall.callId,
    },
  );
  assert.equal(callCredentials.callId, startedCall.callId);
  assert.ok(callCredentials.token.length > 20);
  await callable(
    'endBookingCall',
    passengerToken,
    {
      bookingId,
      callId: startedCall.callId,
    },
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
  const safetyIncident = await callable('createSafetyIncident', passengerToken, {
    bookingId,
  });
  const repeatedSafetyIncident = await callable(
    'createSafetyIncident',
    passengerToken,
    { bookingId },
  );
  assert.equal(safetyIncident.idempotent, false);
  assert.equal(repeatedSafetyIncident.idempotent, true);
  assert.equal(safetyIncident.incidentId, repeatedSafetyIncident.incidentId);
  const shared = await callable(
    'getShareTripInformation',
    passengerToken,
    { bookingId },
  );
  assert.equal(shared.driverName, 'Dario Driver');

  await callable('transitionBookingLifecycle', driverToken, {
    bookingId,
    operationId: operation('start-main', 1),
    action: 'start',
  });
  await callable('transitionBookingLifecycle', driverToken, {
    bookingId,
    operationId: operation('dropoff-main', 1),
    action: 'dropOff',
  });

  await callable('transitionBookingLifecycle', driverToken, {
    bookingId,
    operationId: operation('complete-main', 1),
    action: 'complete',
  });
  const driverBeforeRating =
    (await db.doc('drivers/driver-test-001').get()).data();
  const ratingResult = await callable('submitDriverRating', passengerToken, {
    bookingId,
    rating: 5,
    comment: 'Local emulator lifecycle.',
  });
  const repeatedRating = await callable('submitDriverRating', passengerToken, {
    bookingId,
    rating: 5,
    comment: 'Repeated local emulator lifecycle.',
  });
  assert.equal(ratingResult.idempotent, false);
  assert.equal(repeatedRating.idempotent, true);
  const savedRating = (await db.doc(
    `ratings/${bookingId}_passenger-test-001`,
  ).get()).data();
  assert.equal(savedRating.rating, 5);
  assert.equal(savedRating.comment, 'Local emulator lifecycle.');
  assert.equal(savedRating.todaId, 'test-toda-bacolod');
  const driverAfterRating =
    (await db.doc('drivers/driver-test-001').get()).data();
  assert.equal(
    driverAfterRating.ratingCount,
    Number(driverBeforeRating.ratingCount || 0) + 1,
  );
  await callable('createRideReport', passengerToken, {
    bookingId,
    reportId: 'report-test-main-001',
    category: 'test_follow_up',
    details: 'Local emulator verification report.',
  });

  booking = (await db.doc(`bookings/${bookingId}`).get()).data();
  assert.equal(booking.status, 'completed');
  assert.equal(booking.settlementStatus, 'settled');
  assert.match(booking.receiptNumber, /^VT-/);
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
  await Promise.all([
    setFreshDriverLocation(
      'driver-test-001',
      10.6780,
      122.9520,
    ),
    setFreshDriverLocation(
      'driver-test-002',
      10.6763,
      122.9507,
    ),
  ]);
  await callable('createBookingLifecycle', passengerToken, {
    bookingId: cancelledBookingId,
    operationId: operation('create-cancel', 1),
    pickup: { latitude: 10.6762, longitude: 122.9506 },
    destination: { latitude: 10.7000, longitude: 122.9800 },
    pickupAddress: 'Cancellation Pickup',
    destinationAddress: 'Cancellation Destination',
    additionalPassengers: 0,
    baggageCount: 0,
    isOutsideToda: false,
    distanceMeters: 1,
    estimatedFare: 1,
  });
  const crossBoundaryBooking = (await db.doc(
    `bookings/${cancelledBookingId}`,
  ).get()).data();
  assert.equal(crossBoundaryBooking.isOutsideToda, true);
  assert.equal(crossBoundaryBooking.fareBreakdown.boundarySurcharge, 20);
  assert.deepEqual(
    crossBoundaryBooking.eligibleTodaIds,
    ['test-toda-bacolod'],
  );
  await waitFor(
    async () => {
      const [first, second] = await Promise.all([
        db.doc(
          `drivers/driver-test-001/bookingOffers/${cancelledBookingId}`,
        ).get(),
        db.doc(
          `drivers/driver-test-002/bookingOffers/${cancelledBookingId}`,
        ).get(),
      ]);
      return first.data()?.status === 'offered' &&
        second.data()?.status === 'offered';
    },
    'competing distance-ranked offers',
  );
  const competingAccepts = await Promise.allSettled([
    callable('acceptBookingLifecycle', driverToken, {
      bookingId: cancelledBookingId,
      operationId: operation('accept-competition-far', 1),
    }),
    callable('acceptBookingLifecycle', secondDriverToken, {
      bookingId: cancelledBookingId,
      operationId: operation('accept-competition-near', 1),
    }),
  ]);
  assert.equal(
    competingAccepts.filter((result) => result.status === 'fulfilled').length,
    1,
  );
  assert.equal(
    (await db.doc(`bookings/${cancelledBookingId}`).get()).data().driverId,
    'driver-test-002',
  );
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
    'adminListRatings',
    developerToken,
    { pageSize: 20 },
    { expectError: 'PERMISSION_DENIED' },
  );
  const developerSafety = await callable(
    'adminListSafetyIncidents',
    developerToken,
    { pageSize: 20 },
  );
  assert.ok(
    developerSafety.items.some((item) => item.bookingId === bookingId),
  );
  const todaSafety = await callable(
    'adminListSafetyIncidents',
    todaAdminToken,
    { pageSize: 20 },
  );
  assert.ok(
    todaSafety.items.some((item) => item.bookingId === bookingId),
  );
  assert.ok(
    todaSafety.items.every(
      (item) => item.todaId === 'test-toda-bacolod',
    ),
  );
  const todaRatings = await callable(
    'adminListRatings',
    todaAdminToken,
    { pageSize: 20 },
  );
  assert.ok(
    todaRatings.items.some((item) => item.bookingId === bookingId),
  );
  assert.ok(
    todaRatings.items.every(
      (item) => item.todaId === 'test-toda-bacolod',
    ),
  );
  const developerMetrics = await callable(
    'adminGetMetrics',
    developerToken,
    {},
  );
  assert.ok(developerMetrics.bookings >= 2);
  assert.ok(developerMetrics.trips >= 1);
  assert.ok(developerMetrics.safetyIncidents >= 1);
  const todaMetrics = await callable(
    'adminGetMetrics',
    todaAdminToken,
    {},
  );
  assert.ok(todaMetrics.bookings >= 1);
  assert.ok(todaMetrics.trips >= 1);
  assert.ok(todaMetrics.safetyIncidents >= 1);
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
