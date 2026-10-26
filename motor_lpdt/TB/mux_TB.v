`timescale 1ns / 1ps

// Cada instancia compara contra palabras separadas, no contra otro part-select.
module mux_test_case #(
    parameter INPUTS = 2,
    parameter BITS = 8,
    parameter SEL_BITS = (INPUTS > 1) ? $clog2(INPUTS) : 1
) (
    output reg done = 0
);
  reg [INPUTS*BITS-1:0] data_in = 0;
  reg [SEL_BITS-1:0] sel = 0;
  wire [BITS-1:0] data_out;
  reg [BITS-1:0] words [0:INPUTS-1];
  reg [BITS-1:0] expected;
  integer pattern;
  integer selection;
  integer lane;
  integer bit_index;

  mux #(.INPUTS(INPUTS), .BITS(BITS)) dut (
      .data_in(data_in), .sel(sel), .data_out(data_out)
  );

  task pack_inputs;
    integer entry;
    integer bit_number;
    begin
      for (entry = 0; entry < INPUTS; entry = entry + 1)
        for (bit_number = 0; bit_number < BITS; bit_number = bit_number + 1)
          data_in[entry*BITS + bit_number] = words[entry][bit_number];
    end
  endtask

  task check;
    begin
      if (selection < INPUTS)
        expected = words[selection];
      else
        expected = 0;
      #1;  // Solo permite estabilizar la logica combinacional en simulacion.
      if (data_out !== expected)
        $fatal(1, "FAIL %m: patron=%0d sel=%0d entrada=%h salida=%h esperado=%h",
               pattern, selection, data_in, data_out, expected);
    end
  endtask

  initial begin
    // 8:1 de un bit: las 256 combinaciones posibles del vector de entrada.
    // Resto: ceros, unos, un bit activo por palabra y patrones deterministas.
    for (pattern = 0; pattern < 256; pattern = pattern + 1) begin
      for (selection = 0; selection < (2**SEL_BITS); selection = selection + 1) begin
        for (lane = 0; lane < INPUTS; lane = lane + 1) begin
          if (INPUTS == 8 && BITS == 1)
            words[lane] = (pattern >> lane) & 1;
          else if (pattern == 0)
            words[lane] = 0;
          else if (pattern == 1)
            words[lane] = {BITS{1'b1}};
          else if (pattern < BITS + 2) begin
            words[lane] = 0;
            bit_index = (pattern - 2 + lane) % BITS;
            words[lane][bit_index] = 1'b1;
          end else
            words[lane] = (pattern * 73) ^ (lane * 37);
        end

        pack_inputs;
        sel = selection;
        check;

        // Cambiar entradas no seleccionadas no debe afectar a la salida.
        for (lane = 0; lane < INPUTS; lane = lane + 1)
          if (lane != selection) words[lane] = ~words[lane];
        pack_inputs;
        check;

        // Cambiar la entrada seleccionada debe propagarse sin reloj.
        if (selection < INPUTS) begin
          words[selection] = ~words[selection];
          pack_inputs;
          check;
        end
      end
    end
    $display("PASS: %m (INPUTS=%0d BITS=%0d)", INPUTS, BITS);
    done = 1;
  end
endmodule

module mux_TB;
  wire [4:0] done;

  mux_test_case #(.INPUTS(8), .BITS(1)) bit_mux (.done(done[0]));
  mux_test_case byte_mux (.done(done[1]));  // Por defecto: 2:1 de 8 bits.
  mux_test_case #(.INPUTS(8), .BITS(8)) wide_mux (.done(done[2]));
  mux_test_case #(.INPUTS(3), .BITS(5)) odd_mux (.done(done[3]));
  mux_test_case #(.INPUTS(1), .BITS(8)) single_mux (.done(done[4]));

  initial begin
    $dumpfile("mux_TB.vcd");
    $dumpvars(0, mux_TB);
    wait (&done);
    #1;
    $display("PASS: mux_TB");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "FAIL: tiempo limite de simulacion excedido");
  end
endmodule
