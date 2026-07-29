'use strict';

const DRIVER_VIOLATION_EVENT_CLASS = Object.freeze({
  restrictedAreaEntry: 'restricted_area_entry',
  // Reserved for provider route advisories. It must never be presented as a
  // confirmed live road-entry violation without an independent trusted
  // source capable of proving road class and direction of travel.
  highwayRouteAdvisory: 'highway_route_advisory',
});

const DRIVER_VIOLATION_STATUS = Object.freeze({
  open: 'open',
  acknowledged: 'acknowledged',
  responding: 'responding',
  resolved: 'resolved',
  dismissed: 'dismissed',
});

const DRIVER_VIOLATION_ACTIONS = new Set([
  'acknowledge',
  'respond',
  'investigate',
  'resolve',
  'dismiss',
]);

const RESTRICTION_ENTRY_SAMPLE_COUNT = 2;
const RESTRICTION_EXIT_SAMPLE_COUNT = 2;
const RESTRICTION_REENTRY_COOLDOWN_MS = 60000;

function validIdentifier(value) {
  return typeof value === 'string' &&
    /^[A-Za-z0-9_-]{8,128}$/.test(value);
}

function normalizeDriverLocation(raw, {
  now = Date.now(),
  maximumAgeMs = 35000,
  maximumFutureMs = 10000,
  maximumAccuracyMeters = 100,
  requireObservedAt = false,
  maximumObservedAgeMs = maximumAgeMs,
} = {}) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new TypeError('A current driver location is required.');
  }
  const latitude = Number(raw.latitude);
  const longitude = Number(raw.longitude);
  const accuracy = Number(raw.accuracy);
  const publishedAt = Number(raw.timestamp ?? raw.updatedAt);
  const hasObservedAt = raw.observedAt !== undefined &&
    raw.observedAt !== null;
  const observedAt = hasObservedAt ? Number(raw.observedAt) : null;
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new TypeError('Driver location coordinates are invalid.');
  }
  if (!Number.isFinite(accuracy) || accuracy < 0 ||
      accuracy > maximumAccuracyMeters) {
    throw new TypeError(
      `Driver location accuracy must be within ${maximumAccuracyMeters} metres.`,
    );
  }
  if (!Number.isFinite(publishedAt) ||
      publishedAt < now - maximumAgeMs ||
      publishedAt > now + maximumFutureMs) {
    throw new TypeError('Driver location is stale or has a future timestamp.');
  }
  if (hasObservedAt && (!Number.isFinite(observedAt) ||
      observedAt > now + maximumFutureMs)) {
    throw new TypeError('Driver GPS observation has an invalid future time.');
  }
  if (requireObservedAt && (!Number.isFinite(observedAt) ||
      observedAt < now - maximumObservedAgeMs ||
      observedAt > now + maximumFutureMs)) {
    throw new TypeError(
      'A fresh GPS observedAt value is required for violation evidence.',
    );
  }
  if (raw.online !== true) {
    throw new TypeError('Driver must be online before reporting position.');
  }
  const bearingValue = Number(raw.bearing);
  const speedValue = Number(raw.speed);
  return {
    latitude,
    longitude,
    accuracy,
    bearing: Number.isFinite(bearingValue)
      ? ((bearingValue % 360) + 360) % 360
      : 0,
    speed: Number.isFinite(speedValue) && speedValue >= 0
      ? Math.min(speedValue, 80)
      : 0,
    timestamp: publishedAt,
    observedAt,
    online: true,
  };
}

function actorCanAccessDriverViolation(actor, violation) {
  if (!actor || actor.isActive === false || !violation) return false;
  if (actor.role === 'developer_admin') return true;
  if (actor.role === 'toda_admin') {
    return typeof actor.todaId === 'string' &&
      actor.todaId.length > 0 &&
      actor.todaId === violation.ownerTodaId;
  }
  return actor.role === 'driver' && actor.uid === violation.driverId;
}

function driverViolationContext(bookingId, bookingStatus) {
  if (typeof bookingId !== 'string' || bookingId.length === 0) {
    return 'online_idle';
  }
  return ['passengerOnBoard', 'paymentConfirmation']
    .includes(bookingStatus)
    ? 'active_trip'
    : 'to_pickup';
}

function nextDriverViolationStatus(currentStatus, rawAction) {
  const action = rawAction === 'investigate' ? 'respond' : rawAction;
  if (!DRIVER_VIOLATION_ACTIONS.has(rawAction)) {
    throw new TypeError('Unsupported driver violation action.');
  }
  if ([
    DRIVER_VIOLATION_STATUS.resolved,
    DRIVER_VIOLATION_STATUS.dismissed,
  ].includes(currentStatus)) {
    throw new TypeError('This driver violation case is already closed.');
  }
  if (action === 'acknowledge') {
    return currentStatus === DRIVER_VIOLATION_STATUS.responding
      ? DRIVER_VIOLATION_STATUS.responding
      : DRIVER_VIOLATION_STATUS.acknowledged;
  }
  if (action === 'respond') return DRIVER_VIOLATION_STATUS.responding;
  if (action === 'resolve') return DRIVER_VIOLATION_STATUS.resolved;
  return DRIVER_VIOLATION_STATUS.dismissed;
}

