"""Reject board profiles that would silently build at an incompatible clock/size."""
from copy import deepcopy
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root))
from gateware.targets.display_board import load_hs_profile, timing_constraints


class BoardProfileTest(unittest.TestCase):
    def setUp(self):
        self.template = json.loads((root / "profiles" / "display_hs.template.json").read_text())

    def load(self, profile):
        with TemporaryDirectory() as directory:
            path = Path(directory) / "profile.json"
            path.write_text(json.dumps(profile))
            return load_hs_profile(path)

    def test_template_stays_disabled(self):
        parameters, _ = self.load(self.template)
        self.assertEqual(parameters["PROFILE_OK"], 0)
        self.assertEqual(parameters["TIMING_OK_TABLE"], 0)
        self.assertEqual(parameters["TARGET_OK_TABLE"], 0)
        self.assertEqual(parameters["LP_ONLY"], 0)

    def test_reject_incompatible_profiles(self):
        invalid = {
            "PLL_FBDIV": 4, "PLL_SDIV": 8, "PLL_ODIV": 2,
            "PLL_PHASE": "unknown", "SER_HWL": "yes", "J": -1,
            "WIDTH": 719, "BUFFER_WORDS": 1024, "MAP_BITS": 0,
            "N_EVENTS_TABLE": 2, "EVENT_TABLE": 1 << 66,
            "PROFILE_OK": "false", "TARGET_OK_TABLE": 1,
        }
        for name, value in invalid.items():
            with self.subTest(parameter=name):
                profile = deepcopy(self.template)
                profile["rtl_parameters"][name] = value
                with self.assertRaises(ValueError):
                    self.load(profile)

    def test_reject_unknown_fields(self):
        profile = deepcopy(self.template)
        profile["rtl_parameters"]["LP_ONLY"] = 1
        with self.assertRaises(ValueError):
            self.load(profile)

    def test_constraints_keep_half_cycles_and_bound_bus(self):
        lp_sdc = timing_constraints("lpdt", None)
        hs_sdc = timing_constraints("hs", self.template)
        self.assertIn("12.500", lp_sdc)
        self.assertIn("-multiply_by 4", hs_sdc)
        self.assertIn("held_command", hs_sdc)
        self.assertIn("held_response", hs_sdc)
        self.assertNotIn("set_false_path", hs_sdc)


if __name__ == "__main__":
    unittest.main()
