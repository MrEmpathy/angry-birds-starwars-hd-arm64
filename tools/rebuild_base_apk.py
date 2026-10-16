#!/usr/bin/env python3
"""Rebuild an original-equivalent (unsigned) base APK from a bridge-packaged APK plus the 32-bit libs.

The packaged APK keeps every original entry except the old signature and lib/; this restores
lib/armeabi-v7a and lib/x86 from copies of the original libraries so the packaging tools have
their usual input again.
"""
import hashlib
import pathlib
import sys
import zipfile

SIGNING = (".SF", ".RSA", ".DSA", ".EC")


def main():
    packaged, libdir, out = sys.argv[1], pathlib.Path(sys.argv[2]), pathlib.Path(sys.argv[3])
    arm = (libdir / "armeabi-v7a" / "libAngryBirdsStarWars.so").read_bytes()
    with zipfile.ZipFile(packaged) as src:
        guest = next(n for n in src.namelist() if n.startswith("lib/") and n.endswith("/libabsw_arm32.so"))
        shipped = src.read(guest)
        if hashlib.sha256(shipped).digest() != hashlib.sha256(arm).digest():
            sys.exit("ARM library copy differs from the one inside the packaged APK")
        out.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(out, "w") as dst:
            for info in src.infolist():
                name = info.filename
                base = name.rsplit("/", 1)[-1].upper()
                if name.startswith("lib/") or (name.startswith("META-INF/") and
                                               (base == "MANIFEST.MF" or base.endswith(SIGNING))):
                    continue
                dst.writestr(info, src.read(info), compress_type=info.compress_type)
            for abi in ("armeabi-v7a", "x86"):
                for lib in sorted((libdir / abi).glob("*.so")):
                    dst.write(lib, f"lib/{abi}/{lib.name}", compress_type=zipfile.ZIP_DEFLATED)
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
