module rom_descriptores (
    input  wire [ 3:0] paso,
    output reg  [33:0] descriptor
);

  always @(*) begin
    case (paso)
      //                    base   longitud  espera
      4'd0: descriptor = {7'd0, 4'd4, 23'd800000};
      4'd1: descriptor = {7'd4, 4'd4, 23'd200000};
      4'd2: descriptor = {7'd8, 4'd12, 23'd0};
      4'd3: descriptor = {7'd20, 4'd10, 23'd0};
      4'd4: descriptor = {7'd30, 4'd4, 23'd0};
      4'd5: descriptor = {7'd34, 4'd4, 23'd4800000};
      4'd6: descriptor = {7'd38, 4'd10, 23'd0};
      4'd7: descriptor = {7'd48, 4'd15, 23'd0};
      4'd8: descriptor = {7'd63, 4'd4, 23'd0};
      4'd9: descriptor = {7'd67, 4'd4, 23'd800000};
      4'd10: descriptor = {7'd71, 4'd4, 23'd4800000};
      default: descriptor = 34'd0;
    endcase

  end


endmodule
