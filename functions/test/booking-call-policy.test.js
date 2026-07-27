'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  CALL_DURATION_MS,
  CALL_INVITATION_MS,
  CALL_STATUS,
  callAllowedForBookingStatus,
  effectiveCallStatus,
  participantRole,
  recipientFor,
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
