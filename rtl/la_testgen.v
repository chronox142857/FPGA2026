`timescale 1ns/1ps
// Output roles: UART TX=0; I2C SCL=0 SDA=1; SPI SCK=0 MOSI=1 MISO=2 CSn=3.
// I2C outputs use open-drain output enables: external pullups are required.
module la_testgen #(parameter CLOCK_HZ=50000000)(
    input clk,input rst_n,input [1:0] mode,input [1:0] spi_mode,input inject_error,
    output reg [3:0] data,output reg [3:0] drive
);
    localparam UART_DIV=CLOCK_HZ/115200;
    localparam BUS_DIV=CLOCK_HZ/400000;
    reg [15:0] timer;
    reg [8:0] phase;
    reg [1:0] old_mode, old_spi_mode;
    reg [7:0] value;
    reg uart_bit;
    reg [7:0] i2c_byte;
    reg scl,sda;
    reg [5:0] q;
    reg sck,csn,mosi,miso;
    always @* begin
        data=4'hf; drive=0; uart_bit=1; i2c_byte=8'ha0;
        scl=1;sda=1;sck=spi_mode[1];csn=1;mosi=0;miso=0;q=0;
        if(mode==1) begin
            drive=1;
            if(phase<80) begin
                case(phase % 10)
                    0:uart_bit=0;
                    9:uart_bit=!(inject_error && phase/10==3);
                    default:uart_bit=value[(phase%10)-1];
                endcase
            end
            data[0]=uart_bit;
        end else if(mode==2) begin
            // Four phases per bit; explicit start, address, ACK, data, ACK, stop.
            if(phase==1) sda=0;
            else if(phase>=2 && phase<74) begin
                q=(phase-2)/4;
                scl=((phase-2)%4==1 || (phase-2)%4==2);
                if(q<8) sda=i2c_byte[7-q];
                else if(q==8 || q==17) sda=0;
                else sda=value[16-q];
            end else if(phase==74) begin scl=0;sda=0;end
            else if(phase==75) begin scl=1;sda=0;end
            data[1:0]=0; drive[0]=!scl; drive[1]=!sda;
        end else if(mode==3) begin
            drive=4'hf;
            if(phase<=64) begin
                csn=0; q=phase/4;
                sck=spi_mode[1] ^ (phase[1:0]>=2);
                if(spi_mode[0]) begin
                    mosi=(phase<2)?0:value[7-(((phase-2)&31)/4)];
                    miso=(phase<2)?0:(~value[7-(((phase-2)&31)/4)]);
                end else begin mosi=value[7-(q%8)];miso=~value[7-(q%8)]; end
            end
            data={csn,miso,mosi,sck};
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin timer<=0;phase<=0;value<=8'h55;old_mode<=0;old_spi_mode<=0;end
        else if(mode!=old_mode || spi_mode!=old_spi_mode) begin
            timer<=0;phase<=0;value<=8'h55;old_mode<=mode;old_spi_mode<=spi_mode;
        end else if(mode!=0) begin
            if(timer==((mode==1)?UART_DIV-1:BUS_DIV-1)) begin
                timer<=0;
                if(phase==127) begin phase<=0;value<=value+8'h13;end
                else begin phase<=phase+1'b1; if(mode==1 && phase<79 && phase%10==9) value<=value+8'h13;end
            end else timer<=timer+1'b1;
        end
    end
endmodule
