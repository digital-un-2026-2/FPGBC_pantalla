`timescale 1ns / 1ps

// Recorre 1..31 bytes y prueba el paquete B7 de 22 bytes capturado.
module motor_lpdt_31_TB;
  motor_lpdt_TB #(.ANCHO_LONGITUD(5)) prueba ();
endmodule
