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
    require(counts["TLVDS_TBUF"] == 3, "Se requieren tres TLVDS_TBUF HS")
    require(counts["IBUF"] == 1, "Se requiere un IBUF de reloj")
    # Son marcadores de pad que nextpnr fusiona con los TLVDS_TBUF, no seis
    # drivers independientes. pack_diff_iobs() requiere precisamente esta red.
    require(counts["OBUF"] == 6, "Se requieren seis marcadores OBUF de pad HS")
    require(counts["IOBUF"] == 0, "IOBUF inesperado")

    high = {"1"}
    for cell in cells.values():
        if cell["type"] == "VCC":
            high.update(cell["connections"]["V"])

    ports = top["ports"]
    output_buffers = {
        tuple(cell["connections"]["I"]): cell["connections"]["O"]
        for cell in cells.values() if cell["type"] == "OBUF"
    }
    for lane in range(3):
        hs = cells[f"hs_off_buf_{lane}"]["connections"]
        require(set(hs["OEN"]) <= high, f"HS {lane}: OEN no está fijado a uno")
        require(output_buffers.get(tuple(hs["O"])) == [ports["dsi_hs_p"]["bits"][lane]],
                "Pad HS P incorrecto")
        require(output_buffers.get(tuple(hs["OB"])) == [ports["dsi_hs_n"]["bits"][lane]],
                "Pad HS N incorrecto")
        for polarity in ("p", "n"):
            lp = cells[f"lp_{polarity}_buf_{lane}"]["connections"]
            require(lp["O"] == [ports[f"dsi_lp_{polarity}"]["bits"][lane]],
                    f"Pad LP {lane}/{polarity} incorrecto")
            if lane > 0:
                require(set(lp["I"]) <= high, "D1/CLK no están fijados a LP-11")
    print("PASS: 6 TBUF LP, 3 TLVDS_TBUF HS con OEN=1 y sus marcadores de pad")


def check_routed(path):
    design = json.loads(Path(path).read_text())
    top = design["modules"]["top"]
    high = top["netnames"]["$PACKER_VCC"]["bits"]
    diff = [cell for cell in top["cells"].values()
            if cell.get("parameters", {}).get("DIFF_TYPE") == "TLVDS_TBUF"]
    if len(diff) != 6:
        raise ValueError("Deben conservarse los seis pads diferenciales HS")
    positive = [cell for cell in diff if cell["parameters"]["DIFF"] == "P"]
    negative = [cell for cell in diff if cell["parameters"]["DIFF"] == "N"]
    if len(positive) != 3 or len(negative) != 3:
        raise ValueError("Pares HS incompletos")
    for cell in diff:
        attrs = cell["attributes"]
        if "NEXTPNR_BEL" not in attrs or "&PULL_MODE=NONE" not in attrs:
            raise ValueError("Pad HS sin ubicación o sin PULL_MODE=NONE")
    for cell in positive:
        # En el par físico OEN lo gobierna la rama P tras pack_diff_iobs().
        if cell["connections"]["OEN"] != high:
            raise ValueError("Un driver HS no conserva OEN=1 tras place-and-route")
    lp = [cell for cell in top["cells"].values() if cell["type"] == "TBUF"]
    if len(lp) != 6:
        raise ValueError("Faltan pads LP en el diseño enrutado")
    for cell in lp:
        attrs = cell["attributes"]
        if not {"NEXTPNR_BEL", "&IO_TYPE=LVCMOS12", "&PULL_MODE=NONE"} <= attrs.keys():
            raise ValueError("Pad LP sin restricciones esperadas")
    print("PASS: diseño enrutado conserva los doce pads y los tres drivers HS apagados")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("json")
    parser.add_argument("--routed", action="store_true")
    args = parser.parse_args()
    (check_routed if args.routed else check_netlist)(args.json)
