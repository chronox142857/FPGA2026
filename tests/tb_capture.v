`timescale 1ns/1ps
module tb_capture;
    reg clk=0;always #10 clk=~clk;
    reg rst_n=0,arm=0,cancel=0;
    reg [7:0] probe=0,mask=255,level_mask=1,level_value=1;
    reg [5:0] divider=1;
    reg [1:0] trigger=0,pre=0;
    reg [2:0] channel=0;
    wire [2:0] state;
    wire we;wire [4:0] addr,start_index,trigger_index;wire [5:0] valid_count;
    wire [7:0] data,active_mask;wire [5:0] active_divider;
    wire [63:0] first_tick,trigger_tick,first_edge,last_edge;wire [31:0] edge_count;
    reg host_en=0;reg [31:0] host_addr=0;wire [31:0] host_data;
    la_capture #(.ADDR_WIDTH(5)) dut(.clk(clk),.rst_n(rst_n),.probe(probe),.arm(arm),.cancel(cancel),
        .cfg_mask(mask),.cfg_divider(divider),.cfg_trigger(trigger),.cfg_channel(channel),
        .cfg_level_mask(level_mask),.cfg_level_value(level_value),.cfg_pretrigger(pre),
        .state(state),.mem_we(we),.mem_addr(addr),.mem_data(data),.start_index(start_index),.valid_count(valid_count),
        .trigger_index(trigger_index),.first_tick(first_tick),.trigger_tick(trigger_tick),
        .active_mask(active_mask),.active_divider(active_divider),.stat_channel(3'd0),
        .edge_count(edge_count),.first_edge_tick(first_edge),.last_edge_tick(last_edge));
    la_sample_ram #(.ADDR_WIDTH(5)) ram(.clk(clk),.wr_en(we),.wr_addr(addr),.wr_data(data),
        .host_clk(clk),.host_rst(!rst_n),.host_en(host_en),.host_addr(host_addr),.host_data(host_data));
    reg [7:0] q0=0,q1=0,q2=0;
    reg [7:0] history[0:99999];
    integer writes=0,cycles=0,last_write=-1,edge_total=0;
    reg checking=0;reg [7:0] expected_mask;
    integer expected_div;
    always @(posedge clk) begin
        if(!rst_n)begin q0<=0;q1<=0;q2<=0;end
        else begin q0<=probe;q1<=q0;q2<=q1;end
        cycles=cycles+1;
        if(checking && we) begin
            if(data !== (q2 & expected_mask)) $fatal(1,"sync/sample mismatch %h expected %h",data,q2&expected_mask);
            if(addr !== (writes%32))$fatal(1,"write address mismatch");
            if(last_write>=0 && cycles-last_write!=expected_div)$fatal(1,"divider mismatch");
            if(writes && ((data^history[writes-1])&1))edge_total=edge_total+1;
            history[writes]=data;writes=writes+1;last_write=cycles;
        end
    end
    integer stim_count=0;
    always @(negedge clk) if(rst_n)begin stim_count=stim_count+1;if(stim_count%7==0)probe=probe+1;end
    task pulse_arm;
        begin @(negedge clk);arm=1;@(negedge clk);arm=0;end
    endtask
    task check_run;
        input integer div_value,pre_value,trig_value;
        integer timeout,i,physical,position;reg [7:0] got;
        begin
            @(negedge clk);writes=0;last_write=-1;edge_total=0;checking=1;
            divider=div_value;pre=pre_value;trigger=trig_value;
            case(pre_value)0:mask=8'hff;1:mask=8'h55;2:mask=8'h0f;3:mask=8'h01;endcase
            expected_mask=mask;expected_div=div_value;
            pulse_arm;
            // Mutate pending configuration. Current run must remain unchanged.
            repeat(5)@(negedge clk);divider=3;mask=0;pre=0;
            if(div_value==1 && pre_value==0)pulse_arm; // busy ARM must be ignored
            timeout=0;while(state!=3 && timeout<100000)begin @(negedge clk);timeout=timeout+1;end
            if(state!=3)$fatal(1,"capture timeout div=%d pre=%d trigger=%d",div_value,pre_value,trig_value);
            if(valid_count!=32 || trigger_index!=pre_value*8)$fatal(1,"metadata count/index mismatch");
            if(trigger_tick-first_tick!=pre_value*8*div_value)$fatal(1,"timestamp mismatch");
            if(active_divider!=div_value || active_mask!=expected_mask)$fatal(1,"configuration not latched");
            if(edge_count!=edge_total)$fatal(1,"edge count mismatch");
            if(writes<32)$fatal(1,"not enough writes");
            for(i=0;i<32;i=i+1)begin
                physical=(start_index+i)%32;
                @(negedge clk);host_en=1;host_addr=physical&32'hfffffffc;
                @(negedge clk);got=host_data>>(8*(physical%4));
                position=writes-32+i;
                if(got!==history[position])$fatal(1,"ring/last-write mismatch i=%d got=%h expected=%h",i,got,history[position]);
            end
            @(negedge clk);host_en=0;checking=0;
            repeat(3)@(negedge clk);
            if(we)$fatal(1,"write after DONE");
        end
    endtask
    integer n;
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(n=0;n<100;n=n+1)begin
            case(n%5)
                0:check_run(1,n%4,(n/4)%4);
                1:check_run(2,n%4,(n/4)%4);
                2:check_run(5,n%4,(n/4)%4);
                3:check_run(10,n%4,(n/4)%4);
                4:check_run(50,n%4,(n/4)%4);
            endcase
        end
        divider=3;mask=255;pulse_arm;repeat(3)@(negedge clk);
        if(state!=4)$fatal(1,"bad divider accepted");
        divider=1;mask=1;trigger=1;channel=7;pulse_arm;repeat(3)@(negedge clk);
        if(state!=4)$fatal(1,"disabled trigger channel accepted");
        mask=255;channel=0;trigger=1;pre=3;checking=0;pulse_arm;
        @(negedge clk);cancel=1;@(negedge clk);cancel=0;repeat(3)@(negedge clk);
        if(state!=0 || valid_count!=0)$fatal(1,"cancel failed");
        trigger=0;pre=0;pulse_arm;repeat(8)@(negedge clk);
        cancel=1;@(negedge clk);cancel=0;repeat(3)@(negedge clk);
        if(state!=0 || valid_count!=0 || we)$fatal(1,"cancel during POST failed");
        $display("PASS tb_capture: 100 acquisitions, ring, sampling, metadata, cancel, validation");$finish;
    end
endmodule
