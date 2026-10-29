`timescale 1ns/1ps
// Single clock for AXI registers, sampler and BRAM controller in create_project.tcl.
module la_axi #(
    parameter ADDR_WIDTH=15,
    parameter DEBOUNCE_CYCLES=1000000
)(
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME s_axi, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_REGION 0, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWADDR" *) input [11:0] s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWPROT" *) input [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWVALID" *) input s_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWREADY" *) output s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WDATA" *) input [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WSTRB" *) input [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WVALID" *) input s_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WREADY" *) output s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BRESP" *) output [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BVALID" *) output reg s_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BREADY" *) input s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARADDR" *) input [11:0] s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARPROT" *) input [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARVALID" *) input s_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARREADY" *) output s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RDATA" *) output reg [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RRESP" *) output [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RVALID" *) output reg s_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RREADY" *) input s_axi_rready,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME clk, ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET rst_n, FREQ_HZ 50000000" *)
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk CLK" *) input clk,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 rst_n RST" *) input rst_n,
    (* X_INTERFACE_INFO="xilinx.com:interface:bram:1.0 capture_bram CLK" *) input bram_clk,
    (* X_INTERFACE_INFO="xilinx.com:interface:bram:1.0 capture_bram RST" *) input bram_rst,
    (* X_INTERFACE_INFO="xilinx.com:interface:bram:1.0 capture_bram EN" *) input bram_en,
    (* X_INTERFACE_INFO="xilinx.com:interface:bram:1.0 capture_bram WE" *) input [3:0] bram_we,
    (* X_INTERFACE_INFO="xilinx.com:interface:bram:1.0 capture_bram ADDR" *) input [31:0] bram_addr,
    (* X_INTERFACE_INFO="xilinx.com:interface:bram:1.0 capture_bram DIN" *) input [31:0] bram_wrdata,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME capture_bram, MEM_SIZE 32768, MEM_WIDTH 32, READ_LATENCY 1, READ_WRITE_MODE READ_WRITE, MASTER_TYPE BRAM_CTRL" *)
    (* X_INTERFACE_INFO="xilinx.com:interface:bram:1.0 capture_bram DOUT" *) output [31:0] bram_rddata,
    input [7:0] probe, input [1:0] keys_n,
    output [1:0] leds,
    inout [3:0] test_io
);
    reg aw_pending,w_pending;
    wire [3:0] test_data,test_drive,test_read;
    genvar t;
    generate for(t=0;t<4;t=t+1) begin: test_pads
        IOBUF test_buffer(.I(test_data[t]),.T(~test_drive[t]),.O(test_read[t]),.IO(test_io[t]));
    end endgenerate
    reg [11:0] aw_address;
    reg [31:0] write_data;
    reg [3:0] write_strobe;
    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready = !w_pending && !s_axi_bvalid;
    assign s_axi_arready = !s_axi_rvalid;
    assign s_axi_bresp = 0;
    assign s_axi_rresp = 0;
    reg arm,cancel;
    reg [7:0] cfg_mask,cfg_level_mask,cfg_level_value;
    reg [5:0] cfg_divider;
    reg [6:0] cfg_trigger;
    reg [1:0] cfg_pre, test_mode, test_spi_mode;
    reg test_error;
    reg [2:0] stat_channel;
    wire [2:0] state;
    wire mem_we;
    wire [ADDR_WIDTH-1:0] mem_addr,start_index,trigger_index;
    wire [ADDR_WIDTH:0] valid_count;
    wire [7:0] mem_data,active_mask;
    wire [5:0] active_divider;
    wire [63:0] first_tick,trigger_tick,first_edge,last_edge;
    wire [31:0] edge_count;
    reg [31:0] read_value;
    (* ASYNC_REG="TRUE" *) reg [1:0] keys_meta,keys_sync;
    reg [1:0] keys;
    reg [19:0] key_count0,key_count1;
    reg [25:0] heartbeat;
    assign leds={state==3,heartbeat[25]};
    function [31:0] merge_bytes;
        input [31:0] old_value,new_value; input [3:0] strobe;
        integer i;
        begin
            for(i=0;i<4;i=i+1) merge_bytes[i*8+:8]=strobe[i]?new_value[i*8+:8]:old_value[i*8+:8];
        end
    endfunction
    reg [31:0] merged;
    always @* begin
        case(s_axi_araddr[11:2])
            'h00:read_value=32'h4c410101;
            'h02:read_value={29'b0,state};
            'h03:read_value={24'b0,cfg_mask};
            'h04:read_value={26'b0,cfg_divider};
            'h05:read_value={25'b0,cfg_trigger};
            'h06:read_value={24'b0,cfg_level_mask};
            'h07:read_value={24'b0,cfg_level_value};
            'h08:read_value={30'b0,cfg_pre};
            'h09:read_value=start_index;
            'h0a:read_value=valid_count;
            'h0b:read_value=trigger_index;
            'h0c:read_value=first_tick[31:0];
            'h0d:read_value=first_tick[63:32];
            'h0e:read_value=trigger_tick[31:0];
            'h0f:read_value=trigger_tick[63:32];
            'h10:read_value=active_mask;
            'h11:read_value=active_divider;
            'h12:read_value=stat_channel;
            'h13:read_value=edge_count;
            'h14:read_value=first_edge[31:0];
            'h15:read_value=first_edge[63:32];
            'h16:read_value=last_edge[31:0];
            'h17:read_value=last_edge[63:32];
            'h18:read_value={27'b0,test_error,test_spi_mode,test_mode};
            'h19:read_value={30'b0,~keys};
            'h1a:read_value={28'b0,test_read};
            default:read_value=0;
        endcase
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            aw_pending<=0;w_pending<=0;aw_address<=0;write_data<=0;write_strobe<=0;
            s_axi_bvalid<=0;s_axi_rvalid<=0;s_axi_rdata<=0;arm<=0;cancel<=0;
            cfg_mask<=8'hff;cfg_divider<=1;cfg_trigger<=0;cfg_level_mask<=1;cfg_level_value<=0;
            cfg_pre<=0;stat_channel<=0;test_mode<=0;test_spi_mode<=0;test_error<=0;
            keys_meta<=3;keys_sync<=3;keys<=3;key_count0<=0;key_count1<=0;heartbeat<=0;
        end else begin
            heartbeat<=heartbeat+1'b1; keys_meta<=keys_n;keys_sync<=keys_meta;
            if(keys_sync[0]==keys[0]) key_count0<=0;
            else if(key_count0==DEBOUNCE_CYCLES-1) begin keys[0]<=keys_sync[0];key_count0<=0;end
            else key_count0<=key_count0+1'b1;
            if(keys_sync[1]==keys[1]) key_count1<=0;
            else if(key_count1==DEBOUNCE_CYCLES-1) begin keys[1]<=keys_sync[1];key_count1<=0;end
            else key_count1<=key_count1+1'b1;
            arm<=0;cancel<=0;
            if(s_axi_awready && s_axi_awvalid) begin aw_pending<=1;aw_address<=s_axi_awaddr;end
            if(s_axi_wready && s_axi_wvalid) begin w_pending<=1;write_data<=s_axi_wdata;write_strobe<=s_axi_wstrb;end
            if(s_axi_bvalid && s_axi_bready) s_axi_bvalid<=0;
            if(aw_pending && w_pending && !s_axi_bvalid) begin
                aw_pending<=0;w_pending<=0;s_axi_bvalid<=1;
                case(aw_address[11:2])
                    'h01:if(write_strobe[0]) begin arm<=write_data[0] && !write_data[1];cancel<=write_data[1];end
                    'h03:begin merged=merge_bytes({24'b0,cfg_mask},write_data,write_strobe);cfg_mask<=merged[7:0];end
                    'h04:begin merged=merge_bytes({26'b0,cfg_divider},write_data,write_strobe);cfg_divider<=merged[5:0];end
                    'h05:begin merged=merge_bytes({25'b0,cfg_trigger},write_data,write_strobe);cfg_trigger<=merged[6:0];end
                    'h06:begin merged=merge_bytes({24'b0,cfg_level_mask},write_data,write_strobe);cfg_level_mask<=merged[7:0];end
                    'h07:begin merged=merge_bytes({24'b0,cfg_level_value},write_data,write_strobe);cfg_level_value<=merged[7:0];end
                    'h08:if(write_strobe[0])cfg_pre<=write_data[1:0];
                    'h12:if(write_strobe[0])stat_channel<=write_data[2:0];
                    'h18:if(write_strobe[0])begin test_mode<=write_data[1:0];test_spi_mode<=write_data[3:2];test_error<=write_data[4];end
                    default:begin end
                endcase
            end
            if(s_axi_rvalid && s_axi_rready) s_axi_rvalid<=0;
            if(s_axi_arvalid && s_axi_arready) begin s_axi_rvalid<=1;s_axi_rdata<=read_value;end
        end
    end
    la_capture #(.ADDR_WIDTH(ADDR_WIDTH)) capture(
        .clk(clk),.rst_n(rst_n),.probe(probe),.arm(arm),.cancel(cancel),
        .cfg_mask(cfg_mask),.cfg_divider(cfg_divider),.cfg_trigger(cfg_trigger[1:0]),
        .cfg_channel(cfg_trigger[6:4]),.cfg_level_mask(cfg_level_mask),.cfg_level_value(cfg_level_value),
        .cfg_pretrigger(cfg_pre),.state(state),.mem_we(mem_we),.mem_addr(mem_addr),.mem_data(mem_data),
        .start_index(start_index),.valid_count(valid_count),.trigger_index(trigger_index),
        .first_tick(first_tick),.trigger_tick(trigger_tick),.active_mask(active_mask),.active_divider(active_divider),
        .stat_channel(stat_channel),.edge_count(edge_count),.first_edge_tick(first_edge),.last_edge_tick(last_edge));
    la_sample_ram #(.ADDR_WIDTH(ADDR_WIDTH)) samples(
        .clk(clk),.wr_en(mem_we),.wr_addr(mem_addr),.wr_data(mem_data),
        .host_clk(bram_clk),.host_rst(bram_rst),.host_en(bram_en),.host_addr(bram_addr),.host_data(bram_rddata));
    la_testgen generator(.clk(clk),.rst_n(rst_n),.mode(test_mode),.spi_mode(test_spi_mode),.inject_error(test_error),
        .data(test_data),.drive(test_drive));
endmodule
