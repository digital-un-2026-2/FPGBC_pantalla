`timescale 1ns/1ps
module hs_phy_fault_link_TB;
  reg clk=0;always #12.5 clk=~clk;
  reg rst=1,pll=1,valid=0,last=0;
  reg [1:0] keep=3;
  wire ready,req,req_ready,reserved,grant,done,complete,transport_error,abort;
  wire cs,ds,dt,ct,cp,dp,dstop,cstop,local_stop,phy_error,mode_error;
  wire [2:0] phy_code;
  wire [1:0] mode_code,transport_code;
  wire [15:0] word;
  wire [1:0] word_keep;
  wire word_valid,word_last;
  dsi_hs_transport t(.clk(clk),.rst(rst),.tx_word_data(16'h55aa),
    .tx_word_keep(keep),.tx_word_valid(valid),.tx_word_last(last),.tx_word_ready(ready),
    .hs_req(req),.hs_req_ready(req_ready),.hs_data_ready(reserved),.hs_grant(grant),
    .hs_done(done),.hs_error(transport_error),.hs_complete(complete),.phy_abort(abort),
    .hs_word_data(word),.hs_word_keep(word_keep),.hs_word_valid(word_valid),
    .hs_word_last(word_last),.busy(),.error(),.error_code(transport_code));
  dphy_mode_ctrl a(.clk(clk),.rst(rst),.lp_req(1'b0),.lp_req_ready(),.lp_done(1'b0),
    .lp_grant(),.lp_complete(),.hs_req(req),.hs_req_ready(req_ready),.hs_done(done),
    .hs_error(transport_error|phy_error),.hs_data_ready(reserved),.pll_locked(pll),
    .hs_grant(grant),.hs_complete(complete),.clk_start_req(cs),.data_start_req(ds),
    .data_stop_req(dt),.clk_stop_req(ct),.clk_prepared(cp),.data_prepared(dp),
    .data_stopped(dstop),.clk_stopped(cstop),.stop_ready(local_stop),
    .clear_error(1'b0),.busy(),.error(mode_error),.error_code(mode_code),.phy_abort(abort));
  dphy_hs_tx phy(.clk(clk),.rst(rst),.phy_abort(abort),.clk_start_req(cs),
    .data_start_req(ds),.data_stop_req(dt),.clk_stop_req(ct),.hs_grant(grant),
    .hs_word_data(word),.hs_word_keep(word_keep),.hs_word_valid(word_valid),
    .hs_word_last(word_last),.clk_prepared(cp),.data_prepared(dp),
    .data_stopped(dstop),.clk_stopped(cstop),.hs_local_stop(local_stop),
    .phy_error(phy_error),.error_code(phy_code),.hs_frame_data(),.hs_frame_kind(),
    .hs_data_on(),.hs_clk_on(),.clk_toggle(),.lp_clk(),.lp_d0(),.lp_d1());
  task reset_chain;
    begin
      @(negedge clk);#1;rst=1;pll=1;valid=0;last=0;keep=3;
      repeat(3) @(posedge clk);
      @(negedge clk);#1;rst=0;
      wait(local_stop);@(negedge clk);#1;
    end
  endtask
  task send_word(input final_word,input [1:0] mask);
    begin
      @(negedge clk);#1;valid=1;last=final_word;keep=mask;
      @(posedge clk);while(!ready) @(posedge clk);
      @(negedge clk);#1;valid=0;
    end
  endtask
  integer successes=0,phase_index,phase_target;
  integer phases[0:4];
  always @(negedge clk) begin
    #1;if(!rst && complete) successes=successes+1;
  end
  initial begin
    phases[0]=4; phases[1]=11; phases[2]=12; phases[3]=18; phases[4]=20;
    for(phase_index=0;phase_index<5;phase_index=phase_index+1) begin
      reset_chain;
      send_word(0,3);send_word(1,3);
      // Hierarchy selects injection time only; outcomes use public ports.
      phase_target=phases[phase_index];
      wait(phy.control.state==phase_target);
      @(negedge clk);#1;pll=0;
      #1;if(!abort || grant) $fatal(1,"PLL abort mask");
      wait(mode_error && local_stop);repeat(5) @(negedge clk);#1;
      if(mode_code!=1 || !transport_error || transport_code!=3 || phy_error || successes)
        $fatal(1,"PLL recovery code state=%0d mode=%0d phy=%0d",phases[phase_index],mode_code,phy_code);
    end
    reset_chain;
    send_word(0,3);send_word(1,1);
    wait(mode_error && local_stop);repeat(5) @(negedge clk);#1;
    if(mode_code!=2 || !phy_error || phy_code!=1 || !transport_error || successes)
      $fatal(1,"partial lane failure path");
    // Coordinated reset recovers every component; then a correct packet succeeds.
    reset_chain;send_word(0,3);send_word(1,3);
    wait(complete);repeat(3) @(negedge clk);#1;
    if(successes!=1 || mode_error || phy_error || transport_error)
      $fatal(1,"coordinated reset recovery");
    $display("PASS fault link: PLL loss in 5 phases, partial lane, coordinated recovery");$finish;
  end
  initial begin #2000000;$fatal(1,"fault link watchdog");end
endmodule
