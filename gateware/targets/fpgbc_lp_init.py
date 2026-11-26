"""Exporta el top LP y sus restricciones. No sintetiza, empaqueta ni programa."""

import argparse
import shlex
import sys

from migen import ClockDomain, If, Instance, Module, Signal
from migen.genlib.cdc import MultiReg

from gateware.cores.lp_init import LPInit, ROOT
from gateware.platforms.fpgbc import Platform


class LPInitTarget(Module):
    def __init__(self, platform, *, enable_lp=False, enable_backlight=False):
        if enable_backlight and not enable_lp:
            raise ValueError("El backlight requiere la inicialización LP activa")
        # No usar el packer sin la corrección de pads usados y su auditoría.
        platform.toolchain.packer_cmd = (
            f"{shlex.quote(sys.executable)} "
            f"{shlex.quote(str(ROOT / 'scripts/pack_lp_checked.py'))}"
        )
        clk_pad = platform.request("clk40")
        clk = Signal(name="clk40_i")
        self.specials += Instance("IBUF", name="clk40_buf", i_I=clk_pad, o_O=clk)
        # Pads simples explícitos: no hay transmisor ni fusión diferencial HS.
        self.clock_domains.cd_por = ClockDomain("por", reset_less=True)
        self.clock_domains.cd_sys = ClockDomain("sys")
        self.comb += [self.cd_por.clk.eq(clk), self.cd_sys.clk.eq(clk)]

        rst_pad = platform.request("global_rst_n")
        rst_n = Signal(name="button_rst_n")
        self.specials += Instance("IBUF", name="reset_buf", i_I=rst_pad, o_O=rst_n)
        button_reset = Signal()
        # El dominio por sigue funcionando mientras sys está en reset.
        self.specials += MultiReg(~rst_n, button_reset, odomain="por")
        # Reset global durante 16 ciclos, cubriendo ambos flancos del RTL.
        # Cada pulsación lo recarga; la liberación conserva 16 ciclos de reset.
        # No sustituye ni detecta la alimentación/reset del panel.
        por = Signal(16, reset=0xffff)
        self.sync.por += If(button_reset, por.eq(0xffff)).Else(por.eq(por >> 1))
        self.comb += self.cd_sys.rst.eq((por != 0) | (not enable_lp))
        platform.add_period_constraint(clk_pad, platform.default_clk_period)
        self.submodules.init = LPInit(platform)

        if enable_backlight:
            # 40 MHz / 40 000 = 1 kHz; mitad del periodo en alto.
            period = 40_000
            counter = Signal(max=period)
            enabled = Signal()
            pwm = Signal()
            ready = Signal()
            # Registrar el fin de INIT evita habilitar por transitorios de su decodificador.
            self.comb += ready.eq(enabled & ~self.init.fallo & ~self.cd_sys.rst)
            self.sync += [
                enabled.eq(self.init.init_completa & ~self.init.fallo),
                If(
                    ready,
                    If(counter == period - 1, counter.eq(0)).Else(counter.eq(counter + 1)),
                    pwm.eq(counter < period // 2),
                ).Else(counter.eq(0), pwm.eq(0)),
            ]
            self.specials += [
                Instance("OBUF", i_I=ready, o_O=platform.request("backlight_en")),
                Instance("OBUF", i_I=ready & pwm, o_O=platform.request("backlight_pwm")),
            ]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="build/fpgbc_lp_init")
    parser.add_argument(
        "--enable-lp", action="store_true",
        help="Exportar la variante activa para revisión; NO autoriza carga en placa",
    )
    parser.add_argument(
        "--enable-backlight", action="store_true",
        help="Añadir EN y PWM de backlight; requiere --enable-lp",
    )
    args = parser.parse_args()
    if args.enable_backlight and not args.enable_lp:
        parser.error("--enable-backlight requiere --enable-lp")

    platform = Platform(toolchain="apicula")
    top = LPInitTarget(platform, enable_lp=args.enable_lp, enable_backlight=args.enable_backlight)
    platform.build(
        top, build_dir=args.output_dir, build_name="fpgbc_lp_init", run=False,
        timingstrict=True,
    )
    print("Solo exportación. No se han ejecutado síntesis, place-and-route ni carga.")
    print("Revisar E/S, corriente/slew, arranque y temporización antes de usar en placa.")
    if not args.enable_lp:
        print("Variante por defecto: reset permanente, todos los drivers deshabilitados.")


if __name__ == "__main__":
    main()
