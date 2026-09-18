/*  phone-boot-post.js — runs AFTER index.html's script, for the things that need the app's
    DOM and globals to already exist. Additive: it binds listeners and never redefines app
    behaviour. Everything here is delegated from `document`, so it survives every re-render
    (the shelf, diary and observatory all rebuild their subtrees wholesale). */
(function () {
  function toNative(msg) {
    try { webkit.messageHandlers.bitacora.postMessage(msg); return true; } catch (e) { return false; }
  }

  /* ── Haptics ───────────────────────────────────────────────────────────────────────────
     With the tap highlight removed (phone.css) a control has no browser-supplied feedback at
     all, so the thumb needs something. Mapped by WEIGHT, the way iOS does it: a selection tick
     for picking, a heavier thud for a commitment, a success pattern only for a real write. */
  function tap(kind) { toNative({ cmd: 'haptic', kind: kind }); }

  document.addEventListener('click', function (e) {
    if (e.target.closest('.bottom-tabs .tab, .view-tab')) return tap('selection');
    if (e.target.closest('#fab-add, .add-btn')) return tap('medium');
    if (e.target.closest('#roul-launch')) return tap('medium');
    if (e.target.closest('.star-input .zone')) return tap('selection');
    if (e.target.closest('.item-card, .cmdk-row, .diary-entry')) return tap('light');
    if (e.target.closest('.ghost-btn, .btn-secondary, .close, .tag-chip')) return tap('light');
  }, true);

  /* A save is the one action that changes the record, so it gets the success pattern — and it
     fires on SUBMIT rather than on the button, so a keyboard save feels the same as a tap. */
  var form = document.getElementById('entry-form');
  if (form) form.addEventListener('submit', function () { tap('success'); });

  /* ── The vault talking back ────────────────────────────────────────────────────────────
     Native calls this when it accepts, holds or rejects a save. A held save is NOT allowed to
     be quiet: the whole point of holding is that a human has to look. `toast` is index.html's
     own, so the notice wears the app's voice instead of a second styling system. */
  window.__bitacoraVaultNotice = function (kind, detail) {
    try {
      if (typeof toast !== 'function') return;
      if (kind === 'shrink') toast('backup held: this save drops ' + detail + '. your backup is untouched — confirm on the alert to accept it.', true);
      else if (kind === 'invalid') toast('backup refused an unreadable save — your backup is untouched.', true);
      else if (kind === 'restored') toast('restored ' + detail + ' from the on-device backup.');
    } catch (e) {}
  };

  /* ── The document itself must not scroll ───────────────────────────────────────────────
     The shell is fixed chrome around scrolling panes. Without this, dragging on the topbar or
     the tab bar drags the whole page and the app reads as a web view in a frame. Panes keep
     their own scrolling; only drags that would move the DOCUMENT are cancelled. */
  document.addEventListener('touchmove', function (e) {
    var sc = e.target.closest('.content, .modal-body, .cmdk-results, .sidebar, .cur-thread, textarea, .observatory');
    if (!sc) e.preventDefault();
  }, { passive: false });

  /* One geometry line into the vault log on every boot. This is the only instrument that can
     see env(safe-area-inset-*): they are 0 in any desktop browser, so the one variable that
     decides whether the title sits under the clock is invisible everywhere except here. */
  function geom() {
    var cs = getComputedStyle(document.body);
    var tb = document.querySelector('.topbar');
    var r = tb ? tb.getBoundingClientRect() : { top: -1, height: -1 };
    var probe = document.createElement('div');
    probe.style.cssText = 'position:fixed;top:0;height:env(safe-area-inset-top);width:env(safe-area-inset-bottom)';
    document.body.appendChild(probe);
    var pr = probe.getBoundingClientRect();
    probe.remove();
    toNative({ cmd: 'log', text: 'geom vw=' + innerWidth + ' vh=' + innerHeight
      + ' safeTop=' + pr.height + ' safeBottom=' + pr.width
      + ' bodyPadTop=' + cs.paddingTop
      + ' topbarTop=' + Math.round(r.top) + ' topbarH=' + Math.round(r.height)
      + ' standalone=' + matchMedia('(display-mode: standalone)').matches
      + ' ' + faceReport() });
  }

  /*  document.fonts.check() answers TRUE for a face that does not exist (verified in this very
      webview: a family named NoSuchFaceXYZ reported loaded), so it cannot tell a bundled font
      from a silent fallback. Measure a CONSEQUENCE instead: render the same string in the named
      family and in an invented one. Both fall back to the same generic if the real face is
      missing, so EQUAL widths mean the font never loaded, and that is the only honest reading. */
  function faceReport() {
    function w(fam) {
      var el = document.createElement('span');
      el.textContent = 'Bitácora Hamburgefonstiv 0123';
      el.style.cssText = 'position:absolute;visibility:hidden;white-space:nowrap;font-size:48px;font-family:' + fam;
      document.body.appendChild(el);
      var x = el.getBoundingClientRect().width;
      el.remove();
      return Math.round(x * 10) / 10;
    }
    var ctlSerif = w('"NoSuchFaceXYZ", serif'), serif = w('"Instrument Serif", serif');
    var ctlMono = w('"NoSuchFaceXYZ", monospace'), mono = w('"JetBrains Mono", monospace');
    return 'serif=' + serif + ' vs fallback ' + ctlSerif + ' → ' + (serif !== ctlSerif ? 'LOADED' : 'NOT LOADED')
       + ' · mono=' + mono + ' vs fallback ' + ctlMono + ' → ' + (mono !== ctlMono ? 'LOADED' : 'NOT LOADED');
  }
  if (document.readyState === 'complete') setTimeout(geom, 300);
  else window.addEventListener('load', function () { setTimeout(geom, 300); });

  toNative({ cmd: 'ready' });
})();
