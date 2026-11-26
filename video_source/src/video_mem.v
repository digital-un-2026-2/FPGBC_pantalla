module video_mem (
    input [10:0] ADDR,
    input [1:0] RGB_PHASE,
    output reg [15:0] VID_WORD
);
  // Ocho barras × 90 píxeles = ocho tramos de 135 palabras.
  // Cada corte se compara en paralelo; no hay memoria ni división.
  wire [7:1] GE;
  assign GE[1] = (ADDR >= 11'd135);
  assign GE[2] = (ADDR >= 11'd270);
  assign GE[3] = (ADDR >= 11'd405);
  assign GE[4] = (ADDR >= 11'd540);
  assign GE[5] = (ADDR >= 11'd675);
  assign GE[6] = (ADDR >= 11'd810);
  assign GE[7] = (ADDR >= 11'd945);

  wire [2:0] BAR;
  assign BAR[2] = GE[4];
  assign BAR[1] = (GE[2] && !GE[4]) || GE[6];
  assign BAR[0] = (GE[1] && !GE[2]) || (GE[3] && !GE[4]) || (GE[5] && !GE[6]) || GE[7];

  // Niveles distintos para distinguir R, G y B también en las barras
  // clara y oscura. Los dos píxeles de cada grupo están en la misma barra.
  wire [7:0] R = BAR[1] ? 8'h10 : 8'hf0;
  wire [7:0] G = BAR[2] ? 8'h20 : 8'he0;
  wire [7:0] B = BAR[0] ? 8'h30 : 8'hd0;

  always @(*) begin
    case (RGB_PHASE)
      2'd0: VID_WORD = {G, R};  // D0=R0, D1=G0
      2'd1: VID_WORD = {R, B};  // D0=B0, D1=R1
      2'd2: VID_WORD = {B, G};  // D0=G1, D1=B1
      default: VID_WORD = 16'h0000;
    endcase
  end
endmodule
