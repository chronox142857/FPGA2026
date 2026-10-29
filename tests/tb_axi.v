`timescale 1ns/1ps
module tb_axi;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0;
    reg [11:0] awaddr=0,araddr=0;reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    reg [31:0] wdata=0;reg [3:0] wstrb=15;
    wire awready,wready,bvalid,arready,rvalid;wire [31:0] rdata;wire [1:0] bresp,rresp,leds;
    wire [3:0] test_io;wire [31:0] bram_data;
    la_axi #(.ADDR_WIDTH(5),.DEBOUNCE_CYCLES(3)) dut(
        .clk(clk),.rst_n(rst_n),.s_axi_awaddr(awaddr),.s_axi_awprot(3'b0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(3'b0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
        .probe(8'h55),.keys_n(2'b11),.leds(leds),.test_io(test_io),
        .bram_clk(clk),.bram_rst(!rst_n),.bram_en(1'b0),.bram_addr(32'b0),.bram_we(4'b0),.bram_wrdata(32'b0),.bram_rddata(bram_data));
    task address;
        input [11:0] addr;
        begin @(negedge clk);awaddr=addr;awvalid=1;@(posedge clk);while(!awready)@(posedge clk);@(negedge clk);awvalid=0;end
    endtask
    task value;
        input [31:0] v;input [3:0] strb;
        begin @(negedge clk);wdata=v;wstrb=strb;wvalid=1;@(posedge clk);while(!wready)@(posedge clk);@(negedge clk);wvalid=0;end
    endtask
    task response;
        begin
            while(!bvalid)@(negedge clk);
            repeat(5)begin @(negedge clk);if(!bvalid || bresp!=0)$fatal(1,"B backpressure");end
            bready=1;@(negedge clk);bready=0;
        end
    endtask
    task read;
        input [11:0] addr;input [31:0] expected;
        begin
            @(negedge clk);araddr=addr;arvalid=1;@(posedge clk);while(!arready)@(posedge clk);
            @(negedge clk);arvalid=0;
            while(!rvalid)@(negedge clk);
            repeat(4)begin @(negedge clk);if(!rvalid || rdata!==expected || rresp!=0)$fatal(1,"read %h got=%h expected=%h",addr,rdata,expected);end
            rready=1;@(negedge clk);rready=0;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        read(0,32'h4c410101);
        address('h0c);repeat(7)@(negedge clk);value(32'h37,1);response;read('h0c,'h37);
        value(32'h12,1);repeat(7)@(negedge clk);address('h0c);response;read('h0c,'h12);
        fork address('h0c);value(32'hffffffff,4'b0010);join
        response;read('h0c,'h12); // byte strobe must not overwrite low byte
        fork address('h0c);value(32'hff,1);join response;
        fork address('h04);value(1,1);join response;
        repeat(60)@(negedge clk);read('h08,3);read('h28,32);read('h40,255);
        fork address('h04);value(2,1);join response;read('h08,0);
        $display("PASS tb_axi: independent AW/W, backpressure, strobes, arm/cancel");$finish;
    end
    initial begin #10000000;$fatal(1,"AXI timeout");end
endmodule
