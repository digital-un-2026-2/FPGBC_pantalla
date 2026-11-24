from litex.build.generic_platform import Pins, IOStandard, Misc, Subsignal
from litex.build.gowin.platform import GowinPlatform


_dsi_hs_pins = {"p": "117 115 113", "n": "116 114 112"}

_io = [
    ("clk40", 0, Pins("11"), IOStandard("LVCMOS33")),
    # Misma entrada de reset de FPGBC_digital_UN/soc/FPGBC_unal_platform.py.
    ("global_rst_n", 0, Pins("120"), IOStandard("LVCMOS33"), Misc("PULL_MODE=UP")),
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
    # Ramas HS: BANK1 medido a 2,52 V; GPIO LVCMOS25 siempre deshabilitados.
    # No se implementa un transmisor HS ni se conducen 2,5 V sobre el panel.
    # Declarar el estándar también evita agrupar LP P/N como diferencial.
    # PULL_MODE=NONE solo rige tras configuración; revisar los pulls de arranque.
    (
        "dsi_lp",
        0,
        Subsignal("p", Pins("122 124 126")),
        Subsignal("n", Pins("123 125 128")),
        IOStandard("LVCMOS12"),
        Misc("PULL_MODE=NONE"),
        # Perfil explícito: conserva los defaults del packer ya usados.
        # Estos ajustes no certifican niveles/flancos sobre el panel.
        Misc("DRIVE=8"),
        Misc("SLEW_RATE=FAST"),
    ),
    (
        "dsi_hs",
        0,
        Subsignal("p", Pins(_dsi_hs_pins["p"])),
        Subsignal("n", Pins(_dsi_hs_pins["n"])),
        IOStandard("LVCMOS25"),
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
