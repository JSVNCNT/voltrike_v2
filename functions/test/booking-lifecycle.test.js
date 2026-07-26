'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  BOOKING_STATUS,
  activeStatus,
  canTransition,
  distanceMeters,
  normalizeCoordinate,
  pickupPinHash,
  validBookingId,
  validOperationId,
} = require('../booking-lifecycle');

test('canonical transitions allow only forward lifecycle changes', () => {
  assert.equal(canTransition(BOOKING_STATUS.pending, BOOKING_STATUS.driverAssigned), true);
  assert.equal(canTransition(BOOKING_STATUS.driverAssigned, BOOKING_STATUS.driverArriving), true);
  assert.equal(canTransition(BOOKING_STATUS.driverArriving, BOOKING_STATUS.passengerOnBoard), true);
  assert.equal(canTransition(BOOKING_STATUS.passengerOnBoard, BOOKING_STATUS.completed), true);
  assert.equal(canTransition(BOOKING_STATUS.pending, BOOKING_STATUS.completed), false);
  assert.equal(canTransition(BOOKING_STATUS.completed, BOOKING_STATUS.pending), false);
});

test('terminal status detection is stable', () => {
  assert.equal(activeStatus(BOOKING_STATUS.pending), true);
  assert.equal(activeStatus(BOOKING_STATUS.completed), false);
  assert.equal(activeStatus(BOOKING_STATUS.cancelled), false);
});

test('operation and booking IDs reject unsafe values', () => {
  assert.equal(validBookingId('booking_12345678'), true);
  assert.equal(validOperationId('operation-12345678'), true);
  assert.equal(validBookingId('../booking'), false);
  assert.equal(validOperationId('short'), false);
});

test('coordinates are normalized and bounded', () => {
  assert.deepEqual(
    normalizeCoordinate({ latitude: '10.67', longitude: 122.95 }, 'Pickup'),
    { latitude: 10.67, longitude: 122.95 },
  );
  assert.throws(
    () => normalizeCoordinate({ latitude: 100, longitude: 122.95 }, 'Pickup'),
    /invalid/,
  );
});

test('pickup PIN hashing is deterministic and booking scoped', () => {
  assert.equal(pickupPinHash('booking-a', '1234'), pickupPinHash('booking-a', '1234'));
  assert.notEqual(pickupPinHash('booking-a', '1234'), pickupPinHash('booking-b', '1234'));
});

test('backend proximity calculation supports the five kilometre boundary', () => {
  const pickup = { latitude: 10.6765, longitude: 122.9509 };
  const nearby = { latitude: 10.6855, longitude: 122.9509 };
  const far = { latitude: 10.75, longitude: 122.9509 };
  assert.ok(distanceMeters(pickup, nearby) < 5000);
  assert.ok(distanceMeters(pickup, far) > 5000);
});
