#!/usr/bin/env python3
"""Entrada del empaquetador comprobado; no programa dispositivos."""

from pathlib import Path
import sys

# LiteX ejecuta el empaquetador desde build/, no desde la raíz del repositorio.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from gateware.tests.review_fuses import main


if __name__ == "__main__":
    raise SystemExit(main())
