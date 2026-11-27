"""Audita conectividad de la sonda y, opcionalmente, fusibles en memoria."""

import argparse
from hashlib import sha256
import inspect
import json
from pathlib import Path
import re
import sys
from tempfile import TemporaryDirectory
from unittest.mock import patch

from apycula import gowin_pack as pack
from apycula import bitmatrix

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


def verify_isolated_clock_pad(pad, high):
    require(pad["type"] == "IOBUF"
            and pad["connections"].get("OEN") == high
            and pad["parameters"].get("NET_OEN") == "VCC"
            and "DIFF_TYPE" not in pad["parameters"],
            "DATA_ONLY: HS_CLK no es IOBUF con OEN=1 fijo")


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
    require(variant in {"direct", "delay", "data-only"}, "Variante de PHY desconocida")
    data_only = variant == "data-only"
    cells, nets = top["cells"], top["netnames"]
    require(top["settings"]["packer.partno"] == DEVICE, "Dispositivo enrutado incorrecto")
    package, device, _ = db.packages[DEVICE]
    pins = db.pinout[device][package]
    pads = {}

    fclk, byte = (nets[name] for name in ("CLK_HS", "CLK_BYTE"))
    half = None if data_only else nets["forwarded.PCLK_110"]
    pll = cells["clocks.pll"]["connections"]
    require(pll["CLKOUT"] == fclk["bits"] and pll["CLKOUTD"] == byte["bits"],
            "Fuentes de reloj incorrectas")
    if data_only:
        require(not any(c["type"] in {"OSER4", "CLKDIV", "IODELAY"} for c in cells.values()),
                "DATA_ONLY conserva un generador de CLK externo")
    else:
        divider = cells["forwarded.divider"]
        require(divider["type"] == "CLKDIV" and divider["parameters"]["DIV_MODE"] == "2"
                and divider["connections"]["HCLKIN"] == fclk["bits"]
                and divider["connections"]["CLKOUT"] == half["bits"],
                "Divisor de CLK incorrecto")

    for pair, branches in PINOUT.items():
        group = "clk" if pair == "CLK" else "dat"
        for bank, numbers in enumerate(branches):
            branch = ("LP", "HS")[bank]
            isolated = data_only and pair == "CLK" and branch == "HS"
            oen = None if isolated else (
                nets["ISO"] if data_only and pair == "CLK" and branch == "LP"
                else nets[f"pads.oen_{branch.lower()}_{group}"])
            for side, number in zip("PN", numbers):
                port = f"{branch}_{pair}_{side}"
                bits = top["ports"][port]["bits"]
                pad, = (cell for cell in cells.values()
                        if cell["type"] in {"TBUF", "IOBUF", "TLVDS_TBUF", "OBUF"}
                        and cell["connections"].get("IO" if isolated else "O") == bits)
                pin_name = pins[str(number)][0]
                bel, row, col, polarity = expected_bel(db, pin_name)
                params, attrs, conn = pad["parameters"], pad["attributes"], pad["connections"]
                require(attrs["NEXTPNR_BEL"] == bel and db.pin_bank[pin_name] == bank,
                        f"{port}: pin, BEL o banco incorrecto")
                standard = "LVCMOS25" if isolated else ("LVCMOS12", "LVDS25")[bank]
                require(io_attribute(pad, "IO_TYPE") == standard
                        and io_attribute(pad, "PULL_MODE") == "NONE",
                        f"{port}: estándar o pulls incorrectos")
                key = row, col, f"IOB{polarity}"
                require(key not in pads, f"{port}: pad duplicado")
                pads[key] = (port, number, bank)
                site = bel.split("/")[0]

                if isolated:
                    verify_isolated_clock_pad(pad, nets["$PACKER_VCC"]["bits"])
                    continue
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
                    if data_only and pair == "CLK":
                        require(conn["I"] == nets["DATA_ONLY_LP_CLK"]["bits"],
                                f"{port}: LP_CLK no viene del registro 11→00")

                oe_wire = db[row, col].bels[f"IOB{polarity}"].portmap["OE"]
                require(conn["OEN"] == oen["bits"] and params.get("NET_OEN") == "NET"
                        and any(pip.startswith(f"{site}/{oe_wire}/") for pip in route_pips(oen)),
                        f"{port}: el OEN dinámico no llega al pin físico")

    iso = nets["ISO"]["bits"]
    outputs = set()
    names = ("oen_lp_dat", "oen_lp_clk", "oen_hs_dat") if data_only else (
        "oen_lp_dat", "oen_lp_clk", "oen_hs_dat", "oen_hs_clk")
    for name in names:
        oen = iso if data_only and name == "oen_lp_clk" else nets[f"pads.{name}"]["bits"]
        if data_only and name == "oen_lp_clk":
            require(oen == iso, "DATA_ONLY: LP_CLK no se aísla directamente con ISO")
            outputs.update(oen)
            continue
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
    require(len(outputs) == len(names), "Se fusionaron OEN de grupos distintos")

    if not data_only:
        forwarded = cells["forwarded.serializer"]
        require((forwarded["attributes"].get("IODELAY"),
                 int(forwarded["parameters"].get("C_STATIC_DLY", "0"), 2))
                == (("OUT", 32) if variant == "delay" else (None, 0)),
                "Configuración inesperada del IODELAY de CLK")
    return pads


