// Text-only screen check using the existing tested rectangle interface.
// Labels deliberately identify this as a display test, not a running capture.
module st7735s_text_demo #(
    parameter integer CLK_HZ=50000000,
    parameter integer SPI_HALF_CYCLES=100,
    parameter integer INIT_PROFILE=2,
    parameter integer X_OFFSET=2,
    parameter integer Y_OFFSET=3,
    parameter [7:0] MADCTL=8'hc8
)(
    input wire clk_50m,rst_n,pause_requests,
    output wire lcd_init_done,
    output reg frame_done,
    output wire lcd_rst_n,lcd_cs_n,lcd_sck,lcd_dc,lcd_mosi,lcd_bl
);
    localparam [2:0] WAIT_INIT=0,CLEAR_REQ=1,CLEAR_WAIT=2,
                     SCAN=3,DRAW_WAIT=4,ADVANCE=5,HOLD=6;
    reg [2:0] state;
    reg [2:0] line_index,row,column;
    reg [4:0] character_index;
    wire init_done,ready,done,error;
    wire [159:0] label=line_text(line_index);
    wire [7:0] character=label[159-character_index*8 -: 8];
    wire ink;
    wire clearing=(state==CLEAR_REQ);
    wire [7:0] draw_x=8'd4+character_index*6+column;
    wire [7:0] draw_y={1'b0,line_index,4'b0000}+row;
    assign lcd_init_done=init_done;
    st7735s_font5x7 u_font(.character(character),.row(row),.column(column),.ink(ink));
    st7735s_driver #(.CLK_HZ(CLK_HZ),.SPI_HALF_CYCLES(SPI_HALF_CYCLES),
        .INIT_PROFILE(INIT_PROFILE),.X_OFFSET(X_OFFSET),.Y_OFFSET(Y_OFFSET),.MADCTL(MADCTL)) u_lcd(
        .clk(clk_50m),.rst_n(rst_n),.bl_enable(1'b1),
        .req_valid((clearing || (state==SCAN && ink)) && !pause_requests),.req_ready(ready),
        .x0(clearing?8'd0:draw_x),.x1(clearing?8'd127:draw_x),
        .y0(clearing?8'd0:draw_y),.y1(clearing?8'd127:draw_y),
        .color(clearing?16'h0000:line_color(line_index)),
        .raw_valid(1'b0),.raw_ready(),.raw_dc(1'b0),.raw_data(8'd0),.raw_done(),
        .init_done(init_done),.req_done(done),.req_error(error),.busy(),
        .lcd_rst_n(lcd_rst_n),.lcd_cs_n(lcd_cs_n),.lcd_sck(lcd_sck),
        .lcd_dc(lcd_dc),.lcd_mosi(lcd_mosi),.lcd_bl(lcd_bl));
    always @(posedge clk_50m or negedge rst_n) begin
        if(!rst_n) begin
            state<=WAIT_INIT;line_index<=0;row<=0;column<=0;
            character_index<=0;frame_done<=0;
        end else begin
            case(state)
                WAIT_INIT: if(init_done) state<=CLEAR_REQ;
                CLEAR_REQ: if(ready && !pause_requests) state<=CLEAR_WAIT;
                CLEAR_WAIT: if(done) state<=SCAN;
                SCAN: if(!ink) state<=ADVANCE;
                      else if(ready && !pause_requests) state<=DRAW_WAIT;
                DRAW_WAIT: if(done) state<=ADVANCE;
                ADVANCE: begin
                    state<=SCAN;
                    if(column!=4) column<=column+1'b1;
                    else begin
                        column<=0;
                        if(row!=6) row<=row+1'b1;
                        else begin
                            row<=0;
                            if(character_index!=19) character_index<=character_index+1'b1;
                            else begin
                                character_index<=0;
                                if(line_index!=7) line_index<=line_index+1'b1;
                                else begin state<=HOLD;frame_done<=1;end
                            end
                        end
                    end
                end
                HOLD: state<=HOLD;
                default: state<=WAIT_INIT;
            endcase
        end
    end
    function [15:0] line_color;
        input [2:0] n;
        begin
            case(n)
                0,4: line_color=16'h07ff;
                1: line_color=16'h07e0;
                3: line_color=16'hffe0;
                6: line_color=16'h8410;
                default: line_color=16'hffff;
            endcase
        end
    endfunction
    // 20 cells per row; text occupies five columns plus one column spacing.
    function [159:0] line_text;
        input [2:0] n;
        begin
            case(n)
                0: line_text="LOGIC ANALYZER      ";
                1: line_text="SCREEN READY        ";
                2: line_text="FPGA ZYNQ7010       ";
                3: line_text="UART I2C SPI        ";
                4: line_text="CH 0 1 2 3 4 5 6 7  ";
                5: line_text="DISPLAY TEST        ";
                6: line_text="CAPTURE OFF         ";
                7: line_text="0123456789ABCDEF    ";
                default: line_text=0;
            endcase
        end
    endfunction
endmodule
