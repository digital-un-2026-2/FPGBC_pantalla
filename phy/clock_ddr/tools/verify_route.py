"""Comprueba las tres E/S y sus rutas de reloj en una misma netlist."""

import argparse
import json
import re
from pathlib import Path


def require(condition, message):
    if not condition:
        raise SystemExit(f"Error en la sonda CLOCK_DDR: {message}")


def verify(build, variant):
    (module,) = json.loads((build / "probe_routed.json").read_text())["modules"].values()
    cells, nets = module["cells"], module["netnames"]
    log = (build / "probe.log").read_text()
    pll = cells["clocks.pll"]
    divider = cells["forwarded.divider"]
    fclk = pll["connections"]["CLKOUT"]
    pclk_byte = pll["connections"]["CLKOUTD"]
    pclk_110 = divider["connections"]["CLKOUT"]

    for name, bits in (("CLK_HS", fclk), ("CLK_BYTE", pclk_byte),
                       ("forwarded.PCLK_110", pclk_110)):
        require(nets[name]["bits"] == bits, f"fuente inesperada de {name}")
        require(f"'{name}' net was routed using global resources only." in log,
                f"{name} sin ruta exclusiva de reloj")
    hs_route = set(nets["CLK_HS"]["attributes"]["ROUTING"].split(";"))
    byte_route = set(nets["CLK_BYTE"]["attributes"]["ROUTING"].split(";"))
    local_route = set(nets["forwarded.PCLK_110"]["attributes"]["ROUTING"].split(";"))

    divider_site, divider_bel = divider["attributes"]["NEXTPNR_BEL"].split("/")
    require(divider["type"] == "CLKDIV" and divider["parameters"]["DIV_MODE"] == "2"
            and divider["connections"]["HCLKIN"] == fclk,
            "divisor incorrecto")
    require(any(pip.startswith(f"{divider_site}/{divider_bel}_HCLKIN/HCLK")
                for pip in hs_route), "no se encontró la rama HCLK del divisor")
    require(any(re.fullmatch(fr"{divider_site}/CLKDIV_[0-9]_CLKOUT/{divider_bel}_CLKOUT", pip)
                for pip in local_route), "no se encontró la salida del divisor hacia GCLK")
    reset_flops = [cell for name, cell in cells.items()
                   if name.startswith("forwarded.") and cell["type"] == "DFFNP"]
    iso = nets["ISO"]["bits"]
    require(len(reset_flops) == 2
            and all(cell["connections"]["CLK"] == fclk
                    and cell["connections"]["PRESET"] == iso for cell in reset_flops),
            "sincronizador de reset no conservado en CLK_HS")
    for cell in reset_flops:
        site = cell["attributes"]["NEXTPNR_BEL"].split("/")[0]
        require(any(re.fullmatch(fr"{site}/CLK[0-2]/GB[0-7]0", pip) for pip in hs_route),
                f"no se encontró reloj primario para el reset en {site}")

    serializers = (
        ("d0.serializer", "D0", "X39Y0", "OSER8", "ODDRX4", pclk_byte, byte_route, ("CLK0", "CLK1")),
        ("d1.serializer", "D1", "X41Y0", "OSER8", "ODDRX4", pclk_byte, byte_route, ("CLK0", "CLK1")),
        ("forwarded.serializer", "CLK", "X47Y0", "OSER4", "ODDRX2", pclk_110, local_route, ("CLK0",)),
    )
    for name, pair, site, primitive, mode, pclk, pclk_route, primary_pins in serializers:
        ser = cells[name]
        require(ser["type"] == primitive and ser["parameters"]["OUTMODE"] == mode
                and ser["attributes"]["NEXTPNR_BEL"] == f"{site}/IOLOGICAO",
                f"{name} no quedó como {primitive} en {site}")
        require(ser["connections"]["FCLK"] == fclk
                and any(re.fullmatch(fr"{site}/FCLKA/HCLK_OUT[13]", pip) for pip in hs_route),
                f"falta la rama HCLK a {name}")
        require(ser["connections"]["PCLK"] == pclk, f"PCLK incorrecto en {name}")
        for pin in primary_pins:
            require(any(re.fullmatch(fr"{site}/{pin}/GB[0-7]0", pip) for pip in pclk_route),
                    f"falta la rama primaria a {site}/{pin}")
        if primitive == "OSER8":
            aux = cells[f"{name}_aux$"]
            require(aux["type"] == "IOLOGIC_DUMMY" and aux["connections"]["PCLK"] == pclk
                    and aux["attributes"]["NEXTPNR_BEL"] == f"{site}/IOLOGICBO",
                    f"falta el IOLOGIC auxiliar de {name}")

        buffer_type = "TLVDS_TBUF" if pair == "CLK" else "TLVDS_OBUF"
        for side, bel in (("P", "IOBA"), ("N", "IOBB")):
            iob = cells[f"{pair}_{side}_OBUF_O"]
            require(iob["attributes"]["NEXTPNR_BEL"] == f"{site}/{bel}"
                    and iob["parameters"]["DIFF_TYPE"] == buffer_type
                    and iob["parameters"]["DIFF"] == side,
                    f"par diferencial incorrecto en {pair}_{side}")
            if side == "P":
                require(int(iob["parameters"]["IOLOGIC_IOB"], 2) == 1,
                        f"{pair} no usa salida local de IOLOGIC")
                if pair == "CLK":
                    require(iob["connections"]["OEN"] == iso,
                            "ISO no llega al OEN de la sonda")
        require(not ser["connections"]["Q0"], f"quedó una red ordinaria en el Q0 de {name}")

    ser = cells["forwarded.serializer"]
    if variant == "delay":
        require(ser["attributes"].get("IODELAY") == "OUT"
                and int(ser["parameters"].get("C_STATIC_DLY", "0"), 2) == 32,
                "IODELAY no quedó integrado con el valor de prueba")
    else:
        require("IODELAY" not in ser["attributes"], "se esperaba Q0 directo")
    print(f"PASS {variant}: D0/D1/CLK juntos, FCLK y PCLK dedicados, salida local e ISO a OEN")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("build", type=Path)
    parser.add_argument("variant", choices=("direct", "delay"))
    args = parser.parse_args()
    verify(args.build, args.variant)
