`timescale 1ns/1ps
module gowin_tx_TB;
  localparam J=`GOWIN_MODEL_J, L=2+J;
  reg ref_clk=0, rst=1, phy_abort=0, lp_grant=0;
  always #12.5 ref_clk=~ref_clk;
  reg [1:0] estado_D0=3, hs_frame_kind=0, lp_clk=3, lp_d0=3, lp_d1=3;
  reg [15:0] hs_frame_data=0;
  reg hs_data_on=0, hs_clk_on=0, clk_toggle=0;
  reg clk_prepared_s=0,data_prepared_s=0,data_stopped_s=1,clk_stopped_s=1,local_stop_s=1;
  wire byte_clk,rst_byte,clk_prepared_p,data_prepared_p,data_stopped_p,clk_stopped_p;
  wire stop_ready,pll_ready,clock_fault;
  wire [2:0] lp_pad_p,lp_pad_n,hs_pad_p,hs_pad_n;
  dphy_gowin_tx #(.J(J),.PROFILE_OK(1)) dut (.*);
  wire [2:0] disabled_lp_p,disabled_lp_n,disabled_hs_p,disabled_hs_n;
  wire disabled_ready,disabled_stop;
  dphy_gowin_tx disabled (
      .ref_clk(ref_clk),.rst(rst),.phy_abort(1'b0),.lp_grant(1'b0),.estado_D0(2'b11),
      .hs_frame_data(16'hffff),.hs_frame_kind(2'd2),.hs_data_on(1'b1),.hs_clk_on(1'b1),
      .clk_toggle(1'b1),.lp_clk(2'b11),.lp_d0(2'b11),.lp_d1(2'b11),
      .clk_prepared_s(1'b1),.data_prepared_s(1'b1),.data_stopped_s(1'b1),
      .clk_stopped_s(1'b1),.local_stop_s(1'b1),
      .byte_clk(),.rst_byte(),.clk_prepared_p(),.data_prepared_p(),.data_stopped_p(),.clk_stopped_p(),
      .stop_ready(disabled_stop),.pll_ready(disabled_ready),.clock_fault(),
      .lp_pad_p(disabled_lp_p),.lp_pad_n(disabled_lp_n),.hs_pad_p(disabled_hs_p),.hs_pad_n(disabled_hs_n));
  task tick; begin @(posedge ref_clk); #0.02; end endtask
  task blocked;
    begin
      if ({lp_pad_p,lp_pad_n,hs_pad_p,hs_pad_n} !== 12'bzzzzzzzzzzzz ||
          {clk_prepared_p,data_prepared_p,data_stopped_p,clk_stopped_p,pll_ready,stop_ready} !== 6'b0)
        $fatal(1,"blocked pads/feedback at %t",$time);
    end
  endtask
  task idle_inputs;
    begin
      lp_grant=0;estado_D0=3;hs_frame_data=0;hs_frame_kind=0;
      hs_data_on=0;hs_clk_on=0;clk_toggle=0;lp_clk=3;lp_d0=3;lp_d1=3;
      clk_prepared_s=0;data_prepared_s=0;data_stopped_s=1;clk_stopped_s=1;local_stop_s=1;
    end
  endtask
  task reset_all;
    begin
      @(negedge ref_clk); #1; rst=1; phy_abort=0;
      dut.clocks.pll0.halted=0;dut.clocks.pll0.locked=1;
      idle_inputs;
      repeat(4) tick;
      if(clock_fault) $fatal(1,"reset did not clear fault");
      blocked;
      @(negedge ref_clk); #1; rst=0;
    end
  endtask
  task ready;
    integer n;
    begin
      n=0;
      while(!stop_ready && n<80) begin tick;n=n+1;end
      if(!stop_ready || !pll_ready || clock_fault) $fatal(1,"startup timeout");
      repeat(6) tick;
    end
  endtask
  reg [32:0] history[0:L-1];
  reg [32:0] expected;
  reg [16:0] c;
  reg [5:0] pads_lp;
  reg [2:0] enabled;
  reg expected_stop;
  integer i,k,b,seed=32'h5678;
  task compare_cycle;
    begin
      @(posedge ref_clk);
      for(k=L-1;k>0;k=k-1) history[k]=history[k-1];
      history[0]={hs_frame_data,local_stop_s,clk_stopped_s,data_stopped_s,
          data_prepared_s,clk_prepared_s,lp_grant,lp_clk,lp_d1,
          lp_grant?estado_D0:lp_d0,clk_toggle,hs_clk_on,hs_data_on,hs_frame_kind};
      expected=history[L-1];c=expected[16:0];
      #0.01;
      pads_lp={lp_pad_p[2],lp_pad_n[2],lp_pad_p[1],lp_pad_n[1],lp_pad_p[0],lp_pad_n[0]};
      if(pads_lp!==c[10:5]) $fatal(1,"LP latency/bit order: %h expected %h i=%0d dutL=%0d ctrl=%h hist=%h",pads_lp,c[10:5],i,dut.L,dut.dp.ctrl[L-1],history[L-1]);
      if({clk_stopped_p,data_stopped_p,data_prepared_p,clk_prepared_p}!==c[15:12])
        $fatal(1,"ACK latency");
      expected_stop=c[16] && c[10:5]==6'h3f && !c[3] && !c[2] && !c[11] && !lp_grant && estado_D0==3;
      if(stop_ready!==expected_stop) $fatal(1,"stop qualification");
      enabled={c[3],c[2],c[2]};
      // Sample after centered CLK edge, with data stable for half a UI.
      #1.56;
      for(b=0;b<8;b=b+1) begin
        if(hs_pad_p[0] !== (enabled[0]?expected[17+b]:1'bz) ||
           hs_pad_p[1] !== (enabled[1]?expected[25+b]:1'bz) ||
           hs_pad_p[2] !== (enabled[2]?(c[4] && (b%2)):1'bz))
          $fatal(1,"serial bit %0d, L=%0d at %t",b,L,$time);
        for(k=0;k<3;k=k+1)
          if(hs_pad_n[k] !== (enabled[k]?~hs_pad_p[k]:1'bz)) $fatal(1,"differential output");
        if(b!=7) #3.125;
      end
    end
  endtask
  initial begin
    repeat(4) tick;blocked;
    phy_abort=1;rst=0;
    repeat(8) tick;
    if(pll_ready || clock_fault || dut.run_started) $fatal(1,"startup abort should wait");
    @(negedge ref_clk);#1;phy_abort=0;ready;
    for(k=0;k<L;k=k+1) history[k]={16'h0,1'b1,4'b1100,1'b0,6'h3f,3'b0,2'b0};
    for(i=0;i<128;i=i+1) begin
      if(i==0) begin @(negedge ref_clk);#1;end else #0.1;
      hs_frame_data=$random(seed);hs_frame_kind=$random(seed);
      {local_stop_s,clk_stopped_s,data_stopped_s,data_prepared_s,clk_prepared_s,
       lp_grant,lp_clk,lp_d1,lp_d0,clk_toggle,hs_clk_on,hs_data_on}=$random(seed);
      estado_D0=$random(seed);
      compare_cycle;
    end
    if(disabled_ready || disabled_stop ||
        {disabled_lp_p,disabled_lp_n,disabled_hs_p,disabled_hs_n}!==12'bzzzzzzzzzzzz)
      $fatal(1,"default profile not blocked");

    // Stop must also qualify current LP owner and the motor, without a clock.
    reset_all;ready;
    #1;lp_grant=1;#0.01;if(stop_ready) $fatal(1,"current owner ignored");
    lp_grant=0;estado_D0=0;#0.01;if(stop_ready) $fatal(1,"current LP state ignored");
    estado_D0=3;
    // Abort shorter than REF/PCLK, with all derived clocks halted.
    dut.clocks.pll0.halted=1;
    #1;phy_abort=1;#0.01;blocked;
    if(rst_byte) $fatal(1,"abort must not reset arbiter");
    #0.5;phy_abort=0;
    repeat(5) tick;blocked;
    if(clock_fault) $fatal(1,"abort invented clock_fault");
    dut.clocks.pll0.halted=0;repeat(12) tick;blocked;

    reset_all;ready;
    // LOCK pulse entirely between REF edges: sticky even after LOCK recovers.
    @(negedge ref_clk);#1;dut.clocks.pll0.locked=0;
    #0.01;blocked;
    if(!clock_fault || !rst_byte) $fatal(1,"raw lock loss not captured");
    #0.5;dut.clocks.pll0.locked=1;
    repeat(12) tick;blocked;
    if(!clock_fault || rst_byte) $fatal(1,"fault/reset recovery distinction");

    reset_all;
    wait(dut.release_safe);#0.2;phy_abort=1;#0.01;blocked;
    #0.5;phy_abort=0;
    repeat(16) tick;blocked;
    if(clock_fault) $fatal(1,"RELEASE abort invented clock fault");

    reset_all;ready;
    @(negedge ref_clk);#1;force dut.uc.state=3'b100;
    #0.01;blocked;release dut.uc.state;
    repeat(12) tick;blocked;
    if(clock_fault) $fatal(1,"invalid state invented lock fault");

    reset_all;ready;
    force dut.pipe_valid=0;
    repeat(6) tick;release dut.pipe_valid;
    repeat(6) tick;blocked;
    reset_all;ready;
    $display("PASS Gowin unit: L=%0d, 128 serial/LP/ACK vectors, startup, brief abort/PLL loss, halted clocks, RELEASE, invalid STATE, READY loss, reset",L);
    $finish;
  end
  initial begin #100000; $fatal(1,"unit watchdog"); end
endmodule
