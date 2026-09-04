`timescale 1ns/1ps

module itech32_game_selector_tb;
	logic clk = 1'b0;
	logic write = 1'b0;
	logic [7:0] data = 8'd0;
	logic timekill_mode;
	logic bloodstorm_mode;

	itech32_game_selector dut (
		.clk(clk), .write(write), .data(data),
		.timekill_mode(timekill_mode), .bloodstorm_mode(bloodstorm_mode)
	);

	always #5 clk = ~clk;

	task automatic select(input logic [7:0] value);
		@(negedge clk);
		data = value;
		write = 1'b1;
		@(negedge clk);
		write = 1'b0;
		#1;
	endtask

	initial begin
		#1;
		assert ({bloodstorm_mode, timekill_mode} == 2'b00)
			else $fatal(1, "SELECTOR_POWERUP");
		select(8'h01);
		assert ({bloodstorm_mode, timekill_mode} == 2'b01)
			else $fatal(1, "SELECTOR_TIMEKILL");
		select(8'h02);
		assert ({bloodstorm_mode, timekill_mode} == 2'b10)
			else $fatal(1, "SELECTOR_BLOODSTORM");
		select(8'h03);
		assert ({bloodstorm_mode, timekill_mode} == 2'b00)
			else $fatal(1, "SELECTOR_SFTM_FALLBACK_03");
		select(8'hff);
		assert ({bloodstorm_mode, timekill_mode} == 2'b00)
			else $fatal(1, "SELECTOR_FALLBACK");
		$display("GAME_SELECTOR_PASS profiles=3 sftm_fallbacks=2");
		$finish;
	end
endmodule
