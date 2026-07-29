'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  classifyTripCoverage,
  decodePolyline,
  firstNoServiceEndpointConflict,
  firestoreGeometry,
  firestoreRestrictionGeometry,
  normalizeGeometry,
  pointInPolygon,
  routeConflictsRestriction,
} = require('../service-area-policy');

const square = [
  [122.94, 10.66],
  [122.96, 10.66],
  [122.96, 10.68],
  [122.94, 10.68],
];

test('Firestore geometry uses maps rather than nested coordinate arrays', () => {
  const stored = firestoreGeometry([square]);
  assert.equal(stored.geometryVersion, 2);
  assert.deepEqual(stored.polygon[0], {
    latitude: 10.66,
    longitude: 122.94,
  });
  assert.deepEqual(stored.areas[0].points[3], {
    latitude: 10.68,
    longitude: 122.94,
  });
  assert.equal(Array.isArray(stored.polygon[0]), false);
  assert.equal(Array.isArray(stored.areas[0]), false);
});

test('geometry parser accepts callable tuples and stored point maps', () => {
  const stored = firestoreGeometry([square]);
  assert.deepEqual(
    normalizeGeometry(stored),
    normalizeGeometry({ polygon: square }),
  );
});

test('polygon validation rejects degenerate and self-intersecting areas', () => {
  assert.throws(
    () => normalizeGeometry({
      polygon: [
        [122.95, 10.67],
        [122.95, 10.67],
        [122.95, 10.67],
      ],
    }),
    /unique points|duplicate|too small/,
  );
  assert.throws(
    () => normalizeGeometry({
      polygon: [
        [122.94, 10.66],
        [122.96, 10.68],
        [122.94, 10.68],
        [122.96, 10.66],
      ],
    }),
    /self-intersect|too small/,
  );
});

test('coverage classifies intra-TODA, cross-boundary, and unserved pickup', () => {
  const geofences = [{
    todaId: 'toda-a',
    isActive: true,
    coverageRevision: 3,
    ...firestoreGeometry([square]),
  }];
  const inside = { latitude: 10.67, longitude: 122.95 };
  const outside = { latitude: 10.70, longitude: 122.98 };
  assert.deepEqual(
    classifyTripCoverage(geofences, inside, inside),
    {
      configured: true,
      serviceable: true,
      isOutsideToda: false,
      coverageClass: 'intra_toda',
      pickupTodaIds: ['toda-a'],
      destinationTodaIds: ['toda-a'],
      sharedTodaIds: ['toda-a'],
      eligibleTodaIds: ['toda-a'],
      serviceTodaId: 'toda-a',
      geofenceRevisions: { 'toda-a': 3 },
    },
  );
  const crossBoundary = classifyTripCoverage(
    geofences,
    inside,
    outside,
  );
  assert.equal(crossBoundary.coverageClass, 'cross_boundary');
  assert.equal(crossBoundary.isOutsideToda, true);
  assert.deepEqual(crossBoundary.eligibleTodaIds, ['toda-a']);
  const unserved = classifyTripCoverage(geofences, outside, inside);
  assert.equal(unserved.coverageClass, 'pickup_outside_service');
  assert.equal(unserved.serviceable, false);
});

test('overlapping zones remain deterministic without arbitrary ownership', () => {
  const geofences = ['toda-b', 'toda-a'].map((todaId, index) => ({
    todaId,
    coverageRevision: index + 4,
    ...firestoreGeometry([square]),
  }));
  const coverage = classifyTripCoverage(
    geofences,
    { latitude: 10.67, longitude: 122.95 },
    { latitude: 10.67, longitude: 122.95 },
  );
  assert.deepEqual(coverage.sharedTodaIds, ['toda-a', 'toda-b']);
  assert.deepEqual(coverage.eligibleTodaIds, ['toda-a', 'toda-b']);
  assert.deepEqual(coverage.geofenceRevisions, {
    'toda-a': 5,
    'toda-b': 4,
  });
  assert.equal(coverage.serviceTodaId, null);
});

test('no approved geometry preserves the legacy open dispatch fallback', () => {
  const coverage = classifyTripCoverage(
    [],
    { latitude: 10.67, longitude: 122.95 },
    { latitude: 10.70, longitude: 122.98 },
  );
  assert.equal(coverage.configured, false);
  assert.equal(coverage.serviceable, true);
  assert.equal(coverage.isOutsideToda, false);
  assert.deepEqual(coverage.eligibleTodaIds, []);
});

test('polygon boundaries count as inside', () => {
  assert.equal(
    pointInPolygon(
      { latitude: 10.66, longitude: 122.95 },
      square,
    ),
    true,
  );
});

test('route restriction supports polygons and buffered corridors', () => {
  const route = [
    { latitude: 10.65, longitude: 122.95 },
    { latitude: 10.69, longitude: 122.95 },
  ];
  const polygon = {
    type: 'restricted_crossing',
    geometryType: 'polygon',
    isActive: true,
    ...firestoreRestrictionGeometry([square], 'polygon'),
  };
  assert.equal(routeConflictsRestriction(route, polygon), true);
  const corridor = {
    type: 'prohibited_highway',
    geometryType: 'corridor',
    bufferMeters: 30,
    isActive: true,
    ...firestoreRestrictionGeometry([[
      [122.94, 10.67],
      [122.96, 10.67],
    ]], 'corridor'),
  };
  assert.equal(routeConflictsRestriction(route, corridor), true);
});

test('no-service areas reject pickup or destination endpoints', () => {
  const restriction = {
    id: 'closed-terminal',
    type: 'no_service_area',
    isActive: true,
    ...firestoreRestrictionGeometry([square], 'polygon'),
  };
  assert.equal(
    firstNoServiceEndpointConflict(
      { latitude: 10.67, longitude: 122.95 },
      { latitude: 10.70, longitude: 122.98 },
      [restriction],
    )?.id,
    'closed-terminal',
  );
});

test('Google encoded polylines decode to latitude/longitude points', () => {
  assert.deepEqual(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@'), [
    { latitude: 38.5, longitude: -120.2 },
    { latitude: 40.7, longitude: -120.95 },
    { latitude: 43.252, longitude: -126.453 },
  ]);
});
