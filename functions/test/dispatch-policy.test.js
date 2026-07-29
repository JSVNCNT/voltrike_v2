'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  bookingDriverServicePriority,
  compareDispatchClaims,
  dispatchDateKey,
  dispatchScoreSnapshot,
  driverDispatchStats,
  nextDriverDispatchStats,
  selectDispatchBatch,
  smoothedQuality,
  smoothedReliability,
} = require('../dispatch-policy');

test('accepted candidates are awarded by service tier before distance', () => {
  const claims = [
    {
      driverId: 'primary-far',
      servicePriority: 0,
      distanceMeters: 800,
      acceptedAt: 200,
    },
    {
      driverId: 'secondary-near',
      servicePriority: 1,
      distanceMeters: 50,
      acceptedAt: 50,
    },
    {
      driverId: 'fallback-nearest',
      servicePriority: 2,
      distanceMeters: 10,
      acceptedAt: 10,
    },
  ].sort(compareDispatchClaims);
  assert.deepEqual(
    claims.map((claim) => claim.driverId),
    ['primary-far', 'secondary-near', 'fallback-nearest'],
  );
});

test('distance bands precede balanced workload and exact distance', () => {
  const claims = [
    {
      driverId: 'nearer-but-busier',
      servicePriority: 0,
      distanceMeters: 210,
      dailyAwards: 5,
    },
    {
      driverId: 'farther-but-fairer',
      servicePriority: 0,
      distanceMeters: 290,
      dailyAwards: 0,
    },
    {
      driverId: 'next-band',
      servicePriority: 0,
      distanceMeters: 301,
      dailyAwards: 0,
    },
  ].sort(compareDispatchClaims);
  assert.deepEqual(
    claims.map((claim) => claim.driverId),
    ['farther-but-fairer', 'nearer-but-busier', 'next-band'],
  );
});

test('reliability, quality, and exact distance resolve a balanced band', () => {
  const claims = [
    {
      driverId: 'lower-reliability',
      servicePriority: 0,
      distanceMeters: 205,
      dailyAwards: 1,
      reliabilityScore: 0.8,
      qualityScore: 5,
    },
    {
      driverId: 'higher-quality',
      servicePriority: 0,
      distanceMeters: 290,
      dailyAwards: 1,
      reliabilityScore: 0.95,
      qualityScore: 4.9,
    },
    {
      driverId: 'nearer-equal-quality',
      servicePriority: 0,
      distanceMeters: 220,
      dailyAwards: 1,
      reliabilityScore: 0.95,
      qualityScore: 4.7,
    },
    {
      driverId: 'farther-equal-quality',
      servicePriority: 0,
      distanceMeters: 280,
      dailyAwards: 1,
      reliabilityScore: 0.95,
      qualityScore: 4.7,
    },
  ].sort(compareDispatchClaims);
  assert.deepEqual(
    claims.map((claim) => claim.driverId),
    [
      'higher-quality',
      'nearer-equal-quality',
      'farther-equal-quality',
      'lower-reliability',
    ],
  );
});

test('accept time and driver ID provide stable final tie breakers', () => {
  const claims = [
    { driverId: 'b', distanceMeters: 100, acceptedAt: 200 },
    { driverId: 'c', distanceMeters: 100, acceptedAt: 100 },
    { driverId: 'a', distanceMeters: 100, acceptedAt: 200 },
  ].sort(compareDispatchClaims);
  assert.deepEqual(
    claims.map((claim) => claim.driverId),
    ['c', 'a', 'b'],
  );
});

test('cold-start and malformed scoring inputs receive neutral safe defaults', () => {
  assert.equal(smoothedReliability(), 0.9);
  assert.equal(smoothedQuality(), 4.5);
  assert.equal(smoothedQuality({ rating: 5, ratingCount: 0 }), 4.5);
  assert.equal(
    smoothedReliability({
      completedAssignments: -10,
      driverFaultCancellations: 'invalid',
    }),
    0.9,
  );
  assert.deepEqual(
    dispatchScoreSnapshot({
      servicePriority: -1,
      distanceMeters: -50,
      dailyAwards: -5,
      reliabilityScore: 9,
      qualityScore: -2,
    }),
    {
      version: 3,
      servicePriority: Number.MAX_SAFE_INTEGER,
      distanceBandMeters: 100,
      distanceBand: Number.MAX_SAFE_INTEGER,
      distanceMeters: Number.POSITIVE_INFINITY,
      dailyAwards: 0,
      reliabilityScore: 1,
      qualityScore: 0,
    },
  );
});

