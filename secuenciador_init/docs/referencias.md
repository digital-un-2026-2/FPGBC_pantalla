# Referencias de la secuencia

Contraste documental del 2026-11-02 de los comandos y esperas de
`jdi_panel_init()` y `jdi_panel_on()` en `panel-jdi-lt031mdz4000.c`:

- [will-tm, revisión fa7f622275c11bffb6bdf3946ec9987918a52d47](https://github.com/will-tm/RPI-LCD-LT031MDZ4000/blob/fa7f622275c11bffb6bdf3946ec9987918a52d47/panel-jdi-lt031mdz4000.c).
- [jamwu, revisión 22798c7a7ee714f0a17a0979ab6f09c7c86d3313](https://github.com/jamwu/RPI-LCD-LT031MDZ4000/blob/22798c7a7ee714f0a17a0979ab6f09c7c86d3313/panel-jdi-lt031mdz4000.c).

Ambos archivos declaran **GPL-2.0-only**. Se conserva esta atribución como
referencia de los valores; no se incorpora su implementación C. Revisar licencia
y atribuciones antes de trasladar código de esos proyectos.

Coinciden los 11 comandos, su orden y las esperas. Aquí se eligen 20 ms dentro
del intervalo de 10–20 ms tras Software Reset. Los drivers solicitan LP durante
el arranque y usan GPIO de reset/backlight que esta placa no ofrece.

La prueba integrada verifica ECC y CRC de los paquetes preparados, no la
recepción del panel. El [datasheet LT031MDZ4000](https://www.panoxdisplay.com/uploadfile/datasheet/LT031MDZ4000.pdf)
no sustituye la identificación de la variante exacta ni valida estos registros
privados o su funcionamiento en el ejemplar FPGBC.
