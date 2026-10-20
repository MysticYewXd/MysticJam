//! Reading one song file: tags, cover art and lyrics in every format lofty
//! supports (MP3, AAC, WAV, AIFF, FLAC, OGG Vorbis, Opus, Speex, M4A/MP4,
//! APE, WavPack, Musepack). WMA isn't one of them; Dart reads those.

use std::fs::File;
use std::path::Path;

use lofty::config::ParseOptions;
use lofty::file::{AudioFile, FileType, TaggedFileExt};
use lofty::id3::v2::{Frame, Id3v2Tag, SynchronizedTextFrame, TimestampFormat};
use lofty::prelude::ItemKey;
use lofty::probe::Probe;
use lofty::tag::Tag;
use rayon::prelude::*;

use crate::{lyrics, sidecar, tags};

/// Everything the scanner stores for one song.
pub struct TrackFile {
    pub title: Option<String>,
    pub artist: Option<String>,
    pub album: Option<String>,
    pub album_artist: Option<String>,
    pub genre: Option<String>,
    pub year: Option<i32>,
    pub track_number: Option<i32>,
    pub duration_ms: Option<u32>,
    /// Embedded lyrics that aren't timestamped.
    pub lyrics: Option<String>,
    /// LRC text: the `.lrc` file next to the song if there is one, else
    /// timestamped lyrics embedded in the file (a lyrics tag holding LRC
    /// text, or ID3's SYLT frame).
    pub synced_lyrics: Option<String>,
    /// Embedded cover, else a `cover.jpg`/`folder.png`-style image next to
    /// the song.
    pub artwork: Option<Vec<u8>>,
}

/// Reads `path`. Errors (unsupported or corrupt file, unreadable path) are
/// returned as a message; the Dart side then falls back to its own readers.
pub fn read_track_file(path: String) -> Result<TrackFile, String> {
    read(Path::new(&path))
}

/// One file's result from [read_track_files]: `file`, or the `error` that
/// stopped it being read.
pub struct TrackFileResult {
    pub path: String,
    pub file: Option<TrackFile>,
    pub error: Option<String>,
}

/// Reads many files at once, spread across all CPU cores. Results come back
/// in the same order as `paths`, one per path; a failure affects only its
/// own file.
pub fn read_track_files(paths: Vec<String>) -> Vec<TrackFileResult> {
    paths
        .into_par_iter()
        .map(|path| match read(Path::new(&path)) {
            Ok(file) => TrackFileResult {
                path,
                file: Some(file),
                error: None,
            },
            Err(error) => TrackFileResult {
                path,
                file: None,
                error: Some(error),
            },
        })
        .collect()
}

/// Whether lyrics text is LRC-style synced lyrics, for lyrics the Dart
/// readers find (WMA).
#[flutter_rust_bridge::frb(sync)]
pub fn is_synced_lyrics(text: String) -> bool {
    lyrics::is_synced(&text)
}

/// Whether lyrics text has no lyric lines at all (only markers like
/// `[instrumental:true]`), for lyrics the Dart readers find.
#[flutter_rust_bridge::frb(sync)]
pub fn has_no_lyric_lines(text: String) -> bool {
    lyrics::has_no_lyric_lines(&text)
}

/// Plain lyrics without LRC header lines, for lyrics the Dart readers find.
#[flutter_rust_bridge::frb(sync)]
pub fn plain_lyrics_text(text: String) -> String {
    lyrics::without_header_tags(&text)
}

