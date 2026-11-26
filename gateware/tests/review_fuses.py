"""Audita fusibles Apicula; solo serializa si se solicita -o y pasan los controles."""

import argparse
from collections import Counter
from functools import partial
from hashlib import sha256
import inspect
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
from unittest.mock import patch

from apycula import attrids, gowin_pack as pack
from apycula import bitmatrix

from gateware.tests.review_io import BACKLIGHT_PINS, DEVICE, expected_bel, reviewed_pinout


class _StopBeforeSerialization(Exception):
    pass


def _register_used_bels(get_bels, data):
    # Apicula 0.32 reprocesa como libres los pads sin registrar. También se
    # registra N de un diferencial aunque place() lo configure desde P.
    frame = inspect.currentframe().f_back
    db = frame.f_locals.get("db")
    if frame.f_code is not pack.place.__code__ or db is None:
        raise ValueError("No se pudo identificar la base usada por place()")
    for item in get_bels(data):
        typ, row, col, num, *_ = item
        if typ in {"IBUF", "OBUF", "TBUF", "IOBUF"}:
            bank = pack.chipdb.loc2bank(db, row - 1, col - 1)
            name = pack.rc2tbrl(db, row, col, num)
            pack._banks.setdefault(bank, pack.BankDesc(None, set())).bels.add(name)
        yield item


def verify_iob_encoding(db, effective, attributes):
    encoded = set()
    for name, value in effective.items():
        if name in attrids.iob_attrids:
            pack.add_attr_val(db, "IOB", encoded, attrids.iob_attrids[name],
                              attrids.iob_attrvals[value])
    if encoded != attributes:
        raise ValueError("Los atributos observados no coinciden con los que codificó Apicula")


def fuses_present(tile, bits):
    return all(tile[row][col] == 1 for row, col in bits)


def pack_to_tilemap(path):
    """Ejecuta el packer con los observadores instalados hasta el mapa en memoria."""
    final = {}

    def stop(db, tilemap):
        local = inspect.currentframe().f_back.f_locals
        final.update(db=db, tilemap=tilemap, extra_slots=local["extra_slots"])
        raise _StopBeforeSerialization

    def forbid(*args, **kwargs):
        raise RuntimeError("La auditoría no permite escribir un bitstream")

    temp_base = Path("/tmp/opencode")
    with TemporaryDirectory(prefix="fpgbc-fuse-review-",
                            dir=temp_base if temp_base.is_dir() else None) as temp:
        suppressed = Path(temp) / "NO_GENERAR.fs"
        with (
            patch.object(sys, "argv", ["review", str(path), "-d", "GW2A-18C",
                                       "-o", str(suppressed)]),
            patch.object(pack, "get_bels", new=partial(_register_used_bels, pack.get_bels)),
            patch.object(pack, "_banks", {}),
            patch.object(pack, "_io_bels", {}),
            patch.object(pack, "_pip_bels", []),
            patch.object(pack, "adc_iolocs", {}),
            patch.object(pack, "_used_ihclk_wires", set()),
            patch.object(pack.chipdb, "fuse_bitmap", new=stop),
            patch.object(pack.bslib, "write_bitstream", new=forbid),
            patch.object(pack.bslib, "write_bitstream_with_bsram_init", new=forbid),
        ):
            try:
                pack.main()
            except _StopBeforeSerialization:
                pass
        if not final or suppressed.exists():
            raise RuntimeError("No se detuvo correctamente antes de serializar")
    return final


def validate_input(design):
    top = design["modules"]["top"]
    pinout = reviewed_pinout(top["ports"].keys())
    if top["ports"].keys() != pinout.keys():
        raise ValueError("El empaquetador solo admite los puertos del top LP revisado")
    io_types = {"IBUF", "OBUF", "TBUF", "IOBUF", "TLVDS_TBUF", "TLVDS_OBUF"}
    counts = Counter(cell["type"] for cell in top["cells"].values()
                     if cell["type"] in io_types)
    expected = Counter({"IBUF": 2, "TBUF": 6, "IOBUF": 6})
    if BACKLIGHT_PINS.keys() <= pinout.keys():
        expected["OBUF"] = 2
    if counts != expected:
        raise ValueError(f"Buffers del top LP incorrectos: {counts}, esperados {expected}")
    return pinout


def validate_attributes(pads, pinout=None):
    if pinout is None:
        pinout = reviewed_pinout({pad["port"] for pad in pads})
    errors = []
    expected_pads = {(port, pin) for port, pins in pinout.items() for pin in pins}
    if len(pads) != len(expected_pads) or {(pad["port"], pad["pin"]) for pad in pads} != expected_pads:
        errors.append("No se verificaron todos los pads del top LP")
    for pad in pads:
        pin, port, attrs = pad["pin"], pad["port"], pad["effective_attributes"]
        if not pad["selected_fuses_present"]:
            errors.append(f"Pin {pin}: fusibles seleccionados ausentes del mapa final")
        if port.startswith("dsi_") or port in BACKLIGHT_PINS:
            for key, value in {"PULLMODE": "NONE", "LVDS_OUT": "OFF", "OPENDRAIN": "OFF"}.items():
                if attrs.get(key) != value:
                    errors.append(f"Pin {pin}: {key} no conserva {value}")
        if port.startswith("dsi_hs"):
            expected = {"IO_TYPE": "LVCMOS25", "BANK_VCCIO": "2.5", "ODMUX_1": "0"}
        elif port.startswith("dsi_lp"):
            expected = {
                "IO_TYPE": "LVCMOS12", "BANK_VCCIO": "1.2",
                "DRIVE": "8", "SLEWRATE": "FAST",
            }
            # Variante aislada: OFF estático. Variante activa: usar el mux OEN.
            if attrs.get("ODMUX_1") != "0" and (
                attrs.get("ODMUX") != "TRIMUX" or attrs.get("TO") != "SIG"
            ):
                errors.append(f"Pin {pin}: habilitación LP no es OFF ni OEN dinámico")
        elif port in BACKLIGHT_PINS:
            expected = {"IO_TYPE": "LVCMOS33", "BANK_VCCIO": "3.3", "ODMUX_1": "1"}
        else:
            expected = {"IO_TYPE": "LVCMOS33", "DRIVE": "0"}
            if port == "global_rst_n":
                expected["PULLMODE"] = "UP"
        for key, value in expected.items():
            if attrs.get(key) != value:
                errors.append(f"Pin {pin}: {key}={attrs.get(key)}, esperado {value}")
    return errors


