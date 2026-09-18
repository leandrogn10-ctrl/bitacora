/*  phone-boot-pre.js — runs BEFORE index.html's own script, which matters for all three jobs:
    the vault has to have restored before the app reads localStorage, and the share shim has to
    exist before the app's click handler tests for it.

    Additive only. index.html is never edited for the app's benefit; everything here either
    fills a hole a WKWebView has (no Web Share API) or protects data the webview can lose. */
(function () {
  var KEY = 'bitacora.v2';

  function toNative(msg) {
    try { webkit.messageHandlers.bitacora.postMessage(msg); return true; }
    catch (e) { return false; }           // running in a plain browser: everything below no-ops
  }

  /* ── 1. Restore ────────────────────────────────────────────────────────────────────────
     Native injected window.__BITACORA_VAULT__ at document-start. The rule is NEWEST VALID
     WINS, and — the part that matters — a local copy that will not parse is QUARANTINED under
     its own key rather than overwritten, because the one thing worse than a corrupt library is
     a corrupt library we destroyed while replacing it. */
  try {
    var v = window.__BITACORA_VAULT__ || null;
    var raw = null;
    try { raw = localStorage.getItem(KEY); } catch (e) { raw = null; }

    var localMod = -1;                     // -1 = nothing usable here (missing OR corrupt)
    if (raw != null) {
      try {
        var parsed = JSON.parse(raw);
        localMod = (parsed && typeof parsed.lastModified === 'number') ? parsed.lastModified : 0;
      } catch (e) {
        try { localStorage.setItem(KEY + '.corrupt.' + Date.now(), raw); } catch (e2) {}
        toNative({ cmd: 'log', text: 'local state failed to parse — quarantined, not overwritten' });
        localMod = -1;
      }
    }

    if (v && v.json) {
      var vaultMod = (typeof v.lastModified === 'number') ? v.lastModified : 0;
      if (localMod < 0 || vaultMod > localMod) {
        localStorage.setItem(KEY, v.json);
        toNative({ cmd: 'log', text: 'restored from vault (local=' + localMod + ' vault=' + vaultMod + ', ' + (v.items || '?') + ' items)' });
      }
    }
  } catch (e) {
    toNative({ cmd: 'log', text: 'restore threw: ' + e });
  }

  /* ── 2. Mirror every write to the vault ────────────────────────────────────────────────
     Hooked at the STORAGE boundary, not at the app's save(): persistState, the quota-prune
     retry, the gist pull and the importer all end at this one call, so one patch catches
     every path and none of it depends on an app symbol staying named what it is today. */
  try {
    var proto = Object.getPrototypeOf(localStorage) || window.Storage.prototype;
    var orig = proto.setItem;
    proto.setItem = function (k, val) {
      var r = orig.apply(this, arguments);
      if (k === KEY) toNative({ cmd: 'save', json: String(val) });
      return r;
    };
  } catch (e) {
    toNative({ cmd: 'log', text: 'could not hook setItem: ' + e });
  }

  /* ── 3. navigator.share ────────────────────────────────────────────────────────────────
     WKWebView does not implement the Web Share API, so index.html's share path would fall
     through to its clipboard branch — the app would be WORSE at sharing than the web page it
     replaces, on the one thing a phone is actually better at. This shim hands the payload to
     a real UIActivityViewController and resolves/rejects like the standard API, so the app's
     existing `if (navigator.share)` branch just starts working. */
  if (!navigator.share) {
    var seq = 0, pending = {};
    window.__bitacoraShareResult = function (id, ok, why) {
      var p = pending[id]; if (!p) return;
      delete pending[id];
      if (ok) p.resolve();
      else p.reject(new DOMException(why || 'share dismissed', 'AbortError'));
    };
    try {
      navigator.share = function (data) {
        return new Promise(function (resolve, reject) {
          var id = ++seq;
          pending[id] = { resolve: resolve, reject: reject };
          if (!toNative({ cmd: 'share', id: id, title: (data && data.title) || '', text: (data && data.text) || '', url: (data && data.url) || '' })) {
            delete pending[id];
            reject(new DOMException('no native bridge', 'AbortError'));
          }
        });
      };
    } catch (e) {}
  }
})();
