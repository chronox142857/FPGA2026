`timescale 1ns/1ps
// Board adapter: automatic startup without pressing reset, 1 MHz SCK,
// then button reset during a transaction and a fresh initialization.
module tb_st7735s_top;
    reg clk = 1'b0;
    always #10 clk = ~clk;
    reg rst_n = 1'b1;
    wire lcd_rst_n,lcd_cs_n,lcd_sck,lcd_dc,lcd_mosi,lcd_bl;
    integer count = 0, bit_count = 0;
    reg [7:0] serial = 8'd0;
    reg dc;
    reg [8:0] words [0:20];
    time last_rise = 0;

    st7735s_top #(.CLK_HZ(1000), .POWER_ON_CYCLES(4), .INIT_PROFILE(0), .DISPLAY_TEXT(0),
        .SPI_HALF_CYCLES(25), .X_OFFSET(0), .Y_OFFSET(32)) dut (
        .sys_clk(clk), .sys_rst_n(rst_n),
        .lcd_rst_n(lcd_rst_n), .lcd_cs_n(lcd_cs_n),
        .lcd_sck(lcd_sck), .lcd_dc(lcd_dc),
        .lcd_mosi(lcd_mosi), .lcd_bl(lcd_bl)
    );

    always @(negedge lcd_cs_n) begin
        bit_count=0;serial=0;dc=lcd_dc;last_rise=0;
    end
    always @(posedge lcd_sck) if (!lcd_cs_n && rst_n) begin
        if (last_rise != 0 && $time-last_rise != 1000)
            $fatal(1,"Board SCK is not 1 MHz");
        last_rise=$time;
        if(lcd_dc !== dc) $fatal(1,"Board DC changed within byte");
        serial={serial[6:0],lcd_mosi};bit_count=bit_count+1;
    end
    always @(posedge lcd_cs_n) if (rst_n && lcd_rst_n && bit_count != 0) begin
        if(bit_count != 8) $fatal(1,"Board byte framing");
        words[count]={dc,serial};count=count+1;
    end

    initial begin
        #2000000 $fatal(1,"Board adapter test timeout");
    end
    initial begin
        #1;
        if(lcd_rst_n !== 0 || lcd_bl !== 0)
            $fatal(1,"Power-on reset/backlight state");
        wait(count==3);
        if(words[0] !== 9'h011 || words[1] !== 9'h0B1 || words[2] !== 9'h102)
            $fatal(1,"Automatic startup initialization");
        // Interrupt the next serial byte, including asynchronous assertion.
        wait(!lcd_cs_n && lcd_sck);
        @(negedge clk);rst_n=0;
        #1;
        if(lcd_rst_n !== 0 || lcd_bl !== 0 || lcd_cs_n !== 1 || lcd_sck !== 0)
            $fatal(1,"External reset did not stop/clear outputs");
        repeat(3) @(negedge clk);
        count=0;bit_count=0;rst_n=1;
        wait(count==1);
        if(words[0] !== 9'h011) $fatal(1,"Reset did not restart initialization");
        if(lcd_bl !== 0) $fatal(1,"Backlight turned on before first full frame");
        $display("PASS: BOARD startup, 1 MHz SPI and external reset restart");
        $finish;
    end
endmodule
