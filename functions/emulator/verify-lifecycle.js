'use strict';

const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
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

async function setFreshDriverLocation(
  driverId,
  latitude,
  longitude,
  {
    accuracy = 5,
    includeObservedAt = true,
    observedAt = Date.now(),
  } = {},
) {
  const location = {
    latitude,
    longitude,
    accuracy,
    timestamp: Date.now(),
    online: true,
  };
  if (includeObservedAt) location.observedAt = observedAt;
  await realtime.ref(`driver_locations/${driverId}`).set(location);
  return location;
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

  const sharedAdminWebToken =
    'emulator-admin-web-push-shared-token-v1';
  const sharedAdminWebDeviceId = createHash('sha256')
    .update(sharedAdminWebToken)
    .digest('hex');
  const legacyTodaDeviceRef = db.doc(
    `users/toda-admin-test-001/devices/${sharedAdminWebDeviceId}`,
  );
  await legacyTodaDeviceRef.set({
    token: sharedAdminWebToken,
    platform: 'web',
  });
  const migratedWebPush = await callable(
    'registerAdminWebPushToken',
    developerToken,
    {
      token: sharedAdminWebToken,
      previousUid: 'toda-admin-test-001',
      previousDeviceId: sharedAdminWebDeviceId,
    },
  );
  assert.deepEqual(migratedWebPush, {
    registered: true,
    deviceId: sharedAdminWebDeviceId,
  });
  assert.equal((await legacyTodaDeviceRef.get()).exists, false);
  assert.equal(
    (await db.doc(
      `users/developer-admin-test-001/devices/${sharedAdminWebDeviceId}`,
    ).get()).data().token,
    sharedAdminWebToken,
  );
  const migratedRegistry = (await db.doc(
    `adminWebPushTokens/${sharedAdminWebDeviceId}`,
  ).get()).data();
  assert.equal(migratedRegistry.ownerUid, 'developer-admin-test-001');
  assert.equal(migratedRegistry.tokenHash, sharedAdminWebDeviceId);
  assert.equal(migratedRegistry.token, undefined);

  const transferredWebPush = await callable(
    'registerAdminWebPushToken',
    todaAdminToken,
    { token: sharedAdminWebToken },
  );
  assert.equal(transferredWebPush.registered, true);
  assert.equal(
    (await db.doc(
      `users/developer-admin-test-001/devices/${sharedAdminWebDeviceId}`,
    ).get()).exists,
    false,
  );
  assert.equal(
    (await legacyTodaDeviceRef.get()).data().token,
    sharedAdminWebToken,
  );
  assert.equal(
    (await db.doc(
      `adminWebPushTokens/${sharedAdminWebDeviceId}`,
    ).get()).data().ownerUid,
    'toda-admin-test-001',
  );
  await Promise.all([
    expectHttpStatus(
      'administrator cannot directly read the web push owner registry',
      firestoreDocument(`adminWebPushTokens/${sharedAdminWebDeviceId}`),
      developerToken,
      [403],
    ),
    expectHttpStatus(
      'administrator cannot directly overwrite the web push owner registry',
      firestoreDocument(`adminWebPushTokens/${sharedAdminWebDeviceId}`),
      todaAdminToken,
      [403],
      {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          fields: {
            ownerUid: { stringValue: 'developer-admin-test-001' },
          },
        }),
      },
    ),
  ]);
  const refusedWebPushRemoval = await callable(
    'unregisterAdminWebPushToken',
    developerToken,
    {
      token: sharedAdminWebToken,
      deviceId: sharedAdminWebDeviceId,
    },
  );
  assert.equal(refusedWebPushRemoval.unregistered, false);
  assert.equal((await legacyTodaDeviceRef.get()).exists, true);
  const removedWebPush = await callable(
    'unregisterAdminWebPushToken',
    todaAdminToken,
    {
      token: sharedAdminWebToken,
      deviceId: sharedAdminWebDeviceId,
    },
  );
  assert.equal(removedWebPush.unregistered, true);
  assert.equal((await legacyTodaDeviceRef.get()).exists, false);
  assert.equal(
    (await db.doc(
      `adminWebPushTokens/${sharedAdminWebDeviceId}`,
    ).get()).exists,
    false,
  );

  const mismatchedMigrationRef = db.doc(
    'users/toda-admin-test-001/devices/legacy-mismatched-web-device',
  );
  await mismatchedMigrationRef.set({
    token: 'a-different-browser-token',
    platform: 'web',
  });
  const migrationCandidateToken =
    'emulator-admin-web-push-migration-candidate-v1';
  const migrationCandidateDeviceId = createHash('sha256')
    .update(migrationCandidateToken)
    .digest('hex');
  await callable('registerAdminWebPushToken', developerToken, {
    token: migrationCandidateToken,
    previousUid: 'toda-admin-test-001',
    previousDeviceId: 'legacy-mismatched-web-device',
  });
  assert.equal(
    (await mismatchedMigrationRef.get()).data().token,
    'a-different-browser-token',
  );
  await callable('unregisterAdminWebPushToken', developerToken, {
    token: migrationCandidateToken,
    deviceId: migrationCandidateDeviceId,
  });
  await mismatchedMigrationRef.delete();

  // Before any coverage is approved, the pilot fallback remains open to
  // drivers from every active TODA and does not charge a boundary fee.
  await Promise.all([
    callable('setDriverOnlineStatus', driverToken, { isOnline: true }),
    callable('setDriverOnlineStatus', secondDriverToken, { isOnline: true }),
    setFreshDriverLocation('driver-test-001', 10.6765, 122.9509),
    setFreshDriverLocation('driver-test-002', 10.6768, 122.9511),
  ]);
  const pilotBookingId = 'booking-test-pilot-open-001';
  const pilotCreated = await callable(
    'createBookingLifecycle',
    passengerToken,
    {
      bookingId: pilotBookingId,
      operationId: operation('create-pilot-open', 1),
      pickup: { latitude: 10.6762, longitude: 122.9506 },
      destination: { latitude: 10.6840, longitude: 122.9580 },
      pickupAddress: 'Pilot Open Pickup',
      destinationAddress: 'Pilot Open Destination',
      additionalPassengers: 0,
      baggageCount: 0,
      isOutsideToda: true,
      distanceMeters: 1,
      estimatedFare: 1,
    },
  );
  assert.equal(pilotCreated.coverageClass, 'unconfigured_fallback');
  assert.equal(pilotCreated.isOutsideToda, false);
  assert.equal(pilotCreated.fareBreakdown.boundarySurcharge, 0);
  assert.deepEqual(pilotCreated.primaryTodaIds, []);
  assert.deepEqual(pilotCreated.secondaryTodaIds, []);
  await waitFor(
    async () => {
      const [primaryTodaDriver, secondTodaDriver] = await Promise.all([
        db.doc(
          `drivers/driver-test-001/bookingOffers/${pilotBookingId}`,
        ).get(),
        db.doc(
          `drivers/driver-test-002/bookingOffers/${pilotBookingId}`,
        ).get(),
      ]);
      return primaryTodaDriver.data()?.status === 'offered' &&
          secondTodaDriver.data()?.status === 'offered'
        ? [primaryTodaDriver.data(), secondTodaDriver.data()]
        : null;
    },
    'open-pilot offers for both TODAs',
  ).then((offers) => {
    assert.deepEqual(
      offers.map((offer) => offer.servicePriority),
      [0, 0],
    );
    assert.deepEqual(
      offers.map((offer) => offer.serviceTier),
      ['open', 'open'],
    );
  });
  await callable('acceptBookingLifecycle', secondDriverToken, {
    bookingId: pilotBookingId,
    operationId: operation('accept-pilot-open', 1),
  });
  await callable('transitionBookingLifecycle', passengerToken, {
    bookingId: pilotBookingId,
    operationId: operation('cancel-pilot-open', 1),
    action: 'cancel',
    reasonCode: 'emulator_cleanup',
  });

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
  const secondaryCoveragePolygon = [
    [122.975, 10.66],
    [123.005, 10.66],
    [123.005, 10.69],
    [122.975, 10.69],
  ];
  const secondaryZone = await callable(
    'adminSubmitZoneRequest',
    developerToken,
    {
      todaId: 'test-toda-east',
      polygon: secondaryCoveragePolygon,
      areas: [secondaryCoveragePolygon],
      notes: 'Developer-created secondary TODA emulator coverage.',
    },
  );
  await callable('adminReviewZoneRequest', developerToken, {
    zoneRequestId: secondaryZone.zoneRequestId,
    status: 'approved',
  });
  const secondaryGeofence = (await db.doc(
    'geofences/test-toda-east',
  ).get()).data();
  assert.equal(secondaryGeofence.geometryVersion, 2);
  assert.equal(secondaryGeofence.areas[0].points.length, 4);

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
  await callable(
    'adminCreateRouteRestriction',
    developerToken,
    {
      name: 'Emulator segmented highway',
      type: 'prohibited_highway',
      geometryType: 'corridor',
      areas: [
        [
          [122.9400, 10.6500],
          [122.9450, 10.6550],
        ],
        [
          [122.9550, 10.6650],
          [122.9600, 10.6700],
        ],
      ],
      bufferMeters: 30,
      notes: 'New manual highway creation must stay disabled.',
    },
    { expectError: 'FAILED_PRECONDITION' },
  );
  const restrictedDriving = await callable(
    'adminCreateRouteRestriction',
    developerToken,
    {
      name: 'Emulator restricted driving district',
      type: 'restricted_crossing',
      geometryType: 'polygon',
      areas: [blockingArea],
      notes: 'Validates identical endpoint enforcement.',
    },
  );
  await callable('createBookingLifecycle', passengerToken, {
    bookingId: 'booking-test-restricted-driving-001',
    operationId: operation('create-restricted-driving', 1),
    pickup: { latitude: 10.6762, longitude: 122.9506 },
    destination: { latitude: 10.6820, longitude: 122.9540 },
    pickupAddress: 'Allowed Pickup',
    destinationAddress: 'Restricted Driving District',
    additionalPassengers: 0,
    baggageCount: 0,
    isOutsideToda: false,
    distanceMeters: 1,
    estimatedFare: 1,
  }, { expectError: 'FAILED_PRECONDITION' });
  await callable('adminSetRouteRestrictionStatus', developerToken, {
    restrictionId: restrictedDriving.restrictionId,
    isActive: false,
  });
  const legacyHighwayId = 'legacy-highway-history-001';
  await db.doc(`routeRestrictions/${legacyHighwayId}`).set({
    name: 'Archived emulator highway corridor',
    type: 'prohibited_highway',
    geometryType: 'corridor',
    bufferMeters: 30,
    isActive: true,
    coordinates: [
      { latitude: 10.6810, longitude: 122.9480 },
      { latitude: 10.6810, longitude: 122.9600 },
    ],
    notes: 'Retained for history but excluded from route enforcement.',
  });

  await Promise.all([
    callable('setDriverOnlineStatus', driverToken, { isOnline: true }),
    callable('setDriverOnlineStatus', secondDriverToken, { isOnline: true }),
  ]);
  await Promise.all([
    setFreshDriverLocation('driver-test-001', 10.6765, 122.9509),
    setFreshDriverLocation('driver-test-002', 10.6770, 122.9512),
  ]);
  const [developerLiveDrivers, todaLiveDrivers] = await Promise.all([
    callable('adminListLiveDrivers', developerToken, {}),
    callable('adminListLiveDrivers', todaAdminToken, {}),
  ]);
  assert.deepEqual(
    developerLiveDrivers.items.map((item) => item.uid).sort(),
    ['driver-test-001', 'driver-test-002'],
  );
  assert.deepEqual(
    todaLiveDrivers.items.map((item) => item.uid),
    ['driver-test-001'],
  );
  const initialDriverDispatchStats =
    (await db.doc('drivers/driver-test-001').get()).data().dispatchStats || {};

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
  assert.equal(created.coveragePolicyVersion, 3);
  assert.deepEqual(created.primaryTodaIds, ['test-toda-bacolod']);
  assert.deepEqual(created.secondaryTodaIds, []);
  assert.equal(created.allowAnyActiveToda, true);
  assert.deepEqual(created.avoidedRouteRestrictionIds, []);
  assert.deepEqual(created.avoidedRouteRestrictionNames, []);
  assert.equal(created.routePolicyVersion, 4);
  assert.equal(
    created.highwayRouteAdvisory.confirmedViolation,
    false,
  );
  assert.equal(
    (await db.doc(`bookings/${bookingId}`).get())
      .data().routeRestrictionIdsChecked.includes(legacyHighwayId),
    false,
  );

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
  assert.equal(offer.servicePriority, 0);
  assert.equal(offer.dispatchPolicyVersion, 3);
  assert.equal(offer.dispatchScore.version, 3);
  assert.ok(offer.queueEnteredAt);
  assert.ok(offer.bookingCreatedAt);
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
  assert.equal(booking.routePolicyVersion, 4);
  assert.equal(booking.highwayRouteAdvisory.confirmedViolation, false);
  assert.equal(booking.coveragePolicyVersion, 3);
  assert.equal(booking.coverageDecision.version, 3);
  assert.equal(booking.awardPolicyVersion, 3);
  assert.equal(booking.winningDispatchScore.version, 3);
  assert.equal(booking.clientEstimate.estimatedFare, 1);
  assert.notEqual(booking.estimatedFare, 1);
  const assignedDriver =
    (await db.doc('drivers/driver-test-001').get()).data();
  assert.equal(
    assignedDriver.dispatchStats.assignmentCount,
    Number(initialDriverDispatchStats.assignmentCount || 0) + 1,
  );
  assert.ok(assignedDriver.dispatchStats.dailyAwardCount >= 1);
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
  assert.match(startedCall.serverUrl, /^wss?:\/\//);
  const persistedRingingCall =
    (await db.doc(`bookingCalls/${bookingId}`).get()).data();
  assert.equal(persistedRingingCall.serverUrl, startedCall.serverUrl);
  assert.equal(Object.hasOwn(persistedRingingCall, 'token'), false);
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
  assert.equal(acceptedCall.serverUrl, startedCall.serverUrl);
  assert.ok(acceptedCall.token.length > 20);
  const persistedAcceptedCall =
    (await db.doc(`bookingCalls/${bookingId}`).get()).data();
  assert.equal(Object.hasOwn(persistedAcceptedCall, 'token'), false);
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
  assert.equal(
    (await db.doc(`bookingCalls/${bookingId}`).get()).data().status,
    'ended',
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
  for (const [description, location] of [
    [
      'driver cannot publish a stale location timestamp',
      {
        latitude: 10.6762,
        longitude: 122.9506,
        accuracy: 5,
        timestamp: Date.now() - 130000,
        online: true,
      },
    ],
    [
      'driver cannot publish a future location timestamp',
      {
        latitude: 10.6762,
        longitude: 122.9506,
        accuracy: 5,
        timestamp: Date.now() + 11000,
        online: true,
      },
    ],
    [
      'driver cannot publish location worse than 100 metre accuracy',
      {
        latitude: 10.6762,
        longitude: 122.9506,
        accuracy: 101,
        timestamp: Date.now(),
        online: true,
      },
    ],
    [
      'driver cannot publish a stale GPS observation timestamp',
      {
        latitude: 10.6762,
        longitude: 122.9506,
        accuracy: 5,
        observedAt: Date.now() - 130000,
        timestamp: Date.now(),
        online: true,
      },
    ],
    [
      'driver cannot publish a future GPS observation timestamp',
      {
        latitude: 10.6762,
        longitude: 122.9506,
        accuracy: 5,
        observedAt: Date.now() + 11000,
        timestamp: Date.now(),
        online: true,
      },
    ],
    [
      'driver cannot publish an unknown location field',
      {
        latitude: 10.6762,
        longitude: 122.9506,
        accuracy: 5,
        observedAt: Date.now(),
        timestamp: Date.now(),
        online: true,
        spoofedTodaId: 'test-toda-east',
      },
    ],
  ]) {
    await expectHttpStatus(
      description,
      realtimeDocument('driver_locations/driver-test-001', driverToken),
      driverToken,
      [401, 403],
      {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(location),
      },
    );
  }
  await expectHttpStatus(
    'legacy driver location without observedAt remains dispatch-readable',
    realtimeDocument('driver_locations/driver-test-001', driverToken),
    driverToken,
    [200],
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
  await callable(
    'driverReportRestrictionPosition',
    driverToken,
    {},
    { expectError: 'FAILED_PRECONDITION' },
  );
  await expectHttpStatus(
    'dispatch accepts an 80 metre fix before violation confidence filtering',
    realtimeDocument('driver_locations/driver-test-001', driverToken),
    driverToken,
    [200],
    {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        latitude: 10.6762,
        longitude: 122.9506,
        accuracy: 80,
        observedAt: Date.now(),
        timestamp: Date.now(),
        online: true,
      }),
    },
  );
  await callable(
    'driverReportRestrictionPosition',
    driverToken,
    {},
    { expectError: 'FAILED_PRECONDITION' },
  );
  await expectHttpStatus(
    'driver can publish online presence',
    realtimeDocument('driver_presence/driver-test-001', driverToken),
    driverToken,
    [200],
    {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        online: true,
        updatedAt: Date.now(),
      }),
    },
  );
  await expectHttpStatus(
    'driver can publish the onDisconnect-compatible offline presence',
    realtimeDocument('driver_presence/driver-test-001', driverToken),
    driverToken,
    [200],
    {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        online: false,
        updatedAt: Date.now(),
      }),
    },
  );
  await expectHttpStatus(
    'driver presence rejects unknown fields',
    realtimeDocument('driver_presence/driver-test-001', driverToken),
    driverToken,
    [401, 403],
    {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        online: true,
        updatedAt: Date.now(),
        adminOverride: true,
      }),
    },
  );
  await expectHttpStatus(
    'driver can restore online presence after an offline transition',
    realtimeDocument('driver_presence/driver-test-001', driverToken),
    driverToken,
    [200],
    {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        online: true,
        updatedAt: Date.now(),
      }),
    },
  );
  await setFreshDriverLocation(
    'driver-test-001',
    10.6762,
    122.9506,
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
    driver.dispatchStats.completedAssignments,
    Number(initialDriverDispatchStats.completedAssignments || 0) + 1,
  );
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
    destination: { latitude: 10.6765, longitude: 122.9850 },
    pickupAddress: 'Cancellation Pickup',
    destinationAddress: 'Secondary TODA Destination',
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
  assert.equal(
    crossBoundaryBooking.coverageDecision.coverageClass,
    'cross_boundary',
  );
  assert.deepEqual(
    crossBoundaryBooking.primaryTodaIds,
    ['test-toda-bacolod'],
  );
  assert.deepEqual(
    crossBoundaryBooking.secondaryTodaIds,
    ['test-toda-east'],
  );
  assert.equal(crossBoundaryBooking.allowAnyActiveToda, true);
  assert.equal(crossBoundaryBooking.fareBreakdown.boundarySurcharge, 20);
  assert.deepEqual(
    crossBoundaryBooking.eligibleTodaIds,
    ['test-toda-bacolod', 'test-toda-east'],
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
  const [primaryOffer, secondaryOffer] = await Promise.all([
    db.doc(
      `drivers/driver-test-001/bookingOffers/${cancelledBookingId}`,
    ).get(),
    db.doc(
      `drivers/driver-test-002/bookingOffers/${cancelledBookingId}`,
    ).get(),
  ]);
  assert.equal(primaryOffer.data().servicePriority, 0);
  assert.equal(primaryOffer.data().serviceTier, 'primary');
  assert.equal(secondaryOffer.data().servicePriority, 1);
  assert.equal(secondaryOffer.data().serviceTier, 'secondary');
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
    'driver-test-001',
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

  const uncoveredBookingId = 'booking-test-uncovered-001';
  await Promise.all([
    setFreshDriverLocation(
      'driver-test-001',
      10.7051,
      123.0101,
    ),
    setFreshDriverLocation(
      'driver-test-002',
      10.7052,
      123.0102,
    ),
  ]);
  const uncoveredCreated = await callable(
    'createBookingLifecycle',
    passengerToken,
    {
      bookingId: uncoveredBookingId,
      operationId: operation('create-uncovered', 1),
      pickup: { latitude: 10.7050, longitude: 123.0100 },
      destination: { latitude: 10.7100, longitude: 123.0150 },
      pickupAddress: 'Outside Network Pickup',
      destinationAddress: 'Outside Network Destination',
      additionalPassengers: 0,
      baggageCount: 0,
      isOutsideToda: false,
      distanceMeters: 1,
      estimatedFare: 1,
    },
  );
  assert.equal(uncoveredCreated.coverageClass, 'outside_network');
  assert.equal(uncoveredCreated.isOutsideToda, true);
  assert.equal(uncoveredCreated.fareBreakdown.boundarySurcharge, 20);
  assert.deepEqual(uncoveredCreated.primaryTodaIds, []);
  assert.deepEqual(uncoveredCreated.secondaryTodaIds, []);
  assert.equal(uncoveredCreated.allowAnyActiveToda, true);
  const uncoveredOffers = await waitFor(
    async () => {
      const [first, second] = await Promise.all([
        db.doc(
          `drivers/driver-test-001/bookingOffers/${uncoveredBookingId}`,
        ).get(),
        db.doc(
          `drivers/driver-test-002/bookingOffers/${uncoveredBookingId}`,
        ).get(),
      ]);
      return first.data()?.status === 'offered' &&
          second.data()?.status === 'offered'
        ? [first.data(), second.data()]
        : null;
    },
    'configured-network fallback offers',
  );
  assert.deepEqual(
    uncoveredOffers.map((offer) => offer.servicePriority),
    [0, 0],
  );
  assert.deepEqual(
    uncoveredOffers.map((offer) => offer.serviceTier),
    ['fallback', 'fallback'],
  );
  await callable('acceptBookingLifecycle', secondDriverToken, {
    bookingId: uncoveredBookingId,
    operationId: operation('accept-uncovered', 1),
  });
  await callable('transitionBookingLifecycle', passengerToken, {
    bookingId: uncoveredBookingId,
    operationId: operation('cancel-uncovered', 1),
    action: 'cancel',
    reasonCode: 'emulator_cleanup',
  });

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

  const violationArea = [
    [123.0095, 10.7045],
    [123.0105, 10.7045],
    [123.0105, 10.7055],
    [123.0095, 10.7055],
  ];
  const violationRestriction = await callable(
    'adminCreateRouteRestriction',
    developerToken,
    {
      name: 'Emulator Downtown Restricted Area',
      type: 'restricted_crossing',
      geometryType: 'polygon',
      areas: [violationArea],
      notes: 'Exercises backend-verified online-idle entry detection.',
    },
  );
  const firstInsideObservedAt = Date.now() - 3000;
  await setFreshDriverLocation(
    'driver-test-001',
    10.7050,
    123.0100,
    { observedAt: firstInsideObservedAt },
  );
  await waitFor(
    async () => {
      const state = await db.doc(
        'driverRestrictionStates/driver-test-001/restrictions/' +
          violationRestriction.restrictionId,
      ).get();
      return state.data()?.candidateInsideSamples === 1
        ? state.data()
        : null;
    },
    'server-triggered first restricted-area observation',
  );
  // A heartbeat republishes the point with a newer server timestamp while
  // retaining the same device GPS observedAt. It must not count as evidence.
  await setFreshDriverLocation(
    'driver-test-001',
    10.7050,
    123.0100,
    { observedAt: firstInsideObservedAt },
  );
  const repeatedHeartbeat = await callable(
    'driverReportRestrictionPosition',
    driverToken,
    {},
  );
  assert.deepEqual(repeatedHeartbeat.createdViolationIds, []);
  assert.equal(repeatedHeartbeat.locationObservedAt, firstInsideObservedAt);
  assert.equal(
    (await db.doc(
      'driverRestrictionStates/driver-test-001/restrictions/' +
        violationRestriction.restrictionId,
    ).get()).data().candidateInsideSamples,
    1,
  );
  const secondInsideObservedAt = firstInsideObservedAt + 1000;
  await setFreshDriverLocation(
    'driver-test-001',
    10.7050,
    123.0100,
    { observedAt: secondInsideObservedAt },
  );
  const violationSnapshot = await waitFor(
    async () => {
      const documents = await db.collection('driverViolations').get();
      return documents.docs.find((document) =>
        document.data().restrictionId === violationRestriction.restrictionId &&
        document.data().driverId === 'driver-test-001') || null;
    },
    'server-triggered confirmed restricted-area case',
  );
  const violationId = violationSnapshot.id;
  const repeatedPositionReport = await callable(
    'driverReportRestrictionPosition',
    driverToken,
    {},
  );
  assert.deepEqual(repeatedPositionReport.createdViolationIds, []);
  assert.equal(violationSnapshot.data().eventClass, 'restricted_area_entry');
  assert.equal(violationSnapshot.data().status, 'open');
  assert.equal(violationSnapshot.data().driverId, 'driver-test-001');
  assert.equal(
    violationSnapshot.data().ownerTodaId,
    'test-toda-bacolod',
  );
  assert.equal(violationSnapshot.data().context, 'online_idle');
  assert.equal(
    violationSnapshot.data().restrictionId,
    violationRestriction.restrictionId,
  );
  assert.equal(
    violationSnapshot.data().confidence,
    'two_fresh_driver_reported_gps_fixes_server_geometry_match',
  );
  assert.equal(violationSnapshot.data().evidence.sampleCount, 2);
  assert.equal(
    violationSnapshot.data().evidence.clock,
    'gps_observed_at',
  );
  assert.equal(
    violationSnapshot.data().evidence.firstObservedAt,
    firstInsideObservedAt,
  );
  assert.equal(
    violationSnapshot.data().evidence.confirmingObservedAt,
    secondInsideObservedAt,
  );
  assert.equal(
    violationSnapshot.data().eventLocation.observedAt,
    secondInsideObservedAt,
  );
  assert.equal(
    violationSnapshot.data().restrictionSnapshot.id,
    violationRestriction.restrictionId,
  );
  assert.equal(
    violationSnapshot.data().restrictionSnapshot.areas[0].points.length,
    4,
  );
  const completedViolationDelivery = await waitFor(
    async () => {
      const data = (await db.doc(
        `driverViolations/${violationId}`,
      ).get()).data();
      return data?.delivery?.status !== 'pending' &&
          data?.driverDelivery?.status !== 'pending'
        ? data
        : null;
    },
    'separate admin and driver restricted-area notification delivery',
  );
  assert.equal(completedViolationDelivery.delivery.recipientCount, 2);
  assert.equal(completedViolationDelivery.driverDelivery.recipientCount, 1);

  const [developerViolations, todaViolations, driverViolations] =
    await Promise.all([
      callable('adminListDriverViolations', developerToken, {
        limit: 20,
      }),
      callable('adminListDriverViolations', todaAdminToken, {
        limit: 20,
      }),
      callable('listMyDriverViolations', driverToken, {
        limit: 20,
        includeClosed: true,
      }),
    ]);
  assert.ok(
    developerViolations.items.some(
      (item) => item.violationId === violationId,
    ),
  );
  assert.ok(
    todaViolations.items.some(
      (item) => item.violationId === violationId,
    ),
  );
  assert.ok(
    todaViolations.items.every(
      (item) => item.ownerTodaId === 'test-toda-bacolod',
    ),
  );
  assert.ok(
    driverViolations.items.some(
      (item) => item.violationId === violationId,
    ),
  );
  assert.equal(developerViolations.nextCursor, null);
  const [developerViolationDetail, todaViolationDetail] =
    await Promise.all([
      callable('adminGetDriverViolation', developerToken, {
        violationId,
      }),
      callable('adminGetDriverViolation', todaAdminToken, {
        violationId,
      }),
    ]);
  assert.equal(
    developerViolationDetail.item.violationId,
    violationId,
  );
  assert.equal(todaViolationDetail.item.ownerTodaId, 'test-toda-bacolod');
  await callable(
    'adminGetDriverViolation',
    passengerToken,
    { violationId },
    { expectError: 'PERMISSION_DENIED' },
  );
  await callable(
    'listMyDriverViolations',
    passengerToken,
    {},
    { expectError: 'PERMISSION_DENIED' },
  );
  await Promise.all([
    expectHttpStatus(
      'driver may read their own restricted-area case',
      firestoreDocument(`driverViolations/${violationId}`),
      driverToken,
      [200],
    ),
    expectHttpStatus(
      'owning TODA admin may read a restricted-area case',
      firestoreDocument(`driverViolations/${violationId}`),
      todaAdminToken,
      [200],
    ),
    expectHttpStatus(
      'passenger cannot read a driver restricted-area case',
      firestoreDocument(`driverViolations/${violationId}`),
      passengerToken,
      [403],
    ),
    expectHttpStatus(
      'another driver cannot read a driver restricted-area case',
      firestoreDocument(`driverViolations/${violationId}`),
      secondDriverToken,
      [403],
    ),
  ]);

  await callable('adminUpdateDriverViolation', todaAdminToken, {
    violationId,
    action: 'acknowledge',
    note: 'TODA administrator acknowledged the alert.',
  });
  await callable('adminUpdateDriverViolation', developerToken, {
    violationId,
    action: 'investigate',
    note: 'Developer administrator started investigation.',
  });
  const driverMessageId = 'violation-msg-driver-001';
  const adminMessageId = 'violation-msg-admin-001';
  await callable('sendDriverViolationMessage', driverToken, {
    violationId,
    messageId: driverMessageId,
    message: 'I am leaving the restricted district now.',
  });
  const repeatedMessage = await callable(
    'sendDriverViolationMessage',
    driverToken,
    {
      violationId,
      messageId: driverMessageId,
      message: 'I am leaving the restricted district now.',
    },
  );
  assert.equal(repeatedMessage.idempotent, true);
  await callable('sendDriverViolationMessage', developerToken, {
    violationId,
    messageId: adminMessageId,
    message: 'Follow the permitted route and confirm when clear.',
  });
  const storedAdminMessage = (await db.doc(
    `driverViolations/${violationId}/messages/${adminMessageId}`,
  ).get()).data();
  assert.equal(
    storedAdminMessage.senderName,
    'Devon Administrator',
  );
  await callable(
    'sendDriverViolationMessage',
    passengerToken,
    {
      violationId,
      messageId: 'violation-msg-passenger-001',
      message: 'Passengers are not members of violation cases.',
    },
    { expectError: 'PERMISSION_DENIED' },
  );
  await Promise.all([
    expectHttpStatus(
      'driver may read violation case messages',
      firestoreDocument(
        `driverViolations/${violationId}/messages/${adminMessageId}`,
      ),
      driverToken,
      [200],
    ),
    expectHttpStatus(
      'passenger cannot read violation case messages',
      firestoreDocument(
        `driverViolations/${violationId}/messages/${adminMessageId}`,
      ),
      passengerToken,
      [403],
    ),
  ]);
  const readResult = await callable(
    'markDriverViolationMessagesRead',
    driverToken,
    { violationId },
  );
  assert.equal(readResult.markedRead, 2);

  const firstOutsideObservedAt = Date.now() - 2000;
  await setFreshDriverLocation(
    'driver-test-001',
    10.7070,
    123.0120,
    { observedAt: firstOutsideObservedAt },
  );
  await waitFor(
    async () => {
      const state = await db.doc(
        'driverRestrictionStates/driver-test-001/restrictions/' +
          violationRestriction.restrictionId,
      ).get();
      return state.data()?.candidateOutsideSamples === 1
        ? state.data()
        : null;
    },
    'server-triggered first restricted-area exit observation',
  );
  await setFreshDriverLocation(
    'driver-test-001',
    10.7071,
    123.0121,
    { observedAt: firstOutsideObservedAt + 1000 },
  );
  const exitedViolation = await waitFor(
    async () => {
      const snapshot = await db.doc(
        `driverViolations/${violationId}`,
      ).get();
      return snapshot.data()?.exitedAt ? snapshot.data() : null;
    },
    'server-triggered confirmed restricted-area exit',
  );
  assert.equal(
    exitedViolation.exitEvidence.confirmingObservedAt,
    firstOutsideObservedAt + 1000,
  );
  const resolvedViolation = await callable(
    'adminUpdateDriverViolation',
    developerToken,
    {
      violationId,
      action: 'resolve',
      note: 'Driver left the mapped restricted district safely.',
    },
  );
  assert.equal(resolvedViolation.status, 'resolved');
  await expectHttpStatus(
    'driver location may be removed by the onDisconnect-compatible cleanup',
    realtimeDocument('driver_locations/driver-test-001', driverToken),
    driverToken,
    [200],
    { method: 'DELETE' },
  );

  console.log('Verified isolated VolTrike lifecycle:');
  console.log('- trusted booking/fare creation and 5 km dispatch');
  console.log('- driver acceptance, tracking grant, arrival, SOS, and sharing');
  console.log('- pickup PIN, start, cash settlement, completion, and rating');
  console.log('- report creation, cancellation cleanup, and admin/TODA scope');
  console.log('- Firestore and RTDB participant/offer security rules');
  console.log('- restricted-area entry dedupe, scope, response, and case chat');
}

main().then(
  () => process.exit(0),
  (error) => {
    console.error(error);
    process.exit(1);
  },
);
