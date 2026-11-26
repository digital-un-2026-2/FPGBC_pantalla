"""Prueba aislada de rutas de CLOCK_GEN: un solo pin de entrada, sin bitstream."""

import argparse
import json
from pathlib import Path


PORTS = {
    "CLKIN": "CLK_REF", "RESET": "RESET", "CLKOUT": "CLK_HS",
    "CLKOUTD": "CLK_BYTE", "LOCK": "LOCK_RAW",
}
PARAMS = {
    "DEVICE": "GW2AR-18", "FCLKIN": "40",
    "IDIV_SEL": 1, "FBDIV_SEL": 10, "ODIV_SEL": 4, "DYN_SDIV_SEL": 4,
    "CLKFB_SEL": "internal", "CLKOUTD_SRC": "CLKOUT",
    **dict.fromkeys(("DYN_IDIV_SEL", "DYN_FBDIV_SEL", "DYN_ODIV_SEL",
                     "DYN_DA_EN", "CLKOUT_BYPASS", "CLKOUTD_BYPASS"), "false"),
}
HCLK_GROUP = "X27Y0/CLKDIV_HCLK0_SECT"


def require(condition, message):
    if not condition:
        raise SystemExit(f"Error en la sonda de CLOCK_GEN: {message}")


def prepare(build):
    design = json.loads((build / "clock_gen.json").read_text())
    mod = design["modules"]["clock_gen"]
    ports, cells, nets = (mod[k] for k in ("ports", "cells", "netnames"))
    require(set(ports) == set(PORTS.values()), "interfaz inesperada")
    pll = cells["pll"]
    require(pll["type"] == "rPLL" and
            all(c["type"] == "GND" for n, c in cells.items() if n != "pll"),
            "el módulo no se reduce a una rPLL y masa")

    conn = pll["connections"]
    for pin, port in PORTS.items():
        require(len(ports[port]["bits"]) == 1 and conn[pin] == ports[port]["bits"],
                f"{pin} no está cableado directamente a {port}")
    for param, value in PARAMS.items():
        got = pll["parameters"][param]
        actual = int(got, 2) if isinstance(value, int) else got
        require(actual == value, f"{param} = {actual}, esperado {value}")
    zeros = {"0"} | {c["connections"]["G"][0] for c in cells.values() if c["type"] == "GND"}
    for pin in ("RESET_P", "CLKFB", "IDSEL", "FBDSEL", "ODSEL", "PSDA", "DUTYDA", "FDLY"):
        require(set(conn[pin]) <= zeros, f"{pin} no está a cero")
    require(not conn["CLKOUTP"] and not conn["CLKOUTD3"], "salida de PLL no prevista")

    def cell(name, kind, inputs, outputs, **parameters):
        cells[name] = {
            "type": kind, "hide_name": 0, "parameters": parameters,
            "attributes": {"keep": "1"},
            "port_directions": dict.fromkeys(inputs, "input") | dict.fromkeys(outputs, "output"),
            "connections": inputs | outputs,
        }

    next_bit = max(b for net in nets.values() for b in net["bits"] if isinstance(b, int)) + 1

    def new_net(name):
        nonlocal next_bit
        bits = [next_bit]
        nets[name] = {"hide_name": 0, "attributes": {}, "bits": bits}
        next_bit += 1
        return bits

    ref = new_net("CLK_REF")
    nets["ref_to_pll"] = {"hide_name": 0, "attributes": {}, "bits": conn["CLKIN"]}
    cell("ref_ibuf", "IBUF", {"I": ref}, {"O": conn["CLKIN"]})
    mod["ports"] = {"CLK_REF": {"direction": "input", "bits": ref}}
    conn["RESET"] = conn["RESET_P"]
    del nets["RESET"]

    # Cargas internas de prueba: alcanzan GCLK y el grupo HCLK superior.
    # El CLKDIV es un sumidero de la sonda, no RTL de CLOCK_DDR.
    divided = new_net("hclk_divided")
    cell("probe_hclk", "CLKDIV", {"HCLKIN": conn["CLKOUT"], "RESETN": ["1"], "CALIB": ["0"]},
         {"CLKOUT": divided}, DIV_MODE="2", GSREN="false")
    for name, clock in (("byte", conn["CLKOUTD"]), ("divided", divided)):
        cell(f"witness_{name}", "DFF", {"CLK": clock, "D": conn["LOCK"]},
             {"Q": new_net(f"witness_{name}_q")})

    (build / "probe.json").write_text(json.dumps(design))
    (build / "probe.cst").write_text(
        'IO_LOC "CLK_REF" 11;\nIO_PORT "CLK_REF" IO_TYPE=LVCMOS33;\n'
        'INS_LOC "probe_hclk" TOPSIDE[0];\n'
    )
    # Periodos nominales para esta sonda, no restricciones de integración.
    (build / "probe.sdc").write_text(
        "create_clock -period 25 [get_ports CLK_REF]\n"
        "create_clock -period 4.5454545 [get_nets CLK_HS]\n"
        "create_clock -period 18.181818 [get_nets CLK_BYTE]\n"
        "create_clock -period 9.090909 [get_nets hclk_divided]\n"
    )
    print("PASS síntesis: rPLL 40 → 220/55 MHz, salidas y RESET directos")


def verify(build):
    (mod,) = json.loads((build / "probe_routed.json").read_text())["modules"].values()
    cells = mod["cells"]
    require(list(mod["ports"]) == ["CLK_REF"] and
            mod["ports"]["CLK_REF"]["direction"] == "input", "se esperaba un único pin de entrada")
    ref_ibuf = cells["ref_ibuf"]
    require(ref_ibuf["attributes"]["NEXTPNR_BEL"] == "X0Y26/IOBA",
            "la referencia no llegó al sitio IOL27A del pin 11")
    pll = cells["pll"]
    require(pll["type"] == "rPLL", "no se colocó rPLL")
    require(pll["connections"]["CLKIN"] == ref_ibuf["connections"]["O"],
            "CLKIN no está conectado al pin 11")
    divider = cells["probe_hclk"]
    bel = divider["attributes"]["NEXTPNR_BEL"]
    require(divider["type"] == "CLKDIV" and bel.startswith(HCLK_GROUP),
            "la carga no está en el grupo HCLK superior previsto")
    require(divider["connections"]["HCLKIN"] == pll["connections"]["CLKOUT"],
            "el HCLK superior no recibe CLKOUT")
    require(cells["witness_byte"]["connections"]["CLK"] == pll["connections"]["CLKOUTD"],
            "el registro de prueba de byte no recibe CLKOUTD")
    require(cells["witness_divided"]["connections"]["CLK"] == divider["connections"]["CLKOUT"],
            "no se conservó la carga interna del divisor de prueba")
    log = (build / "probe.log").read_text()
    for name in ("ref_to_pll", "CLK_BYTE", "CLK_HS", "hclk_divided"):
        require(f"'{name}' net was routed using global resources only." in log,
                f"{name}: no se confirmó ruta global")
    hs_route = mod["netnames"]["CLK_HS"]["attributes"]["ROUTING"]
    require(f"{bel}_HCLKIN" in hs_route, "falta HCLKIN en la ruta de CLK_HS")
    print(f"PASS enrutado: pin 11 → {pll['attributes']['NEXTPNR_BEL']}; "
          f"CLK_BYTE por GCLK y CLK_HS hasta {bel}.")
    print("Sonda interna: no comprueba FCLK/PCLK de los serializadores ni cierre temporal.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "verify"))
    parser.add_argument("build", type=Path)
    args = parser.parse_args()
    {"prepare": prepare, "verify": verify}[args.action](args.build)
