'use strict';

const crypto = require('node:crypto');

const BOOKING_STATUS = Object.freeze({
  pending: 'pending',
  driverAssigned: 'driverAssigned',
  driverArriving: 'driverArriving',
  passengerOnBoard: 'passengerOnBoard',
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

function pickupPinHash(bookingId, pin) {
  return crypto
    .createHash('sha256')
    .update(`${bookingId}:${pin}`)
    .digest('hex');
}

function randomPickupPin() {
  return String(crypto.randomInt(0, 10000)).padStart(4, '0');
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

module.exports = {
  BOOKING_STATUS,
  TRANSITIONS,
  activeStatus,
  canTransition,
  distanceMeters,
  normalizeCoordinate,
  pickupPinHash,
  randomPickupPin,
  validBookingId,
  validOperationId,
};
