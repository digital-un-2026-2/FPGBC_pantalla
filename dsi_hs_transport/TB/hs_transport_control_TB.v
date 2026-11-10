`timescale 1ns / 1ps
// Matriz dirigida de UC; inyeccion solo para cubrir todos los codigos y prioridades.
module hs_transport_control_TB;
  reg clk = 0;
  always #12.5 clk = ~clk;
  reg rst, abort, valid, last, mask_ok, full, occupied, final_word;
  reg req_ready, grant, complete;
  wire ready, req, data_ready, out_valid, write_en, read_en, prime;
  wire advance, clear_count, busy, error, done;
  wire [1:0] code;
  hs_transport_control dut (
      .clk(clk), .rst(rst), .phy_abort(abort), .valid(valid), .last(last),
      .mask_ok(mask_ok), .full(full), .occupied(occupied), .final_word(final_word),
      .hs_req_ready(req_ready), .hs_grant(grant), .hs_complete(complete),
      .ready(ready), .req(req), .data_ready(data_ready), .out_valid(out_valid),
      .write_en(write_en), .read_en(read_en), .prime(prime), .advance(advance),
      .clear_count(clear_count), .busy(busy), .error(error), .error_code(code), .done(done)
  );
  integer phase, vector, expected_state, cases = 0;
  reg old_done, expected_done, enabled;
  reg [1:0] expected_code;
  reg [11:0] expected_outputs;
  reg [2:0] injected_state;
  initial begin
    for (phase=0; phase<8; phase=phase+1) begin
      for (vector=0; vector<2048; vector=vector+1) begin
        @(negedge clk); #1;
        {rst,abort,valid,last,mask_ok,full,occupied,final_word,req_ready,grant,complete}=vector;
        injected_state=phase;
        old_done=vector%2;
        force dut.state=injected_state;
        force dut.done_reg=old_done;
        force dut.cause_reg=2'b10;
        #1;
        release dut.state; release dut.done_reg; release dut.cause_reg;
        enabled=!rst&&!abort;
        expected_outputs={
          enabled && phase==0,
          enabled && phase==2,
          enabled && (phase==2 || phase==3 || phase==4),
          enabled && phase==4 && grant,
          enabled && phase==0 && valid && mask_ok,
          enabled && (phase==1 || (phase==4 && grant && !final_word)),
          phase==1,
          enabled && phase==4 && grant && !final_word,
          enabled && phase==5 && complete,
          phase!=0 || occupied,
          phase==6,
          enabled && old_done
        };
        if ({ready,req,data_ready,out_valid,write_en,read_en,prime,advance,clear_count,busy,error,done}
            !== expected_outputs || code!==2'b10)
          $fatal(1,"control decode phase=%d vector=%d",phase,vector);
        // Memoria no cambia fuera de posedge, incluidas entradas de reset/aborto.
        #2;
        if (dut.state!==injected_state || dut.done_reg!==old_done || code!==2'b10)
          $fatal(1,"memory changed outside posedge");
        expected_state=phase; expected_done=0; expected_code=2'b10;
        if (rst) begin expected_state=0; expected_code=0; end
        else if (phase==6) expected_state=6;
        else if (abort) begin expected_state=6; expected_code=3; end
        else case(phase)
          0: if(valid) begin
            if(!mask_ok) begin expected_state=6; expected_code=2; end
            else if(full&&!last) begin expected_state=6; expected_code=1; end
            else if(last) expected_state=1;
          end
          1: expected_state=2;
          2: if(req_ready) expected_state=3;
          3: if(grant) expected_state=4;
          4: if(!grant) begin expected_state=6; expected_code=3; end
             else if(final_word) begin expected_state=5; expected_done=1; end
          5: if(complete) expected_state=0;
          default: begin expected_state=6; expected_code=3; end
        endcase
        @(posedge clk); #1;
        if (dut.state!==expected_state[2:0] || dut.done_reg!==expected_done || code!==expected_code)
          $fatal(1,"transition phase=%d vector=%d",phase,vector);
        cases=cases+1;
      end
    end
    $display("PASS transport control: %0d combinations, eight codes, reset/abort priority, same-edge controls",cases);
    $finish;
  end
  initial begin #1000000; $fatal(1,"control watchdog"); end
endmodule
