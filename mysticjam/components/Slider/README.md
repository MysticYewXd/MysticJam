Slider is the draggable bar used for seeking within a track and for volume, with the elapsed and remaining times around the seek bar.

**Your app provides:** the current value (`aria-valuenow`, 0 to 100), the track duration and elapsed time (`data-duration`, `data-elapsed` on the container that holds a seek bar), and a listener for the `vs-input` event that reports `detail.value` while the listener drags or uses the keyboard.

```html
<div class="vs-progress">
  <span class="time vs-elapsed">1:34</span>
  <div class="vs-slider" data-role="seek" role="slider" tabindex="0" aria-label="Seek"
       aria-valuemin="0" aria-valuemax="100" aria-valuenow="42">
    <div class="vs-slider__track"><div class="vs-slider__fill"></div></div>
    <div class="vs-slider__thumb"></div>
  </div>
  <span class="time vs-remaining">-2:08</span>
</div>
```

Helpers: `Vesper.progress()` and `Vesper.volume(value)` return this markup; `Vesper.mount(root)` wires pointer, click and keyboard (arrows step 5, Page keys step 15, Home and End jump).

The unfilled track is `surface-3`, the fill is `ember`, the thumb is `ink` and appears on hover, focus and drag. The track grows from `size-slider-track` (4px) to 6px on hover. The fill and the printed times carry the value, and `aria-valuetext` reads "1:34 of 3:42" for screen readers.

Do
- Keep the times in `time` (tabular numerals, `ink-faint`) so the bar does not jitter as digits change.
- Give the volume slider a fixed width (104px in the bar) beside its speaker icon.

Don't
- Recolour the fill: it is always `ember`.
- Hide the slider's keyboard focus; the thumb and the `focus-ring` outline must show.
