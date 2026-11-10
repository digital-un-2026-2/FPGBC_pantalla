"""Inspeccion de netlist generica por defecto, anterior al mapeo de FPGA."""
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    top = json.load(source)["modules"]["dsi_test_pattern"]
bits = 0
banks = 0
for cell in top.get("cells", {}).values():
    kind = cell["type"]
    assert "latch" not in kind.lower(), kind
    assert "mem" not in kind.lower(), kind
    assert kind not in ("$div", "$mod", "$divfloor", "$modfloor"), kind
    if "dff" in kind.lower():
        assert kind in ("$dff", "$dffe", "$sdff", "$sdffe", "$sdffce"), kind
        assert int(cell["parameters"]["CLK_POLARITY"], 2) == 1
        assert cell["connections"]["CLK"] == top["ports"]["clk"]["bits"]
        bits += int(cell["parameters"]["WIDTH"], 2)
        banks += 1
assert bits == 24, bits
assert banks == 5, banks
print("PASS estructura 720x720: 24 bits en 5 bancos posedge, sin latches, RAM, reset asincrono ni divisor")
