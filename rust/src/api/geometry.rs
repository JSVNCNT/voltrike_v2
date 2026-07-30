use std::sync::{Arc, OnceLock, RwLock};

const COORDINATE_STRIDE: usize = 2;
const MAX_ROUTE_POINTS: usize = 200_000;
const MAX_POLYGON_POINTS: usize = 200_000;
const MAX_RESTRICTIONS: usize = 10_000;
const MAX_GEOMETRY_WORK_ITEMS: usize = 20_000_000;
const MAX_ENCODED_POLYLINE_BYTES: usize = 4_000_000;
const ORIENTATION_EPSILON: f64 = 1e-12;
const ON_SEGMENT_EPSILON: f64 = 1e-10;
const METERS_PER_DEGREE: f64 = 111_320.0;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GeometryBatchStatus {
    Ok,
    InvalidInput,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RouteConflictBatchResult {
    pub status: GeometryBatchStatus,
    pub conflicting_restriction_indices: Vec<u32>,
    pub error_message: Option<String>,
}

impl RouteConflictBatchResult {
    fn ok(conflicting_restriction_indices: Vec<u32>) -> Self {
        Self {
            status: GeometryBatchStatus::Ok,
            conflicting_restriction_indices,
            error_message: None,
        }
    }

    fn invalid(message: impl Into<String>) -> Self {
        Self {
            status: GeometryBatchStatus::InvalidInput,
            conflicting_restriction_indices: Vec::new(),
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GeometryCacheStatus {
    Ok,
    InvalidInput,
    CacheUnavailable,
    GenerationMismatch,
    InternalError,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RestrictionCacheUpdateResult {
    pub status: GeometryCacheStatus,
    pub cache_generation: u32,
    pub restriction_count: u32,
    pub error_message: Option<String>,
}

impl RestrictionCacheUpdateResult {
    fn ok(cache_generation: u32, restriction_count: u32) -> Self {
        Self {
            status: GeometryCacheStatus::Ok,
            cache_generation,
            restriction_count,
            error_message: None,
        }
    }

    fn error(status: GeometryCacheStatus, message: impl Into<String>) -> Self {
        Self {
            status,
            cache_generation: 0,
            restriction_count: 0,
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CachedRouteConflictResult {
    pub status: GeometryCacheStatus,
    pub cache_generation: u32,
    pub conflicting_restriction_indices: Vec<u32>,
    pub error_message: Option<String>,
}

impl CachedRouteConflictResult {
    fn ok(cache_generation: u32, conflicting_restriction_indices: Vec<u32>) -> Self {
        Self {
            status: GeometryCacheStatus::Ok,
            cache_generation,
            conflicting_restriction_indices,
            error_message: None,
        }
    }

    fn error(error: CacheAccessError) -> Self {
        Self {
            status: error.status,
            cache_generation: error.cache_generation,
            conflicting_restriction_indices: Vec::new(),
            error_message: Some(error.message),
        }
    }

    fn invalid(cache_generation: u32, message: impl Into<String>) -> Self {
        Self {
            status: GeometryCacheStatus::InvalidInput,
            cache_generation,
            conflicting_restriction_indices: Vec::new(),
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct CachedPointProximityResult {
    pub status: GeometryCacheStatus,
    pub cache_generation: u32,
    pub inside_restriction_index: Option<u32>,
    pub nearest_restriction_index: Option<u32>,
    pub nearest_distance_meters: Option<f64>,
    pub preferred_distance_meters: Option<f64>,
    pub error_message: Option<String>,
}

impl CachedPointProximityResult {
    fn ok(
        cache_generation: u32,
        inside_restriction_index: Option<u32>,
        nearest_restriction_index: Option<u32>,
        nearest_distance_meters: Option<f64>,
        preferred_distance_meters: Option<f64>,
    ) -> Self {
        Self {
            status: GeometryCacheStatus::Ok,
            cache_generation,
            inside_restriction_index,
            nearest_restriction_index,
            nearest_distance_meters,
            preferred_distance_meters,
            error_message: None,
        }
    }

    fn error(error: CacheAccessError) -> Self {
        Self {
            status: error.status,
            cache_generation: error.cache_generation,
            inside_restriction_index: None,
            nearest_restriction_index: None,
            nearest_distance_meters: None,
            preferred_distance_meters: None,
            error_message: Some(error.message),
        }
    }

    fn invalid(cache_generation: u32, message: impl Into<String>) -> Self {
        Self {
            status: GeometryCacheStatus::InvalidInput,
            cache_generation,
            inside_restriction_index: None,
            nearest_restriction_index: None,
            nearest_distance_meters: None,
            preferred_distance_meters: None,
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct GeoPoint {
    latitude: f64,
    longitude: f64,
}

impl GeoPoint {
    fn validated(latitude: f64, longitude: f64) -> Result<Self, String> {
        if !latitude.is_finite() || !longitude.is_finite() {
            return Err("coordinates must be finite".to_owned());
        }
        if !(-90.0..=90.0).contains(&latitude) {
            return Err("latitude must be within [-90, 90]".to_owned());
        }
        if !(-180.0..=180.0).contains(&longitude) {
            return Err("longitude must be within [-180, 180]".to_owned());
        }
        Ok(Self {
            latitude,
            longitude,
        })
    }
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct GeoBounds {
    minimum_latitude: f64,
    maximum_latitude: f64,
    minimum_longitude: f64,
    maximum_longitude: f64,
}

impl GeoBounds {
    fn from_points(points: &[GeoPoint]) -> Option<Self> {
        let first = *points.first()?;
        let mut bounds = Self {
            minimum_latitude: first.latitude,
            maximum_latitude: first.latitude,
            minimum_longitude: first.longitude,
            maximum_longitude: first.longitude,
        };
        for point in &points[1..] {
            bounds.minimum_latitude = bounds.minimum_latitude.min(point.latitude);
            bounds.maximum_latitude = bounds.maximum_latitude.max(point.latitude);
            bounds.minimum_longitude = bounds.minimum_longitude.min(point.longitude);
            bounds.maximum_longitude = bounds.maximum_longitude.max(point.longitude);
        }
        Some(bounds)
    }

    fn from_pair(first: GeoPoint, second: GeoPoint) -> Self {
        Self {
            minimum_latitude: first.latitude.min(second.latitude),
            maximum_latitude: first.latitude.max(second.latitude),
            minimum_longitude: first.longitude.min(second.longitude),
            maximum_longitude: first.longitude.max(second.longitude),
        }
    }

    fn union(self, other: Self) -> Self {
        Self {
            minimum_latitude: self.minimum_latitude.min(other.minimum_latitude),
            maximum_latitude: self.maximum_latitude.max(other.maximum_latitude),
            minimum_longitude: self.minimum_longitude.min(other.minimum_longitude),
            maximum_longitude: self.maximum_longitude.max(other.maximum_longitude),
        }
    }

    fn intersects(self, other: Self) -> bool {
        self.maximum_latitude + ON_SEGMENT_EPSILON >= other.minimum_latitude
            && other.maximum_latitude + ON_SEGMENT_EPSILON >= self.minimum_latitude
            && self.maximum_longitude + ON_SEGMENT_EPSILON >= other.minimum_longitude
            && other.maximum_longitude + ON_SEGMENT_EPSILON >= self.minimum_longitude
    }

    fn contains(self, point: GeoPoint) -> bool {
        point.latitude >= self.minimum_latitude - ON_SEGMENT_EPSILON
            && point.latitude <= self.maximum_latitude + ON_SEGMENT_EPSILON
            && point.longitude >= self.minimum_longitude - ON_SEGMENT_EPSILON
            && point.longitude <= self.maximum_longitude + ON_SEGMENT_EPSILON
    }

    fn latitude_distance_lower_bound_meters(self, point: GeoPoint) -> f64 {
        let latitude_delta = if point.latitude < self.minimum_latitude {
            self.minimum_latitude - point.latitude
        } else if point.latitude > self.maximum_latitude {
            point.latitude - self.maximum_latitude
        } else {
            0.0
        };
        (latitude_delta - ON_SEGMENT_EPSILON).max(0.0) * METERS_PER_DEGREE
    }
}

#[derive(Clone, Debug)]
struct AreaGeometry {
    points: Vec<GeoPoint>,
    bounds: Option<GeoBounds>,
}

#[derive(Clone, Debug)]
struct RestrictionGeometry {
    areas: Vec<AreaGeometry>,
    bounds: Option<GeoBounds>,
}

#[derive(Clone, Debug)]
struct RestrictionCache {
    restrictions: Vec<RestrictionGeometry>,
    polygon_point_count: usize,
}

struct RestrictionCacheState {
    generation: u32,
    cache: Option<Arc<RestrictionCache>>,
}

struct CacheAccessError {
    status: GeometryCacheStatus,
    cache_generation: u32,
    message: String,
}

static RESTRICTION_CACHE: OnceLock<RwLock<RestrictionCacheState>> = OnceLock::new();

/// Atomically replaces the process-local restriction cache after validating
/// the complete packed geometry. Invalid input leaves the previous cache and
/// generation unchanged.
pub fn replace_restriction_cache(
    polygon_lat_lng: Vec<f64>,
    area_point_counts: Vec<u32>,
    restriction_area_counts: Vec<u32>,
) -> RestrictionCacheUpdateResult {
    let cache = match parse_restrictions(
        &polygon_lat_lng,
        &area_point_counts,
        &restriction_area_counts,
    ) {
        Ok(cache) => cache,
        Err(message) => {
            return RestrictionCacheUpdateResult::error(GeometryCacheStatus::InvalidInput, message);
        }
    };
    let restriction_count = match u32::try_from(cache.restrictions.len()) {
        Ok(count) => count,
        Err(_) => {
            return RestrictionCacheUpdateResult::error(
                GeometryCacheStatus::InternalError,
                "restriction count does not fit into u32",
            );
        }
    };

    let state_lock = restriction_cache_state();
    let mut state = match state_lock.write() {
        Ok(state) => state,
        Err(_) => {
            return RestrictionCacheUpdateResult::error(
                GeometryCacheStatus::InternalError,
                "restriction cache write lock is unavailable",
            );
        }
    };
    let next_generation = match state.generation.checked_add(1) {
        Some(generation) if generation != 0 => generation,
        _ => {
            return RestrictionCacheUpdateResult::error(
                GeometryCacheStatus::InternalError,
                "restriction cache generation is exhausted",
            );
        }
    };
    state.cache = Some(Arc::new(cache));
    state.generation = next_generation;
    RestrictionCacheUpdateResult::ok(next_generation, restriction_count)
}

/// Decodes a Google encoded polyline and finds the first conflict against the
/// requested cache generation without materializing route points in Dart.
pub fn analyze_cached_encoded_route_conflicts(
    encoded_polyline: String,
    expected_cache_generation: u32,
) -> CachedRouteConflictResult {
    let (cache_generation, cache) = match read_restriction_cache(expected_cache_generation) {
        Ok(cache) => cache,
        Err(error) => return CachedRouteConflictResult::error(error),
    };
    let route = match decode_google_polyline(&encoded_polyline) {
        Ok(route) => route,
        Err(message) => return CachedRouteConflictResult::invalid(cache_generation, message),
    };
    if let Err(message) = validate_geometry_work(route.len(), cache.polygon_point_count) {
        return CachedRouteConflictResult::invalid(cache_generation, message);
    }
    let conflict = match first_route_conflict_index(&route, &cache.restrictions) {
        Ok(conflict) => conflict,
        Err(message) => return CachedRouteConflictResult::invalid(cache_generation, message),
    };
    CachedRouteConflictResult::ok(cache_generation, conflict.into_iter().collect::<Vec<u32>>())
}

/// Returns first-inside and first-nearest restriction indices in cached input
/// order. A preferred index also returns its distance so Dart can preserve the
/// current restriction's hysteresis without transferring every distance.
pub fn query_cached_point_proximity(
    latitude: f64,
    longitude: f64,
    expected_cache_generation: u32,
    preferred_restriction_index: Option<u32>,
) -> CachedPointProximityResult {
    let (cache_generation, cache) = match read_restriction_cache(expected_cache_generation) {
        Ok(cache) => cache,
        Err(error) => return CachedPointProximityResult::error(error),
    };
    let point = match GeoPoint::validated(latitude, longitude) {
        Ok(point) => point,
        Err(message) => return CachedPointProximityResult::invalid(cache_generation, message),
    };
    let preferred_index = match preferred_restriction_index {
        Some(index) => {
            let index = index as usize;
            if index >= cache.restrictions.len() {
                return CachedPointProximityResult::invalid(
                    cache_generation,
                    "preferred restriction index is out of range",
                );
            }
            Some(index)
        }
        None => None,
    };

    let mut inside_restriction_index = None;
    let mut nearest_restriction_index = None;
    let mut nearest_distance_meters = None;
    let mut preferred_distance_meters = None;

    for (restriction_index, restriction) in cache.restrictions.iter().enumerate() {
        let is_preferred = preferred_index == Some(restriction_index);
        let Some(restriction_bounds) = restriction.bounds else {
            continue;
        };
        let needs_inside_check =
            inside_restriction_index.is_none() && restriction_bounds.contains(point);
        let distance_lower_bound = restriction_bounds.latitude_distance_lower_bound_meters(point);
        if !is_preferred
            && !needs_inside_check
            && nearest_distance_meters.is_some_and(|nearest| distance_lower_bound > nearest)
        {
            continue;
        }

        let distance = restriction_distance_meters(point, restriction);
        if is_preferred {
            preferred_distance_meters = distance;
        }
        let Some(distance) = distance else {
            continue;
        };
        let index = match u32::try_from(restriction_index) {
            Ok(index) => index,
            Err(_) => {
                return CachedPointProximityResult::invalid(
                    cache_generation,
                    "restriction index does not fit into u32",
                );
            }
        };
        if distance == 0.0 && inside_restriction_index.is_none() {
            inside_restriction_index = Some(index);
        }
        if nearest_distance_meters.is_none_or(|nearest| distance < nearest) {
            nearest_restriction_index = Some(index);
            nearest_distance_meters = Some(distance);
        }
    }

    CachedPointProximityResult::ok(
        cache_generation,
        inside_restriction_index,
        nearest_restriction_index,
        nearest_distance_meters,
        preferred_distance_meters,
    )
}

/// Finds the first conflicting enforced restriction in one bridge call.
///
/// Coordinates are packed as `[latitude, longitude, ...]`. `area_point_counts`
/// partitions `polygon_lat_lng` into polygon areas, and
/// `restriction_area_counts` partitions those areas into restrictions. The
/// The returned list is empty or contains the first conflicting restriction's
/// index in the provided order.
pub fn analyze_route_conflicts(
    route_lat_lng: Vec<f64>,
    polygon_lat_lng: Vec<f64>,
    area_point_counts: Vec<u32>,
    restriction_area_counts: Vec<u32>,
) -> RouteConflictBatchResult {
    match analyze_route_conflicts_checked(
        &route_lat_lng,
        &polygon_lat_lng,
        &area_point_counts,
        &restriction_area_counts,
    ) {
        Ok(indices) => RouteConflictBatchResult::ok(indices),
        Err(message) => RouteConflictBatchResult::invalid(message),
    }
}

fn analyze_route_conflicts_checked(
    route_lat_lng: &[f64],
    polygon_lat_lng: &[f64],
    area_point_counts: &[u32],
    restriction_area_counts: &[u32],
) -> Result<Vec<u32>, String> {
    if !route_lat_lng.len().is_multiple_of(COORDINATE_STRIDE) {
        return Err("route coordinate buffer must contain latitude/longitude pairs".to_owned());
    }
    let route_point_count = route_lat_lng.len() / COORDINATE_STRIDE;
    if route_point_count > MAX_ROUTE_POINTS {
        return Err(format!(
            "route point count exceeds the {MAX_ROUTE_POINTS} item limit"
        ));
    }

    let route = parse_points(route_lat_lng)?;
    let restrictions =
        parse_restrictions(polygon_lat_lng, area_point_counts, restriction_area_counts)?;
    validate_geometry_work(route.len(), restrictions.polygon_point_count)?;
    let conflict = first_route_conflict_index(&route, &restrictions.restrictions)?;
    Ok(conflict.into_iter().collect())
}

fn checked_sum(values: &[u32], label: &str) -> Result<usize, String> {
    values.iter().try_fold(0usize, |total, value| {
        total
            .checked_add(*value as usize)
            .ok_or_else(|| format!("{label} overflowed"))
    })
}

fn restriction_cache_state() -> &'static RwLock<RestrictionCacheState> {
    RESTRICTION_CACHE.get_or_init(|| {
        RwLock::new(RestrictionCacheState {
            generation: 0,
            cache: None,
        })
    })
}

fn read_restriction_cache(
    expected_cache_generation: u32,
) -> Result<(u32, Arc<RestrictionCache>), CacheAccessError> {
    let state = restriction_cache_state()
        .read()
        .map_err(|_| CacheAccessError {
            status: GeometryCacheStatus::InternalError,
            cache_generation: 0,
            message: "restriction cache read lock is unavailable".to_owned(),
        })?;
    let Some(cache) = &state.cache else {
        return Err(CacheAccessError {
            status: GeometryCacheStatus::CacheUnavailable,
            cache_generation: state.generation,
            message: "restriction cache is unavailable".to_owned(),
        });
    };
    if expected_cache_generation == 0 || expected_cache_generation != state.generation {
        return Err(CacheAccessError {
            status: GeometryCacheStatus::GenerationMismatch,
            cache_generation: state.generation,
            message: format!(
                "restriction cache generation mismatch: expected \
                 {expected_cache_generation}, actual {}",
                state.generation
            ),
        });
    }
    Ok((state.generation, Arc::clone(cache)))
}

fn parse_restrictions(
    polygon_lat_lng: &[f64],
    area_point_counts: &[u32],
    restriction_area_counts: &[u32],
) -> Result<RestrictionCache, String> {
    if !polygon_lat_lng.len().is_multiple_of(COORDINATE_STRIDE) {
        return Err("polygon coordinate buffer must contain latitude/longitude pairs".to_owned());
    }
    if restriction_area_counts.len() > MAX_RESTRICTIONS {
        return Err(format!(
            "restriction count exceeds the {MAX_RESTRICTIONS} item limit"
        ));
    }
    if area_point_counts.len() > MAX_POLYGON_POINTS {
        return Err(format!(
            "area count exceeds the {MAX_POLYGON_POINTS} item limit"
        ));
    }

    let polygon_point_count = polygon_lat_lng.len() / COORDINATE_STRIDE;
    if polygon_point_count > MAX_POLYGON_POINTS {
        return Err(format!(
            "polygon point count exceeds the {MAX_POLYGON_POINTS} item limit"
        ));
    }
    let declared_area_count = checked_sum(restriction_area_counts, "restriction area counts")?;
    if declared_area_count != area_point_counts.len() {
        return Err("restriction area counts do not match the area list".to_owned());
    }
    let declared_polygon_points = checked_sum(area_point_counts, "area point counts")?;
    if declared_polygon_points != polygon_point_count {
        return Err("area point counts do not match the polygon coordinate buffer".to_owned());
    }

    let polygon_points = parse_points(polygon_lat_lng)?;
    let mut restrictions = Vec::with_capacity(restriction_area_counts.len());
    let mut area_count_cursor = 0usize;
    let mut polygon_point_cursor = 0usize;
    for area_count in restriction_area_counts {
        let mut areas = Vec::with_capacity(*area_count as usize);
        let mut restriction_bounds: Option<GeoBounds> = None;
        for _ in 0..*area_count {
            let point_count = area_point_counts
                .get(area_count_cursor)
                .copied()
                .ok_or_else(|| "area point count offset exceeds the area list".to_owned())?
                as usize;
            area_count_cursor += 1;
            let area_end = polygon_point_cursor
                .checked_add(point_count)
                .ok_or_else(|| "polygon point offset overflowed".to_owned())?;
            let area = polygon_points
                .get(polygon_point_cursor..area_end)
                .ok_or_else(|| "polygon point offsets exceed the coordinate buffer".to_owned())?;
            polygon_point_cursor = area_end;
            let bounds = if area.len() >= 3 {
                GeoBounds::from_points(area)
            } else {
                None
            };
            if let Some(area_bounds) = bounds {
                restriction_bounds = Some(
                    restriction_bounds.map_or(area_bounds, |current| current.union(area_bounds)),
                );
            }
            areas.push(AreaGeometry {
                points: area.to_vec(),
                bounds,
            });
        }
        restrictions.push(RestrictionGeometry {
            areas,
            bounds: restriction_bounds,
        });
    }
    Ok(RestrictionCache {
        restrictions,
        polygon_point_count,
    })
}

fn validate_geometry_work(
    route_point_count: usize,
    polygon_point_count: usize,
) -> Result<(), String> {
    let geometry_work_items = route_point_count
        .checked_mul(polygon_point_count)
        .ok_or_else(|| "geometry work estimate overflowed".to_owned())?;
    if geometry_work_items > MAX_GEOMETRY_WORK_ITEMS {
        return Err(format!(
            "geometry work exceeds the {MAX_GEOMETRY_WORK_ITEMS} item limit"
        ));
    }
    Ok(())
}

fn parse_points(buffer: &[f64]) -> Result<Vec<GeoPoint>, String> {
    buffer
        .chunks_exact(COORDINATE_STRIDE)
        .map(|pair| GeoPoint::validated(pair[0], pair[1]))
        .collect()
}

fn decode_google_polyline(encoded: &str) -> Result<Vec<GeoPoint>, String> {
    if encoded.len() > MAX_ENCODED_POLYLINE_BYTES {
        return Err(format!(
            "encoded polyline exceeds the {MAX_ENCODED_POLYLINE_BYTES} byte limit"
        ));
    }
    if !encoded.is_ascii() {
        return Err("encoded polyline must contain ASCII characters".to_owned());
    }

    let bytes = encoded.as_bytes();
    let mut index = 0usize;
    let mut latitude_e5 = 0i64;
    let mut longitude_e5 = 0i64;
    let mut route = Vec::new();
    while index < bytes.len() {
        let latitude_delta = decode_polyline_delta(bytes, &mut index)?;
        let longitude_delta = decode_polyline_delta(bytes, &mut index)?;
        latitude_e5 = latitude_e5
            .checked_add(latitude_delta)
            .ok_or_else(|| "encoded polyline latitude overflowed".to_owned())?;
        longitude_e5 = longitude_e5
            .checked_add(longitude_delta)
            .ok_or_else(|| "encoded polyline longitude overflowed".to_owned())?;
        let point = GeoPoint::validated(
            latitude_e5 as f64 / 100_000.0,
            longitude_e5 as f64 / 100_000.0,
        )?;
        route.push(point);
        if route.len() > MAX_ROUTE_POINTS {
            return Err(format!(
                "route point count exceeds the {MAX_ROUTE_POINTS} item limit"
            ));
        }
    }
    Ok(route)
}

fn decode_polyline_delta(bytes: &[u8], index: &mut usize) -> Result<i64, String> {
    let mut value = 0u64;
    let mut shift = 0u32;
    loop {
        let byte = bytes
            .get(*index)
            .copied()
            .ok_or_else(|| "encoded polyline ended inside a coordinate".to_owned())?;
        *index = index
            .checked_add(1)
            .ok_or_else(|| "encoded polyline offset overflowed".to_owned())?;
        let chunk = byte
            .checked_sub(63)
            .filter(|chunk| *chunk <= 63)
            .ok_or_else(|| "encoded polyline contains an invalid character".to_owned())?;
        let payload = u64::from(chunk & 0x1f);
        if shift >= u64::BITS || payload > (u64::MAX >> shift) {
            return Err("encoded polyline coordinate overflowed".to_owned());
        }
        value |= payload << shift;
        if chunk < 0x20 {
            break;
        }
        shift = shift
            .checked_add(5)
            .ok_or_else(|| "encoded polyline shift overflowed".to_owned())?;
    }

    let magnitude = i64::try_from(value >> 1)
        .map_err(|_| "encoded polyline coordinate exceeds i64".to_owned())?;
    if value & 1 == 0 {
        Ok(magnitude)
    } else {
        magnitude
            .checked_neg()
            .and_then(|negative| negative.checked_sub(1))
            .ok_or_else(|| "encoded polyline signed coordinate overflowed".to_owned())
    }
}

fn first_route_conflict_index(
    route: &[GeoPoint],
    restrictions: &[RestrictionGeometry],
) -> Result<Option<u32>, String> {
    if route.len() < 2 {
        return Ok(None);
    }
    let route_bounds =
        GeoBounds::from_points(route).ok_or_else(|| "route bounds are unavailable".to_owned())?;
    for (restriction_index, restriction) in restrictions.iter().enumerate() {
        let Some(restriction_bounds) = restriction.bounds else {
            continue;
        };
        if !route_bounds.intersects(restriction_bounds) {
            continue;
        }
        if restriction
            .areas
            .iter()
            .any(|area| route_intersects(route, route_bounds, area))
        {
            return u32::try_from(restriction_index)
                .map(Some)
                .map_err(|_| "restriction index does not fit into u32".to_owned());
        }
    }
    Ok(None)
}

fn restriction_distance_meters(point: GeoPoint, restriction: &RestrictionGeometry) -> Option<f64> {
    let mut closest = None;
    for area in &restriction.areas {
        let Some(area_bounds) = area.bounds else {
            continue;
        };
        if area_bounds.contains(point) && polygon_contains(point, &area.points) {
            return Some(0.0);
        }
        for (start, end) in area
            .points
            .iter()
            .zip(area.points.iter().cycle().skip(1))
            .take(area.points.len())
        {
            let distance = point_to_segment_meters(point, *start, *end);
            if closest.is_none_or(|current| distance < current) {
                closest = Some(distance);
            }
        }
    }
    closest
}

fn point_to_segment_meters(point: GeoPoint, start: GeoPoint, end: GeoPoint) -> f64 {
    let reference_latitude =
        (point.latitude + start.latitude + end.latitude) / 3.0 * std::f64::consts::PI / 180.0;
    let scale_longitude = METERS_PER_DEGREE * reference_latitude.cos();
    let point_x = (point.longitude - start.longitude) * scale_longitude;
    let point_y = (point.latitude - start.latitude) * METERS_PER_DEGREE;
    let segment_x = (end.longitude - start.longitude) * scale_longitude;
    let segment_y = (end.latitude - start.latitude) * METERS_PER_DEGREE;
    let length_squared = segment_x * segment_x + segment_y * segment_y;
    if length_squared == 0.0 {
        return (point_x * point_x + point_y * point_y).sqrt();
    }
    let projection = ((point_x * segment_x + point_y * segment_y) / length_squared).clamp(0.0, 1.0);
    let delta_x = point_x - segment_x * projection;
    let delta_y = point_y - segment_y * projection;
    (delta_x * delta_x + delta_y * delta_y).sqrt()
}

fn route_intersects(route: &[GeoPoint], route_bounds: GeoBounds, area: &AreaGeometry) -> bool {
    let Some(area_bounds) = area.bounds else {
        return false;
    };
    if !route_bounds.intersects(area_bounds) {
        return false;
    }
    if route
        .iter()
        .any(|point| area_bounds.contains(*point) && polygon_contains(*point, &area.points))
    {
        return true;
    }

    route.windows(2).any(|route_segment| {
        if !GeoBounds::from_pair(route_segment[0], route_segment[1]).intersects(area_bounds) {
            return false;
        }
        area.points
            .iter()
            .zip(area.points.iter().cycle().skip(1))
            .take(area.points.len())
            .any(|(polygon_start, polygon_end)| {
                segments_intersect(
                    route_segment[0],
                    route_segment[1],
                    *polygon_start,
                    *polygon_end,
                )
            })
    })
}

fn polygon_contains(point: GeoPoint, polygon: &[GeoPoint]) -> bool {
    let mut inside = false;
    for (start, end) in polygon
        .iter()
        .zip(polygon.iter().cycle().skip(1))
        .take(polygon.len())
    {
        if point_on_segment(point, *start, *end) {
            return true;
        }
        let intersects = ((start.latitude > point.latitude) != (end.latitude > point.latitude))
            && (point.longitude
                < (end.longitude - start.longitude) * (point.latitude - start.latitude)
                    / (end.latitude - start.latitude)
                    + start.longitude);
        if intersects {
            inside = !inside;
        }
    }
    inside
}

fn segments_intersect(a: GeoPoint, b: GeoPoint, c: GeoPoint, d: GeoPoint) -> bool {
    let ab_c = orientation(a, b, c);
    let ab_d = orientation(a, b, d);
    let cd_a = orientation(c, d, a);
    let cd_b = orientation(c, d, b);
    if ab_c != ab_d && cd_a != cd_b {
        return true;
    }
    (ab_c == 0 && point_on_segment(c, a, b))
        || (ab_d == 0 && point_on_segment(d, a, b))
        || (cd_a == 0 && point_on_segment(a, c, d))
        || (cd_b == 0 && point_on_segment(b, c, d))
}

fn orientation(a: GeoPoint, b: GeoPoint, c: GeoPoint) -> i8 {
    let value = (b.longitude - a.longitude) * (c.latitude - a.latitude)
        - (b.latitude - a.latitude) * (c.longitude - a.longitude);
    if value.abs() <= ORIENTATION_EPSILON {
        0
    } else if value > 0.0 {
        1
    } else {
        -1
    }
}

fn point_on_segment(point: GeoPoint, start: GeoPoint, end: GeoPoint) -> bool {
    let cross = (point.latitude - start.latitude) * (end.longitude - start.longitude)
        - (point.longitude - start.longitude) * (end.latitude - start.latitude);
    if cross.abs() > ON_SEGMENT_EPSILON {
        return false;
    }

    point.latitude >= start.latitude.min(end.latitude) - ON_SEGMENT_EPSILON
        && point.latitude <= start.latitude.max(end.latitude) + ON_SEGMENT_EPSILON
        && point.longitude >= start.longitude.min(end.longitude) - ON_SEGMENT_EPSILON
        && point.longitude <= start.longitude.max(end.longitude) + ON_SEGMENT_EPSILON
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;
    use std::error::Error;

    const SQUARE: [f64; 8] = [
        10.6600, 122.9400, 10.6600, 122.9600, 10.6800, 122.9600, 10.6800, 122.9400,
    ];

    fn analyze(route: &[f64]) -> RouteConflictBatchResult {
        analyze_route_conflicts(route.to_vec(), SQUARE.to_vec(), vec![4], vec![1])
    }

    #[test]
    fn crossing_route_conflicts() {
        let result = analyze(&[10.6500, 122.9500, 10.6900, 122.9500]);

        assert_eq!(result.status, GeometryBatchStatus::Ok);
        assert_eq!(result.conflicting_restriction_indices, vec![0]);
    }

    #[test]
    fn outside_route_does_not_conflict() {
        let result = analyze(&[10.6500, 122.9300, 10.6900, 122.9300]);

        assert_eq!(result.status, GeometryBatchStatus::Ok);
        assert!(result.conflicting_restriction_indices.is_empty());
    }

    #[test]
    fn boundary_contact_counts_as_conflict() {
        let result = analyze(&[10.6500, 122.9400, 10.6600, 122.9400]);

        assert_eq!(result.status, GeometryBatchStatus::Ok);
        assert_eq!(result.conflicting_restriction_indices, vec![0]);
    }

    #[test]
    fn bounds_prune_disjoint_geometry_without_losing_tolerant_boundaries() -> Result<(), String> {
        let points = parse_points(&SQUARE)?;
        let polygon_bounds = GeoBounds::from_points(&points)
            .ok_or_else(|| "square bounds are unavailable".to_owned())?;
        let far_route_bounds = GeoBounds::from_pair(
            GeoPoint {
                latitude: 10.65,
                longitude: 122.90,
            },
            GeoPoint {
                latitude: 10.69,
                longitude: 122.90,
            },
        );
        assert!(!polygon_bounds.intersects(far_route_bounds));

        let result = analyze(&[
            10.6500,
            122.9400,
            10.6600 - ON_SEGMENT_EPSILON / 2.0,
            122.9400,
        ]);
        assert_eq!(result.status, GeometryBatchStatus::Ok);
        assert_eq!(result.conflicting_restriction_indices, vec![0]);
        Ok(())
    }

    #[test]
    fn multiple_restrictions_return_the_first_input_index() {
        let mut polygons = SQUARE.to_vec();
        polygons.extend([
            10.7000, 122.9800, 10.7000, 123.0000, 10.7200, 123.0000, 10.7200, 122.9800,
        ]);
        let result = analyze_route_conflicts(
            vec![10.6500, 122.9500, 10.7100, 122.9900],
            polygons,
            vec![4, 4],
            vec![1, 1],
        );

        assert_eq!(result.status, GeometryBatchStatus::Ok);
        assert_eq!(result.conflicting_restriction_indices, vec![0]);
    }

    #[test]
    fn short_route_matches_dart_no_conflict_behavior() {
        let result = analyze(&[10.6700, 122.9500]);

        assert_eq!(result.status, GeometryBatchStatus::Ok);
        assert!(result.conflicting_restriction_indices.is_empty());
    }

    #[test]
    fn malformed_shapes_return_typed_invalid_status() {
        let result = analyze_route_conflicts(vec![10.0], SQUARE.to_vec(), vec![4], vec![1]);

        assert_eq!(result.status, GeometryBatchStatus::InvalidInput);
        assert!(result.error_message.is_some());
    }

    #[test]
    fn non_finite_coordinates_return_typed_invalid_status() {
        let result = analyze_route_conflicts(
            vec![10.0, 122.0, f64::NAN, 123.0],
            SQUARE.to_vec(),
            vec![4],
            vec![1],
        );

        assert_eq!(result.status, GeometryBatchStatus::InvalidInput);
        assert!(result.error_message.is_some());
    }

    #[test]
    fn areas_with_fewer_than_three_points_are_ignored() {
        let result = analyze_route_conflicts(
            vec![10.6500, 122.9500, 10.6900, 122.9500],
            vec![10.6600, 122.9400, 10.6800, 122.9400],
            vec![2],
            vec![1],
        );

        assert_eq!(result.status, GeometryBatchStatus::Ok);
        assert!(result.conflicting_restriction_indices.is_empty());
    }

    #[test]
    fn excessive_geometry_work_returns_typed_invalid_status() {
        let route = [10.0, 122.0].repeat(5_000);
        let polygon = [12.0, 124.0].repeat(4_001);
        let result = analyze_route_conflicts(route, polygon, vec![4_001], vec![1]);

        assert_eq!(result.status, GeometryBatchStatus::InvalidInput);
        assert!(result
            .error_message
            .as_deref()
            .is_some_and(|message| message.contains("geometry work")));
    }

    #[test]
    fn google_polyline_decoder_is_checked_and_preserves_e5_coordinates() {
        let decoded = decode_google_polyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@");
        assert!(decoded.as_ref().is_ok_and(|points| {
            points
                == &[
                    GeoPoint {
                        latitude: 38.5,
                        longitude: -120.2,
                    },
                    GeoPoint {
                        latitude: 40.7,
                        longitude: -120.95,
                    },
                    GeoPoint {
                        latitude: 43.252,
                        longitude: -126.453,
                    },
                ]
        }));
        assert!(decode_google_polyline("?").is_err());
        assert!(decode_google_polyline("!").is_err());
        assert!(decode_google_polyline("é").is_err());
    }

    #[test]
    fn cached_geometry_v2_is_versioned_atomic_and_preserves_proximity_order() {
        let unavailable = analyze_cached_encoded_route_conflicts("".to_owned(), 1);
        assert_eq!(unavailable.status, GeometryCacheStatus::CacheUnavailable);

        let installed = replace_restriction_cache(SQUARE.to_vec(), vec![4], vec![1]);
        assert_eq!(installed.status, GeometryCacheStatus::Ok);
        assert!(installed.cache_generation > 0);
        assert_eq!(installed.restriction_count, 1);
        let first_generation = installed.cache_generation;

        let crossing =
            analyze_cached_encoded_route_conflicts("oa_`AotlmV_yF?".to_owned(), first_generation);
        assert_eq!(crossing.status, GeometryCacheStatus::Ok);
        assert_eq!(crossing.cache_generation, first_generation);
        assert_eq!(crossing.conflicting_restriction_indices, vec![0]);

        let boundary = query_cached_point_proximity(10.67, 122.94, first_generation, Some(0));
        assert_eq!(boundary.status, GeometryCacheStatus::Ok);
        assert_eq!(boundary.inside_restriction_index, Some(0));
        assert_eq!(boundary.nearest_restriction_index, Some(0));
        assert_eq!(boundary.nearest_distance_meters, Some(0.0));
        assert_eq!(boundary.preferred_distance_meters, Some(0.0));

        let invalid_update = replace_restriction_cache(vec![10.0], vec![1], vec![1]);
        assert_eq!(invalid_update.status, GeometryCacheStatus::InvalidInput);
        let old_cache_survived =
            query_cached_point_proximity(10.67, 122.95, first_generation, None);
        assert_eq!(old_cache_survived.status, GeometryCacheStatus::Ok);
        assert_eq!(old_cache_survived.inside_restriction_index, Some(0));

        let mut polygons = SQUARE.to_vec();
        polygons.extend([
            10.7000, 122.9800, 10.7000, 123.0000, 10.7200, 123.0000, 10.7200, 122.9800,
        ]);
        let replaced = replace_restriction_cache(polygons, vec![4, 4], vec![1, 1]);
        assert_eq!(replaced.status, GeometryCacheStatus::Ok);
        assert!(replaced.cache_generation > first_generation);
        assert_eq!(replaced.restriction_count, 2);

        let stale = query_cached_point_proximity(10.71, 122.99, first_generation, None);
        assert_eq!(stale.status, GeometryCacheStatus::GenerationMismatch);
        assert_eq!(stale.cache_generation, replaced.cache_generation);

        let second =
            query_cached_point_proximity(10.71, 122.99, replaced.cache_generation, Some(0));
        assert_eq!(second.status, GeometryCacheStatus::Ok);
        assert_eq!(second.inside_restriction_index, Some(1));
        assert_eq!(second.nearest_restriction_index, Some(1));
        assert_eq!(second.nearest_distance_meters, Some(0.0));
        assert!(second
            .preferred_distance_meters
            .is_some_and(|distance| distance > 1_000.0));

        let invalid_preferred =
            query_cached_point_proximity(10.71, 122.99, replaced.cache_generation, Some(2));
        assert_eq!(invalid_preferred.status, GeometryCacheStatus::InvalidInput);

        let mut overlapping_polygons = SQUARE.to_vec();
        overlapping_polygons.extend(SQUARE);
        let overlapping = replace_restriction_cache(overlapping_polygons, vec![4, 4], vec![1, 1]);
        assert_eq!(overlapping.status, GeometryCacheStatus::Ok);
        let tied =
            query_cached_point_proximity(10.69, 122.95, overlapping.cache_generation, Some(1));
        assert_eq!(tied.status, GeometryCacheStatus::Ok);
        assert_eq!(tied.nearest_restriction_index, Some(0));
        assert!(tied.nearest_distance_meters.is_some_and(|nearest| {
            tied.preferred_distance_meters
                .is_some_and(|preferred| (nearest - preferred).abs() <= f64::EPSILON)
        }));
    }

    #[derive(Deserialize)]
    struct ParityFixture {
        coordinate_order: String,
        cases: Vec<ParityCase>,
    }

    #[derive(Deserialize)]
    struct ParityCase {
        name: String,
        route: Vec<[f64; 2]>,
        restrictions: Vec<ParityRestriction>,
        expected_conflict_indices: Vec<u32>,
    }

    #[derive(Deserialize)]
    struct ParityRestriction {
        areas: Vec<Vec<[f64; 2]>>,
    }

    #[test]
    fn shared_json_fixtures_match_rust() -> Result<(), Box<dyn Error>> {
        let fixture: ParityFixture = serde_json::from_str(include_str!(
            "../../../test/fixtures/route_restriction_parity.json"
        ))?;
        assert_eq!(fixture.coordinate_order, "latitude_longitude");

        for case in fixture.cases {
            let route_lat_lng = case.route.into_iter().flatten().collect();
            let mut polygon_lat_lng = Vec::new();
            let mut area_point_counts = Vec::new();
            let mut restriction_area_counts = Vec::new();
            for restriction in case.restrictions {
                restriction_area_counts.push(u32::try_from(restriction.areas.len())?);
                for area in restriction.areas {
                    area_point_counts.push(u32::try_from(area.len())?);
                    polygon_lat_lng.extend(area.into_iter().flatten());
                }
            }

            let result = analyze_route_conflicts(
                route_lat_lng,
                polygon_lat_lng,
                area_point_counts,
                restriction_area_counts,
            );
            assert_eq!(
                result.status,
                GeometryBatchStatus::Ok,
                "fixture: {}",
                case.name
            );
            assert_eq!(
                result.conflicting_restriction_indices, case.expected_conflict_indices,
                "fixture: {}",
                case.name
            );
        }
        Ok(())
    }
}
