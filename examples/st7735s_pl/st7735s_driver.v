// Synthesizable ST7735S driver for a 128x128 SPI TFT.
// Coordinates are logical 0..127. A request fills an inclusive rectangle;
// x0=x1 and y0=y1 draws one pixel. Color is RGB565 (R[15:11], G[10:5], B[4:0]).
module st7735s_driver #(
    parameter integer INIT_PROFILE = 0,
    parameter integer CLK_HZ = 50000000,
    parameter integer SPI_HALF_CYCLES = 2,
    parameter integer X_OFFSET = 0,
    parameter integer Y_OFFSET = 32,
    parameter [7:0] MADCTL = 8'hC8,
    parameter integer BL_ACTIVE_HIGH = 1,
    parameter integer RESET_LOW_MS = 100,
    // ST7735S 9.17/10.1.8 require 120 ms before/after Sleep Out.
    // Profile 2 keeps STM32 byte ordering, with corrected conservative waits.
    parameter integer RESET_RECOVERY_MS = (INIT_PROFILE == 1) ? 100 : 150,
    parameter integer SLEEP_OUT_MS = (INIT_PROFILE == 1) ? 120 : 150,
    parameter integer RESET_PREP_MS = 100,
    parameter integer REGISTER_SETTLE_MS = 100,
    parameter integer DISPLAY_ON_MS = 20
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        bl_enable,
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [7:0]  x0,
    input  wire [7:0]  y0,
    input  wire [7:0]  x1,
    input  wire [7:0]  y1,
    input  wire [15:0] color,
    input  wire        raw_valid,
    output wire        raw_ready,
    input  wire        raw_dc,
    input  wire [7:0]  raw_data,
    output reg         raw_done,
    output reg         init_done,
    output reg         req_done,
    output reg         req_error,
    output wire        busy,
    output reg         lcd_rst_n,
    output wire        lcd_cs_n,
    output wire        lcd_sck,
    output wire        lcd_dc,
    output wire        lcd_mosi,
    output wire        lcd_bl
);
    localparam integer LOW_CYCLES = (CLK_HZ / 1000) * RESET_LOW_MS;
    localparam integer RECOVERY_CYCLES = (CLK_HZ / 1000) * RESET_RECOVERY_MS;
    localparam integer SLEEP_CYCLES = (CLK_HZ / 1000) * SLEEP_OUT_MS;
    localparam integer PREP_CYCLES = (CLK_HZ / 1000) * RESET_PREP_MS;
    localparam integer SETTLE_CYCLES = (CLK_HZ / 1000) * REGISTER_SETTLE_MS;
    localparam integer ON_CYCLES = (CLK_HZ / 1000) * DISPLAY_ON_MS;
    localparam [6:0] LAST_INIT = (INIT_PROFILE == 1) ? 7'd77 : (INIT_PROFILE == 2) ? 7'd76 : 7'd73;
    localparam [3:0] RESET_LOW = 4'd0, RESET_RECOVERY = 4'd1,
                     INIT_SEND = 4'd2, INIT_WAIT = 4'd3,
                     INIT_SLEEP = 4'd4, IDLE = 4'd5,
                     OP_SEND = 4'd6, OP_WAIT = 4'd7,
                     RAW_SEND = 4'd8, RAW_WAIT = 4'd9,
                     RESET_PREP = 4'd10, INIT_SETTLE = 4'd11,
                     INIT_ON = 4'd12;
    reg [3:0] state;
    reg [31:0] wait_count;
    reg [6:0] init_index;
    reg [3:0] op_index;
    reg [15:0] xs, xe, ys, ye;
    reg [15:0] saved_color;
    reg [14:0] pixels_left; // 128 * 128 = 16384, fits in 15 bits.
    reg [8:0] raw_word;
    wire spi_ready;
    wire spi_valid;
    wire spi_dc;
    wire [7:0] spi_data;
    wire [8:0] init_word;
    wire [8:0] next_init_word;
    wire spi_last;
    reg [8:0] op_word;

    assign req_ready = init_done && (state == IDLE);
    // Rectangle requests take priority when both valid inputs are asserted.
    assign raw_ready = init_done && (state == IDLE) && !req_valid;
    assign busy = !req_ready;
    assign lcd_bl = BL_ACTIVE_HIGH ? (init_done && bl_enable) :
                                        !(init_done && bl_enable);
    assign spi_valid = (state == INIT_SEND) || (state == OP_SEND) ||
                       (state == RAW_SEND);
    // Profile 2 reproduces the supplied STM32 C, including its extra B3 bytes.
    assign init_word = (INIT_PROFILE == 1) ? init_rom_slow(init_index) :
        (INIT_PROFILE == 2 && init_index>=16 && init_index<=18) ?
            ((init_index==16)?9'h102:(init_index==17)?9'h135:9'h136) :
        init_rom((INIT_PROFILE==2 && init_index>=19)?init_index-7'd3:init_index);
    assign next_init_word = init_rom_slow(init_index+7'd1);
    assign spi_last = (INIT_PROFILE != 1) ? 1'b1 :
        (state == INIT_SEND) ? (!init_word[8] || init_index==LAST_INIT || !next_init_word[8]) :
        (state == RAW_SEND) ? 1'b1 :
        (op_index==0 || op_index==4 || op_index==5 || op_index==9 ||
         op_index==10 || (op_index==12 && pixels_left==1));
    assign spi_dc = (state == INIT_SEND) ? init_word[8] :
                    (state == RAW_SEND) ? raw_word[8] : op_word[8];
    assign spi_data = (state == INIT_SEND) ? init_word[7:0] :
                      (state == RAW_SEND) ? raw_word[7:0] : op_word[7:0];

    st7735s_spi_byte #(.HALF_CYCLES(SPI_HALF_CYCLES),
        .LOW_CYCLES((INIT_PROFILE==1)?2*SPI_HALF_CYCLES:SPI_HALF_CYCLES),
        .CS_IDLE_CYCLES((INIT_PROFILE!=0)?SPI_HALF_CYCLES:1),
        .CS_SETUP_CYCLES((INIT_PROFILE==1)?1:3),
        .CS_HOLD_CYCLES((INIT_PROFILE!=0)?SPI_HALF_CYCLES:3),
        .END_CLOCK_HIGH(INIT_PROFILE==2)) u_spi (
        .clk(clk), .rst_n(rst_n), .tx_valid(spi_valid),
        .tx_ready(spi_ready), .tx_dc(spi_dc), .tx_data(spi_data), .tx_last(spi_last),
        .lcd_cs_n(lcd_cs_n), .lcd_sck(lcd_sck),
        .lcd_dc(lcd_dc), .lcd_mosi(lcd_mosi)
    );

    // 0x2A CASET, 0x2B RASET, 0x2C RAMWR, then RGB565 high byte first.
    always @* begin
        case (op_index)
            4'd0:  op_word = {1'b0, 8'h2A};
            4'd1:  op_word = {1'b1, xs[15:8]};
            4'd2:  op_word = {1'b1, xs[7:0]};
            4'd3:  op_word = {1'b1, xe[15:8]};
            4'd4:  op_word = {1'b1, xe[7:0]};
            4'd5:  op_word = {1'b0, 8'h2B};
            4'd6:  op_word = {1'b1, ys[15:8]};
            4'd7:  op_word = {1'b1, ys[7:0]};
            4'd8:  op_word = {1'b1, ye[15:8]};
            4'd9:  op_word = {1'b1, ye[7:0]};
            4'd10: op_word = {1'b0, 8'h2C};
            4'd11: op_word = {1'b1, saved_color[15:8]};
            4'd12: op_word = {1'b1, saved_color[7:0]};
            default: op_word = 9'd0;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= (INIT_PROFILE==1)?RESET_PREP:RESET_LOW;
            wait_count <= 32'd0;
            init_index <= 7'd0;
            op_index <= 4'd0;
            xs <= 16'd0; xe <= 16'd0;
            ys <= 16'd0; ye <= 16'd0;
            saved_color <= 16'd0;
            pixels_left <= 15'd0;
            raw_word <= 9'd0;
            raw_done <= 1'b0;
            init_done <= 1'b0;
            req_done <= 1'b0;
            req_error <= 1'b0;
            lcd_rst_n <= (INIT_PROFILE==1);
        end else begin
            raw_done <= 1'b0;
            req_done <= 1'b0;
            req_error <= 1'b0;
            case (state)
                RESET_PREP: begin
                    lcd_rst_n <= 1'b1;
                    if(wait_count == PREP_CYCLES-1) begin
                        wait_count<=0;lcd_rst_n<=0;state<=RESET_LOW;
                    end else wait_count<=wait_count+1'b1;
                end
                RESET_LOW: begin
                    lcd_rst_n <= 1'b0;
                    if (wait_count == LOW_CYCLES - 1) begin
                        wait_count <= 32'd0;
                        lcd_rst_n <= 1'b1;
                        state <= RESET_RECOVERY;
                    end else wait_count <= wait_count + 32'd1;
                end
                RESET_RECOVERY: begin
                    if (wait_count == RECOVERY_CYCLES - 1) begin
                        wait_count <= 32'd0;
                        state <= INIT_SEND;
                    end else wait_count <= wait_count + 32'd1;
                end
                INIT_SEND: if (spi_ready) state <= INIT_WAIT;
                INIT_WAIT: if (spi_ready) begin
                    if ((INIT_PROFILE!=1 && init_index==0) ||
                        (INIT_PROFILE==1 && init_index==76)) begin
                        wait_count <= 32'd0;
                        init_index <= init_index+7'd1;
                        state <= INIT_SLEEP;
                    end else if (INIT_PROFILE==1 && init_index==75) begin
                        wait_count<=0;init_index<=76;state<=INIT_SETTLE;
                    end else if (INIT_PROFILE==1 && init_index==LAST_INIT) begin
                        wait_count<=0;state<=INIT_ON;
                    end else if (init_index == LAST_INIT) begin
                        init_done <= 1'b1;
                        state <= IDLE;
                    end else begin
                        init_index <= init_index + 7'd1;
                        state <= INIT_SEND;
                    end
                end
                INIT_SETTLE: if(wait_count==SETTLE_CYCLES-1) begin
                    wait_count<=0;state<=INIT_SEND;
                end else wait_count<=wait_count+1'b1;
                INIT_ON: if(wait_count==ON_CYCLES-1) begin
                    wait_count<=0;init_done<=1;state<=IDLE;
                end else wait_count<=wait_count+1'b1;
                INIT_SLEEP: begin
                    if (wait_count == SLEEP_CYCLES - 1) begin
                        wait_count <= 32'd0;
                        state <= INIT_SEND;
                    end else wait_count <= wait_count + 32'd1;
                end
                IDLE: if (req_valid) begin
                    if ((x0 > x1) || (y0 > y1) || (x1 > 8'd127) ||
                        (y1 > 8'd127)) begin
                        req_done <= 1'b1;
                        req_error <= 1'b1;
                    end else begin
                        xs <= X_OFFSET + {8'd0, x0};
                        xe <= X_OFFSET + {8'd0, x1};
                        ys <= Y_OFFSET + {8'd0, y0};
                        ye <= Y_OFFSET + {8'd0, y1};
                        saved_color <= color;
                        pixels_left <= ({1'b0, x1} - {1'b0, x0} + 9'd1) *
                                       ({1'b0, y1} - {1'b0, y0} + 9'd1);
                        op_index <= 4'd0;
                        state <= OP_SEND;
                    end
                end else if (raw_valid) begin
                    raw_word <= {raw_dc, raw_data};
                    state <= RAW_SEND;
                end
                OP_SEND: if (spi_ready) state <= OP_WAIT;
                OP_WAIT: if (spi_ready) begin
                    if (op_index == 4'd12) begin
                        if (pixels_left == 15'd1) begin
                            req_done <= 1'b1;
                            state <= IDLE;
                        end else begin
                            pixels_left <= pixels_left - 15'd1;
                            op_index <= 4'd11;
                            state <= OP_SEND;
                        end
                    end else begin
                        op_index <= op_index + 4'd1;
                        state <= OP_SEND;
                    end
                end
                RAW_SEND: if (spi_ready) state <= RAW_WAIT;
                RAW_WAIT: if (spi_ready) begin
                    raw_done <= 1'b1;
                    state <= IDLE;
                end
                default: state <= RESET_LOW;
            endcase
        end
    end

    // Original STM32 values, except B3h uses its six documented parameters.
    // Bit 8: D/CX (0=command, 1=data). MADCTL is exposed as a parameter.
    function [8:0] init_rom;
        input [6:0] addr;
        begin
            case (addr)
                7'd0: init_rom = 9'h011;
                7'd1: init_rom = 9'h0B1;
                7'd2: init_rom = 9'h102;
                7'd3: init_rom = 9'h135;
                7'd4: init_rom = 9'h136;
                7'd5: init_rom = 9'h0B2;
                7'd6: init_rom = 9'h102;
                7'd7: init_rom = 9'h135;
                7'd8: init_rom = 9'h136;
                7'd9: init_rom = 9'h0B3;
                7'd10: init_rom = 9'h102;
                7'd11: init_rom = 9'h135;
                7'd12: init_rom = 9'h136;
                7'd13: init_rom = 9'h102;
                7'd14: init_rom = 9'h135;
                7'd15: init_rom = 9'h136;
                7'd16: init_rom = 9'h0B4;
                7'd17: init_rom = 9'h103;
                7'd18: init_rom = 9'h0C0;
                7'd19: init_rom = 9'h1A2;
                7'd20: init_rom = 9'h102;
                7'd21: init_rom = 9'h184;
                7'd22: init_rom = 9'h0C1;
                7'd23: init_rom = 9'h1C5;
                7'd24: init_rom = 9'h0C2;
                7'd25: init_rom = 9'h10D;
                7'd26: init_rom = 9'h100;
                7'd27: init_rom = 9'h0C3;
                7'd28: init_rom = 9'h18D;
                7'd29: init_rom = 9'h12A;
                7'd30: init_rom = 9'h0C4;
                7'd31: init_rom = 9'h18D;
                7'd32: init_rom = 9'h1EE;
                7'd33: init_rom = 9'h0C5;
                7'd34: init_rom = 9'h103;
                7'd35: init_rom = 9'h036;
                7'd36: init_rom = {1'b1, MADCTL};
                7'd37: init_rom = 9'h0E0;
                7'd38: init_rom = 9'h112;
                7'd39: init_rom = 9'h11C;
                7'd40: init_rom = 9'h110;
                7'd41: init_rom = 9'h118;
                7'd42: init_rom = 9'h133;
                7'd43: init_rom = 9'h12C;
                7'd44: init_rom = 9'h125;
                7'd45: init_rom = 9'h128;
                7'd46: init_rom = 9'h128;
                7'd47: init_rom = 9'h127;
                7'd48: init_rom = 9'h12F;
                7'd49: init_rom = 9'h13C;
                7'd50: init_rom = 9'h100;
                7'd51: init_rom = 9'h103;
                7'd52: init_rom = 9'h103;
                7'd53: init_rom = 9'h110;
                7'd54: init_rom = 9'h0E1;
                7'd55: init_rom = 9'h112;
                7'd56: init_rom = 9'h11C;
                7'd57: init_rom = 9'h110;
                7'd58: init_rom = 9'h118;
                7'd59: init_rom = 9'h12D;
                7'd60: init_rom = 9'h128;
                7'd61: init_rom = 9'h123;
                7'd62: init_rom = 9'h128;
                7'd63: init_rom = 9'h128;
                7'd64: init_rom = 9'h126;
                7'd65: init_rom = 9'h12F;
                7'd66: init_rom = 9'h13B;
                7'd67: init_rom = 9'h100;
                7'd68: init_rom = 9'h103;
                7'd69: init_rom = 9'h103;
                7'd70: init_rom = 9'h110;
                7'd71: init_rom = 9'h03A;
                7'd72: init_rom = 9'h105;
                7'd73: init_rom = 9'h029;
                default: init_rom = 9'd0;
            endcase
        end
    endfunction
    // Recovered from 2026-10-30 00:44 GPIO profile=1 snapshot.
    // This remains selectable independently from the original CSDN table.
    function [8:0] init_rom_slow;
        input [6:0] addr;
        begin
            case(addr)
                7'd0: init_rom_slow = 9'h0B1;
                7'd1: init_rom_slow = 9'h101;
                7'd2: init_rom_slow = 9'h12C;
                7'd3: init_rom_slow = 9'h12D;
                7'd4: init_rom_slow = 9'h0B2;
                7'd5: init_rom_slow = 9'h101;
                7'd6: init_rom_slow = 9'h12C;
                7'd7: init_rom_slow = 9'h12D;
                7'd8: init_rom_slow = 9'h0B3;
                7'd9: init_rom_slow = 9'h101;
                7'd10: init_rom_slow = 9'h12C;
                7'd11: init_rom_slow = 9'h12D;
                7'd12: init_rom_slow = 9'h101;
                7'd13: init_rom_slow = 9'h12C;
                7'd14: init_rom_slow = 9'h12D;
                7'd15: init_rom_slow = 9'h0B4;
                7'd16: init_rom_slow = 9'h107;
                7'd17: init_rom_slow = 9'h0C0;
                7'd18: init_rom_slow = 9'h1A2;
                7'd19: init_rom_slow = 9'h102;
                7'd20: init_rom_slow = 9'h184;
                7'd21: init_rom_slow = 9'h0C1;
                7'd22: init_rom_slow = 9'h1C5;
                7'd23: init_rom_slow = 9'h0C2;
                7'd24: init_rom_slow = 9'h10A;
                7'd25: init_rom_slow = 9'h100;
                7'd26: init_rom_slow = 9'h0C3;
                7'd27: init_rom_slow = 9'h18A;
                7'd28: init_rom_slow = 9'h12A;
                7'd29: init_rom_slow = 9'h0C4;
                7'd30: init_rom_slow = 9'h18A;
                7'd31: init_rom_slow = 9'h1EE;
                7'd32: init_rom_slow = 9'h0C5;
                7'd33: init_rom_slow = 9'h10E;
                7'd34: init_rom_slow = 9'h0E0;
                7'd35: init_rom_slow = 9'h10F;
                7'd36: init_rom_slow = 9'h11A;
                7'd37: init_rom_slow = 9'h10F;
                7'd38: init_rom_slow = 9'h118;
                7'd39: init_rom_slow = 9'h12F;
                7'd40: init_rom_slow = 9'h128;
                7'd41: init_rom_slow = 9'h120;
                7'd42: init_rom_slow = 9'h122;
                7'd43: init_rom_slow = 9'h11F;
                7'd44: init_rom_slow = 9'h11B;
                7'd45: init_rom_slow = 9'h123;
                7'd46: init_rom_slow = 9'h137;
                7'd47: init_rom_slow = 9'h100;
                7'd48: init_rom_slow = 9'h107;
                7'd49: init_rom_slow = 9'h102;
                7'd50: init_rom_slow = 9'h110;
                7'd51: init_rom_slow = 9'h0E1;
                7'd52: init_rom_slow = 9'h10F;
                7'd53: init_rom_slow = 9'h11B;
                7'd54: init_rom_slow = 9'h10F;
                7'd55: init_rom_slow = 9'h117;
                7'd56: init_rom_slow = 9'h133;
                7'd57: init_rom_slow = 9'h12C;
                7'd58: init_rom_slow = 9'h129;
                7'd59: init_rom_slow = 9'h12E;
                7'd60: init_rom_slow = 9'h130;
                7'd61: init_rom_slow = 9'h130;
                7'd62: init_rom_slow = 9'h139;
                7'd63: init_rom_slow = 9'h13F;
                7'd64: init_rom_slow = 9'h100;
                7'd65: init_rom_slow = 9'h107;
                7'd66: init_rom_slow = 9'h103;
                7'd67: init_rom_slow = 9'h110;
                7'd68: init_rom_slow = 9'h0F0;
                7'd69: init_rom_slow = 9'h101;
                7'd70: init_rom_slow = 9'h0F6;
                7'd71: init_rom_slow = 9'h100;
                7'd72: init_rom_slow = 9'h03A;
                7'd73: init_rom_slow = 9'h105;
                7'd74: init_rom_slow = 9'h036;
                7'd75: init_rom_slow = {1'b1, MADCTL};
                7'd76: init_rom_slow = 9'h011;
                7'd77: init_rom_slow = 9'h029;
                default: init_rom_slow = 9'd0;
            endcase
        end
    endfunction
endmodule
