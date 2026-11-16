"""Exporta el top LP y sus restricciones. No sintetiza, empaqueta ni programa."""

import argparse

from migen import ClockDomain, Instance, Module, Signal

from gateware.cores.lp_init import LPInit
from gateware.platforms.fpgbc import Platform


class LPInitTarget(Module):
    def __init__(self, platform, *, enable_lp=False):
        clk_pad = platform.request("clk40")
        clk = Signal(name="clk40_i")
        self.specials += Instance("IBUF", name="clk40_buf", i_I=clk_pad, o_O=clk)
        # No usar -noiopads: nextpnr necesita los OBUF de cada rama HS para
        # ubicarlos y fusionarlos con TLVDS_TBUF en pack_diff_iobs().
        self.clock_domains.cd_por = ClockDomain("por", reset_less=True)
        self.clock_domains.cd_sys = ClockDomain("sys")
        self.comb += [self.cd_por.clk.eq(clk), self.cd_sys.clk.eq(clk)]

        # Reset global durante 16 ciclos, cubriendo ambos flancos del RTL.
        # No sustituye ni detecta la alimentación/reset del panel.
        por = Signal(16, reset=0xffff)
        self.sync.por += por.eq(por >> 1)
        self.comb += self.cd_sys.rst.eq((por != 0) | (not enable_lp))
        platform.add_period_constraint(clk_pad, platform.default_clk_period)
        self.submodules.init = LPInit(platform)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", default="build/fpgbc_lp_init")
    parser.add_argument(
        "--enable-lp", action="store_true",
        help="Exportar la variante activa para revisión; NO autoriza carga en placa",
    )
    args = parser.parse_args()

    platform = Platform(toolchain="apicula")
    top = LPInitTarget(platform, enable_lp=args.enable_lp)
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
