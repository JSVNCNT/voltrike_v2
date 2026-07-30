use image::codecs::jpeg::JpegEncoder;
use image::imageops::FilterType;
use image::metadata::Orientation;
use image::{DynamicImage, GenericImageView, ImageDecoder, ImageFormat, ImageReader, Limits};
use std::fs::{self, File, OpenOptions};
use std::io::{BufReader, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Instant;

const MAX_SOURCE_BYTES: u64 = 32 * 1024 * 1024;
const MAX_SOURCE_DIMENSION: u32 = 4_096;
const MAX_DECODE_PIXELS: u64 = 8_000_000;
const MAX_DECODE_ALLOCATION_BYTES: u64 = 64 * 1024 * 1024;
const MAX_TARGET_WIDTH: u32 = 2_600;
const MAX_OUTPUT_BYTES: u64 = 4 * 1024 * 1024;
const JPEG_RETRY_THRESHOLD_BYTES: usize = 3 * 1024 * 1024;
const JPEG_RETRY_WIDTH: u32 = 1_000;
const INITIAL_JPEG_QUALITY: u8 = 78;
const RETRY_JPEG_QUALITY: u8 = 72;
const ASPECT_RATIO_TOLERANCE: f64 = 0.01;
const MIN_TARGET_ASPECT_RATIO: f64 = 0.25;
const MAX_TARGET_ASPECT_RATIO: f64 = 4.0;
static NEXT_OUTPUT_ID: AtomicU64 = AtomicU64::new(0);

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RegistrationImageStatus {
    Ok,
    InvalidRequest,
    SourceUnavailable,
    SourceTooLarge,
    UnsupportedFormat,
    DecodeLimitExceeded,
    DecodeFailed,
    EncodeFailed,
    OutputTooLarge,
    WriteFailed,
    NativePanic,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RegistrationImagePreparationResult {
    pub status: RegistrationImageStatus,
    pub output_path: Option<String>,
    pub source_width: u32,
    pub source_height: u32,
    pub output_width: u32,
    pub output_height: u32,
    pub output_bytes: u64,
    pub orientation_applied: bool,
    pub used_size_retry: bool,
    pub decode_micros: u64,
    pub transform_micros: u64,
    pub encode_micros: u64,
    pub total_micros: u64,
    pub diagnostic: Option<String>,
}

impl RegistrationImagePreparationResult {
    fn success(
        output_path: &Path,
        source_dimensions: (u32, u32),
        output_dimensions: (u32, u32),
        output_bytes: u64,
        orientation_applied: bool,
        used_size_retry: bool,
        timings: ImagePreparationTimings,
    ) -> Self {
        Self {
            status: RegistrationImageStatus::Ok,
            output_path: Some(output_path.to_string_lossy().into_owned()),
            source_width: source_dimensions.0,
            source_height: source_dimensions.1,
            output_width: output_dimensions.0,
            output_height: output_dimensions.1,
            output_bytes,
            orientation_applied,
            used_size_retry,
            decode_micros: timings.decode_micros,
            transform_micros: timings.transform_micros,
            encode_micros: timings.encode_micros,
            total_micros: timings.total_micros,
            diagnostic: None,
        }
    }

    fn failure(status: RegistrationImageStatus, diagnostic: impl Into<String>) -> Self {
        Self {
            status,
            output_path: None,
            source_width: 0,
            source_height: 0,
            output_width: 0,
            output_height: 0,
            output_bytes: 0,
            orientation_applied: false,
            used_size_retry: false,
            decode_micros: 0,
            transform_micros: 0,
            encode_micros: 0,
            total_micros: 0,
            diagnostic: Some(diagnostic.into()),
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ImagePreparationTimings {
    pub decode_micros: u64,
    pub transform_micros: u64,
    pub encode_micros: u64,
    pub total_micros: u64,
}

/// Experimental file-to-file registration image processor.
///
/// The bridge accepts paths rather than encoded bytes so a camera image is not
/// copied through Dart and flutter_rust_bridge. The bounds are deliberately
/// fixed by the native implementation; callers cannot weaken them.
pub fn prepare_registration_image_file(
    source_path: String,
    output_path: String,
    target_aspect_ratio: f64,
    target_width: u32,
) -> RegistrationImagePreparationResult {
    let result = std::panic::catch_unwind(|| {
        prepare_registration_image_file_inner(
            PathBuf::from(source_path),
            PathBuf::from(output_path),
            target_aspect_ratio,
            target_width,
        )
    });
    match result {
        Ok(preparation) => preparation,
        Err(_) => RegistrationImagePreparationResult::failure(
            RegistrationImageStatus::NativePanic,
            "the native image decoder terminated unexpectedly",
        ),
    }
}

fn prepare_registration_image_file_inner(
    source_path: PathBuf,
    output_path: PathBuf,
    target_aspect_ratio: f64,
    target_width: u32,
) -> RegistrationImagePreparationResult {
    let total_started = Instant::now();
    if let Err(message) = validate_request(
        &source_path,
        &output_path,
        target_aspect_ratio,
        target_width,
    ) {
        return RegistrationImagePreparationResult::failure(
            RegistrationImageStatus::InvalidRequest,
            message,
        );
    }

    let metadata = match fs::metadata(&source_path) {
        Ok(metadata) if metadata.is_file() && metadata.len() > 0 => metadata,
        Ok(_) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::SourceUnavailable,
                "source is not a non-empty regular file",
            );
        }
        Err(error) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::SourceUnavailable,
                format!("source metadata is unavailable: {error}"),
            );
        }
    };
    if metadata.len() > MAX_SOURCE_BYTES {
        return RegistrationImagePreparationResult::failure(
            RegistrationImageStatus::SourceTooLarge,
            format!(
                "source is {} bytes; the limit is {MAX_SOURCE_BYTES}",
                metadata.len()
            ),
        );
    }

    let decode_started = Instant::now();
    let source_file = match File::open(&source_path) {
        Ok(file) => file,
        Err(error) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::SourceUnavailable,
                format!("source cannot be opened: {error}"),
            );
        }
    };
    let reader = match ImageReader::new(BufReader::new(source_file)).with_guessed_format() {
        Ok(reader) => reader,
        Err(error) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::DecodeFailed,
                format!("image format cannot be detected: {error}"),
            );
        }
    };
    if !matches!(reader.format(), Some(ImageFormat::Jpeg | ImageFormat::Png)) {
        return RegistrationImagePreparationResult::failure(
            RegistrationImageStatus::UnsupportedFormat,
            "only JPEG and PNG registration images are accepted",
        );
    }

    let mut decoder = match reader.into_decoder() {
        Ok(decoder) => decoder,
        Err(error) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::DecodeFailed,
                format!("image header cannot be decoded: {error}"),
            );
        }
    };
    let source_dimensions = decoder.dimensions();
    if let Err(message) = validate_source_dimensions(source_dimensions.0, source_dimensions.1) {
        return RegistrationImagePreparationResult::failure(
            RegistrationImageStatus::DecodeLimitExceeded,
            message,
        );
    }
    let mut limits = Limits::default();
    limits.max_image_width = Some(MAX_SOURCE_DIMENSION);
    limits.max_image_height = Some(MAX_SOURCE_DIMENSION);
    limits.max_alloc = Some(MAX_DECODE_ALLOCATION_BYTES);
    if let Err(error) = decoder.set_limits(limits) {
        return RegistrationImagePreparationResult::failure(
            RegistrationImageStatus::DecodeLimitExceeded,
            format!("decoder cannot honor the configured resource limits: {error}"),
        );
    }
    let orientation = match decoder.orientation() {
        Ok(orientation) => orientation,
        Err(error) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::DecodeFailed,
                format!("image orientation cannot be read: {error}"),
            );
        }
    };
    let mut image = match DynamicImage::from_decoder(decoder) {
        Ok(image) => image,
        Err(error) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::DecodeFailed,
                format!("image pixels cannot be decoded: {error}"),
            );
        }
    };
    let orientation_applied = orientation != Orientation::NoTransforms;
    image.apply_orientation(orientation);
    let decode_micros = elapsed_micros(decode_started);

    let transform_started = Instant::now();
    let mut prepared = transform_image(image, target_aspect_ratio, target_width);
    let transform_micros = elapsed_micros(transform_started);

    let encode_started = Instant::now();
    let mut encoded = match encode_jpeg(&prepared, INITIAL_JPEG_QUALITY) {
        Ok(encoded) if !encoded.is_empty() => encoded,
        Ok(_) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::EncodeFailed,
                "JPEG encoder returned an empty output",
            );
        }
        Err(error) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::EncodeFailed,
                format!("JPEG encoding failed: {error}"),
            );
        }
    };

    let mut used_size_retry = false;
    if encoded.len() > JPEG_RETRY_THRESHOLD_BYTES && prepared.width() > JPEG_RETRY_WIDTH {
        prepared = resize_to_width(&prepared, JPEG_RETRY_WIDTH);
        encoded = match encode_jpeg(&prepared, RETRY_JPEG_QUALITY) {
            Ok(encoded) if !encoded.is_empty() => encoded,
            Ok(_) => {
                return RegistrationImagePreparationResult::failure(
                    RegistrationImageStatus::EncodeFailed,
                    "retry JPEG encoder returned an empty output",
                );
            }
            Err(error) => {
                return RegistrationImagePreparationResult::failure(
                    RegistrationImageStatus::EncodeFailed,
                    format!("retry JPEG encoding failed: {error}"),
                );
            }
        };
        used_size_retry = true;
    }
    let encode_micros = elapsed_micros(encode_started);

    let output_bytes = match u64::try_from(encoded.len()) {
        Ok(length) => length,
        Err(_) => {
            return RegistrationImagePreparationResult::failure(
                RegistrationImageStatus::OutputTooLarge,
                "encoded image length cannot be represented",
            );
        }
    };
    if output_bytes > MAX_OUTPUT_BYTES {
        return RegistrationImagePreparationResult::failure(
            RegistrationImageStatus::OutputTooLarge,
            format!("output is {output_bytes} bytes; the limit is {MAX_OUTPUT_BYTES}"),
        );
    }

    if let Err(error) = write_output(&output_path, &encoded) {
        return RegistrationImagePreparationResult::failure(
            RegistrationImageStatus::WriteFailed,
            format!("prepared image cannot be written: {error}"),
        );
    }

    RegistrationImagePreparationResult::success(
        &output_path,
        source_dimensions,
        prepared.dimensions(),
        output_bytes,
        orientation_applied,
        used_size_retry,
        ImagePreparationTimings {
            decode_micros,
            transform_micros,
            encode_micros,
            total_micros: elapsed_micros(total_started),
        },
    )
}

