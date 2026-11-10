`timescale 1ns/1ps
module gowin_fault_link_TB;
  localparam J=`GOWIN_MODEL_J;
  reg ref_clk=0, system_rst=1;
  always #12.5 ref_clk=~ref_clk;
  wire clk,rst_byte;
  wire rst=system_rst|rst_byte;
  reg valid=0,last=0,inject_error=0;
  reg [1:0] keep=3;
  wire ready,req,req_ready,reserved,grant,done,complete,transport_error,abort;
  wire cs,ds,dt,ct,cp,dp,dstop,cstop,stop_ready,phy_error,mode_error,pll_ready,clock_fault;
  wire [2:0] phy_code;
  wire [1:0] mode_code,transport_code;
  wire [15:0] word,frame;
  wire [1:0] word_keep,kind,lpc,lpd0,lpd1;
  wire word_valid,word_last,rcp,rdp,rds,rcs,rls,hson,hclk,toggle;
  wire [2:0] lp_p,lp_n,hs_p,hs_n;
  dsi_hs_transport t(.clk(clk),.rst(rst),.tx_word_data(16'h55aa),
    .tx_word_keep(keep),.tx_word_valid(valid),.tx_word_last(last),.tx_word_ready(ready),
    .hs_req(req),.hs_req_ready(req_ready),.hs_data_ready(reserved),.hs_grant(grant),
    .hs_done(done),.hs_error(transport_error),.hs_complete(complete),.phy_abort(abort),
    .hs_word_data(word),.hs_word_keep(word_keep),.hs_word_valid(word_valid),
    .hs_word_last(word_last),.busy(),.error(),.error_code(transport_code));
  dphy_mode_ctrl a(.clk(clk),.rst(rst),.lp_req(1'b0),.lp_req_ready(),.lp_done(1'b0),
    .lp_grant(),.lp_complete(),.hs_req(req),.hs_req_ready(req_ready),.hs_done(done),
    .hs_error(transport_error|phy_error|clock_fault|inject_error),.hs_data_ready(reserved),.pll_locked(pll_ready),
    .hs_grant(grant),.hs_complete(complete),.clk_start_req(cs),.data_start_req(ds),
    .data_stop_req(dt),.clk_stop_req(ct),.clk_prepared(cp),.data_prepared(dp),
    .data_stopped(dstop),.clk_stopped(cstop),.stop_ready(stop_ready),
    .clear_error(1'b0),.busy(),.error(mode_error),.error_code(mode_code),.phy_abort(abort));
  dphy_hs_tx phy(.clk(clk),.rst(rst),.phy_abort(abort),.clk_start_req(cs),
    .data_start_req(ds),.data_stop_req(dt),.clk_stop_req(ct),.hs_grant(grant),
    .hs_word_data(word),.hs_word_keep(word_keep),.hs_word_valid(word_valid),
    .hs_word_last(word_last),.clk_prepared(rcp),.data_prepared(rdp),
    .data_stopped(rds),.clk_stopped(rcs),.hs_local_stop(rls),
    .phy_error(phy_error),.error_code(phy_code),.hs_frame_data(frame),.hs_frame_kind(kind),
    .hs_data_on(hson),.hs_clk_on(hclk),.clk_toggle(toggle),.lp_clk(lpc),.lp_d0(lpd0),.lp_d1(lpd1));
  dphy_gowin_tx #(.J(J),.PROFILE_OK(1)) w (
    .ref_clk(ref_clk),.rst(system_rst),.phy_abort(abort),.lp_grant(1'b0),.estado_D0(2'b11),
    .hs_frame_data(frame),.hs_frame_kind(kind),.hs_data_on(hson),.hs_clk_on(hclk),.clk_toggle(toggle),
    .lp_clk(lpc),.lp_d0(lpd0),.lp_d1(lpd1),.clk_prepared_s(rcp),.data_prepared_s(rdp),
    .data_stopped_s(rds),.clk_stopped_s(rcs),.local_stop_s(rls),
    .byte_clk(clk),.rst_byte(rst_byte),.clk_prepared_p(cp),.data_prepared_p(dp),
    .data_stopped_p(dstop),.clk_stopped_p(cstop),.stop_ready(stop_ready),
    .pll_ready(pll_ready),.clock_fault(clock_fault),
    .lp_pad_p(lp_p),.lp_pad_n(lp_n),.hs_pad_p(hs_p),.hs_pad_n(hs_n));
  task blocked;
    begin
      if({lp_p,lp_n,hs_p,hs_n}!==12'bzzzzzzzzzzzz ||
         {cp,dp,dstop,cstop,stop_ready,pll_ready}!==6'b0) $fatal(1,"fault mask");
    end
  endtask
  task reset_chain;
    begin
      @(negedge ref_clk);#1;system_rst=1;valid=0;last=0;keep=3;inject_error=0;
      w.clocks.pll0.halted=0;w.clocks.pll0.locked=1;
      repeat(4) @(posedge ref_clk);
      @(negedge ref_clk);#1;system_rst=0;
      wait(stop_ready);@(negedge clk);#1;
    end
  endtask
  task send_word(input final_word,input [1:0] mask);
    begin
      @(negedge clk);#1;valid=1;last=final_word;keep=mask;
      @(posedge clk);while(!ready) @(posedge clk);
      @(negedge clk);#1;valid=0;
    end
  endtask
  integer successes=0,phase_index,phase_target,fault_kind;
  integer phases[0:4];
  always @(negedge clk) begin
    #1;if(!rst && complete) successes=successes+1;
  end
  initial begin
    phases[0]=4;phases[1]=11;phases[2]=12;phases[3]=18;phases[4]=20;
    for(fault_kind=0;fault_kind<3;fault_kind=fault_kind+1)
      for(phase_index=0;phase_index<5;phase_index=phase_index+1) begin
        reset_chain;send_word(0,3);send_word(1,3);
        // Hierarchy chooses the injection instant only. Outcomes use ports.
        phase_target=phases[phase_index];wait(phy.control.state==phase_target);
        @(negedge ref_clk);#1;
        case(fault_kind)
          0: begin
            w.clocks.pll0.halted=1;w.clocks.pll0.locked=0;
            #0.01;blocked;
            if(!clock_fault || !rst_byte) $fatal(1,"PLL capture/reset");
            // Recover raw clocks and LOCK. The wrapper must remain blocked.
            repeat(3) @(posedge ref_clk);
            @(negedge ref_clk);#1;w.clocks.pll0.locked=1;w.clocks.pll0.halted=0;
          end
          1: begin inject_error=1;wait(abort);#0.01;blocked;inject_error=0;end
          2: begin system_rst=1;#0.01;blocked;end
        endcase
        repeat(20) @(negedge ref_clk);#1;
        blocked;
        if(successes) $fatal(1,"complete after interrupted prefix");
        if(fault_kind==0 && (!clock_fault || pll_ready || stop_ready || rst_byte))
          $fatal(1,"lost-clock recovery cause clock=%b mode=%b code=%0d transport=%b rst=%b abort=%b",clock_fault,mode_error,mode_code,transport_error,rst,abort);
        if(fault_kind==1 && (clock_fault || !mode_error || !transport_error))
          $fatal(1,"abort recovery cause");
      end
    reset_chain;send_word(0,3);send_word(1,1);
    wait(mode_error);repeat(12) @(negedge ref_clk);#1;blocked;
    if(!phy_error || phy_code!=1 || !transport_error || successes)
      $fatal(1,"partial lane failure");
    reset_chain;send_word(0,3);send_word(1,3);
    wait(complete);repeat(3) @(negedge clk);#1;
    if(successes!=1 || mode_error || phy_error || transport_error || clock_fault)
      $fatal(1,"coordinated reset recovery");
    $display("PASS Gowin fault link: L=%0d; PLL loss/halted clocks, abort and reset in 5 HS phases; partial lane; reset recovery",2+J);
    $finish;
  end
  initial begin #4000000;$fatal(1,"fault link watchdog");end
endmodule
