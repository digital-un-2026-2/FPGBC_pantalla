// LP_MIPI_DSI.kvdat: 18 paquetes, 204 bytes DSI, sin selector 87.
// Espera posterior nominal a 40 MHz. El control añade su overhead entre envíos.
module rom_descriptores (
    input  wire [ 4:0] paso,
    output reg  [35:0] descriptor
);
  always @(*) begin
    case (paso)
      //                    base     longitud  espera (ciclos)
      5'd0:  descriptor = {8'd0,   5'd8,  23'd360000};
      5'd1:  descriptor = {8'd8,   5'd12, 23'd360000};
      5'd2:  descriptor = {8'd20,  5'd10, 23'd360000};
      5'd3:  descriptor = {8'd30,  5'd8,  23'd360000};
      5'd4:  descriptor = {8'd38,  5'd4,  23'd2600000};
      5'd5:  descriptor = {8'd42,  5'd9,  23'd360000};
      5'd6:  descriptor = {8'd51,  5'd19, 23'd360000};
      5'd7:  descriptor = {8'd70,  5'd18, 23'd360000};
      5'd8:  descriptor = {8'd88,  5'd15, 23'd360000};
      5'd9:  descriptor = {8'd103, 5'd8,  23'd2600000};
      5'd10: descriptor = {8'd111, 5'd8,  23'd360000};
      5'd11: descriptor = {8'd119, 5'd4,  23'd360000};
      5'd12: descriptor = {8'd123, 5'd8,  23'd360000};
      5'd13: descriptor = {8'd131, 5'd15, 23'd360000};
      5'd14: descriptor = {8'd146, 5'd22, 23'd360000};
      5'd15: descriptor = {8'd168, 5'd20, 23'd360000};
      5'd16: descriptor = {8'd188, 5'd8,  23'd360000};
      // No se observó un siguiente paquete LP: sin espera adicional final.
      5'd17: descriptor = {8'd196, 5'd8,  23'd0};
      default: descriptor = 36'd0;
    endcase
  end
endmodule
