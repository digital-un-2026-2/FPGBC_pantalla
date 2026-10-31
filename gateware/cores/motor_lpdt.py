from migen import Module, Signal, Instance, ClockSignal, ResetSignal


class MotorLPDT(Module):
    def __init__(self):
        # entradas del motor
        self.permiso_arranque = Signal()
        self.solicitud = Signal()
        self.cantidad_bytes = Signal(3)
        self.byte_almacen = Signal(8)

        # salidas del motor
        self.aceptado = Signal()
        self.ocupado = Signal()
        self.terminado = Signal()
        self.pos = Signal(3)
        self.estado_D0 = Signal(2)

        self.specials += Instance(
            "motor_lpdt",
            i_clk=ClockSignal("sys"),
            i_rst=ResetSignal("sys"),
            i_permiso_arranque=self.permiso_arranque,
            i_solicitud=self.solicitud,
            i_cantidad_bytes=self.cantidad_bytes,
            i_byte_almacen=self.byte_almacen,
            o_aceptado=self.aceptado,
            o_ocupado=self.ocupado,
            o_terminado=self.terminado,
            o_pos=self.pos,
            o_estado_D0=self.estado_D0,
        )
