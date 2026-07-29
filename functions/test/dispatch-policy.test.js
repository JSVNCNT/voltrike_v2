'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { compareDispatchClaims } = require('../dispatch-policy');

test('accepted candidates are awarded by service priority then distance', () => {
  const claims = [
    {
      driverId: 'far',
      servicePriority: 0,
      distanceMeters: 800,
      acceptedAt: 100,
    },
    {
      driverId: 'near',
      servicePriority: 0,
      distanceMeters: 250,
      acceptedAt: 200,
    },
    {
      driverId: 'outside-priority',
      servicePriority: 1,
      distanceMeters: 50,
      acceptedAt: 50,
    },
  ].sort(compareDispatchClaims);
  assert.deepEqual(
    claims.map((claim) => claim.driverId),
    ['near', 'far', 'outside-priority'],
  );
});

test('accept time and driver ID provide stable equal-distance tie breakers', () => {
  const claims = [
    { driverId: 'b', distanceMeters: 100, acceptedAt: 200 },
    { driverId: 'c', distanceMeters: 100, acceptedAt: 100 },
    { driverId: 'a', distanceMeters: 100, acceptedAt: 200 },
  ].sort(compareDispatchClaims);
  assert.deepEqual(
    claims.map((claim) => claim.driverId),
    ['c', 'a', 'b'],
  );
});
