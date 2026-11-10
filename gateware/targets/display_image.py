"""Autonomous JDI LT031MDZ4000 color-bars image, physical FPGBC pads and UART CSR."""
import argparse
from contextlib import chdir
import hashlib
import json
from pathlib import Path

from litex.soc.integration.builder import Builder
from litex.soc.integration.soc_core import SoCMini

from dsi_display.image.generate_assets import generate
from gateware.cores.dsi_display import DSIDisplay
from gateware.platforms.fpgbc import DISPLAY_PINS, Platform
from gateware.targets.crg import CRG


class ImageSoC(SoCMini):
    def __init__(self, platform, phase="0100", latency=0, hwl="false", backlight_dcs=False):
        super().__init__(platform, clk_freq=40_000_000, csr_data_width=32,
                         ident="FPGBC JDI RGB888 image 720x720 60Hz")
        self.submodules.crg = CRG(platform)
        self.add_uartbone(name="uartbone", uart_name="serial", baudrate=115200)
        self.submodules.display = DSIDisplay(
            platform, pads=platform.request("dsi"), module_name="dsi_image_top", reset_initial=0,
            rtl_parameters={"J": latency, "PLL_PHASE": phase, "SER_HWL": hwl,
                            "BACKLIGHT_DCS": int(backlight_dcs)})
        self.csr.add("display")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true", help="Síntesis, P&R y bitstream sin programar")
    parser.add_argument("--toolchain", choices=("apicula", "gowin"), default="apicula")
    parser.add_argument("--phase", choices=[f"{n:04b}" for n in range(16)], default="0100")
    parser.add_argument("--latency", type=int, choices=range(6), default=0)
    parser.add_argument("--hwl", choices=("false", "true"), default="false")
    parser.add_argument("--backlight-dcs", action="store_true",
                        help="Ensayo de brillo DCS 51 FF 00 y control 53 24 después de display on")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if (root / "dsi_display/src/display_image_rom.v").read_text() != generate():
        parser.error("ROM desactualizada: ejecutar dsi_display/image/generate_assets.py")
    suffix = ("_backlight" if args.backlight_dcs else "") + ("_gowin" if args.toolchain == "gowin" else "")
    output = (args.output_dir or root / "build" / ("display_image" + suffix)).resolve()
    platform = Platform(toolchain=args.toolchain, with_display_pins=True)
    soc = ImageSoC(platform, args.phase, args.latency, args.hwl, args.backlight_dcs)
    # PCLK is 60MHz. Do not let the SoC's 40MHz reference lower that target.
    if args.toolchain == "apicula":
        platform.add_period_constraint(soc.display.byte_clk, 1e9/60_000_000)
    builder = Builder(soc, output_dir=str(output),
                      csr_csv=str(output / "csr.csv"), compile_software=False, compile_gateware=False)
    options = {"timingstrict": True} if args.toolchain == "apicula" else {}
    builder.build(build_name="display_image", **options)
    gateware = Path(builder.gateware_dir)
    phase = int(args.phase, 2)*22.5
    (gateware / "display_image.sdc").write_text(
        "create_clock -name sys40 -period 25.000 -waveform {0 12.5} [get_ports {clk40}]\n"
        "create_generated_clock -name image_byte -source [get_ports {clk40}] -multiply_by 3 -divide_by 2 [get_pins {*pll0/CLKOUTD}]\n"
        "create_generated_clock -name image_fast -source [get_ports {clk40}] -multiply_by 6 [get_pins {*pll0/CLKOUT}]\n"
        f"create_generated_clock -name image_clock_fast -source [get_ports {{clk40}}] -multiply_by 6 -phase {phase} [get_pins {{*pll0/CLKOUTP}}]\n"
        "# Stable mailbox data must arrive within one 60MHz byte cycle.\n"
        "set_max_delay -from [get_registers {*mailbox/held_command*}] -to [get_registers {*}] 16.667\n"
        "set_max_delay -from [get_registers {*mailbox/held_response*}] -to [get_registers {*mailbox/response*}] 16.667\n")
    if args.build:
        with chdir(gateware):
            platform.toolchain.run_script("build_display_image.sh")
    bitstream = gateware / "display_image.fs"
    (output / "image_manifest.json").write_text(json.dumps({
        "device": platform.device, "pins": DISPLAY_PINS,
        "image": "eight vertical RGB888 bars", "geometry": [720, 720],
        "raster_lines": 750, "line_hz": 45000, "frame_hz": 60,
        "reference_hz": 40000000, "byte_hz": 60000000, "lane_bitrate": 480000000,
        "pll_phase": args.phase, "serializer_latency": args.latency, "serializer_hwl": args.hwl,
        "autostart": True, "hs_enabled": True, "panel_verified_on_hardware": False,
        "backlight_dcs": args.backlight_dcs, "init_packets": 13 if args.backlight_dcs else 11,
        "backlight_gpio_assigned": False,
        "init_source": "https://github.com/jamwu/RPI-LCD-LT031MDZ4000/blob/main/panel-jdi-lt031mdz4000.c",
        "implementation_complete": args.build, "programmed": False,
        "bitstream_sha256": hashlib.sha256(bitstream.read_bytes()).hexdigest() if args.build else None,
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
