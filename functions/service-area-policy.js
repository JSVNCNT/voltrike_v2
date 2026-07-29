'use strict';

const GEOMETRY_VERSION = 2;
const MAX_AREAS = 20;
const MAX_POINTS = 200;

function isPointLike(value) {
  if (Array.isArray(value)) {
    return value.length === 2 &&
      value.every((coordinate) =>
        typeof coordinate === 'number' && Number.isFinite(coordinate));
  }
  return value != null && typeof value === 'object' &&
    !Array.isArray(value) &&
    (Object.hasOwn(value, 'latitude') || Object.hasOwn(value, 'lat')) &&
    (Object.hasOwn(value, 'longitude') || Object.hasOwn(value, 'lng'));
}

function normalizePoint(value, name = 'Point') {
  let latitude;
  let longitude;
  if (Array.isArray(value) && value.length === 2) {
    // Mapbox and the admin editor use GeoJSON coordinate order.
    [longitude, latitude] = value;
  } else if (value != null && typeof value === 'object' &&
      !Array.isArray(value)) {
    latitude = value.latitude ?? value.lat;
    longitude = value.longitude ?? value.lng;
  }
  if (typeof latitude !== 'number' || !Number.isFinite(latitude) ||
      latitude < -90 || latitude > 90 ||
      typeof longitude !== 'number' || !Number.isFinite(longitude) ||
      longitude < -180 || longitude > 180) {
    throw new TypeError(`${name} coordinates are invalid.`);
  }
  return { latitude, longitude };
}

function samePoint(a, b) {
  return a.latitude === b.latitude && a.longitude === b.longitude;
}

function normalizeArea(value, {
  name = 'Area',
  minimumPoints = 3,
  maximumPoints = MAX_POINTS,
} = {}) {
  const rawPoints = Array.isArray(value) ? value : value?.points;
  if (!Array.isArray(rawPoints)) {
    throw new TypeError(`${name} points are required.`);
  }
  const points = rawPoints.map((point, index) =>
    normalizePoint(point, `${name} point ${index + 1}`));
  if (points.length > minimumPoints &&
      samePoint(points[0], points[points.length - 1])) {
    points.pop();
  }
  if (points.length < minimumPoints || points.length > maximumPoints) {
    throw new TypeError(
      `${name} needs ${minimumPoints} to ${maximumPoints} points.`,
    );
  }
  return points;
}

function validatePolygon(points, name) {
  const unique = new Set(
    points.map((point) => `${point.latitude}:${point.longitude}`),
  );
  if (unique.size < 3) {
    throw new TypeError(`${name} needs at least three unique points.`);
  }
  let twiceSignedArea = 0;
  for (let index = 0; index < points.length; index += 1) {
    const current = points[index];
    const next = points[(index + 1) % points.length];
    if (samePoint(current, next)) {
      throw new TypeError(`${name} contains a duplicate edge point.`);
    }
    twiceSignedArea +=
      current.longitude * next.latitude -
      next.longitude * current.latitude;
  }
  // Roughly ten square metres at Philippine latitudes. This rejects
  // zero-area/near-collinear input without preventing small terminals.
  if (Math.abs(twiceSignedArea) / 2 < 1e-9) {
    throw new TypeError(`${name} area is too small.`);
  }
  for (let first = 0; first < points.length; first += 1) {
    const firstNext = (first + 1) % points.length;
    for (let second = first + 1; second < points.length; second += 1) {
      const secondNext = (second + 1) % points.length;
      const adjacent = first === second ||
        firstNext === second ||
        secondNext === first;
      if (adjacent) continue;
      if (segmentsIntersect(
        points[first],
        points[firstNext],
        points[second],
        points[secondNext],
      )) {
        throw new TypeError(`${name} must not self-intersect.`);
      }
    }
  }
}

function geometryAreaInputs(source) {
  if (Array.isArray(source?.areas) && source.areas.length > 0) {
    return isPointLike(source.areas[0]) ? [source.areas] : source.areas;
  }
  const fallback = source?.coordinates ?? source?.polygon;
  return fallback == null ? [] : [fallback];
}

