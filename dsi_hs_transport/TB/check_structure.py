"""Check the default generic Yosys netlist; no manufacturer mapping implied."""
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    netlist = json.load(source)
memories = []
ff_bits = 0
for module in netlist["modules"].values():
    for cell in module.get("cells", {}).values():
        kind = cell["type"]
        params = cell.get("parameters", {})
        if kind == "$mem_v2":
            memories.append((int(params["WIDTH"], 2), int(params["SIZE"], 2)))
            for key in ("RD_CLK_ENABLE", "WR_CLK_ENABLE", "RD_CLK_POLARITY", "WR_CLK_POLARITY"):
                assert int(params[key], 2) == 1, key
            assert set(params["RD_ARST_VALUE"]) <= {"x"}
            assert set(params["RD_SRST_VALUE"]) <= {"x"}
        if "dff" in kind.lower():
            assert kind in ("$dff", "$dffe", "$sdff", "$sdffe", "$sdffce"), kind
            assert int(params["CLK_POLARITY"], 2) == 1
            ff_bits += int(params["WIDTH"], 2)
        assert "latch" not in kind.lower(), kind
assert memories == [(18, 2048)], memories
assert ff_bits == 29, ff_bits  # COUNT[12], INDEX[11], STATE[3], DONE[1], CAUSE[2].
print("PASS structure: RAM 2048x18 with synchronous posedge read/write; 29 external FF bits, no latches or asynchronous resets")
