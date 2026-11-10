from litex.build.generic_platform import Pins, IOStandard, Misc, Subsignal
from litex.build.gowin.platform import GowinPlatform

from gateware.platforms.toolchain import FPGBCAPiculaToolchain


_io = [
    ("clk40", 0, Pins("11"), IOStandard("LVCMOS33")),
    (
        "serial",
        0,
        Subsignal("rx", Pins("28")),
        Subsignal("tx", Pins("27")),
        IOStandard("LVCMOS33"),
    ),
]

# FPGA package pins, not LCD connector contacts. Vector order: D0, D1, CLK.
# Board continuity and VCCIO measurements are recorded in docs/hardware.md.
DISPLAY_PINS = {
    "lp_p": (122, 124, 126), "lp_n": (123, 125, 128),
    "hs_p": (117, 115, 113), "hs_n": (116, 114, 112),
}
_display_io = [
    ("dsi", 0,
        Subsignal("lp_p", Pins(*map(str, DISPLAY_PINS["lp_p"])),
                  IOStandard("LVCMOS12"), Misc("PULL_MODE=NONE"), Misc("DRIVE=4")),
        Subsignal("lp_n", Pins(*map(str, DISPLAY_PINS["lp_n"])),
                  IOStandard("LVCMOS12"), Misc("PULL_MODE=NONE"), Misc("DRIVE=4")),
        Subsignal("hs_p", Pins(*map(str, DISPLAY_PINS["hs_p"])),
                  IOStandard("LVDS25"), Misc("PULL_MODE=NONE")),
        Subsignal("hs_n", Pins(*map(str, DISPLAY_PINS["hs_n"])),
                  IOStandard("LVDS25"), Misc("PULL_MODE=NONE")),
    ),
]


class Platform(GowinPlatform):
    default_clk_name = "clk40"
    default_clk_period = 1e9 / 40e6  # Periodo de 25ns / 40MHz

    def __init__(self, toolchain="apicula", with_display_pins=False):
        GowinPlatform.__init__(
            self,
            "GW2AR-LV18EQ144PC8/I7",
            _io,
            toolchain=toolchain,
            devicename="GW2AR-18C",
        )
        if with_display_pins:
            self.add_extension(_display_io)
        if toolchain == "apicula":
            self.toolchain = FPGBCAPiculaToolchain()
