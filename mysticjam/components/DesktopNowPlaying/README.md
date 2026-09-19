DesktopNowPlaying is the reference 1280 by 760 window for the focused listening view: sidebar on the left, a stacked `NowPlaying` hero in the middle and an "Up next" queue panel on the right.

**Your app provides:** the current track, the upcoming tracks and all playback state; this layout only arranges the components.

Structure: `.vs-window` (grid: `size-sidebar` plus a fluid main) containing `Sidebar` and `.vs-main`. The main area has a 40px top row of back and forward buttons on the left and queue and more buttons on the right, then `.vs-main__body`, a two-column grid: the hero (`vs-hero--stack`) and a 360px `vs-panel` holding a compact `TrackList`.

Spacing: main padding `space-5` top and bottom and `space-6` at the sides; `space-5` between the top row and the body and between the two panels. The window has `radius-xl` and `shadow-float`.

Do
- Use this arrangement whenever the listener chooses to focus on the song.
- Let the queue panel scroll internally; the hero stays fixed.

Don't
- Add the `PlayerBar` here; the hero already holds the transport.
- Widen the queue past 400px; the hero needs the room for the art and title.
