AlbumArt shows a square cover at a fixed size, with a hairline edge, and provides six placeholder covers drawn entirely from tokens for tracks that have no image.

**Your app provides:** the cover image for real releases (an `<img>` with `object-fit: cover` inside `.vs-art`), or a placeholder kind for demos and empty covers: `harbour`, `moss`, `lantern`, `tide`, `moon` or `bloom`. Give every cover an accessible name.

```html
<span class="vs-art vs-art--row" data-art="harbour" role="img" aria-label="Harbour Lights cover">
  <svg viewBox="0 0 200 200" aria-hidden="true">…</svg>
</span>
```

Helper: `Vesper.art(kind, sizeClass, label)`.

Sizes: `vs-art--nav` 28px, `vs-art--row` 44px (`size-art-row`), `vs-art--bar` 60px (`size-art-bar`), `vs-art--card` 176px, `vs-art--lg` 184px (playlist header), `vs-art--hero` 320px (`size-art-hero`, with `shadow-art` and `radius-xl`). Small sizes use `radius-sm`; cards `radius-md`; the playlist header `radius-lg`.

Do
- Keep artwork square and never stretch it; a 1px inset `line` edge is drawn automatically so dark covers never dissolve into the ground.
- Let placeholders vary across a list so a queue never looks like one repeated tile.

Don't
- Overlay text on artwork.
- Add gradients or extra colours to the placeholders: they use `ember`, `accent`, `rose`, `sea`, `sand` and the surface steps only.
