//! Shrinking oversized cover art before it's saved. A few embedded covers
//! are far bigger than any screen shows them (several megapixels, MBs each);
//! the app never draws a cover larger than about 1000 px.
//!
//! Only those are shrunk. Decoding, resizing and re-encoding a cover costs
//! about half a second on a low-end CPU, so doing it to ordinary ~1300 px
//! covers (which barely get smaller) would make every scan minutes slower
//! for little gain. Whether a cover is oversized is read from its header,
//! which costs almost nothing.

use std::io::Cursor;

use image::codecs::jpeg::JpegEncoder;
use image::{GenericImageView, ImageFormat};

/// Longest side, in pixels, an oversized cover is shrunk to.
pub const COVER_MAX_SIDE: u32 = 1024;

/// A cover is oversized when its longest side is above this…
pub const OVERSIZED_SIDE: u32 = 2000;

/// …or its file is bigger than this (and it's larger than [COVER_MAX_SIDE]).
pub const OVERSIZED_BYTES: usize = 1024 * 1024;

const JPEG_QUALITY: u8 = 90;

/// `bytes` as a cover no larger than `max_side` on its longest side, or
/// `None` to keep the original: when it's already small enough (so it isn't
/// re-compressed for nothing) or can't be decoded (an unusual format the
/// app may still display). Covers with transparency stay PNG; others become
/// JPEG.
pub fn shrink(bytes: &[u8], max_side: u32) -> Option<Vec<u8>> {
    let image = image::load_from_memory(bytes).ok()?;
    let (width, height) = image.dimensions();
    if width.max(height) <= max_side {
        return None;
    }
    // Area averaging: made for large downscales (no jagged edges), and
    // about 3x faster than a CatmullRom resize on a low-end CPU.
    let small = image.thumbnail(max_side, max_side);
    let mut out = Vec::new();
    if small.color().has_alpha() {
        small
            .write_to(&mut Cursor::new(&mut out), ImageFormat::Png)
            .ok()?;
    } else {
        JpegEncoder::new_with_quality(&mut out, JPEG_QUALITY)
            .encode_image(&small.to_rgb8())
            .ok()?;
    }
    Some(out)
}

/// The cover to store: oversized ones (see [is_oversized]) shrunk to
/// [COVER_MAX_SIDE], everything else exactly as it was.
pub fn shrink_or_keep(bytes: Vec<u8>) -> Vec<u8> {
    if !is_oversized(&bytes) {
        return bytes;
    }
    shrink(&bytes, COVER_MAX_SIDE).unwrap_or(bytes)
}

/// Whether a cover is worth the cost of shrinking: wider or taller than
/// [OVERSIZED_SIDE], or a file over [OVERSIZED_BYTES] that's also bigger
/// than [COVER_MAX_SIDE]. Reads only the image header. Unreadable headers
/// count as not oversized.
pub fn is_oversized(bytes: &[u8]) -> bool {
    let Some(side) = longest_side(bytes) else {
        return false;
    };
    side > OVERSIZED_SIDE || (bytes.len() > OVERSIZED_BYTES && side > COVER_MAX_SIDE)
}

fn longest_side(bytes: &[u8]) -> Option<u32> {
    let (width, height) = image::ImageReader::new(Cursor::new(bytes))
        .with_guessed_format()
        .ok()?
        .into_dimensions()
        .ok()?;
    Some(width.max(height))
}

#[cfg(test)]
mod tests {
    use super::*;
    use image::{DynamicImage, Rgb, RgbImage, Rgba, RgbaImage};

    fn png(image: DynamicImage) -> Vec<u8> {
        let mut out = Vec::new();
        image
            .write_to(&mut Cursor::new(&mut out), ImageFormat::Png)
            .unwrap();
        out
    }

    fn photo(width: u32, height: u32) -> Vec<u8> {
        // A gradient, so the encoder has real detail to keep.
        png(DynamicImage::ImageRgb8(RgbImage::from_fn(
            width,
            height,
            |x, y| Rgb([(x % 256) as u8, (y % 256) as u8, 128]),
        )))
    }

