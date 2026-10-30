// ALIENTEK Navigator ZYNQ7010, standalone PL-only LCD test.
// Physical connections are in constraints/linhangz_7010_st7735s.xdc.
module st7735s_top #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SPI_HALF_CYCLES = 100,
    parameter integer INIT_PROFILE = 2,
    parameter integer X_OFFSET = (INIT_PROFILE==0)?0:2,
    parameter integer Y_OFFSET = (INIT_PROFILE==0)?32:3,
    parameter [7:0] MADCTL = 8'hC8,
    parameter integer POWER_ON_CYCLES = 65536,
    parameter integer READBACK_ENABLE = 0,
    parameter integer DISPLAY_TEXT = 1
) (
    input wire sys_clk,
    input wire sys_rst_n,
    output wire lcd_rst_n,
    output wire lcd_cs_n,
    output wire lcd_sck,
    output wire lcd_dc,
    inout wire lcd_mosi,
    output wire lcd_bl
);
    // INIT values also hold reset after FPGA configuration when the external
    // reset button has not been pressed. External reset asserts asynchronously;
    // the two-flop chain releases the application reset on clock edges.
    reg [31:0] power_count = 32'd0;
    reg power_ready = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync = 2'b00;
`ifdef LCD_DEBUG
    wire debug_hold_reset;
    wire app_rst_n = reset_sync[1] && !debug_hold_reset;
`else
    wire app_rst_n = reset_sync[1];
`endif
    wire write_rst_n,write_cs_n,write_sck,write_dc,write_mosi,write_bl;
    wire lcd_init_done,read_busy,read_done,read_cs_n,read_sck,read_dc;
    wire read_sda_out,read_sda_hiz,sda_in;
    wire [2:0] pad_flags;
    wire [31:0] raw_id,raw_power,raw_madctl,raw_colmod;
    assign lcd_rst_n=write_rst_n;
    assign lcd_bl=write_bl;
    assign lcd_cs_n=read_busy?read_cs_n:write_cs_n;
    assign lcd_sck=read_busy?read_sck:write_sck;
    assign lcd_dc=read_busy?read_dc:write_dc;
    IOBUF sda_buffer(.I(read_busy?read_sda_out:write_mosi),
        .T(read_busy && read_sda_hiz),.O(sda_in),.IO(lcd_mosi));

    st7735s_readback u_readback(
        .clk(sys_clk),.rst_n(app_rst_n),
        .start((READBACK_ENABLE!=0) && lcd_init_done),.sda_in(sda_in),
        .busy(read_busy),.done(read_done),.cs_n(read_cs_n),.sck(read_sck),
        .dc(read_dc),.sda_out(read_sda_out),.sda_hiz(read_sda_hiz),
        .pad_flags(pad_flags),.raw_id(raw_id),.raw_power(raw_power),
        .raw_madctl(raw_madctl),.raw_colmod(raw_colmod)
    );

`ifdef LCD_DEBUG
    // Passive event capture: this observes the existing outputs, never sends
    // a panel read. The VIO output can restart this same initializer remotely.
    wire [7:0] debug_bus={app_rst_n,sys_rst_n,lcd_bl,lcd_rst_n,lcd_cs_n,lcd_dc,sda_in,lcd_sck};
    reg [7:0] debug_previous=0;
    reg [31:0] debug_ticks=0;
    wire debug_event=(debug_bus!=debug_previous);
    always @(posedge sys_clk) begin
        debug_previous<=debug_bus;
        debug_ticks<=debug_ticks+1'b1;
    end
    wire [7:0] debug_status={(READBACK_ENABLE!=0),app_rst_n,lcd_init_done,
        read_done,read_busy,pad_flags};
    lcd_ila u_lcd_ila(.clk(sys_clk),
        .probe0(debug_bus),.probe1(debug_ticks),.probe2(debug_event));
    lcd_vio u_lcd_vio(.clk(sys_clk),.probe_in0(raw_id),.probe_in1(raw_power),
        .probe_in2(raw_madctl),.probe_in3(raw_colmod),.probe_in4(debug_status),
        .probe_out0(debug_hold_reset));
`endif

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            power_count <= 32'd0;
            power_ready <= 1'b0;
        end else if (!power_ready) begin
            if (power_count == POWER_ON_CYCLES - 1) begin
                power_ready <= 1'b1;
            end else power_count <= power_count + 32'd1;
        end
    end

    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) reset_sync <= 2'b00;
        else reset_sync <= {reset_sync[0], power_ready};
    end

    generate if(DISPLAY_TEXT!=0) begin:g_text
    st7735s_text_demo #(
        .CLK_HZ(CLK_HZ),.SPI_HALF_CYCLES(SPI_HALF_CYCLES),.INIT_PROFILE(INIT_PROFILE),
        .X_OFFSET(X_OFFSET),.Y_OFFSET(Y_OFFSET),.MADCTL(MADCTL)) u_text(
        .clk_50m(sys_clk),.rst_n(app_rst_n),
        .pause_requests((READBACK_ENABLE!=0) && !read_done),.lcd_init_done(lcd_init_done),.frame_done(),
        .lcd_rst_n(write_rst_n),.lcd_cs_n(write_cs_n),.lcd_sck(write_sck),
        .lcd_dc(write_dc),.lcd_mosi(write_mosi),.lcd_bl(write_bl));
    end else begin:g_color
    st7735s_demo #(
        .CLK_HZ(CLK_HZ), .SPI_HALF_CYCLES(SPI_HALF_CYCLES), .INIT_PROFILE(INIT_PROFILE),
        .X_OFFSET(X_OFFSET), .Y_OFFSET(Y_OFFSET), .MADCTL(MADCTL)
    ) u_demo (
        .clk_50m(sys_clk), .rst_n(app_rst_n),
        .pause_requests((READBACK_ENABLE!=0) && !read_done),.lcd_init_done(lcd_init_done),
        .lcd_rst_n(write_rst_n), .lcd_cs_n(write_cs_n),
        .lcd_sck(write_sck), .lcd_dc(write_dc),
        .lcd_mosi(write_mosi), .lcd_bl(write_bl)
    );
    end endgenerate
endmodule
