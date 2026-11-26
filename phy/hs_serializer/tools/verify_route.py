"""Comprueba en la sonda los sumideros de reloj y el empaquetado de ambos pares."""

import json
import re
import sys
from pathlib import Path


def require(condition, message):
    if not condition:
        raise SystemExit(f"Error en la sonda de HS_SERIALIZER: {message}")


def verify(build):
    (mod,) = json.loads((build / "probe_routed.json").read_text())["modules"].values()
    cells, nets = mod["cells"], mod["netnames"]
    pll = cells["clocks.pll"]
    require(pll["type"] == "rPLL", "falta la PLL de CLOCK_GEN")

    log = (build / "probe.log").read_text()
    pclk = pll["connections"]["CLKOUTD"]
    fclk = pll["connections"]["CLKOUT"]
    for name, bits in (("CLK_BYTE", pclk), ("CLK_HS", fclk)):
        require(nets[name]["bits"] == bits, f"{name} no viene de la PLL")
        require(f"'{name}' net was routed using global resources only." in log,
                f"{name} no tiene ruta exclusivamente de reloj")
    byte_route = set(nets["CLK_BYTE"]["attributes"]["ROUTING"].split(";"))
    hs_route = set(nets["CLK_HS"]["attributes"]["ROUTING"].split(";"))

    for lane, site in ((0, "X39Y0"), (1, "X41Y0")):
        name = f"d{lane}.serializer"
        ser = cells[name]
        aux = cells[f"{name}_aux$"]
        require(ser["type"] == "OSER8" and ser["parameters"]["OUTMODE"] == "ODDRX4"
                and ser["attributes"]["NEXTPNR_BEL"] == f"{site}/IOLOGICAO",
                f"{name} no quedó como OSER8 en {site}")
        require(aux["type"] == "IOLOGIC_DUMMY"
                and aux["attributes"]["NEXTPNR_BEL"] == f"{site}/IOLOGICBO",
                f"falta el sitio auxiliar de {name}")
        require(ser["connections"]["PCLK"] == aux["connections"]["PCLK"] == pclk
                and ser["connections"]["FCLK"] == fclk,
                f"relojes incorrectos en {name}")

        for local_clk in ("CLK0", "CLK1"):
            require(any(re.fullmatch(fr"{site}/{local_clk}/GB[0-7]0", pip) for pip in byte_route),
                    f"falta la rama de reloj primario a {site}/{local_clk}")
        require(any(re.fullmatch(fr"{site}/FCLKA/HCLK_OUT[13]", pip) for pip in hs_route),
                f"falta la rama HCLK a {site}/FCLKA")

        for polarity, half in (("P", "A"), ("N", "B")):
            iob = cells[f"D{lane}_{polarity}_OBUF_O"]
            require(iob["attributes"]["NEXTPNR_BEL"] == f"{site}/IOB{half}"
                    and iob["parameters"]["DIFF_TYPE"] == "TLVDS_OBUF"
                    and iob["parameters"]["DIFF"] == polarity,
                    f"par diferencial incorrecto para D{lane}_{polarity}")
            if polarity == "P":
                require(int(iob["parameters"]["IOLOGIC_IOB"], 2) == 1,
                        f"Q0 de {name} no usa el camino local a la E/S")
        require(not ser["connections"]["Q0"], f"queda una red ordinaria en Q0 de {name}")
        print(f"PASS D{lane} en {site}: PCLK por CLK0/CLK1, FCLK por FCLKA, salida diferencial local")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
