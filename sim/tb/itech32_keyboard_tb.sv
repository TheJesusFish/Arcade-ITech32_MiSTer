`timescale 1ns/1ps
// MAME default keys as MiSTer joystick words. Every mapped key sets and clears
// exactly its own bit; an event counts once per ps2_key[10] toggle; unmapped
// and wrong-prefix codes (Right Ctrl, keypad arrows) do nothing; the OSD clear
// drops held keys.
module itech32_keyboard_tb;
	logic clk = 1'b0, reset = 1'b1, clear = 1'b0;
	logic [10:0] ps2_key = 11'd0;
	logic [11:0] joystick_0, joystick_1;
	integer checks = 0;

	itech32_keyboard dut (.*);
	always #5 clk = ~clk;

	// One hps_io key event: flip the toggle with the new pressed/code bits.
	task automatic key(input logic [8:0] code, input logic pressed);
		@(negedge clk);
		ps2_key = {~ps2_key[10], pressed, code};
		@(negedge clk);
	endtask

	task automatic expect_keys(input string label, input logic [11:0] p1, input logic [11:0] p2);
		if (joystick_0 !== p1 || joystick_1 !== p2)
			$fatal(1, "KEYBOARD_%s p1=%03x p2=%03x expected %03x %03x",
				label, joystick_0, joystick_1, p1, p2);
		checks++;
	endtask

	// {code, player, bit}: CONF_STR J order R, L, D, U, B1..B6, Start, Coin.
	localparam int KEYS = 22;
	localparam logic [8:0] CODE [KEYS] = '{
		9'h174, 9'h16b, 9'h172, 9'h175, 9'h014, 9'h011, 9'h029, 9'h012, 9'h01a, 9'h022,
		9'h016, 9'h02e,
		9'h034, 9'h023, 9'h02b, 9'h02d, 9'h01c, 9'h01b, 9'h015, 9'h01d, 9'h01e, 9'h036};
	localparam int PLAYER [KEYS] = '{0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
		1, 1, 1, 1, 1, 1, 1, 1, 1, 1};
	localparam int BIT [KEYS] = '{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11,
		0, 1, 2, 3, 4, 5, 6, 7, 10, 11};

	initial begin
		repeat (2) @(negedge clk);
		reset = 1'b0;
		@(negedge clk);
		expect_keys("IDLE", 12'h000, 12'h000);
		for (int k = 0; k < KEYS; k++) begin
			key(CODE[k], 1'b1);
			expect_keys("PRESS", PLAYER[k] == 0 ? 12'(1 << BIT[k]) : 12'h000,
				PLAYER[k] == 1 ? 12'(1 << BIT[k]) : 12'h000);
			// The toggle is an edge, not a level: holding it changes nothing.
			repeat (3) @(negedge clk);
			expect_keys("HOLD", PLAYER[k] == 0 ? 12'(1 << BIT[k]) : 12'h000,
				PLAYER[k] == 1 ? 12'(1 << BIT[k]) : 12'h000);
			key(CODE[k], 1'b0);
			expect_keys("RELEASE", 12'h000, 12'h000);
		end
		// Right Ctrl/Alt (0xE0 forms) and keypad arrows (no 0xE0) are not mapped.
		key(9'h114, 1'b1); key(9'h111, 1'b1); key(9'h074, 1'b1); key(9'h075, 1'b1);
		expect_keys("UNMAPPED", 12'h000, 12'h000);
		// A changed code without a toggle edge is ignored.
		@(negedge clk); ps2_key[9:0] = {1'b1, 9'h175}; repeat (2) @(negedge clk);
		expect_keys("NO_EDGE", 12'h000, 12'h000);
		// Diagonals and both players at once.
		key(9'h175, 1'b1); key(9'h174, 1'b1); key(9'h02d, 1'b1); key(9'h01c, 1'b1);
		expect_keys("COMBINED", 12'h009, 12'h018);
		key(9'h175, 1'b0);
		expect_keys("PARTIAL_RELEASE", 12'h001, 12'h018);
		// The OSD clear drops every held key; its own releases never arrive.
		@(negedge clk); clear = 1'b1; @(negedge clk); clear = 1'b0;
		expect_keys("CLEAR", 12'h000, 12'h000);
		key(9'h02e, 1'b1);
		@(negedge clk); reset = 1'b1; @(negedge clk); reset = 1'b0;
		expect_keys("RESET", 12'h000, 12'h000);

		if (checks != 73) $fatal(1, "KEYBOARD_CASE_COUNT %0d", checks);
		$display("KEYBOARD_PASS checks=%0d keys=%0d", checks, KEYS);
		$finish;
	end
endmodule