    #[test]
    fn a_big_cover_shrinks_to_jpeg_keeping_its_shape() {
        let out = shrink(&photo(1600, 800), COVER_MAX_SIDE).unwrap();
        assert_eq!(image::guess_format(&out).unwrap(), ImageFormat::Jpeg);
        let back = image::load_from_memory(&out).unwrap();
        assert_eq!(back.dimensions(), (1024, 512));
    }

    #[test]
    fn a_tall_cover_is_limited_by_its_height() {
        let out = shrink(&photo(300, 1500), COVER_MAX_SIDE).unwrap();
        let back = image::load_from_memory(&out).unwrap();
        assert_eq!(back.dimensions().1, 1024);
    }

    #[test]
    fn a_cover_already_small_enough_is_kept_untouched() {
        let original = photo(800, 800);
        assert!(shrink(&original, COVER_MAX_SIDE).is_none());
        assert_eq!(shrink_or_keep(original.clone()), original);
        assert!(shrink(&photo(1024, 600), COVER_MAX_SIDE).is_none());
    }

    /// Pixels that don't compress well, for a big file at a modest size.
    fn noisy(width: u32, height: u32) -> Vec<u8> {
        png(DynamicImage::ImageRgb8(RgbImage::from_fn(
            width,
            height,
            |x, y| {
                let n = x.wrapping_mul(2_654_435_761) ^ y.wrapping_mul(40_503);
                Rgb([n as u8, (n >> 8) as u8, (n >> 16) as u8])
            },
        )))
    }

    #[test]
    fn a_typical_cover_is_left_alone() {
        // About the size of most covers in a real library: over 1024 px but
        // neither huge nor a big file — not worth half a second to shrink.
        let typical = photo(1300, 1300);
        assert!(typical.len() < OVERSIZED_BYTES);
        assert!(!is_oversized(&typical));
        assert_eq!(shrink_or_keep(typical.clone()), typical);
    }

    #[test]
    fn a_huge_cover_is_shrunk() {
        let huge = photo(2400, 1200);
        assert!(is_oversized(&huge));
        let out = shrink_or_keep(huge);
        let back = image::load_from_memory(&out).unwrap();
        assert_eq!(back.dimensions(), (1024, 512));
    }

    #[test]
    fn a_heavy_file_over_1024_px_is_shrunk() {
        let heavy = noisy(1300, 1300);
        assert!(heavy.len() > OVERSIZED_BYTES, "{}", heavy.len());
        assert!(is_oversized(&heavy));
        assert!(shrink_or_keep(heavy.clone()).len() < heavy.len());
    }

    #[test]
    fn a_heavy_file_at_or_under_1024_px_is_left_alone() {
        let heavy_small = noisy(1000, 1000);
        assert!(!is_oversized(&heavy_small), "never enlarged or re-encoded");
    }

    #[test]
    fn transparency_stays_png() {
        let clear = png(DynamicImage::ImageRgba8(RgbaImage::from_pixel(
            1200,
            1200,
            Rgba([255, 0, 0, 100]),
        )));
        let out = shrink(&clear, COVER_MAX_SIDE).unwrap();
        assert_eq!(image::guess_format(&out).unwrap(), ImageFormat::Png);
        let back = image::load_from_memory(&out).unwrap();
        assert!(back.color().has_alpha());
        assert_eq!(back.dimensions(), (1024, 1024));
    }

    #[test]
    fn something_undecodable_is_kept_as_is() {
        let junk = b"not an image at all".to_vec();
        assert!(shrink(&junk, COVER_MAX_SIDE).is_none());
        assert!(!is_oversized(&junk));
        assert_eq!(shrink_or_keep(junk.clone()), junk);
    }

    #[test]
    fn a_big_jpeg_cover_ends_up_smaller() {
        // Real covers are nearly always JPEG photos; start from one.
        let mut original = Vec::new();
        JpegEncoder::new_with_quality(&mut original, JPEG_QUALITY)
            .encode_image(
                &image::load_from_memory(&photo(1800, 1800))
                    .unwrap()
                    .to_rgb8(),
            )
            .unwrap();
        let out = shrink(&original, COVER_MAX_SIDE).unwrap();
        // How much smaller depends on the picture (measured on the real
        // library by the scan benchmark); here: fewer pixels, fewer bytes.
        assert!(
            out.len() < original.len(),
            "{} vs {}",
            out.len(),
            original.len()
        );
    }
}
