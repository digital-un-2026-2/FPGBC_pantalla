"""FPGBC EQ144 display pins, CSR control and reproducible board build (no load)."""
import argparse
from contextlib import chdir
import hashlib
import json
from pathlib import Path

from migen import Constant
from litex.soc.integration.builder import Builder
from litex.soc.integration.soc_core import SoCMini

from gateware.cores.dsi_display import DSIDisplay
from gateware.platforms.fpgbc import DISPLAY_PINS, Platform
from gateware.targets.crg import CRG


def load_hs_profile(path):
    """A single explicit panel schedule; no synthetic schedule is enabled by default."""
    data = json.loads(Path(path).read_text())
    if not isinstance(data, dict) or set(data) != {"description", "rtl_parameters"} or not isinstance(data["description"], str):
        raise ValueError("El perfil requiere description y rtl_parameters")
    values = data["rtl_parameters"]
    integers = {"WIDTH": (8, 65535), "HEIGHT": (1, 65535), "BUFFER_WORDS": (1, 32771),
                "J": (0, 16), "PLL_IDIV": (0, 63), "PLL_FBDIV": (0, 63),
                "PLL_ODIV": (2, 128), "PLL_SDIV": (4, 4), "E_MAX": (1, 65535),
                "N_EVENTS_TABLE": (0, 65535), "T_FRAME_TABLE": (0, 0xfffffffe),
                "EVENT_TABLE": (0, None), "MAP_BITS": (0, 0xffffff)}
    booleans = {"PROFILE_OK", "TIMING_OK_TABLE", "TARGET_OK_TABLE"}
    strings = {"PLL_PHASE", "SER_HWL"}
    if not isinstance(values, dict) or set(values) != set(integers) | booleans | strings:
        raise ValueError("Faltan parámetros del perfil HS o hay campos desconocidos")
    for name, (low, high) in integers.items():
        value = values[name]
        if type(value) is not int or value < low or (high is not None and value > high):
            raise ValueError(f"Valor inválido para {name}")
    for name in booleans:
        if type(values[name]) is not bool:
            raise ValueError(f"{name} debe ser booleano")
    if values["PLL_PHASE"] not in {f"{n:04b}" for n in range(16)} or values["SER_HWL"] not in ("true", "false"):
        raise ValueError("Fase PLL o SER_HWL inválidos")
    if values["PLL_ODIV"] not in (2, 4, 8, 16, 32, 48, 64, 80, 96, 112, 128):
        raise ValueError("PLL_ODIV no es un divisor rPLL válido")
    if values["WIDTH"] % 8 or 3*values["WIDTH"]+6 > 2*values["BUFFER_WORDS"] or 3*values["WIDTH"] > 65535:
        raise ValueError("Geometría incompatible con fuente/WC/buffer")
    if values["N_EVENTS_TABLE"] > values["E_MAX"] or values["EVENT_TABLE"].bit_length() > 66*values["E_MAX"]:
        raise ValueError("Tabla de eventos fuera de rango")
    if sorted((values["MAP_BITS"] >> (3*n)) & 7 for n in range(8)) != list(range(8)):
        raise ValueError("MAP_BITS debe ser una permutación de los ocho bits")
    # Current logical HS sequencer implements the fixed S320 phase timings.
    # Other bitrates need a corresponding new timing profile in dphy_hs_tx.
    if 40_000_000*(values["PLL_FBDIV"]+1) != 160_000_000*(values["PLL_IDIV"]+1):
        raise ValueError("El secuenciador actual requiere FCLK=160MHz y byte_clk=40MHz")
    vco = 160_000_000*values["PLL_ODIV"]
    if not 500_000_000 <= vco <= 1_250_000_000:
        raise ValueError("VCO fuera del rango del GW2AR C8/I7")
    result = {name: int(value) if name in booleans else value for name, value in values.items()}
    result["EVENT_TABLE"] = Constant(values["EVENT_TABLE"], 66*values["E_MAX"])
    result["LP_ONLY"] = 0
    return result, data


