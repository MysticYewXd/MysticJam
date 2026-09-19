NowPlaying is the hero panel for focused listening: large artwork with an ember glow behind it, the track title in `display-xl`, the artist, a quality chip, the seek bar, the transport controls, a like button and volume.

**Your app provides:** the current track (`title`, `artist`, `album`, `dur`, `art`, `fav`), the elapsed time, whether it is playing, and handlers for seek, transport, like and volume.

```html
<section class="vs-hero" data-vs-player data-duration="222" data-elapsed="84">
  <span class="vs-hero__glow" aria-hidden="true"></span>
  …AlbumArt vs-art--hero…
  <div class="vs-hero__info">
    <div class="vs-hero__eyebrow overline">Now playing</div>
    <h2 class="vs-hero__title display-xl">Harbour Lights</h2>
    <p class="vs-hero__artist body-lg">Marlowe Reed</p>
    <div class="vs-hero__meta">…chip, album…</div>
    <div class="vs-hero__controls">…progress… <div class="vs-hero__row">…like, transport, volume…</div></div>
  </div>
</section>
```

Helper: `Vesper.hero(track, {stack, elapsed, playing})`. Add `vs-hero--stack` (art above the text, everything centred) when the panel shares the screen with a queue.

The panel sits on `surface-1` with `radius-xl`; the glow is an `ember` circle at 11% opacity with a 90px blur. Padding is `space-8` when it stands alone and `space-5` when stacked. The title, artist and meta use `ink`, `ink-muted` and `ink-faint`.

Do
- Show one hero per screen, and hide the `PlayerBar` while it is open.
- Truncate an overlong title with an ellipsis; never shrink the display size.

Don't
- Put more than the like button, transport and volume in the control row.
- Add a second glow, a gradient, or a blurred copy of the cover behind the panel.