function normalizeGeometry(source, {
  geometryType = 'polygon',
  maximumAreas = MAX_AREAS,
  maximumPoints = MAX_POINTS,
} = {}) {
  const rawAreas = geometryAreaInputs(source);
  const minimumPoints = geometryType === 'corridor' ? 2 : 3;
  if (rawAreas.length === 0 || rawAreas.length > maximumAreas) {
    throw new TypeError(
      geometryType === 'corridor'
        ? `A corridor needs one to ${maximumAreas} centrelines.`
        : `Geometry needs one to ${maximumAreas} areas.`,
    );
  }
  return rawAreas.map((area, index) => {
    const name = geometryType === 'corridor'
      ? 'Corridor'
      : `Area ${index + 1}`;
    const points = normalizeArea(area, {
      name,
      minimumPoints,
      maximumPoints,
    });
    if (geometryType === 'polygon') {
      validatePolygon(points, name);
    } else {
      for (let pointIndex = 1;
        pointIndex < points.length;
        pointIndex += 1) {
        if (samePoint(points[pointIndex - 1], points[pointIndex])) {
          throw new TypeError(
            `${name} contains consecutive duplicate points.`,
          );
        }
      }
    }
    return points;
  });
}

function firestoreGeometry(areas) {
  const normalized = normalizeGeometry({ areas });
  const storedAreas = normalized.map((points) => ({
    points: points.map((point) => ({
      latitude: point.latitude,
      longitude: point.longitude,
    })),
  }));
  return {
    geometryVersion: GEOMETRY_VERSION,
    polygon: storedAreas[0].points,
    areas: storedAreas,
  };
}

function firestoreRestrictionGeometry(areas, geometryType) {
  const normalized = normalizeGeometry(
    { areas },
    { geometryType },
  );
  const storedAreas = normalized.map((points) => ({
    points: points.map((point) => ({
      latitude: point.latitude,
      longitude: point.longitude,
    })),
  }));
  return {
    geometryVersion: GEOMETRY_VERSION,
    polygon: storedAreas[0].points,
    coordinates: storedAreas[0].points,
    areas: storedAreas,
  };
}

function pointOnSegment(point, start, end) {
  const cross = (point.longitude - start.longitude) *
      (end.latitude - start.latitude) -
    (point.latitude - start.latitude) *
      (end.longitude - start.longitude);
  if (Math.abs(cross) > 1e-9) return false;
  const dot = (point.longitude - start.longitude) *
      (end.longitude - start.longitude) +
    (point.latitude - start.latitude) *
      (end.latitude - start.latitude);
  if (dot < 0) return false;
  const squaredLength = (end.longitude - start.longitude) ** 2 +
    (end.latitude - start.latitude) ** 2;
  return dot <= squaredLength;
}

function pointInPolygon(rawPoint, rawPolygon) {
  const point = normalizePoint(rawPoint);
  const polygon = rawPolygon.map((entry) => normalizePoint(entry));
  if (polygon.length < 3) return false;
  let inside = false;
  for (let index = 0, previous = polygon.length - 1;
    index < polygon.length;
    previous = index++) {
    const start = polygon[previous];
    const end = polygon[index];
    if (pointOnSegment(point, start, end)) return true;
    const intersects =
      ((end.latitude > point.latitude) !==
        (start.latitude > point.latitude)) &&
      (point.longitude <
        (start.longitude - end.longitude) *
          (point.latitude - end.latitude) /
          (start.latitude - end.latitude) +
        end.longitude);
    if (intersects) inside = !inside;
  }
  return inside;
}

function normalizedRecordAreas(record, geometryType = 'polygon') {
  try {
    return normalizeGeometry(record, { geometryType });
  } catch {
    return [];
  }
}

function recordContainsPoint(record, point) {
  return normalizedRecordAreas(record)
    .some((polygon) => pointInPolygon(point, polygon));
}