test('coverage tiers admit primary, secondary, and active fallback TODAs', () => {
  const booking = {
    primaryTodaIds: ['pickup-a'],
    secondaryTodaIds: ['destination-b'],
    allowAnyActiveToda: true,
  };
  assert.equal(bookingDriverServicePriority(booking, 'pickup-a'), 0);
  assert.equal(bookingDriverServicePriority(booking, 'destination-b'), 1);
  assert.equal(bookingDriverServicePriority(booking, 'mutual-aid-c'), 2);
  assert.equal(bookingDriverServicePriority(booking, ''), null);
});

test('no-primary fallback gives every active TODA equal priority', () => {
  const booking = {
    primaryTodaIds: [],
    secondaryTodaIds: [],
    allowAnyActiveToda: true,
  };
  assert.equal(bookingDriverServicePriority(booking, 'toda-a'), 0);
  assert.equal(bookingDriverServicePriority(booking, 'toda-z'), 0);
});

test('mixed offer batches reserve nearest secondary and fallback drivers', () => {
  const candidates = [
    ...Array.from({ length: 8 }, (_, index) => ({
      driverId: `primary-${index}`,
      servicePriority: 0,
      distanceMeters: 100 + index,
    })),
    {
      driverId: 'secondary-nearest',
      servicePriority: 1,
      distanceMeters: 410,
      dailyAwards: 9,
    },
    {
      driverId: 'secondary-fairer',
      servicePriority: 1,
      distanceMeters: 450,
      dailyAwards: 0,
    },
    {
      driverId: 'fallback-nearest',
      servicePriority: 2,
      distanceMeters: 510,
      dailyAwards: 9,
    },
    {
      driverId: 'fallback-fairer',
      servicePriority: 2,
      distanceMeters: 550,
      dailyAwards: 0,
    },
  ];
  const selected = selectDispatchBatch(candidates, 5);
  assert.deepEqual(
    selected.map((candidate) => candidate.driverId),
    [
      'primary-0',
      'primary-1',
      'primary-2',
      'secondary-nearest',
      'fallback-nearest',
    ],
  );
});

test('daily award windows reset at Manila midnight and retain totals', () => {
  const beforeMidnight = Date.parse('2026-01-01T15:59:00.000Z');
  const afterMidnight = Date.parse('2026-01-01T16:00:00.000Z');
  assert.equal(dispatchDateKey(beforeMidnight), '2026-01-01');
  assert.equal(dispatchDateKey(afterMidnight), '2026-01-02');

  const driver = {
    dispatchStats: {
      dailyAwardDate: '2026-01-01',
      dailyAwardCount: 4,
      assignmentCount: 20,
      completedAssignments: 18,
      cancellationCount: 2,
      driverFaultCancellations: 1,
    },
  };
  assert.equal(
    driverDispatchStats(driver, beforeMidnight).dailyAwardCount,
    4,
  );
  assert.deepEqual(driverDispatchStats(driver, afterMidnight), {
    dailyAwardDate: '2026-01-02',
    dailyAwardCount: 0,
    assignmentCount: 20,
    completedAssignments: 18,
    cancellationCount: 2,
    driverFaultCancellations: 1,
  });
});

test('assignment, completion, and cancellation statistics advance once per outcome', () => {
  const now = Date.parse('2026-01-01T03:00:00.000Z');
  const assigned = nextDriverDispatchStats({}, 'assigned', now);
  assert.equal(assigned.dailyAwardCount, 1);
  assert.equal(assigned.assignmentCount, 1);

  const completed = nextDriverDispatchStats(
    { dispatchStats: assigned },
    'completed',
    now,
  );
  assert.equal(completed.completedAssignments, 1);
  assert.equal(completed.cancellationCount, 0);

  const driverFault = nextDriverDispatchStats(
    { dispatchStats: completed },
    'driver_fault_cancelled',
    now,
  );
  assert.equal(driverFault.cancellationCount, 1);
  assert.equal(driverFault.driverFaultCancellations, 1);
});
