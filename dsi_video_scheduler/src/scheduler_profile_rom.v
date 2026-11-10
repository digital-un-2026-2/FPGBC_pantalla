`timescale 1ns / 1ps

// Tablas constantes: el elemento cero ocupa los bits menos significativos.
// Evento = {KIND[2], RELEASE[32], DEADLINE[32]}. Lectura combinacional.
module scheduler_profile_rom #(
    parameter integer N_PROFILES = 1,
    parameter integer E_MAX = 1,
    parameter [N_PROFILES*16-1:0] WIDTH_TABLE = 0,
    parameter [N_PROFILES*16-1:0] HEIGHT_TABLE = 0,
    parameter [N_PROFILES*16-1:0] N_EVENTS_TABLE = 0,
    parameter [N_PROFILES*32-1:0] T_FRAME_TABLE = 0,
    parameter [N_PROFILES-1:0] TIMING_OK_TABLE = 0,
    parameter [N_PROFILES-1:0] TARGET_OK_TABLE = 0,
    parameter [N_PROFILES*E_MAX*66-1:0] EVENT_TABLE = {N_PROFILES*E_MAX{66'h30000000000000000}}
) (
    input [7:0] profile_id, input [15:0] ip,
    output reg [15:0] width, output reg [15:0] height,
    output reg [15:0] n_events, output reg [31:0] t_frame,
    output reg timing_ok, output reg target_ok,
    output reg [65:0] event_data
);
  // Extender el ID: 8'd255 sigue siendo legal con N_PROFILES=256.
  always @(*) begin
    width = 0; height = 0; n_events = 0; t_frame = 0;
    timing_ok = 0; target_ok = 0;
    event_data = {2'd3, 32'd0, 32'd0};
    if ({1'b0, profile_id} < N_PROFILES) begin
      width = WIDTH_TABLE[profile_id*16 +: 16];
      height = HEIGHT_TABLE[profile_id*16 +: 16];
      n_events = N_EVENTS_TABLE[profile_id*16 +: 16];
      t_frame = T_FRAME_TABLE[profile_id*32 +: 32];
      timing_ok = TIMING_OK_TABLE[profile_id];
      target_ok = TARGET_OK_TABLE[profile_id];
      if (ip < n_events && ip < E_MAX)
        event_data = EVENT_TABLE[(profile_id*E_MAX+ip)*66 +: 66];
    end
  end

  // Un perfil habilitado debe tener una tabla estructuralmente legal.
  // Esto NO demuestra el presupuesto temporal ni certifica un panel.
  function integer schedule_ok;
    input integer p;
    integer e, rgb_count, n;
    reg [65:0] ev;
    reg [31:0] previous_release, frame_limit;
    begin
      n = N_EVENTS_TABLE[p*16 +: 16];
      frame_limit = T_FRAME_TABLE[p*32 +: 32];
      schedule_ok = n >= 1 && n <= E_MAX && frame_limit <= 32'hfffffffe;
      rgb_count = 0; previous_release = 0;
      for (e = 0; e < E_MAX; e = e + 1) begin
        if (e < n) begin
          ev = EVENT_TABLE[(p*E_MAX+e)*66 +: 66];
          if (ev[65:64] == 1) rgb_count = rgb_count + 1;
          if (ev[65:64] == 3 || ev[63:32] > ev[31:0] ||
              ev[31:0] > frame_limit || ev[63:32] < previous_release ||
              (ev[65:64] == 2) != (e == n-1)) schedule_ok = 0;
          previous_release = ev[63:32];
        end
      end
      if (rgb_count != HEIGHT_TABLE[p*16 +: 16]) schedule_ok = 0;
    end
  endfunction

  genvar p;
  generate
    if (N_PROFILES < 1 || N_PROFILES > 256 || E_MAX < 1 || E_MAX > 65535) begin : invalid_size
      DSI_SCHEDULER_INVALID_ROM_SIZE invalid_config ();
    end
    for (p = 0; p < N_PROFILES; p = p + 1) begin : validate_profile
      if (TIMING_OK_TABLE[p] && TARGET_OK_TABLE[p] && !schedule_ok(p)) begin : invalid_table
        DSI_SCHEDULER_INVALID_ENABLED_SCHEDULE invalid_config ();
      end
    end
  endgenerate
endmodule
