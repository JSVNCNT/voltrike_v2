'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  actionableSafetyEvent,
  bookingNotificationStatus,
  staleNotificationReason,
} = require('../outbox-worker');

test('live notification events are skipped after their delivery window', () => {
  const now = Date.parse('2026-08-07T08:00:00Z');
  assert.equal(staleNotificationReason({
    type: 'booking.driverAssigned',
    createdAt: '2026-08-07T07:44:59Z',
  }, now), 'stale-notification-event');
  assert.equal(staleNotificationReason({
    type: 'booking.driverAssigned',
    createdAt: '2026-08-07T07:50:00Z',
  }, now), null);
  assert.equal(staleNotificationReason({
    type: 'call.ringing',
    createdAt: '2026-08-07T07:57:59Z',
  }, now), 'stale-notification-event');
});

test('booking notification uses the recorded transition instead of current projection', () => {
  assert.equal(bookingNotificationStatus({
    type: 'booking.driverAssigned',
    payload: { status: 'driverAssigned' },
  }), 'driverAssigned');
  assert.equal(bookingNotificationStatus({
    type: 'booking.receipt',
    payload: { status: 'completed' },
  }), 'completed');
  assert.equal(bookingNotificationStatus({
    type: 'booking.created',
    payload: { status: 'pending' },
  }), '');
});

test('SOS creation and escalation notify only while the incident is actionable', () => {
  assert.equal(actionableSafetyEvent('safety.sos.created', {
    status: 'open', responseStatus: 'reported',
  }), true);
  assert.equal(actionableSafetyEvent('safety.escalated', {
    status: 'reporter_safe', responseStatus: 'resolved',
  }), false);
  assert.equal(actionableSafetyEvent('safety.sos.safe', {
    status: 'reporter_safe', responseStatus: 'resolved',
  }), true);
});
