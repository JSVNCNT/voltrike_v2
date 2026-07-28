'use strict';

const SOS_ACKNOWLEDGEMENT_MS = 2 * 60 * 1000;
const SOS_UNRESPONSIVE_MS = 5 * 60 * 1000;

const SAFETY_RESPONSE_STATUS = Object.freeze({
  reported: 'reported',
  acknowledged: 'acknowledged',
  responding: 'responding',
  resolved: 'resolved',
});

function normalizedResponseStatus(incident) {
  if (Object.values(SAFETY_RESPONSE_STATUS).includes(incident?.responseStatus)) {
    return incident.responseStatus;
  }
  if (incident?.status === 'resolved' ||
      incident?.status === 'reporter_safe') {
    return SAFETY_RESPONSE_STATUS.resolved;
  }
  return SAFETY_RESPONSE_STATUS.reported;
}

function nextAdminResponseStatus(current, action) {
  const status = normalizedResponseStatus({ responseStatus: current });
  if (action === 'acknowledge') {
    return status === SAFETY_RESPONSE_STATUS.reported
      ? SAFETY_RESPONSE_STATUS.acknowledged
      : status;
  }
  if (action === 'responding') {
    if (status === SAFETY_RESPONSE_STATUS.resolved) return null;
    return SAFETY_RESPONSE_STATUS.responding;
  }
  if (action === 'resolve') {
    return SAFETY_RESPONSE_STATUS.resolved;
  }
  return null;
}

function escalationLevel({
  createdAtMs,
  nowMs = Date.now(),
  responseStatus,
  currentLevel = 0,
}) {
  if (!Number.isFinite(createdAtMs) ||
      normalizedResponseStatus({ responseStatus }) !==
        SAFETY_RESPONSE_STATUS.reported) {
    return currentLevel;
  }
  const age = nowMs - createdAtMs;
  if (age >= SOS_UNRESPONSIVE_MS) return Math.max(currentLevel, 2);
  if (age >= SOS_ACKNOWLEDGEMENT_MS) return Math.max(currentLevel, 1);
  return currentLevel;
}

function canCancelBookingForSafety({
  incidentStatus,
  createdAtMs,
  nowMs = Date.now(),
  bookingStatus,
}) {
  return incidentStatus === 'open' &&
    Number.isFinite(createdAtMs) &&
    nowMs - createdAtMs >= SOS_UNRESPONSIVE_MS &&
    ['pending', 'driverAssigned', 'driverArriving'].includes(bookingStatus);
}

module.exports = {
  SAFETY_RESPONSE_STATUS,
  SOS_ACKNOWLEDGEMENT_MS,
  SOS_UNRESPONSIVE_MS,
  canCancelBookingForSafety,
  escalationLevel,
  nextAdminResponseStatus,
  normalizedResponseStatus,
};
