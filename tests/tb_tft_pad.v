`timescale 1ns/1ps
module tb_tft_pad;
    reg sck=0,mosi=0,cs=1;
    reg [7:0] control=0;
    wire [2:0] pins;
    wire out_sck,out_cs,readback;
    tri1 data_line;
    reg remote_drive=0,remote_data=0;
    integer i;
    assign data_line=remote_drive ? remote_data : 1'bz;
    la_tft_pad dut(.spi_sck(sck),.spi_mosi(mosi),.spi_cs_n(cs),
        .control(control),.tft_ctrl(pins),.tft_sck(out_sck),
        .tft_cs_n(out_cs),.sda(data_line),.sda_in(readback));
    task verify;
        input okay;
        input [511:0] message;
        begin if(okay!==1'b1)begin $display("FAIL tb_tft_pad: %0s",message);$finish;end end
    endtask
    initial begin
        #200;
        for(i=0;i<8;i=i+1)begin
            sck=i&1;mosi=(i>>1)&1;cs=(i>>2)&1;control=i;
            #10;
            verify(out_sck===sck && out_cs===cs,"hardware SPI routing");
            verify(data_line===mosi && readback===mosi,"hardware SDA echo");
            verify(pins===control[2:0],"DC/RES/BLK mapping");
        end
        for(i=0;i<8;i=i+1)begin
            control=8'h0f|((i&1)<<4)|(((i>>1)&1)<<5)|(((i>>2)&1)<<7);
            sck=~control[4];mosi=~control[5];cs=~control[7];
            #10;
            verify(out_sck===control[4] && out_cs===control[7],"GPIO clock/CS override");
            verify(data_line===control[5],"GPIO data output override");
            verify(pins===3'b111,"diagnostics preserve control outputs");
        end
        control=8'hcf;remote_drive=1;remote_data=0;#10;
        verify(data_line===1'b0 && readback===1'b0,"released SDA accepts panel low");
        remote_data=1;#10;
        verify(data_line===1'b1 && readback===1'b1,"released SDA accepts panel high");
        remote_drive=0;#10;
        verify(readback===1'b1,"released undriven SDA pull-up");
        control=7;sck=0;mosi=0;cs=1;#10;
        verify(out_sck===1'b0 && out_cs===1'b1 && data_line===1'b0,"return to hardware SPI");
        $display("PASS tb_tft_pad: SPI/GPIO mux, bidirectional SDA and release");
        $finish;
    end
endmodule
