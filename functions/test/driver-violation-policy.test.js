'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  actorCanAccessDriverViolation,
  driverViolationContext,
  nextDriverViolationStatus,
  nextRestrictionObservation,
  normalizeDriverLocation,
  validIdentifier,
} = require('../driver-violation-policy');

test('fresh online driver locations are normalized for trusted matching', () => {
  assert.deepEqual(normalizeDriverLocation({
    latitude: 10.676,
    longitude: 122.951,
    accuracy: 12,
    bearing: -1,
    speed: -1,
    timestamp: 99000,
    observedAt: 98500,
    online: true,
  }, { now: 100000 }), {
    latitude: 10.676,
    longitude: 122.951,
    accuracy: 12,
    bearing: 359,
    speed: 0,
    timestamp: 99000,
    observedAt: 98500,
    online: true,
  });
});

test('legacy publication remains readable but cannot become violation evidence', () => {
  const legacyLocation = {
    latitude: 10.676,
    longitude: 122.951,
    accuracy: 12,
    timestamp: 99000,
    online: true,
  };
  assert.equal(
    normalizeDriverLocation(legacyLocation, { now: 100000 }).observedAt,
    null,
  );
  assert.throws(
    () => normalizeDriverLocation(legacyLocation, {
      now: 100000,
      requireObservedAt: true,
    }),
    /fresh GPS observedAt/,
  );
});

test('stale, future, inaccurate, and offline locations are rejected', () => {
  const base = {
    latitude: 10.676,
    longitude: 122.951,
    accuracy: 12,
    timestamp: 100000,
    observedAt: 99500,
    online: true,
  };
  assert.throws(
    () => normalizeDriverLocation(
      { ...base, timestamp: 64000 },
      { now: 100000 },
    ),
    /stale|future/,
  );
  assert.throws(
    () => normalizeDriverLocation(
      { ...base, timestamp: 111000 },
      { now: 100000 },
    ),
    /stale|future/,
  );
  assert.throws(
    () => normalizeDriverLocation(
      { ...base, accuracy: 101 },
      { now: 100000 },
    ),
    /accuracy/,
  );
  assert.throws(
    () => normalizeDriverLocation(
      { ...base, online: false },
      { now: 100000 },
    ),
    /online/,
  );
});

test('violation evidence requires a fresh observed fix and 35 metre accuracy', () => {
  const base = {
    latitude: 10.676,
    longitude: 122.951,
    accuracy: 5,
    timestamp: 100000,
    observedAt: 99500,
    online: true,
  };
  assert.throws(
    () => normalizeDriverLocation(
      { ...base, observedAt: 64000 },
      {
        now: 100000,
        requireObservedAt: true,
        maximumObservedAgeMs: 35000,
      },
    ),
    /fresh GPS observedAt/,
  );
  assert.equal(
    normalizeDriverLocation(
      { ...base, accuracy: 80 },
      { now: 100000 },
    ).accuracy,
    80,
  );
  assert.throws(
    () => normalizeDriverLocation(
      { ...base, accuracy: 80 },
      {
        now: 100000,
        requireObservedAt: true,
        maximumAccuracyMeters: 35,
      },
    ),
    /35 metres/,
  );
});

test('violation access excludes passengers and scopes TODA admins', () => {
  const violation = {
    driverId: 'driver-001',
    ownerTodaId: 'toda-a',
  };
  assert.equal(actorCanAccessDriverViolation({
    uid: 'developer-001',
    role: 'developer_admin',
    isActive: true,
  }, violation), true);
  assert.equal(actorCanAccessDriverViolation({
    uid: 'admin-a-001',
    role: 'toda_admin',
    todaId: 'toda-a',
    isActive: true,
  }, violation), true);
  assert.equal(actorCanAccessDriverViolation({
    uid: 'admin-b-001',
    role: 'toda_admin',
    todaId: 'toda-b',
    isActive: true,
  }, violation), false);
  assert.equal(actorCanAccessDriverViolation({
    uid: 'driver-001',
    role: 'driver',
    isActive: true,
  }, violation), true);
  assert.equal(actorCanAccessDriverViolation({
    uid: 'passenger-001',
    role: 'passenger',
    isActive: true,
  }, violation), false);
});

