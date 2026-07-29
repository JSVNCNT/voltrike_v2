'use strict';

function timestampMillis(value) {
  if (value != null && typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return Number.POSITIVE_INFINITY;
}

function compareDispatchClaims(a, b) {
  const servicePriorityA = Number.isFinite(Number(a.servicePriority))
    ? Number(a.servicePriority)
    : 0;
  const servicePriorityB = Number.isFinite(Number(b.servicePriority))
    ? Number(b.servicePriority)
    : 0;
  if (servicePriorityA !== servicePriorityB) {
    return servicePriorityA - servicePriorityB;
  }
  const distanceA = Number.isFinite(Number(a.distanceMeters))
    ? Number(a.distanceMeters)
    : Number.POSITIVE_INFINITY;
  const distanceB = Number.isFinite(Number(b.distanceMeters))
    ? Number(b.distanceMeters)
    : Number.POSITIVE_INFINITY;
  if (distanceA !== distanceB) return distanceA - distanceB;
  const acceptedAtDifference =
    timestampMillis(a.acceptedAt) - timestampMillis(b.acceptedAt);
  if (acceptedAtDifference !== 0) return acceptedAtDifference;
  return String(a.driverId || '').localeCompare(String(b.driverId || ''));
}

module.exports = {
  compareDispatchClaims,
  timestampMillis,
};
