'use strict';

const {
  fromCentavos,
  roundCurrency,
  toCentavos,
} = require('./fare-policy');

const MAX_COMMISSION_PERCENT = 30;
const PERCENT_HUNDREDTHS_PER_WHOLE = 100;
const PERCENT_HUNDREDTHS_PER_TOTAL = 10000;

function normalizedCommissionPercent(value) {
  const number = Number(value);
  if (!Number.isFinite(number) ||
      number < 0 ||
      number > MAX_COMMISSION_PERCENT) {
    return 0;
  }
  return roundCurrency(number);
}

function calculateSettlementBreakdown({
  grossFare,
  commissionPercent,
}) {
  const numericGrossFare = Number(grossFare);
  if (!Number.isFinite(numericGrossFare) || numericGrossFare < 0) {
    throw new RangeError('Gross fare must be a finite non-negative amount.');
  }
  const grossCentavos = toCentavos(numericGrossFare);
  if (!Number.isSafeInteger(grossCentavos)) {
    throw new RangeError('Gross fare exceeds the supported range.');
  }
  const normalizedPercent = normalizedCommissionPercent(commissionPercent);
  const percentHundredths =
    Math.round(normalizedPercent * PERCENT_HUNDREDTHS_PER_WHOLE);
  if (!Number.isSafeInteger(grossCentavos * percentHundredths)) {
    throw new RangeError('Settlement calculation exceeds the supported range.');
  }
  const commissionCentavos = Math.round(
    grossCentavos * percentHundredths /
      PERCENT_HUNDREDTHS_PER_TOTAL,
  );
  const driverNetCentavos = grossCentavos - commissionCentavos;
  if (commissionCentavos < 0 ||
      driverNetCentavos < 0 ||
      commissionCentavos + driverNetCentavos !== grossCentavos) {
    throw new RangeError('Settlement amounts do not balance.');
  }
  return {
    grossFare: fromCentavos(grossCentavos),
    commissionPercent: normalizedPercent,
    commissionAmount: fromCentavos(commissionCentavos),
    driverNetEarnings: fromCentavos(driverNetCentavos),
  };
}

function settlementInvariantHolds(value) {
  if (!value) return false;
  const grossCentavos = toCentavos(value.grossFare);
  const commissionCentavos = toCentavos(value.commissionAmount);
  const driverNetCentavos = toCentavos(value.driverNetEarnings);
  return grossCentavos >= 0 &&
    commissionCentavos >= 0 &&
    driverNetCentavos >= 0 &&
    commissionCentavos + driverNetCentavos === grossCentavos;
}

module.exports = {
  MAX_COMMISSION_PERCENT,
  calculateSettlementBreakdown,
  normalizedCommissionPercent,
  settlementInvariantHolds,
};
