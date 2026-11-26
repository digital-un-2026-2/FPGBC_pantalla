"""Audita conectividad de la sonda y, opcionalmente, fusibles en memoria."""

import argparse
from hashlib import sha256
import inspect
import json
from pathlib import Path
import re
import sys
from unittest.mock import patch

from apycula import gowin_pack as pack

from gateware.tests.review_fuses import fuses_present, pack_to_tilemap, verify_iob_encoding
from gateware.tests.review_io import DEVICE, expected_bel, io_attribute, load_reference
from phy.dphy_pads.tools.apicula_mixed import mixed_place


PINOUT = {
    "D0": ((122, 123), (117, 116)),
    "D1": ((124, 125), (115, 114)),
    "CLK": ((126, 128), (113, 112)),
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def route_pips(net):
    return net["attributes"]["ROUTING"].split(";")[1::3]


def verify_serial_route(cells, pair, site, fclk, byte, half):
    if pair == "CLK":
        name, pclk, primitive, outmode, sinks = "forwarded.serializer", half, "OSER4", "ODDRX2", ("CLK0",)
    else:
        name, pclk, primitive, outmode, sinks = f"{pair.lower()}.serializer", byte, "OSER8", "ODDRX4", ("CLK0", "CLK1")
    serializer = cells[name]
    conn = serializer["connections"]
    require(serializer["type"] == primitive
            and serializer["attributes"]["NEXTPNR_BEL"] == f"{site}/IOLOGICAO"
            and serializer["parameters"]["OUTMODE"] == outmode and not conn["Q0"],
            f"{pair}: serializador fuera de IOLOGIC o Q0 no absorbido")
    require(conn["FCLK"] == fclk["bits"]
            and any(re.fullmatch(fr"{site}/FCLKA/HCLK_OUT[13]", pip) for pip in route_pips(fclk)),
            f"{pair}: FCLK no llega por HCLK")
    require(conn["PCLK"] == pclk["bits"]
            and all(any(re.fullmatch(fr"{site}/{sink}/GB[0-7]0", pip)
                        for pip in route_pips(pclk)) for sink in sinks),
            f"{pair}: PCLK no llega por GCLK")
    if primitive == "OSER8":
        aux = cells[f"{name}_aux$"]
        require(aux["type"] == "IOLOGIC_DUMMY"
                and aux["attributes"]["NEXTPNR_BEL"] == f"{site}/IOLOGICBO"
                and aux["connections"]["PCLK"] == byte["bits"],
                f"{pair}: falta IOLOGIC auxiliar del OSER8")


def verify_route(top, db, variant):
    cells, nets = top["cells"], top["netnames"]
    require(top["settings"]["packer.partno"] == DEVICE, "Dispositivo enrutado incorrecto")
    package, device, _ = db.packages[DEVICE]
    pins = db.pinout[device][package]
    pads = {}

    fclk, byte, half = (nets[name] for name in ("CLK_HS", "CLK_BYTE", "forwarded.PCLK_110"))
    pll = cells["clocks.pll"]["connections"]
    divider = cells["forwarded.divider"]
    require(pll["CLKOUT"] == fclk["bits"] and pll["CLKOUTD"] == byte["bits"]
            and divider["type"] == "CLKDIV" and divider["parameters"]["DIV_MODE"] == "2"
            and divider["connections"]["HCLKIN"] == fclk["bits"]
            and divider["connections"]["CLKOUT"] == half["bits"],
            "Fuentes de reloj incorrectas")

    for pair, branches in PINOUT.items():
        group = "clk" if pair == "CLK" else "dat"
        for bank, numbers in enumerate(branches):
            branch = ("LP", "HS")[bank]
            oen = nets[f"pads.oen_{branch.lower()}_{group}"]
            for side, number in zip("PN", numbers):
                port = f"{branch}_{pair}_{side}"
                bits = top["ports"][port]["bits"]
                pad, = (cell for cell in cells.values() if cell["connections"].get("O") == bits)
                pin_name = pins[str(number)][0]
                bel, row, col, polarity = expected_bel(db, pin_name)
                params, attrs, conn = pad["parameters"], pad["attributes"], pad["connections"]
                require(attrs["NEXTPNR_BEL"] == bel and db.pin_bank[pin_name] == bank,
                        f"{port}: pin, BEL o banco incorrecto")
                require(io_attribute(pad, "IO_TYPE") == ("LVCMOS12", "LVDS25")[bank]
                        and io_attribute(pad, "PULL_MODE") == "NONE",
                        f"{port}: estándar o pulls incorrectos")
                key = row, col, f"IOB{polarity}"
                require(key not in pads, f"{port}: pad duplicado")
                pads[key] = (port, number, bank)
                site = bel.split("/")[0]

                if branch == "HS":
                    require(params.get("DIFF_TYPE") == "TLVDS_TBUF" and params.get("DIFF") == side
                            and polarity == ("A" if side == "P" else "B"),
                            f"{port}: falta fusión diferencial en el lado correcto")
                    if side == "N":
                        require(not conn.get("OEN"), f"{port}: driver diferencial N independiente")
                        continue
                    require(int(params["IOLOGIC_IOB"], 2) == 1 and not conn["I"],
                            f"{port}: el diferencial no recibe la señal serial por IOLOGIC local")
                    verify_serial_route(cells, pair, site, fclk, byte, half)
                else:
                    require(pad["type"] == "TBUF" and io_attribute(pad, "DRIVE") == "8"
                            and io_attribute(pad, "SLEW_RATE") == "FAST",
                            f"{port}: no es el TBUF LP solicitado")

                oe_wire = db[row, col].bels[f"IOB{polarity}"].portmap["OE"]
                require(conn["OEN"] == oen["bits"] and params.get("NET_OEN") == "NET"
                        and any(pip.startswith(f"{site}/{oe_wire}/") for pip in route_pips(oen)),
                        f"{port}: el OEN dinámico no llega al pin físico")

    iso = nets["ISO"]["bits"]
    outputs = set()
    for name in ("oen_lp_dat", "oen_lp_clk", "oen_hs_dat", "oen_hs_clk"):
        oen = nets[f"pads.{name}"]["bits"]
        lut, = (c for c in cells.values() if c["type"].startswith("LUT")
                and c["connections"].get("F") == oen)
        index, = (int(port[1:]) for port, signal in lut["connections"].items()
                  if port.startswith("I") and signal == iso)
        table = int(lut["parameters"]["INIT"], 2)
        entries = range(len(lut["parameters"]["INIT"]))
        require(all((table >> i) & 1 for i in entries if i & (1 << index))
                and not all((table >> i) & 1 for i in entries if not i & (1 << index)),
                f"{name}: ISO no domina el OEN activo en bajo")
        outputs.update(oen)
    require(len(outputs) == 4, "Se fusionaron OEN de grupos distintos")

    forwarded = cells["forwarded.serializer"]
    require((forwarded["attributes"].get("IODELAY"),
             int(forwarded["parameters"].get("C_STATIC_DLY", "0"), 2))
            == (("OUT", 32) if variant == "delay" else (None, 0)),
            "Configuración inesperada del IODELAY de CLK")
    return pads


def audit_fuses(path, pads, provenance):
    """Comprueba atributos y fusibles seleccionados por el codificador adaptado."""
    require(len(pads) == 12, "Auditoría incompleta: se requieren los doce pads del PHY")
    observations, bank_choices, bank_io_choices = {}, {}, {}
    get_fuses = pack.get_longval_fuses
    get_bank_fuses, get_bank_io_fuses = pack.get_bank_fuses, pack.get_bank_io_fuses
    place, adapted_sha256 = mixed_place()

    def observe(db, tile_type, attributes, table):
        bits = get_fuses(db, tile_type, attributes, table)
        frame = inspect.currentframe().f_back
        if frame.f_code is place.__code__ and table in {"IOBA", "IOBB"}:
            local = frame.f_locals
            key = (local.get("row"), local.get("col"), table)
            if key in pads and local.get("iob_attrs") is attributes:
                require(key not in observations, f"Apicula reprocesó {pads[key][0]}")
                effective = dict(local["atr"])
                verify_iob_encoding(db, effective, attributes)
                require((local["fuse_row"], local["fuse_col"]) == key[:2],
                        f"{pads[key][0]}: fusibles fuera de la tesela del pad")
                observations[key] = (effective, set(bits))
        return bits

    def observe_bank(db, tile_type, attributes, table, bank):
        bits = get_bank_fuses(db, tile_type, attributes, table, bank)
        if bank in {0, 1}:
            frame = inspect.currentframe().f_back
            local = frame.f_locals
            require(frame.f_code is place.__code__ and table == "BANK"
                    and local["bank_attrs"] is attributes
                    and (local["brow"], local["bcol"]) == db.bank_tiles[bank],
                    f"BANK{bank}: origen de fusibles inesperado")
            require(bank not in bank_choices, f"Apicula reprocesó el banco {bank}")
            effective = {key: value for key, value in local["in_bank_attrs"].items()
                         if key in {"BANK_VCCIO", "IO_TYPE", "LVDS_OUT", "DRIVE",
                                    "OPENDRAIN", "PULL_STRENGTH"}}
            verify_iob_encoding(db, effective, attributes)
            bank_choices[bank] = (effective["BANK_VCCIO"], attributes, set(bits))
        return bits

    def observe_bank_io(db, tile_type, attributes):
        bits = get_bank_io_fuses(db, tile_type, attributes)
        frame = inspect.currentframe().f_back
        bank = frame.f_locals.get("bank")
        if frame.f_code is place.__code__ and bank in {0, 1}:
            require(bank in bank_choices and bank not in bank_io_choices
                    and bank_choices[bank][1] is attributes,
                    f"BANK{bank}: selección complementaria sin evidencia de banco")
            bank_io_choices[bank] = set(bits)
        return bits

    with (
        patch.object(pack, "place", new=place),
        patch.object(pack, "get_longval_fuses", new=observe),
        patch.object(pack, "get_bank_fuses", new=observe_bank),
        patch.object(pack, "get_bank_io_fuses", new=observe_bank_io),
    ):
        result = pack_to_tilemap(path)
    require(observations.keys() == pads.keys()
            and bank_choices.keys() == bank_io_choices.keys() == {0, 1},
            "Auditoría incompleta: faltan pads, bancos o el mapa anterior a serialización")

    report = {"bitstream_written": False, "electrical_validation": "NOT_MEASURED",
              "routed_json_sha256": sha256(path.read_bytes()).hexdigest(),
              "adapted_place_sha256": adapted_sha256,
              **provenance, "pads": {}, "banks": {}, "errors": []}
    for key, (port, number, bank) in pads.items():
        attrs, bits = observations[key]
        expected = {
            "IO_TYPE": ("LVCMOS12", "LVDS25")[bank],
            "BANK_VCCIO": ("1.2", "2.5")[bank],
            "PULLMODE": "NONE",
            "OPENDRAIN": "OFF",
            "ODMUX_1": "UNKNOWN",
            "ODMUX": "TRIMUX",
            "TRIMUX_PADDT": "SIG",
            "TO": "SIG",
            "LVDS_OUT": ("OFF", "ON")[bank],
        }
        expected.update({"DIFFRESISTOR": "OFF"} if bank else {"DRIVE": "8", "SLEWRATE": "FAST"})
        present = bool(bits) and fuses_present(result["tilemap"][key[:2]], bits)
        report["pads"][port] = {"pin": number, "attributes": attrs,
                                "selected_fuse_count": len(bits), "selected_fuses_present": present}
        if not present:
            report["errors"].append(f"{port}: faltan fusibles seleccionados")
        for name, value in expected.items():
            if attrs.get(name) != value:
                report["errors"].append(f"{port}: {name}={attrs.get(name)}, esperado {value}")
    for bank, (voltage, _, bits) in bank_choices.items():
        selected = bits | bank_io_choices[bank]
        tile = result["tilemap"][result["db"].bank_tiles[bank]]
        present = bool(bits) and fuses_present(tile, selected)
        report["banks"][bank] = {"BANK_VCCIO": voltage, "selected_fuse_count": len(selected),
                                 "selected_fuses_present": present}
        if voltage != ("1.2", "2.5")[bank] or not present:
            report["errors"].append(f"BANK{bank}: tensión o fusibles de banco incorrectos ({voltage} V)")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("variant", choices=("direct", "delay"))
    parser.add_argument("--fuses", action="store_true")
    parser.add_argument("--phy-prefix", default="")
    args = parser.parse_args()
    path = args.build / "probe_routed.json"
    top = json.loads(path.read_text())["modules"]["top"]
    if args.phy_prefix:
        for key in ("cells", "netnames"):
            top[key] = {name.removeprefix(args.phy_prefix): entry for name, entry in top[key].items()}
    db, _, provenance = load_reference()
    pads = verify_route(top, db, args.variant)
    print(f"PASS {args.variant}: 6 TBUF, 3 TLVDS_TBUF, Q0 locales, OEN dinámicos e ISO", flush=True)
    if args.fuses:
        report = audit_fuses(path, pads, provenance)
        target = args.build / "fuse_review.json"
        target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
        if report["errors"]:
            for error in report["errors"]:
                print(error, file=sys.stderr)
            print(f"FAIL {args.variant} fusibles: {target}", file=sys.stderr)
            return 1
        print(f"PASS {args.variant} fusibles: {target}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, ValueError) as error:
        raise SystemExit(f"Error en la sonda DPHY_PADS: {error}") from error
