'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  classifyTripCoverage,
  decodePolyline,
  firstHighwayTravelConflict,
  firstNoServiceEndpointConflict,
  firstRouteConflict,
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

test('coverage classifies intra-TODA and one-endpoint-outside trips', () => {
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
      primaryTodaIds: ['toda-a'],
      secondaryTodaIds: [],
      allowAnyActiveToda: true,
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
  assert.equal(
    crossBoundary.coverageClass,
    'destination_outside_coverage',
  );
  assert.equal(crossBoundary.isOutsideToda, true);
  assert.deepEqual(crossBoundary.primaryTodaIds, ['toda-a']);
  assert.deepEqual(crossBoundary.secondaryTodaIds, []);
  assert.deepEqual(crossBoundary.eligibleTodaIds, ['toda-a']);
  const pickupOutside = classifyTripCoverage(geofences, outside, inside);
  assert.equal(pickupOutside.coverageClass, 'pickup_outside_coverage');
  assert.equal(pickupOutside.serviceable, true);
  assert.deepEqual(pickupOutside.primaryTodaIds, ['toda-a']);
  assert.equal(pickupOutside.allowAnyActiveToda, true);
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
  assert.deepEqual(coverage.primaryTodaIds, ['toda-a', 'toda-b']);
  assert.deepEqual(coverage.secondaryTodaIds, []);
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
  assert.equal(coverage.coverageClass, 'unconfigured_fallback');
  assert.deepEqual(coverage.primaryTodaIds, []);
  assert.deepEqual(coverage.secondaryTodaIds, []);
  assert.equal(coverage.allowAnyActiveToda, true);
  assert.deepEqual(coverage.eligibleTodaIds, []);
});

test('disjoint endpoint TODAs form primary and secondary mutual-aid tiers', () => {
  const squareB = square.map(([longitude, latitude]) => [
    longitude + 0.04,
    latitude,
  ]);
  const geofences = [
    {
      todaId: 'toda-a',
      coverageRevision: 7,
      ...firestoreGeometry([square]),
    },
    {
      todaId: 'toda-b',
      coverageRevision: 2,
      ...firestoreGeometry([squareB]),
    },
  ];
  const coverage = classifyTripCoverage(
    geofences,
    { latitude: 10.67, longitude: 122.95 },
    { latitude: 10.67, longitude: 122.99 },
  );
  assert.equal(coverage.serviceable, true);
  assert.equal(coverage.coverageClass, 'cross_boundary');
  assert.equal(coverage.isOutsideToda, true);
  assert.deepEqual(coverage.pickupTodaIds, ['toda-a']);
  assert.deepEqual(coverage.destinationTodaIds, ['toda-b']);
  assert.deepEqual(coverage.primaryTodaIds, ['toda-a']);
  assert.deepEqual(coverage.secondaryTodaIds, ['toda-b']);
  assert.deepEqual(coverage.eligibleTodaIds, ['toda-a', 'toda-b']);
  assert.deepEqual(coverage.geofenceRevisions, {
    'toda-a': 7,
    'toda-b': 2,
  });
});

test('configured network keeps fully uncovered trips serviceable', () => {
  const geofences = [{
    todaId: 'toda-a',
    coverageRevision: 1,
    ...firestoreGeometry([square]),
  }];
  const coverage = classifyTripCoverage(
    geofences,
    { latitude: 10.72, longitude: 123.02 },
    { latitude: 10.73, longitude: 123.03 },
  );
  assert.equal(coverage.configured, true);
  assert.equal(coverage.serviceable, true);
  assert.equal(coverage.coverageClass, 'outside_network');
  assert.equal(coverage.isOutsideToda, true);
  assert.deepEqual(coverage.primaryTodaIds, []);
  assert.deepEqual(coverage.secondaryTodaIds, []);
  assert.equal(coverage.allowAnyActiveToda, true);
});

