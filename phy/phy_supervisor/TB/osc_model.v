`timescale 1ns / 1fs

module OSC #(
    parameter integer FREQ_DIV = 100,
    parameter integer TEST_HZ = 25_000_000,
    parameter DEVICE = "GW2A-18"
) (
    output reg OSCOUT = 1'b0
);
  initial if (FREQ_DIV != 10 || DEVICE != "GW2AR-18")
    $fatal(1, "Configuración de OSC inesperada");
  always #(500_000_000.0 / TEST_HZ) OSCOUT = !OSCOUT;
endmodule

module BUFG (input I, output O);
  assign O = I;
endmodule
