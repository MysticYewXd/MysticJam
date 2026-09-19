/* @ds-bundle: {"format":4,"namespace":"Vesper","components":[]} */
/* Vesper helpers: icons, placeholder album art, and light interactivity for the CSS components. No dependencies. */
(function () {
  'use strict';

  var ICON_PATHS = {
    play: '<path d="M8 5.6v12.8a1 1 0 0 0 1.52.85l10.2-6.4a1 1 0 0 0 0-1.7L9.52 4.75A1 1 0 0 0 8 5.6z"/>',
    pause: '<rect x="6.5" y="5" width="4" height="14" rx="1.5"/><rect x="13.5" y="5" width="4" height="14" rx="1.5"/>',
    next: '<path d="M5.5 6.4v11.2a.9.9 0 0 0 1.4.75l8.1-5.6a.9.9 0 0 0 0-1.5L6.9 5.65a.9.9 0 0 0-1.4.75z"/><rect x="16.8" y="5" width="2.7" height="14" rx="1.35"/>',
    prev: '<g transform="translate(24 0) scale(-1 1)"><path d="M5.5 6.4v11.2a.9.9 0 0 0 1.4.75l8.1-5.6a.9.9 0 0 0 0-1.5L6.9 5.65a.9.9 0 0 0-1.4.75z"/><rect x="16.8" y="5" width="2.7" height="14" rx="1.35"/></g>',
    shuffle: '<path d="M3 7h3.5c1.6 0 3 .8 3.9 2.1l3.2 4.8c.9 1.3 2.3 2.1 3.9 2.1H21"/><path d="M18 14l3 3-3 3"/><path d="M3 17h3.5c1.6 0 3-.8 3.9-2.1"/><path d="M13.6 9.1C14.5 7.8 15.9 7 17.5 7H21"/><path d="M18 4l3 3-3 3"/>',
    repeat: '<path d="M4 11V9a3 3 0 0 1 3-3h12"/><path d="M16 3l3 3-3 3"/><path d="M20 13v2a3 3 0 0 1-3 3H5"/><path d="M8 21l-3-3 3-3"/>',
    'repeat-one': '<path d="M4 11V9a3 3 0 0 1 3-3h12"/><path d="M16 3l3 3-3 3"/><path d="M20 13v2a3 3 0 0 1-3 3H5"/><path d="M8 21l-3-3 3-3"/><path d="M11 10.6l1.4-.9v4.6"/>',
    heart: '<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/>',
    volume: '<path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5H4z"/><path d="M15.5 9a4 4 0 0 1 0 6"/><path d="M18 6.5a7.5 7.5 0 0 1 0 11"/>',
    'volume-mute': '<path d="M4 9.5v5h3.5L12 18.5v-13L7.5 9.5H4z"/><path d="M16 9.5l5 5"/><path d="M21 9.5l-5 5"/>',
    queue: '<path d="M4 6h11"/><path d="M4 11h11"/><path d="M4 16h6"/><path d="M17 13.5v6l4.5-3z"/>',
    home: '<path d="M4 11l8-6.5 8 6.5"/><path d="M6 10v9h4v-5h4v5h4v-9"/>',
    search: '<circle cx="11" cy="11" r="6.5"/><path d="M16 16l4.5 4.5"/>',
    library: '<rect x="4" y="4" width="4" height="16" rx="1"/><rect x="10" y="4" width="4" height="16" rx="1"/><path d="M16.3 5.8l3.4-.9 3 11.3-3.4.9z" transform="translate(-1.7 0)"/>',
    album: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="2.5"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0"/><path d="M12 17.5V21"/>',
    download: '<path d="M12 4v11"/><path d="M7.5 11l4.5 4.5 4.5-4.5"/><path d="M5 20h14"/>',
    more: '<circle cx="6" cy="12" r="1.7"/><circle cx="12" cy="12" r="1.7"/><circle cx="18" cy="12" r="1.7"/>',
    'chevron-left': '<path d="M14.5 6l-6 6 6 6"/>',
    'chevron-right': '<path d="M9.5 6l6 6-6 6"/>',
    plus: '<path d="M12 5v14"/><path d="M5 12h14"/>',
    check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    moon: '<path d="M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6L7 7M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4"/>'
  };
  var FILLED = { play: 1, pause: 1, next: 1, prev: 1, more: 1 };

  function icon(name, size) {
    var s = size || 24;
    var body = ICON_PATHS[name];
    if (!body) return '';
    var filled = FILLED[name];
    return '<svg class="vs-icon" width="' + s + '" height="' + s + '" viewBox="0 0 24 24" aria-hidden="true" focusable="false" ' +
      'fill="' + (filled ? 'currentColor' : 'none') + '" stroke="' + (filled ? 'none' : 'currentColor') + '" ' +
      'stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>';
  }

  function landscape(sx, sy, sr) {
    return '<rect class="a-sky" width="200" height="200"/>' +
      '<circle class="a-sun" cx="' + sx + '" cy="' + sy + '" r="' + sr + '"/>' +
      '<path class="a-far" d="M0 128C30 104 58 100 88 118S150 132 200 106V200H0z"/>' +
      '<path class="a-mid" d="M0 150C40 130 76 132 110 148S168 158 200 140V200H0z"/>' +
      '<path class="a-near" d="M0 174C36 160 80 164 118 176S176 182 200 168V200H0z"/>';
  }
  var ART = {
    harbour: landscape(128, 82, 34),
    moss: landscape(70, 74, 26),
    lantern: landscape(140, 96, 42),
    tide: '<rect class="a-sky" width="200" height="200"/>' +
      ['a-w1', 'a-w2', 'a-w3', 'a-w4', 'a-w5'].map(function (c, i) {
        var y = 44 + i * 30;
        return '<path class="' + c + '" fill="none" stroke-width="7" stroke-linecap="round" d="M-10 ' + y + 'Q20 ' + (y - 20) + ' 50 ' + y + 'T110 ' + y + 'T170 ' + y + 'T230 ' + y + '"/>';
      }).join(''),
    moon: '<rect class="a-sky" width="200" height="200"/>' +
      '<circle class="a-sun" cx="100" cy="100" r="58"/><circle class="a-sky" cx="128" cy="84" r="52"/>' +
      '<circle class="a-star" cx="38" cy="42" r="2.5"/><circle class="a-star" cx="164" cy="46" r="2"/>' +
      '<circle class="a-star" cx="150" cy="158" r="2.5"/><circle class="a-star" cx="52" cy="150" r="2"/>',
    bloom: '<rect class="a-sky" width="200" height="200"/>' +
      '<circle class="a-c1" cx="100" cy="100" r="76"/><circle class="a-c2" cx="100" cy="100" r="52"/>' +
      '<circle class="a-c3" cx="100" cy="100" r="28"/><circle class="a-sky" cx="100" cy="100" r="10"/>'
  };

  function art(kind, cls, label) {
    var k = ART[kind] ? kind : 'harbour';
    return '<span class="vs-art ' + (cls || '') + '" data-art="' + k + '" role="img" aria-label="' + (label || 'Album art') + '">' +
      '<svg viewBox="0 0 200 200" preserveAspectRatio="xMidYMid slice" aria-hidden="true">' + ART[k] + '</svg></span>';
  }

  function fmt(sec) {
    var t = Math.max(0, Math.round(sec));
    var m = Math.floor(t / 60), s = t % 60;
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  function slider(el) {
    var min = parseFloat(el.getAttribute('aria-valuemin') || '0');
    var max = parseFloat(el.getAttribute('aria-valuemax') || '100');
    function set(v, emit) {
      v = Math.min(max, Math.max(min, v));
      el.setAttribute('aria-valuenow', String(Math.round(v * 100) / 100));
      el.style.setProperty('--vs-pct', ((v - min) / (max - min) * 100) + '%');
      if (emit) el.dispatchEvent(new CustomEvent('vs-input', { bubbles: true, detail: { value: v } }));
    }
    el._set = set;
    set(parseFloat(el.getAttribute('aria-valuenow') || '0'), false);
    function fromEvent(e) {
      var r = el.getBoundingClientRect();
      return min + (max - min) * Math.min(1, Math.max(0, (e.clientX - r.left) / r.width));
    }
    el.addEventListener('pointerdown', function (e) {
      try { el.setPointerCapture(e.pointerId); } catch (err) { /* not capturable */ }
      el.classList.add('is-drag');
      set(fromEvent(e), true);
    });
    el.addEventListener('pointermove', function (e) { if (el.classList.contains('is-drag')) set(fromEvent(e), true); });
    function end() { el.classList.remove('is-drag'); }
    el.addEventListener('pointerup', end);
    el.addEventListener('pointercancel', end);
    el.addEventListener('keydown', function (e) {
      var step = parseFloat(el.getAttribute('data-step') || String((max - min) / 20));
      var v = parseFloat(el.getAttribute('aria-valuenow') || '0');
      var next = null;
      if (e.key === 'ArrowRight' || e.key === 'ArrowUp') next = v + step;
      else if (e.key === 'ArrowLeft' || e.key === 'ArrowDown') next = v - step;
      else if (e.key === 'PageUp') next = v + step * 3;
      else if (e.key === 'PageDown') next = v - step * 3;
      else if (e.key === 'Home') next = min;
      else if (e.key === 'End') next = max;
      if (next !== null) { e.preventDefault(); set(next, true); }
    });
  }

  function player(root) {
    var dur = parseFloat(root.getAttribute('data-duration') || '200');
    var t = parseFloat(root.getAttribute('data-elapsed') || '0');
    var seek = root.querySelector('[data-role="seek"]');
    var elapsed = root.querySelector('.vs-elapsed');
    var remaining = root.querySelector('.vs-remaining');
    var play = root.querySelector('.vs-btn--play');
    var timer = null;
    function render() {
      if (seek && seek._set) {
        seek._set(t / dur * 100, false);
        seek.setAttribute('aria-valuetext', fmt(t) + ' of ' + fmt(dur));
      }
      if (elapsed) elapsed.textContent = fmt(t);
      if (remaining) remaining.textContent = '-' + fmt(dur - t);
    }
    function sync() {
      var on = play && play.getAttribute('data-playing') === 'true';
      if (on && !timer) timer = setInterval(function () { t += 0.25; if (t >= dur) t = 0; render(); }, 250);
      if (!on && timer) { clearInterval(timer); timer = null; }
    }
    if (play) {
      play.addEventListener('click', function () {
        var on = play.getAttribute('data-playing') === 'true';
        play.setAttribute('data-playing', on ? 'false' : 'true');
        play.setAttribute('aria-label', on ? 'Play' : 'Pause');
        sync();
      });
    }
    if (seek) seek.addEventListener('vs-input', function (e) { t = e.detail.value / 100 * dur; render(); });
    render();
    sync();
  }

  function mount(scope) {
    var root = scope || document;
    var sliders = root.querySelectorAll('.vs-slider');
    for (var i = 0; i < sliders.length; i++) if (!sliders[i]._set) slider(sliders[i]);
    var players = root.querySelectorAll('[data-vs-player]');
    for (var j = 0; j < players.length; j++) player(players[j]);
    root.addEventListener('click', function (e) {
      var tog = e.target.closest ? e.target.closest('[data-toggle], .vs-btn--fav') : null;
      if (tog) {
        tog.setAttribute('aria-pressed', tog.getAttribute('aria-pressed') === 'true' ? 'false' : 'true');
        e.stopPropagation();
        return;
      }
      var row = e.target.closest ? e.target.closest('.vs-row') : null;
      if (row && row.parentNode) {
        var sibs = row.parentNode.querySelectorAll('.vs-row');
        for (var k = 0; k < sibs.length; k++) sibs[k].setAttribute('aria-current', sibs[k] === row ? 'true' : 'false');
        return;
      }
      var nav = e.target.closest ? e.target.closest('.vs-nav__item') : null;
      if (nav) {
        e.preventDefault();
        var all = root.querySelectorAll('.vs-nav__item');
        for (var n = 0; n < all.length; n++) all[n].removeAttribute('aria-current');
        nav.setAttribute('aria-current', 'page');
      }
    });
    root.addEventListener('keydown', function (e) {
      if ((e.key === 'Enter' || e.key === ' ') && e.target.classList && e.target.classList.contains('vs-row')) {
        e.preventDefault();
        e.target.click();
      }
    });
  }

  /* ---------- Markup builders (optional: each returns an HTML string that the README of its component documents) ---------- */
  function esc(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  var SAMPLE = {
    tracks: [
      { title: 'Harbour Lights', artist: 'Marlowe Reed', album: 'Evening Drift', dur: 222, art: 'harbour', fav: true },
      { title: 'Slow Tide', artist: 'Ines Calloway', album: 'Small Hours', dur: 258, art: 'tide', fav: false },
      { title: 'Night Garden', artist: 'The Quiet Hours', album: 'Night Garden', dur: 303, art: 'moss', fav: true },
      { title: 'Paper Lanterns', artist: 'Sabine Ortega', album: 'Lantern Season', dur: 207, art: 'lantern', fav: false },
      { title: 'Low Sun', artist: 'Marlowe Reed', album: 'Evening Drift', dur: 241, art: 'bloom', fav: false },
      { title: 'Rain on Glass', artist: 'Ines Calloway', album: 'Small Hours', dur: 176, art: 'moon', fav: false },
      { title: 'Blue Hour', artist: 'The Quiet Hours', album: 'Night Garden', dur: 218, art: 'harbour', fav: false }
    ],
    playlists: [
      { name: 'Evening Drift', art: 'harbour' },
      { name: 'Rain on Glass', art: 'moon' },
      { name: 'Slow Morning', art: 'moss' },
      { name: 'Late Train', art: 'lantern' }
    ]
  };

  function button(name, label, o) {
    o = o || {};
    var cls = 'vs-btn' + (o.sm ? ' vs-btn--sm' : '') + (o.cls ? ' ' + o.cls : '');
    return '<button type="button" class="' + cls + '" aria-label="' + esc(label) + '"' +
      (o.pressed !== undefined ? ' aria-pressed="' + (o.pressed ? 'true' : 'false') + '"' : '') +
      (o.toggle ? ' data-toggle' : '') + '>' + icon(name, o.size || 22) + '</button>';
  }

  function playButton(o) {
    o = o || {};
    var sm = o.size === 'sm';
    var px = sm ? 22 : 28;
    var on = !!o.playing;
    return '<button type="button" class="vs-btn vs-btn--play' + (sm ? ' vs-btn--play-sm' : '') + '" data-playing="' + (on ? 'true' : 'false') + '" aria-label="' + (on ? 'Pause' : 'Play') + '">' +
      icon('play', px).replace('<svg ', '<svg data-when="paused" ') + icon('pause', px).replace('<svg ', '<svg data-when="playing" ') + '</button>';
  }

  function transport(o) {
    o = o || {};
    var g = o.size === 'sm' ? 20 : 22;
    return '<div class="vs-transport">' +
      button('shuffle', 'Shuffle', { toggle: true, pressed: !!o.shuffle, size: g }) +
      button('prev', 'Previous track', { size: g }) +
      playButton(o) +
      button('next', 'Next track', { size: g }) +
      button('repeat', 'Repeat', { toggle: true, pressed: !!o.repeat, size: g }) + '</div>';
  }

  function sliderHtml(label, value, role) {
    return '<div class="vs-slider"' + (role ? ' data-role="' + role + '"' : '') + ' role="slider" tabindex="0" aria-label="' + esc(label) + '" aria-valuemin="0" aria-valuemax="100" aria-valuenow="' + value + '">' +
      '<div class="vs-slider__track"><div class="vs-slider__fill"></div></div><div class="vs-slider__thumb"></div></div>';
  }

  function progress() {
    return '<div class="vs-progress"><span class="time vs-elapsed">0:00</span>' + sliderHtml('Seek', 0, 'seek') + '<span class="time vs-remaining">-0:00</span></div>';
  }

  function volume(value) {
    return '<div class="vs-volume">' + button('volume', 'Mute', { sm: true, size: 20 }) + sliderHtml('Volume', value === undefined ? 64 : value, 'volume') + '</div>';
  }

  function row(t, i, o) {
    o = o || {};
    var idx = '<span class="vs-row__idx time"><span class="vs-row__num">' + (i + 1) + '</span><span class="vs-eq" role="img" aria-label="Playing"><i></i><i></i><i></i></span></span>';
    var main = '<div class="vs-row__main">' + art(t.art, 'vs-art--row', esc(t.title) + ' cover') +
      '<div class="vs-row__text"><div class="vs-row__title body-strong">' + esc(t.title) + '</div><div class="vs-row__artist">' + esc(t.artist) + '</div></div></div>';
    var fav = button('heart', 'Like', { sm: true, cls: 'vs-btn--fav', pressed: !!t.fav, size: 18 });
    var time = '<span class="vs-row__time time">' + fmt(t.dur) + '</span>';
    return '<div class="vs-row" role="listitem" tabindex="0" aria-current="' + (o.current ? 'true' : 'false') + '">' + idx + main +
      (o.compact ? '' : '<div class="vs-row__album body">' + esc(t.album) + '</div>') + fav + time +
      (o.compact ? '' : button('more', 'More options', { sm: true, size: 18 })) + '</div>';
  }

  function list(tracks, o) {
    o = o || {};
    var head = o.compact ? '' : '<div class="vs-list__head" aria-hidden="true"><span>#</span><span>Title</span><span>Album</span><span></span><span>Time</span><span></span></div>';
    var rows = tracks.map(function (t, i) { return row(t, i, { compact: o.compact, current: o.current === i }); }).join('');
    return '<div class="vs-list' + (o.compact ? ' vs-list--compact' : '') + '" role="list">' + head + rows + '</div>';
  }

  function navItem(iconName, label, current) {
    return '<a class="vs-nav__item body" href="#"' + (current ? ' aria-current="page"' : '') + '>' + icon(iconName, 20) + '<span>' + esc(label) + '</span></a>';
  }

  function sidebar(active) {
    var lib = [['home', 'Home'], ['library', 'Songs'], ['album', 'Albums'], ['mic', 'Artists'], ['download', 'Downloads']];
    var items = lib.map(function (n) { return navItem(n[0], n[1], n[1] === (active || 'Home')); }).join('');
    var pls = SAMPLE.playlists.map(function (p) {
      return '<a class="vs-nav__item body" href="#">' + art(p.art, 'vs-art--nav', esc(p.name)) + '<span class="vs-truncate">' + esc(p.name) + '</span></a>';
    }).join('');
    return '<nav class="vs-side" aria-label="Library">' +
      '<div class="vs-side__brand">' + icon('moon', 24) + '<span class="display-sm">Vesper</span></div>' +
      '<div class="vs-search">' + icon('search', 20) + '<input class="vs-search__input" type="search" placeholder="Search your music" aria-label="Search your music"></div>' +
      '<div class="vs-side__group"><div class="vs-side__label overline">Library</div>' + items + '</div>' +
      '<div class="vs-side__group"><div class="vs-side__label overline">Playlists</div>' + pls + '</div></nav>';
  }

  function bar(t, o) {
    o = o || {};
    return '<div class="vs-bar" data-vs-player data-duration="' + t.dur + '" data-elapsed="' + (o.elapsed || 0) + '">' +
      '<div class="vs-bar__track">' + art(t.art, 'vs-art--bar', esc(t.title) + ' cover') +
      '<div class="vs-bar__meta"><div class="vs-bar__title display-sm vs-truncate">' + esc(t.title) + '</div><div class="vs-bar__artist vs-truncate">' + esc(t.artist) + '</div></div>' +
      button('heart', 'Like', { sm: true, cls: 'vs-btn--fav', pressed: !!t.fav, size: 18 }) + '</div>' +
      '<div class="vs-bar__center">' + transport({ size: 'sm', playing: o.playing !== false }) + progress() + '</div>' +
      '<div class="vs-bar__right">' + button('queue', 'Queue', { size: 20 }) + volume(64) + '</div></div>';
  }

  function hero(t, o) {
    o = o || {};
    return '<section class="vs-hero' + (o.stack ? ' vs-hero--stack' : '') + '" data-vs-player data-duration="' + t.dur + '" data-elapsed="' + (o.elapsed || 0) + '">' +
      '<span class="vs-hero__glow" aria-hidden="true"></span>' + art(t.art, 'vs-art--hero', esc(t.title) + ' cover') +
      '<div class="vs-hero__info"><div class="vs-hero__eyebrow overline">Now playing</div>' +
      '<h2 class="vs-hero__title display-xl vs-truncate">' + esc(t.title) + '</h2>' +
      '<p class="vs-hero__artist body-lg">' + esc(t.artist) + '</p>' +
      '<div class="vs-hero__meta"><span class="vs-chip">' + icon('check', 14) + 'Lossless</span><span class="vs-hero__album caption">' + esc(t.album) + '</span></div>' +
      '<div class="vs-hero__controls">' + progress() +
      '<div class="vs-hero__row">' + button('heart', 'Like', { sm: true, cls: 'vs-btn--fav', pressed: !!t.fav, size: 20 }) + transport({ playing: o.playing !== false }) + volume(64) + '</div></div></div></section>';
  }

  window.Vesper = {
    icon: icon, art: art, fmt: fmt, mount: mount, esc: esc,
    button: button, playButton: playButton, transport: transport, progress: progress, volume: volume,
    row: row, list: list, sidebar: sidebar, bar: bar, hero: hero,
    sample: SAMPLE, artKinds: Object.keys(ART), iconNames: Object.keys(ICON_PATHS)
  };
})();
