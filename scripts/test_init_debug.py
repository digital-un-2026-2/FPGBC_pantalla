"""Regresión sin hardware del arnés y del verificador de capturas.

Ejecutar: pixi run python -m unittest scripts.test_init_debug -v
Genera Verilog del wrapper real y lo simula con Icarus (sin UART/LiteScope).
"""

from pathlib import Path
import subprocess
import unittest

from migen import Cat, Signal
from migen.fhdl import verilog
from migen.sim import run_simulation

from gateware.cores.init_debug import InitDebug, InitMonitor
from scripts.test_init_hw import (PACKETS, WIDTHS, check_packet, verify_selected,
                                  verify_timeline)


class MonitorTest(unittest.TestCase):
    def test_overflow_reset_and_bad_handshake(self):
        dut = InitMonitor()

        def bench():
            yield dut.reset.eq(1)
            yield
            yield dut.reset.eq(0)
            yield
            for _ in range(16):
                yield dut.aceptado.eq(1)
                yield
                yield dut.aceptado.eq(0)
                yield dut.terminado.eq(1)
                yield
                yield dut.terminado.eq(0)
                yield
            yield
            self.assertEqual((yield dut.aceptaciones), 15)
            self.assertEqual((yield dut.finales), 15)
            self.assertEqual((yield dut.error), 1)
            yield dut.reset.eq(1)
            yield
            yield dut.reset.eq(0)
            yield
            self.assertEqual((yield dut.error), 0)
            self.assertEqual((yield dut.aceptaciones), 0)
            self.assertEqual((yield dut.inicios[0]), 0)
            yield dut.terminado.eq(1)
            yield
            yield dut.terminado.eq(0)
            yield
            self.assertEqual((yield dut.error), 1)

        run_simulation(dut, bench())

    def test_packet_vectors(self):
        for packet in PACKETS:
            check_packet(packet)
        damaged = bytearray(PACKETS[7])
        damaged[-1] ^= 1
        with self.assertRaises(ValueError):
            check_packet(damaged)


