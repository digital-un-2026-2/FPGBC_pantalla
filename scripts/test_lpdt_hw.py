"""Prueba LPDT interna por UARTWishbone y LiteScope, sin acceso al panel.

Ejecutar desde la raíz con litex_server activo y el bitstream correspondiente
a csr.csv/analyzer.csv cargado. No sintetiza ni programa la FPGA.
"""

import argparse
import json
import math
from pathlib import Path
import shlex
import sys
import time

from litex import RemoteClient
from litescope.software.driver.analyzer import LiteScopeAnalyzerDriver


# PAYLOAD = [0x12, 0x34, 0xA5]
PAYLOAD = [0x00, 0xFF, 0x55, 0xAA, 0x12, 0x34, 0xA5]
SIGNALS = {
    "lp": "main_estado_D0",
    "solicitud": "main_solicitud",
    "aceptado": "main_aceptado",
    "ocupado": "main_ocupado0",
    "terminado": "main_terminado",
    "pos": "main_pos",
    "byte": "main_byte_almacen",
    "longitud": "main_cantidad_bytes",
    "rechazada": "main_rechazada",
    "reset": "main_reset_observado",
}


def require(condition, message):
    # No usar assert: python -O no debe deshabilitar las comprobaciones.
    if not condition:
        raise ValueError(message)


def dsi_header_ecc(header):
    """ECC de los 24 bits del encabezado, D0 = bit 0 del primer byte.

    Ecuaciones contrastadas con la referencia técnica (no normativa):
    https://www.zephray.me/post/mipi_dsi_note/
    P6 y P7 son cero. No es el CRC de un paquete largo.
    """
    require(len(header) == 3 and all(0 <= value <= 255 for value in header),
            "El encabezado debe contener tres bytes")
    word = header[0] | (header[1] << 8) | (header[2] << 16)
    parity_bits = (
        (0, 1, 2, 4, 5, 7, 10, 11, 13, 16, 20, 21, 22, 23),
        (0, 1, 3, 4, 6, 8, 10, 12, 14, 17, 20, 21, 22, 23),
        (0, 2, 3, 5, 6, 9, 11, 12, 15, 18, 20, 21, 22),
        (1, 2, 3, 7, 8, 9, 13, 14, 15, 19, 20, 21, 23),
        (4, 5, 6, 7, 8, 9, 16, 17, 18, 19, 20, 22, 23),
        (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23),
    )
    ecc = 0
    for parity_index, positions in enumerate(parity_bits):
        parity = 0
        for bit in positions:
            parity ^= (word >> bit) & 1
        ecc |= parity << parity_index
    return ecc


def dcs_short_packet(command):
    """VC=0, DT=0x05: escritura DCS corta sin parámetros, sin CRC."""
    header = [0x05, command, 0x00]
    return header + [dsi_header_ecc(header)]


def check_ecc_vectors():
    # Reset está documentado en motor_lpdt/docs/lpdt.md. Estos vectores fijos
    # detectan regresiones de las ecuaciones, pero no prueban todos los headers.
    for command, ecc in ((0x01, 0x10), (0x11, 0x36), (0x29, 0x1C)):
        require(dsi_header_ecc([0x05, command, 0x00]) == ecc,
                f"ECC incorrecto para comando DCS 0x{command:02X}")


def unpack_samples(scope):
    """Extraer canales según el layout real, sin tratar DumpData como list.

    DumpData redefine data[n] como selección de un bit en todas las muestras.
    Convertir a list permite trabajar con palabras de muestra convencionales.
    """
    samples = list(scope.data)
    channels = {}
    offset = 0
    for name, width in scope.layouts[0]:
        mask = (1 << width) - 1
        channels[name] = [(word >> offset) & mask for word in samples]
        offset += width
    missing = set(SIGNALS.values()) - channels.keys()
    require(not missing, f"Señales ausentes en analyzer.csv: {sorted(missing)}")
    return {key: channels[name] for key, name in SIGNALS.items()}


def state_runs(values):
    """Tramos (inicio, fin exclusivo, estado) definidos por transiciones."""
    runs = []
    start = 0
    for index in range(1, len(values)):
        if values[index] != values[start]:
            runs.append((start, index, values[start]))
            start = index
    if values:
        runs.append((start, len(values), values[start]))
    return runs


