"""Captura interna del secuenciador y motor; no sintetiza ni programa hardware."""

import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import time

from litex import RemoteClient
from litescope.software.driver.analyzer import LiteScopeAnalyzerDriver

try:
    from .test_lpdt_hw import dsi_header_ecc, require, verify_capture
except ImportError:
    from test_lpdt_hw import dsi_header_ecc, require, verify_capture


# Vectores fijos independientes de la ROM, contrastados en el TB integrado.
PACKETS = [bytes.fromhex(s) for s in (
    "05 01 00 10", "15 B0 00 3A", "39 06 00 30 E4 00 00 00 00 08 87 16",
    "39 04 00 2C D0 45 45 71 42 9E", "15 6F 01 2B", "05 11 00 36",
    "39 04 00 2C D0 52 4A 71 1A 14",
    "39 09 00 30 BE FF 0F 00 18 04 04 00 5D E7 C4",
    "15 BB 2F 39", "15 B0 2F 1A", "05 29 00 1C",
)]
WAITS = [800000, 200000, 0, 0, 0, 4800000, 0, 0, 0, 800000, 4800000]
WIDTHS = {"reset_local": 1, "rst_motor": 1, "solicitud": 1,
          "aceptado": 1, "ocupado": 1, "terminado": 1, "longitud": 4,
          "pos": 4, "dato": 8, "d0": 2, "indice": 4, "trigger": 1,
          "fallo": 1, "causa": 3}


def signal_names(layout):
    """Resolver nombres elaborados por sufijo único y comprobar anchuras."""
    names = {}
    for key, width in WIDTHS.items():
        matches = [(n, w) for n, w in layout if n.endswith(f"init_{key}")]
        require(len(matches) == 1 and matches[0][1] == width,
                f"Layout incompatible para {key}: {matches}")
        names[key] = matches[0][0]
    return names


def unpack(scope, names):
    words = list(scope.data)
    raw = {}
    offset = 0
    for name, width in scope.layouts[0]:
        raw[name] = [(w >> offset) & ((1 << width) - 1) for w in words]
        offset += width
    return {key: raw[name] for key, name in names.items()}


def check_packet(packet):
    require(packet[3] == dsi_header_ecc(list(packet[:3])), "ECC incorrecto")
    if packet[0] == 0x39:
        wc = packet[1] | packet[2] << 8
        require(wc + 6 == len(packet), "Word Count incorrecto")
        crc = 0xffff
        for value in packet[4:-2]:
            crc ^= value
            for _ in range(8):
                crc = (crc >> 1) ^ (0x8408 if crc & 1 else 0)
        require(crc == int.from_bytes(packet[-2:], "little"), "CRC incorrecto")


def verify_selected(ch, index):
    require(not any(ch["fallo"]), "Fallo del secuenciador durante la captura")
    accepted = [i for i, v in enumerate(ch["aceptado"])
                if v and ch["indice"][i] == index]
    require(len(accepted) == 1, "No hay una única aceptación del paquete seleccionado")
    a = accepted[0]
    finished = next((i for i in range(a + 1, len(ch["terminado"]))
                     if ch["terminado"][i]), None)
    require(finished is not None and a >= 2 and finished + 2 < len(ch["d0"]),
            "Transacción incompleta dentro de la ventana")
    require(ch["trigger"][a] == 1, "Aceptación sin trigger seleccionado")
    require(all(v == index for v in ch["indice"][a:finished + 1]),
            "Índice cambia antes de terminar")
    remap = {"lp": "d0", "byte": "dato", "reset": "rst_motor"}
    channels = {key: ch[remap.get(key, key)][a - 2:finished + 3]
                for key in ("lp", "byte", "reset", "solicitud", "aceptado",
                            "ocupado", "terminado", "pos", "longitud")}
    channels["rechazada"] = [0] * len(channels["lp"])
    decoded = verify_capture(channels, list(PACKETS[index]))
    check_packet(bytes(decoded[1:]))
    return {"index": index, "decoded": decoded,
            "accepted_sample": a, "finished_sample": finished}


def verify_timeline(starts, ends, complete, counts=0xbb, state=2):
    require(state == 2, f"Estado final incorrecto: 0x{state:02x}")
    require(counts == 0xbb, f"Cuentas incorrectas: 0x{counts:02x}")
    require(len(starts) == len(ends) == 11, "Registro de eventos incompleto")
    for i, packet in enumerate(PACKETS):
        require(ends[i] - starts[i] == 64 * (len(packet) + 1) + 21,
                f"Duración de transmisión incorrecta, paso {i}")
        if i < 10:
            require(starts[i + 1] - ends[i] == WAITS[i] + 8,
                    f"Espera/interfaz incorrecta después del paso {i}")
    require(starts[0] == 808009, f"Arranque inesperado: {starts[0]} ciclos")
    require(complete - ends[-1] == WAITS[-1] + 2,
            "No se cumple la espera final antes de init_completa")
    return {"starts": starts, "ends": ends, "complete_cycle": complete,
            "counts": counts, "state": state}


