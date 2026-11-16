"""Conexión de los tres tops RTL, sin CPU, CSR, UART ni protocolo adicional."""

from pathlib import Path

from migen import ClockSignal, Instance, Module, ResetSignal, Signal

from gateware.cores.phy_pads import GowinLPPads


ROOT = Path(__file__).resolve().parents[2]
RTL_SOURCES = (
    "motor_lpdt/src/count.v",
    "motor_lpdt/src/comp.v",
    "motor_lpdt/src/mux.v",
    "motor_lpdt/src/reg_0.v",
    "motor_lpdt/src/motor_control.v",
    "motor_lpdt/src/motor_lpdt.v",
    "secuenciador_init/src/rom_descriptores.v",
    "secuenciador_init/src/rom_paquetes.v",
    "secuenciador_init/src/validador_descriptor.v",
    "secuenciador_init/src/secuenciador_control.v",
    "secuenciador_init/src/secuenciador_init.v",
    "motor_phy/src/phy_control.v",
    "motor_phy/src/phy_mask.v",
    "motor_phy/src/phy_lanes.v",
    "motor_phy/src/motor_phy.v",
)


class LPInit(Module):
    def __init__(self, platform, *, t_habilitacion=4):
        if not isinstance(t_habilitacion, int) or t_habilitacion < 1:
            raise ValueError("t_habilitacion debe ser un entero >= 1")

        for source in RTL_SOURCES:
            platform.add_source(str(ROOT / source))

        # Se exponen para pruebas o una futura interfaz de diagnóstico.
        self.init_en_curso = Signal()
        self.init_completa = Signal()
        self.fallo = Signal()
        self.codigo_fallo = Signal(3)
        self.lp_preparada = Signal()
        self.estado_D0 = Signal(2)
        self.lp_p = Signal(3)
        self.lp_n = Signal(3)
        self.lp_oe = Signal(3)
        self.hs_oen = Signal(3)

        preparar_lp = Signal()
        solicitud = Signal()
        permiso_arranque = Signal()
        aceptado = Signal()
        ocupado = Signal()
        terminado = Signal()
        pos = Signal(5)
        cantidad_bytes = Signal(5)
        byte_almacen = Signal(8)
        rst_motor = Signal()

        self.specials += [
            Instance(
                "secuenciador_init", name="secuenciador",
                i_clk=ClockSignal(), i_rst=ResetSignal(),
                i_lp_preparada=self.lp_preparada, o_preparar_lp=preparar_lp,
                i_aceptado=aceptado, i_ocupado=ocupado, i_terminado=terminado,
                i_pos=pos, o_solicitud=solicitud, o_permiso_arranque=permiso_arranque,
                o_cantidad_bytes=cantidad_bytes, o_byte_almacen=byte_almacen,
                o_rst_motor=rst_motor, o_init_en_curso=self.init_en_curso,
                o_init_completa=self.init_completa, o_fallo=self.fallo,
                o_codigo_fallo=self.codigo_fallo,
            ),
            Instance(
                "motor_lpdt", name="motor", p_ANCHO_LONGITUD=5,
                i_clk=ClockSignal(), i_rst=rst_motor,
                i_permiso_arranque=permiso_arranque, i_solicitud=solicitud,
                i_cantidad_bytes=cantidad_bytes, i_byte_almacen=byte_almacen,
                o_aceptado=aceptado, o_ocupado=ocupado, o_terminado=terminado,
                o_pos=pos, o_estado_D0=self.estado_D0,
            ),
            Instance(
                "motor_phy", name="phy", p_T_HABILITACION=t_habilitacion,
                # Reset GLOBAL: rst_motor es únicamente el aborto/reset LPDT.
                i_clk=ClockSignal(), i_rst=ResetSignal(),
                i_preparar_lp=preparar_lp, i_fallo_init=self.fallo,
                i_estado_D0=self.estado_D0, o_lp_preparada=self.lp_preparada,
                o_lp_p=self.lp_p, o_lp_n=self.lp_n, o_lp_oe=self.lp_oe,
                o_hs_oen=self.hs_oen,
            ),
        ]

        self.submodules.pads = GowinLPPads(
            platform.request("dsi_lp"), platform.request("dsi_hs"),
            self.lp_p, self.lp_n, self.lp_oe,
        )
