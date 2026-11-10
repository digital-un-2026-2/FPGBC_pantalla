`timescale 1ns/1ps
module unit_case #(parameter N=3)(output reg finished=0);
 reg clk=0; always #12.5 clk=~clk;
 reg rst=1,valid=0,last=0,req_ready=0,grant=0,complete=0,abort=0;
 reg [15:0] data=0; reg [1:0] keep=3;
 wire ready,req,data_ready,done,hs_error,out_valid,out_last,busy,error;
 wire [15:0] out_data; wire [1:0] out_keep,code;
 dsi_hs_transport #(.BUFFER_WORDS(N)) dut(
 .clk(clk),.rst(rst),.tx_word_data(data),.tx_word_keep(keep),.tx_word_valid(valid),
 .tx_word_last(last),.tx_word_ready(ready),.hs_req(req),.hs_req_ready(req_ready),
 .hs_data_ready(data_ready),.hs_grant(grant),.hs_done(done),.hs_error(hs_error),
 .hs_complete(complete),.phy_abort(abort),.hs_word_data(out_data),.hs_word_keep(out_keep),
 .hs_word_valid(out_valid),.hs_word_last(out_last),.busy(busy),.error(error),.error_code(code));
 reg [18:0] expected[0:2048]; integer wr=0,rd=0,requests=0,success=0;
 reg checking=1,stream=0,previous_last=0;
 always @(posedge clk) begin
  if(rst) begin wr=0; rd=0; stream=0; previous_last=0; end
  else if(checking) begin
   if(valid && ready) begin expected[wr]={last,keep,data}; wr=wr+1; end
   if(req && req_ready) requests=requests+1;
   if(stream && !out_valid) $fatal(1,"N=%0d bubble",N);
   if(out_valid) begin
    if(rd>=wr || {out_last,out_keep,out_data} !== expected[rd])
      $fatal(1,"N=%0d word mismatch rd=%0d got=%h expected=%h",N,rd,{out_last,out_keep,out_data},expected[rd]);
    rd=rd+1; stream=!out_last;
   end
   if(done !== previous_last) $fatal(1,"done timing");
   previous_last=out_valid && out_last;
   if(done) success=success+1;
  end
 end
 task drive; begin @(negedge clk); #1; end endtask
 task tick; begin @(posedge clk); #1; end endtask
 task reset_all;
 begin
  drive; rst=1; valid=0; grant=0; req_ready=0; complete=0; abort=0;
  #1; if(ready || req || out_valid || done) $fatal(1,"reset gating");
  tick; drive; rst=0; tick;
  if(error || code || busy) $fatal(1,"reset state");
 end endtask
 task push(input integer value,input [1:0] k,input l);
 begin
  drive; data=value; keep=k; last=l; valid=1;
  @(posedge clk); if(!ready) $fatal(1,"unexpected not ready");
  drive; valid=0;
 end endtask
 task reserve;
 begin
  wait(req); repeat(4) begin tick; if(!req || !data_ready || out_valid) $fatal(1,"request unstable"); end
  drive; req_ready=1; tick; drive; req_ready=0;
  repeat(4) begin tick; if(req || !data_ready || out_valid) $fatal(1,"wait grant"); end
 end endtask
 task finish_packet;
 begin
  reserve; drive; grant=1;
  wait(done); drive; grant=0;
  repeat(4) begin tick; if(ready || !busy || out_valid || done) $fatal(1,"early release"); end
  drive; complete=1; tick; drive; complete=0; tick;
  if(!ready || busy || rd!=wr) $fatal(1,"release/scoreboard");
  wr=0; rd=0;
 end endtask
 task expect_error(input [1:0] c);
 begin
  tick; if(!error || !hs_error || code!=c || ready || req || out_valid || done) $fatal(1,"error code expected %d got %d",c,code);
  drive; abort=1; repeat(3) tick;
  if(code!=c) $fatal(1,"first error not retained");
  reset_all;
 end endtask
 task interrupt_phase(input integer target,input do_abort);
 begin
  reset_all;
  if(target==0) begin
   if(N>1) push(321,3,0);
  end else begin
   push(123,3,1); // Al volver, PRIME todavia no ha leido RAM.
   if(target>=2) begin tick; drive; end
   if(target>=3) begin req_ready=1; tick; drive; req_ready=0; end
   if(target>=4) begin grant=1; tick; drive; end
   if(target>=5) begin tick; drive; end
   if(target==6) begin abort=1; tick; drive; end
  end
  if(dut.control.state!==target[2:0]) $fatal(1,"phase setup %d",target);
  if(do_abort) begin
   abort=1; #1;
   if(ready || req || out_valid || done) $fatal(1,"abort masks phase %d",target);
   tick;
   if(!error || code!=3) $fatal(1,"abort phase %d",target);
  end
  rst=1; valid=0; #1;
  if(ready || req || out_valid || done) $fatal(1,"reset masks phase %d",target);
  tick; drive; rst=0; abort=0; grant=0; req_ready=0; complete=0; tick;
  if(error || code || busy || !ready) $fatal(1,"phase recovery %d",target);
 end endtask
 integer i,j,before_requests,before_success;
 initial begin
  repeat(2) tick; reset_all;
  before_requests=requests; before_success=success;
  for(j=0;j<4;j=j+1) begin
   for(i=0;i<N;i=i+1) begin
    push(i+j*71,(i==N-1 && j%2)?1:3,i==N-1);
    if(i<N-1) repeat(i%3) tick;
   end
   finish_packet;
  end
  if(requests-before_requests!=4 || success-before_success!=4) $fatal(1,"duplicate transaction");
  checking=0;
  for(i=0;i<N;i=i+1) push(i,3,0);
  expect_error(1);
  push(0,0,1); expect_error(2);
  push(0,2,1); expect_error(2);
  push(0,1,0); expect_error(2);
  // Cada fase real de la cadena: no basta con resetear solo la UC inyectada.
  for(j=0;j<7;j=j+1) begin
   interrupt_phase(j,0);
   interrupt_phase(j,1);
  end
  push(0,3,1); drive; abort=1; expect_error(3);
  push(0,3,1); reserve; drive; grant=1; tick;
  drive; abort=1; #1; if(out_valid || done) $fatal(1,"abort gating"); expect_error(3);
  push(0,3,1); reserve; drive; grant=1; tick;
  drive; grant=0; expect_error(3);
  checking=1; push(42,1,1); finish_packet;
  $display("PASS transport unit depth=%0d",N); finished=1;
 end
endmodule
module hs_transport_TB;
 wire a,b,c;
 unit_case #(1) one(a); unit_case #(3) three(b); unit_case #(2048) depth2048(c);
 initial begin wait(a&&b&&c); $display("PASS transport unit all depths"); $finish; end
 initial begin #5000000; $fatal(1,"unit watchdog"); end
endmodule
