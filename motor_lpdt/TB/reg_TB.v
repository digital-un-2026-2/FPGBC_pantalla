`timescale 1ns / 1ps

module reg_TB;
  localparam real PERIOD = 25.0;  // 40 MHz

  reg clk = 0;
  // Habilitaciones independientes: [0] byte, [1] WC, [2] longitud, [3] flag.
  reg [3:0] ld = 0;
  reg [7:0] byte_in = 0;
  reg [15:0] wc_in = 0;
  reg [2:0] length_in = 0;
  reg flag_in = 0;
  wire [7:0] byte_out;
  wire [15:0] wc_out;
  wire [2:0] length_out;
  wire flag_out;
  reg [7:0] expected_byte = 8'hxx;
  reg [15:0] expected_wc = 16'hxxxx;
  reg [2:0] expected_length = 3'bxxx;
  reg expected_flag = 1'bx;
  integer value;

  reg_0 byte_register (
      .clk(clk), .reg_in(byte_in), .ld(ld[0]), .reg_out(byte_out)
  );
  reg_0 #(.BITS(16)) wc_register (
      .clk(clk), .reg_in(wc_in), .ld(ld[1]), .reg_out(wc_out)
  );
  reg_0 #(.BITS(3)) length_register (
      .clk(clk), .reg_in(length_in), .ld(ld[2]), .reg_out(length_out)
  );
  reg_0 #(.BITS(1)) flag_register (
      .clk(clk), .reg_in(flag_in), .ld(ld[3]), .reg_out(flag_out)
  );

  always #(PERIOD / 2) clk = ~clk;

  task check;
    begin
      if ({flag_out, length_out, wc_out, byte_out} !==
          {expected_flag, expected_length, expected_wc, expected_byte})
        $fatal(1, "FAIL t=%0t: flag/longitud/WC/byte=%b/%b/%h/%h; esperado %b/%b/%h/%h",
               $time, flag_out, length_out, wc_out, byte_out,
               expected_flag, expected_length, expected_wc, expected_byte);
    end
  endtask

  // Estimulos en posedge; captura en negedge. #1 observa despues de las NBA.
  // El modelo conserva X hasta la primera carga de cada instancia, sin reset.
  task step;
    input [3:0] enables;
    input [7:0] next_byte;
    input [15:0] next_wc;
    input [2:0] next_length;
    input next_flag;
    begin
      @(posedge clk);
      ld <= enables;
      byte_in <= next_byte;
      wc_in <= next_wc;
      length_in <= next_length;
      flag_in <= next_flag;
      #1;
      check;  // Ni el posedge ni cambiar las entradas deben cargar el registro.
      @(negedge clk);
      if (enables[0]) expected_byte = next_byte;
      if (enables[1]) expected_wc = next_wc;
      if (enables[2]) expected_length = next_length;
      if (enables[3]) expected_flag = next_flag;
      #1;
      check;
    end
  endtask

  initial begin
    $dumpfile("reg_TB.vcd");
    $dumpvars(0, reg_TB);

    $display("CASO 1: sin reset, X inicial y retencion antes de cargar");
    #1;
    check;
    step(4'b0000, 8'hff, 16'hffff, 3'd7, 1'b1);
    step(4'b0000, 8'h00, 16'h0000, 3'd0, 1'b0);

    $display("CASO 2: cargas independientes y primera inicializacion");
    step(4'b0001, 8'h87, 16'h1234, 3'd7, 1'b1);
    step(4'b0010, 8'hff, 16'h1234, 3'd7, 1'b1);
    step(4'b0100, 8'h00, 16'hffff, 3'd4, 1'b1);
    step(4'b1000, 8'hff, 16'h0000, 3'd0, 1'b1);

    $display("CASO 3: byte LPDT/DSI, cargas consecutivas con ld sostenido");
    step(4'b0001, 8'h87, 16'h0000, 3'd0, 1'b0);
    step(4'b0001, 8'h05, 16'h0000, 3'd0, 1'b0);
    step(4'b0001, 8'h01, 16'h0000, 3'd0, 1'b0);
    step(4'b0001, 8'h00, 16'h0000, 3'd0, 1'b0);
    step(4'b0001, 8'h10, 16'h0000, 3'd0, 1'b0);

    $display("CASO 4: retencion mientras cambian todas las entradas");
    step(4'b0000, 8'haa, 16'haaaa, 3'd5, 1'b0);
    step(4'b0000, 8'h55, 16'h5555, 3'd2, 1'b1);
    step(4'b0000, 8'h00, 16'h0000, 3'd0, 1'b0);

    $display("CASO 5: carga simultanea, ceros, maximos y patrones alternos");
    step(4'b1111, 8'h00, 16'h0000, 3'd0, 1'b0);
    step(4'b1111, 8'hff, 16'hffff, 3'd7, 1'b1);
    step(4'b1111, 8'haa, 16'haaaa, 3'd5, 1'b0);
    step(4'b1111, 8'h55, 16'h5555, 3'd2, 1'b1);

    $display("CASO 6: todos los valores del byte, carga y retencion");
    for (value = 0; value < 256; value = value + 1) begin
      step(4'b0001, value[7:0], 16'h0000, 3'd0, 1'b0);
      step(4'b0000, ~value[7:0], 16'hffff, 3'd7, 1'b0);
    end

    $display("PASS: reg_TB");
    $finish;
  end

  initial begin
    #(PERIOD * 1000);
    $fatal(1, "FAIL: tiempo limite de simulacion excedido");
  end
endmodule
