from pathlib import Path
import struct
import tempfile
import unittest

from compare_lp_captures import compare, inspect, public
from kvdat_lp import load_capture, pair_spans


def save_capture(path, samples, channels):
    raw = bytearray(
        b"<settings><devices><LA1010/></devices><chnVth>0.90</chnVth></settings>"
        b"kvdat\0\0\0"
    )
    raw.extend(struct.pack("<4Q", samples, 50_000_000, 0, len(channels)))
    for number, (initial, edges) in channels.items():
        timestamps = [*edges, samples]
        raw.extend(struct.pack("<4sBB2xQ", b"##D\0", number, initial, len(timestamps)))
        for timestamp in timestamps:
            raw.extend(timestamp.to_bytes(5, "little"))
    path.write_bytes(raw)


def save_initialization(path, gap=450_000, preamble=False):
    spans = [(3, 50)]
    if preamble:
        spans.extend([(2, 5), (0, 5), (1, 5), (0, 30), (2, 5), (3, 50)])
    wire = bytes.fromhex("87 29 02 00 00 B0 00 D6 CA")
    for _ in range(18):
        spans.extend([(2, 5), (0, 5), (1, 5), (0, 25)])
        for byte in wire:
            for bit in range(8):
                spans.extend([(2 if byte & (1 << bit) else 1, 5), (0, 5)])
        spans.extend([(2, 5), (3, gap)])
    channels = {number: (1, []) for number in range(6)}
    previous, elapsed = 3, 0
    for state, width in spans:
        for channel, mask in ((0, 2), (1, 1)):
            if (state ^ previous) & mask:
                channels[channel][1].append(elapsed)
        previous = state
        elapsed += width
    save_capture(path, elapsed, channels)


class LPCaptureTests(unittest.TestCase):
    def test_endpoint_is_not_an_edge(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.kvdat"
            save_capture(path, 100, {0: (1, [10, 20]), 1: (1, [])})
            metadata, channels = load_capture(path)
        self.assertEqual(metadata["samples"], 100)
        self.assertEqual(metadata["sample_rate_hz"], 50_000_000)
        self.assertEqual(metadata["device"], "LA1010")
        self.assertEqual(channels, {0: (1, [10, 20]), 1: (1, [])})

    def test_simultaneous_pair_edges_do_not_invent_intermediate_states(self):
        channels = {0: (1, [10, 20, 30]), 1: (1, [10])}
        self.assertEqual(
            pair_spans(channels, 0, 1, 40),
            [(0, 10, 3), (10, 20, 0), (20, 30, 2), (30, 40, 0)],
        )

    def test_rejects_truncated_transition_array(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.kvdat"
            save_capture(path, 100, {0: (1, [10])})
            path.write_bytes(path.read_bytes()[:-1])
            with self.assertRaisesRegex(ValueError, "Truncated"):
                load_capture(path)

    def test_rejects_non_monotonic_timestamps(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.kvdat"
            save_capture(path, 100, {0: (1, [20, 10])})
            with self.assertRaisesRegex(ValueError, "Non-monotonic"):
                load_capture(path)

    def test_compares_all_packets_and_measures_gap_differences(self):
        with tempfile.TemporaryDirectory() as directory:
            reference = Path(directory) / "reference.kvdat"
            actual = Path(directory) / "actual.kvdat"
            save_initialization(reference)
            save_initialization(actual, gap=450_010)
            observed = inspect(actual)
            result = compare(observed, inspect(reference))
        self.assertEqual(len(result["packets"]), 18)
        self.assertTrue(all(row["same_bytes"] for row in result["packets"]))
        self.assertTrue(all(row["same_entire_burst_state_order"] for row in result["packets"]))
        self.assertAlmostEqual(result["packets"][0]["gap_error_us"], 0.2)
        self.assertAlmostEqual(result["packets"][-1]["relative_start_error_us"], 3.4)
        self.assertEqual(observed["channels"][2]["edges_total"], 0)
        self.assertNotIn("_spans", public(observed)["packets"][0])

    def test_preserves_non_packet_escape_separately(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.kvdat"
            save_initialization(path, preamble=True)
            result = inspect(path)
        self.assertEqual(len(result["packets"]), 18)
        self.assertEqual(len(result["non_packet_escapes"]), 1)
        self.assertEqual(result["non_packet_escapes"][0]["bytes_with_selector"], "")

    def test_rejects_capture_without_eighteen_packets(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "sample.kvdat"
            save_capture(path, 100, {0: (1, []), 1: (1, [])})
            with self.assertRaisesRegex(ValueError, "expected 18 LP packets"):
                inspect(path)


if __name__ == "__main__":
    unittest.main()
