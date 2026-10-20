//! Telling synced (timestamped LRC) lyrics apart from plain lyrics, and
//! turning ID3's binary synced-lyrics frame (SYLT) into LRC text.
//!
//! The timestamp rule matches the Dart LRC parser (lrc_parser.dart): a line
//! starting with `[m:ss]`, `[mm:ss.xx]` or `[mmm:ss.xxx]` (`.` or `:` before
//! the fraction), possibly several in a row, followed by the lyric text.

/// Length of the timestamp tag at the start of `s` (e.g. 10 for
/// `[01:23.45]`), or `None` if `s` doesn't start with one.
fn timestamp_len(s: &str) -> Option<usize> {
    let b = s.as_bytes();
    let digits = |from: usize, max: usize| {
        b[from..]
            .iter()
            .take(max)
            .take_while(|c| c.is_ascii_digit())
            .count()
    };
    if b.first() != Some(&b'[') {
        return None;
    }
    let mut i = 1;
    let minutes = digits(i, 3);
    if minutes == 0 {
        return None;
    }
    i += minutes;
    if b.get(i) != Some(&b':') {
        return None;
    }
    i += 1;
    if digits(i, 2) != 2 {
        return None;
    }
    i += 2;
    if matches!(b.get(i), Some(b'.') | Some(b':')) {
        let fraction = digits(i + 1, 3);
        if fraction > 0 {
            i += 1 + fraction;
        }
    }
    if b.get(i) != Some(&b']') {
        return None;
    }
    Some(i + 1)
}

/// What a line of lyrics text is, for classification.
enum Line {
    /// Timestamped and with lyric text — what the LRC parser shows.
    Timed,
    /// An LRC header tag like `[ar:Artist]` or `[offset:+100]`, or a
    /// timestamp with no text: neither lyrics nor evidence against LRC.
    Neutral,
    /// Ordinary text.
    Plain,
}

/// `[tag:value]` LRC header lines, where the tag is letters
/// (`[ar:Artist]`, `[by:Tool]`, `[instrumental:true]`).
fn is_header_tag(line: &str) -> bool {
    let line = line.trim();
    line.strip_prefix('[')
        .and_then(|l| l.strip_suffix(']'))
        .and_then(|inner| inner.split_once(':'))
        .is_some_and(|(tag, _)| !tag.is_empty() && tag.chars().all(|c| c.is_ascii_alphabetic()))
}

/// Plain lyrics without LRC header lines (`[ti:...]`, `[by:...]`), which
/// taggers put above untimed lyrics too; trimmed. Section markers like
/// `[Chorus]` stay.
pub fn without_header_tags(text: &str) -> String {
    text.lines()
        .filter(|l| !is_header_tag(l))
        .collect::<Vec<_>>()
        .join("\n")
        .trim()
        .to_string()
}

fn classify(line: &str) -> Line {
    let line = line.trim();
    if line.is_empty() {
        return Line::Neutral;
    }
    let mut rest = line;
    let mut stamped = false;
    while let Some(n) = timestamp_len(rest) {
        rest = &rest[n..];
        stamped = true;
    }
    if stamped {
        return if rest.trim().is_empty() {
            Line::Neutral
        } else {
            Line::Timed
        };
    }
    if is_header_tag(line) {
        return Line::Neutral;
    }
    Line::Plain
}

fn count(text: &str) -> (usize, usize) {
    let (mut timed, mut plain) = (0usize, 0usize);
    for line in text.lines() {
        match classify(line) {
            Line::Timed => timed += 1,
            Line::Plain => plain += 1,
            Line::Neutral => {}
        }
    }
    (timed, plain)
}

/// True when `text` is LRC-style synced lyrics: at least one timestamped
/// lyric line, and timestamped lines outnumber (or equal) plain ones. Plain
/// lyrics with section markers like `[Chorus]` are not synced.
pub fn is_synced(text: &str) -> bool {
    let (timed, plain) = count(text);
    timed > 0 && timed >= plain
}

/// True when `text` holds no lyric lines at all — only LRC header tags such
/// as `[instrumental:true]` or `[ar:Artist]`, which taggers write in place
/// of lyrics for instrumentals.
pub fn has_no_lyric_lines(text: &str) -> bool {
    count(text) == (0, 0)
}

/// LRC text from SYLT entries (millisecond timestamps, text). Entry text
/// often starts with a newline marking a new line; that is trimmed. `None`
/// when no entry has text.
pub fn lrc_from_timed_entries(entries: &[(u32, String)]) -> Option<String> {
    let mut out = String::new();
    for (ms, text) in entries {
        let text = text.trim();
        if text.is_empty() {
            continue;
        }
        let (minutes, seconds, centis) = (ms / 60_000, ms / 1000 % 60, ms % 1000 / 10);
        out.push_str(&format!("[{minutes:02}:{seconds:02}.{centis:02}]{text}\n"));
    }
    (!out.is_empty()).then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timestamp_forms_the_dart_parser_accepts() {
        for ok in ["[01:23.45]x", "[1:23]x", "[123:45.678]x", "[01:23:45]x"] {
            assert!(timestamp_len(ok).is_some(), "{ok}");
        }
        for bad in ["[ar:Me]", "[1:2]x", "01:23]x", "[01:234]x", "[:23]x"] {
            assert!(timestamp_len(bad).is_none(), "{bad}");
        }
    }

    #[test]
    fn lrc_text_is_synced() {
        let lrc = "[ar:Artist]\n[ti:Song]\n[00:01.00]First\n[00:05.50]Second\n";
        assert!(is_synced(lrc));
        assert!(is_synced("[00:01.00][00:30.00]Chorus line"));
    }

    #[test]
    fn plain_lyrics_are_not_synced() {
        assert!(!is_synced("Just some words\nand more words"));
        assert!(!is_synced("[Chorus]\nLa la la\n[Verse 2]\nMore"));
        assert!(!is_synced(""));
        assert!(!is_synced("[ar:Artist]\n[00:01.00]"), "no timed text");
    }

    #[test]
    fn header_tags_alone_are_not_lyrics() {
        assert!(has_no_lyric_lines("[instrumental:true]"));
        assert!(has_no_lyric_lines("[ti:Song]\n[ar:Artist]\n"));
        assert!(!has_no_lyric_lines("[instrumental:true]\nActual words"));
        assert!(!has_no_lyric_lines("[00:01.00]Timed"));
    }

    #[test]
    fn header_lines_are_stripped_from_plain_lyrics() {
        let text = "[ti:Song]\n[by:Tool (source: LRCLIB)]\n\nFirst line\n[Chorus]\nLa la";
        assert_eq!(without_header_tags(text), "First line\n[Chorus]\nLa la");
        assert_eq!(without_header_tags("No headers\nhere"), "No headers\nhere");
    }

    #[test]
    fn mostly_plain_text_with_a_stray_timestamp_is_plain() {
        assert!(!is_synced("Line one\nLine two\n[00:01.00]odd\nLine four"));
    }

    #[test]
    fn sylt_entries_become_lrc() {
        let entries = vec![
            (1_000, "\nFirst".to_string()),
            (65_430, "Second ".to_string()),
            (70_000, "  ".to_string()),
        ];
        assert_eq!(
            lrc_from_timed_entries(&entries).unwrap(),
            "[00:01.00]First\n[01:05.43]Second\n"
        );
        assert!(lrc_from_timed_entries(&[(0, " ".into())]).is_none());
    }
}