fn validate_request(
    source_path: &Path,
    output_path: &Path,
    target_aspect_ratio: f64,
    target_width: u32,
) -> Result<(), String> {
    if source_path.as_os_str().is_empty() || output_path.as_os_str().is_empty() {
        return Err("source and output paths are required".to_owned());
    }
    if source_path == output_path {
        return Err("output path must not replace the picked source".to_owned());
    }
    if !target_aspect_ratio.is_finite()
        || !(MIN_TARGET_ASPECT_RATIO..=MAX_TARGET_ASPECT_RATIO).contains(&target_aspect_ratio)
    {
        return Err(format!(
            "target aspect ratio must be within \
             [{MIN_TARGET_ASPECT_RATIO}, {MAX_TARGET_ASPECT_RATIO}]"
        ));
    }
    if target_width == 0 || target_width > MAX_TARGET_WIDTH {
        return Err(format!(
            "target width must be within [1, {MAX_TARGET_WIDTH}]"
        ));
    }
    let extension = output_path
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase);
    if !matches!(extension.as_deref(), Some("jpg" | "jpeg")) {
        return Err("output path must use a .jpg or .jpeg extension".to_owned());
    }
    if output_path.parent().is_none_or(|parent| !parent.is_dir()) {
        return Err("output parent directory does not exist".to_owned());
    }
    Ok(())
}

