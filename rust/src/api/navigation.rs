use std::panic::{catch_unwind, AssertUnwindSafe};
use std::sync::{OnceLock, RwLock};

const MAX_ENCODED_POLYLINE_BYTES: usize = 4_000_000;
const MAX_ROUTE_POINTS: usize = 200_000;
const MAX_BATCH_SAMPLES: usize = 256;
const SEGMENTS_PER_BLOCK: usize = 64;
const MAX_ACCEPTED_ACCURACY_METERS: f64 = 100.0;
const MAX_SAMPLE_AGE_MILLIS: i64 = 30_000;
const MAX_PLAUSIBLE_SPEED_METERS_PER_SECOND: f64 = 75.0;
const MOTION_ACCURACY_ALLOWANCE_MULTIPLIER: f64 = 2.0;
const OFF_ROUTE_BASE_THRESHOLD_METERS: f64 = 25.0;
const OFF_ROUTE_CONFIDENCE_RANGE_METERS: f64 = 100.0;
const OFF_ROUTE_EMA_ALPHA: f64 = 0.35;
const METERS_PER_DEGREE: f64 = 111_320.0;
const MIN_METERS_PER_LATITUDE_DEGREE: f64 = 110_500.0;
const MIN_SEGMENT_LENGTH_METERS: f64 = 0.01;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NavigationRouteStatus {
    Ok,
    InvalidInput,
    RouteUnavailable,
    GenerationMismatch,
    InternalError,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum NavigationSampleDisposition {
    Accepted,
    InvalidCoordinates,
    InvalidAccuracy,
    InvalidTimestamp,
    Stale,
    ImplausibleMotion,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NavigationRouteInstallResult {
    pub status: NavigationRouteStatus,
    pub route_generation: u32,
    pub point_count: u32,
    pub segment_count: u32,
    pub total_distance_meters: f64,
    pub error_message: Option<String>,
}

impl NavigationRouteInstallResult {
    fn ok(
        route_generation: u32,
        point_count: u32,
        segment_count: u32,
        total_distance_meters: f64,
    ) -> Self {
        Self {
            status: NavigationRouteStatus::Ok,
            route_generation,
            point_count,
            segment_count,
            total_distance_meters,
            error_message: None,
        }
    }

    fn error(status: NavigationRouteStatus, message: impl Into<String>) -> Self {
        Self {
            status,
            route_generation: 0,
            point_count: 0,
            segment_count: 0,
            total_distance_meters: 0.0,
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct NavigationRouteClearResult {
    pub status: NavigationRouteStatus,
    pub route_generation: u32,
    pub error_message: Option<String>,
}

impl NavigationRouteClearResult {
    fn ok(route_generation: u32) -> Self {
        Self {
            status: NavigationRouteStatus::Ok,
            route_generation,
            error_message: None,
        }
    }

    fn error(
        status: NavigationRouteStatus,
        route_generation: u32,
        message: impl Into<String>,
    ) -> Self {
        Self {
            status,
            route_generation,
            error_message: Some(message.into()),
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct NavigationGpsSample {
    pub latitude: f64,
    pub longitude: f64,
    pub accuracy_meters: f64,
    pub timestamp_millis: i64,
}

#[derive(Clone, Debug, PartialEq)]
pub struct NavigationSampleResult {
    pub input_index: u32,
    pub disposition: NavigationSampleDisposition,
    pub filtered_latitude: Option<f64>,
    pub filtered_longitude: Option<f64>,
    pub nearest_segment_index: Option<u32>,
    pub distance_from_route_meters: Option<f64>,
    pub route_progress_meters: Option<f64>,
    pub remaining_distance_meters: Option<f64>,
    pub route_heading_degrees: Option<f64>,
    pub off_route_confidence: Option<f64>,
}

impl NavigationSampleResult {
    fn rejected(input_index: u32, disposition: NavigationSampleDisposition) -> Self {
        Self {
            input_index,
            disposition,
            filtered_latitude: None,
            filtered_longitude: None,
            nearest_segment_index: None,
            distance_from_route_meters: None,
            route_progress_meters: None,
            remaining_distance_meters: None,
            route_heading_degrees: None,
            off_route_confidence: None,
        }
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct NavigationBatchResult {
    pub status: NavigationRouteStatus,
    pub route_generation: u32,
    pub accepted_count: u32,
    pub rejected_count: u32,
    pub samples: Vec<NavigationSampleResult>,
    pub error_message: Option<String>,
}

impl NavigationBatchResult {
    fn ok(
        route_generation: u32,
        accepted_count: u32,
        rejected_count: u32,
        samples: Vec<NavigationSampleResult>,
    ) -> Self {
        Self {
            status: NavigationRouteStatus::Ok,
            route_generation,
            accepted_count,
            rejected_count,
            samples,
            error_message: None,
        }
    }

    fn error(
        status: NavigationRouteStatus,
        route_generation: u32,
        message: impl Into<String>,
    ) -> Self {
        Self {
            status,
            route_generation,
            accepted_count: 0,
            rejected_count: 0,
            samples: Vec::new(),
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

#[derive(Clone, Copy, Debug)]
struct RouteBounds {
    minimum_latitude: f64,
    maximum_latitude: f64,
}

impl RouteBounds {
    fn from_segment(segment: &RouteSegment) -> Self {
        Self {
            minimum_latitude: segment.start.latitude.min(segment.end.latitude),
            maximum_latitude: segment.start.latitude.max(segment.end.latitude),
        }
    }

    fn include_segment(&mut self, segment: &RouteSegment) {
        self.minimum_latitude = self
            .minimum_latitude
            .min(segment.start.latitude)
            .min(segment.end.latitude);
        self.maximum_latitude = self
            .maximum_latitude
            .max(segment.start.latitude)
            .max(segment.end.latitude);
    }

    fn latitude_distance_lower_bound_meters(self, point: GeoPoint) -> f64 {
        if point.latitude < self.minimum_latitude {
            (self.minimum_latitude - point.latitude) * MIN_METERS_PER_LATITUDE_DEGREE
        } else if point.latitude > self.maximum_latitude {
            (point.latitude - self.maximum_latitude) * MIN_METERS_PER_LATITUDE_DEGREE
        } else {
            0.0
        }
    }
}

#[derive(Clone, Copy, Debug)]
struct RouteSegment {
    start: GeoPoint,
    end: GeoPoint,
    length_meters: f64,
    cumulative_start_meters: f64,
    heading_degrees: f64,
}

#[derive(Clone, Copy, Debug)]
struct RouteBlock {
    start_index: usize,
    end_index: usize,
    bounds: RouteBounds,
}

#[derive(Clone, Copy, Debug)]
struct NearestRoutePoint {
    segment_index: usize,
    distance_meters: f64,
    projection: f64,
}

#[derive(Clone, Debug)]
struct NavigationTracker {
    last_timestamp_millis: Option<i64>,
    last_raw_point: Option<GeoPoint>,
    last_raw_accuracy_meters: Option<f64>,
    filtered_point: Option<GeoPoint>,
    last_nearest_segment_index: Option<usize>,
    off_route_confidence: f64,
}

impl NavigationTracker {
    fn empty() -> Self {
        Self {
            last_timestamp_millis: None,
            last_raw_point: None,
            last_raw_accuracy_meters: None,
            filtered_point: None,
            last_nearest_segment_index: None,
            off_route_confidence: 0.0,
        }
    }
}

#[derive(Clone, Debug)]
struct ActiveRouteSession {
    point_count: usize,
    segments: Vec<RouteSegment>,
    blocks: Vec<RouteBlock>,
    total_distance_meters: f64,
    tracker: NavigationTracker,
}

impl ActiveRouteSession {
    fn build(encoded_polyline: &str) -> Result<Self, String> {
        let points = decode_google_polyline(encoded_polyline)?;
        if points.len() < 2 {
            return Err("active route must contain at least two points".to_owned());
        }

        let mut segments = Vec::with_capacity(points.len().saturating_sub(1));
        let mut total_distance_meters = 0.0;
        for pair in points.windows(2) {
            let Some(start) = pair.first().copied() else {
                continue;
            };
            let Some(end) = pair.get(1).copied() else {
                continue;
            };
            let length_meters = haversine_distance_meters(start, end);
            if !length_meters.is_finite() {
                return Err("active route contains a non-finite segment length".to_owned());
            }
            if length_meters < MIN_SEGMENT_LENGTH_METERS {
                continue;
            }
            segments.push(RouteSegment {
                start,
                end,
                length_meters,
                cumulative_start_meters: total_distance_meters,
                heading_degrees: initial_bearing_degrees(start, end),
            });
            total_distance_meters += length_meters;
        }
        if segments.is_empty() || !total_distance_meters.is_finite() {
            return Err("active route must contain at least one non-zero segment".to_owned());
        }

        let blocks = build_route_blocks(&segments)?;
        Ok(Self {
            point_count: points.len(),
            segments,
            blocks,
            total_distance_meters,
            tracker: NavigationTracker::empty(),
        })
    }

    fn process_samples(
        &mut self,
        samples: Vec<NavigationGpsSample>,
        route_generation: u32,
    ) -> NavigationBatchResult {
        if samples.is_empty() {
            return NavigationBatchResult::error(
                NavigationRouteStatus::InvalidInput,
                route_generation,
                "GPS sample batch must not be empty",
            );
        }
        if samples.len() > MAX_BATCH_SAMPLES {
            return NavigationBatchResult::error(
                NavigationRouteStatus::InvalidInput,
                route_generation,
                format!("GPS sample batch exceeds the {MAX_BATCH_SAMPLES} item limit"),
            );
        }

        let newest_timestamp_millis = samples
            .iter()
            .filter_map(|sample| (sample.timestamp_millis > 0).then_some(sample.timestamp_millis))
            .max();
        let mut results = Vec::with_capacity(samples.len());
        let mut accepted_count = 0u32;
        let mut rejected_count = 0u32;

        for (index, sample) in samples.into_iter().enumerate() {
            let input_index = match u32::try_from(index) {
                Ok(value) => value,
                Err(_) => {
                    return NavigationBatchResult::error(
                        NavigationRouteStatus::InternalError,
                        route_generation,
                        "GPS sample index does not fit into u32",
                    );
                }
            };
            let disposition = self.validate_sample(&sample, newest_timestamp_millis);
            if disposition != NavigationSampleDisposition::Accepted {
                rejected_count = rejected_count.saturating_add(1);
                results.push(NavigationSampleResult::rejected(input_index, disposition));
                continue;
            }

            let raw_point = match GeoPoint::validated(sample.latitude, sample.longitude) {
                Ok(point) => point,
                Err(_) => {
                    rejected_count = rejected_count.saturating_add(1);
                    results.push(NavigationSampleResult::rejected(
                        input_index,
                        NavigationSampleDisposition::InvalidCoordinates,
                    ));
                    continue;
                }
            };
            let filtered_point = smooth_point(
                self.tracker.filtered_point,
                raw_point,
                sample.accuracy_meters,
            );
            let nearest = match self.nearest_route_point(filtered_point) {
                Some(nearest) => nearest,
                None => {
                    return NavigationBatchResult::error(
                        NavigationRouteStatus::InternalError,
                        route_generation,
                        "active route has no queryable segments",
                    );
                }
            };
            let Some(segment) = self.segments.get(nearest.segment_index).copied() else {
                return NavigationBatchResult::error(
                    NavigationRouteStatus::InternalError,
                    route_generation,
                    "nearest route segment is unavailable",
                );
            };
            let progress_meters = (segment.cumulative_start_meters
                + segment.length_meters * nearest.projection)
                .clamp(0.0, self.total_distance_meters);
            let remaining_distance_meters = (self.total_distance_meters - progress_meters).max(0.0);
            let instantaneous_off_route_confidence =
                off_route_confidence(nearest.distance_meters, sample.accuracy_meters);
            self.tracker.off_route_confidence = if self.tracker.last_timestamp_millis.is_some() {
                OFF_ROUTE_EMA_ALPHA * instantaneous_off_route_confidence
                    + (1.0 - OFF_ROUTE_EMA_ALPHA) * self.tracker.off_route_confidence
            } else {
                instantaneous_off_route_confidence
            };
            self.tracker.last_timestamp_millis = Some(sample.timestamp_millis);
            self.tracker.last_raw_point = Some(raw_point);
            self.tracker.last_raw_accuracy_meters = Some(sample.accuracy_meters);
            self.tracker.filtered_point = Some(filtered_point);
            self.tracker.last_nearest_segment_index = Some(nearest.segment_index);

            accepted_count = accepted_count.saturating_add(1);
            results.push(NavigationSampleResult {
                input_index,
                disposition: NavigationSampleDisposition::Accepted,
                filtered_latitude: Some(filtered_point.latitude),
                filtered_longitude: Some(filtered_point.longitude),
                nearest_segment_index: u32::try_from(nearest.segment_index).ok(),
                distance_from_route_meters: Some(nearest.distance_meters),
                route_progress_meters: Some(progress_meters),
                remaining_distance_meters: Some(remaining_distance_meters),
                route_heading_degrees: Some(segment.heading_degrees),
                off_route_confidence: Some(self.tracker.off_route_confidence),
            });
        }

        NavigationBatchResult::ok(route_generation, accepted_count, rejected_count, results)
    }

    fn validate_sample(
        &self,
        sample: &NavigationGpsSample,
        newest_timestamp_millis: Option<i64>,
    ) -> NavigationSampleDisposition {
        if GeoPoint::validated(sample.latitude, sample.longitude).is_err() {
            return NavigationSampleDisposition::InvalidCoordinates;
        }
        if !sample.accuracy_meters.is_finite()
            || sample.accuracy_meters < 0.0
            || sample.accuracy_meters > MAX_ACCEPTED_ACCURACY_METERS
        {
            return NavigationSampleDisposition::InvalidAccuracy;
        }
        if sample.timestamp_millis <= 0 {
            return NavigationSampleDisposition::InvalidTimestamp;
        }
        if self
            .tracker
            .last_timestamp_millis
            .is_some_and(|last| sample.timestamp_millis <= last)
        {
            return NavigationSampleDisposition::Stale;
        }
        if newest_timestamp_millis.is_some_and(|newest| {
            newest.saturating_sub(sample.timestamp_millis) > MAX_SAMPLE_AGE_MILLIS
        }) {
            return NavigationSampleDisposition::Stale;
        }

        if let (Some(last_point), Some(last_timestamp), Some(last_accuracy)) = (
            self.tracker.last_raw_point,
            self.tracker.last_timestamp_millis,
            self.tracker.last_raw_accuracy_meters,
        ) {
            let elapsed_millis = sample.timestamp_millis.saturating_sub(last_timestamp);
            if elapsed_millis > 0 {
                let elapsed_seconds = elapsed_millis as f64 / 1_000.0;
                let distance_meters = haversine_distance_meters(
                    last_point,
                    GeoPoint {
                        latitude: sample.latitude,
                        longitude: sample.longitude,
                    },
                );
                let accuracy_allowance =
                    (last_accuracy + sample.accuracy_meters) * MOTION_ACCURACY_ALLOWANCE_MULTIPLIER;
                let plausible_distance =
                    MAX_PLAUSIBLE_SPEED_METERS_PER_SECOND * elapsed_seconds + accuracy_allowance;
                if distance_meters > plausible_distance {
                    return NavigationSampleDisposition::ImplausibleMotion;
                }
            }
        }
        NavigationSampleDisposition::Accepted
    }

    fn nearest_route_point(&self, point: GeoPoint) -> Option<NearestRoutePoint> {
        let mut best = self
            .tracker
            .last_nearest_segment_index
            .and_then(|index| self.project_onto_segment(point, index));

        for block in &self.blocks {
            if best.is_some_and(|candidate| {
                block.bounds.latitude_distance_lower_bound_meters(point) > candidate.distance_meters
            }) {
                continue;
            }
            for segment_index in block.start_index..block.end_index {
                let Some(candidate) = self.project_onto_segment(point, segment_index) else {
                    continue;
                };
                if best.is_none_or(|current| candidate.distance_meters < current.distance_meters) {
                    best = Some(candidate);
                }
            }
        }
        best
    }

    fn project_onto_segment(
        &self,
        point: GeoPoint,
        segment_index: usize,
    ) -> Option<NearestRoutePoint> {
        let segment = self.segments.get(segment_index)?;
        let (distance_meters, projection) =
            point_to_segment_distance_and_projection(point, segment.start, segment.end);
        if !distance_meters.is_finite() || !projection.is_finite() {
            return None;
        }
        Some(NearestRoutePoint {
            segment_index,
            distance_meters,
            projection,
        })
    }
}

#[derive(Debug)]
struct ActiveRouteState {
    generation: u32,
    session: Option<ActiveRouteSession>,
}

static ACTIVE_ROUTE: OnceLock<RwLock<ActiveRouteState>> = OnceLock::new();

/// Decodes and indexes one process-local active route. Invalid input is atomic:
/// it never replaces the current route or advances its generation.
pub fn install_active_route(encoded_polyline: String) -> NavigationRouteInstallResult {
    match catch_unwind(AssertUnwindSafe(|| {
        install_active_route_checked(encoded_polyline)
    })) {
        Ok(result) => result,
        Err(_) => NavigationRouteInstallResult::error(
            NavigationRouteStatus::InternalError,
            "active route installation failed internally",
        ),
    }
}

/// Processes an ordered GPS batch against the requested route generation.
/// Individual bad samples receive typed dispositions; route/session failures
/// are returned as a typed batch status.
pub fn process_active_route_samples(
    samples: Vec<NavigationGpsSample>,
    expected_route_generation: u32,
) -> NavigationBatchResult {
    match catch_unwind(AssertUnwindSafe(|| {
        process_active_route_samples_checked(samples, expected_route_generation)
    })) {
        Ok(result) => result,
        Err(_) => NavigationBatchResult::error(
            NavigationRouteStatus::InternalError,
            0,
            "active route GPS processing failed internally",
        ),
    }
}

/// Clears only the route generation requested by Dart, preventing a delayed
/// cleanup from deleting a newer navigation session.
pub fn clear_active_route(expected_route_generation: u32) -> NavigationRouteClearResult {
    match catch_unwind(AssertUnwindSafe(|| {
        clear_active_route_checked(expected_route_generation)
    })) {
        Ok(result) => result,
        Err(_) => NavigationRouteClearResult::error(
            NavigationRouteStatus::InternalError,
            0,
            "active route cleanup failed internally",
        ),
    }
}

fn active_route_state() -> &'static RwLock<ActiveRouteState> {
    ACTIVE_ROUTE.get_or_init(|| {
        RwLock::new(ActiveRouteState {
            generation: 0,
            session: None,
        })
    })
}

fn install_active_route_checked(encoded_polyline: String) -> NavigationRouteInstallResult {
    let session = match ActiveRouteSession::build(&encoded_polyline) {
        Ok(session) => session,
        Err(message) => {
            return NavigationRouteInstallResult::error(
                NavigationRouteStatus::InvalidInput,
                message,
            );
        }
    };
    let point_count = match u32::try_from(session.point_count) {
        Ok(count) => count,
        Err(_) => {
            return NavigationRouteInstallResult::error(
                NavigationRouteStatus::InternalError,
                "active route point count does not fit into u32",
            );
        }
    };
    let segment_count = match u32::try_from(session.segments.len()) {
        Ok(count) => count,
        Err(_) => {
            return NavigationRouteInstallResult::error(
                NavigationRouteStatus::InternalError,
                "active route segment count does not fit into u32",
            );
        }
    };
    let total_distance_meters = session.total_distance_meters;
    let mut state = match active_route_state().write() {
        Ok(state) => state,
        Err(_) => {
            return NavigationRouteInstallResult::error(
                NavigationRouteStatus::InternalError,
                "active route write lock is unavailable",
            );
        }
    };
    let next_generation = match state.generation.checked_add(1) {
        Some(generation) if generation != 0 => generation,
        _ => {
            return NavigationRouteInstallResult::error(
                NavigationRouteStatus::InternalError,
                "active route generation is exhausted",
            );
        }
    };
    state.session = Some(session);
    state.generation = next_generation;
    NavigationRouteInstallResult::ok(
        next_generation,
        point_count,
        segment_count,
        total_distance_meters,
    )
}

fn process_active_route_samples_checked(
    samples: Vec<NavigationGpsSample>,
    expected_route_generation: u32,
) -> NavigationBatchResult {
    if expected_route_generation == 0 {
        return NavigationBatchResult::error(
            NavigationRouteStatus::InvalidInput,
            0,
            "expected route generation must be non-zero",
        );
    }
    if samples.len() > MAX_BATCH_SAMPLES {
        return NavigationBatchResult::error(
            NavigationRouteStatus::InvalidInput,
            expected_route_generation,
            format!("GPS sample batch exceeds the {MAX_BATCH_SAMPLES} item limit"),
        );
    }
    let mut state = match active_route_state().write() {
        Ok(state) => state,
        Err(_) => {
            return NavigationBatchResult::error(
                NavigationRouteStatus::InternalError,
                0,
                "active route write lock is unavailable",
            );
        }
    };
    if state.generation != expected_route_generation {
        return NavigationBatchResult::error(
            NavigationRouteStatus::GenerationMismatch,
            state.generation,
            format!(
                "active route generation mismatch: expected \
                 {expected_route_generation}, actual {}",
                state.generation
            ),
        );
    }
    let generation = state.generation;
    let Some(session) = state.session.as_mut() else {
        return NavigationBatchResult::error(
            NavigationRouteStatus::RouteUnavailable,
            generation,
            "active route is unavailable",
        );
    };
    session.process_samples(samples, generation)
}

fn clear_active_route_checked(expected_route_generation: u32) -> NavigationRouteClearResult {
    if expected_route_generation == 0 {
        return NavigationRouteClearResult::error(
            NavigationRouteStatus::InvalidInput,
            0,
            "expected route generation must be non-zero",
        );
    }
    let mut state = match active_route_state().write() {
        Ok(state) => state,
        Err(_) => {
            return NavigationRouteClearResult::error(
                NavigationRouteStatus::InternalError,
                0,
                "active route write lock is unavailable",
            );
        }
    };
    if state.generation != expected_route_generation {
        return NavigationRouteClearResult::error(
            NavigationRouteStatus::GenerationMismatch,
            state.generation,
            format!(
                "active route generation mismatch: expected \
                 {expected_route_generation}, actual {}",
                state.generation
            ),
        );
    }
    if state.session.is_none() {
        return NavigationRouteClearResult::error(
            NavigationRouteStatus::RouteUnavailable,
            state.generation,
            "active route is already clear",
        );
    }
    state.session = None;
    NavigationRouteClearResult::ok(state.generation)
}

fn build_route_blocks(segments: &[RouteSegment]) -> Result<Vec<RouteBlock>, String> {
    let mut blocks = Vec::with_capacity(
        segments
            .len()
            .saturating_add(SEGMENTS_PER_BLOCK.saturating_sub(1))
            / SEGMENTS_PER_BLOCK,
    );
    for (block_index, chunk) in segments.chunks(SEGMENTS_PER_BLOCK).enumerate() {
        let Some(first) = chunk.first() else {
            continue;
        };
        let start_index = block_index
            .checked_mul(SEGMENTS_PER_BLOCK)
            .ok_or_else(|| "route block offset overflowed".to_owned())?;
        let end_index = start_index
            .checked_add(chunk.len())
            .ok_or_else(|| "route block end overflowed".to_owned())?;
        let mut bounds = RouteBounds::from_segment(first);
        for segment in &chunk[1..] {
            bounds.include_segment(segment);
        }
        blocks.push(RouteBlock {
            start_index,
            end_index,
            bounds,
        });
    }
    if blocks.is_empty() {
        return Err("active route block index is empty".to_owned());
    }
    Ok(blocks)
}

fn decode_google_polyline(encoded: &str) -> Result<Vec<GeoPoint>, String> {
    if encoded.is_empty() {
        return Err("encoded polyline must not be empty".to_owned());
    }
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
        route.push(GeoPoint::validated(
            latitude_e5 as f64 / 100_000.0,
            longitude_e5 as f64 / 100_000.0,
        )?);
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

fn smooth_point(previous: Option<GeoPoint>, current: GeoPoint, accuracy_meters: f64) -> GeoPoint {
    let Some(previous) = previous else {
        return current;
    };
    let alpha = (20.0 / (accuracy_meters + 20.0)).clamp(0.15, 0.75);
    GeoPoint {
        latitude: previous.latitude + (current.latitude - previous.latitude) * alpha,
        longitude: previous.longitude + (current.longitude - previous.longitude) * alpha,
    }
}

fn off_route_confidence(distance_meters: f64, accuracy_meters: f64) -> f64 {
    let threshold = OFF_ROUTE_BASE_THRESHOLD_METERS + accuracy_meters.max(0.0);
    ((distance_meters - threshold) / OFF_ROUTE_CONFIDENCE_RANGE_METERS).clamp(0.0, 1.0)
}

fn point_to_segment_distance_and_projection(
    point: GeoPoint,
    start: GeoPoint,
    end: GeoPoint,
) -> (f64, f64) {
    let reference_latitude =
        (point.latitude + start.latitude + end.latitude) / 3.0 * std::f64::consts::PI / 180.0;
    let scale_longitude = METERS_PER_DEGREE * reference_latitude.cos().abs();
    let point_x = (point.longitude - start.longitude) * scale_longitude;
    let point_y = (point.latitude - start.latitude) * METERS_PER_DEGREE;
    let segment_x = (end.longitude - start.longitude) * scale_longitude;
    let segment_y = (end.latitude - start.latitude) * METERS_PER_DEGREE;
    let length_squared = segment_x * segment_x + segment_y * segment_y;
    if length_squared <= f64::EPSILON {
        return ((point_x * point_x + point_y * point_y).sqrt(), 0.0);
    }
    let projection = ((point_x * segment_x + point_y * segment_y) / length_squared).clamp(0.0, 1.0);
    let delta_x = point_x - segment_x * projection;
    let delta_y = point_y - segment_y * projection;
    ((delta_x * delta_x + delta_y * delta_y).sqrt(), projection)
}

fn haversine_distance_meters(first: GeoPoint, second: GeoPoint) -> f64 {
    const EARTH_RADIUS_METERS: f64 = 6_371_000.0;
    let first_latitude = first.latitude.to_radians();
    let second_latitude = second.latitude.to_radians();
    let latitude_delta = (second.latitude - first.latitude).to_radians();
    let longitude_delta = (second.longitude - first.longitude).to_radians();
    let sin_latitude = (latitude_delta / 2.0).sin();
    let sin_longitude = (longitude_delta / 2.0).sin();
    let haversine = (sin_latitude * sin_latitude
        + first_latitude.cos() * second_latitude.cos() * sin_longitude * sin_longitude)
        .clamp(0.0, 1.0);
    2.0 * EARTH_RADIUS_METERS * haversine.sqrt().asin()
}

fn initial_bearing_degrees(first: GeoPoint, second: GeoPoint) -> f64 {
    let first_latitude = first.latitude.to_radians();
    let second_latitude = second.latitude.to_radians();
    let longitude_delta = (second.longitude - first.longitude).to_radians();
    let y = longitude_delta.sin() * second_latitude.cos();
    let x = first_latitude.cos() * second_latitude.sin()
        - first_latitude.sin() * second_latitude.cos() * longitude_delta.cos();
    y.atan2(x).to_degrees().rem_euclid(360.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    const SAMPLE_ROUTE: &str = "o~b`AotlmV?gEgEgE";

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct ParityFixture {
        encoded_polyline: String,
        samples: Vec<ParitySample>,
        expected_dispositions: Vec<String>,
        expected_accepted_count: u32,
        expected_rejected_count: u32,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct ParitySample {
        latitude: f64,
        longitude: f64,
        accuracy_meters: f64,
        timestamp_millis: i64,
    }

    fn sample(
        latitude: f64,
        longitude: f64,
        accuracy_meters: f64,
        timestamp_millis: i64,
    ) -> NavigationGpsSample {
        NavigationGpsSample {
            latitude,
            longitude,
            accuracy_meters,
            timestamp_millis,
        }
    }

    #[test]
    fn route_is_decoded_indexed_and_progressed_in_one_session() -> Result<(), String> {
        let mut route = ActiveRouteSession::build(SAMPLE_ROUTE)?;
        assert_eq!(route.point_count, 3);
        assert_eq!(route.segments.len(), 2);
        assert_eq!(route.blocks.len(), 1);
        assert!(route.total_distance_meters > 150.0);

        let result = route.process_samples(vec![sample(10.67, 122.9505, 5.0, 1_000)], 7);
        assert_eq!(result.status, NavigationRouteStatus::Ok);
        assert_eq!(result.accepted_count, 1);
        assert_eq!(result.rejected_count, 0);
        let accepted = result
            .samples
            .first()
            .ok_or_else(|| "accepted result is missing".to_owned())?;
        assert_eq!(accepted.disposition, NavigationSampleDisposition::Accepted);
        assert!(accepted
            .route_progress_meters
            .is_some_and(|progress| progress > 30.0));
        assert!(accepted
            .remaining_distance_meters
            .is_some_and(|remaining| remaining > 50.0));
        assert!(accepted
            .distance_from_route_meters
            .is_some_and(|distance| distance < 2.0));
        Ok(())
    }

    #[test]
    fn smoothing_rejection_and_off_route_confidence_are_deterministic() -> Result<(), String> {
        let mut route = ActiveRouteSession::build(SAMPLE_ROUTE)?;
        let result = route.process_samples(
            vec![
                sample(10.67, 122.95, 5.0, 10_000),
                sample(10.67, 122.95, 101.0, 11_000),
                sample(10.67, 122.95, 5.0, 9_000),
                sample(10.69, 122.99, 5.0, 12_000),
                sample(10.672, 122.951, 5.0, 25_000),
            ],
            4,
        );
        assert_eq!(result.status, NavigationRouteStatus::Ok);
        assert_eq!(result.accepted_count, 2);
        assert_eq!(result.rejected_count, 3);
        assert_eq!(
            result.samples.get(1).map(|item| item.disposition),
            Some(NavigationSampleDisposition::InvalidAccuracy)
        );
        assert_eq!(
            result.samples.get(2).map(|item| item.disposition),
            Some(NavigationSampleDisposition::Stale)
        );
        assert_eq!(
            result.samples.get(3).map(|item| item.disposition),
            Some(NavigationSampleDisposition::ImplausibleMotion)
        );
        assert!(result
            .samples
            .get(4)
            .and_then(|item| item.off_route_confidence)
            .is_some_and(|confidence| confidence > 0.0));
        Ok(())
    }

    #[test]
    fn malformed_and_oversized_inputs_return_typed_errors() {
        let malformed = install_active_route("?".to_owned());
        assert_eq!(malformed.status, NavigationRouteStatus::InvalidInput);

        let route = ActiveRouteSession::build(SAMPLE_ROUTE);
        assert!(route.is_ok());
        let mut route = match route {
            Ok(route) => route,
            Err(_) => return,
        };
        let oversized = route.process_samples(
            vec![sample(10.67, 122.95, 5.0, 1_000); MAX_BATCH_SAMPLES + 1],
            1,
        );
        assert_eq!(oversized.status, NavigationRouteStatus::InvalidInput);
        assert!(oversized.samples.is_empty());
    }

    #[test]
    fn public_lifecycle_is_generation_guarded_and_atomic() {
        let installed = install_active_route(SAMPLE_ROUTE.to_owned());
        assert_eq!(installed.status, NavigationRouteStatus::Ok);
        assert!(installed.route_generation > 0);

        let invalid = install_active_route("?".to_owned());
        assert_eq!(invalid.status, NavigationRouteStatus::InvalidInput);

        let still_active = process_active_route_samples(
            vec![sample(10.67, 122.95, 5.0, 1_000)],
            installed.route_generation,
        );
        assert_eq!(still_active.status, NavigationRouteStatus::Ok);

        let stale_clear = clear_active_route(installed.route_generation.saturating_add(1));
        assert_eq!(
            stale_clear.status,
            NavigationRouteStatus::GenerationMismatch
        );
        let cleared = clear_active_route(installed.route_generation);
        assert_eq!(cleared.status, NavigationRouteStatus::Ok);
        let unavailable = process_active_route_samples(
            vec![sample(10.67, 122.95, 5.0, 2_000)],
            installed.route_generation,
        );
        assert_eq!(unavailable.status, NavigationRouteStatus::RouteUnavailable);
    }

    #[test]
    fn shared_dart_rust_fixture_preserves_batch_dispositions() -> Result<(), String> {
        let fixture: ParityFixture = serde_json::from_str(include_str!(
            "../../../test/fixtures/active_route_navigation_parity.json"
        ))
        .map_err(|error| error.to_string())?;
        let mut route = ActiveRouteSession::build(&fixture.encoded_polyline)?;
        let result = route.process_samples(
            fixture
                .samples
                .into_iter()
                .map(|item| {
                    sample(
                        item.latitude,
                        item.longitude,
                        item.accuracy_meters,
                        item.timestamp_millis,
                    )
                })
                .collect(),
            9,
        );
        let actual_dispositions = result
            .samples
            .iter()
            .map(|item| match item.disposition {
                NavigationSampleDisposition::Accepted => "accepted",
                NavigationSampleDisposition::InvalidCoordinates => "invalidCoordinates",
                NavigationSampleDisposition::InvalidAccuracy => "invalidAccuracy",
                NavigationSampleDisposition::InvalidTimestamp => "invalidTimestamp",
                NavigationSampleDisposition::Stale => "stale",
                NavigationSampleDisposition::ImplausibleMotion => "implausibleMotion",
            })
            .collect::<Vec<_>>();
        assert_eq!(result.accepted_count, fixture.expected_accepted_count);
        assert_eq!(result.rejected_count, fixture.expected_rejected_count);
        assert_eq!(actual_dispositions, fixture.expected_dispositions);
        Ok(())
    }
}
