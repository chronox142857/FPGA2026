`timescale 1ns/1ps
module tb_st7735s_readback;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,start=0,slave_enable=1,slave_drive=0,slave_data=0;
    wire busy,done,cs_n,sck,dc,sda_out,sda_hiz;
    tri sda;
    pullup(sda);
    assign sda=sda_hiz?1'bz:sda_out;
    assign sda=slave_drive?slave_data:1'bz;
    wire [2:0] flags;
    wire [31:0] raw_id,raw_power,raw_madctl,raw_colmod;
    integer command_bits=0,read_bits=0,response_bit=0,transactions=0;
    reg [7:0] received_command=0;
    reg [31:0] response;

    st7735s_readback #(.HALF_CYCLES(4)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.sda_in(sda),
        .busy(busy),.done(done),.cs_n(cs_n),.sck(sck),.dc(dc),
        .sda_out(sda_out),.sda_hiz(sda_hiz),.pad_flags(flags),
        .raw_id(raw_id),.raw_power(raw_power),.raw_madctl(raw_madctl),.raw_colmod(raw_colmod));
    always @(negedge cs_n) if(rst_n) begin
        command_bits=0;read_bits=0;response_bit=0;received_command=0;
    end
    always @(posedge sck) if(!cs_n && rst_n) begin
        if(command_bits<8) begin
            if(dc!==0 || sda_hiz!==0) $fatal(1,"Command sampled with wrong direction/DC");
            received_command={received_command[6:0],sda};
            command_bits=command_bits+1;
            if(command_bits==8) begin
                case(received_command)
                    8'h04:response=32'h12345678;
                    8'h0a:response=32'h9abcdef0;
                    8'h0b:response=32'hc8010203;
                    8'h0c:response=32'h05060708;
                    default:$fatal(1,"Unexpected read command");
                endcase
            end
        end else begin
            if(dc!==1 || sda_hiz!==1) $fatal(1,"FPGA not released during response");
            read_bits=read_bits+1;
        end
    end
    always @(negedge sck) if(!cs_n && rst_n && command_bits==8) begin
        if(!sda_hiz) $fatal(1,"SDA not released by final command falling edge");
        if(response_bit<32) begin
            slave_data=response[31-response_bit];slave_drive=slave_enable;
            response_bit=response_bit+1;
        end else slave_drive=0;
    end
    always @(posedge cs_n) begin
        slave_drive=0;
        if(rst_n && command_bits!=0) begin
            if(command_bits!=8 || read_bits!=32) $fatal(1,"Read transaction length");
            transactions=transactions+1;
        end
    end
    initial begin #1000000 $fatal(1,"Readback test timeout");end
    initial begin
        repeat(3) @(negedge clk);rst_n=1;start=1;
        wait(done);@(negedge clk);
        if(busy || flags!==3'b110 || transactions!=4) $fatal(1,"Readback status/self-test");
        if(raw_id!==32'h12345678 || raw_power!==32'h9abcdef0 ||
           raw_madctl!==32'hc8010203 || raw_colmod!==32'h05060708)
            $fatal(1,"Raw response lost or misaligned");
        repeat(20) @(negedge clk);
        if(transactions!=4) $fatal(1,"One-shot readback restarted");
        rst_n=0;slave_enable=0;transactions=0;command_bits=0;
        repeat(3) @(negedge clk);rst_n=1;
        wait(done);@(negedge clk);
        if(raw_id!==32'hffffffff || raw_power!==32'hffffffff ||
           raw_madctl!==32'hffffffff || raw_colmod!==32'hffffffff)
            $fatal(1,"Unanswered floating response was not preserved");
        if(flags!==3'b110 || transactions!=4) $fatal(1,"Second probe completion");
        $display("PASS: READBACK command turn-around, four raw streams, one-shot and no-response case");
        $finish;
    end
endmodule
