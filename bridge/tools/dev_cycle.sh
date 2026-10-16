#!/usr/bin/env bash
# Build (WSL) -> package -> install on the connected device/emulator -> launch -> filtered log.
# Usage: dev_cycle.sh [abi] [seconds]   (run from Git Bash on Windows)
set -euo pipefail
ABI="${1:-x86_64}"
WAIT="${2:-25}"
ROOT="/c/Users/nicox/Documents/absw-engine"
SDK="/c/Users/nicox/AppData/Local/Android/Sdk"
APK="$ROOT/test-out/absw-test-$ABI.apk"
PKG="com.rovio.angrybirdsstarwars.ads.iap"
mkdir -p "$ROOT/test-out"

if ! wsl.exe -e bash -lc "cd /tmp && ABIS=$ABI TRACE=${TRACE:-OFF} bash /mnt/c/Users/nicox/Documents/absw-engine/bridge/tools/build.sh" > "$ROOT/test-out/build.log" 2>&1; then
  grep -E "error|undefined|failed" "$ROOT/test-out/build.log" | head -20
  exit 1
fi
grep -E "bytes" "$ROOT/test-out/build.log"
rm -rf "$ROOT/bridge/out/overlay"
wsl.exe -e bash -lc "python3 -I /mnt/c/Users/nicox/Documents/absw-engine/bridge/tools/build_lua_patches.py \
  /mnt/c/Users/nicox/Documents/absw-engine/original/angry_birds_sw.apk /mnt/c/Users/nicox/Documents/absw-engine/bridge/lua \
  /mnt/c/Users/nicox/Documents/absw-engine/bridge/out/overlay" || exit 1
python -I "$ROOT/bridge/tools/package_apk.py" "$(cygpath -w "$ROOT/original/angry_birds_sw.apk")" "$(cygpath -w "$APK")" \
  --bridge-out "$(cygpath -w "$ROOT/bridge/out")" --abi "$ABI" --overlay "$(cygpath -w "$ROOT/bridge/out/overlay")" \
  --build-tools "$(cygpath -w "$SDK/build-tools/36.0.0")" \
  --keystore "$(cygpath -w "$ROOT/keystore/absw-local.keystore")" | tail -1
adb install -r "$(cygpath -w "$APK")" | tail -1
adb shell am force-stop "$PKG"
adb logcat -c
adb shell am start -n "$PKG/com.rovio.fusion.App" > /dev/null
sleep "$WAIT"
adb logcat -d -v brief > "$ROOT/test-out/last-run.log"
grep -E "absw|AndroidRuntime|F/libc|F/DEBUG.*(signal|#0[0-9]|Abort)|UnsatisfiedLink|E/rovio|Exception" "$ROOT/test-out/last-run.log" \
  | grep -vE "ConnectivityService|NetworkMonitor" | head -${LINES_MAX:-60}
