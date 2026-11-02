`timescale 1ns / 1ps

// Misma verificación ciclo a ciclo con índices/longitud de cuatro bits.
module motor_lpdt_15_TB;
  motor_lpdt_TB #(.ANCHO_LONGITUD(4)) prueba ();
endmodule
