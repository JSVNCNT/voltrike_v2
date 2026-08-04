'use strict';

const DEFAULT_CELL_DEGREES = 0.05;

function dispatchCellForLocation(location, cellDegrees = DEFAULT_CELL_DEGREES) {
  const latitude = Number(location?.latitude);
  const longitude = Number(location?.longitude);
  if (!Number.isFinite(cellDegrees) || cellDegrees <= 0 || cellDegrees > 1 ||
      !Number.isFinite(latitude) || latitude < -90 || latitude > 90 ||
      !Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
    return null;
  }
  return `${Math.floor((latitude + 90) / cellDegrees)}:` +
    `${Math.floor((longitude + 180) / cellDegrees)}`;
}

function dispatchIndexUpdates({
  driverId,
  before,
  after,
  cellDegrees = DEFAULT_CELL_DEGREES,
}) {
  if (typeof driverId !== 'string' || driverId.length === 0) return {};
  const beforeCell = dispatchCellForLocation(before, cellDegrees);
  const afterCell = after?.online === true
    ? dispatchCellForLocation(after, cellDegrees)
    : null;
  const updates = {};
  if (beforeCell && beforeCell !== afterCell) {
    updates[`dispatchCells/${beforeCell}/${driverId}`] = null;
  }
  if (afterCell) {
    updates[`dispatchCells/${afterCell}/${driverId}`] = {
      driverId,
      latitude: Number(after.latitude),
      longitude: Number(after.longitude),
      timestamp: Number(after.timestamp || 0),
      accuracy: Number(after.accuracy || 0),
      online: true,
    };
    updates[`dispatchDriverCells/${driverId}`] = afterCell;
  } else {
    updates[`dispatchDriverCells/${driverId}`] = null;
  }
  return updates;
}

module.exports = {
  DEFAULT_CELL_DEGREES,
  dispatchCellForLocation,
  dispatchIndexUpdates,
};
