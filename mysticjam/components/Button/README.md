Button covers the round icon buttons, the play/pause button, the transport row, pill call-to-action buttons and chips that carry every action in the player.

**Your app provides:** an `aria-label` on every icon button, the icon (use `Vesper.icon(name, size)` or your own `currentColor` SVG), and the click handlers. Toggles use `aria-pressed`; the play button uses `data-playing="true|false"`.

```html
<button type="button" class="vs-btn" aria-label="Next track">…icon…</button>
<button type="button" class="vs-btn vs-btn--sm vs-btn--fav" aria-pressed="true" aria-label="Like">…heart…</button>
<button type="button" class="vs-btn vs-btn--play" data-playing="false" aria-label="Play">
  …play icon with data-when="paused"… …pause icon with data-when="playing"…
</button>
<button type="button" class="vs-cta">…icon…Play</button>
<button type="button" class="vs-cta vs-cta--ghost">Shuffle</button>
```

Helpers: `Vesper.transport({playing, shuffle, repeat, size})` returns the full shuffle, previous, play, next, repeat row; `Vesper.button(name, label, opts)` and `Vesper.playButton(opts)` return single buttons.

Sizes: standard `size-control-md` (40px), small `vs-btn--sm` `size-control-sm` (32px), play `size-play` (64px), compact play `vs-btn--play-sm` `size-play-sm` (48px).

Do
- Give the play button the only `accent` fill in a view; the other transport buttons rest in `ink-muted` and brighten to `ink` on hover.
- Show a toggled-on control (shuffle, repeat) in `accent` and keep the icon shape the same.
- Use `vs-cta` for the one main action of a page (Play) and `vs-cta--ghost` for the secondary (Shuffle).

Don't
- Colour a liked heart with anything but `rose`, and never rely on colour alone: the heart fills when liked.
- Put text labels inside icon buttons; use a tooltip or `aria-label`.
- Add a second `accent` fill next to the play button.
