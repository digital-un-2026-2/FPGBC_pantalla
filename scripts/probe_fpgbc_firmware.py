"""Offline, bounded probes of FPGBC update containers; never accesses hardware.

Usage (system Python with numpy and cryptography):
  python3 scripts/probe_fpgbc_firmware.py

All hypotheses and successful signature candidates are recorded under build/.
A signature candidate alone is NOT a verified decryption.
"""

from __future__ import annotations

import argparse
import binascii
import bz2
from collections import Counter
import hashlib
import itertools
import json
import lzma
from pathlib import Path
import struct
import zlib

import numpy as np
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.decrepit.ciphers.modes import CFB, CFB8, OFB


ROOT = Path(__file__).resolve().parents[1]
GW2_ID = bytes.fromhex("060000000000081b")
LIMIT = 1024 * 1024


def entropy(data: bytes | np.ndarray) -> float:
    a = np.frombuffer(data, dtype=np.uint8) if isinstance(data, bytes) else data
    counts = np.bincount(a, minlength=256)
    prob = counts[counts > 0] / len(a)
    return float(-np.sum(prob * np.log2(prob)))


def crc16(data: bytes, poly: int, initial: int, reflected: bool) -> int:
    table = []
    for i in range(256):
        r = i if reflected else i << 8
        for _ in range(8):
            if reflected:
                r = (r >> 1) ^ (poly if r & 1 else 0)
            else:
                r = ((r << 1) ^ (poly if r & 0x8000 else 0)) & 0xFFFF
        table.append(r)
    r = initial
    for value in data:
        if reflected:
            r = table[(r ^ value) & 255] ^ (r >> 8)
        else:
            r = table[((r >> 8) ^ value) & 255] ^ ((r << 8) & 0xFFFF)
    return r


def rc4_prefix(data: bytes, key: bytes, drop: int = 0) -> bytes:
    s = list(range(256))
    j = 0
    for i in range(256):
        j = (j + s[i] + key[i % len(key)]) & 255
        s[i], s[j] = s[j], s[i]
    i = j = 0
    result = bytearray()
    for n in range(drop + len(data)):
        i = (i + 1) & 255
        j = (j + s[i]) & 255
        s[i], s[j] = s[j], s[i]
        k = s[(s[i] + s[j]) & 255]
        if n >= drop:
            result.append(data[n - drop] ^ k)
    return bytes(result)


