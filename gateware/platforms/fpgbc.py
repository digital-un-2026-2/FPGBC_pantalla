from litex.build.generic_platform import Pins, IOStandard, Subsignal
from litex.build.gowin.platform import GowinPlatform


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


class Platform(GowinPlatform):
    default_clk_name = "clk40"
    default_clk_period = 1e9 / 40e6  # Periodo de 25ns / 40MHz

    def __init__(self, toolchain="apicula"):
        GowinPlatform.__init__(
            self,
            "GW2AR-LV18EQ144PC8/I7",
            _io,
            toolchain=toolchain,
            devicename="GW2AR-18C",
        )
