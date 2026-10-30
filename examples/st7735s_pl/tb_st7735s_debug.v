`timescale 1ns/1ps
// Simulation substitutes for the generated debug IP, never synthesized.
module lcd_ila(input clk,input [7:0] probe0,input [31:0] probe1,input probe2);
    integer events=0;
    always @(posedge clk) if(probe2) events=events+1;
endmodule
module lcd_vio(input clk,input [31:0] probe_in0,probe_in1,probe_in2,probe_in3,
    input [7:0] probe_in4,output reg probe_out0=0);
endmodule
module tb_st7735s_debug;
    reg clk=0;
    always #10 clk=~clk;
    wire res,cs,sck,dc,sda,bl;
    integer before_ticks,before_events;
    integer byte_count=0;
    time res_release=0,sleep_end=0;
    st7735s_top #(.CLK_HZ(1000),.SPI_HALF_CYCLES(2),.POWER_ON_CYCLES(4)) dut(
        .sys_clk(clk),.sys_rst_n(1'b1),.lcd_rst_n(res),.lcd_cs_n(cs),
        .lcd_sck(sck),.lcd_dc(dc),.lcd_mosi(sda),.lcd_bl(bl));
    always @(negedge dut.app_rst_n) begin byte_count=0;res_release=0;sleep_end=0;end
    always @(posedge res) if(dut.app_rst_n) res_release=$time;
    always @(posedge sck) if(dut.app_rst_n && byte_count==0)
        if($time-res_release<3000) $fatal(1,"Default sends Sleep Out before 150 ms wait");
    always @(posedge cs) if(dut.app_rst_n) begin
        if(byte_count==0)sleep_end=$time;
        byte_count=byte_count+1;
    end
    always @(negedge cs) if(dut.app_rst_n && byte_count==1)
        if($time-sleep_end<3000) $fatal(1,"Default continues before 150 ms Sleep Out wait");
    initial begin
        #1000000 $fatal(1,"Debug restart timeout");
    end
    initial begin
        wait(dut.lcd_init_done);
        @(negedge clk);
        before_ticks=dut.debug_ticks;before_events=dut.u_lcd_ila.events;
        dut.u_lcd_vio.probe_out0=1;
        repeat(5) @(negedge clk);
        if(dut.app_rst_n!==0 || dut.lcd_init_done!==0 || {res,cs,sck,dc,sda,bl}!==0)
            $fatal(1,"VIO restart did not reset STM32 profile");
        if(dut.debug_ticks<=before_ticks) $fatal(1,"Capture timestamp stopped during restart");
        dut.u_lcd_vio.probe_out0=0;
        wait(dut.lcd_init_done);
        @(negedge clk);
        if(dut.read_busy!==0) $fatal(1,"Passive debug unexpectedly reads panel");
        if(dut.u_lcd_ila.events<=before_events+100) $fatal(1,"Event observer did not capture init");
        $display("PASS: DEBUG passive capture, timestamp, VIO restart, no panel read, corrected 150ms waits");
        $finish;
    end
endmodule
