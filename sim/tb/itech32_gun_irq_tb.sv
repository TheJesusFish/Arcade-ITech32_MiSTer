`timescale 1ns/1ps
// Must Shoot TV gun interrupts against MAME's gun_interrupt: level 5 at lines
// with (vpos & 0x1f) == 0 and level 6 at 16, each held until its clear read,
// level 6 outranking 5, nothing while disabled.
module itech32_gun_irq_tb;
	logic clk = 1'b0, reset = 1'b1, enable = 1'b1;
	logic line_start = 1'b0, ack5 = 1'b0, ack6 = 1'b0;
	logic [9:0] vpos = '0;
	logic [2:0] irq_level;
	integer checks = 0;

	itech32_gun_irq dut (.*);
	always #5 clk = ~clk;

	task automatic line(input integer v);
		@(negedge clk); vpos = 10'(v); line_start = 1'b1;
		@(negedge clk); line_start = 1'b0;
	endtask

	task automatic expect_level(input string label, input logic [2:0] level);
		#1;
		if (irq_level !== level)
			$fatal(1, "GUN_IRQ_%s level=%0d expected %0d", label, irq_level, level);
		checks++;
	endtask

	task automatic ack(input logic five, input logic six);
		@(negedge clk); ack5 = five; ack6 = six;
		@(negedge clk); ack5 = 1'b0; ack6 = 1'b0;
	endtask

	initial begin
		repeat (2) @(negedge clk);
		reset = 1'b0;
		expect_level("RESET", 3'd0);
		for (int v = 1; v < 16; v++) line(v);
		expect_level("QUIET_LINES", 3'd0);
		line(16);
		expect_level("LINE16", 3'd6);
		ack(1'b0, 1'b1);
		expect_level("ACK6", 3'd0);
		line(32);
		expect_level("LINE32", 3'd5);
		line(48);
		expect_level("BOTH_6_WINS", 3'd6);
		ack(1'b0, 1'b1);
		expect_level("STILL_5", 3'd5);
		ack(1'b1, 1'b0);
		expect_level("ACK5", 3'd0);
		// The raster position alone does not raise them; only a line start.
		@(negedge clk); vpos = 10'd64;
		repeat (3) @(negedge clk);
		expect_level("NO_LINE_START", 3'd0);
		line(64);
		line(208);
		expect_level("LINE208", 3'd6);
		@(negedge clk); enable = 1'b0;
		@(negedge clk);
		expect_level("DISABLED_CLEARS", 3'd0);
		line(0);
		expect_level("DISABLED", 3'd0);

		if (checks != 12) $fatal(1, "GUN_IRQ_CASE_COUNT %0d", checks);
		$display("GUN_IRQ_PASS checks=%0d", checks);
		$finish;
	end
endmodule
