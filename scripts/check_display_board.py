"""Check generated pin constraints, and optionally an implemented LPDT bitstream."""
import argparse
import hashlib
import json
from pathlib import Path
import re


def check_pins(directory, build_name="display_board"):
    root = Path(__file__).resolve().parents[1]
    directory = Path(directory)
    gateware = directory / "gateware"
    # Independent reference: the board continuity table, not the Python pin map.
    rows = re.findall(r"\| (CLK|D0|D1)_([PN]) \| (\d+) \| 100 Ω \| (\d+) \|",
                      (root / "docs" / "hardware.md").read_text())
    expected = {"clk40": "11", "serial_rx": "28", "serial_tx": "27"}
    for lane, polarity, lp, hs in rows:
        index = {"D0": 0, "D1": 1, "CLK": 2}[lane]
        expected[f"dsi_lp_{polarity.lower()}[{index}]"] = lp
        expected[f"dsi_hs_{polarity.lower()}[{index}]"] = hs
    if len(expected) != 15:
        raise ValueError("No se pudo reconstruir la tabla de continuidad de la placa")
    cst = (gateware / f"{build_name}.cst").read_text()
    actual = {}
    for name, pins in re.findall(r'IO_LOC "([^"]+)" ([\d,]+);', cst):
        values = pins.split(",")
        actual[name] = values[0]
        if len(values) == 2:
            actual[name.replace("_p[", "_n[")] = values[1]
    if actual != expected or len(set(actual.values())) != 15:
        raise ValueError(f"Pinout incorrecto: {actual}")
    for name, options in re.findall(r'IO_PORT "([^"]+)" ([^;]+);', cst):
        if name.startswith("dsi_lp_") and not all(value in options for value in ("LVCMOS12", "PULL_MODE=NONE", "DRIVE=4")):
            raise ValueError(f"Opciones LP incorrectas: {name}")
        if name.startswith("dsi_hs_") and not all(value in options for value in ("LVDS25", "PULL_MODE=NONE")):
            raise ValueError(f"Opciones HS incorrectas: {name}")
    script = gateware / f"build_{build_name}.sh"
    if script.exists() and "--timing-allow-fail" in script.read_text():
        raise ValueError("La implementación no debe permitir fallos de timing")
    if not (gateware / f"{build_name}.sdc").exists():
        raise ValueError("Falta el SDC de referencia")
    print("PASS board pinout: 15 package pins, LP LVCMOS12/4mA, HS LVDS25, pulls NONE")
    return gateware


def check(directory, implemented=False):
    directory = Path(directory)
    gateware = check_pins(directory)
    manifest = json.loads((directory / "board_manifest.json").read_text())
    if implemented:
        if manifest["mode"] != "lpdt" or not manifest["implementation_complete"]:
            raise ValueError("Esta comprobación de implementación requiere el bitstream LPDT")
        digest = hashlib.sha256((gateware / "display_board.fs").read_bytes()).hexdigest()
        if digest != manifest["bitstream_sha256"]:
            raise ValueError("El bitstream no coincide con el manifiesto")
        netlist = next(iter(json.loads((gateware / "display_board_routed.json").read_text())["modules"].values()))
        cells = netlist["cells"]
        if any(cell["type"] in ("rPLL", "PLLVR", "OSER8") for cell in cells.values()):
            raise ValueError("LPDT no debe depender del PLL/serializador HS")
        vcc = netlist["netnames"]["$PACKER_VCC"]["bits"]
        hs_positive = [cell for cell in cells.values() if cell["parameters"].get("DIFF") == "P"]
        if len(hs_positive) != 3 or any(cell["connections"].get("OEN") != vcc for cell in hs_positive):
            raise ValueError("Los tres drivers diferenciales deben permanecer deshabilitados")
        for cell in cells.values():
            if cell["type"] == "TBUF":
                if not all(attr in cell["attributes"] for attr in ("&IO_TYPE=LVCMOS12", "&DRIVE=4", "&PULL_MODE=NONE")):
                    raise ValueError("El ruteo no conserva las opciones eléctricas LP")
        report = json.loads((gateware / "display_board.report").read_text())
        clocks = report["fmax"]
        if not clocks or any(clock["constraint"] != 40 or clock["achieved"] < 40 for clock in clocks.values()):
            raise ValueError("Timing incompleto o incumplido a 40MHz")
        print(f"PASS LPDT bitstream: SHA256, HS OEN=1, sin PLL/OSER; timing {clocks}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--implemented", action="store_true")
    args = parser.parse_args()
    check(args.directory, args.implemented)


if __name__ == "__main__":
    main()
