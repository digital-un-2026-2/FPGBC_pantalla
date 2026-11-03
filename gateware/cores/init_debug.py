"""Arnés externo de diagnóstico: secuenciador y motor Verilog sin E/S DSI."""

from migen import Cat, ClockSignal, If, Instance, Module, ResetSignal, Signal
from litex.soc.interconnect.csr import AutoCSR, CSRStatus, CSRStorage


class InitMonitor(Module):
    """Monitor pasivo, independiente del control funcional y simulable en Migen."""

    def __init__(self):
        self.reset = Signal()
        self.aceptado = Signal()
        self.terminado = Signal()
        self.completa = Signal()
        self.fallo = Signal()
        self.ciclo = Signal(32)
        self.aceptaciones = Signal(4)
        self.finales = Signal(4)
        self.error = Signal()
        self.ciclo_completa = Signal(32)
        self.inicios = [Signal(32) for _ in range(11)]
        self.fines = [Signal(32) for _ in range(11)]
        completa_anterior = Signal()
        self.sync += If(self.reset,
            self.ciclo.eq(0), self.aceptaciones.eq(0), self.finales.eq(0),
            self.error.eq(0), self.ciclo_completa.eq(0), completa_anterior.eq(0),
            *[s.eq(0) for s in self.inicios + self.fines],
        ).Else(
            completa_anterior.eq(self.completa),
            If(~self.completa & ~self.fallo, self.ciclo.eq(self.ciclo + 1)),
            If(self.completa & ~completa_anterior,
                self.ciclo_completa.eq(self.ciclo)),
            If(self.aceptado,
                If(self.aceptaciones != 15,
                    self.aceptaciones.eq(self.aceptaciones + 1)),
                If((self.aceptaciones >= 11) |
                   (self.aceptaciones != self.finales), self.error.eq(1)),
                *[If(self.aceptaciones == i, s.eq(self.ciclo))
                  for i, s in enumerate(self.inicios)],
            ),
            If(self.terminado,
                If(self.finales != 15, self.finales.eq(self.finales + 1)),
                If((self.finales >= 11) |
                   (self.aceptaciones != self.finales + 1), self.error.eq(1)),
                *[If(self.finales == i, s.eq(self.ciclo))
                  for i, s in enumerate(self.fines)],
            ),
        )


class InitDebug(Module, AutoCSR):
    def __init__(self):
        self.reset_prueba = CSRStorage(1, name="reset_prueba")
        self.lp_habilitada = CSRStorage(1, reset=1, name="lp_habilitada")
        self.paquete = CSRStorage(4, name="paquete")
        self.estado = CSRStatus(7, name="estado")
        self.cuentas = CSRStatus(8, name="cuentas")
        self.completa_ciclo = CSRStatus(32, name="completa_ciclo")

        for name, width in (
            ("reset_local", 1), ("rst_motor", 1), ("lp_preparada", 1),
            ("preparar_lp", 1), ("solicitud", 1), ("permiso", 1),
            ("aceptado", 1), ("ocupado", 1), ("terminado", 1),
            ("longitud", 4), ("pos", 4), ("dato", 8), ("d0", 2),
            ("en_curso", 1), ("completa", 1), ("fallo", 1),
            ("causa", 3), ("indice", 4), ("trigger", 1),
        ):
            setattr(self, name, Signal(width, name=f"init_{name}"))

        self.submodules.monitor = mon = InitMonitor()
        self.comb += [
            self.reset_local.eq(ResetSignal() | self.reset_prueba.storage),
            self.lp_preparada.eq(self.preparar_lp & self.lp_habilitada.storage),
            mon.reset.eq(self.reset_local), mon.aceptado.eq(self.aceptado),
            mon.terminado.eq(self.terminado), mon.completa.eq(self.completa),
            mon.fallo.eq(self.fallo), self.indice.eq(mon.finales),
            self.trigger.eq(self.solicitud & (self.indice == self.paquete.storage)
                            & ~self.reset_local),
            self.estado.status.eq(Cat(self.en_curso, self.completa, self.fallo,
                                     self.causa, mon.error)),
            self.cuentas.status.eq(Cat(mon.aceptaciones, mon.finales)),
            self.completa_ciclo.status.eq(mon.ciclo_completa),
        ]
        for i in range(11):
            for prefix, signals in (("inicio", mon.inicios), ("fin", mon.fines)):
                csr = CSRStatus(32, name=f"{prefix}{i}")
                setattr(self, f"{prefix}{i}", csr)
                self.comb += csr.status.eq(signals[i])

        self.specials += Instance("secuenciador_init",
            i_clk=ClockSignal(), i_rst=self.reset_local,
            i_lp_preparada=self.lp_preparada, o_preparar_lp=self.preparar_lp,
            i_aceptado=self.aceptado, i_ocupado=self.ocupado,
            i_terminado=self.terminado, i_pos=self.pos,
            o_solicitud=self.solicitud, o_permiso_arranque=self.permiso,
            o_cantidad_bytes=self.longitud, o_byte_almacen=self.dato,
            o_rst_motor=self.rst_motor, o_init_en_curso=self.en_curso,
            o_init_completa=self.completa, o_fallo=self.fallo,
            o_codigo_fallo=self.causa,
        )
        self.specials += Instance("motor_lpdt", p_ANCHO_LONGITUD=4,
            i_clk=ClockSignal(), i_rst=self.rst_motor,
            i_solicitud=self.solicitud, i_permiso_arranque=self.permiso,
            i_cantidad_bytes=self.longitud, i_byte_almacen=self.dato,
            o_aceptado=self.aceptado, o_ocupado=self.ocupado,
            o_terminado=self.terminado, o_pos=self.pos, o_estado_D0=self.d0,
        )
