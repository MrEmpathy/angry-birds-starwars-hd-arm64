#!/usr/bin/env python3
"""Repackage the user's original APK with the ARM32 bridge for 64-bit-only devices.

The output keeps the original DEX/resources/assets, drops the old signature and the 32-bit
native folders, and adds lib/<abi>/libAngryBirdsStarWars.so (bridge) plus
lib/<abi>/libabsw_arm32.so (the original armeabi-v7a engine, loaded by the bridge).
"""
import argparse
import os
import pathlib
import subprocess
import sys
import zipfile

GUEST_SRC = "lib/armeabi-v7a/libAngryBirdsStarWars.so"
DROP_PREFIXES = ("lib/armeabi/", "lib/armeabi-v7a/", "lib/x86/", "lib/mips/")


def is_old_signature(name):
    if not name.startswith("META-INF/"):
        return False
    base = name.rsplit("/", 1)[-1].upper()
    return base == "MANIFEST.MF" or base.endswith((".SF", ".RSA", ".DSA", ".EC"))


def load_overlay(root):
    """Files under `root` keyed by their APK path (e.g. assets/data/scripts/...)."""
    if not root:
        return {}
    root = pathlib.Path(root)
    return {p.relative_to(root).as_posix(): p.read_bytes() for p in sorted(root.rglob("*")) if p.is_file()}


def build_unsigned(src_apk, bridge_out, abis, dst, overlay):
    with zipfile.ZipFile(src_apk) as src, zipfile.ZipFile(dst, "w") as out:
        guest = src.read(GUEST_SRC)
        pending = dict(overlay)
        for info in src.infolist():
            if is_old_signature(info.filename) or info.filename.startswith(DROP_PREFIXES):
                continue
            data = pending.pop(info.filename, None)
            out.writestr(info, src.read(info) if data is None else data, compress_type=info.compress_type)
        for name, data in pending.items():
            out.writestr(zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0)), data, compress_type=zipfile.ZIP_DEFLATED)
        for abi in abis:
            bridge = pathlib.Path(bridge_out, abi, "libAngryBirdsStarWars.so").read_bytes()
            out.writestr(zipfile.ZipInfo(f"lib/{abi}/libAngryBirdsStarWars.so", (2026, 1, 1, 0, 0, 0)), bridge,
                         compress_type=zipfile.ZIP_DEFLATED)
            out.writestr(zipfile.ZipInfo(f"lib/{abi}/libabsw_arm32.so", (2026, 1, 1, 0, 0, 0)), guest,
                         compress_type=zipfile.ZIP_DEFLATED)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("apk", help="original Angry Birds Star Wars APK")
    ap.add_argument("out", help="signed output APK")
    ap.add_argument("--bridge-out", required=True, help="bridge/out directory with <abi>/ builds")
    ap.add_argument("--abi", action="append", default=[], help="ABI to include (repeatable)")
    ap.add_argument("--build-tools", required=True, help="Android SDK build-tools directory")
    ap.add_argument("--keystore", required=True, help="local signing keystore (created if missing)")
    ap.add_argument("--overlay", help="directory whose files replace or add APK entries (e.g. Lua patches)")
    args = ap.parse_args()
    abis = args.abi or ["arm64-v8a"]

    out = pathlib.Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)
    unsigned = out.with_suffix(".unsigned.apk")
    aligned = out.with_suffix(".aligned.apk")
    build_unsigned(args.apk, args.bridge_out, abis, unsigned, load_overlay(args.overlay))

    bt = pathlib.Path(args.build_tools)
    exe = ".exe" if os.name == "nt" else ""
    bat = ".bat" if os.name == "nt" else ""
    subprocess.run([str(bt / f"zipalign{exe}"), "-f", "4", str(unsigned), str(aligned)], check=True)

    ks = pathlib.Path(args.keystore)
    if not ks.exists():
        ks.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["keytool", "-genkeypair", "-keystore", str(ks), "-alias", "absw", "-keyalg", "RSA",
                        "-keysize", "2048", "-validity", "10000", "-dname", "CN=absw local build",
                        "-storepass", "absw-local", "-keypass", "absw-local"], check=True)
    subprocess.run([str(bt / f"apksigner{bat}"), "sign", "--ks", str(ks), "--ks-pass", "pass:absw-local",
                    "--ks-key-alias", "absw", "--out", str(out), str(aligned)], check=True, shell=os.name == "nt")
    unsigned.unlink()
    aligned.unlink()
    print(f"wrote {out} ({out.stat().st_size} bytes) for {', '.join(abis)}")


if __name__ == "__main__":
    sys.exit(main())
