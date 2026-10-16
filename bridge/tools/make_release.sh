#!/usr/bin/env bash
# Build the phone APK: arm64 bridge + Lua display patches, signed with the local keystore.
# Usage (Git Bash on Windows): make_release.sh [unlocked]
#   unlocked: also apply bridge/lua-unlocked (all content open, power-ups refilled on every launch)
#             and write dist/AngryBirdsStarWars-arm64-unlocked.apk instead of the stable APK.
set -euo pipefail
ROOT="/c/Users/nicox/Documents/absw-engine"
SDK="/c/Users/nicox/AppData/Local/Android/Sdk"
BASE="$ROOT/original/angry_birds_sw.apk"
OUT="$ROOT/dist/AngryBirdsStarWars-arm64.apk"
W="/mnt/c/Users/nicox/Documents/absw-engine"
LUA="$W/bridge/lua"
case "${1:-}" in
  "") ;;
  unlocked) OUT="$ROOT/dist/AngryBirdsStarWars-arm64-unlocked.apk"; LUA="$LUA $W/bridge/lua-unlocked" ;;
  *) echo "unknown variant: $1" >&2; exit 2 ;;
esac

wsl.exe -e bash -lc "cd /tmp && ABIS=arm64-v8a bash $W/bridge/tools/build.sh" > "$ROOT/dist/build.log" 2>&1 \
  || { grep -E "error|undefined|failed" "$ROOT/dist/build.log" | head -20; exit 1; }
grep -E "arm64-v8a:" "$ROOT/dist/build.log"
rm -rf "$ROOT/bridge/out/overlay"
wsl.exe -e bash -lc "python3 -I $W/bridge/tools/build_lua_patches.py $W/original/angry_birds_sw.apk $LUA $W/bridge/out/overlay"
python -I "$ROOT/bridge/tools/package_apk.py" "$(cygpath -w "$BASE")" "$(cygpath -w "$OUT")" \
  --bridge-out "$(cygpath -w "$ROOT/bridge/out")" --abi arm64-v8a --overlay "$(cygpath -w "$ROOT/bridge/out/overlay")" \
  --build-tools "$(cygpath -w "$SDK/build-tools/36.0.0")" --keystore "$(cygpath -w "$ROOT/keystore/absw-local.keystore")"
sha256sum "$OUT"