def pulse_index(values, name):
    """Exigir exactamente un pulso completo de una muestra."""
    indices = [i for i, value in enumerate(values) if value]
    require(
        len(indices) == 1,
        f"{name}: esperaba un pulso de un ciclo; muestras activas={len(indices)}",
    )
    index = indices[0]
    require(0 < index < len(values) - 1, f"{name}: pulso cortado por la captura")
    return index


def verify_capture(channels, payload=None):
    """Reconocer entrada, Mark/Space y salida; después comprobar el contenido.

    No es un receptor D-PHY general: acepta una sola transacción LPDT lógica,
    muestreada a 40 MHz sin subsampling, según el contrato del motor actual.
    """
    if payload is None:
        payload = PAYLOAD
    lp = channels["lp"]
    require(bool(lp), "Captura vacía")
    require(not any(channels["reset"]), "Reset durante la captura")
    require(not any(channels["rechazada"]), "El supervisor rechazó una orden")
    accepted = pulse_index(channels["aceptado"], "aceptado")
    finished = pulse_index(channels["terminado"], "terminado")
    require(accepted < finished, "terminado no sucede después de aceptado")
    require(channels["solicitud"][accepted] == 1, "Aceptación sin solicitud")
    require(
        not any(channels["solicitud"][accepted + 2 :]),
        "La solicitud no se retira tras aceptar",
    )
    require(
        all(channels["ocupado"][accepted:finished]), "ocupado cae antes de terminar"
    )
    require(
        not any(channels["ocupado"][finished:]),
        "ocupado permanece activo o hay otro envío",
    )

    runs = state_runs(lp)
    require(len(runs) >= 7, "No hay una transacción LPDT completa")
    states = [value for _, _, value in runs]
    require(
        states[:5] == [3, 2, 0, 1, 0], "Entrada a escape distinta de 11→10→00→01→00"
    )
    require(states[-2:] == [2, 3], "Falta salida Mark-1→LP-11")
    require(runs[-1][0] <= finished, "terminado aparece antes del retorno a LP-11")
    require(
        all(value == 3 for value in lp[finished:]),
        "No permanece en LP-11 después de terminar",
    )

    # Excluir entrada a escape y salida. Cada par Mark/Space entrega un bit.
    data_runs = runs[5:-2]
    require(len(data_runs) % 2 == 0, "Secuencia Mark/Space incompleta")
    bits = []
    bit_samples = []
    for index in range(0, len(data_runs), 2):
        mark, space = data_runs[index : index + 2]
        require(
            mark[2] in (1, 2) and space[2] == 0,
            f"Codificación inválida en bit {len(bits)}: {mark[2]:02b}→{space[2]:02b}",
        )
        bits.append(1 if mark[2] == 2 else 0)
        bit_samples.append(mark[0])
    require(len(bits) % 8 == 0, f"Cantidad de bits no múltiplo de 8: {len(bits)}")
    decoded = [
        sum(bits[start + bit] << bit for bit in range(8))
        for start in range(0, len(bits), 8)
    ]
    expected = [0x87] + payload
    require(decoded == expected, f"Bytes recibidos: {decoded}; esperados: {expected}")

    # Las transiciones se reconocieron primero; ahora medir sus duraciones.
    # Reposo inicial y final no tienen duración fija en esta captura.
    for start, stop, value in runs[1:-1]:
        require(
            stop - start == 4,
            f"Fase LP-{value:02b} en muestra {start}: {stop - start} ciclos, esperaba 4",
        )

    for sample in bit_samples:
        require(
            channels["longitud"][sample] == len(payload), "Longitud activa incorrecta"
        )

    # pos solicita datos anticipadamente: NO identifica el byte que sale por D0.
    # Comprobar la respuesta del almacén a la dirección observada, mientras que
    # decoded (arriba) comprueba de forma independiente los bytes transmitidos.
    for sample in range(accepted, finished + 1):
        position = channels["pos"][sample]
        require(
            0 <= position < len(payload),
            f"pos fuera del paquete en muestra {sample}: {position}",
        )
        require(
            channels["byte"][sample] == payload[position],
            f"byte_almacen incorrecto para pos={position} en muestra {sample}",
        )

    # Según el contrato actual: 0 durante el selector, lecturas anticipadas
    # de los siguientes bytes y retorno a 0 al entrar en IDLE. No imponer
    # posiciones temporales fijas ni igualar esta dirección al byte serial.
    requested = [
        value for _, _, value in state_runs(channels["pos"][accepted : finished + 1])
    ]
    expected_positions = list(range(len(payload)))
    if len(payload) > 1:
        expected_positions.append(0)
    require(
        requested == expected_positions,
        f"Recorrido de pos: {requested}; esperado: {expected_positions}",
    )
    return decoded


