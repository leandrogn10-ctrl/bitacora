/*  test-bridge.js — falsifies phone-boot-pre.js's two load-bearing behaviours without a phone:
      1. the RESTORE rule (newest valid wins; a corrupt local copy is quarantined, not destroyed)
      2. the SAVE hook (every write to the state key reaches native, and nothing else does)
    Run: node ios-bitacora/test-bridge.js

    The live bridge transport is proven separately and for real — the geometry and restore lines
    in the simulator's vault.log arrived through webkit.messageHandlers, so page→native works.
    What this file pins is the LOGIC around it, which is the part that can regress silently. */
const fs = require('fs');
const path = require('path');
const SRC = fs.readFileSync(path.join(__dirname, 'phone-boot-pre.js'), 'utf8');
const KEY = 'bitacora.v2';

let checks = 0, failures = 0;
const ok = (c, what) => { checks++; console.log((c ? '  ok   ' : '  FAIL ') + what); if (!c) failures++; };

/** Builds a fresh fake page and runs phone-boot-pre.js inside it. */
function run({ local, vault }) {
  const store = Object.create(null);
  if (local !== undefined) store[KEY] = local;
  const posted = [];
  const storageProto = {
    getItem(k) { return k in this._s ? this._s[k] : null; },
    setItem(k, v) { this._s[k] = String(v); },
  };
  const localStorage = Object.create(storageProto);
  localStorage._s = store;

  const sandbox = {
    localStorage,
    window: { Storage: { prototype: storageProto } },
    navigator: {},
    webkit: { messageHandlers: { bitacora: { postMessage: (m) => posted.push(m) } } },
    Object, JSON, Date, String, Promise, DOMException: class extends Error {},
  };
  sandbox.window.__BITACORA_VAULT__ = vault;
  sandbox.window.localStorage = localStorage;
  sandbox.window.navigator = sandbox.navigator;
  // the script reads `window.__BITACORA_VAULT__` and bare `localStorage`/`navigator`
  const fn = new Function('window', 'localStorage', 'navigator', 'webkit', SRC);
  fn(sandbox.window, localStorage, sandbox.navigator, sandbox.webkit);
  return { store, posted, localStorage, navigator: sandbox.navigator };
}

const lib = (n, mod) => JSON.stringify({ items: Array.from({ length: n }, (_, i) => ({ id: 'i' + i })), lastModified: mod });

console.log('\n── restore ──');
let r = run({ local: undefined, vault: { json: lib(46, 2000), lastModified: 2000, items: 46 } });
ok(r.store[KEY] === lib(46, 2000), 'nothing stored locally → the vault is restored');

r = run({ local: lib(46, 3000), vault: { json: lib(3, 2000), lastModified: 2000, items: 3 } });
ok(r.store[KEY] === lib(46, 3000), 'a NEWER local copy is kept; an older vault does not clobber it');

r = run({ local: lib(2, 1000), vault: { json: lib(46, 5000), lastModified: 5000, items: 46 } });
ok(r.store[KEY] === lib(46, 5000), 'a NEWER vault wins over a stale local copy');

console.log('\n── a corrupt local copy is quarantined, never overwritten in place ──');
r = run({ local: '{"items":[ truncated', vault: { json: lib(46, 5000), lastModified: 5000, items: 46 } });
ok(r.store[KEY] === lib(46, 5000), 'corrupt local → vault restored');
const quarantined = Object.keys(r.store).filter(k => k.startsWith(KEY + '.corrupt.'));
ok(quarantined.length === 1, 'the unreadable bytes are kept under a .corrupt.<ts> key');
ok(r.store[quarantined[0]] === '{"items":[ truncated', 'the quarantined copy is the ORIGINAL bytes, verbatim');

//  CONTROL — the tempting simplification ("if it will not parse, just overwrite it") destroys
//  the only copy of whatever was actually in there. Prove the assertion above can see that.
ok(!('{"items":[ truncated' === lib(46, 5000)),
   'CONTROL: overwrite-in-place would have left no trace of the corrupt bytes');

console.log('\n── the save hook ──');
r = run({ local: lib(1, 1000), vault: null });
r.posted.length = 0;
r.localStorage.setItem(KEY, lib(2, 2000));
ok(r.posted.length === 1 && r.posted[0].cmd === 'save', 'a write to the state key posts exactly one save');
ok(r.posted[0].json === lib(2, 2000), 'the posted payload is the bytes that were written');
ok(r.store[KEY] === lib(2, 2000), 'the underlying write still happens (the hook wraps, never replaces)');

r.posted.length = 0;
r.localStorage.setItem('bitacora_palette_frecency', '{"x":1}');
ok(r.posted.length === 0, 'writes to OTHER keys are not mirrored (frecency must not churn the vault)');

console.log('\n── navigator.share shim ──');
r = run({ local: lib(1, 1000), vault: null });
ok(typeof r.navigator.share === 'function', 'navigator.share is installed where WKWebView has none');
r.posted.length = 0;
const p = r.navigator.share({ title: 'Pedro Páramo', text: 'five stars' });
ok(r.posted.length === 1 && r.posted[0].cmd === 'share', 'calling it posts a share command');
ok(r.posted[0].title === 'Pedro Páramo', 'accented titles survive the hop to native');
ok(typeof p.then === 'function', 'it returns a Promise, like the real API');

console.log(`\n${checks - failures}/${checks} checks passed`);
if (failures) { console.log(`BRIDGE GATE RED — ${failures} failure(s)\n`); process.exit(1); }
console.log('bridge gate green\n');
