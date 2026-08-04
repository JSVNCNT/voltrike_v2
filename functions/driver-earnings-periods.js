'use strict';

const MANILA_OFFSET_MS = 8 * 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

function driverEarningsPeriodStarts(now = Date.now()) {
  const shifted = new Date(now + MANILA_OFFSET_MS);
  const localMidnightAsUtc = Date.UTC(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth(),
    shifted.getUTCDate(),
  );
  const day = localMidnightAsUtc - MANILA_OFFSET_MS;
  const weekday = shifted.getUTCDay() || 7;
  return {
    day: new Date(day),
    week: new Date(day - (weekday - 1) * DAY_MS),
    month: new Date(
      Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), 1) -
        MANILA_OFFSET_MS,
    ),
  };
}

module.exports = { driverEarningsPeriodStarts };