def capture_packet(wb, scope, payload, output, timeout):
    """Una NUEVA captura por paquete, sin depender del flag finalizado anterior."""
    require(1 <= len(payload) <= 7, "El paquete debe contener de 1 a 7 bytes")
    require(wb.regs.lpdt_estado.read() == 1, "El supervisor no está listo sin errores")
    # Limpiar los términos evita acumular triggers entre envíos consecutivos.
    scope.clear()
    scope.configure_group(0)
    scope.configure_subsampler(1)
    scope.configure_trigger(cond={SIGNALS["solicitud"]: "1"})
    for index, value in enumerate(payload):
        getattr(wb.regs, f"lpdt_byte{index}").write(value)
    wb.regs.lpdt_longitud.write(len(payload))
    scope.run(offset=32, length=2048)
    requested_at = time.monotonic()
    wb.regs.lpdt_iniciar.write(1)
    deadline = time.monotonic() + timeout
    while not scope.done():
        if time.monotonic() >= deadline:
            raise TimeoutError("LiteScope no completó la captura")
        time.sleep(0.01)
    nivel = scope.storage_mem_level.read()
    print(f"Nivel de almacenamiento antes de descargar: {nivel}")
    require(0 < nivel <= scope.depth, f"Nivel de almacenamiento inválido: {nivel}")
    scope.upload()
    # Conservar las ondas también si falla la verificación posterior.
    scope.save(str(output))
    print(f"Captura: {output}")
    decoded = verify_capture(unpack_samples(scope), payload)
    require(wb.regs.lpdt_estado.read() == 1,
            "El supervisor no volvió a listo sin errores")
    require(wb.regs.lpdt_finalizado.read() == 1, "Falta finalización persistente")
    completed_observed_at = time.monotonic()
    print("PASS: " + " ".join(f"{value:02X}" for value in decoded))
    print(f"Ondas: pixi run gtkwave {shlex.quote(str(output))}")
    return {
        "packet_hex": " ".join(f"{value:02X}" for value in payload),
        "decoded_hex": " ".join(f"{value:02X}" for value in decoded),
        "capture": str(output),
        "storage_level": nivel,
        "request_host_monotonic_s": requested_at,
        "completion_observed_host_monotonic_s": completed_observed_at,
        "result": "PASS",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=1234)
    parser.add_argument("--csr-csv", default="build/debug/csr.csv")
    parser.add_argument("--analyzer-csv", default="build/debug/analyzer.csv")
    parser.add_argument("--output", default="build/debug/captures/tres_bytes.vcd")
    parser.add_argument("--dcs-sequence", action="store_true",
                        help="Prueba INTERNA: Software Reset, Exit Sleep Mode, Display On.")
    parser.add_argument("--output-dir", default="build/debug/captures/dcs_sequence",
                        help="Directorio de capturas y resumen del modo --dcs-sequence.")
    parser.add_argument("--reset-wait-ms", type=float,
                        help="Espera adicional tras verificar Reset, sin valor predeterminado.")
    parser.add_argument("--sleepout-wait-ms", type=float,
                        help="Espera adicional tras verificar Exit Sleep, sin valor predeterminado.")
    parser.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="Timeout en segundos para accesos y espera de captura.",
    )
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout debe ser finito y positivo")
    if args.dcs_sequence:
        for name in ("reset_wait_ms", "sleepout_wait_ms"):
            value = getattr(args, name)
            if value is None or not math.isfinite(value) or value < 0:
                parser.error(f"--{name.replace('_', '-')} es obligatorio, finito y no negativo")
    elif args.reset_wait_ms is not None or args.sleepout_wait_ms is not None:
        parser.error("Las esperas DCS requieren --dcs-sequence")
    for filename in (args.csr_csv, args.analyzer_csv):
        if not Path(filename).is_file():
            parser.error(f"No existe {filename}")

    if args.dcs_sequence:
        check_ecc_vectors()
        output_dir = Path(args.output_dir)
        plan = [
            ("software_reset", dcs_short_packet(0x01), args.reset_wait_ms),
            ("exit_sleep", dcs_short_packet(0x11), args.sleepout_wait_ms),
            ("display_on", dcs_short_packet(0x29), 0.0),
        ]
        outputs = [output_dir / f"{index:02d}_{name}.vcd"
                   for index, (name, _, _) in enumerate(plan, 1)]
        report_path = output_dir / "summary.json"
        reserved = outputs + [report_path]
        print("PRUEBA INTERNA: D0 no está conectado al panel.")
        print("Esta secuencia NO certifica la inicialización ni los tiempos del panel.")
    else:
        plan = [("patron", PAYLOAD, 0.0)]
        outputs = [Path(args.output)]
        report_path = None
        reserved = outputs
    for output in reserved:
        require(not output.exists(), f"Ya existe {output}; elige otro destino")
    for output in outputs:
        require(output.suffix.lower() == ".vcd", "La captura debe terminar en .vcd")
        output.parent.mkdir(parents=True, exist_ok=True)

    report = {
        "mode": "dcs_sequence_internal" if args.dcs_sequence else "pattern_internal",
        "motor_output_exported_to_pins": False,
        "timing_note": "Esperas adicionales del host tras verificar cada envío; no tiempos exactos de D-PHY/DCS.",
        "result": "INCOMPLETE",
        "commands": [],
    }

    with RemoteClient(
        host=args.host,
        port=args.port,
        csr_csv=args.csr_csv,
        timeout=args.timeout,
        raise_on_timeout=True,
    ) as wb:
        require(wb.regs.lpdt_estado.read() & 1, "El supervisor no está listo")
        scope = LiteScopeAnalyzerDriver(
            wb.regs, "analyzer", config_csv=args.analyzer_csv, debug=True
        )
        try:
            require(
                scope.depth >= 2048, "La prueba requiere profundidad de al menos 2048"
            )
            require(
                scope.samplerate == 40_000_000, "La prueba requiere muestreo a 40 MHz"
            )
            require(not scope.with_rle, "La prueba espera un analizador sin RLE")
            names = {name for name, _ in scope.layouts[0]}
            require(
                set(SIGNALS.values()) <= names,
                "El layout no corresponde al target LPDT esperado",
            )
            previous_completion = None
            for (name, payload, wait_ms), output in zip(plan, outputs):
                print(f"Comando: {name}; paquete: " + " ".join(f"{b:02X}" for b in payload))
                result = capture_packet(wb, scope, payload, output, args.timeout)
                result["name"] = name
                if previous_completion is not None:
                    result["host_gap_from_previous_observation_ms"] = (
                        result["request_host_monotonic_s"] - previous_completion) * 1000
                previous_completion = result["completion_observed_host_monotonic_s"]
                result["additional_wait_requested_ms"] = wait_ms
                report["commands"].append(result)
                if wait_ms:
                    print(f"Espera adicional del host: {wait_ms:g} ms")
                start_wait = time.monotonic()
                # Desde una observación de finalización ya verificada, no desde
                # el pulso exacto. Descarga y validación añaden más separación.
                deadline_wait = start_wait + wait_ms / 1000
                while True:
                    remaining = deadline_wait - time.monotonic()
                    if remaining <= 0:
                        break
                    time.sleep(remaining)
                result["additional_wait_host_elapsed_ms"] = (time.monotonic() - start_wait) * 1000
                if report_path is not None:
                    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
            report["result"] = "PASS"
            if report_path is not None:
                report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
                print(f"Resumen: {report_path}")
                print("PASS: secuencia DCS interna completa, sin resetear la FPGA entre comandos")
        except Exception as error:
            report["result"] = "FAIL"
            report["error"] = str(error)
            if report_path is not None:
                try:
                    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
                except OSError as report_error:
                    print(f"Aviso al guardar resumen: {report_error}", file=sys.stderr)
            raise
        finally:
            # Dejar desarmado el analizador sin tocar reset ni drivers del motor.
            # No ocultar el error original si también falla la limpieza.
            try:
                scope.trigger_enable.write(0)
                scope.storage_enable.write(0)
            except Exception as error:
                print(f"Aviso al desarmar LiteScope: {error}", file=sys.stderr)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, AttributeError, KeyError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
