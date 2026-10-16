# absw-engine

Personal tooling to run **Angry Birds Star Wars 1.5.13** (your own APK) on 64-bit-only Android phones
such as the Galaxy S26 Ultra, whose CPUs cannot execute the game's 32-bit ARM engine.

Nothing here contains Rovio code, assets or keys. The build reads them from your APK on your machine.
Do not distribute the generated APK, `decoded-assets/` or `keystore/`.

## How it works

`bridge/` builds a 64-bit `libAngryBirdsStarWars.so` that Java loads in place of the original. It:

1. Reserves a 4 GiB guest address space, where guest address A lives at host `base + A`.
2. Loads the original `armeabi-v7a` engine, shipped in the APK as `lib/arm64-v8a/libabsw_arm32.so`,
   plus a small ARM32 runtime (`bridge/guest/`: printf, setjmp, qsort, pthread_once).
3. Runs the engine with [dynarmic](https://github.com/Vita3K/dynarmic) (ARM32 → AArch64/x86-64 JIT),
   one JIT per host thread.
4. Services the engine's imports on the host (`src/hle_*.cpp`): libc, libm, pthread, stdio, GLES2,
   AAsset, log, with 32/64-bit struct conversion. Kernel "kuser helpers" are mapped at 0xffff0f60.
5. Gives the engine a synthetic 32-bit `JNIEnv`/`JavaVM` (`src/jni_bridge.cpp`) and registers
   trampolines for every Rovio `native` method found in the DEX (`natives.txt`).

Display adaptation (`src/display.cpp`) runs on the UI thread from the `nativeConfig` trampoline:

- The window draws under the camera cutout (`SHORT_EDGES`). Otherwise the window is narrower than
  `Display.getRealSize()`, which the game uses for layout.
- The game draws its 1280x800 UI sprites at native pixel size, so on 1440p screens the UI looks small.
  The GL surface is therefore fixed at 1080 px high and scaled up by the display hardware, and touch
  coordinates in `nativeInput` are scaled to match. `adb shell setprop debug.absw.render_height N`
  changes this height; `0` turns it off.

Lua display patches live in `bridge/lua/` as plain Lua source. The engine's Lua 5.1 includes its parser,
so it accepts source text. At packaging time, `tools/build_lua_patches.py`:

1. Packs each patch the way the game packs its scripts: LZMA, then AES-256-CBC, with the key recovered
   from your APK.
2. Keeps the original encrypted script as `<name>.orig.lua`.

Each patch loads its original with `loadLuaFileToObject` and then overrides the layout code that assumes
iPad screens:

- `menus/AnimatedTutorial.lua`: tutorials and story comics are scaled to fit the screen (the smaller of
  height/768 and width/950). Before, they used fixed x1.5/x2 steps based on screen width, so they
  overflowed on wide phones.
- `menus/EpisodeButton.lua`: the planet score panel keeps the phone font scale. Before, it applied the
  x0.4 iPad-Retina shrink to any screen at least 2000 px wide.

`bridge/tools/make_release.sh` builds the phone APK with these patches. The packaging tools read
`original/angry_birds_sw.apk`. If the original APK is lost, `tools/rebuild_base_apk.py` rebuilds an
equivalent copy from a packaged APK plus the original 32-bit libraries.

Behaviour that is compatible on purpose with Android 4.x bionic:

- `_ctype_` and `_tolower_tab_` are pointer variables.
- rwlocks can be re-entered by the thread that holds the write lock.
- A thread that joins itself is detached instead of failing.

## Build (WSL, user-space toolchain under `~/tools`)

```
bash tools/setup_toolchain.sh                      # NDK r27d, CMake, Ninja, Boost, dynarmic
ABIS=arm64-v8a bash bridge/tools/build.sh          # also: x86_64 for the emulator
python bridge/tools/package_apk.py <original.apk> dist/AngryBirdsStarWars-arm64.apk \
    --bridge-out bridge/out --abi arm64-v8a \
    --build-tools <sdk>/build-tools/36.0.0 --keystore keystore/absw-local.keystore
```

`bridge/tools/dev_cycle.sh` and `play_level1.sh` run the emulator loop: build, install, launch,
reach Tatooine 1-1, fire one bird and take screenshots.

## Debugging

Logs use the tags `absw` (bridge) and `absw-guest` (engine stdout). A guest fault prints the guest PC,
LR and stack candidates as `libAngryBirdsStarWars.so+offset (symbol+delta)`. Build with `TRACE=ON` to
log every import call.

## Verified (Android 36 x86_64 emulator, 64-bit only: `x86_64,arm64-v8a`)

- x86_64 build, running natively:
  - menu, planet and level selection, comic, Tatooine 1-1 gameplay with physics and score;
  - audio at 16 kHz with 0 underruns;
  - progress saved across restarts.
- arm64 build, running under the emulator's ARM translation:
  - the same flow up to "Level cleared". This covers function only, not speed.

Not verified: running on real arm64 hardware (performance, Samsung firmware), in-app purchases
(they fail because of the new signature), ads, camera.
