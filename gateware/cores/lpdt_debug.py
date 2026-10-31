"""Control CSR del motor LPDT para depuración interna, sin drivers de panel."""

from migen import Array, Cat, Constant, If, Module, ResetSignal, Signal
from litex.soc.interconnect.csr import AutoCSR, CSRStatus, CSRStorage

from gateware.cores.motor_lpdt import MotorLPDT


class LPDTDebug(Module, AutoCSR):
    IDLE = 0
    SOLICITANDO = 1
    TRANSMITIENDO = 2

    def __init__(self):
        # Almacén de preparación: el PC puede escribirlo incluso durante un envío.
        # Ocho bits para rechazar también longitudes > 7, sin truncarlas a 3 bits.
        self.longitud = CSRStorage(8, name="longitud")
        preparacion = []
        for indice in range(7):
            registro = CSRStorage(8, name=f"byte{indice}")
            setattr(self, f"byte{indice}", registro)
            preparacion.append(registro)

        # Cada escritura de 1 es una orden; el valor almacenado no mantiene
        # la solicitud activa. Una escritura de 0 no hace nada.
        self.iniciar = CSRStorage(1, name="iniciar")
        self.estado = CSRStatus(6, name="estado")
        self.finalizado = CSRStatus(1, name="finalizado")

        self.submodules.motor = motor = MotorLPDT()

        # Copia privada: sólo cambia al admitir una orden válida estando libre.
        self.bytes_activos = [Signal(8, name=f"lpdt_activo_{i}") for i in range(7)]
        self.longitud_activa = Signal(3)
        self.estado_supervisor = Signal(2, reset=self.IDLE)
        self.orden = Signal()
        self.listo = Signal()
        self.ocupado = Signal()
        self.rechazada = Signal()
        self.longitud_invalida = Signal()
        self.fin_latched = Signal()
        self.reset_observado = Signal()

        longitud_valida = Signal()
        # El índice 7 no pertenece al paquete: dar una respuesta definida.
        almacen = Array(self.bytes_activos + [Constant(0, 8)])
        self.comb += [
            self.reset_observado.eq(ResetSignal("sys")),
            self.orden.eq(self.iniciar.wr_stb & self.iniciar.storage),
            longitud_valida.eq((self.longitud.storage >= 1) & (self.longitud.storage <= 7)),
            self.ocupado.eq((self.estado_supervisor != self.IDLE) | motor.ocupado),
            self.listo.eq(~self.ocupado & ~self.reset_observado),
            motor.solicitud.eq(self.estado_supervisor == self.SOLICITANDO),
            # Permiso lógico exclusivo de esta prueba INTERNA. No certifica
            # reposo D-PHY ni habilita drivers físicos.
            motor.permiso_arranque.eq(1),
            motor.cantidad_bytes.eq(self.longitud_activa),
            motor.byte_almacen.eq(almacen[motor.pos]),
            self.finalizado.status.eq(self.fin_latched),
            self.estado.status.eq(Cat(
                self.listo,                         # bit 0
                self.ocupado,                       # bit 1
                self.estado_supervisor == self.SOLICITANDO,  # bit 2
                motor.ocupado,                      # bit 3
                self.rechazada,                     # bit 4
                self.longitud_invalida,             # bit 5
            )),
        ]

        self.sync += [
            If(self.orden,
                If(~self.listo,
                    # Sin cola y sin modificar el paquete activo.
                    self.rechazada.eq(1),
                    self.longitud_invalida.eq(~longitud_valida),
                ).Elif(~longitud_valida,
                    self.rechazada.eq(1),
                    self.longitud_invalida.eq(1),
                ).Else(
                    *[destino.eq(origen.storage)
                      for destino, origen in zip(self.bytes_activos, preparacion)],
                    self.longitud_activa.eq(self.longitud.storage),
                    self.rechazada.eq(0),
                    self.longitud_invalida.eq(0),
                    self.estado_supervisor.eq(self.SOLICITANDO),
                )
            ),
            If((self.estado_supervisor == self.SOLICITANDO) & motor.aceptado,
                self.estado_supervisor.eq(self.TRANSMITIENDO),
                self.fin_latched.eq(0),
            ),
            If((self.estado_supervisor == self.TRANSMITIENDO) & motor.terminado,
                self.estado_supervisor.eq(self.IDLE),
                self.fin_latched.eq(1),
            ),
        ]
