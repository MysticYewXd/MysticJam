//! Walking a music folder for the scanner. Paths are streamed to Dart in
//! batches as they're found, so a huge library starts indexing straight
//! away, and the walk stops as soon as Dart stops listening (a cancelled
//! scan).

use std::collections::HashSet;
use std::path::Path;

use walkdir::WalkDir;

use crate::frb_generated::StreamSink;

/// Streams every file under `root` whose extension is in `extensions`
/// (compared case-insensitively), in batches of `batch_size`, sorted by name
/// within each folder. Symlinks aren't followed, and folders that can't be
/// read are skipped rather than ending the walk. Paths that aren't valid
/// UTF-8 are skipped too: Dart couldn't open them by name.
pub fn walk_media_files(
    root: String,
    extensions: Vec<String>,
    batch_size: u32,
    sink: StreamSink<Vec<String>>,
) {
    let extensions: HashSet<String> = extensions.iter().map(|e| e.to_lowercase()).collect();
    walk(
        Path::new(&root),
        &extensions,
        batch_size as usize,
        |batch| sink.add(batch).is_ok(),
    );
}

/// Calls `emit` with each batch; stops when it returns false.
fn walk(
    root: &Path,
    extensions: &HashSet<String>,
    batch_size: usize,
    mut emit: impl FnMut(Vec<String>) -> bool,
) {
    let batch_size = batch_size.max(1);
    let mut batch = Vec::with_capacity(batch_size);
    let entries = WalkDir::new(root)
        .follow_links(false)
        .sort_by_file_name()
        .into_iter()
        .filter_map(Result::ok)
        .filter(|e| e.file_type().is_file());
    for entry in entries {
        let path = entry.path();
        let wanted = path
            .extension()
            .and_then(|e| e.to_str())
            .is_some_and(|e| extensions.contains(&e.to_lowercase()));
        let Some(path) = path.to_str().filter(|_| wanted) else {
            continue;
        };
        batch.push(path.to_string());
        if batch.len() >= batch_size && !emit(std::mem::take(&mut batch)) {
            return;
        }
    }
    if !batch.is_empty() {
        emit(batch);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;

    fn tree(test: &str) -> PathBuf {
        let dir =
            std::env::temp_dir().join(format!("mysticjam_walk_{test}_{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        for f in [
            "b.flac",
            "a.MP3",
            "notes.txt",
            "x/c.ogg",
            "x/y/d.opus",
            "x/y/e.jpg",
        ] {
            let p = dir.join(f);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, b"").unwrap();
        }
        dir
    }

    fn exts() -> HashSet<String> {
        ["mp3", "flac", "ogg", "opus"]
            .iter()
            .map(|s| s.to_string())
            .collect()
    }

    fn names(root: &Path, batches: &[Vec<String>]) -> Vec<String> {
        batches
            .iter()
            .flatten()
            .map(|p| {
                Path::new(p)
                    .strip_prefix(root)
                    .unwrap()
                    .to_string_lossy()
                    .into_owned()
            })
            .collect()
    }

    #[test]
    fn finds_media_files_in_every_folder_case_insensitively() {
        let root = tree("all");
        let mut batches = Vec::new();
        walk(&root, &exts(), 100, |b| {
            batches.push(b);
            true
        });
        assert_eq!(batches.len(), 1);
        assert_eq!(
            names(&root, &batches),
            ["a.MP3", "b.flac", "x/c.ogg", "x/y/d.opus"]
        );
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn batches_have_the_requested_size() {
        let root = tree("batches");
        let mut sizes = Vec::new();
        walk(&root, &exts(), 3, |b| {
            sizes.push(b.len());
            true
        });
        assert_eq!(sizes, [3, 1]);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn stops_when_the_listener_goes_away() {
        let root = tree("stop");
        let mut calls = 0;
        walk(&root, &exts(), 1, |_| {
            calls += 1;
            false
        });
        assert_eq!(calls, 1);
        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn a_missing_folder_yields_nothing() {
        let mut called = false;
        walk(Path::new("/nonexistent/mysticjam"), &exts(), 10, |_| {
            called = true;
            true
        });
        assert!(!called);
    }
}
