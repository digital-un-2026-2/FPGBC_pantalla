"""Generate the display integration with UARTWishbone control, pads internal."""
import argparse
from pathlib import Path

from litex.soc.integration.builder import Builder
from litex.soc.integration.soc_core import SoCMini

from gateware.cores.dsi_display import DSIDisplay
from gateware.platforms.fpgbc import Platform
from gateware.targets.crg import CRG


class DisplaySoC(SoCMini):
    def __init__(self, platform):
        super().__init__(platform, clk_freq=40_000_000, csr_data_width=32, ident="FPGBC DSI integration")
        self.submodules.crg = CRG(platform)
        self.add_uartbone(name="uartbone", uart_name="serial", baudrate=115200)
        self.submodules.display = DSIDisplay(platform)
        self.csr.add("display")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true", help="Añadir síntesis e implementación, sin programar FPGA")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = root / "build" / "display"
    builder = Builder(DisplaySoC(Platform()), output_dir=str(output),
                      csr_csv=str(output / "csr.csv"), compile_software=False, compile_gateware=args.build)
    builder.build(build_name="display")


if __name__ == "__main__":
    main()
