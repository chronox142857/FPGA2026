`timescale 1ns/1ps
// All addresses and indices are SAMPLE indices, not BRAM word addresses.
module la_capture #(
    parameter ADDR_WIDTH = 15
)(
    input clk, input rst_n,
    input [7:0] probe,
    input arm, input cancel,
    input [7:0] cfg_mask,
    input [5:0] cfg_divider,
    input [1:0] cfg_trigger,
    input [2:0] cfg_channel,
    input [7:0] cfg_level_mask, input [7:0] cfg_level_value,
    input [1:0] cfg_pretrigger,
    output reg [2:0] state,
    output reg mem_we,
    output reg [ADDR_WIDTH-1:0] mem_addr,
    output reg [7:0] mem_data,
    output reg [ADDR_WIDTH-1:0] start_index,
    output reg [ADDR_WIDTH:0] valid_count,
    output reg [ADDR_WIDTH-1:0] trigger_index,
    output reg [63:0] first_tick,
    output reg [63:0] trigger_tick,
    output reg [7:0] active_mask,
    output reg [5:0] active_divider,
    input [2:0] stat_channel,
    output [31:0] edge_count,
    output [63:0] first_edge_tick,
    output [63:0] last_edge_tick
);
    localparam IDLE=0, WAITING=1, POST=2, DONE=3, ERROR=4, DRAIN=5;
    localparam [ADDR_WIDTH:0] DEPTH = (1 << ADDR_WIDTH);
    (* ASYNC_REG="TRUE" *) reg [7:0] probe_meta, probe_sync;
    reg [7:0] previous;
    reg previous_valid;
    reg [5:0] divide_count;
    reg [1:0] trigger_mode;
    reg [2:0] trigger_channel;
    reg [7:0] level_mask, level_value;
    reg [ADDR_WIDTH-1:0] write_index;
    reg [ADDR_WIDTH:0] history_count, pre_count, remaining;
    reg [63:0] ticks;
    reg [31:0] counts[0:7];
    reg [63:0] first_edges[0:7], last_edges[0:7];
    wire [7:0] sample_value = probe_sync & active_mask;
    wire [7:0] changed = (sample_value ^ previous) & active_mask;
    wire fired = (trigger_mode == 0) ||
        (previous_valid && trigger_mode == 1 && !previous[trigger_channel] && sample_value[trigger_channel]) ||
        (previous_valid && trigger_mode == 2 && previous[trigger_channel] && !sample_value[trigger_channel]) ||
        (trigger_mode == 3 && ((sample_value & level_mask) == (level_value & level_mask)));
    assign edge_count = counts[stat_channel];
    assign first_edge_tick = first_edges[stat_channel];
    assign last_edge_tick = last_edges[stat_channel];
    integer k;
    always @(posedge clk) begin
        if (!rst_n) begin probe_meta <= 0; probe_sync <= 0; end
        else begin probe_meta <= probe; probe_sync <= probe_meta; end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            ticks<=0; state<=IDLE; mem_we<=0; mem_addr<=0; mem_data<=0;
            start_index<=0; valid_count<=0; trigger_index<=0;
            first_tick<=0; trigger_tick<=0; active_mask<=0; active_divider<=1;
            previous<=0; previous_valid<=0; divide_count<=0; trigger_mode<=0;
            trigger_channel<=0; level_mask<=0; level_value<=0;
            write_index<=0; history_count<=0; pre_count<=0; remaining<=0;
            for(k=0;k<8;k=k+1) begin counts[k]<=0; first_edges[k]<=0; last_edges[k]<=0; end
        end else begin
            ticks <= ticks+1'b1;
            mem_we <= 0;
            if (cancel) begin state<=IDLE; valid_count<=0; end
            else if (arm && (state==IDLE || state==DONE || state==ERROR)) begin
                if (!(cfg_divider==1 || cfg_divider==2 || cfg_divider==5 || cfg_divider==10 || cfg_divider==50) ||
                    cfg_mask==0 || ((cfg_trigger==1 || cfg_trigger==2) && !cfg_mask[cfg_channel]) ||
                    (cfg_trigger==3 && (cfg_level_mask==0 || (cfg_level_mask & ~cfg_mask)!=0))) begin
                    state<=ERROR; valid_count<=0;
                end else begin
                    state<=WAITING; active_mask<=cfg_mask; active_divider<=cfg_divider;
                    trigger_mode<=cfg_trigger; trigger_channel<=cfg_channel;
                    level_mask<=cfg_level_mask; level_value<=cfg_level_value;
                    pre_count <= (DEPTH >> 2) * cfg_pretrigger;
                    history_count<=0; remaining<=0; write_index<=0; valid_count<=0;
                    start_index<=0; trigger_index<=0; first_tick<=0; trigger_tick<=0;
                    previous_valid<=0; previous<=0; divide_count<=0;
                    for(k=0;k<8;k=k+1) begin counts[k]<=0; first_edges[k]<=0; last_edges[k]<=0; end
                end
            end else if (state==DRAIN) begin state<=DONE; valid_count<=DEPTH; end
            else if (state==WAITING || state==POST) begin
                if (divide_count != 0) divide_count<=divide_count-1'b1;
                else begin
                    divide_count<=active_divider-1'b1;
                    mem_we<=1; mem_addr<=write_index; mem_data<=sample_value;
                    write_index<=write_index+1'b1;
                    previous<=sample_value; previous_valid<=1;
                    if(previous_valid) for(k=0;k<8;k=k+1) if(changed[k]) begin
                        counts[k]<=counts[k]+1'b1;
                        if(counts[k]==0) first_edges[k]<=ticks;
                        last_edges[k]<=ticks;
                    end
                    if (state==WAITING) begin
                        if (history_count < DEPTH) history_count<=history_count+1'b1;
                        // Do not accept a trigger until the requested history exists.
                        if (history_count>=pre_count && fired) begin
                            trigger_index<=pre_count[ADDR_WIDTH-1:0];
                            start_index<=write_index-pre_count[ADDR_WIDTH-1:0];
                            trigger_tick<=ticks;
                            first_tick<=ticks - pre_count * active_divider;
                            remaining<=DEPTH-pre_count-1'b1;
                            if(DEPTH-pre_count==1) state<=DRAIN;
                            else state<=POST;
                        end
                    end else if (remaining==1) begin
                        state<=DRAIN; remaining<=0;
                    end else remaining<=remaining-1'b1;
                end
            end
        end
    end
endmodule
