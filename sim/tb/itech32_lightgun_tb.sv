`timescale 1ns/1ps
// Light-gun aim point: centred at reset, one pixel per mouse count (PS/2 +Y
// up is screen up), clamped to 384x256, d-pad at 5/16 pixel per tick, stick
// speed from its deflection with a dead zone, and absolute sticks spanning
// the screen.
module itech32_lightgun_tb;
	logic clk = 1'b0, reset = 1'b1, tick = 1'b0, absolute_stick = 1'b0;
	logic mouse_valid = 1'b0;
	logic signed [8:0] mouse_dx = '0, mouse_dy = '0;
	logic signed [7:0] stick_x = '0, stick_y = '0;
	logic [3:0] dpad = '0;
	logic [8:0] x;
	logic [7:0] y;
	integer checks = 0;

	itech32_lightgun dut (.*);
	always #5 clk = ~clk;

	task automatic expect_xy(input string label, input logic [8:0] ex, input logic [7:0] ey);
		#1;
		if (x !== ex || y !== ey)
			$fatal(1, "LIGHTGUN_%s x=%0d y=%0d expected %0d %0d", label, x, y, ex, ey);
		checks++;
	endtask

	task automatic mouse(input integer dx, input integer dy);
		@(negedge clk);
		mouse_dx = 9'(dx); mouse_dy = 9'(dy); mouse_valid = 1'b1;
		@(negedge clk);
		mouse_valid = 1'b0;
	endtask

	task automatic ticks(input integer n);
		repeat (n) begin
			@(negedge clk); tick = 1'b1;
			@(negedge clk); tick = 1'b0;
		end
	endtask

	initial begin
		repeat (2) @(negedge clk);
		reset = 1'b0;
		expect_xy("RESET_CENTRE", 9'd192, 8'd128);
		mouse(10, 5);
		expect_xy("MOUSE", 9'd202, 8'd123);
		mouse(-255, -200);
		expect_xy("MOUSE_CLAMP_LEFT_BOTTOM", 9'd0, 8'd255);
		mouse(255, 255); mouse(255, 255);
		expect_xy("MOUSE_CLAMP_RIGHT_TOP", 9'd383, 8'd0);
		// D-pad left and down: 5/16 pixel per tick, 16 ticks = 5 pixels.
		dpad = 4'b0110;
		ticks(16);
		expect_xy("DPAD", 9'd378, 8'd5);
		dpad = 4'b0000;
		// The stick wins over the d-pad: +64 is 4/16 per tick.
		dpad = 4'b0010; stick_x = 8'sd64;
		ticks(8);
		expect_xy("STICK_OVER_DPAD", 9'd380, 8'd5);
		// Inside the dead zone the stick is centred and the d-pad applies.
		stick_x = 8'sd15; dpad = 4'b1000;
		ticks(16);
		expect_xy("DEAD_ZONE_DPAD", 9'd380, 8'd0);
		stick_x = 8'sd0; dpad = 4'b0000;
		// Without a tick nothing moves.
		repeat (20) @(negedge clk);
		expect_xy("HOLD", 9'd380, 8'd0);
		// Absolute stick: -128..127 spans the screen.
		absolute_stick = 1'b1; stick_x = -8'sd128; stick_y = -8'sd128;
		@(negedge clk);
		expect_xy("ABS_TOP_LEFT", 9'd0, 8'd0);
		stick_x = 8'sd127; stick_y = 8'sd127;
		@(negedge clk);
		expect_xy("ABS_BOTTOM_RIGHT", 9'd382, 8'd255);
		stick_x = 8'sd0; stick_y = 8'sd0;
		@(negedge clk);
		expect_xy("ABS_CENTRE", 9'd192, 8'd128);
		// Absolute mode ignores the mouse.
		mouse(20, 0);
		expect_xy("ABS_IGNORES_MOUSE", 9'd192, 8'd128);
		absolute_stick = 1'b0;
		@(negedge clk); reset = 1'b1; @(negedge clk); reset = 1'b0;
		expect_xy("RESET_AGAIN", 9'd192, 8'd128);

		if (checks != 13) $fatal(1, "LIGHTGUN_CASE_COUNT %0d", checks);
		$display("LIGHTGUN_PASS checks=%0d", checks);
		$finish;
	end
endmodule
