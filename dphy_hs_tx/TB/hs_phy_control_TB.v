`timescale 1ns/1ps
module hs_phy_control_TB;
  reg clk=0; always #12.5 clk=~clk;
  reg [26:0] x=0;
  reg [5:0] flags=0;
  reg [4:0] injected_state;
  reg [2:0] injected_cause;
  wire cp,dp,ds,cs,stop,err,hd,hc,toggle;
  wire [2:0] code;
  hs_phy_control dut(.clk(clk),.rst(x[26]),.phy_abort(x[25]),.cs(x[24]),.ds(x[23]),
    .dt(x[22]),.ct(x[21]),.grant(x[20]),.valid(x[19]),.last(x[18]),
    .p_valid(flags[0]),.p_last(flags[1]),.a_valid(flags[2]),.a_last(flags[3]),
    .mask_ok(x[17:16]==3),.time_last(flags[4]),.post_last(flags[5]),
    .capture(),.move(),.retire(),.clear_pipe(),.sel_word(),.time_sel(),
    .time_load(),.time_step(),.post_load(),.post_step(),
    .clk_prepared(cp),.data_prepared(dp),.data_stopped(ds),.clk_stopped(cs),
    .local_stop(stop),.hs_data_on(hd),.hs_clk_on(hc),.clk_toggle(toggle),
    .lp_clk(),.lp_d0(),.lp_d1(),.phy_error(err),.error_code(code));
  wire [16:0] observed={toggle,hc,hd,err,stop,cs,ds,dp,cp,code,dut.state};
  integer f,rc,n=0;
  reg [16:0] expected;
  reg [1023:0] path;
  initial begin
    if(!$value$plusargs("vectors=%s",path)) $fatal(1,"missing file");
    f=$fopen(path,"r"); if(!f) $fatal(1,"open vectors");
    while(!$feof(f)) begin
      @(negedge clk);
      rc=$fscanf(f,"%h %h %h %h %h\n",injected_state,injected_cause,flags,x,expected);
      if(rc!=5) $fatal(1,"bad control vector");
      force dut.state=injected_state;force dut.cause=injected_cause;
      #1;release dut.state;release dut.cause;
      @(posedge clk);#1;
      if(observed!==expected) $fatal(1,"UC vector %0d state=%0d got=%h want=%h",n,injected_state,observed,expected);
      n=n+1;
    end
    // Force a corrupt nominal selector specifically on a real LOAD in BOOT.
    @(negedge clk);x=0; flags=0;
    force dut.state=5'd0;force dut.cause=3'd0;
    #1;release dut.state;release dut.cause;
    force dut.nominal_sel=4'd15;
    @(posedge clk);#1;
    if(code!==6 || dut.state!==23) $fatal(1,"bad nominal selector");
    release dut.nominal_sel;
    $display("PASS UC: %0d combinations, all 32 codes; corrupt LOAD selector",n);$finish;
  end
endmodule
