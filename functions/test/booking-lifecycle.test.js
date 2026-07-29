'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  BOOKING_STATUS,
  activeStatus,
  cancellationExpectedStatuses,
  canTransition,
  distanceMeters,
  nextRatingAggregate,
  normalizeCoordinate,
  validBookingId,
  validOperationId,
} = require('../booking-lifecycle');

test('canonical transitions allow only forward lifecycle changes', () => {
  assert.equal(canTransition(BOOKING_STATUS.pending, BOOKING_STATUS.driverAssigned), true);
  assert.equal(canTransition(BOOKING_STATUS.driverAssigned, BOOKING_STATUS.driverArriving), true);
  assert.equal(canTransition(BOOKING_STATUS.driverArriving, BOOKING_STATUS.passengerOnBoard), true);
  assert.equal(canTransition(BOOKING_STATUS.passengerOnBoard, BOOKING_STATUS.paymentConfirmation), true);
  assert.equal(canTransition(BOOKING_STATUS.paymentConfirmation, BOOKING_STATUS.completed), true);
  assert.equal(canTransition(BOOKING_STATUS.pending, BOOKING_STATUS.completed), false);
  assert.equal(canTransition(BOOKING_STATUS.completed, BOOKING_STATUS.pending), false);
});

test('terminal status detection is stable', () => {
  assert.equal(activeStatus(BOOKING_STATUS.pending), true);
  assert.equal(activeStatus(BOOKING_STATUS.completed), false);
  assert.equal(activeStatus(BOOKING_STATUS.cancelled), false);
});

test('search timeout can cancel only a still-pending passenger request', () => {
  assert.deepEqual(
    cancellationExpectedStatuses({
      isDriver: false,
      cancellationCode: 'search_timeout',
    }),
    [BOOKING_STATUS.pending],
  );
  assert.deepEqual(
    cancellationExpectedStatuses({
      isDriver: false,
      cancellationCode: 'cancelled_by_passenger',
    }),
    [
      BOOKING_STATUS.pending,
      BOOKING_STATUS.driverAssigned,
      BOOKING_STATUS.driverArriving,
    ],
  );
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

test('backend proximity calculation supports the five kilometre boundary', () => {
  const pickup = { latitude: 10.6765, longitude: 122.9509 };
  const nearby = { latitude: 10.6855, longitude: 122.9509 };
  const far = { latitude: 10.75, longitude: 122.9509 };
  assert.ok(distanceMeters(pickup, nearby) < 5000);
  assert.ok(distanceMeters(pickup, far) > 5000);
});

test('rating aggregation increments once and rounds to two decimals', () => {
  assert.deepEqual(nextRatingAggregate(4.9, 12, 5), {
    rating: 4.91,
    ratingCount: 13,
  });
  assert.deepEqual(nextRatingAggregate(0, 0, 3), {
    rating: 3,
    ratingCount: 1,
  });
  assert.throws(() => nextRatingAggregate(4, 2, 0), /invalid/);
});
