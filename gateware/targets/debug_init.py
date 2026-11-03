"""Síntesis conjunta para diagnóstico interno; no programa ni conduce DSI."""

import argparse
from pathlib import Path

from litescope import LiteScopeAnalyzer
from litex.soc.integration.builder import Builder
from litex.soc.integration.soc_core import SoCMini

from gateware.cores.debug_regs import DebugRegs
from gateware.cores.init_debug import InitDebug
from gateware.platforms.fpgbc import Platform
from gateware.targets.lpdt_demo import CRG


class InitDebugSoC(SoCMini):
    def __init__(self, platform):
        super().__init__(platform, clk_freq=40_000_000, csr_data_width=32,
                         ident="FPGBC debug secuenciador init")
        self.submodules.crg = CRG(platform)
        self.add_uartbone(name="uartbone", uart_name="serial", baudrate=115200)
        self.submodules.debug_regs = DebugRegs()
        self.csr.add("debug_regs")
        raiz = Path(__file__).resolve().parents[2]
        for nombre in ("motor_lpdt", "motor_control", "count", "comp", "reg_0", "mux"):
            platform.add_source(str(raiz / "motor_lpdt" / "src" / f"{nombre}.v"))
        for fuente in sorted((raiz / "secuenciador_init" / "src").glob("*.v")):
            platform.add_source(str(fuente))
        self.submodules.init = init = InitDebug()
        self.csr.add("init")
        self.submodules.analyzer = LiteScopeAnalyzer(
            [getattr(init, name) for name in (
                "reset_local", "rst_motor", "lp_preparada", "preparar_lp",
                "solicitud", "permiso", "aceptado", "ocupado", "terminado",
                "longitud", "pos", "dato", "d0", "en_curso", "completa",
                "fallo", "causa", "indice", "trigger")],
            depth=2048, clock_domain="sys", samplerate=40_000_000,
            csr_csv=str(raiz / "build/debug_init/analyzer.csv"),
        )
        self.csr.add("analyzer")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build", action="store_true")
    args = parser.parse_args()
    builder = Builder(InitDebugSoC(Platform()), output_dir="build/debug_init",
                      csr_csv="build/debug_init/csr.csv", compile_software=False,
                      compile_gateware=args.build)
    # Este target no acepta silenciosamente fallos de timing de nextpnr.
    builder.build(build_name="debug_init", timingstrict=True)


if __name__ == "__main__":
    main()
