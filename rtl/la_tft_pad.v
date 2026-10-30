`timescale 1ns/1ps
// Hardware SPI for frames; slow GPIO override for half-duplex SDA readback.
// GPIO[2:0]=DC/RES/BLK, [3]=override, [4]=SCK, [5]=SDA, [6]=HiZ, [7]=CSn.
module la_tft_pad(
    input spi_sck, input spi_mosi, input spi_cs_n,
    input [7:0] control,
    output [2:0] tft_ctrl,
    output tft_sck, output tft_cs_n,
    inout sda, output sda_in
);
    wire override_mode=control[3];
    wire sda_out=override_mode ? control[5] : spi_mosi;
    wire sda_hiz=override_mode && control[6];
    assign tft_ctrl=control[2:0];
    assign tft_sck=override_mode ? control[4] : spi_sck;
    assign tft_cs_n=override_mode ? control[7] : spi_cs_n;
    IOBUF data_pad(.I(sda_out),.T(sda_hiz),.O(sda_in),.IO(sda));
endmodule
