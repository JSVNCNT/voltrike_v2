'use strict';

const DEFAULT_FARE = Object.freeze({
  version: 1,
  baseFare: 20,
  includedMeters: 1000,
  distanceStepMeters: 500,
  distanceStepPrice: 5,
  additionalPassengerFee: 40,
  baggageFee: 20,
  outsideTodaSurcharge: 20,
  currency: 'PHP',
});

function finiteNumber(value, fallback) {
  return typeof value === 'number' && Number.isFinite(value)
    ? value
    : fallback;
}

function positiveInteger(value, fallback) {
  return Number.isInteger(value) && value > 0 ? value : fallback;
}

function fareSnapshot(data) {
  const source = data || {};
  return {
    version: positiveInteger(source.version, DEFAULT_FARE.version),
    baseFare: finiteNumber(source.baseFare, DEFAULT_FARE.baseFare),
    includedMeters: positiveInteger(
      source.includedMeters,
      DEFAULT_FARE.includedMeters,
    ),
    distanceStepMeters: positiveInteger(
      source.distanceStepMeters,
      DEFAULT_FARE.distanceStepMeters,
    ),
    distanceStepPrice: finiteNumber(
      source.distanceStepPrice,
      DEFAULT_FARE.distanceStepPrice,
    ),
    additionalPassengerFee: finiteNumber(
      source.additionalPassengerFee,
      DEFAULT_FARE.additionalPassengerFee,
    ),
    baggageFee: finiteNumber(source.baggageFee, DEFAULT_FARE.baggageFee),
    outsideTodaSurcharge: finiteNumber(
      source.outsideTodaSurcharge,
      DEFAULT_FARE.outsideTodaSurcharge,
    ),
    currency: source.currency === 'PHP' ? source.currency : DEFAULT_FARE.currency,
  };
}

function calculateFare({
  config,
  distanceMeters,
  additionalPassengers = 0,
  baggageCount = 0,
  isOutsideToda = false,
}) {
  const snapshot = fareSnapshot(config);
  const distance = Math.max(0, Math.round(distanceMeters));
  const chargeableMeters = Math.max(0, distance - snapshot.includedMeters);
  const distanceSteps = Math.ceil(
    chargeableMeters / snapshot.distanceStepMeters,
  );
  const total = snapshot.baseFare +
    distanceSteps * snapshot.distanceStepPrice +
    Math.max(0, additionalPassengers) * snapshot.additionalPassengerFee +
    Math.max(0, baggageCount) * snapshot.baggageFee +
    (isOutsideToda ? snapshot.outsideTodaSurcharge : 0);
  return Math.round(total * 100) / 100;
}

module.exports = {
  DEFAULT_FARE,
  calculateFare,
  fareSnapshot,
};
