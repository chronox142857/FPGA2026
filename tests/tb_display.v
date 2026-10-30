`timescale 1ns/1ps
module tb_display;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,bus_rst_n=0;
    reg [15:0] awaddr=0,araddr=0;
    reg [31:0] wdata=0;
    reg [3:0] wstrb=15;
    reg awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
    wire awready,wready,bvalid,arready,rvalid;
    wire [31:0] rdata;wire [1:0] bresp,rresp;
    wire sck,cs,mosi,dc,res,bl;wire [2:0] ctrl;
    assign dc=ctrl[0];assign res=ctrl[1];assign bl=ctrl[2];
    la_display #(.CLK_HZ(1000),.SPI_HALF_CYCLES(1)) dut(
        .clk(clk),.rst_n(bus_rst_n),.panel_reset_n(rst_n),.s_axi_awaddr(awaddr),.s_axi_awprot(3'd0),.s_axi_awvalid(awvalid),.s_axi_awready(awready),
        .s_axi_wdata(wdata),.s_axi_wstrb(wstrb),.s_axi_wvalid(wvalid),.s_axi_wready(wready),
        .s_axi_bresp(bresp),.s_axi_bvalid(bvalid),.s_axi_bready(bready),
        .s_axi_araddr(araddr),.s_axi_arprot(3'd0),.s_axi_arvalid(arvalid),.s_axi_arready(arready),
        .s_axi_rdata(rdata),.s_axi_rresp(rresp),.s_axi_rvalid(rvalid),.s_axi_rready(rready),
        .tft_sck(sck),.tft_mosi(mosi),.tft_cs_n(cs),.tft_ctrl(ctrl));
    reg [8:0] init_expected[0:76];
    reg [15:0] expected[0:16383],canvas[0:16383];
    reg [7:0] serial=0,command=0,pixel_hi=0;
    reg byte_dc=0,second_pixel_byte=0;
    integer bits=0,bytes=0,parameter_index=0,xs=0,xe=0,ys=0,ye=0,x=0,y=0,k,writes=0;
    time reset_released,sleep_finished;
    always @(posedge res)if(rst_n)reset_released=$time;
    always @(negedge cs)if(rst_n && bytes==1)
        if($time-sleep_finished<3000)$fatal(1,"Sleep Out wait shortened");
    always @(posedge cs)if(rst_n)begin
        if(!dc && serial==8'h11)begin
            if($time-reset_released<3000)$fatal(1,"Reset recovery shortened");
            sleep_finished=$time;
        end
    end
    always @(posedge sck) if(!cs && rst_n) begin
        if(bits==0) byte_dc=dc;
        if(dc!==byte_dc) $fatal(1,"Text byte DC changed");
        serial={serial[6:0],mosi};bits=bits+1;
    end
    always @(posedge cs) if(rst_n) begin
        if(bits!=8 || sck!==1) $fatal(1,"Integrated byte framing");
        if(bytes<77) begin
            if({byte_dc,serial}!==init_expected[bytes])$fatal(1,"Initialization byte %0d changed",bytes);
        end else begin
            if(!byte_dc) begin
                command=serial;parameter_index=0;second_pixel_byte=0;
                if(serial==8'h2c) begin x=xs;y=ys;end
                else if(serial!=8'h2a && serial!=8'h2b) $fatal(1,"Unexpected drawing command");
            end else if(command==8'h2a || command==8'h2b) begin
                if(command==8'h2a) case(parameter_index)
                    0:xs=serial*256;1:xs=xs+serial;2:xe=serial*256;3:xe=xe+serial;
                endcase
                else case(parameter_index)
                    0:ys=serial*256;1:ys=ys+serial;2:ye=serial*256;3:ye=ye+serial;
                endcase
                parameter_index=parameter_index+1;
                if(parameter_index>4) $fatal(1,"Too many window bytes");
            end else if(command==8'h2c) begin
                if(!second_pixel_byte) begin pixel_hi=serial;second_pixel_byte=1;end
                else begin
                    if(x<2 || x>129 || y<3 || y>130) $fatal(1,"Pixel outside visible window");
                    canvas[(y-3)*128+x-2]={pixel_hi,serial};writes=writes+1;
                    second_pixel_byte=0;
                    if(x==xe) begin x=xs;y=y+1;end else x=x+1;
                end
            end else $fatal(1,"Pixel data without RAMWR");
        end
        bytes=bytes+1;bits=0;
    end
    task address;
        input [15:0] a;
        begin @(negedge clk);awaddr=a;awvalid=1;
            @(posedge clk);while(!awready)@(posedge clk);
            @(negedge clk);awvalid=0;end
    endtask
    task data;
        input [31:0] d;input [3:0] strobe;
        begin @(negedge clk);wdata=d;wstrb=strobe;wvalid=1;
            @(posedge clk);while(!wready)@(posedge clk);
            @(negedge clk);wvalid=0;end
    endtask
    integer transactions=0;
    task write;
        input [15:0] a;input [31:0] d;input [3:0] strobe;input [1:0] response;
        begin
            if(transactions%3==0)begin data(d,strobe);address(a);end
            else if(transactions%3==1)begin address(a);data(d,strobe);end
            else fork address(a);data(d,strobe);join
            while(!bvalid)@(negedge clk);
            repeat(2)begin @(negedge clk);if(!bvalid || bresp!==response)$fatal(1,"Write %h response %d",a,bresp);end
            bready=1;@(negedge clk);bready=0;transactions=transactions+1;
        end
    endtask
    reg [31:0] last_read;
    task read;
        input [15:0] a;
        reg [31:0] value;
        begin @(negedge clk);araddr=a;arvalid=1;
            @(posedge clk);while(!arready)@(posedge clk);
            @(negedge clk);arvalid=0;while(!rvalid)@(negedge clk);
            value=rdata;
            repeat(2)begin @(negedge clk);if(!rvalid || rdata!==value || rresp!=0)$fatal(1,"Read backpressure");end
            last_read=value;rready=1;@(negedge clk);rready=0;
        end
    endtask
    task check_canvas;
        begin for(k=0;k<16384;k=k+1)
            if(canvas[k]!==expected[k])$fatal(1,"Pixel %0d got %h expected %h",k,canvas[k],expected[k]);end
    endtask
    integer file_handle,scan,page=-1;
    reg [31:0] offset,value;
    reg [511:0] expected_path;
    initial begin
        $readmemh("display_init.hex",init_expected);
        for(k=0;k<16384;k=k+1)canvas[k]=16'hdead;
        repeat(4)@(negedge clk);rst_n=1;bus_rst_n=1;
        // PS/AXI reset during panel recovery must not interrupt LCD init.
        @(posedge res);@(negedge clk);bus_rst_n=0;
        repeat(4)@(negedge clk);bus_rst_n=1;
        write(8,1,15,2);write(8,2,15,0); // PRESENT before init fails
        wait(dut.init_done);read(0);if(last_read!==32'h4c440101)$fatal(1,"Display ID");
        file_handle=$fopen("display_mmio.hex","r");if(!file_handle)$fatal(1,"No host trace");
        while(!$feof(file_handle)) begin
            scan=$fscanf(file_handle,"%h %h\n",offset,value);
            if(scan!=2)$fatal(1,"Malformed host trace");
            if(offset==32'hffffffff)begin
                wait(!dut.busy);@(negedge clk);page=page+1;
                if(value!=page)$fatal(1,"Frame ordering");
                $sformat(expected_path,"display_expected_%0d.hex",page);
                $readmemh(expected_path,expected);check_canvas;
                read(12);if(last_read!==page+1)$fatal(1,"Frame completion counter");
                $display("PASS integrated page %0d: all 16384 physical SPI pixels match ARM UI",page);
            end else begin
                write(offset[15:0],value,15,0);
                if(offset==8 && value==1 && page==-1)begin
                    write(16'h8000,32'hdeadbeef,15,2); // must not corrupt a running frame
                    write(16'h0010,127,15,2);write(8,2,15,0);
                end
            end
        end
        $fclose(file_handle);
        // Partial-byte write and an odd, one-pixel rectangle preserve neighbours.
        write(16'h8208,32'h005a0000,4'b0100,0);
        write(16'h10,5,15,0);write(16'h14,2,15,0);write(16'h18,5,15,0);write(16'h1c,2,15,0);
        write(8,1,15,0);wait(!dut.busy);@(negedge clk);
        expected[261]={expected[261][15:8],8'h5a};check_canvas;
        read(12);if(last_read!=6)$fatal(1,"Partial completion");
        write(16'h10,128,15,0);write(8,1,15,2);read(4);
        if(last_read!=5)$fatal(1,"Invalid bounds accepted");write(8,2,15,0);
        $display("PASS tb_display: production ARM UI to AXI framebuffer to proven SPI, five pages plus byte-strobe/odd rectangle, busy protection, invalid bounds, original init and 150ms waits");
        $finish;
    end
    initial #300000000 $fatal(1,"Integrated display timeout");
endmodule
