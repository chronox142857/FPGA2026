`timescale 1ns/1ps
// LCD GRAM model reconstructs the image from physical SPI bytes, then compares
// every pixel with a framebuffer independently rendered from the original C font.
module tb_st7735s_text;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0;
    wire res,cs,sck,dc,mosi,bl,init_done,frame_done;
    reg [15:0] expected[0:16383],canvas[0:16383];
    reg [7:0] serial=0,command=0,pixel_hi=0;
    reg byte_dc=0,second_pixel_byte=0;
    integer bits=0,bytes=0,parameter_index=0,xs=0,xe=0,ys=0,ye=0,x=0,y=0,k,writes=0;
    st7735s_text_demo #(.CLK_HZ(1000),.SPI_HALF_CYCLES(2)) dut(
        .clk_50m(clk),.rst_n(rst_n),.pause_requests(1'b0),
        .lcd_init_done(init_done),.frame_done(frame_done),
        .lcd_rst_n(res),.lcd_cs_n(cs),.lcd_sck(sck),.lcd_dc(dc),.lcd_mosi(mosi),.lcd_bl(bl));
    always @(posedge clk) if(rst_n && dut.error) $fatal(1,"Text sent an invalid rectangle");
    always @(posedge sck) if(!cs && rst_n) begin
        if(bits==0) byte_dc=dc;
        if(dc!==byte_dc) $fatal(1,"Text byte DC changed");
        serial={serial[6:0],mosi};bits=bits+1;
    end
    always @(posedge cs) if(rst_n) begin
        if(bits!=8 || sck!==1) $fatal(1,"Text byte framing");
        if(bytes>=77) begin
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
    initial #80000000 $fatal(1,"Text rendering timeout");
    initial begin
        $readmemh("text_expected.hex",expected);
        for(k=0;k<16384;k=k+1)canvas[k]=16'hdead;
        repeat(3) @(negedge clk);rst_n=1;
        wait(frame_done);@(negedge clk);
        if(!init_done || !bl) $fatal(1,"Text completed without initialized backlight");
        if(second_pixel_byte) $fatal(1,"Incomplete final RGB565 pixel");
        for(k=0;k<16384;k=k+1)
            if(canvas[k]!==expected[k]) $fatal(1,"Text pixel %0d got %04h expected %04h",k,canvas[k],expected[k]);
        $display("PASS: TEXT all 16384 pixels match independent C-font framebuffer; %0d writes",writes);
        $finish;
    end
endmodule
