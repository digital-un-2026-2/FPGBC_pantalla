`timescale 1ns / 1ps

module video_source_TB #(
    parameter integer PROFILE = 0
);
  localparam integer T_CLK = 20;
  localparam integer PALABRAS = 1080;
  localparam integer W_CRC = 2 + PALABRAS;
  // Perfiles del banco de LINK_FSM. W0 llega tras LPX/PREP/ZERO y SoT.
  // El reloj del banco y estos límites no son ajustes físicos.
  localparam integer W0_OFFSET = (PROFILE == 0) ? 4 : 16;
  localparam integer C_LINE = (PROFILE == 0) ? 1091 : 1166;

  reg CLK_BYTE = 0;
  always #(T_CLK/2) CLK_BYTE = !CLK_BYTE;

  reg RST_BYTE = 1, FIN_ROM = 0, INIT_DONE;
  reg READY = 1, LOCK = 1, INIT_REQ = 0;
  reg RD_ESPURIO = 0;
  wire VID_REQ, VID_LINE_RDY;
  wire [15:0] VID_WORD;

  integer ciclo = 0, siguiente_admision, inicia_w0, ultima_admision, admisiones;
  reg PK_START;
  integer pack_word;
  wire RD_PACKER = (pack_word >= 2) && (pack_word < W_CRC);
  wire VID_RD = RD_PACKER || RD_ESPURIO;

  integer lecturas, lineas, primera_admision;
  time ultima_lectura;

  video_source dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE), .INIT_DONE(INIT_DONE), .VID_RD(VID_RD),
      .VID_REQ(VID_REQ), .VID_LINE_RDY(VID_LINE_RDY), .VID_WORD(VID_WORD)
  );

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("video_source_TB.fst");
      $dumpvars(1, video_source_TB, dut);
    end
  end

  // INIT_SEQUENCER: END se publica en ↑ y habilita hasta reset.
  always @(posedge CLK_BYTE) begin
    if (RST_BYTE) INIT_DONE <= 0;
    else if (FIN_ROM) INIT_DONE <= 1;
  end

  // LINK_FSM: arbitra en ↑, agenda PK_START y no admite otra línea
  // antes del próximo turno. No modela el camino LP ni el PHY.
  always @(posedge CLK_BYTE) begin
    ciclo <= ciclo + 1;
    if (RST_BYTE) begin
      siguiente_admision <= 0;
      inicia_w0 <= -1;
      ultima_admision <= -1;
      admisiones <= 0;
      PK_START <= 0;
    end else begin
      PK_START <= (ciclo == inicia_w0);
      if (ciclo >= siguiente_admision && READY && LOCK && !INIT_REQ &&
          VID_REQ && VID_LINE_RDY) begin
        ultima_admision <= ciclo;
        admisiones <= admisiones + 1;
        inicia_w0 <= ciclo + W0_OFFSET;
        siguiente_admision <= ciclo + C_LINE;
      end
    end
  end

  // HS_PACKER: ↓0 inicia W0; al consumir W1 se activa VID_RD para
  // el ↓ siguiente. En CRC y después no hay lectura de la fuente.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) pack_word <= 0;
    else if (pack_word == W_CRC + 1) pack_word <= 0;
    else if (PK_START || pack_word != 0) pack_word <= pack_word + 1;
  end

  // Referencia independiente por byte del raster RGB, no por tramos de
  // palabras ni por el RGB_PHASE del DUT.
  function automatic [7:0] byte_rgb(input integer n);
    reg [23:0] rgb;
    begin
      case ((n / 3) / 90)
        0: rgb = 24'hf0e0d0;
        1: rgb = 24'hf0e030;
        2: rgb = 24'h10e0d0;
        3: rgb = 24'h10e030;
        4: rgb = 24'hf020d0;
        5: rgb = 24'hf02030;
        6: rgb = 24'h1020d0;
        7: rgb = 24'h102030;
        default: rgb = 24'hxxxxxx;
      endcase
      case (n % 3)
        0: byte_rgb = rgb[23:16];
        1: byte_rgb = rgb[15:8];
        default: byte_rgb = rgb[7:0];
      endcase
    end
  endfunction

  task automatic comprobar_fuente(input string momento, input integer indice, input bit oferta);
    reg [7:0] d0, d1;
    reg [1:0] fase;
    begin
      d0 = byte_rgb(2 * indice);
      d1 = byte_rgb(2 * indice + 1);
      fase = indice % 3;
      if ({VID_REQ, VID_LINE_RDY} !== {oferta, oferta})
        $fatal(1, "ciclo %0d %s: VID_REQ/VID_LINE_RDY=%b/%b, esperado %b/%b",
               ciclo, momento, VID_REQ, VID_LINE_RDY, oferta, oferta);
      // Palabras repetidas dentro de una barra no deben ocultar un salto de índice.
      if (dut.ADDR !== indice[10:0] || dut.RGB_PHASE !== fase)
        $fatal(1, "ciclo %0d %s: ADDR/fase=%0d/%0d, esperado %0d/%0d",
               ciclo, momento, dut.ADDR, dut.RGB_PHASE, indice, fase);
      if (VID_WORD[7:0] !== d0 || VID_WORD[15:8] !== d1)
        $fatal(1, "ciclo %0d %s: P%0d D0/D1=%02h/%02h, esperado %02h/%02h",
               ciclo, momento, indice, VID_WORD[7:0], VID_WORD[15:8], d0, d1);
    end
  endtask

  task automatic comprobar_posicion(input string momento);
    integer indice;
    begin
      indice = (lecturas == PALABRAS) ? 0 : lecturas;
      comprobar_fuente(momento, indice, INIT_DONE && (indice == 0));
    end
  endtask

  always @(posedge CLK_BYTE) begin
    #1;
    if (!RST_BYTE) comprobar_posicion("después de ↑");
  end

  // Se toma el valor anterior a ↓ igual que el packer y se comprueba aparte
  // el que publica la fuente después de que actualicen los registros.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) begin
      lecturas = 0;
      lineas = 0;
      ultima_lectura = 0;
      #1;
      comprobar_fuente("reset después de ↓", 0, 0);
    end else begin
      comprobar_posicion("antes de ↓");
      if (RD_PACKER) begin
        if (!INIT_DONE || VID_RD !== 1'b1 || lecturas != pack_word - 2 ||
            lecturas >= PALABRAS || (lecturas != 0 && $time - ultima_lectura != T_CLK))
          $fatal(1, "ciclo %0d: lectura inesperada/separada en W%0d (%0d previas)",
                 ciclo, pack_word, lecturas);
        lecturas = lecturas + 1;
        ultima_lectura = $time;
      end else if (pack_word == W_CRC) begin
        if (VID_RD !== 1'b0 || lecturas != PALABRAS)
          $fatal(1, "ciclo %0d: llegó el CRC con %0d lecturas y VID_RD=%b", ciclo, lecturas, VID_RD);
        lineas = lineas + 1;
        lecturas = 0;
      end
      #1;
      comprobar_posicion("después de ↓");
    end
  end

  task automatic esperar_bloqueado(input integer n, esperadas, input string causa);
    repeat (n) begin
      @(negedge CLK_BYTE); #2;
      if (admisiones !== esperadas || RD_PACKER !== 1'b0)
        $fatal(1, "ciclo %0d %s: admisiones=%0d, se esperaban %0d sin lecturas",
               ciclo, causa, admisiones, esperadas);
    end
  endtask

  task automatic publicar_end;
    begin
      FIN_ROM = 1;
      @(posedge CLK_BYTE); #2;
      FIN_ROM = 0;
      if (INIT_DONE !== 1'b1 || admisiones !== 0)
        $fatal(1, "ciclo %0d: END se perdió o se admitió en el ↑ que lo publica", ciclo);
      comprobar_fuente("↑ publica INIT_DONE", 0, 1);
    end
  endtask

  task automatic admitir_en_proximo_flanco(input integer n);
    begin
      @(posedge CLK_BYTE); #2;
      if (admisiones !== n || ultima_admision !== ciclo - 1)
        $fatal(1, "ciclo %0d: se perdió o se adelantó la admisión %0d", ciclo - 1, n);
    end
  endtask

  // Invocado después de ↓; mantiene reset en el ↑ y ↓ siguientes.
  task automatic reiniciar(input integer indice_previo);
    begin
      RST_BYTE = 1;
      #1;
      comprobar_fuente("reset antes del ↑", indice_previo, 0);
      @(posedge CLK_BYTE); #1;
      comprobar_fuente("reset después del ↑", indice_previo, 0);
      @(negedge CLK_BYTE); #2;
      comprobar_fuente("reset después del ↓", 0, 0);
      if (INIT_DONE !== 1'b0 || admisiones !== 0 || lineas !== 0 || RD_PACKER !== 1'b0)
        $fatal(1, "El reset común no abortó la transacción modelada");
      RST_BYTE = 0;
    end
  endtask

  initial begin
    repeat (2) @(negedge CLK_BYTE);
    #2;
    RST_BYTE = 0;
    esperar_bloqueado(4, 0, "antes de INIT_DONE con enlace listo");
    RD_ESPURIO = 1;
    esperar_bloqueado(4, 0, "VID_RD fuera de inicialización no avanza");
    RD_ESPURIO = 0;

    READY = 0;
    publicar_end;
    esperar_bloqueado(C_LINE + 7, 0, "READY=0: la oferta no vence");
    LOCK = 0;
    READY = 1;
    esperar_bloqueado(6, 0, "LOCK=0");
    LOCK = 1;
    INIT_REQ = 1;  // Contención sintética para verificar prioridad de LP.
    esperar_bloqueado(9, 0, "INIT_REQ prioritario");
    INIT_REQ = 0;
    $display("PASS p%0d: bloqueo por INIT_DONE y oferta retenida con READY/LOCK/prioridad LP", PROFILE);

    admitir_en_proximo_flanco(1);
    primera_admision = ultima_admision;
    repeat (C_LINE - 1) @(posedge CLK_BYTE);
    #2;
    if (admisiones !== 1 || lineas !== 1)
      $fatal(1, "Duplicación de admisión o primera línea incompleta");
    admitir_en_proximo_flanco(2);
    if (ultima_admision - primera_admision != C_LINE)
      $fatal(1, "Las dos admisiones no están separadas por C_LINE");
    wait (lineas == 2);
    #2;
    READY = 0;
    esperar_bloqueado(C_LINE + 2, 2, "oferta siguiente sin una tercera admisión");
    $display("PASS p%0d: dos líneas sin duplicados, 1080 palabras RGB888 cada una, C_LINE=%0d",
             PROFILE, C_LINE);

    reiniciar(0);  // Aborta una solicitud todavía pendiente.
    READY = 1;
    esperar_bloqueado(5, 0, "reset de oferta requiere nuevo END");
    publicar_end;
    admitir_en_proximo_flanco(1);
    wait (lecturas == 17);
    #2;
    reiniciar(17);  // Aborta el payload con VID_RD alto y ADDR no nula.
    esperar_bloqueado(5, 0, "no se reanuda la línea parcial");
    publicar_end;
    admitir_en_proximo_flanco(1);
    wait (lineas == 1);
    #2;
    $display("PASS p%0d: reset en espera y en carga; vuelve a P0 tras INIT_DONE", PROFILE);
    $finish;
  end

  initial begin
    #(12 * C_LINE * T_CLK);
    $fatal(1, "Tiempo agotado en video_source_TB");
  end
endmodule
