// ST7735S 4-wire, write-only serial byte transmitter; sampled on rising SCK.
// tx_last ends a packet; non-final bytes keep CS low until the next byte.
module st7735s_spi_byte #(
    parameter integer HALF_CYCLES = 2,
    parameter integer LOW_CYCLES = HALF_CYCLES,
    parameter integer HIGH_CYCLES = HALF_CYCLES,
    parameter integer CS_IDLE_CYCLES = 1,
    parameter integer CS_SETUP_CYCLES = 3,
    parameter integer CS_HOLD_CYCLES = 3,
    parameter integer END_CLOCK_HIGH = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tx_valid,
    output wire       tx_ready,
    input  wire       tx_dc,
    input  wire [7:0] tx_data,
    input  wire       tx_last,
    output reg        lcd_cs_n,
    output reg        lcd_sck,
    output reg        lcd_dc,
    output reg        lcd_mosi
);
    localparam [2:0] IDLE = 3'd0, SETUP = 3'd1,
                     LOW = 3'd2, HIGH = 3'd3, HOLD = 3'd4,
                     WAIT_NEXT = 3'd5, PRESELECT = 3'd6;
    reg [2:0] state;
    reg [15:0] ticks;
    reg [2:0] bit_index;
    reg [7:0] shift_data;
    reg last_byte;

    assign tx_ready = (state == IDLE) || (state == WAIT_NEXT);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            ticks <= 16'd0;
            bit_index <= 3'd0;
            shift_data <= 8'd0;
            last_byte <= 1'b1;
            lcd_cs_n <= END_CLOCK_HIGH ? 1'b0 : 1'b1;
            lcd_sck <= 1'b0;
            lcd_dc <= END_CLOCK_HIGH ? 1'b0 : 1'b1;
            lcd_mosi <= 1'b0;
        end else begin
            case (state)
                IDLE, WAIT_NEXT: begin
                    // STM32 GPIO initialization starts CS/SCK/DC/SDA low.
                    // In that profile CS stays low until the first byte ends.
                    if(state == IDLE && !END_CLOCK_HIGH) lcd_cs_n <= 1'b1;
                    if(!END_CLOCK_HIGH) lcd_sck <= 1'b0;
                    if (tx_valid) begin
                        shift_data <= tx_data;
                        last_byte <= tx_last;
                        bit_index <= 3'd7;
                        if(!END_CLOCK_HIGH) lcd_mosi <= tx_data[7];
                        lcd_dc <= tx_dc;
                        ticks <= 16'd0;
                        state <= (state == IDLE) ? PRESELECT : SETUP;
                    end
                end
                PRESELECT: begin
                    if(ticks == CS_IDLE_CYCLES-1) begin
                        lcd_cs_n <= 1'b0;ticks <= 0;state <= SETUP;
                    end else ticks <= ticks+1'b1;
                end
                SETUP: begin
                    // STM32 original: select first, then lower SCK and set SDA.
                    if(END_CLOCK_HIGH) begin
                        lcd_sck <= 1'b0;
                        lcd_mosi <= shift_data[7];
                    end
                    if (ticks == CS_SETUP_CYCLES - 1) begin
                        ticks <= 16'd0;
                        state <= LOW;
                    end else ticks <= ticks + 16'd1;
                end
                LOW: begin
                    if (ticks == LOW_CYCLES - 1) begin
                        lcd_sck <= 1'b1; // ST7735S samples SDA on this edge.
                        ticks <= 16'd0;
                        state <= HIGH;
                    end else ticks <= ticks + 16'd1;
                end
                HIGH: begin
                    if (ticks == HIGH_CYCLES - 1) begin
                        if(!END_CLOCK_HIGH || bit_index!=0) lcd_sck <= 1'b0;
                        ticks <= 16'd0;
                        if (bit_index == 3'd0) begin
                            state <= last_byte ? HOLD : WAIT_NEXT;
                        end else begin
                            bit_index <= bit_index - 3'd1;
                            lcd_mosi <= shift_data[bit_index - 3'd1];
                            state <= LOW;
                        end
                    end else ticks <= ticks + 16'd1;
                end
                HOLD: begin
                    if (ticks == CS_HOLD_CYCLES - 1) begin
                        lcd_cs_n <= 1'b1;
                        ticks <= 16'd0;
                        state <= IDLE;
                    end else ticks <= ticks + 16'd1;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
