"""Adapta place() de Apicula 0.32 para el PHY mixto GW2A-18C."""

from hashlib import sha256
from importlib.metadata import version
import inspect
from pathlib import Path

from apycula import gowin_pack as pack


PACKER_SHA256 = "176cf71a8b17ce8e2e36809cdf5ab1c429acdb54538b9f7725ffc83df145a529"


def mixed_place(*, data_only=False):
    """Devuelve el codificador adaptado y el hash de su fuente efectiva."""
    path = Path(pack.__file__)
    if version("apycula") != "0.32" or sha256(path.read_bytes()).hexdigest() != PACKER_SHA256:
        raise ValueError("El adaptador LP/HS requiere el gowin_pack.py revisado de Apicula 0.32")

    lines, first = inspect.getsourcelines(pack.place)
    source = "".join(lines)
    # Mantener LVDS25 en los IOB activos y usar LVCMOS25 solo como estándar
    # de respaldo para los pines sin usar de ese banco.
    old_bank = """        if not vccio:
            if device not in {'GW5A-25A', 'GW5AST-138C'}:
"""
    new_bank = """        if device == 'GW2A-18C' and bank == 1:
            modes = [(iob.flags['mode'], iob.attrs['IO_TYPE']) for iob in ios.values()]
            # RESET_N es IBUF LVCMOS25 y no selecciona la tensión del banco.
            if (vccio is not None or modes.count(('TLVDS_TBUF', 'LVDS25')) != 3
                    or set(modes) - {('IBUF', 'LVCMOS25'), ('TLVDS_TBUF', 'LVDS25')}):
                raise ValueError("Banco 1 fuera del perfil de tres salidas TLVDS_TBUF/LVDS25")
            vccio = _vcc_ios['LVDS25']
            iostd = 'LVCMOS25'
        if not vccio:
            if device not in {'GW5A-25A', 'GW5AST-138C'}:
"""
    old_drive = "if mode[1:].startswith('LVDS') and in_iob_attrs['DRIVE'] != '0':"
    new_drive = "if iob.flags['mode'][1:].startswith('LVDS') and in_iob_attrs['DRIVE'] != '0':"
    if data_only:
        new_bank = """        if device == 'GW2A-18C' and bank == 1:
            modes = [(iob.flags['mode'], iob.attrs['IO_TYPE']) for iob in ios.values()]
            if (vccio not in (None, _vcc_ios['LVDS25'])
                    or modes.count(('TLVDS_TBUF', 'LVDS25')) != 2
                    or modes.count(('IOBUF', 'LVCMOS25')) != 2
                    or set(modes) - {('IBUF', 'LVCMOS25'), ('IOBUF', 'LVCMOS25'),
                                     ('TLVDS_TBUF', 'LVDS25')}):
                raise ValueError("Banco 1 fuera del perfil DATA_ONLY de dos TLVDS y dos IOBUF")
            vccio = _vcc_ios['LVDS25']
            iostd = 'LVCMOS25'
        if not vccio:
            if device not in {'GW5A-25A', 'GW5AST-138C'}:
"""
    for old, new in ((old_bank, new_bank), (old_drive, new_drive)):
        if source.count(old) != 1:
            raise ValueError("No se encontró un único punto de adaptación en Apicula place()")
        source = source.replace(old, new)

    namespace = {}
    code = compile("\n" * (first - 1) + source, f"{path} [adaptador LP/HS]", "exec")
    exec(code, vars(pack), namespace)
    return namespace["place"], sha256(source.encode()).hexdigest()
