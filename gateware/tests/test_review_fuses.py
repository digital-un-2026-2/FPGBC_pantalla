import unittest

from gateware.tests.review_fuses import validate_attributes, validate_input
from gateware.tests.review_io import PINOUT


class FuseReviewTest(unittest.TestCase):
    def setUp(self):
        self.pads = []
        for port, numbers in PINOUT.items():
            for pin in numbers:
                attrs = {
                    "IO_TYPE": "LVCMOS33", "DRIVE": "0",
                    "PULLMODE": "NONE", "LVDS_OUT": "OFF", "OPENDRAIN": "OFF",
                }
                if port.startswith("dsi_lp"):
                    attrs.update(IO_TYPE="LVCMOS12", DRIVE="8", BANK_VCCIO="1.2",
                                 SLEWRATE="FAST", ODMUX="TRIMUX", TO="SIG")
                elif port.startswith("dsi_hs"):
                    attrs.update(IO_TYPE="LVCMOS25", BANK_VCCIO="2.5", ODMUX_1="0")
                elif port == "global_rst_n":
                    attrs["PULLMODE"] = "UP"
                self.pads.append({"pin": pin, "port": port,
                                  "effective_attributes": attrs, "selected_fuses_present": True})

    def test_valid_attributes(self):
        self.assertEqual(validate_attributes(self.pads), [])

    def test_rejects_hs_driver_enabled(self):
        next(p for p in self.pads if p["port"] == "dsi_hs_p")["effective_attributes"]["ODMUX_1"] = "1"
        self.assertTrue(validate_attributes(self.pads))

    def test_rejects_wrong_bank_voltage(self):
        next(p for p in self.pads if p["port"] == "dsi_hs_p")["effective_attributes"]["BANK_VCCIO"] = "1.2"
        self.assertTrue(validate_attributes(self.pads))

    def test_rejects_pullup(self):
        next(p for p in self.pads if p["port"] == "dsi_lp_p")["effective_attributes"]["PULLMODE"] = "UP"
        self.assertTrue(validate_attributes(self.pads))

    def test_rejects_reset_without_pullup(self):
        next(p for p in self.pads if p["port"] == "global_rst_n")["effective_attributes"]["PULLMODE"] = "NONE"
        self.assertTrue(validate_attributes(self.pads))

    def test_rejects_missing_fuses(self):
        self.pads[-1]["selected_fuses_present"] = False
        self.assertTrue(validate_attributes(self.pads))

    def test_rejects_missing_pad(self):
        self.assertTrue(validate_attributes(self.pads[:-1]))

    def test_rejects_extra_port(self):
        design = {"modules": {"top": {"ports": {**dict.fromkeys(PINOUT), "extra": {}}, "cells": {}}}}
        with self.assertRaises(ValueError):
            validate_input(design)

    def test_rejects_unexpected_buffer(self):
        design = {"modules": {"top": {
            "ports": dict.fromkeys(PINOUT), "cells": {"bad": {"type": "OBUF"}},
        }}}
        with self.assertRaises(ValueError):
            validate_input(design)


if __name__ == "__main__":
    unittest.main()
