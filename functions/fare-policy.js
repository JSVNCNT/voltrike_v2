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

function calculateFareBreakdown({
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
  const distanceFare = distanceSteps * snapshot.distanceStepPrice;
  const additionalPassengerFare =
    Math.max(0, additionalPassengers) *
    snapshot.additionalPassengerFee;
  const baggageFare = Math.max(0, baggageCount) * snapshot.baggageFee;
  const boundarySurcharge =
    isOutsideToda ? snapshot.outsideTodaSurcharge : 0;
  const total = snapshot.baseFare + distanceFare +
    additionalPassengerFare + baggageFare + boundarySurcharge;
  return {
    baseFare: snapshot.baseFare,
    includedMeters: snapshot.includedMeters,
    chargeableMeters,
    distanceSteps,
    distanceStepMeters: snapshot.distanceStepMeters,
    distanceStepPrice: snapshot.distanceStepPrice,
    distanceFare,
    additionalPassengers: Math.max(0, additionalPassengers),
    additionalPassengerFare,
    baggageCount: Math.max(0, baggageCount),
    baggageFare,
    isOutsideToda,
    boundarySurcharge,
    currency: snapshot.currency,
    total: Math.round(total * 100) / 100,
  };
}

function calculateFare(options) {
  return calculateFareBreakdown(options).total;
}

module.exports = {
  DEFAULT_FARE,
  calculateFare,
  calculateFareBreakdown,
  fareSnapshot,
};
