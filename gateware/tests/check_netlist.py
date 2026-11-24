"""Comprueba los pads del JSON sintetizado; no ejecuta herramientas de FPGA."""

import argparse
from collections import Counter
import json
from pathlib import Path


def check_netlist(path):
    design = json.loads(Path(path).read_text())
    top = design["modules"]["fpgbc_lp_init"]
    cells = top["cells"]
    counts = Counter(cell["type"] for cell in cells.values())

    def require(condition, message):
        if not condition:
            raise ValueError(message)

    require(counts["TBUF"] == 6, "Se requieren seis TBUF LP")
    require(counts["TLVDS_TBUF"] == 0, "No se permite un transmisor diferencial HS")
    require(counts["IBUF"] == 2, "Se requieren IBUF de reloj y botón de reset")
    require(counts["OBUF"] == 0, "No se permiten buffers de salida sin OEN")
    require(counts["IOBUF"] == 6, "Se requieren seis IOBUF HS apagados")

    high = {"1"}
    for cell in cells.values():
        if cell["type"] == "VCC":
            high.update(cell["connections"]["V"])

    ports = top["ports"]
    for name, port in (("clk40_buf", "clk40"), ("reset_buf", "global_rst_n")):
        require(cells[name]["type"] == "IBUF" and
                cells[name]["connections"]["I"] == ports[port]["bits"],
                f"Entrada {port} sin su IBUF")
    for lane in range(3):
        for polarity in ("p", "n"):
            hs = cells[f"hs_{polarity}_off_buf_{lane}"]["connections"]
            require(len(hs["OEN"]) == 1 and set(hs["OEN"]) <= high,
                    f"HS {lane}/{polarity}: OEN no está fijado a uno")
            require(hs["IO"] == [ports[f"dsi_hs_{polarity}"]["bits"][lane]],
                    "Pad HS incorrecto")
            lp = cells[f"lp_{polarity}_buf_{lane}"]["connections"]
            require(lp["O"] == [ports[f"dsi_lp_{polarity}"]["bits"][lane]],
                    f"Pad LP {lane}/{polarity} incorrecto")
            if lane > 0:
                require(set(lp["I"]) <= high, "D1/CLK no están fijados a LP-11")
    print("PASS: 6 TBUF LP y 6 IOBUF HS con OEN=1, sin transmisor diferencial")


def check_routed(path):
    design = json.loads(Path(path).read_text())
    top = design["modules"]["top"]
    high = top["netnames"]["$PACKER_VCC"]["bits"]
    for port in ("dsi_lp_p", "dsi_lp_n", "dsi_hs_p", "dsi_hs_n"):
        for bit in top["ports"][port]["bits"]:
            hs = port.startswith("dsi_hs")
            pad_port = "IO" if hs else "O"
            matches = [cell for cell in top["cells"].values()
                       if cell["connections"].get(pad_port) == [bit]]
            if len(matches) != 1 or matches[0]["type"] != ("IOBUF" if hs else "TBUF"):
                raise ValueError("Pad DSI sin buffer independiente")
            cell = matches[0]
            attrs = cell["attributes"]
            standard = "LVCMOS25" if port.startswith("dsi_hs") else "LVCMOS12"
            if not {"NEXTPNR_BEL", f"&IO_TYPE={standard}", "&PULL_MODE=NONE"} <= attrs.keys():
                raise ValueError("Pad DSI sin restricciones esperadas")
            if port.startswith("dsi_hs"):
                if cell["connections"]["OEN"] != high:
                    raise ValueError("Un GPIO de las ramas HS podría conducir")
                if cell["parameters"].get("NET_OEN") != "VCC":
                    raise ValueError("El packer no recibe metadata de HS apagado")
    print("PASS: doce pads enrutados; seis GPIO de ramas HS apagados con NET_OEN=VCC")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json")
    parser.add_argument("--routed", action="store_true")
    args = parser.parse_args()
    (check_routed if args.routed else check_netlist)(args.json)