def serialize_checked(result, output):
    """Publica un candidato nuevo solo si su bitmap releído es idéntico."""
    output = Path(output)
    review = output.with_suffix(".fs.review.json")
    require(not output.exists() and not review.exists(),
            "No se sobrescriben bitstreams ni revisiones anteriores")
    require(pack.bsram_init_map is None, "La serialización auditada no admite BSRAM inicializada")
    main_map = pack.chipdb.fuse_bitmap(result["db"], result["tilemap"])
    pack.header_footer(result["db"], main_map, False)
    with TemporaryDirectory(prefix="mixed-fs-", dir=output.parent) as temp:
        candidate = Path(temp) / "candidate.fs"
        pack.bslib.write_bitstream(str(candidate), main_map, result["db"].cmd_hdr,
                                  result["db"].cmd_ftr, False, result["extra_slots"])
        readback, _, _, _ = pack.bslib.read_bitstream(str(candidate))
        require(bitmatrix.shape(readback) == bitmatrix.shape(main_map)
                and not bitmatrix.any(bitmatrix.xor(readback, main_map)),
                "La lectura del .fs no coincide con el mapa auditado")
        with output.open("xb") as stream:
            stream.write(candidate.read_bytes())
    return {"bitstream_written": True, "hardware_accessed": False,
            "serialized_bitmap_roundtrip": True,
            "bitstream_sha256": sha256(output.read_bytes()).hexdigest(),
            "checker_sha256": sha256(Path(__file__).read_bytes()).hexdigest()}


def audit_fuses(path, pads, provenance, *, board_pads=None, output=None, data_only=False):
    """Comprueba atributos y fusibles seleccionados por el codificador adaptado."""
    require(len(pads) == 12, "Auditoría incompleta: se requieren los doce pads del PHY")
    board_pads = board_pads or {}
    all_pads = {**pads, **board_pads}
    expected_voltages = {0: "1.2", 1: "2.5", **({5: "3.3"} if board_pads else {})}
    if output is not None:
        output = Path(output)
        require(not output.exists() and not output.with_suffix(".fs.review.json").exists(),
                "No se sobrescriben bitstreams ni revisiones anteriores")
    observations, bank_choices, bank_io_choices = {}, {}, {}
    get_fuses = pack.get_longval_fuses
    get_bank_fuses, get_bank_io_fuses = pack.get_bank_fuses, pack.get_bank_io_fuses
    place, adapted_sha256 = mixed_place(data_only=data_only)

    def observe(db, tile_type, attributes, table):
        bits = get_fuses(db, tile_type, attributes, table)
        frame = inspect.currentframe().f_back
        if frame.f_code is place.__code__ and table in {"IOBA", "IOBB"}:
            local = frame.f_locals
            key = (local.get("row"), local.get("col"), table)
            if key in all_pads and local.get("iob_attrs") is attributes:
                require(key not in observations, f"Apicula reprocesó {all_pads[key][0]}")
                effective = dict(local["atr"])
                verify_iob_encoding(db, effective, attributes)
                require((local["fuse_row"], local["fuse_col"]) == key[:2],
                        f"{all_pads[key][0]}: fusibles fuera de la tesela del pad")
                observations[key] = (effective, set(bits))
        return bits

    def observe_bank(db, tile_type, attributes, table, bank):
        bits = get_bank_fuses(db, tile_type, attributes, table, bank)
        if bank in expected_voltages:
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
        if frame.f_code is place.__code__ and bank in expected_voltages:
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
    require(observations.keys() == all_pads.keys()
            and bank_choices.keys() == bank_io_choices.keys() == expected_voltages.keys(),
            "Auditoría incompleta: faltan pads, bancos o el mapa anterior a serialización")

    report = {"bitstream_written": False, "electrical_validation": "NOT_MEASURED",
              "phy_variant": "data-only" if data_only else "forwarded-clock",
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
        if data_only and port.startswith("HS_CLK_"):
            # IOBUF LVCMOS25: apagado estático, NO transmisor LVDS ni GPIO activo.
            expected = {"IO_TYPE": "LVCMOS25", "BANK_VCCIO": "2.5",
                        "PULLMODE": "NONE", "OPENDRAIN": "OFF",
                        "LVDS_OUT": "OFF", "ODMUX_1": "0"}
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
        if voltage != expected_voltages[bank] or not present:
            report["errors"].append(f"BANK{bank}: tensión o fusibles de banco incorrectos ({voltage} V)")
    for key, (port, number, bank) in board_pads.items():
        attrs, bits = observations[key]
        present = bool(bits) and fuses_present(result["tilemap"][key[:2]], bits)
        report["pads"][port] = {"pin": number, "bank": bank, "attributes": attrs,
                                "selected_fuse_count": len(bits), "selected_fuses_present": present}
        # OBUF sin OEN conserva TO=INV del perfil OBUF de Apicula 0.32;
        # SIG corresponde al OEN dinámico de TBUF, no al dato de salida.
        expected = {"IO_TYPE": "LVCMOS33", "BANK_VCCIO": "3.3", "PULLMODE": "NONE",
                    "LVDS_OUT": "OFF", "OPENDRAIN": "OFF", "ODMUX_1": "1", "TO": "INV"}
        if not present or any(attrs.get(name) != value for name, value in expected.items()):
            report["errors"].append(f"{port}: fusibles/atributos de backlight incorrectos")
    if output is not None:
        require(not report["errors"], "\n".join(report["errors"]))
        # Serializar exactamente el mapa observado, no una segunda ejecución
        # del packer. Publicar solo tras releer y comparar todo el bitmap.
        report.update(serialize_checked(result, output))
        with output.with_suffix(".fs.review.json").open("x") as stream:
            stream.write(json.dumps(report, indent=2, ensure_ascii=False) + "\n")
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