test('administrator actions follow the violation response state machine', () => {
  assert.equal(
    nextDriverViolationStatus('open', 'acknowledge'),
    'acknowledged',
  );
  assert.equal(
    nextDriverViolationStatus('acknowledged', 'investigate'),
    'responding',
  );
  assert.equal(
    nextDriverViolationStatus('responding', 'respond'),
    'responding',
  );
  assert.equal(
    nextDriverViolationStatus('responding', 'resolve'),
    'resolved',
  );
  assert.equal(
    nextDriverViolationStatus('open', 'dismiss'),
    'dismissed',
  );
  assert.throws(
    () => nextDriverViolationStatus('resolved', 'respond'),
    /already closed/,
  );
  assert.throws(
    () => nextDriverViolationStatus('open', 'unknown'),
    /Unsupported/,
  );
});

test('violation and message identifiers reject paths and short values', () => {
  assert.equal(validIdentifier('violation_12345678'), true);
  assert.equal(validIdentifier('short'), false);
  assert.equal(validIdentifier('violation/path'), false);
});

test('violation context distinguishes idle, pickup approach, and active trip', () => {
  assert.equal(driverViolationContext(null, null), 'online_idle');
  assert.equal(
    driverViolationContext('booking-001', 'driverAssigned'),
    'to_pickup',
  );
  assert.equal(
    driverViolationContext('booking-001', 'driverArriving'),
    'to_pickup',
  );
  assert.equal(
    driverViolationContext('booking-001', 'passengerOnBoard'),
    'active_trip',
  );
  assert.equal(
    driverViolationContext('booking-001', 'paymentConfirmation'),
    'active_trip',
  );
});

test('entry and exit require two distinct monotonically newer fixes', () => {
  const firstInside = nextRestrictionObservation({}, {
    inside: true,
    observedAt: 1000,
    now: 1000,
  });
  assert.equal(firstInside.transition, 'candidate_entry');
  const repeatedInside = nextRestrictionObservation(firstInside.updates, {
    inside: true,
    observedAt: 1000,
    now: 1001,
  });
  assert.equal(repeatedInside.transition, 'ignored');
  const confirmedEntry = nextRestrictionObservation(firstInside.updates, {
    inside: true,
    observedAt: 2000,
    now: 2000,
  });
  assert.equal(confirmedEntry.transition, 'enter');
  assert.deepEqual(confirmedEntry.evidence, {
    sampleCount: 2,
    firstObservedAt: 1000,
    confirmingObservedAt: 2000,
  });
  const enteredState = {
    ...firstInside.updates,
    ...confirmedEntry.updates,
    activeViolationId: 'violation_12345678',
  };
  const firstOutside = nextRestrictionObservation(enteredState, {
    inside: false,
    observedAt: 3000,
    now: 3000,
  });
  assert.equal(firstOutside.transition, 'candidate_exit');
  const confirmedExit = nextRestrictionObservation({
    ...enteredState,
    ...firstOutside.updates,
  }, {
    inside: false,
    observedAt: 4000,
    now: 4000,
  });
  assert.equal(confirmedExit.transition, 'exit');
  assert.equal(confirmedExit.updates.inside, false);
  assert.equal(confirmedExit.updates.reentryAllowedAtMillis, 64000);
});

test('re-entry cooldown suppresses rapid edge jitter without losing state', () => {
  const first = nextRestrictionObservation({
    inside: false,
    reentryAllowedAtMillis: 70000,
    lastProcessedObservedAt: 4000,
  }, {
    inside: true,
    observedAt: 5000,
    now: 5000,
  });
  const second = nextRestrictionObservation({
    inside: false,
    reentryAllowedAtMillis: 70000,
    ...first.updates,
  }, {
    inside: true,
    observedAt: 6000,
    now: 6000,
  });
  assert.equal(second.transition, 'reentry_cooldown');
  const afterCooldown = nextRestrictionObservation({
    inside: false,
    reentryAllowedAtMillis: 70000,
    ...second.updates,
  }, {
    inside: true,
    observedAt: 71000,
    now: 71000,
  });
  assert.equal(afterCooldown.transition, 'enter');
});