function classifyTripCoverage(geofences, rawPickup, rawDestination) {
  const pickup = normalizePoint(rawPickup, 'Pickup');
  const destination = normalizePoint(rawDestination, 'Destination');
  const valid = geofences
    .filter((geofence) =>
      geofence?.isActive !== false &&
      typeof geofence?.todaId === 'string' &&
      geofence.todaId.trim().length > 0)
    .map((geofence) => ({
      geofence,
      areas: normalizedRecordAreas(geofence),
    }))
    .filter((entry) => entry.areas.length > 0);
  const configured = valid.length > 0;
  const matching = (point) => [...new Set(valid
    .filter(({ areas }) =>
      areas.some((polygon) => pointInPolygon(point, polygon)))
    .map(({ geofence }) => geofence.todaId.trim()))].sort();
  const pickupTodaIds = matching(pickup);
  const destinationTodaIds = matching(destination);
  const destinationSet = new Set(destinationTodaIds);
  const sharedTodaIds = pickupTodaIds
    .filter((todaId) => destinationSet.has(todaId));
  const primaryTodaIds = sharedTodaIds.length > 0
    ? sharedTodaIds
    : pickupTodaIds.length > 0
      ? pickupTodaIds
      : destinationTodaIds;
  const primarySet = new Set(primaryTodaIds);
  const secondaryTodaIds = [...new Set([
    ...pickupTodaIds,
    ...destinationTodaIds,
  ])]
    .filter((todaId) => !primarySet.has(todaId))
    .sort();
  const matchedTodaIds = new Set([
    ...pickupTodaIds,
    ...destinationTodaIds,
  ]);
  const geofenceRevisions = {};
  for (const { geofence } of valid) {
    const todaId = geofence.todaId.trim();
    if (!matchedTodaIds.has(todaId)) continue;
    const revision = Number(
      geofence.coverageRevision ?? geofence.revision ?? 0,
    );
    if (Number.isInteger(revision) && revision >= 0) {
      geofenceRevisions[todaId] = Math.max(
        geofenceRevisions[todaId] ?? 0,
        revision,
      );
    }
  }
  const isOutsideToda = configured && sharedTodaIds.length === 0;
  const coverageClass = !configured
    ? 'unconfigured_fallback'
    : sharedTodaIds.length > 0
      ? 'intra_toda'
      : pickupTodaIds.length > 0 && destinationTodaIds.length > 0
        ? 'cross_boundary'
        : pickupTodaIds.length > 0
          ? 'destination_outside_coverage'
          : destinationTodaIds.length > 0
            ? 'pickup_outside_coverage'
            : 'outside_network';
  // Compatibility summary of endpoint TODAs. Dispatch uses the explicit
  // primary/secondary tiers and may admit other active TODAs as fallback.
  const eligibleTodaIds = [...primaryTodaIds, ...secondaryTodaIds];
  return {
    configured,
    serviceable: true,
    isOutsideToda,
    coverageClass,
    pickupTodaIds,
    destinationTodaIds,
    sharedTodaIds,
    primaryTodaIds,
    secondaryTodaIds,
    allowAnyActiveToda: true,
    eligibleTodaIds,
    serviceTodaId:
      primaryTodaIds.length === 1 ? primaryTodaIds[0] : null,
    geofenceRevisions,
  };
}

function orientation(a, b, c) {
  const value = (b.longitude - a.longitude) *
      (c.latitude - a.latitude) -
    (b.latitude - a.latitude) *
      (c.longitude - a.longitude);
  if (Math.abs(value) <= 1e-12) return 0;
  return value > 0 ? 1 : -1;
}

function segmentsIntersect(a, b, c, d) {
  const abC = orientation(a, b, c);
  const abD = orientation(a, b, d);
  const cdA = orientation(c, d, a);
  const cdB = orientation(c, d, b);
  if (abC !== abD && cdA !== cdB) return true;
  return (abC === 0 && pointOnSegment(c, a, b)) ||
    (abD === 0 && pointOnSegment(d, a, b)) ||
    (cdA === 0 && pointOnSegment(a, c, d)) ||
    (cdB === 0 && pointOnSegment(b, c, d));
}

function routeIntersectsPolygon(route, polygon) {
  if (route.some((point) => pointInPolygon(point, polygon))) return true;
  for (let routeIndex = 1; routeIndex < route.length; routeIndex += 1) {
    for (let polygonIndex = 0;
      polygonIndex < polygon.length;
      polygonIndex += 1) {
      if (segmentsIntersect(
        route[routeIndex - 1],
        route[routeIndex],
        polygon[polygonIndex],
        polygon[(polygonIndex + 1) % polygon.length],
      )) {
        return true;
      }
    }
  }
  return false;
}

