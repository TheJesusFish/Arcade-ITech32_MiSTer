`timescale 1ns/1ps

// Trackball emulation: hand-computed directed cases (orientation, 1/16-count
// units, one count per tick, saturation, dead zone, d-pad fallback, stick
// symmetry, enable) followed by a randomized run checked every clock against
// an integer reference model of the same specification.
module itech32_trackball_tb;
    logic clk = 1'b0, reset = 1'b1, enable = 1'b1, tick = 1'b0;
    logic [1:0] speed = 2'd2;
    logic mouse_valid = 1'b0;
    logic signed [8:0] mouse_dx = '0, mouse_dy = '0;
    logic signed [7:0] stick_x = '0, stick_y = '0;
    logic [3:0] dpad = '0;
    logic [3:0] count_x, count_y;
    integer checks = 0;

    itech32_trackball dut (.*);
    always #5 clk = ~clk;

    // ---------------------------------------------------------------- model
    int model_px = 0, model_py = 0, model_cx = 0, model_cy = 0;
    logic model_check = 1'b0;

    function automatic int clamp(input int value);
        return value > 1023 ? 1023 : value < -1023 ? -1023 : value;
    endfunction

    function automatic int rate(input int stick, input logic pos, input logic neg);
        int magnitude = stick < 0 ? -stick : stick;
        if (magnitude > 15) return stick;
        if (pos && !neg) return 96;
        if (neg && !pos) return -96;
        return 0;
    endfunction

    function automatic int stick_sixteenths(input int r, input int gain);
        int magnitude = ((r < 0 ? -r : r) << gain) >> 4;
        return r < 0 ? -magnitude : magnitude;
    endfunction

    always @(posedge clk) begin
        int sx, sy, rx, ry;
        logic up_x, dn_x, up_y, dn_y;
        if (reset || !enable) begin
            model_px = 0; model_py = 0;
            if (reset) begin model_cx = 0; model_cy = 0; end
        end else begin
            up_x = tick && model_px >= 16; dn_x = tick && model_px <= -16;
            up_y = tick && model_py >= 16; dn_y = tick && model_py <= -16;
            sx = model_px - (up_x ? 16 : 0) + (dn_x ? 16 : 0);
            sy = model_py - (up_y ? 16 : 0) + (dn_y ? 16 : 0);
            if (mouse_valid) begin
                sx -= int'(mouse_dx) * (4 << speed);
                sy -= int'(mouse_dy) * (4 << speed);
            end
            if (tick) begin
                rx = rate(int'(stick_x), dpad[0], dpad[1]);
                ry = rate(int'(stick_y), dpad[2], dpad[3]);
                sx -= stick_sixteenths(rx, int'(speed));
                sy += stick_sixteenths(ry, int'(speed));
            end
            model_px = clamp(sx); model_py = clamp(sy);
            model_cx = (model_cx + (up_x ? 1 : 0) - (dn_x ? 1 : 0)) & 15;
            model_cy = (model_cy + (up_y ? 1 : 0) - (dn_y ? 1 : 0)) & 15;
        end
    end

    always @(negedge clk) if (model_check) begin
        if (count_x !== 4'(model_cx) || count_y !== 4'(model_cy))
            $fatal(1, "TRACKBALL_MODEL x=%0d/%0d y=%0d/%0d", count_x, model_cx, count_y, model_cy);
        checks++;
    end

    // ------------------------------------------------------------- helpers
    task automatic mouse(input int dx, input int dy);
        @(negedge clk);
        mouse_dx = 9'(dx); mouse_dy = 9'(dy); mouse_valid = 1'b1;
        @(negedge clk);
        mouse_valid = 1'b0;
    endtask

    task automatic ticks(input int n);
        repeat (n) begin
            @(negedge clk); tick = 1'b1;
            @(negedge clk); tick = 1'b0;
        end
    endtask

    task automatic expect_counts(input string label, input logic [3:0] x, input logic [3:0] y);
        @(negedge clk);
        if (count_x !== x || count_y !== y)
            $fatal(1, "TRACKBALL_%s x=%h y=%h expected x=%h y=%h", label, count_x, count_y, x, y);
        checks++;
    endtask

    task automatic restart();
        @(negedge clk); reset = 1'b1;
        @(negedge clk); reset = 1'b0;
    endtask

    initial begin
        repeat (3) @(negedge clk);
        reset = 1'b0;
        expect_counts("RESET", 4'h0, 4'h0);

        // 100%: one mickey = one count. Right decreases X; forward decreases Y.
        speed = 2'd2;
        mouse(3, 2);
        expect_counts("NO_TICK_NO_COUNT", 4'h0, 4'h0);
        ticks(1); expect_counts("ONE_PER_TICK", 4'hf, 4'hf);
        ticks(1); expect_counts("SECOND_TICK", 4'he, 4'he);
        ticks(5); expect_counts("DRAINED", 4'hd, 4'he);
        mouse(-3, -2); ticks(6); expect_counts("RETURN", 4'h0, 4'h0);

        // 25%: four mickeys per count; fractions stay pending.
        restart(); speed = 2'd0;
        mouse(-3, 0); ticks(2); expect_counts("QUARTER_FRACTION", 4'h0, 4'h0);
        mouse(-1, 0); ticks(2); expect_counts("QUARTER_WHOLE", 4'h1, 4'h0);

        // Saturation: a huge flick holds at most 1023/16 = 63 whole counts,
        // released one per tick.
        restart(); speed = 2'd3;
        mouse(-255, 0); ticks(10); expect_counts("RATE_LIMIT", 4'(10), 4'h0);
        ticks(100); expect_counts("SATURATED", 4'(63), 4'h0);

        // Stick dead zone, then symmetric deflection at 100%: 40 -> 10/16.
        restart(); speed = 2'd2;
        stick_x = 8'sd15; ticks(20); expect_counts("DEAD_ZONE", 4'h0, 4'h0);
        stick_x = 8'sd40; ticks(16); expect_counts("STICK_RIGHT", 4'(-9), 4'h0);
        restart(); stick_x = -8'sd40; ticks(16); expect_counts("STICK_LEFT", 4'(9), 4'h0);
        // Stick toward the player increases Y.
        restart(); stick_x = 0; stick_y = 8'sd64; ticks(4); expect_counts("STICK_BACK", 4'h0, 4'h3);
        stick_y = 0;

        // D-pad stands in for 96 while the stick is centered; opposite
        // directions cancel; a deflected stick wins.
        // 96 at 100% is 24/16 per tick: no count on tick 1, then one per tick.
        restart(); dpad = 4'b0001; ticks(8); expect_counts("DPAD_RIGHT", 4'(-7), 4'h0);
        restart(); dpad = 4'b0011; ticks(8); expect_counts("DPAD_CANCEL", 4'h0, 4'h0);
        // Full left stick (31/16 per tick) overrides d-pad right.
        restart(); dpad = 4'b0001; stick_x = -8'sd127; ticks(4); expect_counts("STICK_OVER_DPAD", 4'(3), 4'h0);
        dpad = 4'b0000; stick_x = 0;

        // Disabled: input discarded, counts held, pending cleared.
        restart(); mouse(-2, 0); ticks(1); expect_counts("BEFORE_DISABLE", 4'h1, 4'h0);
        enable = 1'b0; mouse(-5, -5); ticks(10); expect_counts("DISABLED", 4'h1, 4'h0);
        enable = 1'b1; ticks(10); expect_counts("PENDING_CLEARED", 4'h1, 4'h0);

        // Randomized run against the reference model.
        restart();
        model_check = 1'b1;
        for (int cycle = 0; cycle < 200000; cycle++) begin
            @(negedge clk);
            tick = ($urandom % 7) == 0;
            mouse_valid = ($urandom % 11) == 0;
            mouse_dx = 9'($urandom); mouse_dy = 9'($urandom);
            if (($urandom % 500) == 0) stick_x = 8'($urandom);
            if (($urandom % 500) == 0) stick_y = 8'($urandom);
            if (($urandom % 300) == 0) dpad = 4'($urandom);
            if (($urandom % 2000) == 0) speed = 2'($urandom);
            if (($urandom % 5000) == 0) enable = !enable;
            if (stick_x == -8'sd128) stick_x = -8'sd127;
            if (stick_y == -8'sd128) stick_y = -8'sd127;
        end
        @(negedge clk);
        model_check = 1'b0;
        $display("TRACKBALL_PASS checks=%0d", checks);
        $finish;
    end
endmodule
