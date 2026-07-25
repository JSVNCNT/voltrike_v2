import { useEffect, useRef } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import type { Point } from '../types';

interface Props {
  points: Point[];
  onChange: (points: Point[]) => void;
  onFinish?: () => void;
  disabled?: boolean;
}

const bacolod: Point = [122.9511, 10.6765];

export function PolygonEditor({ points, onChange, onFinish, disabled }: Props) {
  const element = useRef<HTMLDivElement>(null);
  const mapRef = useRef<mapboxgl.Map | null>(null);
  const latest = useRef(points);
  latest.current = points;

  useEffect(() => {
    const token = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
    if (!element.current || !token || token === 'INSERT_MAPBOX_ACCESS_TOKEN_HERE') return;
    mapboxgl.accessToken = token;
    const map = new mapboxgl.Map({ container: element.current, style: 'mapbox://styles/mapbox/streets-v12', center: bacolod, zoom: 12 });
    mapRef.current = map;
    map.on('load', () => {
      map.addSource('zone', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
      map.addLayer({ id: 'zone-fill', type: 'fill', source: 'zone', paint: { 'fill-color': '#008B8B', 'fill-opacity': 0.22 } });
      map.addLayer({ id: 'zone-line', type: 'line', source: 'zone', paint: { 'line-color': '#008B8B', 'line-width': 3 } });
      map.addLayer({ id: 'zone-points', type: 'circle', source: 'zone', paint: { 'circle-color': '#ffffff', 'circle-stroke-color': '#008B8B', 'circle-stroke-width': 3, 'circle-radius': 6 } });
    });
    map.on('click', (event) => { if (!disabled) onChange([...latest.current, [event.lngLat.lng, event.lngLat.lat]]); });
    return () => map.remove();
  }, [disabled, onChange]);

  useEffect(() => {
    const map = mapRef.current;
    const source = map?.getSource('zone') as mapboxgl.GeoJSONSource | undefined;
    if (!source) return;
    const coordinates = points.length >= 3 ? [[...points, points[0]]] : points;
    source.setData({ type: 'FeatureCollection', features: [
      ...(points.length >= 3 ? [{ type: 'Feature', properties: {}, geometry: { type: 'Polygon', coordinates: [coordinates] } }] : []),
      ...points.map((point) => ({ type: 'Feature', properties: {}, geometry: { type: 'Point', coordinates: point } })),
    ] } as GeoJSON.FeatureCollection);
  }, [points]);

  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      const tag = (event.target as HTMLElement | null)?.tagName;
      if (event.key === 'Enter' && points.length >= 3 && !['INPUT', 'TEXTAREA', 'SELECT'].includes(tag || '')) {
        event.preventDefault();
        onFinish?.();
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [onFinish, points.length]);

  const configured = Boolean(import.meta.env.VITE_MAPBOX_ACCESS_TOKEN && import.meta.env.VITE_MAPBOX_ACCESS_TOKEN !== 'INSERT_MAPBOX_ACCESS_TOKEN_HERE');
  return <div className="map-shell">{configured ? <div ref={element} className="map" /> : <div className="map-missing">Set <code>VITE_MAPBOX_ACCESS_TOKEN</code> in <code>admin/.env</code> to enable the Bacolod polygon editor.</div>}</div>;
}
