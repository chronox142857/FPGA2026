`timescale 1ns/1ps
module tb_loopback;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,arm=0,cancel=0;reg [1:0] mode=0,spi_mode=0;
    reg inject_error=0;
    wire [3:0] data,drive;tri1 [3:0] pins;
    genvar g;generate for(g=0;g<4;g=g+1)begin:pads assign pins[g]=drive[g]?data[g]:1'bz;end endgenerate
    la_testgen gen(.clk(clk),.rst_n(rst_n),.mode(mode),.spi_mode(spi_mode),.inject_error(inject_error),.data(data),.drive(drive));
    wire [2:0] state;wire we;wire [14:0] addr,start_index,trigger_index;
    wire [15:0] valid_count;wire [7:0] sample,active_mask;wire [5:0] active_div;
    wire [63:0] first_tick,trigger_tick,first_edge,last_edge;wire [31:0] edges;
    la_capture dut(.clk(clk),.rst_n(rst_n),.probe({4'hf,pins}),.arm(arm),.cancel(cancel),
        .cfg_mask(8'hff),.cfg_divider(6'd10),.cfg_trigger(2'd0),.cfg_channel(3'd0),
        .cfg_level_mask(8'd1),.cfg_level_value(8'd0),.cfg_pretrigger(2'd0),
        .state(state),.mem_we(we),.mem_addr(addr),.mem_data(sample),.start_index(start_index),
        .valid_count(valid_count),.trigger_index(trigger_index),.first_tick(first_tick),.trigger_tick(trigger_tick),
        .active_mask(active_mask),.active_divider(active_div),.stat_channel(3'd0),.edge_count(edges),
        .first_edge_tick(first_edge),.last_edge_tick(last_edge));
    integer fd=0,n,i;
    always @(posedge clk)if(we && fd)$fdisplay(fd,"%02x",sample);
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(n=1;n<=7;n=n+1)begin
            mode=(n==7)?1:(n<=2)?n:3;spi_mode=(n>2 && n<7)?n-3:0;inject_error=(n==7);
            case(n)
                1:fd=$fopen("loop_uart.hex","w");
                2:fd=$fopen("loop_i2c.hex","w");
                3:fd=$fopen("loop_spi0.hex","w");
                4:fd=$fopen("loop_spi1.hex","w");
                5:fd=$fopen("loop_spi2.hex","w");
                6:fd=$fopen("loop_spi3.hex","w");
                7:fd=$fopen("loop_uart_error.hex","w");
            endcase
            repeat(500)@(negedge clk);arm=1;@(negedge clk);arm=0;
            i=0;while(state!=3 && i<400000)begin @(negedge clk);i=i+1;end
            if(state!=3 || valid_count!=32768)$fatal(1,"loopback timeout");
            $fclose(fd);fd=0;cancel=1;@(negedge clk);cancel=0;
            repeat(10)@(negedge clk);
        end
        $display("PASS tb_loopback: raw RTL UART/I2C/SPI0..3 captures exported");$finish;
    end
endmodule