def probe(path, output=None):
    path = Path(path).resolve()
    source = path.read_bytes()
    pinout = validate_input(json.loads(source))
    captures = {}
    original = pack.get_longval_fuses

    def trace(db, tile_type, attributes, table):
        bits = original(db, tile_type, attributes, table)
        frame = inspect.currentframe().f_back
        if frame.f_code is not pack.place.__code__ or not table.startswith("IOB"):
            return bits
        local = frame.f_locals
        # La interfaz privada se verifica contra los argumentos reales. Si
        # cambia Apicula, fallar en vez de producir una aprobación inventada.
        effective = local.get("atr")
        if not isinstance(effective, dict) or local.get("iob_attrs") is not attributes:
            return bits
        package, variant, _ = db.packages[DEVICE]
        locations = {}
        for port, numbers in pinout.items():
            for index, number in enumerate(numbers):
                pin_name = db.pinout[variant][package][str(number)][0]
                _, row, col, polarity = expected_bel(db, pin_name)
                locations[row, col, f"IOB{polarity}"] = (number, port, index)
        key = local.get("row"), local.get("col"), table
        if key not in locations:
            return bits
        # Evitar confundir variables residuales del bucle de pines no usados.
        verify_iob_encoding(db, effective, attributes)
        if key in captures:
            raise ValueError(f"El packer reescribió un pad esperado: {key}")
        number, port, index = locations[key]
        captures[key] = {
            "pin": number, "port": port, "bit": index,
            "effective_attributes": dict(effective), "fuses": set(bits),
        }
        return bits

    with patch.object(pack, "get_longval_fuses", new=trace):
        final = pack_to_tilemap(path)

    pads = []
    for (row, col, _), captured in captures.items():
        entry = {key: value for key, value in captured.items() if key != "fuses"}
        entry["selected_fuse_count"] = len(captured["fuses"])
        entry["selected_fuses_present"] = fuses_present(final["tilemap"][row, col], captured["fuses"])
        pads.append(entry)
    pads.sort(key=lambda entry: entry["pin"])
    errors = validate_attributes(pads, pinout)
    packer_path = Path(pack.__file__)
    report = {
        "status": "PAD_FUSE_CHECKS_PASS" if not errors else "PAD_FUSE_CHECKS_FAIL",
        "routed_json_sha256": sha256(source).hexdigest(),
        "packer_sha256": sha256(packer_path.read_bytes()).hexdigest(),
        "checker_sha256": sha256(Path(__file__).read_bytes()).hexdigest(),
        "bitstream_written": False, "hardware_accessed": False,
        "used_pad_registry_workaround": True,
        "electrical_validation": "NOT_MEASURED",
        "pads": pads, "errors": errors,
        "scope": "Atributos solicitados al codificador y sus fusibles en el mapa en memoria; "
                 "no verificación eléctrica ni decodificación independiente del fabricante",
    }
    if output is not None:
        if errors:
            raise ValueError(f"No se puede serializar: {errors}")
        output = Path(output)
        if output.exists() or output.with_suffix(output.suffix + ".review.json").exists():
            raise FileExistsError("No se sobrescriben artefactos de una revisión anterior")
        if pack.bsram_init_map is not None:
            raise ValueError("Este empaquetador limitado al top LP no admite inicialización BSRAM")
        main_map = pack.chipdb.fuse_bitmap(final["db"], final["tilemap"])
        pack.header_footer(final["db"], main_map, False)
        pack.bslib.write_bitstream(
            str(output), main_map, final["db"].cmd_hdr, final["db"].cmd_ftr,
            False, final["extra_slots"],
        )
        readback, _, _, _ = pack.bslib.read_bitstream(str(output))
        if bitmatrix.shape(readback) != bitmatrix.shape(main_map) or bitmatrix.any(
            bitmatrix.xor(readback, main_map)
        ):
            raise ValueError("El archivo serializado no coincide con los fusibles comprobados")
        report.update(
            bitstream_written=True,
            bitstream_sha256=sha256(output.read_bytes()).hexdigest(),
            serialized_bitmap_roundtrip=True,
        )
        output.with_suffix(output.suffix + ".review.json").write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        )
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("routed_json")
    parser.add_argument("-d", "--device", choices=["GW2A-18C"], default="GW2A-18C")
    parser.add_argument("-o", "--output", help="Generar candidato NO validado eléctricamente")
    args = parser.parse_args()
    report = probe(args.routed_json, args.output)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 1 if report["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
