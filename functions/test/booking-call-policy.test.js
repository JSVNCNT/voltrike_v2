'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  CALL_DURATION_MS,
  CALL_INVITATION_MS,
  CALL_STATUS,
  acceptedCallNeedsScheduledEnd,
  callAllowedForBookingStatus,
  effectiveCallStatus,
  participantRole,
  recipientFor,
  remainingCallSeconds,
  terminalCallStatus,
} = require('../booking-call-policy');

test('voice calls are available through the onboard ride stage', () => {
  assert.equal(callAllowedForBookingStatus('driverAssigned'), true);
  assert.equal(callAllowedForBookingStatus('driverArriving'), true);
  assert.equal(callAllowedForBookingStatus('passengerOnBoard'), true);
  assert.equal(callAllowedForBookingStatus('pending'), false);
  assert.equal(callAllowedForBookingStatus('paymentConfirmation'), false);
  assert.equal(callAllowedForBookingStatus('completed'), false);
});

test('booking participant roles and recipients are symmetric', () => {
  const booking = {
    passengerId: 'passenger-1',
    driverId: 'driver-1',
  };
  assert.equal(participantRole(booking, 'passenger-1'), 'passenger');
  assert.equal(participantRole(booking, 'driver-1'), 'driver');
  assert.equal(participantRole(booking, 'stranger'), null);
  assert.equal(recipientFor(booking, 'passenger-1'), 'driver-1');
  assert.equal(recipientFor(booking, 'driver-1'), 'passenger-1');
  assert.equal(recipientFor(booking, 'stranger'), null);
});

test('invitation and accepted-call deadlines derive terminal state', () => {
  const now = 10_000;
  assert.equal(
    effectiveCallStatus({
      status: CALL_STATUS.ringing,
      expiresAt: now + CALL_INVITATION_MS,
    }, now),
    CALL_STATUS.ringing,
  );
  assert.equal(
    effectiveCallStatus({
      status: CALL_STATUS.ringing,
      expiresAt: now,
    }, now),
    CALL_STATUS.expired,
  );
  assert.equal(
    effectiveCallStatus({
      status: CALL_STATUS.accepted,
      endsAt: now + CALL_DURATION_MS,
    }, now),
    CALL_STATUS.accepted,
  );
  assert.equal(
    effectiveCallStatus({
      status: CALL_STATUS.accepted,
      endsAt: now,
    }, now),
    CALL_STATUS.ended,
  );
});

test('terminal call states are explicit', () => {
  assert.equal(terminalCallStatus(CALL_STATUS.declined), true);
  assert.equal(terminalCallStatus(CALL_STATUS.expired), true);
  assert.equal(terminalCallStatus(CALL_STATUS.ended), true);
  assert.equal(terminalCallStatus(CALL_STATUS.ringing), false);
  assert.equal(terminalCallStatus(CALL_STATUS.accepted), false);
});

test('participant credential TTL never outlives the accepted call', () => {
  const now = 10_000;
  assert.equal(
    remainingCallSeconds({
      status: CALL_STATUS.accepted,
      endsAt: now + 1_001,
    }, now),
    2,
  );
  assert.equal(
    remainingCallSeconds({
      status: CALL_STATUS.accepted,
      endsAt: now + 1,
    }, now),
    1,
  );
  assert.equal(
    remainingCallSeconds({
      status: CALL_STATUS.ringing,
      endsAt: now + CALL_DURATION_MS,
    }, now),
    null,
  );
  assert.equal(
    remainingCallSeconds({
      status: CALL_STATUS.accepted,
      endsAt: now,
    }, now),
    null,
  );
  assert.equal(
    remainingCallSeconds({
      status: CALL_STATUS.accepted,
      endsAt: 'invalid',
    }, now),
    null,
  );
});

test('scheduled expiry only transitions the same still-accepted call', () => {
  const now = 10_000;
  const expiredAccepted = {
    callId: 'call-current',
    status: CALL_STATUS.accepted,
    endsAt: now,
  };

  assert.equal(
    acceptedCallNeedsScheduledEnd(expiredAccepted, 'call-current', now),
    true,
  );
  assert.equal(
    acceptedCallNeedsScheduledEnd(expiredAccepted, 'call-replaced', now),
    false,
  );
  assert.equal(
    acceptedCallNeedsScheduledEnd({
      ...expiredAccepted,
      status: CALL_STATUS.ended,
    }, 'call-current', now),
    false,
  );
  assert.equal(
    acceptedCallNeedsScheduledEnd({
      ...expiredAccepted,
      endsAt: now + 1,
    }, 'call-current', now),
    false,
  );
});
