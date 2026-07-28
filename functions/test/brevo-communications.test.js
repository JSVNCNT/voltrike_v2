'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  safetyAlertEmail,
  validEmail,
  verificationEmail,
} = require('../brevo-communications');

test('transactional email validation rejects malformed addresses', () => {
  assert.equal(validEmail('admin@voltrike.ph'), true);
  assert.equal(validEmail('not-an-email'), false);
});

test('verification template escapes names and retains the secure action link', () => {
  const message = verificationEmail({
    name: '<Admin>',
    verificationLink: 'https://example.test/action?code=abc',
  });
  assert.match(message.htmlContent, /&lt;Admin&gt;/);
  assert.match(message.htmlContent, /https:\/\/example\.test\/action\?code=abc/);
  assert.doesNotMatch(message.htmlContent, /Hello <Admin>/);
});

test('safety email contains operational context without participant secrets', () => {
  const message = safetyAlertEmail({
    recipientName: 'TODA Admin',
    eventLabel: 'SOS requires acknowledgement',
    adminPortalUrl: 'https://admin.example.test',
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
});
