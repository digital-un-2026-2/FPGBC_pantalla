`timescale 1ns / 1ps

module hs_packer_TB;
  localparam PIXELES = 720;
  localparam BYTES_CARGA = PIXELES * 3;
  localparam PALABRAS_CARGA = BYTES_CARGA / 2;
  localparam W_CRC = 2 + PALABRAS_CARGA;

  reg CLK_BYTE = 0;
  always #10 CLK_BYTE = !CLK_BYTE;
  reg RST_BYTE = 1;
  reg PK_START = 0;
  reg sot_en = 0;
  reg captura_word = 0;

  reg [7:0] video_mem [0:BYTES_CARGA-1];
  integer lecturas;
  integer capturas;
  wire [15:0] VID_WORD = (lecturas < PALABRAS_CARGA) ?
      {video_mem[2*lecturas + 1], video_mem[2*lecturas]} : 16'hxxxx;
  wire VID_RD, PK_DONE;
  wire [15:0] WORD;
  reg [15:0] palabra_phy;

  hs_packer dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .PK_START(PK_START),
      .VID_WORD(VID_WORD), .VID_RD(VID_RD), .PK_DONE(PK_DONE), .WORD(WORD)
  );

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("hs_packer_TB.fst");
      $dumpvars(1, hs_packer_TB, dut);
    end
  end

  // Modelos: VIDEO_SOURCE adelanta la palabra actual; PHY_IF captura el bus
  // anterior al flanco, o inserta SoT por fuera del DUT.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) begin
      lecturas <= 0;
      capturas <= 0;
      palabra_phy <= 16'h0000;
    end else if (sot_en) begin
      lecturas <= 0;
      capturas <= 1;
      palabra_phy <= 16'hb8b8;
    end else begin
      if (VID_RD) begin
        if (lecturas >= PALABRAS_CARGA)
          $fatal(1, "FAIL: lectura después de agotar VIDEO_MEM");
        lecturas <= lecturas + 1;
      end
      if (captura_word) begin
        capturas <= capturas + 1;
        palabra_phy <= WORD;
      end
    end
  end

  task cargar_barras(input [7:0] cambio_d0, input [7:0] cambio_d1);
    integer p;
    reg [23:0] rgb;
    begin
      for (p = 0; p < PIXELES; p = p + 1) begin
        case (p / 120)
          0: rgb = 24'hc91f54;
          1: rgb = 24'h17e388;
          2: rgb = 24'h53a910;
          3: rgb = 24'hbd2273;
          4: rgb = 24'h4d86fb;
          default: rgb = 24'hdc4781;
        endcase
        {video_mem[3*p], video_mem[3*p + 1], video_mem[3*p + 2]} = rgb;
      end
      video_mem[BYTES_CARGA-2] = video_mem[BYTES_CARGA-2] ^ cambio_d0;
      video_mem[BYTES_CARGA-1] = video_mem[BYTES_CARGA-1] ^ cambio_d1;
    end
  endtask

  // Referencia por bytes en orden RGB: registro orientado hacia el MSB
  // (0x1021), alimentado LSB primero; se refleja el resultado para los carriles.
  function [15:0] crc_referencia(input integer cantidad);
    reg [15:0] resto;
    integer n, b;
    begin
      resto = 16'hffff;
      for (n = 0; n < cantidad; n = n + 1)
        for (b = 0; b < 8; b = b + 1)
          resto = (resto << 1) ^ ((resto[15] ^ video_mem[n][b]) ? 16'h1021 : 16'h0000);
      for (b = 0; b < 16; b = b + 1) crc_referencia[b] = resto[15-b];
    end
  endfunction

  task comprobar_reposo;
    if (WORD !== 16'h703e || VID_RD !== 1'b0 || PK_DONE !== 1'b0)
      $fatal(1, "FAIL: reposo sin W0 preparada o con lectura/fin");
  endtask

  task comprobar_palabra(input integer n, input [7:0] d0, input [7:0] d1);
    begin
      @(negedge CLK_BYTE);
      if (VID_RD !== ((n >= 2) && (n < W_CRC)) || PK_DONE !== 1'b0)
        $fatal(1, "FAIL: antes de capturar W%0d, VID_RD=%b PK_DONE=%b", n, VID_RD, PK_DONE);
      #1;
      if (palabra_phy[7:0] !== d0 || palabra_phy[15:8] !== d1 || capturas !== n + 2)
        $fatal(1, "FAIL: W%0d D0/D1=%02h/%02h, se esperaba %02h/%02h",
               n, palabra_phy[7:0], palabra_phy[15:8], d0, d1);
      if (PK_DONE !== (n == W_CRC))
        $fatal(1, "FAIL: después de capturar W%0d, PK_DONE=%b", n, PK_DONE);
    end
  endtask

  task enviar_cabecera;
    begin
      @(posedge CLK_BYTE);
      sot_en = 1;
      @(negedge CLK_BYTE);
      comprobar_reposo;
      #1;
      if (palabra_phy !== 16'hb8b8 || capturas !== 1)
        $fatal(1, "FAIL: captura de SoT en el modelo");

      @(posedge CLK_BYTE);
      sot_en = 0;
      captura_word = 1;
      PK_START = 1;
      comprobar_palabra(0, 8'h3e, 8'h70);
      @(posedge CLK_BYTE);
      PK_START = 0;
      comprobar_palabra(1, 8'h08, 8'h13);
    end
  endtask

  task enviar_linea;
    reg [15:0] esperado;
    integer p;
    begin
      esperado = crc_referencia(BYTES_CARGA);
      enviar_cabecera;
      for (p = 0; p < PALABRAS_CARGA; p = p + 1) begin
        @(posedge CLK_BYTE);
        PK_START = (p == 13);  // Un pulso durante la carga no reinicia el paquete.
        comprobar_palabra(p + 2, video_mem[2*p], video_mem[2*p + 1]);
      end
      if (WORD !== esperado || VID_RD !== 1'b0 || lecturas !== PALABRAS_CARGA)
        $fatal(1, "FAIL: W1081 no dejó listo el CRC final o hubo %0d lecturas", lecturas);

      comprobar_palabra(W_CRC, esperado[7:0], esperado[15:8]);
      if (WORD !== 16'h0000 || VID_RD !== 1'b0)
        $fatal(1, "FAIL: se presentó una palabra después de W1082");
      @(posedge CLK_BYTE);
      if (PK_DONE !== 1'b1) $fatal(1, "FAIL: LINK_FSM no vio PK_DONE en posedge");
      captura_word = 0;
      @(negedge CLK_BYTE); #1;
      comprobar_reposo;
      if (capturas !== W_CRC + 2 || palabra_phy !== esperado)
        $fatal(1, "FAIL: captura adicional después del CRC");
      $display("PASS: %0d palabras del packer, %0d lecturas, CRC=%04h",
               W_CRC + 1, lecturas, esperado);
    end
  endtask

  task abortar_con_reset;
    begin
      enviar_cabecera;
      comprobar_palabra(2, video_mem[0], video_mem[1]);
      @(posedge CLK_BYTE);
      RST_BYTE = 1;
      captura_word = 0;
      #1;
      if (VID_RD !== 1'b1 || dut.CRC_WORD !== crc_referencia(2))
        $fatal(1, "FAIL: reset actuó antes del negedge");
      @(negedge CLK_BYTE); #1;
      comprobar_reposo;
      if (dut.CRC_WORD !== 16'hffff) $fatal(1, "FAIL: reset del CRC");
      @(posedge CLK_BYTE);
      RST_BYTE = 0;
    end
  endtask

  initial begin
    cargar_barras(8'h00, 8'h00);
    @(negedge CLK_BYTE); #1;
    comprobar_reposo;
    @(posedge CLK_BYTE);
    RST_BYTE = 0;
    repeat (3) begin
      @(negedge CLK_BYTE); #1;
      comprobar_reposo;
    end
    enviar_linea;

    // Cambiar por separado cada byte de W1081 detecta si el CRC omite alguno.
    cargar_barras(8'h80, 8'h00);
    enviar_linea;
    abortar_con_reset;
    cargar_barras(8'h00, 8'h01);
    enviar_linea;

    $display("PASS: hs_packer (SoT externo, ráfagas consecutivas y reset en plena carga)");
    $finish;
  end

  initial #100000 $fatal(1, "FAIL: timeout de hs_packer");
endmodule
