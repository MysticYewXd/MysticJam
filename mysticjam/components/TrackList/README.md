TrackList is the list of songs in a playlist, album or queue: each row shows a number, cover, title, artist, album, a like button, the duration and a more button, and marks the playing row with an accent wash and animated equalizer bars.

**Your app provides:** an array of tracks (`title`, `artist`, `album`, `dur` in seconds, `art`, `fav`), the index of the playing row, and handlers for selecting a row, liking a track and opening its menu.

```html
<div class="vs-list" role="list">
  <div class="vs-list__head" aria-hidden="true">…#, Title, Album, Time…</div>
  <div class="vs-row" role="listitem" tabindex="0" aria-current="true">
    <span class="vs-row__idx time"><span class="vs-row__num">1</span><span class="vs-eq">…</span></span>
    <div class="vs-row__main">…art…<div class="vs-row__text">…title, artist…</div></div>
    <div class="vs-row__album body">Evening Drift</div>
    …like button… <span class="vs-row__time time">3:42</span> …more button…
  </div>
</div>
```

Helpers: `Vesper.list(tracks, {compact, current})` and `Vesper.row(track, index, opts)`. Add `vs-list--compact` (album and more button omitted) for a queue on a `vs-panel`.

States: the playing row has `aria-current="true"`: `accent-soft` background, title in `accent`, equalizer bars in `ember` in place of the number. Hover lifts a row to `surface-2` (`surface-3` on a panel). Like and more are hidden until hover or focus, except a liked heart, which stays visible in `rose`. Row height is `size-track-row` (60px) with `radius-md`.

Do
- Truncate long titles with an ellipsis rather than wrapping; the row height never changes.
- Make each row keyboard-focusable; Enter or Space plays it.

Don't
- Zebra-stripe rows or add dividers between them; the list header has the only hairline.
- Show more than one row as playing.
