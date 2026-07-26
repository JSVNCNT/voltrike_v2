'use strict';

const BOOKING_STATUS = Object.freeze({
  pending: 'pending',
  driverAssigned: 'driverAssigned',
  driverArriving: 'driverArriving',
  passengerOnBoard: 'passengerOnBoard',
  paymentConfirmation: 'paymentConfirmation',
  completed: 'completed',
  cancelled: 'cancelled',
});

const TRANSITIONS = Object.freeze({
  [BOOKING_STATUS.pending]: new Set([
    BOOKING_STATUS.driverAssigned,
    BOOKING_STATUS.cancelled,
  ]),
  [BOOKING_STATUS.driverAssigned]: new Set([
    BOOKING_STATUS.driverArriving,
    BOOKING_STATUS.cancelled,
  ]),
  [BOOKING_STATUS.driverArriving]: new Set([
    BOOKING_STATUS.passengerOnBoard,
    BOOKING_STATUS.cancelled,
  ]),
  [BOOKING_STATUS.passengerOnBoard]: new Set([
    BOOKING_STATUS.paymentConfirmation,
  ]),
  [BOOKING_STATUS.paymentConfirmation]: new Set([
    BOOKING_STATUS.completed,
  ]),
  [BOOKING_STATUS.completed]: new Set(),
  [BOOKING_STATUS.cancelled]: new Set(),
});

function canTransition(current, next) {
  return TRANSITIONS[current]?.has(next) === true;
}

function activeStatus(status) {
  return status !== BOOKING_STATUS.completed &&
    status !== BOOKING_STATUS.cancelled;
}

function validOperationId(value) {
  return typeof value === 'string' &&
    /^[A-Za-z0-9_-]{8,128}$/.test(value);
}

function validBookingId(value) {
  return typeof value === 'string' &&
    /^[A-Za-z0-9_-]{8,128}$/.test(value);
}

function normalizeCoordinate(value, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new TypeError(`${name} coordinates are required.`);
  }
  const latitude = Number(value.latitude);
  const longitude = Number(value.longitude);
  if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    throw new TypeError(`${name} coordinates are invalid.`);
  }
  return { latitude, longitude };
}

function distanceMeters(pointA, pointB) {
  const earthRadiusMeters = 6371000;
  const radians = (degrees) => degrees * Math.PI / 180;
  const latitudeDelta = radians(pointB.latitude - pointA.latitude);
  const longitudeDelta = radians(pointB.longitude - pointA.longitude);
  const latitudeA = radians(pointA.latitude);
  const latitudeB = radians(pointB.latitude);
  const haversine = Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(latitudeA) * Math.cos(latitudeB) *
    Math.sin(longitudeDelta / 2) ** 2;
  return earthRadiusMeters * 2 *
    Math.atan2(Math.sqrt(haversine), Math.sqrt(1 - haversine));
}

function nextRatingAggregate(currentAverage, currentCount, newRating) {
  const average = Number(currentAverage);
  const count = Number(currentCount);
  const rating = Number(newRating);
  if (!Number.isFinite(average) || !Number.isInteger(count) || count < 0 ||
      !Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new TypeError('Rating aggregate values are invalid.');
  }
  const nextCount = count + 1;
  const nextAverage = Math.round(
    ((average * count + rating) / nextCount) * 100,
  ) / 100;
  return { rating: nextAverage, ratingCount: nextCount };
}

module.exports = {
  BOOKING_STATUS,
  TRANSITIONS,
  activeStatus,
  canTransition,
  distanceMeters,
  nextRatingAggregate,
  normalizeCoordinate,
  validBookingId,
  validOperationId,
};
