`timescale 1ns/1ps
module dphy_hs_contract_TB;
reg clk=0; always #12.5 clk=~clk;
reg rst=1, valid=0, last=0;
wire ready, req, req_ready, data_ready, grant, done, complete, err, abort;
wire cs, ds, dt, ct, ov, ol;
wire [15:0] od;
wire [1:0] ok;
integer cycle=0,grant_cycle=-1,last_cycle=-1,got=0,stops=0,delay_stop=0;
wire data_stopped=delay_stop>=4;
wire stop_ready=!cs&&!ds&&!dt&&!ct;
dsi_hs_transport t(.clk(clk),.rst(rst),.tx_word_data(16'h8a31),
.tx_word_keep(2'b11),.tx_word_valid(valid),.tx_word_last(last),.tx_word_ready(ready),
.hs_req(req),.hs_req_ready(req_ready),.hs_data_ready(data_ready),.hs_grant(grant),
.hs_done(done),.hs_error(err),.hs_complete(complete),.phy_abort(abort),
.hs_word_data(od),.hs_word_keep(ok),.hs_word_valid(ov),.hs_word_last(ol),
.busy(),.error(),.error_code());
dphy_mode_ctrl a(.clk(clk),.rst(rst),.lp_req(1'b0),.lp_req_ready(),.lp_done(1'b0),
.lp_grant(),.lp_complete(),.hs_req(req),.hs_req_ready(req_ready),.hs_done(done),
.hs_error(err),.hs_data_ready(data_ready),.pll_locked(1'b1),.hs_grant(grant),
.hs_complete(complete),.clk_start_req(cs),.data_start_req(ds),.clk_prepared(cs),
.data_prepared(ds),.data_stop_req(dt),.clk_stop_req(ct),.data_stopped(data_stopped),
.clk_stopped(ct),.stop_ready(stop_ready),.clear_error(1'b0),.busy(),.error(),
.error_code(),.phy_abort(abort));
always @(posedge clk) begin
 cycle=cycle+1;
 if(rst) begin grant_cycle=-1; last_cycle=-1; got=0; end
 else begin
  if(err) $fatal(1,"unexpected error");
  if(grant && grant_cycle<0) grant_cycle=cycle;
  if(ov) begin
   if(got==0 && cycle!=grant_cycle+1) $fatal(1,"first capture timing");
   got=got+1;
   if(ol) last_cycle=cycle;
  end
 end
end
always @(negedge clk) begin
 if(rst) begin delay_stop=0; stops=0; end
 else if(dt) begin
  if(delay_stop==0) begin
   if(cycle!=last_cycle+1 || grant) $fatal(1,"stop/grant timing");
   stops=stops+1;
  end
  delay_stop=delay_stop+1;
 end
end
task run(input integer n);
 integer i;
 begin
  @(negedge clk); #1; rst=1; valid=0; last=0;
  repeat(3) @(negedge clk);
  #1; rst=0;
  for(i=0;i<n;i=i+1) begin
   @(negedge clk); #1; valid=1; last=(i==n-1);
   @(posedge clk); while(!ready) @(posedge clk);
  end
  @(negedge clk); #1; valid=0; last=0;
  wait(complete); @(posedge clk); #1;
  if(got!=n || stops!=1) $fatal(1,"counts n=%0d got=%0d stops=%0d",n,got,stops);
  $display("PASS existing RTL timing n=%0d",n);
 end
endtask
initial begin run(1); run(2); run(3); run(2048); $finish; end
initial begin #1000000; $fatal(1,"watchdog"); end
endmodule
