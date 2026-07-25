import { FormEvent, useEffect, useRef, useState } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';
import type { Point } from '../types';
import './polygon-editor.css';

interface Props {
  points: Point[];
  onChange: (points: Point[]) => void;
  onFinish?: () => void;
  disabled?: boolean;
}

const bacolod: Point = [122.9511, 10.6765];

interface SearchResult {
  id: string;
  name: string;
  placeName: string;
  coordinates: Point;
}

export function PolygonEditor({ points, onChange, onFinish, disabled }: Props) {
  const element = useRef<HTMLDivElement>(null);
  const mapRef = useRef<mapboxgl.Map | null>(null);
  const latest = useRef(points);
  const searchMarker = useRef<mapboxgl.Marker | null>(null);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<SearchResult[]>([]);
  const [searching, setSearching] = useState(false);
  const [searchError, setSearchError] = useState('');
  latest.current = points;

  useEffect(() => {
    const token = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
    if (!element.current || !token || token === 'INSERT_MAPBOX_ACCESS_TOKEN_HERE') return;
    mapboxgl.accessToken = token;
    const map = new mapboxgl.Map({
      container: element.current,
      style: 'mapbox://styles/mapbox/dark-v11',
      center: bacolod,
      zoom: 12,
      attributionControl: true,
    });
    mapRef.current = map;
    map.addControl(new mapboxgl.NavigationControl({ showCompass: true }), 'top-right');
    map.addControl(new mapboxgl.ScaleControl({ maxWidth: 120, unit: 'metric' }), 'bottom-left');
    map.on('load', () => {
      map.addSource('zone', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
      map.addLayer({ id: 'zone-fill', type: 'fill', source: 'zone', paint: { 'fill-color': '#ef4444', 'fill-opacity': 0.25 } });
      map.addLayer({ id: 'zone-line', type: 'line', source: 'zone', paint: { 'line-color': '#ef4444', 'line-width': 3 } });
      map.addLayer({ id: 'zone-points', type: 'circle', source: 'zone', paint: { 'circle-color': '#ffffff', 'circle-stroke-color': '#ef4444', 'circle-stroke-width': 3, 'circle-radius': 6 } });
    });
    map.on('click', (event) => { if (!disabled) onChange([...latest.current, [event.lngLat.lng, event.lngLat.lat]]); });
    return () => { searchMarker.current?.remove(); map.remove(); };
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

  async function search(event: FormEvent) {
    event.preventDefault();
    const trimmed = query.trim();
    if (!trimmed) return;
    const token = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
    setSearching(true); setSearchError('');
    try {
      const response = await fetch(`https://api.mapbox.com/search/geocode/v6/forward?q=${encodeURIComponent(trimmed)}&proximity=122.9511,10.6765&limit=5&access_token=${encodeURIComponent(token)}`);
      if (!response.ok) throw new Error('Search is unavailable for this Mapbox token.');
      const body = await response.json() as { features?: Array<{ id: string; properties?: { name?: string; full_address?: string; place_formatted?: string }; geometry?: { coordinates?: Point } }> };
      setResults((body.features || []).flatMap((feature) => feature.geometry?.coordinates ? [{ id: feature.id, name: feature.properties?.name || 'Map location', placeName: feature.properties?.full_address || feature.properties?.place_formatted || '', coordinates: feature.geometry.coordinates }] : []));
    } catch (error) { setSearchError(error instanceof Error ? error.message : 'Unable to search.'); }
    finally { setSearching(false); }
  }

  function choose(result: SearchResult) {
    const map = mapRef.current;
    if (!map) return;
    map.flyTo({ center: result.coordinates, zoom: 16, essential: true });
    searchMarker.current?.remove();
    searchMarker.current = new mapboxgl.Marker({ color: '#ef4444' }).setLngLat(result.coordinates).addTo(map);
    setQuery(result.name); setResults([]);
  }

  const configured = Boolean(import.meta.env.VITE_MAPBOX_ACCESS_TOKEN && import.meta.env.VITE_MAPBOX_ACCESS_TOKEN !== 'INSERT_MAPBOX_ACCESS_TOKEN_HERE');
  return <div className="map-shell polygon-editor">{configured ? <><div ref={element} className="map" /><div className="map-search"><form onSubmit={search}><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search address, landmark, or barangay" aria-label="Search map" /><button type="submit" disabled={searching}>{searching ? 'Searching…' : 'Search'}</button></form>{(results.length > 0 || searchError) && <div className="map-search-results">{searchError && <p>{searchError}</p>}{results.map((result) => <button type="button" key={result.id} onClick={() => choose(result)}><b>{result.name}</b><span>{result.placeName}</span></button>)}</div>}</div><div className="map-guide"><b>Coverage editor</b><span>1. Search or pan to an area</span><span>2. Left-click to add red boundary points</span><span>3. Press Enter or Finish polygon to submit</span></div></> : <div className="map-missing">Set <code>VITE_MAPBOX_ACCESS_TOKEN</code> in <code>admin/.env</code> to enable the coverage editor.</div>}</div>;
}
