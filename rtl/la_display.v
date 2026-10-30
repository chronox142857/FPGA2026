`timescale 1ns/1ps
// AXI framebuffer bridge to the unchanged, bench-verified ST7735S PL driver.
// CPU writes RGB565 pairs at +0x8000, then submits an inclusive logical rectangle.
// Writes during a transfer fail with SLVERR; only a frozen framebuffer is streamed.
module la_display #(
    parameter CLK_HZ=50000000,
    parameter SPI_HALF_CYCLES=100,
    parameter POWER_ON_CYCLES=65536
)(
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME s_axi, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 16, HAS_BURST 0, HAS_LOCK 0, HAS_CACHE 0, HAS_REGION 0, SUPPORTS_NARROW_BURST 0, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1" *)
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWADDR" *) input [15:0] s_axi_awaddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWPROT" *) input [2:0] s_axi_awprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWVALID" *) input s_axi_awvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi AWREADY" *) output s_axi_awready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WDATA" *) input [31:0] s_axi_wdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WSTRB" *) input [3:0] s_axi_wstrb,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WVALID" *) input s_axi_wvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi WREADY" *) output s_axi_wready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BRESP" *) output reg [1:0] s_axi_bresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BVALID" *) output reg s_axi_bvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi BREADY" *) input s_axi_bready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARADDR" *) input [15:0] s_axi_araddr,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARPROT" *) input [2:0] s_axi_arprot,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARVALID" *) input s_axi_arvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi ARREADY" *) output s_axi_arready,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RDATA" *) output reg [31:0] s_axi_rdata,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RRESP" *) output reg [1:0] s_axi_rresp,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RVALID" *) output reg s_axi_rvalid,
    (* X_INTERFACE_INFO="xilinx.com:interface:aximm:1.0 s_axi RREADY" *) input s_axi_rready,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME clk, ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET rst_n, FREQ_HZ 50000000" *)
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk CLK" *) input clk,
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME rst_n, POLARITY ACTIVE_LOW" *)
    (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 rst_n RST" *) input rst_n,
    // Display reset is independent of PS initialization, exactly as the working
    // standalone image. AXI reset may restart the host bridge, not the LCD init.
    input panel_reset_n,
    output tft_sck, output tft_mosi, output tft_cs_n,
    output [2:0] tft_ctrl
);
    reg [31:0] power_count=0;
    reg power_ready=0;
    (* ASYNC_REG="TRUE" *) reg [1:0] panel_reset_sync=0;
    always @(posedge clk or negedge panel_reset_n) begin
        if(!panel_reset_n)begin power_count<=0;power_ready<=0;end
        else if(!power_ready)begin
            if(power_count==POWER_ON_CYCLES-1)power_ready<=1;
            else power_count<=power_count+1'b1;
        end
    end
    always @(posedge clk or negedge panel_reset_n) begin
        if(!panel_reset_n)panel_reset_sync<=0;
        else panel_reset_sync<={panel_reset_sync[0],power_ready};
    end
    wire display_rst_n=panel_reset_sync[1];
    localparam IDLE=0, HEADER_SEND=1, HEADER_WAIT=2, FETCH=3, LATCH=4,
               HIGH_SEND=5, HIGH_WAIT=6, LOW_SEND=7, LOW_WAIT=8;
    reg [3:0] state;
    reg [3:0] header_index;
    reg [6:0] x,y,x0,y0,x1,y1;
    reg [7:0] cfg_x0,cfg_y0,cfg_x1,cfg_y1;
    reg [7:0] start_x0,start_y0,start_x1,start_y1;
    reg [15:0] pixel;
    reg [31:0] frames;
    reg present,error;
    wire init_done,raw_ready,raw_done;
    wire busy=(state!=IDLE) || present;
    reg [8:0] header_word;
    wire [15:0] panel_x0={9'd0,x0}+16'd2, panel_x1={9'd0,x1}+16'd2;
    wire [15:0] panel_y0={9'd0,y0}+16'd3, panel_y1={9'd0,y1}+16'd3;
    always @* begin
        case(header_index)
            0:header_word=9'h02a;
            1:header_word={1'b1,panel_x0[15:8]};
            2:header_word={1'b1,panel_x0[7:0]};
            3:header_word={1'b1,panel_x1[15:8]};
            4:header_word={1'b1,panel_x1[7:0]};
            5:header_word=9'h02b;
            6:header_word={1'b1,panel_y0[15:8]};
            7:header_word={1'b1,panel_y0[7:0]};
            8:header_word={1'b1,panel_y1[15:8]};
            9:header_word={1'b1,panel_y1[7:0]};
            default:header_word=9'h02c;
        endcase
    end
    wire raw_valid=(state==HEADER_SEND || state==HIGH_SEND || state==LOW_SEND);
    wire raw_dc=(state==HEADER_SEND)?header_word[8]:1'b1;
    wire [7:0] raw_data=(state==HEADER_SEND)?header_word[7:0]:
                                      (state==HIGH_SEND)?pixel[15:8]:pixel[7:0];
    st7735s_driver #(.INIT_PROFILE(2),.CLK_HZ(CLK_HZ),
        .SPI_HALF_CYCLES(SPI_HALF_CYCLES),.X_OFFSET(2),.Y_OFFSET(3),.MADCTL(8'hc8)) panel(
        .clk(clk),.rst_n(display_rst_n),.bl_enable(1'b1),
        .req_valid(1'b0),.req_ready(),.x0(8'd0),.y0(8'd0),.x1(8'd0),.y1(8'd0),.color(16'd0),
        .raw_valid(raw_valid),.raw_ready(raw_ready),.raw_dc(raw_dc),.raw_data(raw_data),.raw_done(raw_done),
        .init_done(init_done),.req_done(),.req_error(),.busy(),
        .lcd_rst_n(tft_ctrl[1]),.lcd_cs_n(tft_cs_n),.lcd_sck(tft_sck),
        .lcd_dc(tft_ctrl[0]),.lcd_mosi(tft_mosi),.lcd_bl(tft_ctrl[2]));

    reg aw_pending,w_pending;
    reg [15:0] aw_address;
    reg [31:0] write_data;
    reg [3:0] write_strobe;
    wire commit=aw_pending && w_pending && !s_axi_bvalid;
    assign s_axi_awready=!aw_pending && !s_axi_bvalid;
    assign s_axi_wready=!w_pending && !s_axi_bvalid;
    assign s_axi_arready=!s_axi_rvalid;
    (* ram_style="block" *) reg [31:0] framebuffer[0:8191];
    reg [31:0] memory_word;
    wire [12:0] read_index={y,x[6:1]};
    integer lane;
    // No array reset: software fills the framebuffer before its first PRESENT.
    always @(posedge clk) begin
        if(rst_n && commit && aw_address[15] && aw_address[1:0]==0 && !busy)
            for(lane=0;lane<4;lane=lane+1)
                if(write_strobe[lane]) framebuffer[aw_address[14:2]][lane*8+:8]<=write_data[lane*8+:8];
        memory_word<=framebuffer[read_index];
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=IDLE;header_index<=0;pixel<=0;frames<=0;
            x<=0;y<=0;x0<=0;y0<=0;x1<=0;y1<=0;
        end else case(state)
            IDLE:if(present) begin
                x0<=start_x0[6:0];y0<=start_y0[6:0];x1<=start_x1[6:0];y1<=start_y1[6:0];
                x<=start_x0[6:0];y<=start_y0[6:0];header_index<=0;state<=HEADER_SEND;
            end
            HEADER_SEND:if(raw_ready) state<=HEADER_WAIT;
            HEADER_WAIT:if(raw_done) begin
                if(header_index==10)state<=FETCH;
                else begin header_index<=header_index+1'b1;state<=HEADER_SEND;end
            end
            FETCH:state<=LATCH;
            LATCH:begin pixel<=x[0]?memory_word[31:16]:memory_word[15:0];state<=HIGH_SEND;end
            HIGH_SEND:if(raw_ready)state<=HIGH_WAIT;
            HIGH_WAIT:if(raw_done)state<=LOW_SEND;
            LOW_SEND:if(raw_ready)state<=LOW_WAIT;
            LOW_WAIT:if(raw_done) begin
                if(x==x1 && y==y1)begin frames<=frames+1'b1;state<=IDLE;end
                else begin
                    if(x==x1)begin x<=x0;y<=y+1'b1;end else x<=x+1'b1;
                    state<=FETCH;
                end
            end
            default:state<=IDLE;
        endcase
    end
    reg [31:0] read_value;
    always @* begin
        case(s_axi_araddr)
            16'h0000:read_value=32'h4c440101;
            16'h0004:read_value={29'd0,error,busy,init_done};
            16'h000c:read_value=frames;
            16'h0010:read_value={24'd0,cfg_x0};
            16'h0014:read_value={24'd0,cfg_y0};
            16'h0018:read_value={24'd0,cfg_x1};
            16'h001c:read_value={24'd0,cfg_y1};
            16'h0020:read_value=2;
            16'h0024:read_value=32'h00800080;
            16'h0028:read_value=SPI_HALF_CYCLES;
            default:read_value=0;
        endcase
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            aw_pending<=0;w_pending<=0;aw_address<=0;write_data<=0;write_strobe<=0;
            s_axi_bvalid<=0;s_axi_bresp<=0;s_axi_rvalid<=0;s_axi_rdata<=0;s_axi_rresp<=0;
            present<=0;error<=0;cfg_x0<=0;cfg_y0<=0;cfg_x1<=127;cfg_y1<=127;
            start_x0<=0;start_y0<=0;start_x1<=127;start_y1<=127;
        end else begin
            present<=0;
            if(s_axi_awready && s_axi_awvalid)begin aw_pending<=1;aw_address<=s_axi_awaddr;end
            if(s_axi_wready && s_axi_wvalid)begin w_pending<=1;write_data<=s_axi_wdata;write_strobe<=s_axi_wstrb;end
            if(s_axi_bvalid && s_axi_bready)s_axi_bvalid<=0;
            if(commit) begin
                aw_pending<=0;w_pending<=0;s_axi_bvalid<=1;s_axi_bresp<=0;
                if(aw_address[1:0]!=0)begin error<=1;s_axi_bresp<=2;end
                else if(aw_address[15])begin
                    if(busy)begin error<=1;s_axi_bresp<=2;end
                end else if(aw_address==8 && write_strobe[0] && write_data[1:0]==2)error<=0;
                else if(busy)begin error<=1;s_axi_bresp<=2;end
                else case(aw_address)
                    16'h0008:if(write_strobe[0] && write_data[0]) begin
                        if(!init_done || cfg_x0>cfg_x1 || cfg_y0>cfg_y1 || cfg_x1>127 || cfg_y1>127)begin
                            error<=1;s_axi_bresp<=2;
                        end else begin
                            start_x0<=cfg_x0;start_y0<=cfg_y0;start_x1<=cfg_x1;start_y1<=cfg_y1;present<=1;
                        end
                    end
                    16'h0010:if(write_strobe[0])cfg_x0<=write_data[7:0];
                    16'h0014:if(write_strobe[0])cfg_y0<=write_data[7:0];
                    16'h0018:if(write_strobe[0])cfg_x1<=write_data[7:0];
                    16'h001c:if(write_strobe[0])cfg_y1<=write_data[7:0];
                    default:begin error<=1;s_axi_bresp<=2;end
                endcase
            end
            if(s_axi_rvalid && s_axi_rready)s_axi_rvalid<=0;
            if(s_axi_arvalid && s_axi_arready)begin
                s_axi_rvalid<=1;s_axi_rdata<=read_value;
                s_axi_rresp<=(s_axi_araddr[15] || s_axi_araddr[1:0]!=0)?2:0;
            end
        end
    end
endmodule
