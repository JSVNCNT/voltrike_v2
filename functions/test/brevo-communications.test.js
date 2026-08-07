'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  passwordResetEmail,
  safetyAlertEmail,
  validEmail,
  verificationEmail,
} = require('../brevo-communications');
const { safetyEmailDeliveryId } = require('../outbox-worker');

test('transactional email validation rejects malformed addresses', () => {
  assert.equal(validEmail('admin@voltrike.ph'), true);
  assert.equal(validEmail('not-an-email'), false);
});

test('verification template escapes names and retains the secure action link', () => {
  const message = verificationEmail({
    name: '<Admin>',
    verificationLink: 'https://example.test/action?code=abc',
    logoUrl: 'https://example.test/images/appLogo.png',
  });
  assert.match(message.htmlContent, /&lt;Admin&gt;/);
  assert.match(message.htmlContent, /https:\/\/example\.test\/action\?code=abc/);
  assert.doesNotMatch(message.htmlContent, /Hello <Admin>/);
  assert.match(message.htmlContent, /images\/appLogo\.png/);
  assert.match(message.textContent, /Verify email address:/);
});

test('password reset includes HTML and accessible plain text', () => {
  const message = passwordResetEmail({
    name: 'Passenger',
    resetLink: 'https://example.test/reset?code=secure',
    logoUrl: 'https://example.test/images/appLogo.png',
  });
  assert.match(message.subject, /Reset your VolTrike password/);
  assert.match(message.htmlContent, /reset\?code=secure/);
  assert.match(message.textContent, /Reset password:/);
  assert.match(message.textContent, /reset\?code=secure/);
});

test('safety email contains operational context without participant secrets', () => {
  const message = safetyAlertEmail({
    recipientName: 'TODA Admin',
    eventLabel: 'SOS requires acknowledgement',
    adminPortalUrl: 'https://admin.example.test',
    logoUrl: 'https://admin.example.test/images/appLogo.png',
    incident: {
      bookingId: 'booking-123',
      reporterRole: 'passenger',
      todaName: 'Central TODA',
      bookingStatus: 'driverArriving',
      pickupAddress: 'Pickup',
      destinationAddress: 'Destination',
      escalationLevel: 1,
    },
  });
  assert.match(message.subject, /Escalated VolTrike SOS/);
  assert.match(message.htmlContent, /booking-123/);
  assert.match(message.htmlContent, /Open Safety Incidents/);
  assert.match(message.textContent, /Booking: booking-123/);
  assert.doesNotMatch(message.textContent, /password/i);
});

test('safety email delivery IDs deduplicate one recipient per outbox event', () => {
  const first = safetyEmailDeliveryId('event-1', 'admin-1');
  assert.equal(first, safetyEmailDeliveryId('event-1', 'admin-1'));
  assert.notEqual(first, safetyEmailDeliveryId('event-2', 'admin-1'));
  assert.notEqual(first, safetyEmailDeliveryId('event-1', 'admin-2'));
});
