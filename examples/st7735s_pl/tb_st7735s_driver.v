`timescale 1ns/1ps
// Simulation: serial decoding, initialization, rectangle, point and rejection.
module tb_st7735s_driver;
    reg clk = 1'b0;
    always #10 clk = ~clk;
    reg rst_n = 1'b0;
    reg bl_enable = 1'b0;
    reg req_valid = 1'b0;
    reg [7:0] x0 = 8'd0, y0 = 8'd0, x1 = 8'd0, y1 = 8'd0;
    reg [15:0] color = 16'd0;
    reg raw_valid = 1'b0, raw_dc = 1'b0;
    reg [7:0] raw_data = 8'd0;
    wire raw_ready, raw_done;
    wire req_ready, init_done, req_done, req_error, busy;
    wire lcd_rst_n, lcd_cs_n, lcd_sck, lcd_dc, lcd_mosi, lcd_bl;
    reg [8:0] received [0:33000];
    integer received_count = 0;
    integer bit_count = 0;
    reg [7:0] shift_byte = 8'd0;
    reg captured_dc = 1'b0;
    integer k;
    time last_cs_rise = 0;
    time last_cs_fall = 0;
    time last_sck_rise = 0;
    time last_sck_fall = 0;

    st7735s_driver #(
        .CLK_HZ(1000), .RESET_LOW_MS(2),
        .RESET_RECOVERY_MS(2), .SLEEP_OUT_MS(3)
    ) dut (
        .clk(clk), .rst_n(rst_n), .bl_enable(bl_enable),
        .req_valid(req_valid), .req_ready(req_ready),
        .x0(x0), .y0(y0), .x1(x1), .y1(y1), .color(color),
        .raw_valid(raw_valid), .raw_ready(raw_ready),
        .raw_dc(raw_dc), .raw_data(raw_data), .raw_done(raw_done),
        .init_done(init_done), .req_done(req_done),
        .req_error(req_error), .busy(busy),
        .lcd_rst_n(lcd_rst_n), .lcd_cs_n(lcd_cs_n),
        .lcd_sck(lcd_sck), .lcd_dc(lcd_dc),
        .lcd_mosi(lcd_mosi), .lcd_bl(lcd_bl)
    );

    always @(negedge lcd_cs_n) begin
        if (last_cs_rise != 0 && ($time - last_cs_rise < 40))
            $fatal(1, "CS high pulse shorter than 40 ns");
        bit_count = 0;
        shift_byte = 8'd0;
        captured_dc = lcd_dc;
        last_cs_fall = $time;
        last_sck_rise = 0;
        last_sck_fall = 0;
    end
    always @(posedge lcd_sck) if (!lcd_cs_n) begin
        if (last_sck_rise == 0) begin
            if ($time - last_cs_fall < 45)
                $fatal(1, "CS setup shorter than 45 ns");
        end else if ($time - last_sck_rise < 66)
            $fatal(1, "SCK period shorter than 66 ns");
        if (last_sck_fall != 0 && $time - last_sck_fall < 15)
            $fatal(1, "SCK low pulse shorter than 15 ns");
        last_sck_rise = $time;
        shift_byte = {shift_byte[6:0], lcd_mosi};
        bit_count = bit_count + 1;
        if (lcd_dc !== captured_dc) $fatal(1, "D/C changed during byte");
    end
    always @(negedge lcd_sck) if (!lcd_cs_n) begin
        if ($time - last_sck_rise < 15)
            $fatal(1, "SCK high pulse shorter than 15 ns");
        last_sck_fall = $time;
    end
    always @(posedge lcd_cs_n) if (rst_n) begin
        if ($time - last_sck_fall < 45)
            $fatal(1, "CS hold shorter than 45 ns");
        if (bit_count != 8) $fatal(1, "Expected 8 serial bits, got %0d", bit_count);
        received[received_count] = {captured_dc, shift_byte};
        received_count = received_count + 1;
        last_cs_rise = $time;
    end

    task expect_byte;
        input integer index;
        input [8:0] value;
        begin
            if (received[index] !== value)
                $fatal(1, "byte %0d: got %03h, expected %03h",
                       index, received[index], value);
        end
    endtask

    task request_rect;
        input [7:0] ax0, ay0, ax1, ay1;
        input [15:0] rgb565;
        begin
            @(negedge clk);
            while (!req_ready) @(negedge clk);
            x0 = ax0; y0 = ay0; x1 = ax1; y1 = ay1;
            color = rgb565; req_valid = 1'b1;
            @(negedge clk);
            req_valid = 1'b0;
            while (!req_done) @(negedge clk);
        end
    endtask

    initial begin
        #40000000 $fatal(1, "Simulation timeout");
    end

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1'b1;
        wait (init_done);
        @(negedge clk);
        if (received_count != 74) $fatal(1, "Init byte count %0d", received_count);
        expect_byte(0, 9'h011);
        expect_byte(35, 9'h036);
        expect_byte(36, 9'h1C8);
        expect_byte(71, 9'h03A);
        expect_byte(72, 9'h105);
        expect_byte(73, 9'h029);
        if (lcd_bl !== 1'b0) $fatal(1, "Backlight enabled too early");

        request_rect(8'd1, 8'd2, 8'd2, 8'd3, 16'hF800);
        if (req_error) $fatal(1, "Valid rectangle rejected");
        if (received_count != 93) $fatal(1, "Rectangle byte count %0d", received_count);
        expect_byte(74, 9'h02A);
        expect_byte(75, 9'h100);
        expect_byte(76, 9'h101);
        expect_byte(77, 9'h100);
        expect_byte(78, 9'h102);
        expect_byte(79, 9'h02B);
        expect_byte(80, 9'h100);
        expect_byte(81, 9'h122);
        expect_byte(82, 9'h100);
        expect_byte(83, 9'h123);
        expect_byte(84, 9'h02C);
        for (k = 0; k < 4; k = k + 1) begin
            expect_byte(85 + 2*k, 9'h1F8);
            expect_byte(86 + 2*k, 9'h100);
        end

        bl_enable = 1'b1;
        #1;
        if (lcd_bl !== 1'b1) $fatal(1, "Backlight did not turn on");
        request_rect(8'd127, 8'd127, 8'd127, 8'd127, 16'h001F);
        if (received_count != 106) $fatal(1, "Point byte count %0d", received_count);
        expect_byte(95, 9'h17F);
        expect_byte(100, 9'h19F);
        expect_byte(104, 9'h100);
        expect_byte(105, 9'h11F);

        request_rect(8'd0, 8'd0, 8'd128, 8'd0, 16'hFFFF);
        if (!req_error) $fatal(1, "Invalid rectangle was not rejected");
        if (received_count != 106) $fatal(1, "Invalid request sent data");

        request_rect(8'd0, 8'd0, 8'd127, 8'd127, 16'hFFFF);
        if (req_error) $fatal(1, "Full-screen fill was rejected");
        if (received_count != 32885)
            $fatal(1, "Full-screen byte count %0d", received_count);
        expect_byte(106, 9'h02A);
        expect_byte(116, 9'h02C);
        expect_byte(32883, 9'h1FF);
        expect_byte(32884, 9'h1FF);

        @(negedge clk);
        raw_dc = 1'b0; raw_data = 8'h20; raw_valid = 1'b1;
        @(negedge clk);
        raw_valid = 1'b0;
        while (!raw_done) @(negedge clk);
        if (received_count != 32886) $fatal(1, "Raw byte count %0d", received_count);
        expect_byte(32885, 9'h020);
        repeat (2) @(negedge clk);
        if (raw_done) $fatal(1, "Raw completion must be a one-cycle pulse");
        raw_dc = 1'b1; raw_data = 8'h5A; raw_valid = 1'b1;
        @(negedge clk);
        raw_valid = 1'b0;
        while (!raw_done) @(negedge clk);
        if (received_count != 32887) $fatal(1, "Second raw byte not completed");
        expect_byte(32886, 9'h15A);
        repeat (2) @(negedge clk);
        if (raw_done) $fatal(1, "Second raw completion did not clear");
        $display("PASS: ST7735S init, timing, rectangle, point, invalid request, full screen, raw bytes and completion pulses");
        $finish;
    end
endmodule
