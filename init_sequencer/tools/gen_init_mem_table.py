"""Convierte la imagen fijada en una tabla de lectura combinacional."""

import argparse
import hashlib
from pathlib import Path

ROM_SHA256 = "e68a62c8b9499de10a6034a9701137fc5b76478890022f9f310abd36689ea7b4"
ROM_WORDS = 223


def rom_case(image: Path) -> str:
    data = image.read_bytes()
    actual_sha = hashlib.sha256(data).hexdigest()
    if actual_sha != ROM_SHA256:
        raise ValueError(f"{image}: SHA-256 {actual_sha}; se esperaba {ROM_SHA256}")

    words = [int(line, 16) for line in data.decode("ascii").splitlines()]
    if len(words) != ROM_WORDS or any(not 0 <= word < (1 << 11) for word in words):
        raise ValueError(f"{image}: se requieren {ROM_WORDS} palabras de 11 bits")

    return "// Generado de init_mem.hex; no editar.\n" + "".join(
        f"      8'd{addr}: WORD = 11'h{word:03X};\n" for addr, word in enumerate(words)
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    try:
        args.output.write_text(rom_case(args.image), encoding="ascii", newline="\n")
    except (OSError, ValueError) as exc:
        parser.exit(1, f"{exc}\n")


if __name__ == "__main__":
    main()
