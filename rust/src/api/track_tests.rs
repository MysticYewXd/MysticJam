//! Reads real files in every format. Fixtures in tests/fixtures/ are tagged
//! by ffmpeg (an independent writer; see make_fixtures.sh). WAV, AAC, APE
//! and the synced-lyrics cases are tagged here with lofty, since ffmpeg
//! can't write lyrics into those.

use std::fs;
use std::path::{Path, PathBuf};

use lofty::config::WriteOptions;
use lofty::id3::v2::{
    BinaryFrame, Frame, FrameId, Id3v2Tag, SyncTextContentType, SynchronizedTextFrame,
    TimestampFormat,
};
use lofty::prelude::ItemKey;
use lofty::tag::{Tag, TagExt, TagType};
use lofty::TextEncoding;

use super::{read_track_file, TrackFile};

const PLAIN: &str = "Plain line one\nPlain line two";
const LRC: &str = "[00:01.00]First\n[00:02.50]Second\n";

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name)
}

/// A fresh scratch folder per test.
fn scratch(test: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("mysticjam_track_{test}_{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).unwrap();
    dir
}

/// Copies a fixture into `dir` (as `name`) so a test can modify it.
fn copy(fixture_name: &str, dir: &Path, name: &str) -> PathBuf {
    let to = dir.join(name);
    fs::copy(fixture(fixture_name), &to).unwrap();
    to
}

fn read(path: &Path) -> TrackFile {
    read_track_file(path.to_string_lossy().into_owned())
        .unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

fn assert_tags(f: &TrackFile, what: &str) {
    assert_eq!(f.title.as_deref(), Some("Fixture Title"), "{what} title");
    assert_eq!(f.artist.as_deref(), Some("Fixture Artist"), "{what} artist");
    assert_eq!(f.album.as_deref(), Some("Fixture Album"), "{what} album");
    assert_eq!(
        f.album_artist.as_deref(),
        Some("Fixture Album Artist"),
        "{what} album artist"
    );
    assert_eq!(f.genre.as_deref(), Some("Fixture Genre"), "{what} genre");
    assert_eq!(f.year, Some(2001), "{what} year");
    assert_eq!(f.track_number, Some(3), "{what} track");
    let ms = f.duration_ms.unwrap_or(0);
    assert!((250..=400).contains(&ms), "{what} duration {ms} ms");
}

#[test]
fn every_ffmpeg_tagged_format_reads_tags_and_plain_lyrics() {
    for (name, has_cover) in [
        ("tagged.mp3", true),
        ("tagged.flac", true),
        ("tagged.m4a", true),
        ("tagged.mp4", false),
        ("tagged.ogg", false),
        ("tagged.opus", false),
    ] {
        let f = read(&fixture(name));
        assert_tags(&f, name);
        assert_eq!(f.lyrics.as_deref(), Some(PLAIN), "{name} lyrics");
        assert_eq!(f.synced_lyrics, None, "{name} synced");
        let png = f
            .artwork
            .as_deref()
            .is_some_and(|a| a.starts_with(b"\x89PNG"));
        assert_eq!(png, has_cover, "{name} cover");
    }
}

/// Tags a copy of an untagged file through ID3v2 (WAV keeps it in an `id3 `
/// chunk, AAC and MP3 at the start).
fn id3_tagged(fixture_name: &str, dir: &Path, name: &str) -> PathBuf {
    let path = copy(fixture_name, dir, name);
    let mut tag = Tag::new(TagType::Id3v2);
    tag.insert_text(ItemKey::TrackTitle, "Fixture Title".into());
    tag.insert_text(ItemKey::UnsyncLyrics, PLAIN.into());
    tag.save_to_path(&path, WriteOptions::default()).unwrap();
    path
}

#[test]
fn wav_and_aac_read_id3_lyrics() {
    let dir = scratch("id3");
    for (fixture_name, name) in [("untagged.wav", "a.wav"), ("untagged.aac", "a.aac")] {
        let f = read(&id3_tagged(fixture_name, &dir, name));
        assert_eq!(f.title.as_deref(), Some("Fixture Title"), "{name}");
        assert_eq!(f.lyrics.as_deref(), Some(PLAIN), "{name}");
    }
    fs::remove_dir_all(dir).unwrap();
}

/// A minimal Monkey's Audio (.ape) file: descriptor and header for 0.1 s of
/// 16-bit mono at 44.1 kHz, no audio frames. ffmpeg can't encode APE.
fn minimal_ape(path: &Path) {
    let mut b = Vec::new();
    b.extend_from_slice(b"MAC ");
    b.extend_from_slice(&3990u16.to_le_bytes()); // version
    b.extend_from_slice(&0u16.to_le_bytes()); // padding
    for v in [52u32, 24, 0, 0, 0, 0, 0] {
        // descriptor, header, seek table, wav header, audio (lo, hi), terminating
        b.extend_from_slice(&v.to_le_bytes());
    }
    b.extend_from_slice(&[0u8; 16]); // MD5
    b.extend_from_slice(&2000u16.to_le_bytes()); // compression level
    b.extend_from_slice(&0u16.to_le_bytes()); // format flags
    b.extend_from_slice(&73_728u32.to_le_bytes()); // blocks per frame
    b.extend_from_slice(&4_410u32.to_le_bytes()); // final frame blocks
    b.extend_from_slice(&1u32.to_le_bytes()); // total frames
    b.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
    b.extend_from_slice(&1u16.to_le_bytes()); // channels
    b.extend_from_slice(&44_100u32.to_le_bytes()); // sample rate
    fs::write(path, b).unwrap();
}

#[test]
fn ape_reads_lyrics() {
    let dir = scratch("ape");
    let path = dir.join("a.ape");
    minimal_ape(&path);
    let mut tag = Tag::new(TagType::Ape);
    tag.insert_text(ItemKey::TrackTitle, "Fixture Title".into());
    tag.insert_text(ItemKey::Lyrics, PLAIN.into());
    tag.insert_text(ItemKey::TrackNumber, "3".into());
    tag.save_to_path(&path, WriteOptions::default()).unwrap();

    let f = read(&path);
    assert_eq!(f.title.as_deref(), Some("Fixture Title"));
    assert_eq!(f.lyrics.as_deref(), Some(PLAIN));
    assert_eq!(f.track_number, Some(3));
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn timestamped_lyrics_in_a_tag_count_as_synced() {
    let dir = scratch("embedded_lrc");
    let path = copy("tagged.flac", &dir, "a.flac");
    let mut tag = Tag::new(TagType::VorbisComments);
    tag.insert_text(ItemKey::TrackTitle, "Fixture Title".into());
    tag.insert_text(ItemKey::Lyrics, LRC.into());
    tag.save_to_path(&path, WriteOptions::default()).unwrap();

    let f = read(&path);
    // Tag values are trimmed (as the Dart readers did), so the final
    // newline goes; the lyrics themselves are unchanged.
    assert_eq!(f.synced_lyrics.as_deref(), Some(LRC.trim_end()));
    assert_eq!(f.lyrics, None, "the same text isn't also stored as plain");
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn mp3_sylt_frame_becomes_lrc() {
    let dir = scratch("sylt");
    let path = copy("untagged.mp3", &dir, "a.mp3");
    let sylt = SynchronizedTextFrame::new(
        TextEncoding::UTF8,
        *b"eng",
        TimestampFormat::MS,
        SyncTextContentType::Lyrics,
        None,
        vec![(1_000, "First".into()), (2_500, "\nSecond".into())],
    );
    let bytes = sylt.as_bytes(WriteOptions::default()).unwrap();
    let mut id3 = Id3v2Tag::new();
    id3.insert(Frame::Binary(BinaryFrame::new(
        FrameId::Valid("SYLT".into()),
        bytes,
    )));
    id3.save_to_path(&path, WriteOptions::default()).unwrap();

    let f = read(&path);
    assert_eq!(f.synced_lyrics.as_deref(), Some(LRC));
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn lrc_file_wins_over_embedded_synced_lyrics() {
    let dir = scratch("priority");
    let path = copy("tagged.opus", &dir, "song.opus");
    let mut tag = Tag::new(TagType::VorbisComments);
    tag.insert_text(ItemKey::Lyrics, LRC.into());
    tag.save_to_path(&path, WriteOptions::default()).unwrap();
    fs::write(dir.join("song.lrc"), "[00:09.00]From the file\n").unwrap();

    let f = read(&path);
    assert_eq!(
        f.synced_lyrics.as_deref(),
        Some("[00:09.00]From the file\n")
    );
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn lrc_file_and_plain_embedded_lyrics_are_both_kept() {
    let dir = scratch("both");
    let path = copy("tagged.ogg", &dir, "song.ogg");
    fs::write(dir.join("song.lrc"), LRC).unwrap();

    let f = read(&path);
    assert_eq!(f.synced_lyrics.as_deref(), Some(LRC));
    assert_eq!(f.lyrics.as_deref(), Some(PLAIN));
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn folder_cover_only_when_nothing_is_embedded() {
    let dir = scratch("cover");
    let ogg = copy("tagged.ogg", &dir, "a.ogg");
    let flac = copy("tagged.flac", &dir, "b.flac");
    fs::write(dir.join("cover.jpg"), b"jpeg bytes").unwrap();

    assert_eq!(read(&ogg).artwork.as_deref(), Some(&b"jpeg bytes"[..]));
    assert!(
        read(&flac).artwork.unwrap().starts_with(b"\x89PNG"),
        "embedded wins"
    );
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn unreadable_files_are_errors() {
    let dir = scratch("bad");
    let garbage = dir.join("broken.mp3");
    fs::write(&garbage, b"definitely not audio").unwrap();
    assert!(read_track_file(garbage.to_string_lossy().into_owned()).is_err());
    let missing = dir.join("missing.flac");
    assert!(read_track_file(missing.to_string_lossy().into_owned()).is_err());
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn instrumental_marker_is_not_lyrics() {
    let dir = scratch("instrumental");
    let path = copy("tagged.flac", &dir, "a.flac");
    let mut tag = Tag::new(TagType::VorbisComments);
    tag.insert_text(ItemKey::Lyrics, "[instrumental:true]".into());
    tag.save_to_path(&path, WriteOptions::default()).unwrap();

    let f = read(&path);
    assert_eq!(f.lyrics, None);
    assert_eq!(f.synced_lyrics, None);
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn plain_lyrics_lose_their_lrc_header_lines() {
    let dir = scratch("headers");
    let path = copy("tagged.flac", &dir, "a.flac");
    let mut tag = Tag::new(TagType::VorbisComments);
    tag.insert_text(
        ItemKey::Lyrics,
        "[ti:Song]\n[by:Tool (source: LRCLIB)]\n\nWords here\nMore words".into(),
    );
    tag.save_to_path(&path, WriteOptions::default()).unwrap();

    let f = read(&path);
    assert_eq!(f.lyrics.as_deref(), Some("Words here\nMore words"));
    assert_eq!(f.synced_lyrics, None);
    fs::remove_dir_all(dir).unwrap();
}

#[test]
fn several_artist_values_are_joined() {
    // Like the user's BULLY tracks: ARTIST and ALBUMARTIST stored twice.
    let dir = scratch("multi_artist");
    let path = copy("tagged.flac", &dir, "a.flac");
    let mut tag = Tag::new(TagType::VorbisComments);
    for (key, value) in [
        (ItemKey::TrackArtist, "Kanye West"),
        (ItemKey::TrackArtist, "Ye"),
        (ItemKey::TrackArtist, "Travis Scott"),
        (ItemKey::AlbumArtist, "Kanye West"),
        (ItemKey::AlbumArtist, "Ye"),
    ] {
        tag.push(lofty::tag::TagItem::new(
            key,
            lofty::tag::ItemValue::Text(value.into()),
        ));
    }
    tag.save_to_path(&path, WriteOptions::default()).unwrap();

    let f = read(&path);
    assert_eq!(f.artist.as_deref(), Some("Kanye West, Ye, Travis Scott"));
    assert_eq!(f.album_artist.as_deref(), Some("Kanye West, Ye"));
    fs::remove_dir_all(dir).unwrap();
}
