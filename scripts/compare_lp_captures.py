#!/usr/bin/env python3
"""Compare observed LP levels, including non-packet activity. Never modifies RTL."""

import argparse
from bisect import bisect_left, bisect_right
from collections import Counter
import json

from kvdat_lp import load_capture, pair_spans


def histogram(spans, rate):
    return dict(sorted(Counter(
        f"{state:02b}/{(end - start) * 1e9 / rate:.0f}ns"
        for start, end, state in spans
    ).items()))


def inspect(path):
    meta, channels = load_capture(path)
    rate = meta["sample_rate_hz"]
    spans = pair_spans(channels, 0, 1, meta["samples"])
    packets, escapes = [], []
    for i in range(len(spans) - 4):
        if [s[2] for s in spans[i:i + 5]] != [3, 2, 0, 1, 0]:
            continue
        j = i + 5
        while j < len(spans) and spans[j][2] != 3:
            j += 1
        if j == len(spans):
            raise ValueError(f"{path}: escape without return to LP11")
        burst = spans[i + 1:j]
        # Expected observed grammar: data/space, followed by one exit mark.
        body = burst[4:-1]
        if len(body) % 2 or any(
            mark[2] not in (1, 2) or space[2] != 0
            for mark, space in zip(body[::2], body[1::2])
        ):
            raise ValueError(f"{path}: non-alternating escape at {burst[0][0]}")
        bits = [s[2] == 2 for s in body[::2]]
        if len(bits) % 8:
            raise ValueError(f"{path}: partial escape byte at {burst[0][0]}")
        data = bytes(sum(int(v) << k for k, v in enumerate(bits[a:a + 8]))
                     for a in range(0, len(bits), 8))
        entry = {
            "start_sample": burst[0][0], "end_sample": burst[-1][1],
            "start_ms": burst[0][0] * 1e3 / rate,
            "end_ms": burst[-1][1] * 1e3 / rate,
            "duration_us": (burst[-1][1] - burst[0][0]) * 1e6 / rate,
            "bytes_with_selector": data.hex(" "),
            "entry_ns": [(b - a) * 1e9 / rate for a, b, _ in burst[:4]],
            "tail_ns": [(b - a) * 1e9 / rate for a, b, _ in burst[-3:]],
            "_spans": burst,
        }
        escapes.append(entry)
        if data[:1] == b"\x87":
            packets.append(entry)
    if len(packets) != 18:
        raise ValueError(f"{path}: expected 18 LP packets, found {len(packets)}")
    first, last = packets[0]["start_sample"], packets[-1]["end_sample"]
    for a, b in zip(packets, packets[1:]):
        a["gap_after_us"] = (b["start_sample"] - a["end_sample"]) * 1e6 / rate
        between = [s for s in spans
                   if a["end_sample"] <= s[0] < b["start_sample"]]
        a["gap_only_lp11"] = all(s[2] == 3 for s in between)
    channel_report = {}
    for number, (initial, edges) in channels.items():
        lo, hi = bisect_left(edges, first), bisect_right(edges, last)
        channel_report[number] = {
            "initial": initial, "edges_total": len(edges),
            "edges_before_first_packet_ms": [t * 1e3 / rate for t in edges[:lo]],
            "edges_during_command_window": hi - lo,
            "edges_after_last_packet": len(edges) - hi,
            "first_edge_after_last_ms": edges[hi] * 1e3 / rate if hi < len(edges) else None,
            "final_level": initial ^ (len(edges) % 2),
        }
    preamble = {}
    for name, p, n in (("D0", 0, 1), ("D1", 2, 3), ("CLK", 4, 5)):
        if p not in channels or n not in channels:
            continue
        preamble[name] = [
            {"start_ms": a * 1e3 / rate, "end_ms": min(b, first) * 1e3 / rate,
             "state": f"{state:02b}", "duration_ns": (min(b, first) - a) * 1e9 / rate}
            for a, b, state in pair_spans(channels, p, n, meta["samples"])
            if a < first
        ]
    return {
        "file": str(path), "metadata": meta, "channels": channel_report,
        "preamble_all_pair_spans": preamble,
        "non_packet_escapes": [e for e in escapes if e not in packets],
        "packets": packets,
        "body_histogram": histogram(
            [s for p in packets for s in p["_spans"][4:-3]], rate),
        "entry_histogram": histogram(
            [s for p in packets for s in p["_spans"][:4]], rate),
        "tail_histogram": histogram(
            [s for p in packets for s in p["_spans"][-3:]], rate),
    }


def compare(actual, reference):
    r = actual["metadata"]["sample_rate_hz"]
    rr = reference["metadata"]["sample_rate_hz"]
    result = []
    a0 = actual["packets"][0]["start_sample"] / r
    b0 = reference["packets"][0]["start_sample"] / rr
    for step, (a, b) in enumerate(zip(actual["packets"], reference["packets"])):
        sa, sb = a["_spans"], b["_spans"]
        result.append({
            "step": step,
            "same_bytes": a["bytes_with_selector"] == b["bytes_with_selector"],
            "same_entire_burst_state_order": [s[2] for s in sa] == [s[2] for s in sb],
            "actual_duration_us": a["duration_us"],
            "reference_duration_us": b["duration_us"],
            "relative_start_error_us": (
                (a["start_sample"] / r - a0) - (b["start_sample"] / rr - b0)) * 1e6,
            "gap_error_us": (
                a["gap_after_us"] - b["gap_after_us"]) if "gap_after_us" in a else None,
        })
    return {"actual": actual["file"], "reference": reference["file"], "packets": result}


def public(value):
    if isinstance(value, dict):
        return {k: public(v) for k, v in value.items()
                if not isinstance(k, str) or not k.startswith("_")}
    if isinstance(value, list):
        return [public(v) for v in value]
    return value


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("actual", nargs="?", default="LP_ITERATION_2.kvdat")
    parser.add_argument("references", nargs="*",
                        default=["MIPI_DSI.kvdat", "LP_MIPI_DSI_NEW.kvdat"])
    args = parser.parse_args()
    actual = inspect(args.actual)
    refs = [inspect(path) for path in args.references]
    print(json.dumps(public({
        "captures": [actual, *refs],
        "comparisons": [compare(actual, ref) for ref in refs],
        "note": "Observed digital thresholds, not analog levels or HS payload.",
    }), indent=2))
