// 50 MHz PL example: profiles 0/1 cycle RGB; STM32 profile 2 adds black/white.
// Replace the request generator with your own logic when using the driver.
module st7735s_demo #(
    parameter integer CLK_HZ = 50000000,
    parameter integer SPI_HALF_CYCLES = 100,
    parameter integer INIT_PROFILE = 2,
    parameter integer X_OFFSET = (INIT_PROFILE==0)?0:2,
    parameter integer Y_OFFSET = (INIT_PROFILE==0)?32:3,
    parameter [7:0] MADCTL = 8'hC8
) (
    input  wire clk_50m,
    input  wire rst_n,
    input  wire pause_requests,
    output wire lcd_init_done,
    output wire lcd_rst_n,
    output wire lcd_cs_n,
    output wire lcd_sck,
    output wire lcd_dc,
    output wire lcd_mosi,
    output wire lcd_bl
);
    localparam [1:0] WAIT_INIT = 2'd0, REQUEST = 2'd1,
                     WAIT_DONE = 2'd2, PAUSE = 2'd3;
    reg [1:0] state;
    reg [2:0] color_index;
    reg [25:0] delay_count;
    reg bl_enable;
    reg [6:0] row_index;
    wire init_done, req_ready, req_done, req_error, busy;
    assign lcd_init_done = init_done;
    wire [15:0] color = (color_index == 0) ? 16'hF800 :
                        (color_index == 1) ? 16'h07E0 :
                        (color_index == 2) ? 16'h001F :
                        (color_index == 3) ? 16'h0000 : 16'hFFFF;

    st7735s_driver #(
        .CLK_HZ(CLK_HZ), .SPI_HALF_CYCLES(SPI_HALF_CYCLES), .INIT_PROFILE(INIT_PROFILE),
        .X_OFFSET(X_OFFSET), .Y_OFFSET(Y_OFFSET), .MADCTL(MADCTL)
    ) u_lcd (
        .clk(clk_50m), .rst_n(rst_n), .bl_enable(bl_enable),
        .req_valid((state == REQUEST) && !pause_requests), .req_ready(req_ready),
        .x0(8'd0), .y0((INIT_PROFILE==1)?{1'b0,row_index}:8'd0),
        .x1(8'd127), .y1((INIT_PROFILE==1)?{1'b0,row_index}:8'd127),
        .color(color), .raw_valid(1'b0), .raw_ready(),
        .raw_dc(1'b0), .raw_data(8'd0), .raw_done(),
        .init_done(init_done),
        .req_done(req_done), .req_error(req_error), .busy(busy),
        .lcd_rst_n(lcd_rst_n), .lcd_cs_n(lcd_cs_n),
        .lcd_sck(lcd_sck), .lcd_dc(lcd_dc),
        .lcd_mosi(lcd_mosi), .lcd_bl(lcd_bl)
    );

    always @(posedge clk_50m or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT_INIT;
            color_index <= 3'd0;
            delay_count <= 26'd0;
            bl_enable <= (INIT_PROFILE!=0);
            row_index <= 0;
        end else begin
            case (state)
                WAIT_INIT: if (init_done) state <= REQUEST;
                REQUEST: if (req_ready && !pause_requests) state <= WAIT_DONE;
                WAIT_DONE: if (req_done) begin
                    // Profile 0 enables BL after the first frame; profiles 1/2
                    // enable it after initialization, as in their C sources.
                    bl_enable <= 1'b1;
                    if(INIT_PROFILE==1 && row_index!=127) begin
                        row_index<=row_index+1'b1;state<=REQUEST;
                    end else begin
                        row_index<=0;delay_count <= 26'd0;state <= PAUSE;
                    end
                end
                PAUSE: if (delay_count == ((INIT_PROFILE==2)?CLK_HZ/2:CLK_HZ) - 1) begin
                    delay_count <= 26'd0;
                    color_index <= (color_index == ((INIT_PROFILE==2)?4:2)) ? 3'd0 :
                                   color_index + 3'd1;
                    state <= REQUEST;
                end else delay_count <= delay_count + 26'd1;
                default: state <= WAIT_INIT;
            endcase
        end
    end
endmodule