function pointToSegmentMeters(point, start, end) {
  const metresPerDegree = 111320;
  const referenceLatitude =
    (point.latitude + start.latitude + end.latitude) / 3 *
    Math.PI / 180;
  const longitudeScale = metresPerDegree * Math.cos(referenceLatitude);
  const px = (point.longitude - start.longitude) * longitudeScale;
  const py = (point.latitude - start.latitude) * metresPerDegree;
  const sx = (end.longitude - start.longitude) * longitudeScale;
  const sy = (end.latitude - start.latitude) * metresPerDegree;
  const lengthSquared = sx * sx + sy * sy;
  if (lengthSquared === 0) return Math.hypot(px, py);
  const projection = Math.max(
    0,
    Math.min(1, (px * sx + py * sy) / lengthSquared),
  );
  return Math.hypot(px - sx * projection, py - sy * projection);
}

function routeNearCorridor(route, centreline, bufferMeters) {
  for (let routeIndex = 1; routeIndex < route.length; routeIndex += 1) {
    for (let corridorIndex = 1;
      corridorIndex < centreline.length;
      corridorIndex += 1) {
      const routeStart = route[routeIndex - 1];
      const routeEnd = route[routeIndex];
      const corridorStart = centreline[corridorIndex - 1];
      const corridorEnd = centreline[corridorIndex];
      if (segmentsIntersect(
        routeStart,
        routeEnd,
        corridorStart,
        corridorEnd,
      ) ||
        pointToSegmentMeters(routeStart, corridorStart, corridorEnd) <=
          bufferMeters ||
        pointToSegmentMeters(routeEnd, corridorStart, corridorEnd) <=
          bufferMeters ||
        pointToSegmentMeters(corridorStart, routeStart, routeEnd) <=
          bufferMeters ||
        pointToSegmentMeters(corridorEnd, routeStart, routeEnd) <=
          bufferMeters) {
        return true;
      }
    }
  }
  return false;
}

function routeConflictsRestriction(rawRoute, restriction) {
  if (restriction?.isActive === false) return false;
  const route = rawRoute.map((point) => normalizePoint(point));
  if (route.length < 2) return false;
  const geometryType =
    restriction?.geometryType === 'corridor' ? 'corridor' : 'polygon';
  const areas = normalizedRecordAreas(restriction, geometryType);
  if (geometryType === 'corridor') {
    const bufferMeters = Number(restriction.bufferMeters);
    return areas.length > 0 &&
      Number.isFinite(bufferMeters) &&
      bufferMeters > 0 &&
      areas.some((centreline) =>
        routeNearCorridor(route, centreline, bufferMeters));
  }
  return areas.some((polygon) => routeIntersectsPolygon(route, polygon));
}

function firstRouteConflict(route, restrictions) {
  return restrictions.find((restriction) =>
    endpointBlockingRestriction(restriction) &&
    restriction?.geometryType !== 'corridor' &&
    routeConflictsRestriction(route, restriction)) ?? null;
}

function endpointBlockingRestriction(restriction) {
  return restriction?.isActive !== false &&
    ['no_service_area', 'restricted_crossing'].includes(restriction?.type);
}

function firstRestrictedEndpointConflict(
  pickup,
  destination,
  restrictions,
) {
  return restrictions.find((restriction) =>
    endpointBlockingRestriction(restriction) &&
    (recordContainsPoint(restriction, pickup) ||
      recordContainsPoint(restriction, destination))) ?? null;
}

// Compatibility alias retained for older imports while both polygon types
// now enforce the same no-pickup/no-drop-off policy.
const firstNoServiceEndpointConflict = firstRestrictedEndpointConflict;

function decodePolyline(encoded) {
  const points = [];
  let latitude = 0;
  let longitude = 0;
  let index = 0;
  while (index < encoded.length) {
    const nextValue = () => {
      let result = 0;
      let shift = 0;
      let byte;
      do {
        if (index >= encoded.length) {
          throw new TypeError('Encoded route polyline is invalid.');
        }
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      return (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
    };
    latitude += nextValue();
    longitude += nextValue();
    points.push({
      latitude: latitude / 1e5,
      longitude: longitude / 1e5,
    });
  }
  return points;
}

module.exports = {
  GEOMETRY_VERSION,
  classifyTripCoverage,
  decodePolyline,
  firstNoServiceEndpointConflict,
  firstRestrictedEndpointConflict,
  firstRouteConflict,
  firestoreGeometry,
  firestoreRestrictionGeometry,
  normalizeArea,
  normalizeGeometry,
  normalizePoint,
  pointInPolygon,
  recordContainsPoint,
  routeConflictsRestriction,
};
