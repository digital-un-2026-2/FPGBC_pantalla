"""Adaptador Gowin exclusivamente LP, sin registros ni lógica de protocolo."""

from migen import Instance, Module


class GowinLPPads(Module):
    def __init__(self, lp_pads, hs_pads, lp_p, lp_n, lp_oe):
        signals = (lp_pads.p, lp_pads.n, hs_pads.p, hs_pads.n, lp_p, lp_n, lp_oe)
        if any(len(signal) != 3 for signal in signals):
            raise ValueError("Se requieren tres pares en orden D0, D1, CLK")

        for lane in range(3):
            self.specials += [
                Instance(
                    "TBUF", name=f"lp_p_buf_{lane}",
                    i_I=lp_p[lane], i_OEN=~lp_oe[lane], o_O=lp_pads.p[lane],
                ),
                Instance(
                    "TBUF", name=f"lp_n_buf_{lane}",
                    i_I=lp_n[lane], i_OEN=~lp_oe[lane], o_O=lp_pads.n[lane],
                ),
                # No existe control que pueda habilitar HS en este objetivo.
                # Fijar I=0 NO basta: OEN=1 es lo que deshabilita el driver.
                Instance(
                    "TLVDS_TBUF", name=f"hs_off_buf_{lane}",
                    i_I=0, i_OEN=1, o_O=hs_pads.p[lane], o_OB=hs_pads.n[lane],
                ),
            ]
