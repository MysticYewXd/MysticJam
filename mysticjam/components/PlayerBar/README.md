PlayerBar is the floating bar that keeps playback within reach while the listener browses: the current track on the left, compact transport and seek bar in the centre, queue and volume on the right.

**Your app provides:** the current track (`title`, `artist`, `dur`, `art`, `fav`), the elapsed time, whether it is playing, and handlers for seek, transport, like, queue and volume.

```html
<div class="vs-bar" data-vs-player data-duration="303" data-elapsed="122">
  <div class="vs-bar__track">…art vs-art--bar… <div class="vs-bar__meta">…title, artist…</div> …like…</div>
  <div class="vs-bar__center">…compact transport… …progress…</div>
  <div class="vs-bar__right">…queue… …volume…</div>
</div>
```

Helper: `Vesper.bar(track, {elapsed, playing})`.

The bar is `size-playerbar` (92px) tall on `surface-2` with `radius-lg` and `shadow-card`, floating at the bottom of the main area with a `space-5` margin. The centre column is 300px to 400px wide so the title keeps room; the play button is `size-play-sm` (48px) with `size-control-md` neighbours. The track title uses `display-sm`, the artist 13px `ink-muted`; both truncate.

Do
- Keep it visible on every browsing screen and hide it only when `NowPlaying` is open.
- Let the title truncate before you narrow the centre column.

Don't
- Add more than the queue and volume controls to the right side.
- Stretch the seek bar past 400px; it becomes hard to scrub precisely.
