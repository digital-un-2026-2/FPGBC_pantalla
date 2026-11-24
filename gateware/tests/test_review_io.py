"""Inyecciones sintéticas: prueban el auditor, no equivalen a pruebas eléctricas."""

import copy
from types import SimpleNamespace
import unittest

from gateware.tests.review_io import DEVICE, PINOUT, expected_bel, review


class ReviewIOTest(unittest.TestCase):
    def setUp(self):
        class Database:
            rows, cols = 55, 56
            packages = {DEVICE: ("eLQFP144P", "GW2AR-18C", "C8/I7")}
            pinout = {"GW2AR-18C": {"eLQFP144P": {}}}
            pin_bank = {}

            def __getitem__(self, position):
                return SimpleNamespace(bels={
                    "IOBA": SimpleNamespace(is_diff=True, is_true_lvds=True, is_diff_p=True),
                    "IOBB": SimpleNamespace(is_diff=True, is_true_lvds=True, is_diff_p=False),
                })

        self.db = Database()
        # No reutilizar los diccionarios de clase entre pruebas.
        self.db.pinout = copy.deepcopy(self.db.pinout)
        self.db.pin_bank = {}
        ports, cells = {}, {}
        bit = 10
        for port, pins in PINOUT.items():
            ports[port] = {"bits": []}
            for lane, pin in enumerate(pins):
                bit += 1
                hs = port.startswith("dsi_hs")
                clock = port in {"clk40", "global_rst_n"}
                polarity = "B" if hs and port.endswith("_n") else "A"
                pin_name = f"IOT{pin}{polarity}"
                self.db.pinout["GW2AR-18C"]["eLQFP144P"][str(pin)] = (pin_name, [])
                self.db.pin_bank[pin_name] = 7 if clock else (1 if hs else 0)
                bel, *_ = expected_bel(self.db, pin_name)
                attrs = {"NEXTPNR_BEL": bel}
                standard = "LVCMOS33" if clock else ("LVCMOS25" if hs else "LVCMOS12")
                attrs[f"&IO_TYPE={standard}"] = "1"
                if not clock:
                    attrs["&PULL_MODE=NONE"] = "1"
                if port == "global_rst_n":
                    attrs["&PULL_MODE=UP"] = "1"
                cells[f"{port}_{lane}"] = {
                    "type": "IBUF" if clock else ("IOBUF" if hs else "TBUF"),
                    "attributes": attrs,
                    "connections": {"I" if clock else ("IO" if hs else "O"): [bit], "OEN": [1]},
                    "parameters": (
                        {"NET_OEN": "VCC"}
                        if hs else {}
                    ),
                }
                ports[port]["bits"].append(bit)
        self.design = {"modules": {"top": {
            "ports": ports, "cells": cells,
            "netnames": {"$PACKER_VCC": {"bits": [1]}},
        }}}
        self.defaults = {"TBUF": {"DRIVE": "8", "SLEWRATE": "FAST"}}

    def run_review(self):
        return review(self.design, self.db, self.defaults, {})

    def test_reports_defaults_without_approving_board(self):
        report = self.run_review()
        self.assertFalse(report["errors"])
        self.assertFalse(report["ready_for_board"])
        self.assertEqual(len(report["pins"]), 14)
        self.assertEqual(len(report["warnings"]), 2)
        lp = next(row for row in report["pins"] if row["port"] == "dsi_lp_p")
        self.assertIsNone(lp["drive_declared_ma"])
        self.assertEqual(lp["packer_defaults_if_omitted"]["drive_ma"], "8")

    def test_rejects_wrong_pin(self):
        self.design["modules"]["top"]["cells"]["dsi_lp_p_0"]["attributes"]["NEXTPNR_BEL"] = "X0Y0/IOBA"
        self.assertTrue(self.run_review()["errors"])

    def test_rejects_reset_without_pullup(self):
        attrs = self.design["modules"]["top"]["cells"]["global_rst_n_0"]["attributes"]
        del attrs["&PULL_MODE=UP"]
        self.assertTrue(self.run_review()["errors"])

    def test_rejects_hs_enabled(self):
        self.design["modules"]["top"]["cells"]["dsi_hs_p_0"]["connections"]["OEN"] = [0]
        self.assertTrue(self.run_review()["errors"])

    def test_rejects_lp_3v3(self):
        attrs = self.design["modules"]["top"]["cells"]["dsi_lp_p_0"]["attributes"]
        del attrs["&IO_TYPE=LVCMOS12"]
        attrs["&IO_TYPE=LVCMOS33"] = "1"
        self.assertTrue(self.run_review()["errors"])

    def test_rejects_pullup(self):
        attrs = self.design["modules"]["top"]["cells"]["dsi_hs_n_0"]["attributes"]
        del attrs["&PULL_MODE=NONE"]
        attrs["&PULL_MODE=UP"] = "1"
        self.assertTrue(self.run_review()["errors"])

    def test_rejects_undocumented_drive(self):
        self.design["modules"]["top"]["cells"]["dsi_lp_p_0"]["attributes"]["&DRIVE=24"] = "1"
        self.assertTrue(self.run_review()["errors"])

    def test_rejects_missing_off_metadata(self):
        self.design["modules"]["top"]["cells"]["dsi_hs_n_0"]["parameters"] = {}
        self.assertTrue(self.run_review()["errors"])

    def test_rejects_differential_driver(self):
        self.design["modules"]["top"]["cells"]["dsi_hs_p_0"]["parameters"]["DIFF_TYPE"] = "TLVDS_TBUF"
        self.assertTrue(self.run_review()["errors"])


if __name__ == "__main__":
    unittest.main()
