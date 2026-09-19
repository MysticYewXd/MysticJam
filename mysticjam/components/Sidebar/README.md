Sidebar is the fixed 248px navigation column with the Vesper wordmark, a search field, the Library links and the listener's playlists.

**Your app provides:** the navigation destinations, the current page (`aria-current="page"`), the playlist names with their cover art, and the search handler.

```html
<nav class="vs-side" aria-label="Library">
  <div class="vs-side__brand">…moon icon…<span class="display-sm">Vesper</span></div>
  <div class="vs-search">…search icon…<input class="vs-search__input" type="search" placeholder="Search your music"></div>
  <div class="vs-side__group">
    <div class="vs-side__label overline">Library</div>
    <a class="vs-nav__item body" href="#" aria-current="page">…home icon…<span>Home</span></a>
  </div>
</nav>
```

Helper: `Vesper.sidebar(activeLabel)`; `Vesper.mount` moves `aria-current` on click.

Width is `size-sidebar`, ground `surface-1`, padding `space-5` by `space-3`. Items are 40px tall with `radius-md`; the active item takes `accent-soft` with `ink` text and an `accent` icon; hover uses `surface-2`. The search field is a `radius-pill` input on `surface-2` with a `line-strong` border, and its border turns `accent` on focus.

Do
- Keep group labels in `overline` and `ink-faint`.
- Show playlist covers at `vs-art--nav` (28px) beside the name.

Don't
- Add a second highlighted item; only one link is current at a time.
- Collapse the sidebar below 1024px by hiding labels; switch to a compact icon rail in your own layout instead.
