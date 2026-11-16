`timescale 1ns / 1ps

module validador_descriptor_TB;
  reg [4:0] paso;
  reg [7:0] base;
  reg [4:0] longitud;
  wire valido;
  wire [35:0] descriptor;
  reg [7:0] direccion;
  wire [7:0] dato;
  integer p, b, n, siguiente;
  reg esperado;

  validador_descriptor dut (
      .paso(paso), .base_activa(base), .longitud_activa(longitud),
      .descriptor_valido(valido)
  );
  rom_descriptores descriptores (.paso(paso), .descriptor(descriptor));
  rom_paquetes paquetes (.direccion(direccion), .dato(dato));

  initial begin
    // Oráculo de enteros, sin el posible overflow del sumador RTL.
    for (p = 0; p < 32; p = p + 1)
      for (b = 0; b < 256; b = b + 1)
        for (n = 0; n < 32; n = n + 1) begin
          paso = p;
          base = b;
          longitud = n;
          esperado = p < 18 && n > 0 && n <= 22 && b + n <= 204;
          #1;
          if (valido !== esperado)
            $fatal(1, "FAIL: descriptor p=%0d base=%0d largo=%0d", p, b, n);
        end
    siguiente = 0;
    for (p = 0; p < 32; p = p + 1) begin
      paso = p; #1;
      if (p < 18) begin
        base = descriptor[35:28];
        longitud = descriptor[27:23]; #1;
        if (!valido || base != siguiente)
          $fatal(1, "FAIL: descriptor ROM %0d", p);
        siguiente = siguiente + longitud;
        if (descriptor[22:0] !== ((p == 4 || p == 9) ? 2600000 :
                                  (p == 17 ? 0 : 360000)))
          $fatal(1, "FAIL: espera ROM %0d", p);
      end else if (descriptor !== 36'd0)
        $fatal(1, "FAIL: descriptor fuera de rango");
    end
    if (siguiente != 204) $fatal(1, "FAIL: tamaño ROM");
    for (b = 204; b < 256; b = b + 1) begin
      direccion = b; #1;
      if (dato !== 8'd0) $fatal(1, "FAIL: byte fuera de rango");
    end
    $display("PASS: validador_descriptor_TB; 262144 combinaciones, ROM y rangos");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "FAIL: timeout validador_descriptor_TB");
  end
endmodule
