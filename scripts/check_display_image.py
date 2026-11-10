"""Check the implemented autonomous image: pins, enabled HS, PLL and timing."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from check_display_board import check_pins


def check(directory):
    directory = Path(directory)
    gateware = check_pins(directory, "display_image")
    manifest = json.loads((directory / "image_manifest.json").read_text())
    if not all(manifest.get(k) is True for k in ("autostart", "hs_enabled", "implementation_complete")):
        raise ValueError("Se requiere una implementación con imagen y HS activos")
    digest = hashlib.sha256((gateware / "display_image.fs").read_bytes()).hexdigest()
    if digest != manifest["bitstream_sha256"]:
        raise ValueError("El bitstream no coincide con el manifiesto")
    netlist = next(iter(json.loads((gateware / "display_image_routed.json").read_text())["modules"].values()))
    cells = list(netlist["cells"].values())
    counts = Counter(c["type"] for c in cells)
    if counts["OSER8"] != 3 or counts["rPLL"] != 1 or counts["TBUF"] != 6 or counts["SP"] < 1:
        raise ValueError(f"Recursos de vídeo incompletos: {counts}")
    pll = next(c for c in cells if c["type"] == "rPLL")["parameters"]
    if (int(pll["FBDIV_SEL"], 2) != 5 or int(pll["IDIV_SEL"], 2) != 0 or
        int(pll["ODIV_SEL"], 2) != 4 or int(pll["DYN_SDIV_SEL"], 2) != 4 or
        pll["PSDA_SEL"].strip() != manifest["pll_phase"]):
        raise ValueError("PLL distinto del perfil de 60MHz/480Mbit/s")
    constants = [["0"], ["1"], netlist["netnames"]["$PACKER_VCC"]["bits"],
                 netlist["netnames"]["$PACKER_GND"]["bits"]]
    hs = [c for c in cells if c["parameters"].get("DIFF") == "P"]
    if len(hs) != 3 or any(c["connections"].get("OEN") in constants or
                           not c["connections"].get("OEN") for c in hs):
        raise ValueError("HS debe tener habilitación dinámica en los tres pares")
    for cell in cells:
        if cell["type"] == "TBUF" and not all(attr in cell["attributes"] for attr in
            ("&IO_TYPE=LVCMOS12", "&DRIVE=4", "&PULL_MODE=NONE")):
            raise ValueError("Opciones eléctricas LP perdidas durante P&R")
    clocks = json.loads((gateware / "display_image.report").read_text())["fmax"]
    if not clocks or not any("byte_clk" in name for name in clocks):
        raise ValueError("Falta comprobación de timing del reloj de byte")
    if any(c["constraint"] < 60 or c["achieved"] < c["constraint"] for c in clocks.values()):
        raise ValueError(f"No cumple timing a 60MHz: {clocks}")
    print(f"PASS active image: SHA256, ROM, 3 OSER8, dynamic HS enables, 60MHz PLL; timing {clocks}")
    print("Hardware LCD reception and serializer clock/data phase remain unverified.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    check(parser.parse_args().directory)
