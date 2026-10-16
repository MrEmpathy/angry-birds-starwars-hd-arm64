#!/usr/bin/env bash
# Drive the emulator from launch to Tatooine 1-1 and fire one bird; screenshots go to dist/.
# Usage: play_level1.sh <tag> [slowdown]   (slowdown multiplies the waits, e.g. 2 under native-bridge)
set -u
TAG="${1:-run}"
K="${2:-1}"
ROOT="/c/Users/nicox/Documents/absw-engine"
PKG="com.rovio.angrybirdsstarwars.ads.iap"
w() { sleep "$(( $1 * K ))"; }
adb shell am force-stop "$PKG"
adb logcat -c
adb shell am start -n "$PKG/com.rovio.fusion.App" > /dev/null
w 30
adb shell input tap 1672 500; w 2      # system "full screen" hint
adb shell input tap 1771 688; w 3      # old-target-SDK dialog
adb exec-out screencap -p > "$ROOT/dist/$TAG-menu.png"
adb shell input tap 1170 599; w 5      # Play
adb shell input tap 1182 585; w 5      # Tatooine
adb shell input tap 900 181; w 8       # level 1
for i in 1 2 3 4 5; do adb shell input tap 1900 900; w 2; done
w 6
adb exec-out screencap -p > "$ROOT/dist/$TAG-level.png"
adb shell input swipe 854 690 560 790 900
w 8
adb exec-out screencap -p > "$ROOT/dist/$TAG-shot.png"
echo "pid: $(adb shell pidof "$PKG")"
adb logcat -d -v brief > "$ROOT/dist/$TAG.log"
grep -E "F/libc|FATAL|E/Lua|W/absw|E/absw|F/Framework" "$ROOT/dist/$TAG.log" | tail -10
