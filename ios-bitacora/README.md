# Bitácora — the logbook, as a real app on the phone

A native iOS app (`com.leandro.bitacora`) that carries **the whole of Bitácora**, free-signed, with a
nightly re-sign so it never costs the $99. Same idea as El Quiosco; different world, different shape.

`../index.html` stays the single source of truth. The app does not fork it, does not reimplement it,
and does not lag it: `build-bitacora.py` DERIVES the app's payload from it, and every derivation is
anchored by an assert that fails loudly if `index.html` moves. Ship a feature to the web app and it is
in the phone app the next time the payload is rebuilt.

## What is native, and why only this
The engine runs in a WKWebView. Everything else was written because a web page **cannot** do it:

- **The vault** (`Vault.swift`) — the library lives in one localStorage key, which is a fine place to
  read from and a terrible only copy when the app is reinstalled nightly. See below; this is the part
  that matters.
- **A stable origin** — served from `bitacora-app://local/…` through a scheme handler, not `file://`
  and not a localhost server. The origin is the key the data is filed under: `file://` is the odd
  child of every WebKit storage migration, and a port number in the origin means a changed port is an
  erased library.
- **`navigator.share`** — WKWebView ships no Web Share API, so the app's existing share path would
  have fallen through to its clipboard branch. Shimmed onto a real `UIActivityViewController`, so the
  app is better at sharing than the page, not worse.
- **Haptics** — with the browser tap-highlight removed, a control has no feedback at all. Weighted the
  way iOS does: a tick for picking, a thud for committing, the success pattern only for a real write.
- **Bundled fonts** — the PWA fetches Instrument Serif and JetBrains Mono from Google. An app that
  opens on a plane must not render in Times.
- **An icon, a launch screen, safe areas, a single-column shelf** — the phone shape.

## The vault — read this before touching anything near saving
The rule is **append-only and monotonic**, and it exists against a specific way of losing everything:
the app boots, the key is missing or will not parse, the app correctly initializes an EMPTY library,
saves it, and a naive backup records the empty state over the full one. Two components behaving
correctly, one irreversible loss, nothing anywhere reading as broken.

So: every offered state is archived to a time-stamped generation (history never refuses — no state is
lost in either direction), but the PRIMARY is replaced only by one that is newer and has not
collapsed. A stale or sharply-shrunken save is **held**: primary untouched, the state parked as
pending, a native alert raised. A held save is never silent — a silent refusal is the same fake pass
one layer down.

Belt and braces around it: `Documents/` is exposed to Files.app (`UIFileSharingEnabled`), so the
backup is reachable **even when the app will not launch** — which is exactly the state an expired
certificate produces. And `resign.sh` pulls the vault off the phone before each install, keeping 30
copies in `~/.leandro-os/bitacora-vault/`, so the Mac holds a history the phone cannot erase.

## The nightly re-sign
`resign.sh`, run by `com.leandro-os.bitacora-resign` at **03:40 and 13:10** — the same two times as El
Quiosco, on purpose: the failure mode is not "3am is the wrong hour", it is that one run gets exactly
one shot at catching the phone awake. The script is idempotent and only mints a profile under 3 days.

Things in it that look like details and are not:

- It ships **HEAD's `index.html`, never the working tree.** An unattended 3am install of a half-edited
  file is how one bad line of JS becomes a phone that boots to an empty library. Commit to ship; the
  log says so plainly when the tree differs.
- It **deletes the provisioning profile under 3 days left.** Xcode reuses a valid profile rather than
  minting a fresh one, so a nightly rebuild does not by itself extend the expiry — without this the
  app dies on schedule while the log prints `ok` every night.
- It reads the expiry **back out of the built app**, because a reused profile and a newly minted one
  look identical from the outside.
- The `ok · profile expires <ISO>Z` line is the **last statement**, after the install returns 0, so it
  pairs an expiry with an install that actually happened. `~/.leandro-os/quiosco-watch.py` parses it
  verbatim — the separator is U+00B7, and the trailing `Z` is not decoration.
- This tree lives under `~/Projects` deliberately: launchd's `/bin/bash` has no TCC grant for
  `~/Downloads`, which silently killed El Quiosco's agent for seven nights. Nothing here may read from
  Desktop / Documents / Downloads.

## Install (the manual steps, in order)
```bash
bash ios-bitacora/check-app-slots.sh     # 1. phone UNLOCKED — what's already installed?
bash ios-bitacora/setup-xcode.sh         # 2. builds the payload, generates Bitacora.xcodeproj
```
Then in Xcode: **Signing & Capabilities → Team = your Apple ID**, plug in the iPhone, press Run.
Once it has installed by hand at least once:
```bash
cp ios-bitacora/com.leandro-os.bitacora-resign.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.leandro-os.bitacora-resign.plist
launchctl print gui/$(id -u)/com.leandro-os.bitacora-resign   # verify in launchd's view, not the file
```

## The gate
`bash ios-bitacora/gate.sh` — **that script is the only enumeration of it.** Never restate the list
here; that copy goes stale and then lies with authority.

Both harnesses have been falsified (defect re-planted in the real source, gate went red, with the
fixture asserting the source actually changed). Re-falsify if you touch them.

## Verified, and not
**Verified in the simulator (iPhone 17 Pro, iOS 26.5), measured rather than eyeballed:**
full-screen layout; `standalone=false`, which is why the page's own safe-area rules never fire here
and phone.css applies them unconditionally; both bundled faces genuinely loaded (measured by
rendered width against an invented family — `document.fonts.check()` answers `true` for fonts that
do not exist, verified in this very webview); the vault restoring a 3-title library into a wiped
webview with accented titles intact, which is also the proof that the base64 hop decodes as UTF-8.

**Not verified, and honestly cannot be from here:** anything involving the real phone — the install,
the free-signing re-sign, a mint under launchd, whether an install works against a locked or sleeping
phone, and app-slot availability. The simulator proves origin and layout semantics; it cannot prove
the signing path.

**Known gap:** the in-app tap-through of a real save (FAB → fill → save → vault accept) was not driven
on a device, because simulator input was unavailable in the session that built this. The JS half and
the Swift half are each pinned by their own harness and the live bridge transport is proven by the
log lines arriving through `webkit.messageHandlers` — but the end-to-end tap has not been performed.
Do that first thing on the real phone.
