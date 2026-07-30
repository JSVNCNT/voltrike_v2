'use strict';

const CALL_STATUS = Object.freeze({
  ringing: 'ringing',
  accepted: 'accepted',
  declined: 'declined',
  ended: 'ended',
  expired: 'expired',
});

const CALL_INVITATION_MS = 30_000;
const CALL_DURATION_MS = 120_000;

const CALLABLE_BOOKING_STATUSES = new Set([
  'driverAssigned',
  'driverArriving',
  'passengerOnBoard',
]);

const TERMINAL_CALL_STATUSES = new Set([
  CALL_STATUS.declined,
  CALL_STATUS.ended,
  CALL_STATUS.expired,
]);

function callAllowedForBookingStatus(status) {
  return CALLABLE_BOOKING_STATUSES.has(status);
}

function terminalCallStatus(status) {
  return TERMINAL_CALL_STATUSES.has(status);
}

function participantRole(booking, uid) {
  if (booking?.passengerId === uid) return 'passenger';
  if (booking?.driverId === uid) return 'driver';
  return null;
}

function recipientFor(booking, callerId) {
  if (booking?.passengerId === callerId) return booking.driverId || null;
  if (booking?.driverId === callerId) return booking.passengerId || null;
  return null;
}

function timestampMillis(value) {
  if (value != null && typeof value.toMillis === 'function') {
    const millis = value.toMillis();
    return Number.isFinite(millis) ? millis : null;
  }
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  return null;
}

function effectiveCallStatus(call, nowMillis = Date.now()) {
  if (!call || typeof call !== 'object') return null;
  if (call.status === CALL_STATUS.ringing) {
    const expiresAt = timestampMillis(call.expiresAt);
    if (expiresAt != null && expiresAt <= nowMillis) {
      return CALL_STATUS.expired;
    }
  }
  if (call.status === CALL_STATUS.accepted) {
    const endsAt = timestampMillis(call.endsAt);
    if (endsAt != null && endsAt <= nowMillis) {
      return CALL_STATUS.ended;
    }
  }
  return call.status || null;
}

function remainingCallSeconds(call, nowMillis = Date.now()) {
  if (effectiveCallStatus(call, nowMillis) !== CALL_STATUS.accepted) {
    return null;
  }
  const endsAt = timestampMillis(call?.endsAt);
  if (endsAt == null || endsAt <= nowMillis) return null;
  return Math.max(1, Math.ceil((endsAt - nowMillis) / 1000));
}

function acceptedCallNeedsScheduledEnd(
  call,
  expectedCallId,
  nowMillis = Date.now(),
) {
  return call?.callId === expectedCallId &&
    call.status === CALL_STATUS.accepted &&
    effectiveCallStatus(call, nowMillis) === CALL_STATUS.ended;
}

module.exports = {
  CALL_DURATION_MS,
  CALL_INVITATION_MS,
  CALL_STATUS,
  CALLABLE_BOOKING_STATUSES,
  acceptedCallNeedsScheduledEnd,
  callAllowedForBookingStatus,
  effectiveCallStatus,
  participantRole,
  recipientFor,
  remainingCallSeconds,
  terminalCallStatus,
  timestampMillis,
};
