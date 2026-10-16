#!/usr/bin/env python3
"""Decode Angry Birds Star Wars (Android 1.5.13) protected assets from the user's own APK.

Asset container (observed in libAngryBirdsStarWars.so, GameLua decrypt path):
    AES-256-CBC, zero IV, PKCS#7 padding
    -> b"\\x89LZMA\\r\\n\\x1a\\n" + LZMA-alone stream (props, dict size, u64 size, data)
    -> or a 7-Zip archive (written as <name>.7z; extract it with 7-Zip)

No key ships with this tool. It is recovered from the x86 engine library inside the
supplied APK (byte-immediate stores that build it) and accepted only after it decrypts
a real asset; --key-hex overrides that search.

Requires: Python 3.9+, `cryptography`.
"""
from __future__ import annotations

import argparse
import collections
import lzma
import os
import pathlib
import sys
import zipfile

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

LZMA_MAGIC = b"\x89LZMA\r\n\x1a\n"
SEVENZIP_MAGIC = b"7z\xbc\xaf\x27\x1c"
ENGINE_LIB = "lib/x86/libAngryBirdsStarWars.so"
PROBE_ASSET = "assets/data/catalog.json"


def decrypt(key: bytes, data: bytes) -> bytes | None:
    """AES-CBC/zero-IV decrypt with PKCS#7 removal; None when the input is not a valid container."""
    if not data or len(data) % 16:
        return None
    dec = Cipher(algorithms.AES(key), modes.CBC(bytes(16))).decryptor()
    plain = dec.update(data) + dec.finalize()
    pad = plain[-1]
    if not 1 <= pad <= 16 or plain[-pad:] != bytes([pad]) * pad:
        return None
    return plain[:-pad]


def unwrap_lzma(blob: bytes) -> bytes:
    """Decode the magic-prefixed LZMA-alone payload and check the declared size."""
    stream = blob[len(LZMA_MAGIC):]
    declared = int.from_bytes(stream[5:13], "little")
    out = lzma.decompress(stream, format=lzma.FORMAT_ALONE)
    if declared != 0xFFFFFFFFFFFFFFFF and len(out) != declared:
        raise ValueError(f"LZMA size mismatch: declared {declared}, decoded {len(out)}")
    return out


def key_candidates(lib: bytes):
    """Yield 32-byte keys built by x86 `mov byte [r32(+disp8)], imm8` runs."""
    seen = set()
    for i in range(len(lib) - 4):
        # Anchor on the offset-1 store: C6 /0 with mod=01, disp8=1.
        if lib[i] != 0xC6 or lib[i + 1] & 0xF8 != 0x40 or lib[i + 1] == 0x44 or lib[i + 2] != 1:
            continue
        key = [None] * 32
        key[1] = lib[i + 3]
        for j in range(max(0, i - 24), i):  # offset-0 store: C6 /0, mod=00, plain register
            if lib[j] == 0xC6 and lib[j + 1] in (0, 1, 2, 3, 6, 7):
                key[0] = lib[j + 2]
        for j in range(i + 4, min(len(lib) - 4, i + 512)):
            if lib[j] == 0xC6 and lib[j + 1] & 0xF8 == 0x40 and lib[j + 1] != 0x44:
                off = lib[j + 2]
                if 2 <= off < 32 and key[off] is None:
                    key[off] = lib[j + 3]
            if None not in key:
                break
        if None not in key:
            k = bytes(key)
            if k not in seen:
                seen.add(k)
                yield k


def recover_key(apk: zipfile.ZipFile) -> bytes:
    probe = apk.read(PROBE_ASSET)
    try:
        lib = apk.read(ENGINE_LIB)
    except KeyError:
        sys.exit(f"{ENGINE_LIB} not in APK; pass --key-hex")
    for key in key_candidates(lib):
        plain = decrypt(key, probe)
        if plain and plain.startswith(LZMA_MAGIC):
            return key
    sys.exit("no key candidate decrypted the probe asset; pass --key-hex")


def safe_target(out_dir: pathlib.Path, name: str) -> pathlib.Path:
    target = (out_dir / name).resolve()
    if out_dir != target and out_dir not in target.parents:
        raise ValueError(f"entry escapes output directory: {name!r}")
    return target


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("apk", type=pathlib.Path)
    ap.add_argument("out_dir", type=pathlib.Path, help="new or empty directory for decoded assets")
    ap.add_argument("--key-hex", help="use this AES-256 key instead of recovering it")
    ap.add_argument("--copy-plain", action="store_true", help="also copy assets that are not protected")
    args = ap.parse_args()

    out_dir = args.out_dir.resolve()
    if out_dir.exists() and any(out_dir.iterdir()):
        sys.exit(f"output directory is not empty: {out_dir}")

    with zipfile.ZipFile(args.apk) as apk:
        key = bytes.fromhex(args.key_hex) if args.key_hex else recover_key(apk)
        stats = collections.Counter()
        kinds = collections.Counter()
        failures = []
        for info in apk.infolist():
            if info.is_dir() or not info.filename.startswith("assets/"):
                continue
            ext = info.filename.rsplit(".", 1)[-1] if "." in info.filename else ""
            data = apk.read(info)
            plain = decrypt(key, data)
            name = info.filename[len("assets/"):]
            try:
                # A valid PKCS#7 tail alone is a ~1/256 coincidence on plain files (seen on .mp3),
                # so a decrypted result counts only when it carries a known container signature.
                if plain is not None and plain.startswith(LZMA_MAGIC):
                    payload, state = unwrap_lzma(plain), "decrypted+lzma"
                elif plain is not None and plain.startswith(SEVENZIP_MAGIC):
                    payload, state, name = plain, "decrypted+7z", name + ".7z"
                elif data.startswith(LZMA_MAGIC):
                    payload, state = unwrap_lzma(data), "lzma"
                else:
                    payload, state = data, "plain"
            except (lzma.LZMAError, ValueError) as exc:
                failures.append((info.filename, str(exc)))
                stats[(ext, "failed")] += 1
                continue
            stats[(ext, state)] += 1
            if state == "plain" and not args.copy_plain:
                continue
            if state != "plain":
                kinds["lua-bytecode" if payload.startswith(b"\x1bLua") else
                      "7z-archive" if payload.startswith(SEVENZIP_MAGIC) else
                      "json" if payload.lstrip()[:1] in (b"{", b"[") else "other"] += 1
            target = safe_target(out_dir, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            with open(target, "xb") as fh:
                fh.write(payload)

    print(f"key source: {'--key-hex' if args.key_hex else ENGINE_LIB}")
    for (ext, state), n in sorted(stats.items()):
        print(f"  .{ext or '(none)':<6} {state:<15} {n}")
    print("decoded content:", dict(kinds))
    for name, err in failures:
        print(f"  FAILED {name}: {err}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
