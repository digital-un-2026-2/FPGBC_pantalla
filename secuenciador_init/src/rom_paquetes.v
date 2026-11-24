// Bytes exactos de LP_MIPI_DSI.kvdat: cabecera/ECC, payload y CRC.
// No incluye el selector 87, añadido por motor_lpdt.
module rom_paquetes (
    input  wire [7:0] direccion,
    output reg  [7:0] dato
);
  always @(*) begin
    case (direccion)
      // Paso 0: 29 02 00 00 B0 00 D6 CA
      8'd0: dato = 8'h29;
      8'd1: dato = 8'h02;
      8'd2: dato = 8'h00;
      8'd3: dato = 8'h00;
      8'd4: dato = 8'hB0;
      8'd5: dato = 8'h00;
      8'd6: dato = 8'hD6;
      8'd7: dato = 8'hCA;
      // Paso 1: E4
      8'd8: dato = 8'h29;
      8'd9: dato = 8'h06;
      8'd10: dato = 8'h00;
      8'd11: dato = 8'h23;
      8'd12: dato = 8'hE4;
      8'd13: dato = 8'h00;
      8'd14: dato = 8'h00;
      8'd15: dato = 8'h00;
      8'd16: dato = 8'h00;
      8'd17: dato = 8'h08;
      8'd18: dato = 8'h87;  // CRC bajo, no selector
      8'd19: dato = 8'h16;
      // Paso 2: D0 45 45 71
      8'd20: dato = 8'h29;
      8'd21: dato = 8'h04;
      8'd22: dato = 8'h00;
      8'd23: dato = 8'h3F;
      8'd24: dato = 8'hD0;
      8'd25: dato = 8'h45;
      8'd26: dato = 8'h45;
      8'd27: dato = 8'h71;
      8'd28: dato = 8'h42;
      8'd29: dato = 8'h9E;
      // Paso 3: Null Packet
      8'd30: dato = 8'h09;
      8'd31: dato = 8'h02;
      8'd32: dato = 8'h00;
      8'd33: dato = 8'h15;
      8'd34: dato = 8'h00;
      8'd35: dato = 8'h00;
      8'd36: dato = 8'hB8;
      8'd37: dato = 8'hF0;
      // Paso 4: Sleep Out; Data1=45 se conserva sin interpretarlo como parámetro
      8'd38: dato = 8'h05;
      8'd39: dato = 8'h11;
      8'd40: dato = 8'h45;
      8'd41: dato = 8'h04;
      // Paso 5: D0 52 4A
      8'd42: dato = 8'h29;
      8'd43: dato = 8'h03;
      8'd44: dato = 8'h00;
      8'd45: dato = 8'h1A;
      8'd46: dato = 8'hD0;
      8'd47: dato = 8'h52;
      8'd48: dato = 8'h4A;
      8'd49: dato = 8'h25;
      8'd50: dato = 8'hBB;
      // Paso 6: B9
      8'd51: dato = 8'h29;
      8'd52: dato = 8'h0D;
      8'd53: dato = 8'h00;
      8'd54: dato = 8'h00;
      8'd55: dato = 8'hB9;
      8'd56: dato = 8'h02;
      8'd57: dato = 8'h00;
      8'd58: dato = 8'h76;
      8'd59: dato = 8'h00;
      8'd60: dato = 8'hBA;
      8'd61: dato = 8'hBB;
      8'd62: dato = 8'hBF;
      8'd63: dato = 8'hCC;
      8'd64: dato = 8'hE3;
      8'd65: dato = 8'h46;
      8'd66: dato = 8'h81;
      8'd67: dato = 8'h31;
      8'd68: dato = 8'hD0;
      8'd69: dato = 8'hE5;
      // Paso 7: BD
      8'd70: dato = 8'h29;
      8'd71: dato = 8'h0C;
      8'd72: dato = 8'h00;
      8'd73: dato = 8'h1A;
      8'd74: dato = 8'hBD;
      8'd75: dato = 8'hFF;
      8'd76: dato = 8'hFE;
      8'd77: dato = 8'hFE;
      8'd78: dato = 8'hFE;
      8'd79: dato = 8'hFE;
      8'd80: dato = 8'hFE;
      8'd81: dato = 8'hFE;
      8'd82: dato = 8'h80;
      8'd83: dato = 8'h20;
      8'd84: dato = 8'h00;
      8'd85: dato = 8'h00;
      8'd86: dato = 8'h2A;
      8'd87: dato = 8'hE3;
      // Paso 8: BE
      8'd88: dato = 8'h29;
      8'd89: dato = 8'h09;
      8'd90: dato = 8'h00;
      8'd91: dato = 8'h23;
      8'd92: dato = 8'hBE;
      8'd93: dato = 8'hFF;
      8'd94: dato = 8'h0F;
      8'd95: dato = 8'h00;
      8'd96: dato = 8'h18;
      8'd97: dato = 8'h04;
      8'd98: dato = 8'h04;
      8'd99: dato = 8'h00;
      8'd100: dato = 8'h5D;
      8'd101: dato = 8'hE7;
      8'd102: dato = 8'hC4;
      // Paso 9: B0 03
      8'd103: dato = 8'h29;
      8'd104: dato = 8'h02;
      8'd105: dato = 8'h00;
      8'd106: dato = 8'h00;
      8'd107: dato = 8'hB0;
      8'd108: dato = 8'h03;
      8'd109: dato = 8'h4D;
      8'd110: dato = 8'hF8;
      // Paso 10: Null Packet
      8'd111: dato = 8'h09;
      8'd112: dato = 8'h02;
      8'd113: dato = 8'h00;
      8'd114: dato = 8'h15;
      8'd115: dato = 8'h00;
      8'd116: dato = 8'h00;
      8'd117: dato = 8'hB8;
      8'd118: dato = 8'hF0;
      // Paso 11: Display On; Data1=03
      8'd119: dato = 8'h05;
      8'd120: dato = 8'h29;
      8'd121: dato = 8'h03;
      8'd122: dato = 8'h1F;
      // Paso 12: B0 00 (cruza la dirección 127)
      8'd123: dato = 8'h29;
      8'd124: dato = 8'h02;
      8'd125: dato = 8'h00;
      8'd126: dato = 8'h00;
      8'd127: dato = 8'hB0;
      8'd128: dato = 8'h00;
      8'd129: dato = 8'hD6;
      8'd130: dato = 8'hCA;
      // Paso 13: BE repetido
      8'd131: dato = 8'h29;
      8'd132: dato = 8'h09;
      8'd133: dato = 8'h00;
      8'd134: dato = 8'h23;
      8'd135: dato = 8'hBE;
      8'd136: dato = 8'hFF;
      8'd137: dato = 8'h0F;
      8'd138: dato = 8'h00;
      8'd139: dato = 8'h18;
      8'd140: dato = 8'h04;
      8'd141: dato = 8'h04;
      8'd142: dato = 8'h00;
      8'd143: dato = 8'h5D;
      8'd144: dato = 8'hE7;
      8'd145: dato = 8'hC4;
      // Paso 14: B7, máximo de 22 bytes DSI
      8'd146: dato = 8'h29;
      8'd147: dato = 8'h10;
      8'd148: dato = 8'h00;
      8'd149: dato = 8'h3A;
      8'd150: dato = 8'hB7;
      8'd151: dato = 8'h18;
      8'd152: dato = 8'h00;
      8'd153: dato = 8'h18;
      8'd154: dato = 8'h18;
      8'd155: dato = 8'h0C;
      8'd156: dato = 8'h09;
      8'd157: dato = 8'hAC;
      8'd158: dato = 8'h09;
      8'd159: dato = 8'h5C;
      8'd160: dato = 8'h09;
      8'd161: dato = 8'h0C;
      8'd162: dato = 8'h09;
      8'd163: dato = 8'h00;
      8'd164: dato = 8'h10;
      8'd165: dato = 8'h00;
      8'd166: dato = 8'h44;
      8'd167: dato = 8'h32;
      // Paso 15: B8
      8'd168: dato = 8'h29;
      8'd169: dato = 8'h0E;
      8'd170: dato = 8'h00;
      8'd171: dato = 8'h06;
      8'd172: dato = 8'hB8;
      8'd173: dato = 8'hF8;
      8'd174: dato = 8'hDA;
      8'd175: dato = 8'h6D;
      8'd176: dato = 8'hFB;
      8'd177: dato = 8'hFF;
      8'd178: dato = 8'hFF;
      8'd179: dato = 8'h4F;
      8'd180: dato = 8'h1F;
      8'd181: dato = 8'h7F;
      8'd182: dato = 8'h9F;
      8'd183: dato = 8'hBF;
      8'd184: dato = 8'hDF;
      8'd185: dato = 8'hFF;
      8'd186: dato = 8'hAB;
      8'd187: dato = 8'h18;
      // Paso 16: BB 2F
      8'd188: dato = 8'h29;
      8'd189: dato = 8'h02;
      8'd190: dato = 8'h00;
      8'd191: dato = 8'h00;
      8'd192: dato = 8'hBB;
      8'd193: dato = 8'h2F;
      8'd194: dato = 8'h8B;
      8'd195: dato = 8'hF7;
      // Paso 17: B0 03
      8'd196: dato = 8'h29;
      8'd197: dato = 8'h02;
      8'd198: dato = 8'h00;
      8'd199: dato = 8'h00;
      8'd200: dato = 8'hB0;
      8'd201: dato = 8'h03;
      8'd202: dato = 8'h4D;
      8'd203: dato = 8'hF8;
      default: dato = 8'h00;
    endcase
  end
endmodule