fn read(path: &Path) -> Result<TrackFile, String> {
    let options = ParseOptions::new()
        .read_properties(true)
        .read_cover_art(true);
    let file = Probe::open(path)
        .map_err(|e| e.to_string())?
        .options(options)
        .guess_file_type()
        .map_err(|e| e.to_string())?
        .read()
        .map_err(|e| e.to_string())?;

    // Primary tag first; other tags (e.g. ID3v1 or APE next to ID3v2) fill
    // in fields it lacks.
    let primary = file.primary_tag();
    let ordered: Vec<&Tag> = primary
        .into_iter()
        .chain(
            file.tags()
                .iter()
                .filter(|t| !primary.is_some_and(|p| std::ptr::eq(p, *t))),
        )
        .collect();
    let text = |key: ItemKey| {
        ordered
            .iter()
            .find_map(|t| tags::non_empty(t.get_string(key)))
    };
    let raw = |key: ItemKey| ordered.iter().find_map(|t| t.get_string(key));
    // Artists can be stored as several values (ARTIST=A, ARTIST=B); all of
    // them, from the first tag that has any, joined as "A, B".
    let artists = |key: ItemKey| {
        ordered
            .iter()
            .find_map(|t| tags::joined(t.get_strings(key)))
    };

    let duration = file.properties().duration().as_millis();
    let embedded_lyrics = text(ItemKey::Lyrics)
        .or_else(|| text(ItemKey::UnsyncLyrics))
        .filter(|l| !lyrics::has_no_lyric_lines(l));
    let (embedded_synced, plain) = match embedded_lyrics {
        Some(l) if lyrics::is_synced(&l) => (Some(l), None),
        Some(l) => (None, Some(lyrics::without_header_tags(&l))),
        None => (None, None),
    };
    let synced = sidecar::lrc_for(path)
        .or(embedded_synced)
        .or_else(|| sylt_lyrics(path, file.file_type()));
    let artwork = ordered
        .iter()
        .find_map(|t| t.pictures().first())
        .map(|p| p.data().to_vec())
        .or_else(|| sidecar::folder_cover_for(path));

    Ok(TrackFile {
        title: text(ItemKey::TrackTitle),
        artist: artists(ItemKey::TrackArtist),
        album: text(ItemKey::AlbumTitle),
        album_artist: artists(ItemKey::AlbumArtist),
        genre: text(ItemKey::Genre),
        year: tags::leading_year(raw(ItemKey::RecordingDate))
            .or_else(|| tags::leading_year(raw(ItemKey::Year))),
        track_number: tags::leading_track_number(raw(ItemKey::TrackNumber)),
        duration_ms: (duration > 0).then(|| u32::try_from(duration).unwrap_or(u32::MAX)),
        lyrics: plain,
        synced_lyrics: synced,
        artwork,
    })
}

/// Synced lyrics from an ID3v2 SYLT frame, as LRC text. Only millisecond
/// timestamps can be converted (MPEG-frame ones need the frame rate).
/// lofty's generic tag doesn't carry SYLT, so the ID3v2 tag is read again
/// directly — only for formats that can hold one.
fn sylt_lyrics(path: &Path, file_type: FileType) -> Option<String> {
    let mut file = File::open(path).ok()?;
    let options = ParseOptions::new()
        .read_properties(false)
        .read_cover_art(false);
    let id3: Id3v2Tag = match file_type {
        FileType::Mpeg => lofty::mpeg::MpegFile::read_from(&mut file, options)
            .ok()?
            .id3v2()?
            .clone(),
        FileType::Aac => lofty::aac::AacFile::read_from(&mut file, options)
            .ok()?
            .id3v2()?
            .clone(),
        FileType::Wav => lofty::iff::wav::WavFile::read_from(&mut file, options)
            .ok()?
            .id3v2()?
            .clone(),
        FileType::Aiff => lofty::iff::aiff::AiffFile::read_from(&mut file, options)
            .ok()?
            .id3v2()?
            .clone(),
        _ => return None,
    };
    id3.into_iter().find_map(|frame| {
        if frame.id().as_str() != "SYLT" {
            return None;
        }
        let Frame::Binary(binary) = &frame else {
            return None;
        };
        let sylt = SynchronizedTextFrame::parse(&binary.data, frame.flags()).ok()?;
        if sylt.timestamp_format != TimestampFormat::MS {
            return None;
        }
        lyrics::lrc_from_timed_entries(&sylt.content)
    })
}

#[cfg(test)]
#[path = "track_tests.rs"]
mod tests;
