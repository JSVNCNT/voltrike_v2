'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  GOOGLE_ROUTES_FIELD_MASK,
  googleDrivingRouteRequest,
  googleHighwayRouteAdvisory,
} = require('../routes-policy');

test('Google routing requests alternatives with highway avoidance', () => {
  const request = googleDrivingRouteRequest(
    { latitude: 10.67, longitude: 122.95 },
    { latitude: 10.68, longitude: 122.96 },
  );
  assert.equal(request.travelMode, 'DRIVE');
  assert.equal(request.routingPreference, 'TRAFFIC_AWARE');
  assert.equal(request.computeAlternativeRoutes, true);
  assert.equal(request.routeModifiers.avoidHighways, true);
  assert.match(
    GOOGLE_ROUTES_FIELD_MASK,
    /routeRestrictionsPartiallyIgnored/,
  );
});

test('Google highway advisory remains explicitly unconfirmed', () => {
  const ignored = googleHighwayRouteAdvisory({
    travelAdvisory: {
      routeRestrictionsPartiallyIgnored: true,
    },
  });
  assert.equal(ignored.status, 'possibly_ignored');
  assert.equal(ignored.confirmedViolation, false);
  const accepted = googleHighwayRouteAdvisory({});
  assert.equal(
    accepted.status,
    'avoidance_not_reported_ignored',
  );
  assert.equal(accepted.confirmedViolation, false);
});