function nextRestrictionObservation(state = {}, {
  inside,
  observedAt,
  now = Date.now(),
  entrySampleCount = RESTRICTION_ENTRY_SAMPLE_COUNT,
  exitSampleCount = RESTRICTION_EXIT_SAMPLE_COUNT,
  reentryCooldownMs = RESTRICTION_REENTRY_COOLDOWN_MS,
}) {
  const previousObservedAt = Number(state.lastProcessedObservedAt);
  if (!Number.isFinite(observedAt) ||
      (Number.isFinite(previousObservedAt) &&
        observedAt <= previousObservedAt)) {
    return { transition: 'ignored', updates: {} };
  }
  const common = {
    lastProcessedObservedAt: observedAt,
    lastObservedFixAt: observedAt,
  };
  if (inside) {
    if (state.inside === true) {
      return {
        transition: 'inside',
        updates: {
          ...common,
          candidateOutsideSamples: 0,
          lastInsideObservedAt: observedAt,
        },
      };
    }
    const previousInsideObservedAt = Number(
      state.lastInsideObservedAt,
    );
    const previousSamples = Number(state.candidateInsideSamples || 0);
    const candidateInsideSamples =
      Number.isFinite(previousInsideObservedAt) &&
      observedAt > previousInsideObservedAt
        ? previousSamples + 1
        : 1;
    const firstInsideObservedAt = previousSamples > 0 &&
      Number.isFinite(Number(state.firstInsideObservedAt))
      ? Number(state.firstInsideObservedAt)
      : observedAt;
    const candidateUpdates = {
      ...common,
      inside: false,
      candidateInsideSamples,
      firstInsideObservedAt,
      lastInsideObservedAt: observedAt,
      candidateOutsideSamples: 0,
    };
    if (candidateInsideSamples < entrySampleCount) {
      return {
        transition: 'candidate_entry',
        updates: candidateUpdates,
      };
    }
    const reentryAllowedAtMillis = Number(state.reentryAllowedAtMillis || 0);
    if (Number.isFinite(reentryAllowedAtMillis) &&
        now < reentryAllowedAtMillis) {
      return {
        transition: 'reentry_cooldown',
        updates: {
          ...candidateUpdates,
          candidateInsideSamples: entrySampleCount,
        },
      };
    }
    return {
      transition: 'enter',
      evidence: {
        sampleCount: candidateInsideSamples,
        firstObservedAt: firstInsideObservedAt,
        confirmingObservedAt: observedAt,
      },
      updates: {
        ...candidateUpdates,
        inside: true,
        candidateInsideSamples: 0,
        firstInsideObservedAt: null,
        candidateOutsideSamples: 0,
        reentryAllowedAtMillis: 0,
      },
    };
  }

  if (state.inside === true) {
    const previousOutsideObservedAt = Number(
      state.lastOutsideObservedAt,
    );
    const previousSamples = Number(state.candidateOutsideSamples || 0);
    const candidateOutsideSamples =
      Number.isFinite(previousOutsideObservedAt) &&
      observedAt > previousOutsideObservedAt
        ? previousSamples + 1
        : 1;
    const candidateUpdates = {
      ...common,
      candidateOutsideSamples,
      lastOutsideObservedAt: observedAt,
      candidateInsideSamples: 0,
      firstInsideObservedAt: null,
    };
    if (candidateOutsideSamples < exitSampleCount) {
      return {
        transition: 'candidate_exit',
        updates: candidateUpdates,
      };
    }
    return {
      transition: 'exit',
      updates: {
        ...candidateUpdates,
        inside: false,
        candidateOutsideSamples: 0,
        reentryAllowedAtMillis: now + reentryCooldownMs,
      },
    };
  }

  return {
    transition: 'outside',
    updates: {
      ...common,
      inside: false,
      candidateInsideSamples: 0,
      firstInsideObservedAt: null,
      candidateOutsideSamples: 0,
      lastOutsideObservedAt: observedAt,
    },
  };
}

module.exports = {
  DRIVER_VIOLATION_EVENT_CLASS,
  DRIVER_VIOLATION_STATUS,
  RESTRICTION_ENTRY_SAMPLE_COUNT,
  RESTRICTION_EXIT_SAMPLE_COUNT,
  RESTRICTION_REENTRY_COOLDOWN_MS,
  actorCanAccessDriverViolation,
  driverViolationContext,
  nextDriverViolationStatus,
  nextRestrictionObservation,
  normalizeDriverLocation,
  validIdentifier,
};
