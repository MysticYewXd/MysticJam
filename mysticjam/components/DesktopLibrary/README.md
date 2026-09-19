DesktopLibrary is the reference 1280 by 760 window for browsing: sidebar on the left, a playlist header and track list in the middle, and the floating `PlayerBar` along the bottom.

**Your app provides:** the playlist (name, description, cover), its tracks, the playing index and all playback state.

Structure: `.vs-window` containing `Sidebar` and `.vs-main`. The main area holds the 40px top row, `.vs-pl-head` (184px `vs-art--lg` cover, an `overline` "Playlist" label, the `display-lg` title, a `body` description in `ink-muted`, then a `vs-cta` Play and a `vs-cta--ghost` Shuffle), a `.vs-main__scroll` region holding the full `TrackList`, and the `PlayerBar`.

The scroll region fades out over its last 44px so rows disappear softly behind the bar instead of being cut. Gaps between header, list and bar are `space-5`.

Do
- Highlight the playing row with `accent-soft` and let the sidebar show which section is current.
- Keep one `accent` fill in the header (Play) and the bar's play button as the only other.

Don't
- Repeat the artwork or title in the list header; the row for the playing song is enough.
- Place the bar inside the scroll region; it stays fixed while the list scrolls.
