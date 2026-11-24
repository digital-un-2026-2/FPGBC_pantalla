"""Adaptador Gowin exclusivamente LP, sin registros ni lógica de protocolo."""

from migen import Instance, Module, Signal


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
                # Objetivo solo LP: no instanciar un transmisor diferencial.
                # Cada GPIO de las ramas HS permanece deshabilitado. IOBUF
                # evita además que el packer omita BANK1 al clasificar TBUF
                # como salida; la lectura de entrada no se utiliza.
                Instance(
                    "IOBUF", name=f"hs_p_off_buf_{lane}",
                    i_I=0, i_OEN=1, io_IO=hs_pads.p[lane], o_O=Signal(),
                ),
                Instance(
                    "IOBUF", name=f"hs_n_off_buf_{lane}",
                    i_I=0, i_OEN=1, io_IO=hs_pads.n[lane], o_O=Signal(),
                ),
            ]
