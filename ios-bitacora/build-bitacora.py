#!/usr/bin/env python3
"""Derives the app's web payload from ../index.html — NEVER hand-edited, NEVER a fork.

index.html stays the single source of truth for Bitácora (the PWA and the app run the SAME
engine). This script makes the four changes an offline, app-hosted copy needs, each one
anchored by an assert so a drift in index.html fails LOUDLY here instead of shipping a
subtly-broken bundle (the estate's KF-table pattern: derived artifacts get a drift gate,
not trust).

  1. Google Fonts <link>s removed        — an app with no network must not render in Times.
                                           Replaced by @font-face over BUNDLED ttf in phone.css.
  2. phone.css + phone-boot-pre.js       — injected into <head>.
  3. phone-boot-post.js                  — injected before </body>, after the app's own script.
  4. Service worker registration killed  — the bundle IS the cache. A SW under the app's custom
                                           scheme would add a second, staler copy of the app and
                                           resurrect the "bump CACHE_NAME or phones serve stale
                                           bytes" ritual inside a binary that ships whole.

Run:  python3 ios-bitacora/build-bitacora.py            # rebuild Resources/app/
      python3 ios-bitacora/build-bitacora.py --check    # nonzero if the bundle is stale
"""
import io, os, shutil, sys, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
SRC  = os.path.join(HERE, '..', 'index.html')   # --src overrides: resign.sh ships HEAD, not the tree
DEST = os.path.join(HERE, 'Resources', 'app')
FONT_SRC = os.path.join(HERE, 'Fonts')
SIDECARS = ['phone.css', 'phone-boot-pre.js', 'phone-boot-post.js']

GFONT_LINKS = (
    '<link rel="preconnect" href="https://fonts.googleapis.com">\n'
    '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n'
    '<link href="https://fonts.googleapis.com/css2?family=Instrument+Serif:ital@0;1'
    '&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">'
)
INJECT_HEAD = (
    '<!-- offline app build: fonts are bundled (phone.css @font-face), not fetched -->\n'
    '<script src="phone-boot-pre.js"></script>'
)
# The stylesheet goes LAST in <head>, after the app's own <style>. Injecting it where the font
# links were put it BEFORE that block, so every equal-specificity rule in phone.css silently
# lost the cascade — the rules looked present in the served bytes and did nothing.
INJECT_CSS = '<link rel="stylesheet" href="phone.css">\n</head>'
SW_GUARD = "if ('serviceWorker' in navigator) {"
SW_DEAD  = "if (false) {   /* app build: the bundle is the cache — see build-bitacora.py */"


def source_path():
    if '--src' in sys.argv:
        return sys.argv[sys.argv.index('--src') + 1]
    return SRC


def build():
    s = io.open(source_path(), encoding='utf-8').read()

    assert GFONT_LINKS in s, 'the Google Fonts <link> block moved — update build-bitacora.py'
    s = s.replace(GFONT_LINKS, INJECT_HEAD, 1)

    assert SW_GUARD in s, 'the service-worker registration guard moved — update build-bitacora.py'
    assert s.count(SW_GUARD) == 1, 'more than one SW guard — build-bitacora.py would kill the wrong one'
    s = s.replace(SW_GUARD, SW_DEAD, 1)

    assert '</head>' in s
    s = s.replace('</head>', INJECT_CSS, 1)

    assert '</body>' in s
    s = s.replace('</body>', '<script src="phone-boot-post.js"></script>\n</body>', 1)

    # Nothing may still reach for the network to render text.
    assert 'fonts.googleapis.com' not in s and 'fonts.gstatic.com' not in s, \
        'a Google Fonts reference survived the rewrite'
    return s


def files():
    """(published path -> bytes) for everything the app bundle serves."""
    out = {'index.html': build().encode('utf-8')}
    for f in SIDECARS:
        out[f] = io.open(os.path.join(HERE, f), 'rb').read()
    for f in sorted(os.listdir(FONT_SRC)):
        if f.endswith('.ttf'):
            out['fonts/' + f] = io.open(os.path.join(FONT_SRC, f), 'rb').read()
    return out


def main():
    want = files()
    if '--check' in sys.argv:
        stale = []
        for path, data in want.items():
            p = os.path.join(DEST, path)
            if not os.path.exists(p) or io.open(p, 'rb').read() != data:
                stale.append(path)
        if stale:
            raise SystemExit('bundle STALE (%s) — run: python3 ios-bitacora/build-bitacora.py'
                             % ', '.join(sorted(stale)))
        print('bundle current (%d files)' % len(want)); return
    if os.path.isdir(DEST):
        shutil.rmtree(DEST)          # a removed sidecar must not linger in the app
    for path, data in want.items():
        p = os.path.join(DEST, path)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        io.open(p, 'wb').write(data)
    total = sum(len(d) for d in want.values())
    print('bundle: %s (%d files, %.2f MB)' % (DEST, len(want), total / 1048576))
    print('  index.html sha1 %s' % hashlib.sha1(want['index.html']).hexdigest()[:12])


if __name__ == '__main__':
    main()
