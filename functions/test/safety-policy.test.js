'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  SOS_ACKNOWLEDGEMENT_MS,
  SOS_UNRESPONSIVE_MS,
  canCancelBookingForSafety,
  escalationLevel,
  nextAdminResponseStatus,
  normalizedResponseStatus,
} = require('../safety-policy');

test('legacy open incidents normalize to reported', () => {
  assert.equal(normalizedResponseStatus({ status: 'open' }), 'reported');
  assert.equal(normalizedResponseStatus({ status: 'resolved' }), 'resolved');
});

test('admin response lifecycle does not move a resolved incident backwards', () => {
  assert.equal(nextAdminResponseStatus('reported', 'acknowledge'), 'acknowledged');
  assert.equal(nextAdminResponseStatus('acknowledged', 'responding'), 'responding');
  assert.equal(nextAdminResponseStatus('responding', 'resolve'), 'resolved');
  assert.equal(nextAdminResponseStatus('resolved', 'responding'), null);
});

test('unacknowledged incidents escalate at two and five minutes', () => {
  const createdAtMs = 1_000;
  assert.equal(escalationLevel({
    createdAtMs,
    nowMs: createdAtMs + SOS_ACKNOWLEDGEMENT_MS - 1,
    responseStatus: 'reported',
  }), 0);
  assert.equal(escalationLevel({
    createdAtMs,
    nowMs: createdAtMs + SOS_ACKNOWLEDGEMENT_MS,
    responseStatus: 'reported',
  }), 1);
  assert.equal(escalationLevel({
    createdAtMs,
    nowMs: createdAtMs + SOS_UNRESPONSIVE_MS,
    responseStatus: 'reported',
  }), 2);
  assert.equal(escalationLevel({
    createdAtMs,
    nowMs: createdAtMs + SOS_UNRESPONSIVE_MS,
    responseStatus: 'acknowledged',
  }), 0);
});

test('five minutes never authorizes cancellation of an onboard ride', () => {
  const input = {
    incidentStatus: 'open',
    createdAtMs: 1_000,
    nowMs: 1_000 + SOS_UNRESPONSIVE_MS,
  };
  assert.equal(canCancelBookingForSafety({
    ...input,
    bookingStatus: 'driverArriving',
  }), true);
  assert.equal(canCancelBookingForSafety({
    ...input,
    bookingStatus: 'passengerOnBoard',
  }), false);
  assert.equal(canCancelBookingForSafety({
    ...input,
    bookingStatus: 'paymentConfirmation',
  }), false);
});
