'use strict';

const DISTANCE_BAND_METERS = 100;
const RELIABILITY_PRIOR_COMPLETIONS = 9;
const RELIABILITY_PRIOR_TOTAL = 10;
const QUALITY_PRIOR_MEAN = 4.5;
const QUALITY_PRIOR_WEIGHT = 10;
const dispatchDateFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Asia/Manila',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

function timestampMillis(value) {
  if (value != null && typeof value.toMillis === 'function') {
    return value.toMillis();
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return Number.POSITIVE_INFINITY;
}

function nonNegativeNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : fallback;
}

function nonNegativeInteger(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 ? parsed : fallback;
}

function dispatchDateKey(now = Date.now()) {
  const values = Object.fromEntries(
    dispatchDateFormatter
      .formatToParts(new Date(now))
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return `${values.year}-${values.month}-${values.day}`;
}

function driverDispatchStats(driver, now = Date.now()) {
  const source = driver?.dispatchStats != null &&
      typeof driver.dispatchStats === 'object' &&
      !Array.isArray(driver.dispatchStats)
    ? driver.dispatchStats
    : {};
  const dateKey = dispatchDateKey(now);
  return {
    dailyAwardDate: dateKey,
    dailyAwardCount: source.dailyAwardDate === dateKey
      ? nonNegativeInteger(source.dailyAwardCount)
      : 0,
    assignmentCount: nonNegativeInteger(source.assignmentCount),
    completedAssignments: nonNegativeInteger(source.completedAssignments),
    cancellationCount: nonNegativeInteger(source.cancellationCount),
    driverFaultCancellations:
      nonNegativeInteger(source.driverFaultCancellations),
  };
}

function nextDriverDispatchStats(driver, outcome, now = Date.now()) {
  const stats = driverDispatchStats(driver, now);
  if (outcome === 'assigned') {
    stats.dailyAwardCount += 1;
    stats.assignmentCount += 1;
  } else if (outcome === 'completed') {
    stats.completedAssignments += 1;
  } else if (outcome === 'cancelled') {
    stats.cancellationCount += 1;
  } else if (outcome === 'driver_fault_cancelled') {
    stats.cancellationCount += 1;
    stats.driverFaultCancellations += 1;
  }
  return stats;
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value));
}

function roundedScore(value) {
  return Math.round(value * 1000000) / 1000000;
}

function smoothedReliability({
  completedAssignments = 0,
  driverFaultCancellations = 0,
} = {}) {
  const completed = nonNegativeInteger(completedAssignments);
  const driverFaults = nonNegativeInteger(driverFaultCancellations);
  return roundedScore(
    (RELIABILITY_PRIOR_COMPLETIONS + completed) /
    (RELIABILITY_PRIOR_TOTAL + completed + driverFaults),
  );
}

function smoothedQuality({
  rating = 0,
  ratingCount = 0,
} = {}) {
  const count = nonNegativeInteger(ratingCount);
  const average = count > 0
    ? clamp(nonNegativeNumber(rating), 0, 5)
    : QUALITY_PRIOR_MEAN;
  return roundedScore(
    (QUALITY_PRIOR_MEAN * QUALITY_PRIOR_WEIGHT + average * count) /
    (QUALITY_PRIOR_WEIGHT + count),
  );
}

function dispatchScoreSnapshot(candidate = {}) {
  const distanceMeters = nonNegativeNumber(
    candidate.distanceMeters,
    Number.POSITIVE_INFINITY,
  );
  const servicePriority = nonNegativeInteger(
    candidate.servicePriority,
    Number.MAX_SAFE_INTEGER,
  );
  const dailyAwards = nonNegativeInteger(candidate.dailyAwards);
  const reliabilityScore = Number.isFinite(
    Number(candidate.reliabilityScore),
  )
    ? clamp(Number(candidate.reliabilityScore), 0, 1)
    : smoothedReliability(candidate);
  const qualityScore = Number.isFinite(Number(candidate.qualityScore))
    ? clamp(Number(candidate.qualityScore), 0, 5)
    : smoothedQuality(candidate);
  return {
    version: 3,
    servicePriority,
    distanceBandMeters: DISTANCE_BAND_METERS,
    distanceBand: Number.isFinite(distanceMeters)
      ? Math.floor(distanceMeters / DISTANCE_BAND_METERS)
      : Number.MAX_SAFE_INTEGER,
    distanceMeters,
    dailyAwards,
    reliabilityScore: roundedScore(reliabilityScore),
    qualityScore: roundedScore(qualityScore),
  };
}

