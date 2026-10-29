`timescale 1ns/1ps
// Four byte lanes allow 8-bit capture writes and 32-bit CPU reads.
// Host writes are intentionally ignored. One-cycle synchronous read latency.
module la_sample_ram #(parameter ADDR_WIDTH=15)(
    input clk, input wr_en, input [ADDR_WIDTH-1:0] wr_addr, input [7:0] wr_data,
    input host_clk, input host_rst, input host_en,
    input [31:0] host_addr, output reg [31:0] host_data
);
    localparam WORDS=(1 << (ADDR_WIDTH-2));
    (* ram_style="block" *) reg [7:0] lane0[0:WORDS-1];
    (* ram_style="block" *) reg [7:0] lane1[0:WORDS-1];
    (* ram_style="block" *) reg [7:0] lane2[0:WORDS-1];
    (* ram_style="block" *) reg [7:0] lane3[0:WORDS-1];
    always @(posedge clk) if(wr_en) begin
        case(wr_addr[1:0])
            0: lane0[wr_addr[ADDR_WIDTH-1:2]]<=wr_data;
            1: lane1[wr_addr[ADDR_WIDTH-1:2]]<=wr_data;
            2: lane2[wr_addr[ADDR_WIDTH-1:2]]<=wr_data;
            3: lane3[wr_addr[ADDR_WIDTH-1:2]]<=wr_data;
        endcase
    end
    always @(posedge host_clk) begin
        if(host_rst) host_data<=0;
        else if(host_en) host_data <= {lane3[host_addr[ADDR_WIDTH-1:2]],lane2[host_addr[ADDR_WIDTH-1:2]],
                                      lane1[host_addr[ADDR_WIDTH-1:2]],lane0[host_addr[ADDR_WIDTH-1:2]]};
    end
endmodule