def timing_constraints(mode, profile):
    """Native Gowin SDC. Apicula uses --freq and infers PLL-generated clocks."""
    lines = [
        "# FPGBC: reference clock; negedge paths retain their half-cycle budget.",
        "create_clock -name sys40 -period 25.000 -waveform {0.000 12.500} [get_ports {clk40}]",
        "# No blanket false paths or multicycle exceptions.",
    ]
    if mode == "hs":
        phase = int(profile["rtl_parameters"]["PLL_PHASE"], 2)*22.5
        lines += [
            "# Match the sole rPLL instance; verify all three objects in the STA report.",
            "create_generated_clock -name dsi_fclk_d -source [get_ports {clk40}] -multiply_by 4 [get_pins {*pll0/CLKOUT}]",
            f"create_generated_clock -name dsi_fclk_c -source [get_ports {{clk40}}] -multiply_by 4 -phase {phase:.3f} [get_pins {{*pll0/CLKOUTP}}]",
            "create_generated_clock -name dsi_byte -source [get_ports {clk40}] -divide_by 1 [get_pins {*pll0/CLKOUTD}]",
            "# Bundled buses settle before synchronized request/ACK; bound data flight to one byte cycle.",
            "set_max_delay -from [get_registers {*mailbox/held_command*}] -to [get_registers {*core/*}] 25.000",
            "set_max_delay -from [get_registers {*mailbox/held_response*}] -to [get_registers {*mailbox/response*}] 25.000",
            "# Clock/data IO skew must be qualified against the actual panel; no guessed IO delays.",
        ]
    return "\n".join(lines) + "\n"


class DisplayBoardSoC(SoCMini):
    def __init__(self, platform, mode="parked", rtl_parameters=None):
        super().__init__(platform, clk_freq=40_000_000, csr_data_width=32,
                         ident=f"FPGBC display board {mode}")
        self.submodules.crg = CRG(platform)
        self.add_uartbone(name="uartbone", uart_name="serial", baudrate=115200)
        parameters = {"LP_ONLY": 1, "PROFILE_OK": int(mode == "lpdt")}
        if mode == "hs":
            if rtl_parameters is None:
                raise ValueError("El modo HS requiere un perfil explícito")
            parameters = rtl_parameters
        elif mode not in ("parked", "lpdt"):
            raise ValueError("Modo de placa desconocido")
        self.submodules.display = DSIDisplay(platform, pads=platform.request("dsi"), rtl_parameters=parameters)
        self.csr.add("display")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("parked", "lpdt", "hs"), default="parked")
    parser.add_argument("--profile", type=Path, help="Perfil JSON del panel/PHY; obligatorio en modo HS")
    parser.add_argument("--toolchain", choices=("apicula", "gowin"), default="apicula")
    parser.add_argument("--build", action="store_true", help="Síntesis, P&R y bitstream, sin programar FPGA")
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    if (args.mode == "hs") != (args.profile is not None):
        parser.error("--profile se requiere exclusivamente con --mode hs")
    parameters, profile = load_hs_profile(args.profile) if args.profile else (None, None)
    root = Path(__file__).resolve().parents[2]
    suffix = "_gowin" if args.toolchain == "gowin" else ""
    output = (args.output_dir or root / "build" / f"display_board_{args.mode}{suffix}").resolve()
    platform = Platform(toolchain=args.toolchain, with_display_pins=True)
    builder = Builder(DisplayBoardSoC(platform, args.mode, parameters), output_dir=str(output),
                      csr_csv=str(output / "csr.csv"), compile_software=False, compile_gateware=False)
    # No --timing-allow-fail: an implementation that misses timing is a failure.
    build_options = {"timingstrict": True} if args.toolchain == "apicula" else {}
    builder.build(build_name="display_board", **build_options)
    gateware = Path(builder.gateware_dir)
    (gateware / "display_board.sdc").write_text(timing_constraints(args.mode, profile))
    if args.build:
        with chdir(gateware):
            platform.toolchain.run_script("build_display_board.sh")
    bitstream = gateware / "display_board.fs"
    (output / "board_manifest.json").write_text(json.dumps({
        "device": platform.device, "mode": args.mode, "reference_hz": 40_000_000,
        "pins": DISPLAY_PINS, "profile": profile,
        "reset_csr_initial": 1, "programmed": False,
        "implementation_complete": args.build,
        "bitstream_sha256": hashlib.sha256(bitstream.read_bytes()).hexdigest() if args.build else None,
        "timing_backend": "nextpnr --freq 40 (strict)" if args.toolchain == "apicula" else "Gowin SDC",
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
