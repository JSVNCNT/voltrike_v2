import { useEffect, useRef } from 'react';
import mapboxgl from 'mapbox-gl';
import 'mapbox-gl/dist/mapbox-gl.css';

export interface AdminMapPoint {
  id: string;
  latitude: number;
  longitude: number;
  title: string;
  details: string[];
  urgent?: boolean;
}

export function AdminLocationMap({
  points,
  selectedId,
}: {
  points: AdminMapPoint[];
  selectedId?: string | null;
}) {
  const element = useRef<HTMLDivElement | null>(null);
  const mapRef = useRef<mapboxgl.Map | null>(null);
  const markersRef = useRef<Map<string, mapboxgl.Marker>>(new Map());

  useEffect(() => {
    const token = import.meta.env.VITE_MAPBOX_ACCESS_TOKEN;
    if (!element.current || !token ||
        token === 'INSERT_MAPBOX_ACCESS_TOKEN_HERE') return;
    mapboxgl.accessToken = token;
    const map = new mapboxgl.Map({
      container: element.current,
      style: 'mapbox://styles/mapbox/streets-v12',
      center: [122.9511, 10.6765],
      zoom: 12,
    });
    map.addControl(new mapboxgl.NavigationControl(), 'top-right');
    mapRef.current = map;
    return () => {
      markersRef.current.forEach((marker) => marker.remove());
      markersRef.current.clear();
      map.remove();
      mapRef.current = null;
    };
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    markersRef.current.forEach((marker) => marker.remove());
    markersRef.current.clear();
    const bounds = new mapboxgl.LngLatBounds();
    points.forEach((point) => {
      const popupContent = document.createElement('div');
      const heading = document.createElement('strong');
      heading.textContent = point.title;
      popupContent.appendChild(heading);
      point.details.forEach((detail) => {
        const line = document.createElement('div');
        line.textContent = detail;
        popupContent.appendChild(line);
      });
      const marker = new mapboxgl.Marker({
        color: point.urgent ? '#dc2626' : '#087f7f',
      })
        .setLngLat([point.longitude, point.latitude])
        .setPopup(new mapboxgl.Popup({ offset: 24 }).setDOMContent(popupContent))
        .addTo(map);
      markersRef.current.set(point.id, marker);
      bounds.extend([point.longitude, point.latitude]);
    });
    if (points.length === 1) {
      map.flyTo({
        center: [points[0].longitude, points[0].latitude],
        zoom: 16,
      });
    } else if (points.length > 1) {
      map.fitBounds(bounds, { padding: 54, maxZoom: 15 });
    }
  }, [points]);

  useEffect(() => {
    if (!selectedId) return;
    const point = points.find((entry) => entry.id === selectedId);
    const marker = markersRef.current.get(selectedId);
    const map = mapRef.current;
    if (!point || !marker || !map) return;
    map.flyTo({
      center: [point.longitude, point.latitude],
      zoom: 16,
      essential: true,
    });
    marker.togglePopup();
  }, [points, selectedId]);

  const configured = Boolean(
    import.meta.env.VITE_MAPBOX_ACCESS_TOKEN &&
    import.meta.env.VITE_MAPBOX_ACCESS_TOKEN !==
      'INSERT_MAPBOX_ACCESS_TOKEN_HERE',
  );
  return (
    <div className="map-shell admin-location-map">
      {configured
        ? <div ref={element} className="map" />
        : <div className="map-missing">
            Set <code>VITE_MAPBOX_ACCESS_TOKEN</code> to display locations.
          </div>}
    </div>
  );
}
