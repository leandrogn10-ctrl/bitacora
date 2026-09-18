#!/bin/bash
# Bitácora — the nightly re-sign. Free signing dies every 7 days; this rebuilds the app with a fresh
# personal-team profile and installs it over Wi-Fi to the paired phone, with Xcode closed.
# Run by launchd (com.leandro-os.bitacora-resign) at 03:40 and 13:10 — two shots at catching the
# phone awake, matching El Quiosco's schedule so the two apps never disagree about when that is.
# By hand: bash ~/Projects/bitacora/ios-bitacora/resign.sh
# Logs to ~/.leandro-os/bitacora-resign.log; failures go to the caja under src `bitacora`.
#
# WHY THIS TREE LIVES IN ~/Projects: launchd's /bin/bash had no TCC grant for ~/Downloads, so El
# Quiosco's agent exited 126 for seven nights WITHOUT opening its script — and its only alarm lived
# inside the file bash could not open, so the alarm was downstream of its own failure. ~/Projects is
# not a TCC-protected location. Nothing in this script may read from Desktop/Documents/Downloads.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
DEV="539AD729-8A96-5908-AC6E-06FA1B3BC522"   # devicectl identifier — what -destination/install take
UDID="00008140-00157464222B001C"              # hardware UDID — what the list TABLE prints
BUNDLE="com.leandro.bitacora"
DD="/tmp/bitacora-dev"
LOG="$HOME/.leandro-os/bitacora-resign.log"
APP="$DD/Build/Products/Debug-iphoneos/Bitacora.app"
say()  { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }
fail() { say "FAIL $*"; python3 -c "import sys;sys.path.insert(0,'$HOME/.leandro-os');from caja import caja;caja('bitacora.resign.fail',{'why':'''$*'''[:160]},'error')" 2>/dev/null; exit 1; }
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
say "start"

# Reachability. Match EITHER id: Xcode 27 (devicectl 642.16) flipped the Identifier column from the
# devicectl identifier to the hardware UDID, so a gate grepping only $DEV reads a reachable phone as
# unreachable. «available (paired)» is the table's word for reachable.
xcrun devicectl list devices 2>/dev/null | grep -E "$DEV|$UDID" | grep -q "available (paired)" \
  || fail "phone not reachable (not on this network, or asleep too long)"

# Ship a COMMITTED index.html, never the working tree. An unattended 3am install of a half-edited
# file is how one bad line of JS becomes a phone that boots to an empty library — and the vault is
# designed to hold that save, not to be immune to it. Committing is how you ship.
SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)" || fail "not a git repo: $REPO"
if ! git -C "$REPO" diff --quiet -- index.html 2>/dev/null; then
  say "note: index.html has uncommitted changes — shipping HEAD ($SHA), not the working tree"
fi
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git -C "$REPO" show HEAD:index.html > "$TMP/index.html" 2>/dev/null || fail "cannot read index.html at HEAD"
python3 "$HERE/build-bitacora.py" --src "$TMP/index.html" >>"$LOG" 2>&1 || fail "web bundle"

# Xcode REUSES a valid profile rather than minting a fresh one, so a nightly rebuild does NOT by
# itself extend the expiry. Under 3 days left, delete it so -allowProvisioningUpdates mints a new
# 7-day one — without this the app dies on schedule while this log prints "ok" every night.
PD="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
for f in "$PD"/*.mobileprovision; do
  [ -f "$f" ] || continue
  security cms -D -i "$f" 2>/dev/null | grep -q "$BUNDLE" || continue
  E=$(security cms -D -i "$f" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
  ES=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$E" +%s 2>/dev/null || echo 0)
  if [ $(( ES - $(date +%s) )) -lt $(( 3*86400 )) ]; then say "profile $E within 3 days → removing to force a fresh one"; rm -f "$f"; fi
done

cd "$HERE" || fail "cd"
if ! xcodebuild -project Bitacora.xcodeproj -scheme Bitacora -sdk iphoneos -configuration Debug \
     -derivedDataPath "$DD" -destination "id=$DEV" -allowProvisioningUpdates build >>"$LOG.build" 2>&1; then
  fail "xcodebuild (see $LOG.build)"
fi

# Pull the vault off the phone BEFORE replacing the app, so the Mac keeps a copy the phone cannot
# erase — and so a bad install is never the only thing standing between him and the library.
# Best-effort by design: a failed pull must not stop a re-sign, or an expiring cert would ride on
# a backup step. It gets its own event so a silently-never-pulling backup can still be noticed.
VDIR="$HOME/.leandro-os/bitacora-vault"; mkdir -p "$VDIR"
if xcrun devicectl device copy from --device "$DEV" --domain-type appDataContainer \
     --domain-identifier "$BUNDLE" --source Documents/bitacora-vault.json \
     --destination "$VDIR/vault-$(date +%Y%m%d-%H%M%S).json" >>"$LOG" 2>&1; then
  say "vault pulled to $VDIR"
  ls -1t "$VDIR"/vault-*.json 2>/dev/null | tail -n +31 | xargs -I{} rm -f {}   # keep 30
else
  say "note: vault pull failed (no vault yet on a first run, or the phone refused) — continuing"
  python3 -c "import sys;sys.path.insert(0,'$HOME/.leandro-os');from caja import caja;caja('bitacora.vault.pullfail',{},'warn')" 2>/dev/null
fi

xcrun devicectl device install app --device "$DEV" "$APP" >>"$LOG" 2>&1 || fail "install"

# The expiry is read back out of the BUILT app, not assumed from the build succeeding: Xcode
# reusing a valid profile and Xcode minting a new one look identical from the outside.
# This line is the LAST statement on purpose — it pairs an expiry with an install that happened.
# The watchdog parses it verbatim: "ok · profile expires <ISO>Z" with a U+00B7 middle dot.
EXP=$(security cms -D -i "$APP/embedded.mobileprovision" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null)
say "ok · profile expires $EXP"
