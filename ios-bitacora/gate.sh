#!/bin/bash
# The whole gate for the iOS app, in one place. This file is the ONLY enumeration of it — no
# other doc restates the list, because that copy goes stale and then lies with authority.
# Run: bash ios-bitacora/gate.sh
set -u
cd "$(dirname "$0")" || exit 1
RED=0
step() { printf '\n\033[1m── %s\033[0m\n' "$1"; }
fail() { echo "   ✗ $1"; RED=1; }

step "vault rule (Swift, pure Foundation — no simulator, no signing)"
swiftc -o /tmp/vaultgate Vault.swift test-vault.swift 2>/dev/null && /tmp/vaultgate || fail "vault gate"

step "bridge logic (restore rule, save hook, share shim)"
node test-bridge.js || fail "bridge gate"

step "web payload is current with ../index.html"
python3 build-bitacora.py --check || fail "bundle is stale — run: python3 ios-bitacora/build-bitacora.py"

step "the app compiles for a device SDK"
xcodebuild -project Bitacora.xcodeproj -scheme Bitacora -sdk iphonesimulator -configuration Debug \
  -derivedDataPath /tmp/bitacora-gate CODE_SIGNING_ALLOWED=NO build >/tmp/bitacora-gate.log 2>&1 \
  && echo "  ok   build succeeded" || fail "xcodebuild (see /tmp/bitacora-gate.log)"

step "the served bytes really carry the app-only rewrites"
cd Resources/app || exit 1
export LC_ALL=C
[ "$(grep -c 'fonts.googleapis\|fonts.gstatic' index.html)" = "0" ] \
  && echo "  ok   no Google Fonts reference survives" || fail "a Google Fonts link survived — the app would render in Times offline"
grep -F -q "if ('serviceWorker' in navigator) {" index.html \
  && fail "the service worker registration is still live in the app build" \
  || echo "  ok   service worker registration is dead in the app build"
# The stylesheet must come AFTER the app's own <style>, or every equal-specificity rule in it
# silently loses the cascade while reading as perfectly present in the file.
S=$(grep -n '</style>' index.html | tail -1 | cut -d: -f1)
P=$(grep -n 'href="phone.css"' index.html | tail -1 | cut -d: -f1)
[ -n "$S" ] && [ -n "$P" ] && [ "$P" -gt "$S" ] \
  && echo "  ok   phone.css is injected after the app's <style> (line $P > $S)" \
  || fail "phone.css is NOT after the app's <style> — its rules will not win"
cd ../..

echo
[ $RED -eq 0 ] && echo "GATE GREEN" || { echo "GATE RED"; exit 1; }
