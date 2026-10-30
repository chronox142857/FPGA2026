// One-shot four-wire SPI reads over bidirectional SDA. Raw streams include
// any command-specific dummy bits; do not interpret them as decoded IDs.
module st7735s_readback #(
    parameter integer HALF_CYCLES = 250
) (
    input wire clk, input wire rst_n, input wire start,
    input wire sda_in,
    output reg busy, output reg done,
    output reg cs_n, output reg sck, output reg dc,
    output reg sda_out, output reg sda_hiz,
    output reg [2:0] pad_flags,
    output reg [31:0] raw_id, raw_power, raw_madctl, raw_colmod
);
    localparam [3:0] IDLE=0, PAD_LOW=1, PAD_HIGH=2, PAD_Z=3,
        CMD_SETUP=4, CMD_SELECT=5, CMD_LOW=6, CMD_HIGH=7,
        READ_LOW=8, READ_HIGH=9, READ_HOLD=10, GAP=11;
    localparam integer TURN_CYCLES = (HALF_CYCLES > 1) ? HALF_CYCLES/2 : 1;
    reg [3:0] state;
    reg [15:0] ticks;
    reg [1:0] command_index;
    reg [2:0] command_bit;
    reg [5:0] read_bit;
    reg [7:0] command;
    reg [31:0] shift_data;

    function [7:0] read_command;
        input [1:0] index;
        begin
            case(index)
                0: read_command=8'h04;
                1: read_command=8'h0A;
                2: read_command=8'h0B;
                3: read_command=8'h0C;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE;ticks<=0;command_index<=0;command_bit<=7;
            read_bit<=0;command<=8'h04;shift_data<=0;
            busy<=0;done<=0;cs_n<=1;sck<=0;dc<=1;
            sda_out<=0;sda_hiz<=0;pad_flags<=0;
            raw_id<=0;raw_power<=0;raw_madctl<=0;raw_colmod<=0;
        end else begin
            case(state)
                IDLE: if(start && !done) begin
                    busy<=1;cs_n<=1;sck<=0;dc<=1;
                    sda_out<=0;sda_hiz<=0;ticks<=0;state<=PAD_LOW;
                end
                PAD_LOW: if(ticks==HALF_CYCLES-1) begin
                    pad_flags[0]<=sda_in;sda_out<=1;ticks<=0;state<=PAD_HIGH;
                end else ticks<=ticks+1'b1;
                PAD_HIGH: if(ticks==HALF_CYCLES-1) begin
                    pad_flags[1]<=sda_in;sda_hiz<=1;ticks<=0;state<=PAD_Z;
                end else ticks<=ticks+1'b1;
                PAD_Z: if(ticks==HALF_CYCLES-1) begin
                    pad_flags[2]<=sda_in;sda_hiz<=0;sda_out<=0;dc<=0;
                    ticks<=0;state<=CMD_SETUP;
                end else ticks<=ticks+1'b1;
                CMD_SETUP: if(ticks==HALF_CYCLES-1) begin
                    cs_n<=0;ticks<=0;state<=CMD_SELECT;
                end else ticks<=ticks+1'b1;
                CMD_SELECT: if(ticks==HALF_CYCLES-1) begin
                    ticks<=0;state<=CMD_LOW;
                end else ticks<=ticks+1'b1;
                CMD_LOW: if(ticks==HALF_CYCLES-1) begin
                    sck<=1;ticks<=0;state<=CMD_HIGH;
                end else ticks<=ticks+1'b1;
                CMD_HIGH: begin
                    // Release after the final command sampling edge, with
                    // data hold, but BEFORE that command's final falling edge.
                    if(command_bit==0 && ticks==TURN_CYCLES-1) begin
                        sda_hiz<=1;dc<=1;
                    end
                    if(ticks==HALF_CYCLES-1) begin
                        sck<=0;ticks<=0;
                        if(command_bit==0) begin
                            read_bit<=0;shift_data<=0;state<=READ_LOW;
                        end else begin
                            command_bit<=command_bit-1'b1;
                            sda_out<=command[command_bit-1'b1];state<=CMD_LOW;
                        end
                    end else ticks<=ticks+1'b1;
                end
                READ_LOW: if(ticks==HALF_CYCLES-1) begin
                    shift_data<={shift_data[30:0],sda_in};
                    sck<=1;ticks<=0;state<=READ_HIGH;
                end else ticks<=ticks+1'b1;
                READ_HIGH: if(ticks==HALF_CYCLES-1) begin
                    sck<=0;ticks<=0;
                    if(read_bit==31) begin
                        case(command_index)
                            0:raw_id<=shift_data;
                            1:raw_power<=shift_data;
                            2:raw_madctl<=shift_data;
                            3:raw_colmod<=shift_data;
                        endcase
                        state<=READ_HOLD;
                    end else begin read_bit<=read_bit+1'b1;state<=READ_LOW;end
                end else ticks<=ticks+1'b1;
                READ_HOLD: if(ticks==HALF_CYCLES-1) begin
                    cs_n<=1;ticks<=0;state<=GAP;
                end else ticks<=ticks+1'b1;
                GAP: if(ticks==HALF_CYCLES-1) begin
                    ticks<=0;
                    if(command_index==3) begin busy<=0;done<=1;state<=IDLE;end
                    else begin
                        command_index<=command_index+1'b1;
                        command<=read_command(command_index+1'b1);
                        command_bit<=7;sda_hiz<=0;sda_out<=0;dc<=0;
                        state<=CMD_SETUP;
                    end
                end else ticks<=ticks+1'b1;
                default: begin state<=IDLE;busy<=0;cs_n<=1;sck<=0;end
            endcase
        end
    end
endmodule
