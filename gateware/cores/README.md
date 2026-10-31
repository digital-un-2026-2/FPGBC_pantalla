# Bloques de la integración

[Gateware](../README.md) · [Registros y depuración](../../docs/litex_debug.md)

| Archivo | Qué hace |
|---|---|
| `motor_lpdt.py` | Wrapper: presenta las señales del motor Verilog como señales Migen; no reimplementa el motor |
| `lpdt_debug.py` | Supervisor CSR: recibe bytes del PC, conserva una copia estable y coordina petición, aceptación y fin |
| `debug_regs.py` | Diagnóstico del bus: una entrada, su valor más uno y un contador de ciclos |
| `__init__.py` | Permite importar esta carpeta como paquete Python |

CSR significa registros de control y estado. El PC prepara de 1 a 7 bytes y
escribe la orden de iniciar. El supervisor rechaza órdenes durante ocupado,
sin cola, y mantiene el paquete activo inmutable hasta terminar.

El permiso del motor se fija a uno solo para la prueba interna; no autoriza
drivers eléctricos. Los bloques se integran con el target, no se ejecutan solos:

```sh
pixi run python -m gateware.targets.debug
```

El wrapper necesita las fuentes de `motor_lpdt/src/`, añadidas explícitamente
por el target. Para su contrato, consultar [el motor](../../motor_lpdt/README.md).
Las simulaciones del motor no cubren el supervisor CSR ni la integración LiteX.
