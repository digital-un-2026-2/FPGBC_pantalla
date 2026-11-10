"""Control the integrated display CSR bank through an existing litex_server."""
import argparse
import json
import math
import time
from pathlib import Path

from litex import RemoteClient


class DisplayController:
    def __init__(self, registers, timeout=5.0):
        self.regs = registers
        self.timeout = timeout

    def wait(self, predicate, description):
        deadline = time.monotonic() + self.timeout
        while not predicate():
            if time.monotonic() >= deadline:
                raise TimeoutError(description)
            time.sleep(0.001)

    def transaction(self, word):
        self.wait(lambda: self.regs.display_bridge.read() & 1,
                  "La interfaz no está disponible: revisar reset y reloj")
        sequence = self.regs.display_sequence.read()
        self.regs.display_command.write(word)
        self.wait(lambda: self.regs.display_sequence.read() != sequence,
                  "Sin respuesta: revisar reset coordinado o pérdida del PLL")
        bridge = self.regs.display_bridge.read()
        if bridge & 4:
            raise RuntimeError("Escritura rechazada por el puente CSR; limpiar con display_clear=1")
        result = {
            "flags": self.regs.display_flags.read(),
            "frames": self.regs.display_frames.read(),
            "lp_completed": self.regs.display_lp_completed.read(),
            "geometry": self.regs.display_geometry.read(),
        }
        if result["flags"] & (1 << 9):
            raise RuntimeError(f"Orden 0x{word:08x} rechazada: flags=0x{result['flags']:08x}")
        return result

    def status(self):
        return self.transaction(0)

    def diagnose(self):
        """Read ref-domain status even when the byte clock cannot reply."""
        bridge = self.regs.display_bridge.read()
        report = {
            "bridge_raw": bridge,
            "reset_asserted": bool(self.regs.display_reset.read()),
            "command_ready": bool(bridge & 1),
            "phy_available": bool(bridge & 8),
            "clock_fault": bool(bridge & 16),
            "byte_reset": bool(bridge & 32),
            "command_pending": bool(bridge & 64),
            "lcd_reception_verified": False,
        }
        if not bridge & 1:
            report["result"] = "Sin respuesta disponible del dominio de byte; revisar reset, PLL o una orden pendiente"
            return report
        before = self.status()
        begin = time.monotonic()
        time.sleep(0.25)
        after = self.status()
        elapsed = time.monotonic() - begin
        flags = after["flags"]
        report.update(after)
        report.update({
            "running": bool(flags & 1), "stopped": bool(flags & 2),
            "initialized": bool(flags & 8), "error": bool(flags & 16),
            "source_error_cause": (flags >> 10) & 15,
            "phy_error_cause": (flags >> 14) & 7,
            "arbiter_error_cause": (flags >> 17) & 3,
            "frames_advanced": (after["frames"] - before["frames"]) & 0xffffffff,
        })
        report["observed_frame_hz"] = round(report["frames_advanced"] / elapsed, 1)
        if flags & (1 << 30):
            state = (flags >> 26) & 15
            names = ("WAIT_PHY", "LP_REQUEST", "LP_TRANSMIT", "INIT_DELAY", "WAIT_LINE",
                     "PRIME", "REQUEST", "WAIT_GRANT", "SEND", "WAIT_COMPLETE", "HALTED")
            report["source_state"] = names[state] if state < len(names) else f"INVALID_{state}"
            report["init_step"] = (flags >> 21) & 15
            report["backlight_dcs_test"] = bool(flags & (1 << 25))
            report["expected_init_packets"] = 13 if report["backlight_dcs_test"] else 11
        report["result"] = (
            "Fallo local; consultar las causas y el estado" if report["error"] else
            "La FPGA transmite cuadros; comprobar luz y recepción del LCD" if report["frames_advanced"] else
            "Sin avance de cuadros durante la muestra; consultar inicialización y estado")
        return report

    def reset(self):
        self.regs.display_reset.write(1)
        # Software hold also reaches ref-domain wrapper state if byte_clk stops.
        time.sleep(0.01)
        self.regs.display_reset.write(0)
        self.wait(lambda: self.regs.display_bridge.read() & 1, "Sin reloj tras reset")
        return self.status()

    def initialize(self, steps):
        self.transaction(4)
        for step in steps:
            before = self.status()["lp_completed"]
            word = 7 | (step["opcode"] << 4)
            if "param" in step:
                word |= (1 << 12) | (step["param"] << 13)
            self.transaction(word)

            def finished():
                status = self.status()
                if status["flags"] & (1 << 4):
                    raise RuntimeError(f"Fallo durante LPDT: 0x{status['flags']:08x}")
                return status["lp_completed"] == ((before + 1) & 0xffffffff)

            self.wait(finished, "LPDT no ha liberado el enlace")
            time.sleep(step["delay_ms"] / 1000)
        return self.transaction(3)


def load_sequence(path):
    steps = json.loads(Path(path).read_text())
    if not isinstance(steps, list) or not steps:
        raise ValueError("La secuencia debe ser una lista no vacía")
    for step in steps:
        if not isinstance(step, dict) or not {"opcode", "delay_ms"} <= step.keys() or step.keys() - {"opcode", "param", "delay_ms"}:
            raise ValueError("Cada paso requiere opcode y delay_ms; param es opcional")
        for name in ("opcode", "param"):
            if name in step and (type(step[name]) is not int or not 0 <= step[name] <= 255):
                raise ValueError(f"{name} debe ser un entero de 0 a 255")
        delay = step["delay_ms"]
        if type(delay) not in (int, float) or not math.isfinite(delay) or delay < 0:
            raise ValueError("delay_ms debe ser finito y no negativo")
    return steps


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csr-csv", default="build/display/csr.csv")
    parser.add_argument("--host", default="localhost")
    parser.add_argument("--port", type=int, default=1234)
    parser.add_argument("--timeout", type=float, default=5.0)
    commands = parser.add_subparsers(dest="action", required=True)
    for action in ("status", "diagnose", "reset", "start", "stop"):
        commands.add_parser(action)
    apply = commands.add_parser("configure")
    apply.add_argument("--profile", type=int, choices=range(256), default=0)
    apply.add_argument("--vc", type=int, choices=range(4), default=0)
    init = commands.add_parser("initialize")
    init.add_argument("sequence", help="JSON con la secuencia confirmada del panel; solo DCS cortos")
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout debe ser finito y positivo")
    steps = load_sequence(args.sequence) if args.action == "initialize" else None
    bus = RemoteClient(host=args.host, port=args.port, csr_csv=args.csr_csv)
    bus.open()
    try:
        display = DisplayController(bus.regs, args.timeout)
        if args.action == "diagnose":
            result = display.diagnose()
        elif args.action == "reset":
            result = display.reset()
        elif args.action == "configure":
            display.transaction(1 | (args.profile << 4) | (args.vc << 12))
            result = display.transaction(2)
            if not result["flags"] & 4:
                raise RuntimeError("Perfil de vídeo no válido o no habilitado")
        elif args.action == "initialize":
            result = display.initialize(steps)
        elif args.action == "stop":
            display.transaction(6)
            result = None

            def stopped():
                nonlocal result
                result = display.status()
                if result["flags"] & (1 << 4):
                    raise RuntimeError(f"Fallo al detener: 0x{result['flags']:08x}")
                return bool(result["flags"] & 2)

            display.wait(stopped, "STOP no ha terminado el cuadro")
        else:
            result = display.transaction(5 if args.action == "start" else 0)
        print(json.dumps(result, indent=2))
    finally:
        bus.close()


if __name__ == "__main__":
    main()
