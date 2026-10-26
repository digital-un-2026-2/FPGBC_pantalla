`timescale 1ns / 1ps

module count_TB;
  localparam real PERIOD = 25.0;  // 40 MHz

  reg clk = 0;
  // Máscaras: [0] tiempo, [1] bit, [2] byte.
  reg [2:0] rst = 0;
  reg [2:0] inc = 0;
  wire [2:0] time_out;
  wire [2:0] bit_out;
  wire [1:0] byte_out;
  wire [2:0] z;
  integer ticks;
  integer bit_index;
  integer byte_index;
  integer interval_index;
  time interval_start;
  reg [7:0] previous_counts;
  reg [2:0] previous_z;

  // Cuenta periodos transcurridos desde el negedge que acepta reset.
  // Necesita representar 4: no bastan 2 bits.
  count #(.BITS(3)) time_counter (
      .clk(clk), .rst(rst[0]), .inc(inc[0]),
      .count_out(time_out)
  );
  comp #(.BITS(3)) time_comp (
      .A(time_out), .B(3'd4), .z(z[0])
  );

  // Índice del bit actual, no cantidad de bits ya transmitidos.
  count #(.BITS(3)) bit_counter (
      .clk(clk), .rst(rst[1]), .inc(inc[1]),
      .count_out(bit_out)
  );
  comp #(.BITS(3)) bit_comp (
      .A(bit_out), .B(3'd7), .z(z[1])
  );

  // Primer paquete DSI: 05 01 00 10. El selector 87 no ocupa un índice.
  count #(.BITS(2)) byte_counter (
      .clk(clk), .rst(rst[2]), .inc(inc[2]),
      .count_out(byte_out)
  );
  comp #(.BITS(2)) byte_comp (
      .A(byte_out), .B(2'd3), .z(z[2])
  );

  always #(PERIOD / 2) clk = ~clk;

  task check;
    input [2:0] expected_time;
    input [2:0] expected_bit;
    input [1:0] expected_byte;
    begin
      if ({byte_out, bit_out, time_out} !==
          {expected_byte, expected_bit, expected_time})
        $fatal(1, "FAIL t=%0t: tiempo=%0d bit=%0d byte=%0d; esperado %0d/%0d/%0d",
               $time, time_out, bit_out, byte_out,
               expected_time, expected_bit, expected_byte);
      if (z !== {expected_byte == 3, expected_bit == 7, expected_time == 4})
        $fatal(1, "FAIL t=%0t: comparadores z=%b", $time, z);
    end
  endtask

  // El test representa al control: solo actualiza rst/inc en posedge con <=.
  // #1 se usa únicamente para observar resultados después de las NBA.
  task step;
    input [2:0] reset_value;
    input [2:0] increment_value;
    input [2:0] expected_time;
    input [2:0] expected_bit;
    input [1:0] expected_byte;
    begin
      @(posedge clk);
      previous_counts = {byte_out, bit_out, time_out};
      previous_z = z;
      rst <= reset_value;
      inc <= increment_value;
      #1;
      if ({byte_out, bit_out, time_out} !== previous_counts || z !== previous_z)
        $fatal(1, "FAIL: un contador cambio en posedge");
      @(negedge clk);
      #1;
      check(expected_time, expected_bit, expected_byte);
    end
  endtask

  initial begin
    $dumpfile("count_TB.vcd");
    $dumpvars(0, count_TB);

    step(3'b111, 3'b111, 0, 0, 0);  // Reset tiene prioridad sobre inc.
    step(0, 0, 0, 0, 0);

    $display("CASO 1: temporizador, cuatro periodos = 100 ns");
    // Dos usos consecutivos: por ejemplo, Mark y Space. Son pruebas aisladas
    // del contador; no generan una forma de onda LPDT ni su continuidad.
    for (interval_index = 0; interval_index < 2; interval_index = interval_index + 1) begin
      step(3'b001, 0, 0, 0, 0);
      interval_start = $time;
      for (ticks = 1; ticks <= 4; ticks = ticks + 1)
        step(0, 3'b001, ticks, 0, 0);
      if ($time - interval_start != 100)
        $fatal(1, "FAIL: intervalo distinto de 100 ns");
      step(0, 0, 4, 0, 0);  // z no es un pulso: persiste al detenerse.
    end
    step(0, 3'b001, 5, 0, 0);  // El comparador no reinicia ni detiene el contador.
    step(3'b001, 0, 0, 0, 0);

    $display("CASO 2: indice de bit 0..7, habilitado una vez por bit");
    // Selector y cuatro bytes DSI: cinco recorridos del índice de bit.
    for (byte_index = 0; byte_index < 5; byte_index = byte_index + 1) begin
      step(3'b010, 0, 0, 0, 0);
      for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
        // Retención durante Mark/Space (sin generar aquí la señal LP).
        step(0, 0, 0, bit_index, 0);
        step(0, 0, 0, bit_index, 0);
        if (bit_index < 7)
          step(0, 3'b010, 0, bit_index + 1, 0);
      end
    end
    step(0, 3'b010, 0, 0, 0);  // Desbordamiento natural de tres bits.

    $display("CASO 3: indice de byte DSI 0..3, sin contar selector 87");
    step(3'b100, 0, 0, 0, 0);
    // El selector no hace avanzar el índice DSI.
    repeat (8) step(0, 0, 0, 0, 0);
    for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1) begin
      // Ocho eventos de bit antes de avanzar al siguiente byte DSI.
      repeat (8) step(0, 0, 0, 0, byte_index);
      if (byte_index < 3)
        step(0, 3'b100, 0, 0, byte_index + 1);
    end
    step(0, 0, 0, 0, 3);  // La FSM debe finalizar, no avanzar a otro byte.
    step(3'b100, 3'b100, 0, 0, 0);  // Preparar el siguiente paquete.

    $display("PASS: count_TB");
    $finish;
  end

  initial begin
    #(PERIOD * 1000);
    $fatal(1, "FAIL: tiempo limite de simulacion excedido");
  end
endmodule