def candidate_keys(header: bytes) -> dict[bytes, str]:
    """Small metadata/default dictionary, not an exhaustive key search."""
    words = [header, b"FunnyPlaying", b"FUNNYPLAYING", b"funnyplaying",
             b"FUNNY_PLAY_", b"FP_GBC", b"FPGBC", b"GWGBC", b"GOWIN",
             b"CH32V203", b"0123456789abcdef", b"1234567890123456",
             b"1234567812345678", b"0123456789ABCDEF", b"12345678"]
    keys = {bytes(n): f"zero-{n}" for n in (16, 24, 32)}
    keys.update({bytes(range(n)): f"ascending-{n}" for n in (16, 24, 32)})
    keys.update({bytes([255]) * n: f"ff-{n}" for n in (16, 24, 32)})
    for word in words:
        for n in (16, 24, 32):
            keys[(word * ((n + len(word) - 1) // len(word)))[:n]] = (
                f"repeat-{word.decode()}-{n}")
            keys[word[:n].ljust(n, b"\0")] = f"null-pad-{word.decode()}-{n}"
        keys[hashlib.md5(word).digest()] = f"md5-{word.decode()}"
        keys[hashlib.sha256(word).digest()] = f"sha256-{word.decode()}"
    return keys


def checksum_probes(data: bytes) -> dict:
    specs = [("ARC", 0xA001, 0, True, 0),
             ("MODBUS", 0xA001, 65535, True, 0),
             ("USB", 0xA001, 65535, True, 65535),
             ("XMODEM", 0x1021, 0, False, 0),
             ("CCITT_FALSE", 0x1021, 65535, False, 0),
             ("X25", 0x8408, 65535, True, 65535),
             ("KERMIT", 0x8408, 0, True, 0),
             ("DNP", 0xA6BC, 0, True, 65535)]
    result = []
    for start in (0, 8, 24):
        body = data[start:-2]
        values = {name: crc16(body, poly, initial, ref) ^ xorout
                  for name, poly, initial, ref, xorout in specs}
        values.update(sum8=sum(body) & 255, sum16=sum(body) & 65535,
                      sum_words_le=sum(x[0] for x in struct.iter_unpack(
                          "<H", body[:len(body) // 2 * 2])) & 65535,
                      crc32_low=binascii.crc32(body) & 65535,
                      adler32_low=zlib.adler32(body) & 65535)
        for endian in ("little", "big"):
            target = int.from_bytes(data[-2:], endian)
            for name, value in values.items():
                if value == target:
                    result.append(dict(start=start, algorithm=name, endian=endian))
    return dict(trailer_hex=data[-2:].hex(), matches=result,
                caveat="The last two bytes may not be an unencrypted checksum.")


def compression_probes(data: bytes) -> dict:
    results = []
    attempts = 0
    for start in range(65):
        for name in ("zlib", "gzip", "raw_deflate", "xz", "lzma_alone", "bzip2"):
            attempts += 1
            try:
                if name in ("zlib", "gzip", "raw_deflate"):
                    obj = zlib.decompressobj({"zlib": 15, "gzip": 31,
                                              "raw_deflate": -15}[name])
                elif name in ("xz", "lzma_alone"):
                    obj = lzma.LZMADecompressor(
                        format=lzma.FORMAT_XZ if name == "xz" else lzma.FORMAT_ALONE,
                        memlimit=64 * 1024 * 1024)
                else:
                    obj = bz2.BZ2Decompressor()
                decoded = obj.decompress(data[start:], LIMIT)
                # Short raw-deflate coincidences in random bytes are not findings.
                if obj.eof and len(decoded) >= 4096:
                    results.append(dict(start=start, format=name, size=len(decoded),
                                        gw2_id_offset=decoded.find(GW2_ID)))
            except (zlib.error, lzma.LZMAError, OSError, EOFError, ValueError):
                pass
    return dict(attempts=attempts, complete_streams_at_least_4096_bytes=results,
                output_limit=LIMIT, maximum_start_offset=64)


def cipher_probes(data: bytes, out: Path) -> dict:
    keys = candidate_keys(data[:8])
    attempts = Counter()
    hits = []
    best_zero_fraction = (0.0, "")

    def inspect(decoded: bytes, label: str) -> None:
        nonlocal best_zero_fraction
        fraction = (decoded.count(0) + decoded.count(255)) / len(decoded)
        if fraction > best_zero_fraction[0]:
            best_zero_fraction = (fraction, label)
        off = decoded.find(GW2_ID)
        if off >= 0:
            candidate = out / f"candidate_{len(hits)}.prefix.bin"
            candidate.write_bytes(decoded)
            hits.append(dict(label=label, device_id_offset=off,
                             candidate_prefix=str(candidate), verified=False))

    reverse_bits = bytes(int(f"{n:08b}"[::-1], 2) for n in range(256))
    for offset in (8, 10, 16, 24, 26, 32):
        raw = data[offset:offset + 512]
        variants = {"original": raw, "bitreverse": raw.translate(reverse_bits),
                    "swap16": b"".join(raw[i:i+2][::-1] for i in range(0, len(raw), 2)),
                    "swap32": b"".join(raw[i:i+4][::-1] for i in range(0, len(raw), 4))}
        ivs = {bytes(16): "zero", data[:8] * 2: "magic-repeat",
               data[8:24]: "bytes8-23", data[16:32]: "bytes16-31"}
        for variant, sample in variants.items():
            for key, label in keys.items():
                for iv, ivlabel in ivs.items():
                    for mode_type in (modes.ECB, modes.CBC, CFB,
                                      CFB8, OFB, modes.CTR):
                        if mode_type is modes.ECB and ivlabel != "zero":
                            continue
                        mode = mode_type() if mode_type is modes.ECB else mode_type(iv)
                        dec = Cipher(algorithms.AES(key), mode).decryptor()
                        decoded = dec.update(sample) + dec.finalize()
                        attempts[f"AES-{mode_type.__name__}"] += 1
                        inspect(decoded, f"AES-{mode_type.__name__}/{label}/"
                                f"iv={ivlabel}/offset={offset}/{variant}")
            # RC4 probes use the source prefix only, with common drop lengths.
            if variant == "original":
                rc4keys = dict(keys)
                rc4keys[data[:8]] = "magic-raw"
                for key, label in rc4keys.items():
                    for drop in (0, 256, 768, 1536):
                        attempts["RC4"] += 1
                        inspect(rc4_prefix(sample, key, drop),
                                f"RC4/{label}/drop={drop}/offset={offset}")
    return dict(key_count=len(keys), keys={k.hex(): v for k, v in keys.items()},
                attempts=dict(attempts), signature_candidates=hits,
                best_zero_or_ff_fraction=best_zero_fraction,
                caveat="A finite guessed-key search; negative results do not exclude any cipher.")


def corpus_probes(paths: list[Path]) -> dict:
    files = []
    unique = {}
    for path in paths:
        data = path.read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        blocks = [data[i:i + 16] for i in range(8, len(data) - 15, 16)]
        files.append(dict(path=str(path.relative_to(ROOT)), size=len(data),
                          sha256=digest, magic_hex=data[:8].hex(),
                          payload_entropy=entropy(data[8:]),
                          repeated_aligned_16_byte_blocks=len(blocks) - len(set(blocks))))
        unique.setdefault(digest, (path, np.frombuffer(data[8:], dtype=np.uint8)))
    comparisons = []
    for (p, a), (q, b) in itertools.combinations(unique.values(), 2):
        if len(a) == len(b):
            x = a ^ b
            comparisons.append(dict(a=str(p.relative_to(ROOT)), b=str(q.relative_to(ROOT)),
                                    xor_entropy=entropy(x), equal_bytes=int(np.count_nonzero(x == 0))))
    comparisons.sort(key=lambda row: row["xor_entropy"])
    return dict(files=files, distinct_binaries=len(unique), comparisons=comparisons,
                caveat="High pairwise XOR entropy does not prove unique IVs or rule out all stream ciphers.")


def period_probes(data: bytes) -> dict:
    a = np.frombuffer(data[8:], dtype=np.uint8)
    results = []
    for lag in range(1, 4097):
        results.append((int(np.count_nonzero(a[lag:] == a[:-lag])) / (len(a)-lag), lag))
    results.sort(reverse=True)
    return dict(lags_tested=4096, largest_equality_fractions=[
        dict(lag=lag, equal_fraction=fraction) for fraction, lag in results[:20]],
        expected_random_fraction=1 / 256)


def verify_primitives() -> None:
    # Published algorithm check values, not a claim that FPGBC uses them.
    assert crc16(b"123456789", 0xA001, 0, True) == 0xBB3D
    assert crc16(b"123456789", 0x1021, 0xFFFF, False) == 0x29B1
    assert rc4_prefix(bytes(16), bytes.fromhex("0102030405")).hex() == (
        "b2396305f03dc027ccc3524a0a1118a8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path,
                        default=ROOT / "build/reverse_v1_4/original/update.bin")
    parser.add_argument("--output", type=Path,
                        default=ROOT / "build/reverse_v1_4/probes")
    args = parser.parse_args()
    verify_primitives()
    args.output.mkdir(parents=True, exist_ok=True)
    data = args.input.read_bytes()
    result = dict(input=str(args.input), sha256=hashlib.sha256(data).hexdigest(),
                  limitations=["No hardware access or native disassembly.",
                               "No verified plaintext recovered by this script."])
    stages = [("corpus", lambda: corpus_probes(sorted(
        (ROOT / "build/reverse_v1_4/reference").glob("HW*/**/update.bin")))),
              ("checksum", lambda: checksum_probes(data)),
              ("compression", lambda: compression_probes(data)),
              ("periodicity", lambda: period_probes(data)),
              ("ciphers", lambda: cipher_probes(data, args.output))]
    for name, stage in stages:
        print(f"Running {name}", flush=True)
        result[name] = stage()
        (args.output / f"{name}.json").write_text(json.dumps(result[name], indent=2) + "\n")
    (args.output / "report.json").write_text(json.dumps(result, indent=2) + "\n")
    print(f"Saved {args.output / 'report.json'}", flush=True)


if __name__ == "__main__":
    main()
