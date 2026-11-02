module rom_paquetes (
    input  wire [6:0] direccion,
    output reg  [7:0] dato
);

  always @(*) begin

    case (direccion)
      // Paso 0: Software Reset
      7'd0: dato = 8'h05;
      7'd1: dato = 8'h01;
      7'd2: dato = 8'h00;
      7'd3: dato = 8'h10;

      // Paso 1: B0 00
      7'd4: dato = 8'h15;
      7'd5: dato = 8'hB0;
      7'd6: dato = 8'h00;
      7'd7: dato = 8'h3A;

      // Paso 2: E4 00 00 00 00 08
      7'd8:  dato = 8'h39;
      7'd9:  dato = 8'h06;
      7'd10: dato = 8'h00;
      7'd11: dato = 8'h30;
      7'd12: dato = 8'hE4;
      7'd13: dato = 8'h00;
      7'd14: dato = 8'h00;
      7'd15: dato = 8'h00;
      7'd16: dato = 8'h00;
      7'd17: dato = 8'h08;
      7'd18: dato = 8'h87;  // CRC bajo, NO selector LPDT
      7'd19: dato = 8'h16;

      // Paso 3: D0 45 45 71
      7'd20: dato = 8'h39;
      7'd21: dato = 8'h04;
      7'd22: dato = 8'h00;
      7'd23: dato = 8'h2C;
      7'd24: dato = 8'hD0;
      7'd25: dato = 8'h45;
      7'd26: dato = 8'h45;
      7'd27: dato = 8'h71;
      7'd28: dato = 8'h42;
      7'd29: dato = 8'h9E;

      // Paso 4: 6F 01
      7'd30: dato = 8'h15;
      7'd31: dato = 8'h6F;
      7'd32: dato = 8'h01;
      7'd33: dato = 8'h2B;

      // Paso 5: Exit Sleep
      7'd34: dato = 8'h05;
      7'd35: dato = 8'h11;
      7'd36: dato = 8'h00;
      7'd37: dato = 8'h36;

      // Paso 6: D0 52 4A 71
      7'd38: dato = 8'h39;
      7'd39: dato = 8'h04;
      7'd40: dato = 8'h00;
      7'd41: dato = 8'h2C;
      7'd42: dato = 8'hD0;
      7'd43: dato = 8'h52;
      7'd44: dato = 8'h4A;
      7'd45: dato = 8'h71;
      7'd46: dato = 8'h1A;
      7'd47: dato = 8'h14;

      // Paso 7: BE FF 0F 00 18 04 04 00 5D
      7'd48: dato = 8'h39;
      7'd49: dato = 8'h09;
      7'd50: dato = 8'h00;
      7'd51: dato = 8'h30;
      7'd52: dato = 8'hBE;
      7'd53: dato = 8'hFF;
      7'd54: dato = 8'h0F;
      7'd55: dato = 8'h00;
      7'd56: dato = 8'h18;
      7'd57: dato = 8'h04;
      7'd58: dato = 8'h04;
      7'd59: dato = 8'h00;
      7'd60: dato = 8'h5D;
      7'd61: dato = 8'hE7;
      7'd62: dato = 8'hC4;

      // Paso 8: BB 2F
      7'd63: dato = 8'h15;
      7'd64: dato = 8'hBB;
      7'd65: dato = 8'h2F;
      7'd66: dato = 8'h39;

      // Paso 9: B0 2F
      7'd67: dato = 8'h15;
      7'd68: dato = 8'hB0;
      7'd69: dato = 8'h2F;
      7'd70: dato = 8'h1A;

      // Paso 10: Display On
      7'd71: dato = 8'h05;
      7'd72: dato = 8'h29;
      7'd73: dato = 8'h00;
      7'd74: dato = 8'h1C;

      default: dato = 8'h00;
    endcase

  end

endmodule
