`timescale 1ns/1ps
// Compare every emitted byte with actual execution of the unchanged STM32 C.
module tb_st7735s_stm32;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0, request=0;
    wire ready, done, error, initialized, busy, res, cs, sck, dc, mosi, bl;
    reg [8:0] golden[0:32855];
    reg [7:0] shift_byte=0;
    reg byte_dc=0;
    integer bytes=0, bits=0, falls=0;
    time low_start=0, res_released=0, sleep_end=0, rise_time=0, fall_time=0, cs_time=0;
    st7735s_driver #(.INIT_PROFILE(2), .CLK_HZ(1000),
        .SPI_HALF_CYCLES(2), .X_OFFSET(0), .Y_OFFSET(32),
        // Explicitly retain the original C timing for this reference test.
        // Board defaults use corrected 150 ms waits, tested in debug bench.
        .RESET_RECOVERY_MS(50), .SLEEP_OUT_MS(50)) dut (
        .clk(clk), .rst_n(rst_n), .bl_enable(1'b1),
        .req_valid(request), .req_ready(ready),
        .x0(8'd0), .x1(8'd127), .y0(8'd0), .y1(8'd127), .color(16'hf800),
        .raw_valid(1'b0), .raw_ready(), .raw_dc(1'b0), .raw_data(8'd0), .raw_done(),
        .init_done(initialized), .req_done(done), .req_error(error), .busy(busy),
        .lcd_rst_n(res), .lcd_cs_n(cs), .lcd_sck(sck), .lcd_dc(dc), .lcd_mosi(mosi), .lcd_bl(bl));
    always @(posedge res) if(rst_n) begin
        if($time-low_start!=1990) $fatal(1,"STM32 reset-low delay differs");
        res_released=$time;
    end
    always @(negedge cs) if(rst_n) begin
        if(bytes==0 && $time-res_released<1000) $fatal(1,"Reset recovery too short");
        if(bytes==1 && $time-sleep_end<1000) $fatal(1,"Sleep Out delay too short");
        if(bytes>0 && sck!==1) $fatal(1,"SCK not held high between bytes");
        bits=0;falls=0;byte_dc=dc;cs_time=$time;
    end
    always @(posedge sck) if(!cs && rst_n) begin
        if(bytes==0 && bits==0) begin
            byte_dc=dc;
            if($time-res_released<1000) $fatal(1,"First-byte recovery too short");
        end
        if(dc!==byte_dc) $fatal(1,"DC changed during byte");
        if(fall_time!=0 && $time-fall_time<40) $fatal(1,"SCK low too short");
        rise_time=$time;shift_byte={shift_byte[6:0],mosi};bits=bits+1;
    end
    always @(negedge sck) if(!cs && rst_n) begin
        if(bits>0 && $time-rise_time<40) $fatal(1,"SCK high too short");
        fall_time=$time;falls=falls+1;
    end
    always @(posedge cs) if(rst_n) begin
        if(bits!=8 || sck!==1) $fatal(1,"Byte end differs: bits=%0d sck=%b",bits,sck);
        if(falls!=(bytes==0?7:8)) $fatal(1,"Wrong SCK falling edge count");
        if({byte_dc,shift_byte}!==golden[bytes])
            $fatal(1,"STM32 byte %0d got %03h expected %03h",bytes,{byte_dc,shift_byte},golden[bytes]);
        bytes=bytes+1;
        if(bytes==1)sleep_end=$time;
    end
    initial begin
        #40000000 $fatal(1,"STM32-profile simulation timeout");
    end
    initial begin
        $readmemh("stm32_wire_stream.hex",golden);
        repeat(3) @(negedge clk);
        if({cs,sck,dc,mosi,bl,res}!==6'b000000) $fatal(1,"STM32 GPIO startup levels differ");
        rst_n=1;low_start=$time;
        wait(initialized);#1;
        if(bytes!=77 || bl!==1) $fatal(1,"Init count/backlight mismatch");
        @(negedge clk);request=1;
        @(negedge clk);request=0;
        while(!done) @(negedge clk);
        if(error || bytes!=32856) $fatal(1,"Full-frame mismatch");
        $display("PASS: STM32 original: every init/frame byte, reset/delays, per-byte CS, SCK-high ending, RGB565 and window");
        $finish;
    end
endmodule
