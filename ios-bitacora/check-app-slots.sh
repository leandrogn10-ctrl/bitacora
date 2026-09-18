#!/bin/bash
# What is actually installed under the free personal team, before Bitácora takes a slot.
# A free Apple ID can carry only a few side-loaded apps at once, and the number in our docs was
# written in August and never re-checked — so this ASKS the phone rather than trusting the doc.
# The phone must be UNLOCKED and awake: `device info apps` fails with CoreDeviceError 4016 on a
# locked phone, and that is "phone locked", NOT "no room" — different facts, and only one of them
# is about slots. Run: bash ios-bitacora/check-app-slots.sh
set -u
DEV="539AD729-8A96-5908-AC6E-06FA1B3BC522"
OUT=/tmp/bitacora-apps.json
if ! xcrun devicectl device info apps --device "$DEV" --json-output "$OUT" >/tmp/bitacora-apps.err 2>&1; then
  if grep -q "4016\|usage assertion" /tmp/bitacora-apps.err; then
    echo "PHONE LOCKED — unlock the iPhone, keep it awake, and run this again."
    echo "(This says nothing about how many app slots are free.)"
  else
    echo "COULD NOT ASK THE PHONE:"; cat /tmp/bitacora-apps.err
  fi
  exit 1
fi
python3 - "$OUT" <<'PY'
import json, sys
apps = json.load(open(sys.argv[1]))["result"]["apps"]
side = [a for a in apps if not a.get("appClip") and a.get("bundleIdentifier","").startswith(("com.leandro", "com.example"))]
print("Side-loaded apps signed by the personal team:")
for a in side:
    print("  %-34s %s" % (a.get("bundleIdentifier"), a.get("name", "")))
print("\ntotal side-loaded: %d" % len(side))
print("bitacora already installed: %s" % any(a.get("bundleIdentifier") == "com.leandro.bitacora" for a in side))
PY
