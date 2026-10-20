//! Tag value rules, ported from the Dart readers (year_parser.dart,
//! track_number_parser.dart) so both sides store the same values.

/// Trimmed value, or `None` when blank.
pub fn non_empty(value: Option<&str>) -> Option<String> {
    let trimmed = value?.trim();
    (!trimmed.is_empty()).then(|| trimmed.to_string())
}

/// Several tag values as one: trimmed, blanks and repeats dropped, joined
/// with ", " in their original order. `None` when nothing is left.
pub fn joined<'a>(values: impl Iterator<Item = &'a str>) -> Option<String> {
    let mut kept: Vec<&str> = Vec::new();
    for v in values.map(str::trim).filter(|v| !v.is_empty()) {
        if !kept.contains(&v) {
            kept.push(v);
        }
    }
    (!kept.is_empty()).then(|| kept.join(", "))
}

/// First standalone four-digit year from 1000 to 2999 in a raw date
/// ("2019", "2019-05-03", "05/03/2019"). Digits on either side disqualify a
/// run, so "12345" or a catalogue number doesn't yield a bogus year.
pub fn leading_year(raw: Option<&str>) -> Option<i32> {
    let b = raw?.as_bytes();
    (0..b.len().saturating_sub(3)).find_map(|i| {
        let run = &b[i..i + 4];
        let before = i > 0 && b[i - 1].is_ascii_digit();
        let after = b.get(i + 4).is_some_and(u8::is_ascii_digit);
        let ok = matches!(run[0], b'1' | b'2') && run.iter().all(u8::is_ascii_digit);
        (ok && !before && !after).then(|| std::str::from_utf8(run).ok()?.parse().ok())?
    })
}

/// Track number from "5" or "5/12" (track/total).
pub fn leading_track_number(raw: Option<&str>) -> Option<i32> {
    let trimmed = raw?.trim();
    let leading = trimmed.split_once('/').map_or(trimmed, |(n, _)| n);
    leading.trim().parse().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn years_like_the_dart_parser() {
        assert_eq!(leading_year(Some("2019")), Some(2019));
        assert_eq!(leading_year(Some("2019-05-03")), Some(2019));
        assert_eq!(leading_year(Some("05/03/2019")), Some(2019));
        assert_eq!(leading_year(Some("1999-12-31T23:00")), Some(1999));
        assert_eq!(leading_year(Some("12345")), None);
        assert_eq!(leading_year(Some("0999")), None);
        assert_eq!(leading_year(Some("3000")), None);
        assert_eq!(leading_year(Some("abc")), None);
        assert_eq!(leading_year(None), None);
    }

    #[test]
    fn track_numbers_like_the_dart_parser() {
        assert_eq!(leading_track_number(Some("5")), Some(5));
        assert_eq!(leading_track_number(Some(" 5 / 12 ")), Some(5));
        assert_eq!(leading_track_number(Some("05/12")), Some(5));
        assert_eq!(leading_track_number(Some("A1")), None);
        assert_eq!(leading_track_number(Some("")), None);
        assert_eq!(leading_track_number(None), None);
    }

    #[test]
    fn several_values_are_joined_in_order() {
        let j = |v: &[&str]| joined(v.iter().copied());
        assert_eq!(j(&["Kanye West", "Ye"]).as_deref(), Some("Kanye West, Ye"));
        assert_eq!(j(&["Kanye West, Ye"]).as_deref(), Some("Kanye West, Ye"));
        assert_eq!(j(&[" A ", "", "B", "A"]).as_deref(), Some("A, B"));
        assert_eq!(j(&["  "]), None);
        assert_eq!(j(&[]), None);
    }

    #[test]
    fn blank_values_are_none() {
        assert_eq!(non_empty(Some("  Title ")).as_deref(), Some("Title"));
        assert_eq!(non_empty(Some("   ")), None);
        assert_eq!(non_empty(None), None);
    }
}
