from migen import Module, Signal
from litex.soc.interconnect.csr import AutoCSR, CSRStorage, CSRStatus


class DebugRegs(Module, AutoCSR):
    def __init__(self):
        self.entrada = CSRStorage(32, name="entrada")
        self.salida = CSRStatus(32, name="salida")
        self.contador = CSRStatus(32, name="contador")

        cuenta = Signal(32)

        self.comb += [
            self.salida.status.eq(self.entrada.storage + 1),
            self.contador.status.eq(cuenta),
        ]

        self.sync += cuenta.eq(cuenta + 1)