test('shared endpoint ownership is primary and other overlaps are secondary', () => {
  const pickupOnly = square.map(([longitude, latitude]) => [
    longitude - 0.005,
    latitude,
  ]);
  const destinationOnly = square.map(([longitude, latitude]) => [
    longitude + 0.005,
    latitude,
  ]);
  const geofences = [
    { todaId: 'toda-a', ...firestoreGeometry([pickupOnly]) },
    { todaId: 'toda-b', ...firestoreGeometry([square]) },
    { todaId: 'toda-c', ...firestoreGeometry([destinationOnly]) },
  ];
  const coverage = classifyTripCoverage(
    geofences,
    { latitude: 10.67, longitude: 122.942 },
    { latitude: 10.67, longitude: 122.958 },
  );
  assert.deepEqual(coverage.pickupTodaIds, ['toda-a', 'toda-b']);
  assert.deepEqual(coverage.destinationTodaIds, ['toda-b', 'toda-c']);
  assert.deepEqual(coverage.sharedTodaIds, ['toda-b']);
  assert.deepEqual(coverage.primaryTodaIds, ['toda-b']);
  assert.deepEqual(coverage.secondaryTodaIds, ['toda-a', 'toda-c']);
  assert.equal(coverage.coverageClass, 'intra_toda');
  assert.equal(coverage.isOutsideToda, false);
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

test('corridor geometry stores up to twenty disconnected line areas', () => {
  const segments = Array.from({ length: 20 }, (_, index) => [
    [122.94 + index * 0.001, 10.67],
    [122.9405 + index * 0.001, 10.6705],
  ]);
  const stored = firestoreRestrictionGeometry(segments, 'corridor');
  assert.equal(stored.geometryVersion, 2);
  assert.equal(stored.areas.length, 20);
  assert.deepEqual(stored.polygon, stored.areas[0].points);
  assert.deepEqual(stored.coordinates, stored.areas[0].points);
  assert.deepEqual(
    normalizeGeometry(stored, { geometryType: 'corridor' }),
    normalizeGeometry({ areas: segments }, { geometryType: 'corridor' }),
  );
  assert.throws(
    () => firestoreRestrictionGeometry([], 'corridor'),
    /one to 20 centrelines/,
  );
  assert.throws(
    () => firestoreRestrictionGeometry([...segments, segments[0]], 'corridor'),
    /one to 20 centrelines/,
  );
});

test('each corridor line area requires two to two hundred points', () => {
  assert.throws(
    () => firestoreRestrictionGeometry([[[122.94, 10.67]]], 'corridor'),
    /2 to 200 points/,
  );
  const maximumLengthLine = Array.from({ length: 200 }, (_, index) => [
    122.94 + index * 0.00001,
    10.67,
  ]);
  assert.equal(
    firestoreRestrictionGeometry([maximumLengthLine], 'corridor')
      .areas[0].points.length,
    200,
  );
  assert.throws(
    () => firestoreRestrictionGeometry(
      [[...maximumLengthLine, [122.943, 10.67]]],
      'corridor',
    ),
    /2 to 200 points/,
  );
});

test('disconnected corridor segments block either segment but preserve gaps', () => {
  const restriction = {
    type: 'prohibited_highway',
    geometryType: 'corridor',
    bufferMeters: 30,
    isActive: true,
    ...firestoreRestrictionGeometry([
      [
        [122.94, 10.67],
        [122.945, 10.67],
      ],
      [
        [122.955, 10.67],
        [122.96, 10.67],
      ],
    ], 'corridor'),
  };
  const alongFirstSegment = [
    { latitude: 10.67, longitude: 122.941 },
    { latitude: 10.67, longitude: 122.944 },
  ];
  const crossingSecondSegment = [
    { latitude: 10.669, longitude: 122.957 },
    { latitude: 10.671, longitude: 122.957 },
  ];
  const throughWideGap = [
    { latitude: 10.669, longitude: 122.95 },
    { latitude: 10.671, longitude: 122.95 },
  ];
  assert.equal(
    routeConflictsRestriction(alongFirstSegment, restriction),
    true,
  );
  assert.equal(
    routeConflictsRestriction(crossingSecondSegment, restriction),
    true,
  );
  assert.equal(routeConflictsRestriction(throughWideGap, restriction), false);
});

test('a narrow intentional gap between corridor segments remains routable', () => {
  const restriction = {
    type: 'prohibited_highway',
    geometryType: 'corridor',
    bufferMeters: 30,
    isActive: true,
    ...firestoreRestrictionGeometry([
      [
        [122.945, 10.67],
        [122.9496, 10.67],
      ],
      [
        [122.9504, 10.67],
        [122.955, 10.67],
      ],
    ], 'corridor'),
  };
  const throughGap = [
    { latitude: 10.6698, longitude: 122.95 },
    { latitude: 10.6702, longitude: 122.95 },
  ];
  assert.equal(routeConflictsRestriction(throughGap, restriction), false);
});

test('legacy single-corridor coordinates remain supported', () => {
  const legacyRestriction = {
    type: 'prohibited_highway',
    geometryType: 'corridor',
    bufferMeters: 30,
    isActive: true,
    coordinates: [
      [122.94, 10.67],
      [122.96, 10.67],
    ],
  };
  const crossingRoute = [
    { latitude: 10.669, longitude: 122.95 },
    { latitude: 10.671, longitude: 122.95 },
  ];
  assert.equal(
    routeConflictsRestriction(crossingRoute, legacyRestriction),
    true,
  );
});

test('active legacy highway corridors remain readable but do not block routes', () => {
  const legacyRestriction = {
    id: 'archived-highway-corridor',
    type: 'prohibited_highway',
    geometryType: 'corridor',
    bufferMeters: 30,
    isActive: true,
    coordinates: [
      [122.94, 10.67],
      [122.96, 10.67],
    ],
  };
  const crossingRoute = [
    { latitude: 10.669, longitude: 122.95 },
    { latitude: 10.671, longitude: 122.95 },
  ];
  assert.equal(routeConflictsRestriction(crossingRoute, legacyRestriction), true);
  assert.equal(firstRouteConflict(crossingRoute, [legacyRestriction]), null);
});

test('highway groups reject sustained aligned travel but allow a cross-street crossing', () => {
  const highway = {
    id: 'burgos-extension',
    name: 'Burgos Extension',
    type: 'prohibited_highway',
    geometryType: 'corridor',
    bufferMeters: 25,
    minimumAlignedTravelMeters: 80,
    isActive: true,
    ...firestoreRestrictionGeometry([[
      [122.9400, 10.6700],
      [122.9450, 10.6700],
    ]], 'corridor'),
  };
  const along = [
    { latitude: 10.67002, longitude: 122.9402 },
    { latitude: 10.67002, longitude: 122.9420 },
  ];
  const crossing = [
    { latitude: 10.6690, longitude: 122.9420 },
    { latitude: 10.6710, longitude: 122.9420 },
  ];
  assert.equal(firstHighwayTravelConflict(along, [highway])?.restriction.id,
    'burgos-extension');
  assert.equal(firstHighwayTravelConflict(crossing, [highway]), null);
});

test('both retained polygon types reject pickup or destination endpoints', () => {
  for (const [type, id] of [
    ['no_service_area', 'closed-terminal'],
    ['restricted_crossing', 'downtown-driving-ban'],
  ]) {
    const restriction = {
      id,
      type,
      isActive: true,
      ...firestoreRestrictionGeometry([square], 'polygon'),
    };
    assert.equal(
      firstNoServiceEndpointConflict(
        { latitude: 10.67, longitude: 122.95 },
        { latitude: 10.70, longitude: 122.98 },
        [restriction],
      )?.id,
      id,
    );
  }
});

test('Google encoded polylines decode to latitude/longitude points', () => {
  assert.deepEqual(decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@'), [
    { latitude: 38.5, longitude: -120.2 },
    { latitude: 40.7, longitude: -120.95 },
    { latitude: 43.252, longitude: -126.453 },
  ]);
});
