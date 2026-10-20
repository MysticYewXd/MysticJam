//! Files next to a song that the scanner also uses: a `.lrc` with the same
//! name (synced lyrics) and a folder cover image. Same rules as the Dart
//! scanner had (library_scanner.dart).

use std::fs;
use std::path::Path;

const COVER_NAMES: [&str; 5] = ["cover", "folder", "album", "front", "albumart"];
const COVER_EXTENSIONS: [&str; 3] = ["jpg", "jpeg", "png"];

/// Content of `<song name>.lrc` (or `.LRC`) next to `audio`. `None` when
/// there is none, or it's blank. Not valid UTF-8 counts as unreadable, and
/// the other spelling is tried, as the Dart version did.
pub fn lrc_for(audio: &Path) -> Option<String> {
    for ext in ["lrc", "LRC"] {
        let candidate = audio.with_extension(ext);
        if !candidate.is_file() {
            continue;
        }
        if let Ok(bytes) = fs::read(&candidate) {
            if let Ok(text) = String::from_utf8(bytes) {
                return (!text.trim().is_empty()).then_some(text);
            }
        }
    }
    None
}

/// Bytes of the first folder cover (`cover.jpg`, `folder.png`, ...) in the
/// song's directory, by file name order; empty files are skipped.
pub fn folder_cover_for(audio: &Path) -> Option<Vec<u8>> {
    let dir = audio.parent()?;
    let mut candidates: Vec<_> = fs::read_dir(dir)
        .ok()?
        .filter_map(Result::ok)
        .map(|e| e.path())
        .filter(|p| p.is_file() && is_cover_name(p))
        .collect();
    candidates.sort();
    candidates
        .iter()
        .filter_map(|p| fs::read(p).ok())
        .find(|bytes| !bytes.is_empty())
}

fn is_cover_name(path: &Path) -> bool {
    let lower = |s: Option<&std::ffi::OsStr>| s.and_then(|s| s.to_str()).map(str::to_lowercase);
    match (lower(path.file_stem()), lower(path.extension())) {
        (Some(stem), Some(ext)) => {
            COVER_NAMES.contains(&stem.as_str()) && COVER_EXTENSIONS.contains(&ext.as_str())
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> std::path::PathBuf {
        let dir =
            std::env::temp_dir().join(format!("mysticjam_sidecar_{name}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn finds_lrc_in_either_case() {
        let dir = scratch("lrc");
        let song = dir.join("song.flac");
        assert_eq!(lrc_for(&song), None);
        fs::write(dir.join("song.LRC"), "[00:01.00]Hi").unwrap();
        assert_eq!(lrc_for(&song).as_deref(), Some("[00:01.00]Hi"));
        fs::write(dir.join("song.lrc"), "   ").unwrap();
        assert_eq!(lrc_for(&song), None, "blank .lrc wins and means none");
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn invalid_utf8_lrc_falls_through_to_the_other_spelling() {
        let dir = scratch("lrc_utf8");
        let song = dir.join("song.mp3");
        fs::write(dir.join("song.lrc"), [0xff, 0xfe, 0x00]).unwrap();
        fs::write(dir.join("song.LRC"), "[00:01.00]Ok").unwrap();
        let found = lrc_for(&song);
        // On case-insensitive filesystems both names are the same file.
        assert!(found.is_none() || found.as_deref() == Some("[00:01.00]Ok"));
        fs::remove_dir_all(dir).unwrap();
    }

    #[test]
    fn folder_cover_by_name_and_extension() {
        let dir = scratch("cover");
        let song = dir.join("a.flac");
        fs::write(dir.join("notes.jpg"), [1]).unwrap();
        fs::write(dir.join("cover.txt"), [1]).unwrap();
        assert_eq!(folder_cover_for(&song), None);
        fs::write(dir.join("Folder.PNG"), [7, 7]).unwrap();
        fs::write(dir.join("cover.jpg"), []).unwrap();
        assert_eq!(
            folder_cover_for(&song),
            Some(vec![7, 7]),
            "empty cover.jpg skipped"
        );
        fs::remove_dir_all(dir).unwrap();
    }
}