fn validate_source_dimensions(width: u32, height: u32) -> Result<(), String> {
    if width == 0 || height == 0 {
        return Err("source dimensions must be non-zero".to_owned());
    }
    if width > MAX_SOURCE_DIMENSION || height > MAX_SOURCE_DIMENSION {
        return Err(format!(
            "source dimensions {width}x{height} exceed the \
             {MAX_SOURCE_DIMENSION}-pixel edge limit"
        ));
    }
    let pixels = u64::from(width)
        .checked_mul(u64::from(height))
        .ok_or_else(|| "source pixel count overflowed".to_owned())?;
    if pixels > MAX_DECODE_PIXELS {
        return Err(format!(
            "source contains {pixels} pixels; the limit is {MAX_DECODE_PIXELS}"
        ));
    }
    Ok(())
}

fn transform_image(
    image: DynamicImage,
    target_aspect_ratio: f64,
    target_width: u32,
) -> DynamicImage {
    let current_aspect_ratio = f64::from(image.width()) / f64::from(image.height());
    let cropped = if (current_aspect_ratio - target_aspect_ratio).abs() <= ASPECT_RATIO_TOLERANCE {
        image
    } else if current_aspect_ratio > target_aspect_ratio {
        let crop_width = rounded_clamped_dimension(
            f64::from(image.height()) * target_aspect_ratio,
            image.width(),
        );
        let x = (image.width() - crop_width) / 2;
        image.crop_imm(x, 0, crop_width, image.height())
    } else {
        let crop_height = rounded_clamped_dimension(
            f64::from(image.width()) / target_aspect_ratio,
            image.height(),
        );
        let y = (image.height() - crop_height) / 2;
        image.crop_imm(0, y, image.width(), crop_height)
    };

    if cropped.width() > target_width {
        resize_to_width(&cropped, target_width)
    } else {
        cropped
    }
}

