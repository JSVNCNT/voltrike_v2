'use strict';

const GOOGLE_ROUTES_FIELD_MASK = [
  'routes.distanceMeters',
  'routes.duration',
  'routes.polyline.encodedPolyline',
  'routes.travelAdvisory.routeRestrictionsPartiallyIgnored',
].join(',');

function googleDrivingRouteRequest(pickup, destination) {
  return {
    origin: {
      location: {
        latLng: {
          latitude: pickup.latitude,
          longitude: pickup.longitude,
        },
      },
    },
    destination: {
      location: {
        latLng: {
          latitude: destination.latitude,
          longitude: destination.longitude,
        },
      },
    },
    travelMode: 'DRIVE',
    routingPreference: 'TRAFFIC_AWARE',
    routeModifiers: {
      avoidHighways: true,
    },
    computeAlternativeRoutes: true,
    languageCode: 'en-PH',
    units: 'METRIC',
  };
}

function googleHighwayRouteAdvisory(route) {
  const routeRestrictionsPartiallyIgnored =
    route?.travelAdvisory?.routeRestrictionsPartiallyIgnored === true;
  return {
    requestedAvoidHighways: true,
    provider: 'google_routes',
    routeRestrictionsPartiallyIgnored,
    status: routeRestrictionsPartiallyIgnored
      ? 'possibly_ignored'
      : 'avoidance_not_reported_ignored',
    confirmedViolation: false,
  };
}

module.exports = {
  GOOGLE_ROUTES_FIELD_MASK,
  googleDrivingRouteRequest,
  googleHighwayRouteAdvisory,
};
