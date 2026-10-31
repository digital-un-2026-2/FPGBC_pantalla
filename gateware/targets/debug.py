import argparse
from pathlib import Path

from litescope import LiteScopeAnalyzer
from litex.soc.integration.soc_core import SoCMini
from litex.soc.integration.builder import Builder
from gateware.platforms.fpgbc import Platform

from gateware.targets.lpdt_demo import CRG

from gateware.cores.debug_regs import DebugRegs
from gateware.cores.lpdt_debug import LPDTDebug


class DebugSoC(SoCMini):
    def __init__(self, platform):
        super().__init__(
            platform, clk_freq=40_000_000, csr_data_width=32, ident="FPGBC debug"
        )

        self.submodules.crg = CRG(platform)

        self.add_uartbone(
            name="uartbone",
            uart_name="serial",
            baudrate=115200,
        )

        self.submodules.debug_regs = DebugRegs()
        self.csr.add("debug_regs")

        # Fuentes explícitas: Instance no incorpora automáticamente el RTL.
        raiz = Path(__file__).resolve().parents[2]
        for fuente in ("motor_lpdt.v", "motor_control.v", "count.v",
                       "comp.v", "reg_0.v", "mux.v"):
            platform.add_source(str(raiz / "motor_lpdt" / "src" / fuente))

        self.submodules.lpdt = LPDTDebug()
        self.csr.add("lpdt")

        motor = self.lpdt.motor
        self.submodules.analyzer = LiteScopeAnalyzer(
            [
                self.lpdt.reset_observado,
                self.lpdt.orden,
                self.lpdt.estado_supervisor,
                self.lpdt.rechazada,
                motor.solicitud,
                motor.permiso_arranque,
                motor.aceptado,
                motor.ocupado,
                motor.terminado,
                motor.cantidad_bytes,
                motor.pos,
                motor.byte_almacen,
                motor.estado_D0,
            ],
            depth=2048,
            clock_domain="sys",
            samplerate=40_000_000,
            csr_csv=str(raiz / "build" / "debug" / "analyzer.csv"),
        )
        self.csr.add("analyzer")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--build",
        action="store_true",
        help="Ejecutar síntesis e implementación.",
    )
    args = parser.parse_args()

    placa = Platform()
    soc = DebugSoC(placa)

    builder = Builder(
        soc,
        output_dir="build/debug",
        csr_csv="build/debug/csr.csv",
        compile_software=False,
        compile_gateware=args.build,
    )

    builder.build(build_name="debug")


if __name__ == "__main__":
    main()