def read_timeline(wb):
    return {
        "starts": [getattr(wb.regs, f"init_inicio{i}").read() for i in range(11)],
        "ends": [getattr(wb.regs, f"init_fin{i}").read() for i in range(11)],
        "complete": wb.regs.init_completa_ciclo.read(),
        "counts": wb.regs.init_cuentas.read(), "state": wb.regs.init_estado.read(),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1234)
    parser.add_argument("--csr-csv", default="build/debug_init/csr.csv")
    parser.add_argument("--analyzer-csv", default="build/debug_init/analyzer.csv")
    parser.add_argument("--bitstream", default="build/debug_init/gateware/debug_init.fs")
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--timeout", type=float, default=10)
    args = parser.parse_args()
    require(math.isfinite(args.timeout) and args.timeout > 0, "Timeout inválido")
    for packet in PACKETS:
        check_packet(packet)
    artifacts = {}
    for filename in (args.csr_csv, args.analyzer_csv, args.bitstream):
        path = Path(filename)
        artifacts[str(path)] = hashlib.sha256(path.read_bytes()).hexdigest()
    output = Path(args.output_dir)
    output.mkdir(parents=True, exist_ok=False)
    report = {"result": "INCOMPLETE", "panel_connected_to_logic": False,
              "artifacts_sha256": artifacts, "runs": [],
              "command": sys.argv, "git_commit": subprocess.check_output(
                  ["git", "rev-parse", "HEAD"], text=True).strip(),
              "git_status": subprocess.check_output(
                  ["git", "status", "--short"], text=True)}
    report["source_sha256"] = {
        str(p): hashlib.sha256(p.read_bytes()).hexdigest()
        for folder, pattern in (("gateware", "**/*.py"), ("scripts", "test_init*.py"),
                                ("scripts", "test_lpdt_hw.py"),
                                ("motor_lpdt/src", "*.v"),
                                ("secuenciador_init/src", "*.v"))
        for p in sorted(Path(folder).glob(pattern))
    }
    scope = None
    try:
        with RemoteClient(host=args.host, port=args.port, csr_csv=args.csr_csv,
                          timeout=args.timeout, raise_on_timeout=True) as wb:
            try:
                # Verificar el enlace sin depender de direcciones CSR fijas.
                wb.regs.debug_regs_entrada.write(0x12345678)
                require(wb.regs.debug_regs_salida.read() == 0x12345679,
                        "Falló la prueba de acceso CSR")
                scope = LiteScopeAnalyzerDriver(wb.regs, "analyzer",
                                               config_csv=args.analyzer_csv)
                require(scope.depth == 2048 and scope.samplerate == 40_000_000
                        and not scope.with_rle, "Configuración LiteScope incompatible")
                names = signal_names(scope.layouts[0])
                for index in range(11):
                    result = {"index": index}
                    report["runs"].append(result)
                    wb.regs.init_reset_prueba.write(1)
                    wb.regs.init_lp_habilitada.write(1)
                    wb.regs.init_paquete.write(index)
                    scope.clear()
                    scope.configure_group(0)
                    scope.configure_subsampler(1)
                    scope.configure_trigger(cond={names["trigger"]: "1"})
                    scope.run(offset=32, length=2048)
                    wb.regs.init_reset_prueba.write(0)
                    deadline = time.monotonic() + args.timeout
                    while True:
                        state = wb.regs.init_estado.read()
                        result["last_state"] = state
                        require(not state & 0x44, f"Fallo de secuenciador/monitor: {state:#x}")
                        if scope.done() and state & 2:
                            break
                        if time.monotonic() >= deadline:
                            raise TimeoutError(f"Timeout de captura/arranque, paquete {index}")
                        time.sleep(0.01)
                    # Guardar ondas antes de validar para conservar evidencia del fallo.
                    scope.upload()
                    scope.save(str(output / f"paquete_{index:02d}.vcd"))
                    timeline = read_timeline(wb)
                    result["timeline"] = timeline
                    verify_timeline(**timeline)
                    result.update(verify_selected(unpack(scope, names), index))
                    # Releer tras la descarga para detectar envíos espurios en LISTO.
                    require(read_timeline(wb) == timeline, "Eventos adicionales en LISTO")
                    print(f"PASS: paquete {index}, bytes/ECC/CRC y cronología completa")
                report["result"] = "PASS"
            finally:
                # No dejar secuencia parcialmente activa si hubo un error.
                active_error = sys.exc_info()[0]
                cleanup_error = None
                cleanup = [lambda: wb.regs.init_reset_prueba.write(1)]
                if scope is not None:
                    cleanup += [lambda: scope.trigger_enable.write(0),
                                lambda: scope.storage_enable.write(0)]
                for action in cleanup:
                    try:
                        action()
                    except Exception as error:
                        cleanup_error = cleanup_error or error
                        print(f"Aviso durante limpieza: {error}", file=sys.stderr)
                if active_error is None and cleanup_error is not None:
                    raise cleanup_error
    except Exception as error:
        report["result"] = "FAIL"
        report["error"] = str(error)
        raise
    finally:
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS interno (no panel). Resumen: {output / 'summary.json'}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, AttributeError, KeyError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
