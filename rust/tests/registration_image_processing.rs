use image::codecs::jpeg::JpegEncoder;
use image::metadata::Orientation;
use image::{ImageEncoder, Rgb, RgbImage};
use std::error::Error;
use std::fs::{self, File};
use std::io;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use voltrike_core::api::registration_image::{
    prepare_registration_image_file, RegistrationImageStatus,
};

static NEXT_DIRECTORY_ID: AtomicU64 = AtomicU64::new(0);

fn temporary_directory() -> io::Result<PathBuf> {
    let id = NEXT_DIRECTORY_ID.fetch_add(1, Ordering::Relaxed);
    let path = std::env::temp_dir().join(format!(
        "voltrike-registration-image-{}-{id}",
        std::process::id()
    ));
    fs::create_dir_all(&path)?;
    Ok(path)
}

fn write_jpeg(
    path: &Path,
    image: &RgbImage,
    orientation: Option<Orientation>,
) -> Result<(), Box<dyn Error>> {
    let file = File::create(path)?;
    let mut encoder = JpegEncoder::new_with_quality(file, 90);
    if let Some(orientation) = orientation {
        encoder.set_exif_metadata(minimal_orientation_exif(orientation))?;
    }
    encoder.encode_image(image)?;
    Ok(())
}

fn minimal_orientation_exif(orientation: Orientation) -> Vec<u8> {
    vec![
        b'I',
        b'I',
        0x2A,
        0x00,
        0x08,
        0x00,
        0x00,
        0x00,
        0x01,
        0x00,
        0x12,
        0x01,
        0x03,
        0x00,
        0x01,
        0x00,
        0x00,
        0x00,
        orientation.to_exif(),
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
        0x00,
    ]
}

#[test]
fn file_pipeline_preserves_existing_square_crop_semantics() -> Result<(), Box<dyn Error>> {
    let directory = temporary_directory()?;
    let source = directory.join("landscape.jpg");
    let output = directory.join("prepared.jpg");
    let image = RgbImage::from_pixel(1_200, 600, Rgb([40, 120, 200]));
    write_jpeg(&source, &image, None)?;

    let result = prepare_registration_image_file(
        source.to_string_lossy().into_owned(),
        output.to_string_lossy().into_owned(),
        1.0,
        720,
    );

    assert_eq!(result.status, RegistrationImageStatus::Ok);
    assert_eq!((result.output_width, result.output_height), (600, 600));
    assert!(output.is_file());
    fs::remove_dir_all(directory)?;
    Ok(())
}

#[test]
fn exif_orientation_is_applied_before_crop_and_resize() -> Result<(), Box<dyn Error>> {
    let directory = temporary_directory()?;
    let source = directory.join("rotated.jpg");
    let output = directory.join("prepared.jpg");
    let image = RgbImage::from_pixel(400, 200, Rgb([200, 80, 40]));
    write_jpeg(&source, &image, Some(Orientation::Rotate90))?;

    let result = prepare_registration_image_file(
        source.to_string_lossy().into_owned(),
        output.to_string_lossy().into_owned(),
        0.5,
        400,
    );

    assert_eq!(result.status, RegistrationImageStatus::Ok);
    assert!(result.orientation_applied);
    assert_eq!((result.output_width, result.output_height), (200, 400));
    fs::remove_dir_all(directory)?;
    Ok(())
}

#[test]
fn sparse_oversized_source_is_rejected_before_decode() -> Result<(), Box<dyn Error>> {
    let directory = temporary_directory()?;
    let source = directory.join("oversized.jpg");
    let output = directory.join("prepared.jpg");
    File::create(&source)?.set_len(32 * 1024 * 1024 + 1)?;

    let result = prepare_registration_image_file(
        source.to_string_lossy().into_owned(),
        output.to_string_lossy().into_owned(),
        1.0,
        1_080,
    );

    assert_eq!(result.status, RegistrationImageStatus::SourceTooLarge);
    assert!(!output.exists());
    fs::remove_dir_all(directory)?;
    Ok(())
}
