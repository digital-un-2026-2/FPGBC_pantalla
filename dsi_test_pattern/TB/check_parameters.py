"""Los perfiles invalidos deben fallar antes de ejecutar la simulacion."""
import argparse
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--iverilog", default="iverilog")
parser.add_argument("--yosys", default="yosys")
args = parser.parse_args()
sources = sorted((Path(__file__).resolve().parents[1] / "src").glob("*.v"))
profiles = [(8, 1, True), (16, 2, True), (24, 3, True), (720, 720, True),
            (0, 1, False), (7, 1, False), (9, 1, False), (-8, 1, False),
            (8, 0, False), (8, -1, False)]
for width, height, valid in profiles:
    commands = [
        [args.iverilog, "-g2012", "-Wall", "-s", "dsi_test_pattern", "-t", "null",
         f"-Pdsi_test_pattern.WIDTH={width}", f"-Pdsi_test_pattern.HEIGHT={height}",
         *map(str, sources)],
        [args.yosys, "-Q", "-T", "-p",
         f"read_verilog {' '.join(map(str, sources))}; "
         f"chparam -set WIDTH 32'h{width & 0xffffffff:08x} "
         f"-set HEIGHT 32'h{height & 0xffffffff:08x} dsi_test_pattern; "
         "hierarchy -check -top dsi_test_pattern"],
    ]
    for command in commands:
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        assert (result.returncode == 0) == valid, (command, result.stdout, result.stderr)
        if not valid:
            assert "DSI_TEST_PATTERN_REQUIRES" in result.stdout + result.stderr, (
                width, height, command, result.stdout, result.stderr)
print("PASS parametros: 4 perfiles legales y 6 invalidos en Icarus y Yosys")