function bookingDriverServicePriority(booking = {}, todaId) {
  if (typeof todaId !== 'string' || todaId.trim().length === 0) return null;
  const primaryTodaIds = Array.isArray(booking.primaryTodaIds)
    ? booking.primaryTodaIds
    : [];
  const secondaryTodaIds = Array.isArray(booking.secondaryTodaIds)
    ? booking.secondaryTodaIds
    : [];
  if (primaryTodaIds.length > 0) {
    if (primaryTodaIds.includes(todaId)) return 0;
    if (secondaryTodaIds.includes(todaId)) return 1;
    return booking.allowAnyActiveToda === true ? 2 : null;
  }
  if (booking.allowAnyActiveToda === true) return 0;

  // Legacy bookings used an empty eligible list for open dispatch.
  const legacyEligibleTodaIds = Array.isArray(booking.eligibleTodaIds)
    ? booking.eligibleTodaIds
    : [];
  if (legacyEligibleTodaIds.length === 0) return 0;
  return legacyEligibleTodaIds.includes(todaId) ? 0 : null;
}

function compareDispatchClaims(a, b) {
  const scoreA = dispatchScoreSnapshot(a);
  const scoreB = dispatchScoreSnapshot(b);
  if (scoreA.servicePriority !== scoreB.servicePriority) {
    return scoreA.servicePriority - scoreB.servicePriority;
  }
  if (scoreA.distanceBand !== scoreB.distanceBand) {
    return scoreA.distanceBand - scoreB.distanceBand;
  }
  if (scoreA.dailyAwards !== scoreB.dailyAwards) {
    return scoreA.dailyAwards - scoreB.dailyAwards;
  }
  if (scoreA.reliabilityScore !== scoreB.reliabilityScore) {
    return scoreB.reliabilityScore - scoreA.reliabilityScore;
  }
  if (scoreA.qualityScore !== scoreB.qualityScore) {
    return scoreB.qualityScore - scoreA.qualityScore;
  }
  if (scoreA.distanceMeters !== scoreB.distanceMeters) {
    return scoreA.distanceMeters - scoreB.distanceMeters;
  }
  const acceptedAtA = timestampMillis(a.acceptedAt);
  const acceptedAtB = timestampMillis(b.acceptedAt);
  if (acceptedAtA !== acceptedAtB) return acceptedAtA - acceptedAtB;
  return String(a.driverId || '').localeCompare(String(b.driverId || ''));
}

function selectDispatchBatch(candidates, maximumSize = 5) {
  const limit = nonNegativeInteger(maximumSize);
  if (!Array.isArray(candidates) || limit === 0) return [];
  const ordered = [...candidates].sort(compareDispatchClaims);
  if (ordered.length <= limit) return ordered;

  // A fully global slice can starve secondary and fallback TODAs before they
  // ever get a chance to accept. Reserve the physically nearest driver from
  // each existing lower-priority tier, then fill the remaining places using
  // the same comparator used for the final award.
  const reserved = [];
  for (const priority of [1, 2]) {
    if (reserved.length >= limit) break;
    const tier = ordered
      .filter((candidate) =>
        dispatchScoreSnapshot(candidate).servicePriority === priority)
      .sort((a, b) => {
        const distanceDifference =
          dispatchScoreSnapshot(a).distanceMeters -
          dispatchScoreSnapshot(b).distanceMeters;
        return distanceDifference !== 0
          ? distanceDifference
          : compareDispatchClaims(a, b);
      });
    if (tier.length > 0) reserved.push(tier[0]);
  }

  const selected = new Set(reserved);
  const result = ordered
    .filter((candidate) => !selected.has(candidate))
    .slice(0, limit - reserved.length)
    .concat(reserved);
  return result.sort(compareDispatchClaims);
}

module.exports = {
  DISTANCE_BAND_METERS,
  bookingDriverServicePriority,
  compareDispatchClaims,
  dispatchDateKey,
  dispatchScoreSnapshot,
  driverDispatchStats,
  nextDriverDispatchStats,
  selectDispatchBatch,
  smoothedQuality,
  smoothedReliability,
  timestampMillis,
};
