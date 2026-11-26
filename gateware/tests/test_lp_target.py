"""Pruebas de exportación y simulación. Nunca sintetizan ni cargan la FPGA."""

import shutil
import subprocess
import unittest

from gateware.cores.lp_init import ROOT, RTL_SOURCES
from gateware.platforms.fpgbc import Platform
from gateware.targets.fpgbc_lp_init import LPInitTarget


class LPTargetTest(unittest.TestCase):
    def export(self, active):
        directory = ROOT / "build" / "gateware_tests" / ("active" if active else "isolated")
        platform = Platform()
        top = LPInitTarget(platform, enable_lp=active, enable_backlight=active)
        platform.build(
            top, build_dir=str(directory), build_name="fpgbc_lp_init", run=False,
            timingstrict=True,
        )
        return directory

    def test_constraints(self):
        directory = self.export(True)
        cst = (directory / "fpgbc_lp_init.cst").read_text()
        self.assertIn('IO_LOC "global_rst_n" 120;', cst)
        self.assertIn('IO_PORT "global_rst_n" IO_TYPE=LVCMOS33 PULL_MODE=UP;', cst)
        for port, pin in (("backlight_en", 46), ("backlight_pwm", 47)):
            self.assertIn(f'IO_LOC "{port}" {pin};', cst)
            self.assertIn(f'IO_PORT "{port}" IO_TYPE=LVCMOS33 PULL_MODE=NONE;', cst)
        for polarity, pins in (("p", (122, 124, 126)), ("n", (123, 125, 128))):
            for lane, pin in enumerate(pins):
                self.assertIn(f'IO_LOC "dsi_lp_{polarity}[{lane}]" {pin};', cst)
                self.assertIn(
                    f'IO_PORT "dsi_lp_{polarity}[{lane}]" IO_TYPE=LVCMOS12 '
                    'PULL_MODE=NONE DRIVE=8 SLEW_RATE=FAST;',
                    cst,
                )
        for lane, pins in enumerate(("117,116", "115,114", "113,112")):
            self.assertIn(
                f'IO_PORT "dsi_hs_p[{lane}]" IO_TYPE=LVCMOS25 PULL_MODE=NONE;', cst,
            )
            p, n = pins.split(",")
            self.assertIn(f'IO_LOC "dsi_hs_p[{lane}]" {p};', cst)
            self.assertIn(f'IO_LOC "dsi_hs_n[{lane}]" {n};', cst)
            self.assertIn(
                f'IO_PORT "dsi_hs_n[{lane}]" IO_TYPE=LVCMOS25 PULL_MODE=NONE;', cst,
            )
        ys = (directory / "fpgbc_lp_init.ys").read_text()
        self.assertIn("-family gw2a", ys)
        self.assertNotIn("-noiopads", ys)
        script = (directory / "build_fpgbc_lp_init.sh").read_text()
        self.assertNotIn("--timing-allow-fail", script)
        self.assertIn("pack_lp_checked.py", script)
        self.assertNotIn("gowin_pack -d", script)
        self.assertEqual(len(RTL_SOURCES), len(set(RTL_SOURCES)))

    def simulate(self, active):
        if not shutil.which("iverilog") or not shutil.which("vvp"):
            self.skipTest("Se requieren iverilog y vvp")
        directory = self.export(active)
        if not active:
            self.assertNotIn("backlight_", (directory / "fpgbc_lp_init.cst").read_text())
        output = directory / "test.out"
        sources = [
            ROOT / "gateware/tests/lp_target_TB.v",
            ROOT / "gateware/tests/gowin_pad_models.v",
            directory / "fpgbc_lp_init.v",
            *(ROOT / path for path in RTL_SOURCES),
        ]
        defines = ["-DTEST_BACKLIGHT"] if active else []
        subprocess.run(
            ["iverilog", "-g2012", *defines, "-s", "lp_target_TB",
             f"-Plp_target_TB.ENABLE_LP={int(active)}", "-o", str(output),
             *map(str, sources)], check=True, timeout=30,
        )
        result = subprocess.run(
            ["vvp", str(output)], capture_output=True, text=True, timeout=240,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS:", result.stdout)
        print(result.stdout, end="")

    def test_isolated(self):
        self.simulate(False)

    def test_active(self):
        self.simulate(True)


if __name__ == "__main__":
    unittest.main()
