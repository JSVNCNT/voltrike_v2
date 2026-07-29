import { useEffect, useMemo, useRef } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import type { Point } from '../types';

export interface AdminMapPoint {
  id: string;
  latitude: number;
  longitude: number;
  title: string;
  details: string[];
  urgent?: boolean;
  tone?: 'default' | 'driver' | 'warning' | 'danger';
}

export interface AdminMapPolygon {
  id: string;
  name: string;
  areas: Point[][];
  color?: string;
}

interface Props {
  points: AdminMapPoint[];
  selectedId?: string | null;
  polygons?: AdminMapPolygon[];
  onSelect?: (id: string) => void;
  ariaLabel?: string;
}

const bacolod: Point = [122.9511, 10.6765];
const restrictionSourceId = 'admin-operations-restrictions';
const restrictionFillLayerId = 'admin-operations-restrictions-fill';
const restrictionLineLayerId = 'admin-operations-restrictions-line';

function validCoordinate(longitude: number, latitude: number): boolean {
  return Number.isFinite(longitude)
    && Number.isFinite(latitude)
    && Math.abs(longitude) <= 180
    && Math.abs(latitude) <= 90;
}

function markerColor(point: AdminMapPoint): string {
  if (point.tone === 'driver') return '#22c55e';
  if (point.tone === 'warning') return '#f59e0b';
  if (point.urgent || point.tone === 'danger') return '#ef4444';
  return '#14b8a6';
}

function polygonData(polygons: AdminMapPolygon[]): GeoJSON.FeatureCollection {
  return {
    type: 'FeatureCollection',
    features: polygons.flatMap((polygon) =>
      polygon.areas.flatMap((area, index) => {
        const valid = area.filter(([longitude, latitude]) =>
          validCoordinate(longitude, latitude));
        if (valid.length < 3) return [];
        return [{
          type: 'Feature' as const,
          id: `${polygon.id}-${index}`,
          properties: {
            id: polygon.id,
            name: polygon.name,
            color: polygon.color || '#ef4444',
          },
          geometry: {
            type: 'Polygon' as const,
            coordinates: [[...valid, valid[0]]],
          },
        }];
      })),
  };
}

function popupFor(point: AdminMapPoint): mapboxgl.Popup {
  const popupContent = document.createElement('div');
  popupContent.className = 'operations-map-popup';
  const heading = document.createElement('strong');
  heading.textContent = point.title;
  popupContent.appendChild(heading);
  point.details.forEach((detail) => {
    const line = document.createElement('div');
    line.textContent = detail;
    popupContent.appendChild(line);
  });
  return new mapboxgl.Popup({
    closeButton: true,
    closeOnClick: false,
    offset: 24,
  }).setDOMContent(popupContent);
}

/**
 * Shared dark operations map for live drivers, safety incidents, and
 * restriction violations. Marker reconciliation keeps a selected popup open
 * while near-real-time polling replaces the surrounding data.
 */
