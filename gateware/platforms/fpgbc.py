from litex.build.generic_platform import Pins, IOStandard, Misc, Subsignal
from litex.build.gowin.platform import GowinPlatform
from litex.build.gowin.apicula import GowinApiculaToolchain


_dsi_hs_pins = {"p": "117 115 113", "n": "116 114 112"}

_io = [
    ("clk40", 0, Pins("11"), IOStandard("LVCMOS33")),
    (
        "serial",
        0,
        Subsignal("rx", Pins("28")),
        Subsignal("tx", Pins("27")),
        IOStandard("LVCMOS33"),
    ),
    # DSI: números de pin de FPGA, NO contactos del conector LCD.
    # Orden de los bits en p/n: 0 = D0, 1 = D1, 2 = CLK (como motor_phy).
    # Cada rama LP se une al conductor del panel mediante 100 ohmios;
    # la rama HS llega al mismo conductor directamente. Ver docs/hardware.md.
    #
    # Configuración candidata, NO validación eléctrica ni permiso de carga.
    # LP: BANK0 medido a 1,21 V; NUNCA LVCMOS33.
    # HS: BANK1 medido a 2,52 V; TLVDS_TBUF permanentemente deshabilitado.
    # Declarar el estándar también evita agrupar LP P/N como diferencial.
    # PULL_MODE=NONE solo rige tras configuración; revisar los pulls de arranque.
    (
        "dsi_lp",
        0,
        Subsignal("p", Pins("122 124 126")),
        Subsignal("n", Pins("123 125 128")),
        IOStandard("LVCMOS12"),
        Misc("PULL_MODE=NONE"),
    ),
    (
        "dsi_hs",
        0,
        Subsignal("p", Pins(_dsi_hs_pins["p"])),
        Subsignal("n", Pins(_dsi_hs_pins["n"])),
        IOStandard("LVDS25"),
        Misc("PULL_MODE=NONE"),
    ),
]


class Platform(GowinPlatform):
    default_clk_name = "clk40"
    default_clk_period = 1e9 / 40e6  # Periodo de 25ns / 40MHz

    def __init__(self, toolchain="apicula"):
        GowinPlatform.__init__(
            self,
            "GW2AR-LV18EQ144PC8/I7",
            _io,
            toolchain=toolchain,
            devicename="GW2AR-18C",
        )
        if toolchain == "apicula":
            # synth_gowin usa gw1n por defecto; necesitamos las celdas GW2A.
            self.toolchain._synth_opts += " -family gw2a"

    def do_finalize(self, fragment):
        super().do_finalize(fragment)
        if isinstance(self.toolchain, GowinApiculaToolchain):
            hs = self.lookup_request("dsi_hs", loose=True)
            if hs is not None:
                # El CST diferencial de LiteX agrupa P,N en una sola IO_LOC.
                # nextpnr instalado no resuelve la rama N de estos vectores.
                # Al final del CST, fijar AMBAS ramas explícitamente para que
                # ninguna dependa de esa resolución implícita. No cambiar pines.
                for polarity, identifiers in _dsi_hs_pins.items():
                    for lane, pin in enumerate(identifiers.split()):
                        self.add_platform_command(
                            f'IO_LOC "{{pad}}[{lane}]" {pin};',
                            pad=getattr(hs, polarity),
                        )
                        self.add_platform_command(
                            f'IO_PORT "{{pad}}[{lane}]" IO_TYPE=LVDS25 PULL_MODE=NONE;',
                            pad=getattr(hs, polarity),
                        )
