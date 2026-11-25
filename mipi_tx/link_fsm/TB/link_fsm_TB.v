`timescale 1ns / 1ps

module link_fsm_TB #(
    parameter integer PROFILE = 0
);
  localparam integer T_LPX = (PROFILE == 0) ? 1 : 5;
  localparam integer T_PREP = (PROFILE == 0) ? 1 : 3;
  localparam integer T_ZERO = (PROFILE == 0) ? 1 : 7;
  localparam integer T_TRAIL = (PROFILE == 0) ? 1 : 4;
  localparam integer C_LINE = (PROFILE == 0) ? 1091 : 1166;
  localparam integer LP_DIV = (PROFILE == 0) ? 1 : 3;
  localparam integer LP_FIN = 150 * LP_DIV;
  localparam integer W_CRC = 1082;
  localparam [15:0] CRC_MODELO = 16'ha65d;  // Patrón de prueba, no CRC calculado.
  localparam [71:0] PAQUETE_LP = 72'hca_d6_00_b0_00_00_02_29_87;
  localparam integer LP11_CICLOS = C_LINE - T_LPX - T_PREP - T_ZERO - 1084 - 1 - T_TRAIL;

  localparam [1:0] REPOSO = 2'b00, LPDT = 2'b01, FORZADO = 2'b10, HS = 2'b11;
  // {CLK_REQ, HS_REQ, SOT_EN, PK_START, LP_START, INIT_READY, INIT_DONE_TX}.
  localparam [6:0] C_QUIETO = 7'b0000000, C_LISTO = 7'b0000010, C_LP_START = 7'b0000100,
                   C_LP_ACK = 7'b0000001, C_CLK = 7'b1000000, C_HS = 7'b1100000,
                   C_SOT = 7'b1110000, C_PK_START = 7'b1101000;

  reg CLK_BYTE = 0;
  always #10 CLK_BYTE = !CLK_BYTE;
  integer ciclo = 0;
  always @(negedge CLK_BYTE) ciclo <= ciclo + 1;

  reg RST_BYTE = 1;
  reg INIT_REQ = 0, VID_REQ = 0, VID_LINE_RDY = 0;
  reg READY = 0, LOCK = 1;
  reg LP_DONE;
  wire INIT_READY, INIT_DONE_TX, LP_START, PK_START, HS_REQ, CLK_REQ, SOT_EN;
  wire [1:0] SEL_OUT, LP_FORCE;

  reg lp_activo, INIT_NEXT;
  reg [1:0] LP_D0;
  integer lp_slot, direccion, fines_leidos;

  integer indice;
  wire PK_DONE = (indice == W_CRC + 1);
  wire [15:0] WORD = palabra(indice);
  reg [1:0] lp_if_d0, lp_if_d1, lp_if_clk;
  reg [7:0] HS_BYTE0, HS_BYTE1;

  reg hs_previo, phy_toma, phy_trail;
  integer espera_zero, trail_restante;
  reg [15:0] phy_palabra;

  link_fsm #(
      .T_LPX(T_LPX), .T_PREP(T_PREP), .T_ZERO(T_ZERO), .T_TRAIL(T_TRAIL), .C_LINE(C_LINE)
  ) dut (
      .CLK_BYTE(CLK_BYTE), .RST_BYTE(RST_BYTE),
      .INIT_REQ(INIT_REQ), .VID_REQ(VID_REQ), .VID_LINE_RDY(VID_LINE_RDY),
      .READY(READY), .LOCK(LOCK), .LP_DONE(LP_DONE), .PK_DONE(PK_DONE),
      .INIT_READY(INIT_READY), .INIT_DONE_TX(INIT_DONE_TX), .LP_START(LP_START), .PK_START(PK_START),
      .HS_REQ(HS_REQ), .CLK_REQ(CLK_REQ), .SEL_OUT(SEL_OUT), .LP_FORCE(LP_FORCE), .SOT_EN(SOT_EN)
  );

  function [1:0] simbolo_lp(input integer slot);
    integer fase;
    begin
      fase = slot / LP_DIV;
      case (fase)
        0, 148: simbolo_lp = 2'b10;
        2: simbolo_lp = 2'b01;
        1, 3: simbolo_lp = 2'b00;
        default: begin
          if (fase >= 149) simbolo_lp = 2'b11;
          else if (fase[0]) simbolo_lp = 2'b00;
          else simbolo_lp = PAQUETE_LP[(fase-4)/2] ? 2'b10 : 2'b01;
        end
      endcase
    end
  endfunction

  function [15:0] palabra(input integer i);
    case (i)
      0: palabra = 16'h703e;
      1: palabra = 16'h1308;
      W_CRC: palabra = CRC_MODELO;
      default: palabra = (i < W_CRC) ? 16'h175c + 16'h01b3 * i[15:0] : 16'h0000;
    endcase
  endfunction

  // LP_TX inicia en el ↑ posterior a LP_START. Reproduce el guion del
  // primer paquete en ↓; INIT_NEXT solo avanza al secuenciador modelado.
  always @(posedge CLK_BYTE) begin
    if (RST_BYTE) begin
      lp_activo <= 0;
      direccion <= 0;
      fines_leidos <= 0;
    end else begin
      if (LP_START) begin
        if (lp_activo || direccion != 0) $fatal(1, "LP_START sin primer BYTE disponible");
        lp_activo <= 1;
      end else if (LP_DONE) lp_activo <= 0;
      if (INIT_NEXT) begin
        if (direccion >= 8) $fatal(1, "INIT_NEXT consumió la entrada WAIT");
        direccion <= direccion + 1;
      end
      if (INIT_DONE_TX) fines_leidos <= fines_leidos + 1;
    end
  end

  always @(negedge CLK_BYTE) begin
    if (RST_BYTE || !lp_activo) begin
      lp_slot <= 0;
      LP_D0 <= 2'b11;
      INIT_NEXT <= 0;
      LP_DONE <= 0;
    end else begin
      lp_slot <= lp_slot + 1;
      LP_D0 <= simbolo_lp(lp_slot);
      INIT_NEXT <= (lp_slot >= 20*LP_DIV && lp_slot < 148*LP_DIV &&
                    (lp_slot - 20*LP_DIV) % (16*LP_DIV) == 0);
      LP_DONE <= (lp_slot == LP_FIN);
    end
  end

  // HS_PACKER presenta W0 aun en reposo. PHY_IF toma WORD / LP_D0
  // anteriores al ↓, no los que se publican después de ese flanco.
  always @(negedge CLK_BYTE) begin
    if (RST_BYTE) indice <= 0;
    else begin
      if (PK_START && indice != 0) $fatal(1, "PK_START repetido durante el paquete");
      if (PK_DONE) indice <= 0;
      else if (PK_START || indice != 0) indice <= indice + 1;
    end

    lp_if_d0 <= 2'b11;
    lp_if_d1 <= 2'b11;
    lp_if_clk <= 2'b11;
    {HS_BYTE1, HS_BYTE0} <= 16'h0000;
    if (!RST_BYTE) begin
      case (SEL_OUT)
        LPDT: lp_if_d0 <= LP_D0;
        FORZADO: {lp_if_d1, lp_if_d0} <= {LP_FORCE, LP_FORCE};
        HS: begin
          {lp_if_d1, lp_if_d0} <= 4'b0000;
          {HS_BYTE1, HS_BYTE0} <= SOT_EN ? 16'hb8b8 : WORD;
        end
        default: begin end
      endcase
    end
  end

  // Consumidor de palabras para probar la propuesta de cierre. No ve
  // SEL_OUT ni PK_DONE. Tras la caída de HS_REQ toma el último registro
  // por un ciclo completo; los siguientes ciclos son trail, no bytes.
  always @(negedge CLK_BYTE) begin
    phy_toma <= 0;
    phy_trail <= 0;
    if (RST_BYTE) begin
      hs_previo <= 0;
      espera_zero <= 0;
      trail_restante <= 0;
      phy_palabra <= 16'h0000;
    end else begin
      hs_previo <= HS_REQ;
      if (HS_REQ || hs_previo) begin
        if (CLK_REQ !== 1'b1 || trail_restante != 0)
          $fatal(1, "Reloj no pedido o ráfaga durante trail");
        if (!hs_previo) espera_zero <= T_ZERO;
        else if (espera_zero != 0) begin
          if (!HS_REQ) $fatal(1, "HS_REQ cayó antes de SoT");
          espera_zero <= espera_zero - 1;
        end else begin
          phy_toma <= 1;
          phy_palabra <= {HS_BYTE1, HS_BYTE0};
          if (!HS_REQ) trail_restante <= T_TRAIL;
        end
      end else if (trail_restante != 0) begin
        if (CLK_REQ !== 1'b1) $fatal(1, "CLK_REQ cayó antes de terminar trail");
        phy_trail <= 1;
        trail_restante <= trail_restante - 1;
      end
    end
  end

  task automatic comprobar_control(input string paso, input [1:0] sel, pn, input [6:0] control);
    reg [6:0] observado;
    begin
      observado = {CLK_REQ, HS_REQ, SOT_EN, PK_START, LP_START, INIT_READY, INIT_DONE_TX};
      if ({SEL_OUT, LP_FORCE, observado} !== {sel, pn, control})
        $fatal(1, "ciclo %0d %s: SEL_OUT/LP_FORCE/control=%b/%b/%b; esperado %b/%b/%b",
               ciclo, paso, SEL_OUT, LP_FORCE, observado, sel, pn, control);
    end
  endtask

  task automatic comprobar_phy(input string paso, input [1:0] d0, d1, input [15:0] bytes);
    if ({lp_if_d0, lp_if_d1, lp_if_clk, HS_BYTE1, HS_BYTE0} !== {d0, d1, 2'b11, bytes})
      $fatal(1, "ciclo %0d %s: PHY_IF D0/D1/CLK=%b/%b/%b HS=%04h; esperado %b/%b/11 %04h",
             ciclo, paso, lp_if_d0, lp_if_d1, lp_if_clk, {HS_BYTE1, HS_BYTE0}, d0, d1, bytes);
  endtask

  task automatic comprobar_consumo(input bit toma, trail, input [15:0] bytes);
    if ({phy_toma, phy_trail} !== {toma, trail} || (toma && phy_palabra !== bytes))
      $fatal(1, "ciclo %0d PHY modelo: toma/trail/bytes=%b/%b/%04h; esperado %b/%b/%04h",
             ciclo, phy_toma, phy_trail, phy_palabra, toma, trail, bytes);
  endtask

  task automatic esperar_lp11(input integer n, input [6:0] control);
    for (integer i = 0; i < n; i = i + 1) begin
      @(negedge CLK_BYTE); #1;
      comprobar_control("reposo", REPOSO, 2'b11, control);
      comprobar_phy("LP11", 2'b11, 2'b11, 16'h0000);
      comprobar_consumo(0, 0, 16'h0000);
      if (indice !== 0 || LP_DONE !== 1'b0) $fatal(1, "No se completó el retorno a reposo");
    end
  endtask

  task automatic iniciar_lp;
    begin
      @(posedge CLK_BYTE);
      comprobar_control("antes de aceptar INIT_REQ", REPOSO, 2'b11, C_LISTO);
      #1;
      comprobar_control("↑−2 presenta LP_START", LPDT, 2'b11, C_LP_START);
      if (lp_activo !== 1'b0) $fatal(1, "LP_TX tomó LP_START en el ↑ de presentación");
      INIT_REQ = 0;
      @(posedge CLK_BYTE);
      comprobar_control("↑−1 LP_TX lee LP_START", LPDT, 2'b11, C_LP_START);
      #1;
      comprobar_control("LP_START de un ciclo", LPDT, 2'b11, C_QUIETO);
      if (lp_activo !== 1'b1) $fatal(1, "LP_TX no tomó LP_START en el ↑ siguiente");
    end
  endtask

  task automatic enviar_lp;
    reg [1:0] anterior;
    begin
      iniciar_lp;
      anterior = 2'b11;
      for (integer i = 0; i <= LP_FIN; i = i + 1) begin
        @(negedge CLK_BYTE); #1;
        comprobar_control("LPDT hasta leer LP_DONE", LPDT, 2'b11, C_QUIETO);
        comprobar_phy("LP_D0 capturado un ↓ después", anterior, 2'b11, 16'h0000);
        anterior = LP_D0;
        if (LP_DONE !== (i == LP_FIN)) $fatal(1, "LP_DONE fuera del flanco de cierre");
      end
      @(posedge CLK_BYTE);
      comprobar_control("↑ lee LP_DONE", LPDT, 2'b11, C_QUIETO);
      comprobar_phy("LP11 antes de soltar LPDT", 2'b11, 2'b11, 16'h0000);
      #1;
      comprobar_control("fin de un paquete", REPOSO, 2'b11, C_LP_ACK);
      if (direccion !== 8 || fines_leidos !== 0)
        $fatal(1, "INIT_NEXT no llegó al WAIT o se leyó el fin antes de presentarlo");
      esperar_lp11(1, C_LP_ACK);
      @(posedge CLK_BYTE); #1;
      comprobar_control("INIT_DONE_TX leído una vez", REPOSO, 2'b11, C_LISTO);
      if (fines_leidos !== 1) $fatal(1, "INIT_DONE_TX no se leyó en el ↑ posterior");
    end
  endtask

  task automatic fase_forzada(input string nombre, input integer n, input [1:0] pn, input [6:0] control);
    for (integer i = 0; i < n; i = i + 1) begin
      @(negedge CLK_BYTE); #1;
      comprobar_control(nombre, FORZADO, pn, control);
      comprobar_phy(nombre, pn, pn, 16'h0000);
      comprobar_consumo(0, 0, 16'h0000);
    end
  endtask

  task automatic iniciar_hs(output integer primero);
    begin
      @(posedge CLK_BYTE);
      comprobar_control("↑ de admisión HS", REPOSO, 2'b11, C_LISTO);
      #1;
      comprobar_control("primer LP01 presentado en ↑", FORZADO, 2'b01, C_CLK);
      primero = ciclo + 1;
      fase_forzada("T_LPX", T_LPX, 2'b01, C_CLK);
      fase_forzada("T_PREP", T_PREP, 2'b00, C_CLK);
      fase_forzada("T_ZERO", T_ZERO, 2'b00, C_HS);
      @(negedge CLK_BYTE); #1;
      comprobar_control("↓−1 SoT", HS, 2'b11, C_SOT);
      comprobar_phy("↓−1 B8 / B8", 2'b00, 2'b00, 16'hb8b8);
      comprobar_consumo(0, 0, 16'h0000);
      if (indice !== 0 || WORD !== 16'h703e) $fatal(1, "El packer no conservó W0 durante SoT");
      @(posedge CLK_BYTE);
      comprobar_control("↑−1 lee el estado anterior", HS, 2'b11, C_SOT);
      #1;
      comprobar_control("↑−1 retira SoT y presenta PK_START", HS, 2'b11, C_PK_START);
      comprobar_phy("SoT registrado hasta ↓0", 2'b00, 2'b00, 16'hb8b8);
      @(negedge CLK_BYTE); #1;
      comprobar_control("↓0 PK_START aceptado", HS, 2'b11, C_PK_START);
      comprobar_phy("↓0 W0: D0=3E / D1=70", 2'b00, 2'b00, 16'h703e);
      comprobar_consumo(1, 0, 16'hb8b8);
      if (indice !== 1 || WORD !== 16'h1308) $fatal(1, "El packer no avanzó después de W0");
    end
  endtask

  task automatic comprobar_palabra(input integer i);
    begin
      @(negedge CLK_BYTE); #1;
      comprobar_control($sformatf("↓%0d DATA", i), HS, 2'b11, C_HS);
      comprobar_phy("WORD consecutiva", 2'b00, 2'b00, palabra(i));
      comprobar_consumo(1, 0, palabra(i-1));
      if (PK_DONE !== (i == W_CRC)) $fatal(1, "PK_DONE fuera de ↓%0d", W_CRC);
    end
  endtask

  task automatic enviar_linea(input bit retirar_peticion, output integer primero);
    begin
      iniciar_hs(primero);
      if (retirar_peticion) begin
        VID_REQ = 0;
        VID_LINE_RDY = 0;
        READY = 0;  // No es VALID: ya se reservó la línea.
      end
      for (integer i = 1; i <= W_CRC; i = i + 1) comprobar_palabra(i);

      @(posedge CLK_BYTE);
      comprobar_control("↑1082 antes de leer PK_DONE", HS, 2'b11, C_HS);
      if (PK_DONE !== 1'b1) $fatal(1, "No se presentó PK_DONE a tiempo para ↑1082");
      #1;
      comprobar_control("↑1082 EoT: retira HS_REQ sin retirar CLK_REQ", FORZADO, 2'b00, C_CLK);
      comprobar_phy("CRC registrado hasta ↓1083", 2'b00, 2'b00, CRC_MODELO);
      @(negedge CLK_BYTE); #1;
      comprobar_control("↓1083 drena CRC", FORZADO, 2'b00, C_CLK);
      comprobar_phy("↓1083 sin otro dato desde PHY_IF", 2'b00, 2'b00, 16'h0000);
      comprobar_consumo(1, 0, CRC_MODELO);
      if (PK_DONE !== 1'b0 || WORD !== 16'h703e)
        $fatal(1, "No volvió al reposo el modelo HS_PACKER tras PK_DONE");
      @(posedge CLK_BYTE); #1;
      comprobar_control("CRC dispone del ciclo completo", FORZADO, 2'b00, C_CLK);
      comprobar_consumo(1, 0, CRC_MODELO);

      for (integer i = 0; i < T_TRAIL; i = i + 1) begin
        @(negedge CLK_BYTE); #1;
        comprobar_control("T_TRAIL", FORZADO, 2'b00, C_CLK);
        comprobar_phy("PHY_IF entrega 00/00 sin dato durante trail", 2'b00, 2'b00, 16'h0000);
        comprobar_consumo(0, 1, 16'h0000);
      end

      READY = 1;
      esperar_lp11(LP11_CICLOS - 1, C_QUIETO);  // LP11 temporizado.
      esperar_lp11(1, C_LISTO);                  // Primer ciclo en LINE_WAIT.
    end
  endtask

  // Se llama entre ↓ y ↑: el control se enmascara de inmediato, pero los
  // registros deben conservarse hasta su propio flanco síncrono.
  task automatic resetear;
    reg [3:0] estado_previo;
    integer cuenta_previa;
    begin
      estado_previo = dut.STATE;
      cuenta_previa = dut.timer.CNT;
      RST_BYTE = 1;
      INIT_REQ = 0;
      VID_REQ = 0;
      VID_LINE_RDY = 0;
      #1;
      comprobar_control("reset enmascara arranques y fin", REPOSO, 2'b11, C_QUIETO);
      if (dut.STATE !== estado_previo || dut.timer.CNT !== cuenta_previa)
        $fatal(1, "Cambió un registro antes de su flanco de reset");
      @(posedge CLK_BYTE); #1;
      if (dut.STATE !== dut.LINE_WAIT || dut.ENTER_T !== 1'b0 || dut.timer.CNT !== cuenta_previa)
        $fatal(1, "Reset en ↑ debe afectar el estado, no el contador");
      @(negedge CLK_BYTE); #1;
      if (dut.timer.CNT !== 0 || direccion !== 0 || fines_leidos !== 0)
        $fatal(1, "Contador o secuenciador no reiniciado");
      comprobar_phy("reset de PHY_IF en ↓", 2'b11, 2'b11, 16'h0000);
      comprobar_consumo(0, 0, 16'h0000);
      RST_BYTE = 0;
    end
  endtask

  integer ciclo_a, ciclo_b;

  initial begin
    if ($test$plusargs("waves")) begin
      $dumpfile("link_fsm_TB.fst");
      $dumpvars(1, link_fsm_TB, dut, dut.timer);
    end
    esperar_lp11(1, C_QUIETO);
    RST_BYTE = 0;
    INIT_REQ = 1;
    VID_REQ = 1;
    VID_LINE_RDY = 1;
    esperar_lp11(3, C_QUIETO);  // LOCK sin READY.
    READY = 1;
    LOCK = 0;
    esperar_lp11(3, C_QUIETO);  // READY sin LOCK.
    LOCK = 1;
    enviar_lp;  // Con VID_REQ pendiente: LP tiene prioridad.
    $display("PASS p%0d: admisión PHY, prioridad LP, captura retardada y fin por paquete", PROFILE);

    VID_LINE_RDY = 0;
    esperar_lp11(5, C_LISTO);
    VID_REQ = 0;
    VID_LINE_RDY = 1;
    esperar_lp11(3, C_LISTO);  // No se guardó la petición con la línea no lista.
    VID_REQ = 1;
    enviar_linea(0, ciclo_a);
    enviar_linea(1, ciclo_b);
    if (ciclo_b - ciclo_a != C_LINE)
      $fatal(1, "Período inicio a inicio: %0d, esperado %0d", ciclo_b - ciclo_a, C_LINE);
    $display("PASS p%0d: falta de línea, SoT→W0 sin hueco, W1…CRC, drenaje/trail, período %0d ciclos",
             PROFILE, C_LINE);

    VID_REQ = 1;
    VID_LINE_RDY = 1;
    iniciar_hs(ciclo_a);
    comprobar_palabra(1);
    resetear;  // Aborta en DATA, con palabras todavía en la tubería.
    esperar_lp11(3, C_LISTO);

    INIT_REQ = 1;
    iniciar_lp;
    repeat (LP_FIN + 1) @(negedge CLK_BYTE);
    #1;
    if (LP_DONE !== 1'b1 || INIT_DONE_TX !== 1'b0)
      $fatal(1, "Se esperaba LP_DONE aún pendiente de leer");
    resetear;  // La FSM no debe acusar fin aun con LP_DONE pendiente.
    esperar_lp11(3, C_LISTO);
    INIT_REQ = 1;
    enviar_lp;

    VID_REQ = 1;
    VID_LINE_RDY = 1;
    @(posedge CLK_BYTE);
    @(negedge CLK_BYTE); #1;
    comprobar_control("LP01 antes de resetear TIMER", FORZADO, 2'b01, C_CLK);
    if (dut.timer.CNT !== T_LPX - 1) $fatal(1, "Carga inicial de T_LPX incorrecta");
    resetear;
    esperar_lp11(3, C_LISTO);
    VID_REQ = 1;
    VID_LINE_RDY = 1;
    enviar_linea(1, ciclo_a);
    $display("PASS p%0d: reset en DATA, LP_DONE pendiente y TIMER activo; reinicio limpio", PROFILE);
    $finish;
  end

  initial #200000 $fatal(1, "Timeout de link_fsm");
endmodule
