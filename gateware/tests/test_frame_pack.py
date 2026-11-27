from contextlib import ExitStack
from hashlib import sha256
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import unittest
from unittest.mock import patch

from apycula import bitmatrix
from phy.dphy_pads.tools import verify_route as review


class FrameSerializationTest(unittest.TestCase):
    def setUp(self):
        self.temp = TemporaryDirectory(dir="/tmp/opencode")
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / "frame.fs"
        self.bitmap = bitmatrix.zeros(2, 8)
        self.result = {"db": SimpleNamespace(cmd_hdr=[], cmd_ftr=[]),
                       "tilemap": {}, "extra_slots": {}}

    def run_serialization(self, readback=None):
        def write(path, *args):
            Path(path).write_bytes(b"serialized candidate")

        with ExitStack() as stack:
            stack.enter_context(patch.object(review.pack, "bsram_init_map", None))
            stack.enter_context(patch.object(review.pack.chipdb, "fuse_bitmap", return_value=self.bitmap))
            stack.enter_context(patch.object(review.pack, "header_footer"))
            stack.enter_context(patch.object(review.pack.bslib, "write_bitstream", side_effect=write))
            stack.enter_context(patch.object(review.pack.bslib, "read_bitstream",
                                            return_value=(self.bitmap if readback is None else readback,
                                                          [], [], {})))
            return review.serialize_checked(self.result, self.output)

    def test_roundtrip_publishes_candidate_and_hash(self):
        report = self.run_serialization()
        self.assertTrue(report["serialized_bitmap_roundtrip"])
        self.assertTrue(report["bitstream_written"])
        self.assertFalse(report["hardware_accessed"])
        self.assertEqual(report["bitstream_sha256"], sha256(self.output.read_bytes()).hexdigest())

    def test_changed_bit_is_not_published(self):
        different = bitmatrix.zeros(2, 8)
        different[0][0] = 1
        with self.assertRaisesRegex(ValueError, "no coincide"):
            self.run_serialization(different)
        self.assertFalse(self.output.exists())

    def test_changed_shape_is_not_published(self):
        with self.assertRaisesRegex(ValueError, "no coincide"):
            self.run_serialization(bitmatrix.zeros(1, 8))
        self.assertFalse(self.output.exists())

    def test_existing_bitstream_is_preserved(self):
        self.output.write_bytes(b"previous")
        with self.assertRaisesRegex(ValueError, "sobrescriben"):
            self.run_serialization()
        self.assertEqual(self.output.read_bytes(), b"previous")

    def test_existing_review_prevents_publication(self):
        self.output.with_suffix(".fs.review.json").write_text("previous")
        with self.assertRaisesRegex(ValueError, "sobrescriben"):
            self.run_serialization()
        self.assertFalse(self.output.exists())

    def test_bsram_is_rejected(self):
        with patch.object(review.pack, "bsram_init_map", object()):
            with self.assertRaisesRegex(ValueError, "BSRAM"):
                review.serialize_checked(self.result, self.output)
        self.assertFalse(self.output.exists())

    def test_incomplete_pad_audit_never_serializes(self):
        with patch.object(review, "serialize_checked") as serialize:
            with self.assertRaisesRegex(ValueError, "doce pads"):
                review.audit_fuses(Path("unused"), {}, {}, output=self.output)
        serialize.assert_not_called()


if __name__ == "__main__":
    unittest.main()
