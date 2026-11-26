"""Auditoría offline del JSON enrutado. No empaqueta ni accede a hardware."""

import argparse
import ast
from hashlib import sha256
import json
from pathlib import Path
import re

import apycula
from apycula.chipdb import load_chipdb


DEVICE = "GW2AR-LV18EQ144PC8/I7"
PINOUT = {
    "clk40": (11,),
    "global_rst_n": (120,),
    "dsi_lp_p": (122, 124, 126),
    "dsi_lp_n": (123, 125, 128),
    "dsi_hs_p": (117, 115, 113),
    "dsi_hs_n": (116, 114, 112),
}
BACKLIGHT_PINS = {"backlight_en": (46,), "backlight_pwm": (47,)}


def reviewed_pinout(ports):
    if BACKLIGHT_PINS.keys() & ports:
        return {**PINOUT, **BACKLIGHT_PINS}
    return PINOUT


def load_reference():
    directory = Path(apycula.__file__).parent
    database = directory / "GW2A-18C.msgpack.xz"
    packer = directory / "gowin_pack.py"
    # Leer solo el literal: no ejecutar el empaquetador ni sus funciones.
    for node in ast.parse(packer.read_text()).body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id == "_init_io_attrs"
            for target in node.targets
        ):
            defaults = ast.literal_eval(node.value)
            break
    else:
        raise ValueError("No se identificaron los valores por defecto de Apicula")
    provenance = {
        "device": DEVICE,
        "chipdb_sha256": sha256(database.read_bytes()).hexdigest(),
        "packer_sha256": sha256(packer.read_bytes()).hexdigest(),
    }
    return load_chipdb(str(database)), defaults, provenance


def expected_bel(db, pin_name):
    match = re.fullmatch(r"IO([TBLR])(\d+)([AB])", pin_name)
    if match is None:
        raise ValueError(f"Nombre de pad no reconocido: {pin_name}")
    side, index, polarity = match.groups()
    index = int(index) - 1
    positions = {
        "T": (index, 0), "B": (index, db.rows - 1),
        "L": (0, index), "R": (db.cols - 1, index),
    }
    col, row = positions[side]
    return f"X{col}Y{row}/IOB{polarity}", row, col, polarity


def io_attribute(cell, name):
    prefix = f"&{name}="
    values = [key[len(prefix):] for key in cell["attributes"] if key.startswith(prefix)]
    if len(values) > 1:
        raise ValueError(f"Atributo {name} contradictorio")
    return values[0] if values else None


