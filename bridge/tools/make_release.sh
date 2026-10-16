#!/usr/bin/env bash
# Build the phone APK: arm64 bridge + Lua display patches, signed with the local keystore.
# Usage (Git Bash on Windows): make_release.sh [unlocked|hd|hd-unlocked]
#   unlocked:    also apply bridge/lua-unlocked (all content open, power-ups refilled on every launch)
#                and write dist/AngryBirdsStarWars-arm64-unlocked.apk instead of the stable APK.
#   hd:          Angry Birds Star Wars HD from original/angry_birds_sw_hd.apk, unmodified scripts,
#                rendered at native resolution; writes dist/AngryBirdsStarWarsHD-arm64.apk.
#   hd-unlocked: hd plus bridge/lua-paid (paid episodes owned, power-ups and Falcons at 999; progress untouched);
#                writes dist/AngryBirdsStarWarsHD-arm64-unlocked.apk.
set -euo pipefail
ROOT="/c/Users/nicox/Documents/absw-engine"
SDK="/c/Users/nicox/AppData/Local/Android/Sdk"
BASE="$ROOT/original/angry_birds_sw.apk"
OUT="$ROOT/dist/AngryBirdsStarWars-arm64.apk"
W="/mnt/c/Users/nicox/Documents/absw-engine"
LUA="$W/bridge/lua"
EXTRA=()
mkdir -p "$ROOT/test-out"
case "${1:-}" in
  "") ;;
  unlocked) OUT="$ROOT/dist/AngryBirdsStarWars-arm64-unlocked.apk"; LUA="$LUA $W/bridge/lua-unlocked" ;;
  hd) BASE="$ROOT/original/angry_birds_sw_hd.apk"; OUT="$ROOT/dist/AngryBirdsStarWarsHD-arm64.apk"; LUA=""
      EXTRA=(--render-height 0) ;;
  hd-unlocked) BASE="$ROOT/original/angry_birds_sw_hd.apk"; OUT="$ROOT/dist/AngryBirdsStarWarsHD-arm64-unlocked.apk"
      LUA="$W/bridge/lua-paid"; EXTRA=(--render-height 0) ;;
  *) echo "unknown variant: $1" >&2; exit 2 ;;
esac

wsl.exe -e bash -lc "cd /tmp && ABIS=arm64-v8a bash $W/bridge/tools/build.sh" > "$ROOT/test-out/build.log" 2>&1 \
  || { grep -E "error|undefined|failed" "$ROOT/test-out/build.log" | head -20; exit 1; }
grep -E "arm64-v8a:" "$ROOT/test-out/build.log"
rm -rf "$ROOT/bridge/out/overlay"
mkdir -p "$ROOT/bridge/out/overlay"
if [ -n "$LUA" ]; then
  wsl.exe -e bash -lc "python3 -I $W/bridge/tools/build_lua_patches.py $W/original/$(basename "$BASE") $LUA $W/bridge/out/overlay"
fi
python -I "$ROOT/bridge/tools/package_apk.py" "$(cygpath -w "$BASE")" "$(cygpath -w "$OUT")" \
  --bridge-out "$(cygpath -w "$ROOT/bridge/out")" --abi arm64-v8a --overlay "$(cygpath -w "$ROOT/bridge/out/overlay")" \
  --build-tools "$(cygpath -w "$SDK/build-tools/36.0.0")" --keystore "$(cygpath -w "$ROOT/keystore/absw-local.keystore")" \
  "${EXTRA[@]}"
sha256sum "$OUT"
