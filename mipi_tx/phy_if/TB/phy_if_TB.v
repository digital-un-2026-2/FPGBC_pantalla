`timescale 1ns / 1ps

module phy_if_TB;
  localparam [1:0] REPOSO = 2'b00, LPDT = 2'b01, FORZADO = 2'b10, HS = 2'b11;
  localparam integer W_CRC = 1082;
  localparam [15:0] CRC_MODELO = 16'ha65d;  // Patrón, no un CRC calculado.

  reg CLK_BYTE = 0;
  always #10 CLK_BYTE = !CLK_BYTE;
  reg RST_BYTE = 1;
  reg [1:0] SEL_OUT = REPOSO;
  reg [1:0] LP_FORCE = 2'b11;
  reg SOT_EN = 0;

  reg [1:0] lp_siguiente = 2'b11;
  reg [1:0] LP_D0;
  reg PK_START = 0;
  integer indice_packer;
  wire PK_DONE = (indice_packer == W_CRC + 1);
  wire [15:0] WORD = palabra_modelo(indice_packer);

  wire [2:0] LP_P, LP_N;
  wire [7:0] HS_BYTE0, HS_BYTE1;
  time ultimo_negedge = 0;

  phy_if dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .SEL_OUT(SEL_OUT), .LP_FORCE(LP_FORCE), .SOT_EN(SOT_EN),
      .LP_D0(LP_D0), .WORD(WORD),
      .LP_P(LP_P), .LP_N(LP_N), .HS_BYTE0(HS_BYTE0), .HS_BYTE1(HS_BYTE1)
  );

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("phy_if_TB.fst");
      $dumpvars(1, phy_if_TB, dut);
    end
  end

  function [15:0] palabra_modelo(input integer indice);
    case (indice)
      0: palabra_modelo = 16'h703e;
      1: palabra_modelo = 16'h1308;
      W_CRC: palabra_modelo = CRC_MODELO;
      default: palabra_modelo = (indice < W_CRC) ?
          16'h175c + 16'h01b3 * indice[15:0] : 16'h0000;
    endcase
  endfunction

  // LP_TX publica el siguiente símbolo en ↓; HS_PACKER presenta W0 incluso
  // en reposo y avanza el índice en ↓. PK_START nunca se conecta al DUT.
  always @(negedge CLK_BYTE) begin
    ultimo_negedge = $time;
    if (RST_BYTE) begin
      LP_D0 <= 2'b11;
      indice_packer <= 0;
    end else begin
      LP_D0 <= lp_siguiente;
      if (PK_DONE) indice_packer <= 0;
      else if (PK_START || indice_packer != 0) indice_packer <= indice_packer + 1;
    end
  end

  always @(LP_P or LP_N or HS_BYTE0 or HS_BYTE1)
    if ($time != ultimo_negedge)
      $fatal(1, "FAIL: las salidas cambiaron fuera de negedge en %0t", $time);

  task comprobar(input string paso, input [2:0] p, n, input [7:0] d0, d1);
    if ({LP_P, LP_N, HS_BYTE0, HS_BYTE1} !== {p, n, d0, d1})
      $fatal(1, "FAIL: %s: LP P/N=%b/%b, HS D0/D1=%02h/%02h; esperado %b/%b y %02h/%02h",
             paso, LP_P, LP_N, HS_BYTE0, HS_BYTE1, p, n, d0, d1);
  endtask

  task comprobar_negedge(input string paso, input [2:0] p, n, input [7:0] d0, d1);
    begin
      @(negedge CLK_BYTE); #1;
      comprobar(paso, p, n, d0, d1);
    end
  endtask

  // Los estímulos de LINK_FSM se emiten en ↑. Se deja SOT_EN activo
  // durante LP para verificar que no afecte a ninguno de los dos caminos.
  task verificar_lpdt(input [1:0] actual, siguiente);
    begin
      @(posedge CLK_BYTE);
      SEL_OUT = LPDT;
      LP_FORCE = ~actual;
      SOT_EN = 1;
      lp_siguiente = siguiente;
      @(negedge CLK_BYTE);
      if (LP_D0 !== actual)
        $fatal(1, "FAIL: el modelo LP presentó %b en lugar de %b antes de ↓", LP_D0, actual);
      #1;
      comprobar($sformatf("LPDT %b: captura el símbolo anterior a ↓", actual),
                {2'b11, actual[1]}, {2'b11, actual[0]}, 8'h00, 8'h00);
    end
  endtask

  task forzar_lp(input [1:0] estado);
    begin
      @(posedge CLK_BYTE);
      SEL_OUT = FORZADO;
      LP_FORCE = estado;
      SOT_EN = 1;
      lp_siguiente = ~estado;
      comprobar_negedge($sformatf("LP forzado %b en D0 y D1", estado),
                        {1'b1, {2{estado[1]}}}, {1'b1, {2{estado[0]}}}, 8'h00, 8'h00);
    end
  endtask

  task iniciar_hs;
    begin
      @(posedge CLK_BYTE);
      SEL_OUT = HS;
      LP_FORCE = 2'b10;  // Ni LP_FORCE ni LP_D0 gobiernan LP durante HS.
      SOT_EN = 1;
      PK_START = 0;
      comprobar_negedge("SoT en ↓−1", 3'b100, 3'b100, 8'hb8, 8'hb8);
      if (WORD !== 16'h703e || indice_packer !== 0)
        $fatal(1, "FAIL: el packer debe mantener W0 durante SoT");

      // El banco observa lo registrado también en ↑, sin fijar la fase
      // de consumo del PHY físico.
      @(posedge CLK_BYTE);
      comprobar("SoT estable en ↑", 3'b100, 3'b100, 8'hb8, 8'hb8);
      SOT_EN = 0;
      PK_START = 1;
      @(negedge CLK_BYTE);
      if (WORD !== 16'h703e) $fatal(1, "FAIL: W0 no estaba presente al aceptar PK_START");
      #1;
      if (WORD !== 16'h1308) $fatal(1, "FAIL: WORD no avanzó a W1 tras ↓0");
      comprobar("W0 en el mismo ↓0 que acepta PK_START", 3'b100, 3'b100, 8'h3e, 8'h70);

      @(posedge CLK_BYTE);
      comprobar("W0 estable en ↑", 3'b100, 3'b100, 8'h3e, 8'h70);
      PK_START = 0;
      comprobar_negedge("W1 en ↓1", 3'b100, 3'b100, 8'h08, 8'h13);
    end
  endtask

  task enviar_linea;
    reg [15:0] esperado;
    integer i;
    begin
      iniciar_hs;
      for (i = 2; i < W_CRC; i = i + 1) begin
        esperado = palabra_modelo(i);
        comprobar_negedge($sformatf("W%0d, sin pausas", i),
                          3'b100, 3'b100, esperado[7:0], esperado[15:8]);
      end
      comprobar_negedge("CRC en ↓1082", 3'b100, 3'b100, CRC_MODELO[7:0], CRC_MODELO[15:8]);
      @(posedge CLK_BYTE);
      comprobar("CRC estable en el ↑ de PK_DONE", 3'b100, 3'b100, CRC_MODELO[7:0], CRC_MODELO[15:8]);
      if (PK_DONE !== 1'b1) $fatal(1, "FAIL: PK_DONE no visible tras W1082");
      SEL_OUT = FORZADO;  // Sale de WORD; no modela EoT físico.
      LP_FORCE = 2'b00;
      comprobar_negedge("↓1083 sin dato HS", 3'b100, 3'b100, 8'h00, 8'h00);
      if (WORD !== 16'h703e || PK_DONE !== 1'b0)
        $fatal(1, "FAIL: el modelo del packer no volvió al reposo");
      comprobar_negedge("W0 en reposo del packer no se vuelve a emitir", 3'b100, 3'b100, 8'h00, 8'h00);
    end
  endtask

  task abortar_con_reset;
    reg [15:0] w2;
    begin
      iniciar_hs;
      w2 = palabra_modelo(2);
      comprobar_negedge("W2 antes del reset", 3'b100, 3'b100, w2[7:0], w2[15:8]);
      @(posedge CLK_BYTE); #2;
      RST_BYTE = 1;
      #1;
      comprobar("reset aún no muestreado", 3'b100, 3'b100, w2[7:0], w2[15:8]);
      comprobar_negedge("reset domina los datos HS", 3'b111, 3'b111, 8'h00, 8'h00);
      @(posedge CLK_BYTE);
      SOT_EN = 1;
      comprobar_negedge("reset domina SoT", 3'b111, 3'b111, 8'h00, 8'h00);

      @(posedge CLK_BYTE);
      RST_BYTE = 0;
      SEL_OUT = REPOSO;
      comprobar_negedge("reposo tras reset", 3'b111, 3'b111, 8'h00, 8'h00);
    end
  endtask

  initial begin
    comprobar_negedge("reset inicial", 3'b111, 3'b111, 8'h00, 8'h00);
    @(posedge CLK_BYTE);
    RST_BYTE = 0;
    SOT_EN = 1;
    LP_FORCE = 2'b00;
    lp_siguiente = 2'b01;
    comprobar_negedge("reposo", 3'b111, 3'b111, 8'h00, 8'h00);
    comprobar_negedge("reposo ignora LP_D0 activo", 3'b111, 3'b111, 8'h00, 8'h00);
    @(posedge CLK_BYTE);
    lp_siguiente = 2'b11;
    comprobar_negedge("reposo antes de LPDT", 3'b111, 3'b111, 8'h00, 8'h00);
    verificar_lpdt(2'b11, 2'b10);
    verificar_lpdt(2'b10, 2'b00);
    verificar_lpdt(2'b00, 2'b01);
    verificar_lpdt(2'b01, 2'b00);
    verificar_lpdt(2'b00, 2'b11);
    verificar_lpdt(2'b11, 2'b11);
    forzar_lp(2'b10);
    forzar_lp(2'b11);
    forzar_lp(2'b01);
    forzar_lp(2'b00);
    $display("PASS: reposo, LPDT solo en D0 y los cuatro estados forzados en D0/D1");

    enviar_linea;
    $display("PASS: SoT -> W0 -> W1 y 1083 palabras consecutivas hasta el CRC");

    forzar_lp(2'b01);
    forzar_lp(2'b00);
    abortar_con_reset;
    forzar_lp(2'b01);
    forzar_lp(2'b00);
    enviar_linea;
    $display("PASS: reset síncrono en plena ráfaga y nueva línea completa");
    $finish;
  end

  initial #100000 $fatal(1, "FAIL: timeout de phy_if");
endmodule
