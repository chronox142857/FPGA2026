`timescale 1ns/1ps
// Decode at the serial pins, independently from driver state/ROM internals.
module tb_st7735s_slow;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0, req_valid=0;
    reg [7:0] row=0;
    wire ready, done, error, initialized, busy;
    wire res, cs, sck, dc, mosi, bl;
    reg [8:0] golden[0:77];
    reg [8:0] received[0:611];
    integer lengths[0:45];
    integer bytes=0, packets=0, packet_bytes=0, bits=0, i, j, first, expected;
    reg packet_dc=0;
    reg [7:0] shift_byte=0;
    time reset_start=0, reset_release=0, start_time=0;
    time cs_fall=0, cs_rise=0, clock_rise=0, clock_fall=0;
    time madctl_end=0, sleep_end=0, display_end=0;

    // Only millisecond waits are accelerated (50x); serial bit timing is real.
    st7735s_driver #(.INIT_PROFILE(1), .CLK_HZ(1000000),
        .SPI_HALF_CYCLES(100), .X_OFFSET(2), .Y_OFFSET(3),
        .RESET_PREP_MS(2), .RESET_LOW_MS(2), .RESET_RECOVERY_MS(2),
        .REGISTER_SETTLE_MS(3), .SLEEP_OUT_MS(3), .DISPLAY_ON_MS(2)) dut (
        .clk(clk), .rst_n(rst_n), .bl_enable(1'b1),
        .req_valid(req_valid), .req_ready(ready),
        .x0(8'd0), .x1(8'd127), .y0(row), .y1(row), .color(16'hF800),
        .raw_valid(1'b0), .raw_ready(), .raw_dc(1'b0), .raw_data(8'd0), .raw_done(),
        .init_done(initialized), .req_done(done), .req_error(error), .busy(busy),
        .lcd_rst_n(res), .lcd_cs_n(cs), .lcd_sck(sck), .lcd_dc(dc),
        .lcd_mosi(mosi), .lcd_bl(bl));

    always @(negedge res) if(rst_n) begin
        if($time-start_time != 39990) $fatal(1,"Reset high preparation changed");
        reset_start=$time;
    end
    always @(posedge res) if(rst_n) begin
        if($time-reset_start != 40000) $fatal(1,"Reset low duration changed");
        reset_release=$time;
    end
    always @(negedge cs) if(rst_n) begin
        if(bytes==0 && $time-reset_release<40000) $fatal(1,"Reset recovery too short");
        if(cs_rise!=0 && $time-cs_rise<2000) $fatal(1,"CS high too short");
        if(bytes==76 && $time-madctl_end<60000) $fatal(1,"Register settle too short");
        if(bytes==77 && $time-sleep_end<60000) $fatal(1,"Sleep Out delay too short");
        packet_dc=dc;packet_bytes=0;bits=0;cs_fall=$time;clock_rise=0;clock_fall=0;
    end
    always @(posedge sck) if(!cs && rst_n) begin
        if(dc!==packet_dc) $fatal(1,"DC changed while selected");
        if(clock_rise==0 && $time-cs_fall<4000) $fatal(1,"First bit setup too short");
        if(clock_fall!=0 && $time-clock_fall<4000) $fatal(1,"SCK low too short");
        if(bits!=0 && clock_rise!=0 && $time-clock_rise!=6000)
            $fatal(1,"SCK bit period differs from slow GPIO delays");
        clock_rise=$time;
        shift_byte={shift_byte[6:0],mosi};bits=bits+1;
        if(bits==8) begin
            received[bytes]={packet_dc,shift_byte};bytes=bytes+1;
            packet_bytes=packet_bytes+1;bits=0;
        end
    end
    always @(negedge sck) if(!cs && rst_n && clock_rise!=0) begin
        if($time-clock_rise!=2000) $fatal(1,"SCK high differs from slow GPIO delay");
        clock_fall=$time;
    end
    always @(posedge cs) if(rst_n) begin
        if(bits!=0 || packet_bytes==0) $fatal(1,"Truncated/empty packet");
        if($time-clock_fall<2000) $fatal(1,"CS hold too short");
        lengths[packets]=packet_bytes;packets=packets+1;cs_rise=$time;
        if(bytes==76) madctl_end=$time;
        if(bytes==77) sleep_end=$time;
        if(bytes==78) display_end=$time;
    end
    task expect_byte;
        input integer n;
        input [8:0] value;
        begin
            if(received[n]!==value) $fatal(1,"byte %0d got %03h expected %03h",n,received[n],value);
        end
    endtask
    task request_row;
        input [7:0] y;
        begin
            @(negedge clk);while(!ready) @(negedge clk);
            row=y;req_valid=1;
            @(negedge clk);req_valid=0;
            while(!done) @(negedge clk);
            if(error) $fatal(1,"Row fill rejected");
        end
    endtask
    initial begin
        #35000000 $fatal(1,"Slow-profile simulation timeout");
    end
    initial begin
        $readmemh("slow_gpio_init.hex",golden);
        repeat(3) @(negedge clk);
        rst_n=1;start_time=$time;
        wait(initialized);#1;
        if($time-display_end<40000) $fatal(1,"Display On delay too short");
        if(bl!==1) $fatal(1,"Backlight not enabled after init");
        if(bytes!=78 || packets!=34) $fatal(1,"Init byte/packet count %0d/%0d",bytes,packets);
        for(i=0;i<78;i=i+1) expect_byte(i,golden[i]);
        j=0;i=0;
        while(i<78) begin
            if(lengths[j]!=1 || golden[i][8]!=0) $fatal(1,"Command packet mismatch");
            j=j+1;i=i+1;expected=0;
            while(i<78 && golden[i][8]==1) begin expected=expected+1;i=i+1;end
            if(expected!=0) begin
                if(lengths[j]!=expected) $fatal(1,"Parameter packet length mismatch");
                j=j+1;
            end
        end
        request_row(0);
        request_row(127);
        if(bytes!=612 || packets!=46) $fatal(1,"Row byte/packet count %0d/%0d",bytes,packets);
        for(j=0;j<2;j=j+1) begin
            first=78+267*j;
            expect_byte(first,9'h02a);expect_byte(first+1,9'h100);
            expect_byte(first+2,9'h102);expect_byte(first+3,9'h100);expect_byte(first+4,9'h181);
            expect_byte(first+5,9'h02b);expect_byte(first+6,9'h100);
            expect_byte(first+7,j==0?9'h103:9'h182);
            expect_byte(first+8,9'h100);expect_byte(first+9,j==0?9'h103:9'h182);
            expect_byte(first+10,9'h02c);
            for(i=0;i<128;i=i+1) begin
                expect_byte(first+11+2*i,9'h1f8);expect_byte(first+12+2*i,9'h100);
            end
            if(lengths[34+6*j]!=1 || lengths[35+6*j]!=4 || lengths[36+6*j]!=1 ||
               lengths[37+6*j]!=4 || lengths[38+6*j]!=1 || lengths[39+6*j]!=256)
                $fatal(1,"Row CS packet lengths mismatch");
        end
        $display("PASS: SLOW GPIO profile: reset phases, 78 bytes, delays, burst CS, serial timing, first/last row and RGB565");
        $finish;
    end
endmodule