def review(design, db, defaults, provenance):
    top = design["modules"]["top"]
    package, variant, speed = db.packages[DEVICE]
    pins = db.pinout[variant][package]
    high = top["netnames"]["$PACKER_VCC"]["bits"]
    rows, errors, warnings = [], [], []
    missing_drive = False
    missing_slew = False

    for port, pin_numbers in reviewed_pinout(top["ports"].keys()).items():
        bits = top["ports"][port]["bits"]
        if len(bits) != len(pin_numbers):
            raise ValueError(f"Anchura incorrecta: {port}")
        for index, number in enumerate(pin_numbers):
            cell_port = "I" if port in {"clk40", "global_rst_n"} else ("IO" if port.startswith("dsi_hs") else "O")
            matches = [
                (name, cell) for name, cell in top["cells"].items()
                if cell["type"] in {"TBUF", "OBUF", "IBUF", "IOBUF"}
                and cell["connections"].get(cell_port) == [bits[index]]
            ]
            if len(matches) != 1:
                raise ValueError(f"No se identificó un único pad para {port}[{index}]")
            name, cell = matches[0]
            pin_name = pins[str(number)][0]
            bel, row, col, polarity = expected_bel(db, pin_name)
            bank = db.pin_bank[pin_name]
            standard = io_attribute(cell, "IO_TYPE")
            pull = io_attribute(cell, "PULL_MODE")
            actual_bel = cell["attributes"].get("NEXTPNR_BEL")
            entry = {
                "port": port, "bit": index, "pin": number, "pin_name": pin_name,
                "bank": bank, "cell": name, "bel": actual_bel,
                "io_standard": standard, "pull_mode": pull,
            }
            if actual_bel != bel:
                errors.append(f"Pin {number}: BEL {actual_bel}, esperado {bel}")
            if port.startswith("dsi_") and pull != "NONE":
                errors.append(f"Pin {number}: pull no desactivado")

            if port.startswith("dsi_lp"):
                if bank != 0 or standard != "LVCMOS12" or cell["type"] != "TBUF":
                    errors.append(f"Pin {number}: LP no corresponde a BANK0/LVCMOS12/TBUF")
                drive = io_attribute(cell, "DRIVE")
                slew = io_attribute(cell, "SLEW_RATE")
                missing_drive |= drive is None
                missing_slew |= slew is None
                if drive is not None and drive not in {"4", "8"}:
                    errors.append(f"Pin {number}: DRIVE={drive} fuera de DS226 tabla 2-1")
                entry["drive_declared_ma"] = drive
                entry["slew_declared"] = slew
                entry["packer_defaults_if_omitted"] = {
                    "drive_ma": defaults["TBUF"]["DRIVE"],
                    "slew": defaults["TBUF"]["SLEWRATE"],
                }
            elif port.startswith("dsi_hs"):
                params = cell["parameters"]
                if bank != 1 or standard != "LVCMOS25" or cell["type"] != "IOBUF":
                    errors.append(f"Pin {number}: rama HS sin GPIO BANK1/LVCMOS25/IOBUF")
                if "DIFF_TYPE" in params:
                    errors.append(f"Pin {number}: transmisor diferencial inesperado")
                disabled = cell["connections"].get("OEN") == high
                entry["oen_tied_high"] = disabled
                if not disabled:
                    errors.append(f"Pin {number}: rama HS podría conducir")
                entry["packer_net_oen_metadata"] = params.get("NET_OEN")
                if params.get("NET_OEN") != "VCC":
                    errors.append(f"Pin {number}: metadata de apagado HS ausente o contradictoria")
            elif port in BACKLIGHT_PINS:
                if bank != 5 or standard != "LVCMOS33" or cell["type"] != "OBUF" or pull != "NONE":
                    errors.append(f"Pin {number}: backlight sin BANK5/LVCMOS33/OBUF y pull desactivado")
            elif standard != "LVCMOS33" or cell["type"] != "IBUF":
                errors.append(f"{port} sin IBUF/LVCMOS33")
            if port == "global_rst_n" and pull != "UP":
                errors.append("Reset sin pull-up")
            rows.append(entry)

    if missing_drive:
        warnings.append("LP_DRIVE_IMPLICIT: corriente LP no fijada explícitamente")
    if missing_slew:
        warnings.append("LP_SLEW_IMPLICIT: slew LP no fijado; soporte documental pendiente")
    return {
        "status": "STRUCTURAL_ERRORS" if errors else "OFFLINE_CHECKS_ONLY",
        "ready_for_board": False,
        "provenance": {**provenance, "package": package, "variant": variant, "speed": speed},
        "pins": rows, "errors": errors, "warnings": warnings,
        "not_verified": [
            "Niveles, corriente, flancos y sobreimpulso en el panel",
            "Comportamiento durante configuración y de pines ajenos al top",
            "Tiempo y skew externos hasta el receptor; no basta la Fmax interna",
            "Fusibles finales del empaquetador, incluidos OEN y pulls HS",
            "Identificación completa del panel y requisitos de recepción LP",
        ],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("routed_json")
    args = parser.parse_args()
    db, defaults, provenance = load_reference()
    source = Path(args.routed_json).read_bytes()
    provenance["routed_json_sha256"] = sha256(source).hexdigest()
    report = review(json.loads(source), db, defaults, provenance)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