fn resize_to_width(image: &DynamicImage, target_width: u32) -> DynamicImage {
    let target_height = rounded_clamped_dimension(
        f64::from(image.height()) * f64::from(target_width) / f64::from(image.width()),
        u32::MAX,
    );
    // Dart image 4.8.0 copyResize defaults to nearest-neighbour interpolation.
    image.resize_exact(target_width, target_height, FilterType::Nearest)
}

fn rounded_clamped_dimension(value: f64, maximum: u32) -> u32 {
    if !value.is_finite() || value <= 1.0 {
        return 1;
    }
    if value >= f64::from(maximum) {
        return maximum;
    }
    value.round() as u32
}

fn encode_jpeg(image: &DynamicImage, quality: u8) -> image::ImageResult<Vec<u8>> {
    let mut encoded = Vec::new();
    image.write_with_encoder(JpegEncoder::new_with_quality(&mut encoded, quality))?;
    Ok(encoded)
}

fn write_output(output_path: &Path, encoded: &[u8]) -> std::io::Result<()> {
    let output_id = NEXT_OUTPUT_ID.fetch_add(1, Ordering::Relaxed);
    let file_name = output_path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("prepared.jpg");
    let temporary_path = output_path.with_file_name(format!(
        ".{file_name}.{}-{output_id}.tmp",
        std::process::id()
    ));
    let mut output = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary_path)?;
    if let Err(error) = output.write_all(encoded).and_then(|_| output.sync_all()) {
        drop(output);
        let _ = fs::remove_file(&temporary_path);
        return Err(error);
    }
    drop(output);

    #[cfg(windows)]
    if output_path.exists() {
        fs::remove_file(output_path)?;
    }

    if let Err(error) = fs::rename(&temporary_path, output_path) {
        let _ = fs::remove_file(&temporary_path);
        return Err(error);
    }
    Ok(())
}

fn elapsed_micros(started: Instant) -> u64 {
    u64::try_from(started.elapsed().as_micros()).unwrap_or(u64::MAX)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn landscape_square_matches_existing_no_upscale_behavior() {
        let image = DynamicImage::new_rgb8(1_200, 600);
        let prepared = transform_image(image, 1.0, 720);

        assert_eq!(prepared.dimensions(), (600, 600));
    }

    #[test]
    fn portrait_document_matches_existing_center_crop_and_resize() {
        let image = DynamicImage::new_rgb8(1_000, 1_800);
        let prepared = transform_image(image, 1.0 / 1.414, 700);

        assert_eq!(prepared.dimensions(), (700, 990));
    }

    #[test]
    fn source_pixel_bound_is_checked_without_allocating_pixels() {
        let result = validate_source_dimensions(4_000, 4_000);

        assert!(result.is_err());
    }
}
