Icons is Vesper's own 24-glyph set for the player: transport, likes, volume, navigation and small actions, all as inline SVG that inherits its colour from the text around it.

**Your app provides:** the size and the surrounding colour. Icons paint with `currentColor`, so set the colour on the button or link, never on the icon.

```js
Vesper.icon('play', 28)      // returns an <svg> string, 28px, aria-hidden
Vesper.iconNames             // ['play', 'pause', 'next', 'prev', 'shuffle', …]
```

Grid and stroke: 24px viewBox, 1.75px stroke, round caps and joins, no fill. The transport glyphs (`play`, `pause`, `next`, `prev`) and `more` are solid shapes with softly rounded corners. Render at 18px in small buttons, 20px to 22px in standard buttons, 28px in the play button.

Names: play, pause, next, prev, shuffle, repeat, repeat-one, heart, volume, volume-mute, queue, home, search, library, album, mic, download, more, chevron-left, chevron-right, plus, check, moon, sun.

Do
- Pair every icon-only button with an `aria-label`; the SVG itself is `aria-hidden`.
- Draw new glyphs on the same grid with the same stroke and rounding.

Don't
- Import a third-party icon pack, use an icon font, or use emoji as icons.
- Fill an outline icon with colour, except the liked heart, which fills with `rose`.