class IntegrationTest(unittest.TestCase):
    def test_real_wrapper_rtl_and_capture_checker(self):
        root = Path(__file__).resolve().parents[1]
        build = root / "build/debug_init/sim"
        build.mkdir(parents=True, exist_ok=True)
        dut = InitDebug()
        sample = Signal(sum(WIDTHS.values()), name="sample")
        dut.comb += sample.eq(Cat(*[getattr(dut, name) for name in WIDTHS]))
        ports = {
            "reset_prueba": dut.reset_prueba.storage,
            "lp": dut.lp_habilitada.storage, "paquete": dut.paquete.storage,
            "sample": sample, "completa": dut.completa, "fallo": dut.fallo,
            "counts": dut.cuentas.status, "state": dut.estado.status,
            "complete_cycle": dut.completa_ciclo.status,
            **{f"start{i}": s for i, s in enumerate(dut.monitor.inicios)},
            **{f"end{i}": s for i, s in enumerate(dut.monitor.fines)},
        }
        generated = verilog.convert(dut, ios=set(ports.values()), name="init_wrapper")
        generated.write(str(build / "wrapper.v"))
        connections = [f".{generated.ns.get_name(s)}({key})" for key, s in ports.items()]
        declarations = []
        for key, signal in ports.items():
            kind = "reg" if key in ("reset_prueba", "lp", "paquete") else "wire"
            declarations.append(f"{kind} [{len(signal)-1}:0] {key};")
        dump_timeline = "\n".join(
            f'$display("T {i} %0d %0d", start{i}, end{i});' for i in range(11))
        tb = f"""`timescale 1ns/1ps
module init_wrapper_TB;
reg sys_clk=0, sys_rst=1;
always #12.5 sys_clk=~sys_clk;
{' '.join(declarations)}
init_wrapper dut(.sys_clk(sys_clk), .sys_rst(sys_rst), {', '.join(connections)});
integer fd, tail=0;
reg [{len(sample)-1}:0] previous;
wire active = dut.{generated.ns.get_name(dut.solicitud)} |
              dut.{generated.ns.get_name(dut.ocupado)} |
              dut.{generated.ns.get_name(dut.terminado)};
always @(posedge sys_clk) begin
  if (!sys_rst && !reset_prueba) begin
    if (active && tail==0) $fdisplay(fd, "%h", previous);
    if (active || tail>0) $fdisplay(fd, "%h", sample);
    if (active) tail=3; else if (tail>0) tail=tail-1;
  end
  previous=sample;
end
initial begin
  fd=$fopen("samples.hex", "w");
  reset_prueba=0; lp=1; paquete=7;
  repeat(4) @(negedge sys_clk);
  sys_rst=0;
  wait(completa || fallo);
  repeat(8) @(negedge sys_clk);
  {dump_timeline}
  $display("C %0d %0d %0d", complete_cycle, counts, state);
  if (fallo) $fatal(1,"Fallo en integración");
  $fclose(fd);
  // Pérdida de preparación en LISTO: error LP enclavado y reset de motor.
  lp=0;
  repeat(4) @(negedge sys_clk);
  if (!fallo || state[5:3]!=5 || !dut.{generated.ns.get_name(dut.rst_motor)})
    $fatal(1,"No detecta perdida LP");
  reset_prueba=1;
  repeat(4) @(negedge sys_clk);
  if (counts!=0 || state[6:1]!=0) $fatal(1,"Reset local incompleto");
  // Reinicio sin preparación: timeout de preparación, sin envíos.
  reset_prueba=0;
  wait(fallo);
  repeat(4) @(negedge sys_clk);
  if (counts!=0 || state[5:3]!=1) $fatal(1,"Timeout LP incorrecto");
  $finish;
end
initial begin #330000000; $fatal(1,"Timeout global"); end
endmodule
"""
        (build / "tb.v").write_text(tb)
        sources = [root / "motor_lpdt/src" / f"{n}.v" for n in
                   ("motor_lpdt", "motor_control", "count", "comp", "mux", "reg_0")]
        sources += sorted((root / "secuenciador_init/src").glob("*.v"))
        subprocess.run(["iverilog", "-g2012", "-Wall", "-s", "init_wrapper_TB",
                        "-o", "sim.out", "tb.v", "wrapper.v", *map(str, sources)],
                       cwd=build, check=True, capture_output=True, text=True)
        result = subprocess.run(["vvp", "sim.out"], cwd=build, check=True,
                                capture_output=True, text=True, timeout=240)
        (build / "result.txt").write_text(result.stdout)
        starts, ends = [], []
        for line in result.stdout.splitlines():
            if line.startswith("T "):
                _, _, start, end = line.split()
                starts.append(int(start))
                ends.append(int(end))
            if line.startswith("C "):
                _, complete, counts, state = map(str, line.split())
        verify_timeline(starts, ends, int(complete), int(counts), int(state))
        words = [int(line, 16) for line in (build / "samples.hex").read_text().splitlines()]
        channels, offset = {}, 0
        for name, width in WIDTHS.items():
            channels[name] = [(word >> offset) & ((1 << width) - 1) for word in words]
            offset += width
        self.assertEqual(channels["trigger"],
                         [int(idx == 7 and request) for idx, request in
                          zip(channels["indice"], channels["solicitud"])])
        # El archivo contiene ventanas consecutivas y posibles transacciones vecinas.
        for index in range(11):
            channels["trigger"] = [int(v == index and request)
                                   for v, request in zip(channels["indice"], channels["solicitud"])]
            verified = verify_selected(channels, index)
            self.assertEqual(verified["decoded"], [0x87] + list(PACKETS[index]))
        bad_ends = list(ends)
        bad_ends[0] += 1
        with self.assertRaises(ValueError):
            verify_timeline(starts, bad_ends, int(complete))
        channels["d0"][verified["accepted_sample"] + 20] ^= 1
        with self.assertRaises(ValueError):
            verify_selected(channels, 10)