export function AdminLocationMap({
  points,
  selectedId,
  polygons = [],
  onSelect,
  ariaLabel = 'Operations map',
}: Props) {
  const element = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<mapboxgl.Map | null>(null);
  const mapLoaded = useRef(false);
  const markersRef = useRef<Map<string, mapboxgl.Marker>>(new Map());
  const markerSignatures = useRef<Map<string, string>>(new Map());
  const latestPoints = useRef(points);
  const latestPolygons = useRef(polygons);
  const latestSelectedId = useRef(selectedId);
  const onSelectRef = useRef(onSelect);
  latestPoints.current = points;
  latestPolygons.current = polygons;
  latestSelectedId.current = selectedId;
  onSelectRef.current = onSelect;

  const geometrySignature = useMemo(
    () => JSON.stringify({
      pointIds: points.map((point) => point.id).sort(),
      polygons: polygons.map((polygon) => ({
        id: polygon.id,
        areas: polygon.areas,
      })),
    }),
    [points, polygons],
  );
  const fittedGeometrySignature = useRef('');

  useEffect(() => {
    const token = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
    if (!element.current || !token ||
        token === 'INSERT_MAPBOX_ACCESS_TOKEN_HERE') return;
    mapboxgl.accessToken = token;
    const map = new mapboxgl.Map({
      container: element.current,
      style: 'mapbox://styles/mapbox/dark-v11',
      center: bacolod,
      zoom: 12,
      attributionControl: true,
    });
    map.addControl(new mapboxgl.NavigationControl({ showCompass: true }), 'top-right');
    map.addControl(new mapboxgl.ScaleControl({ maxWidth: 120, unit: 'metric' }), 'bottom-left');
    mapRef.current = map;
    map.on('load', () => {
      mapLoaded.current = true;
      map.addSource(restrictionSourceId, {
        type: 'geojson',
        data: polygonData(latestPolygons.current),
      });
      map.addLayer({
        id: restrictionFillLayerId,
        type: 'fill',
        source: restrictionSourceId,
        paint: {
          'fill-color': ['coalesce', ['get', 'color'], '#ef4444'],
          'fill-opacity': 0.28,
        },
      });
      map.addLayer({
        id: restrictionLineLayerId,
        type: 'line',
        source: restrictionSourceId,
        paint: {
          'line-color': ['coalesce', ['get', 'color'], '#ef4444'],
          'line-width': 3,
          'line-opacity': 0.95,
        },
      });
    });
    return () => {
      markersRef.current.forEach((marker) => marker.remove());
      markersRef.current.clear();
      markerSignatures.current.clear();
      mapLoaded.current = false;
      map.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;

    const nextIds = new Set(points.map((point) => point.id));
    markersRef.current.forEach((marker, id) => {
      if (!nextIds.has(id)) {
        marker.remove();
        markersRef.current.delete(id);
        markerSignatures.current.delete(id);
      }
    });

    points.forEach((point) => {
      if (!validCoordinate(point.longitude, point.latitude)) return;
      const signature = JSON.stringify({
        latitude: point.latitude,
        longitude: point.longitude,
        title: point.title,
        details: point.details,
        color: markerColor(point),
      });
      if (markerSignatures.current.get(point.id) === signature) return;

      markersRef.current.get(point.id)?.remove();
      const marker = new mapboxgl.Marker({ color: markerColor(point) })
        .setLngLat([point.longitude, point.latitude])
        .setPopup(popupFor(point))
        .addTo(map);
      marker.getElement().setAttribute('aria-label', point.title);
      marker.getElement().addEventListener('click', () => {
        onSelectRef.current?.(point.id);
      });
      markersRef.current.set(point.id, marker);
      markerSignatures.current.set(point.id, signature);
    });

    if (latestSelectedId.current) {
      const selectedMarker = markersRef.current.get(latestSelectedId.current);
      const popup = selectedMarker?.getPopup();
      if (selectedMarker && popup && !popup.isOpen()) {
        selectedMarker.togglePopup();
      }
    }
  }, [points]);

  useEffect(() => {
    const source = mapRef.current?.getSource(restrictionSourceId) as
      | mapboxgl.GeoJSONSource
      | undefined;
    if (mapLoaded.current && source) source.setData(polygonData(polygons));
  }, [polygons]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || !selectedId) return;
    markersRef.current.forEach((marker, id) => {
      const popup = marker.getPopup();
      if (id !== selectedId && popup?.isOpen()) marker.togglePopup();
    });
    const point = points.find((entry) => entry.id === selectedId);
    const marker = markersRef.current.get(selectedId);
    const popup = marker?.getPopup();
    if (!point || !marker || !popup) return;
    map.flyTo({
      center: [point.longitude, point.latitude],
      zoom: 16,
      essential: true,
    });
    if (!popup.isOpen()) marker.togglePopup();
  }, [points, selectedId]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || fittedGeometrySignature.current === geometrySignature) return;
    const bounds = new mapboxgl.LngLatBounds();
    points.forEach((point) => {
      if (validCoordinate(point.longitude, point.latitude)) {
        bounds.extend([point.longitude, point.latitude]);
      }
    });
    polygons.forEach((polygon) => polygon.areas.forEach((area) =>
      area.forEach(([longitude, latitude]) => {
        if (validCoordinate(longitude, latitude)) bounds.extend([longitude, latitude]);
      })));
    if (!bounds.isEmpty()) {
      map.fitBounds(bounds, {
        padding: 54,
        maxZoom: points.length + polygons.length === 1 ? 16 : 15,
        duration: 0,
      });
      fittedGeometrySignature.current = geometrySignature;
    }
  }, [geometrySignature, points, polygons]);

  const configured = Boolean(
    import.meta.env.VITE_MAPBOX_ACCESS_TOKEN &&
    import.meta.env.VITE_MAPBOX_ACCESS_TOKEN !==
      'INSERT_MAPBOX_ACCESS_TOKEN_HERE',
  );
  return (
    <div className="map-shell admin-location-map" aria-label={ariaLabel}>
      {configured
        ? <div ref={element} className="map" />
        : <div className="map-missing">
            Set <code>VITE_MAPBOX_ACCESS_TOKEN</code> to display locations.
          </div>}
    </div>
  );
}
