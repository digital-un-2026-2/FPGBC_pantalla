"""Lector del formato Kingst observado y reconstrucción de estados de pares LP."""

from collections import defaultdict
import hashlib
from itertools import pairwise
from pathlib import Path
import struct
import xml.etree.ElementTree as ET


def load_capture(path):
    raw = Path(path).read_bytes()
    offset = raw.index(b"kvdat\0\0\0")
    settings = ET.fromstring(raw[:offset])
    data = raw[offset:]
    samples, rate, trigger, slots = struct.unpack_from("<4Q", data, 8)
    channels = {}
    pos = 40
    while pos < len(data):
        if data[pos:pos + 4] != b"##D\0":
            raise ValueError(f"Unexpected channel header at binary offset {pos}")
        channel, initial = data[pos + 4:pos + 6]
        count = struct.unpack_from("<Q", data, pos + 8)[0]
        end = pos + 16 + count * 5
        if end > len(data):
            raise ValueError("Truncated transition array")
        timestamps = [
            int.from_bytes(data[i:i + 5], "little")
            for i in range(pos + 16, end, 5)
        ]
        # La última marca es fin de adquisición, no un flanco de la señal.
        if not timestamps or timestamps[-1] != samples:
            raise ValueError("Missing acquisition endpoint")
        if any(b < a for a, b in pairwise(timestamps)):
            raise ValueError("Non-monotonic timestamps")
        timestamps.pop()
        channels[channel] = (initial, timestamps)
        pos = end
    return {
        "sha256": hashlib.sha256(raw).hexdigest(),
        "samples": samples,
        "sample_rate_hz": rate,
        "trigger_sample": trigger,
        "channel_slots": slots,
        "device": next(iter(settings.find("devices"))).tag,
        "threshold_v": settings.findtext(".//chnVth"),
    }, channels


def pair_spans(channels, p, n, samples):
    events = defaultdict(int)
    state = channels[p][0] * 2 + channels[n][0]
    for channel, mask in ((p, 2), (n, 1)):
        for timestamp in channels[channel][1]:
            events[timestamp] ^= mask
    spans = []
    previous = 0
    for timestamp, mask in sorted(events.items()):
        if timestamp > previous:
            spans.append((previous, timestamp, state))
        state ^= mask
        previous = timestamp
    if previous < samples:
        spans.append((previous, samples, state))
    return spans
