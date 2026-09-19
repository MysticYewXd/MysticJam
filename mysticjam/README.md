Vesper is a desktop music player designed for slow, evening listening: a deep indigo-slate world lit by two warm accents and the album art. Every screen should feel like turning the lamps down. Build with the tokens and components here; do not introduce new colours, fonts or radii.

## Content fundamentals

- Write in sentence case everywhere: titles, buttons, navigation, table headers. "Up next", "Made for you", "Recently played". Only the `overline` style is set uppercase, and only for small section labels such as LIBRARY and PLAYLISTS.
- Keep copy short, calm and concrete. Describe a playlist the way you would to a friend, then give a fact: "Seven quiet songs for the last hour of light. 27 minutes."
- No exclamation marks, no emoji, no urgency. Empty states invite rather than instruct: "Nothing here yet. Add a song from your library."
- Errors are specific and gentle: "Couldn't reach the audio device. Check that it's connected."
- Address the listener as "you" only when an instruction needs it. Prefer nouns and place names to commands: "Search your music", "Downloads".
- Times are `m:ss` (`3:42`). Remaining time carries a leading minus (`-2:18`). Never write "mins" or "secs" inside the player.

## Visual foundations

**Themes.** Set `data-theme="dusk"` on the root for the default night theme and `data-theme="dawn"` for the daylight counterpart. Every colour is a token that resolves per theme; never hard-code a hex.

**Grounds.** Stack surfaces one step at a time. The window sits on `surface-0`; persistent chrome (sidebar, player bar) on `surface-1`; content panels and the bar itself on `surface-2`; hover fills, slider tracks and chips on `surface-3`. Do not jump from `surface-0` straight to `surface-3`.

**Text.** Set titles and active labels in `ink`, secondary text (artist, album, resting icons) in `ink-muted`, and tertiary text (durations, track numbers, captions) in `ink-faint`. All three hold 4.5:1 or better on `surface-0` to `surface-3` in both themes. Never set running text in `accent`, `ember` or `rose`.

**Accent roles.** Each accent has exactly one job.

- `accent` (lavender) is the action colour: the play button, the active navigation item, toggled-on controls, the playing track's title. Put `on-accent` on any `accent` fill.
- `ember` (peach) is the value colour: seek and volume fill, equalizer bars, the sun in artwork. In Dawn, keep `ember` text on `surface-0` to `surface-2` (4.3:1 on `surface-3`).
- `rose` is a liked heart, always with the filled-heart shape.
- `sea` and `sand` appear only inside artwork and the small "lossless" tick. They never colour a control.
- `accent-soft` is the translucent wash behind the selected row and active nav item.

**Focus.** Every interactive element shows a solid 2px `focus-ring` outline with a 2px offset. Do not remove it or replace it with a shadow.

**Type.** Set titles in the display family (`display-xl` for the now-playing title, `display-lg` for playlist pages, `display-md` for section headings, `display-sm` for card titles and the player-bar title) and everything else in the sans family (`body-lg`, `body`, `body-strong`, `label`, `time`, `caption`, `overline`). Use `time` with tabular numerals for every clock and duration. Above 80px, set `font-variation-settings: "opsz" 40` on Fraunces so the counters stay open.

**Spacing and layout.** Use the `space-*` steps only. Panels pad `space-5`; the main area gutters are `space-6`; the hero pads `space-8` when it stands alone and `space-5` when it stacks beside a queue. The desktop frame is a fixed `size-sidebar` (248px) sidebar plus a fluid main area; the player bar floats at the bottom of the main area at `size-playerbar` (92px) with a `space-5` margin. The now-playing art is `size-art-hero` (320px). Design for windows from 1024 by 640 upward.

**Radii.** Everything is soft. `radius-xl` for hero art and the window; `radius-lg` for cards and the player bar; `radius-md` for rows, inputs and small cards; `radius-sm` for thumbnails; `radius-pill` for sliders, chips and call-to-action buttons; `radius-round` for icon buttons and the play button.

**Shadows and light.** Shadows are wide, low and only lift things that float: artwork (`shadow-art`), the player bar and cards (`shadow-card`), the window and menus (`shadow-float`), and the play button (`glow-play`). Rows and chrome sit flat. The one soft light in the system is the `ember` glow behind the hero art (opacity .11, blur 90px); do not add other gradients or glows.

**Borders.** Use `line` for decorative hairlines between rows and the 1px inset edge on artwork. Use `line-strong` for the border of any control, such as the search field and ghost buttons.

**Motion.** Hover, press and colour changes take 200ms (`--vs-dur`) on `--vs-ease`; panel changes take 480ms. The equalizer loops at 1.2s. Nothing bounces, springs or slides in from off-screen. With `prefers-reduced-motion` the equalizer freezes; no state may depend on motion alone.

**Imagery.** Album art is the only imagery. Show it square, never stretched, always with the `line` hairline edge, and let it carry the colour. When there is no cover, use the token-built placeholders in `AlbumArt` (harbour, moss, lantern, tide, moon, bloom).

## Iconography

Vesper uses its own inline SVG icons on a 24px grid: 1.75px stroke, round caps and joins, `currentColor`, no fill. The transport glyphs (`play`, `pause`, `next`, `prev`) and `more` are solid shapes. Render icons at 18px inside small buttons, 20px to 22px in standard buttons and 28px inside the play button. There is no icon font and no emoji. The full set is previewed in `Icons` and listed in `Vesper.iconNames`; add a new glyph by following the same grid and stroke rules rather than importing a third-party pack.

## Using the components

Load `tokens.css`, then `components/bundle.css`, then `components/bundle.js`, set the theme on the root, and wrap the app in an element with the class `vs-stage`. `bundle.js` is dependency-free and exposes `window.Vesper` with `icon`, `art`, `button`, `transport`, `progress`, `volume`, `row`, `list`, `sidebar`, `bar`, `hero` (each returns an HTML string) and `mount(root)` to wire sliders, toggles, play/pause and the row and navigation selection. Read a component's guideline before using it: each one names the markup, the states and what your app must provide.

- Reach for `PlayerBar` on every browsing screen and `NowPlaying` when the listener chooses to focus on the song; never show both at full size at once.
- Keep one primary action per view: a single `accent` play button or `vs-cta`.
- Show like, more and other row actions only on hover or focus, except a liked heart, which stays visible.
