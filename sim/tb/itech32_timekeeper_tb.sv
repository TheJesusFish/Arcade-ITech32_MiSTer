`timescale 1ns/1ps
// M48T02 clock registers against MAME 0.288 timekpr.cpp: BCD rollover through
// every field (including month lengths and leap February), the ST stop bit,
// W (write: counters stop, clearing W loads them), R (read: visible bytes
// freeze, leaving R refreshes them), the MiSTer RTC load at each game load,
// and RTC following until the game first sets its own time.
module itech32_timekeeper_tb;
	logic clk = 1'b0, reset = 1'b1, new_game = 1'b0;
	logic [64:0] rtc = '0;
	logic [7:0] write_enable = '0;
	logic [63:0] write_data = '0;
	logic [63:0] read_data;
	integer checks = 0;

	// Ten clocks per "second".
	itech32_timekeeper #(.CLK_HZ(10)) dut (.*);
	always #5 clk = ~clk;

	function automatic logic [7:0] field(input int i);
		return read_data[8 * i +: 8];
	endfunction

	task automatic expect_time(input string label, input logic [7:0] control, sec, min, hour,
		day, date, month, year);
		if ({field(7), field(6), field(5), field(4), field(3), field(2), field(1), field(0)} !==
			{year, month, date, day, hour, min, sec, control})
			$fatal(1, "TIMEKEEPER_%s got %02x/%02x/%02x day %02x %02x:%02x:%02x ctl %02x",
				label, field(7), field(6), field(5), field(4), field(3), field(2), field(1),
				field(0));
		checks++;
	endtask

	// Writes avoid the clock that carries the one-second strobe, so every
	// tick below is counted by ticks().
	task automatic write_byte(input int i, input logic [7:0] value);
		@(negedge clk);
		while (dut.second) @(negedge clk);
		write_enable = 8'(1 << i);
		write_data = '0;
		write_data[8 * i +: 8] = value;
		@(negedge clk);
		write_enable = '0;
	endtask

	// Set the whole clock as a game does: W, the fields, then clear W.
	task automatic set_time(input logic [7:0] sec, min, hour, day, date, month, year);
		write_byte(0, 8'h80);
		write_byte(1, sec); write_byte(2, min); write_byte(3, hour);
		write_byte(4, day); write_byte(5, date); write_byte(6, month); write_byte(7, year);
		write_byte(0, 8'h00);
	endtask

	// Wait through n one-second strobes.
	task automatic ticks(input int n);
		repeat (n) begin
			while (!dut.second) @(negedge clk);
			@(negedge clk);
		end
	endtask

	task automatic send_rtc(input logic [7:0] sec, min, hour, date, month, year, wday);
		@(negedge clk);
		rtc = {~rtc[64], 8'h40, wday, year, month, date, hour, min, sec};
		@(negedge clk);
	endtask

	initial begin
		// MiSTer sends the RTC at core start, before the game loads.
		send_rtc(8'h58, 8'h59, 8'h23, 8'h31, 8'h12, 8'h26, 8'd4);
		repeat (2) @(negedge clk);
		reset = 1'b0;
		@(negedge clk); new_game = 1'b1; @(negedge clk); new_game = 1'b0;
		#1 expect_time("RTC_LOAD", 8'h00, 8'h58, 8'h59, 8'h23, 8'h05, 8'h31, 8'h12, 8'h26);
		// Thursday 31 Dec 2026 23:59:58 -> Friday 1 Jan 2027 00:00:00.
		ticks(2); #1;
		expect_time("NEW_YEAR", 8'h00, 8'h00, 8'h00, 8'h00, 8'h06, 8'h01, 8'h01, 8'h27);
		// Day of week wraps 7 -> 1.
		set_time(8'h59, 8'h59, 8'h23, 8'h07, 8'h28, 8'h02, 8'h27); #1;
		expect_time("SET", 8'h00, 8'h59, 8'h59, 8'h23, 8'h07, 8'h28, 8'h02, 8'h27);
		ticks(1); #1;
		expect_time("FEB_27", 8'h00, 8'h00, 8'h00, 8'h00, 8'h01, 8'h01, 8'h03, 8'h27);
		set_time(8'h59, 8'h59, 8'h23, 8'h02, 8'h28, 8'h02, 8'h28); ticks(1); #1;
		expect_time("FEB_28_LEAP", 8'h00, 8'h00, 8'h00, 8'h00, 8'h03, 8'h29, 8'h02, 8'h28);
		set_time(8'h59, 8'h59, 8'h23, 8'h02, 8'h30, 8'h04, 8'h28); ticks(1); #1;
		expect_time("APRIL", 8'h00, 8'h00, 8'h00, 8'h00, 8'h03, 8'h01, 8'h05, 8'h28);
		set_time(8'h59, 8'h59, 8'h23, 8'h02, 8'h30, 8'h05, 8'h28); ticks(1); #1;
		expect_time("MAY_30", 8'h00, 8'h00, 8'h00, 8'h00, 8'h03, 8'h31, 8'h05, 8'h28);
		set_time(8'h59, 8'h59, 8'h23, 8'h02, 8'h31, 8'h12, 8'h99); ticks(1); #1;
		expect_time("CENTURY", 8'h00, 8'h00, 8'h00, 8'h00, 8'h03, 8'h01, 8'h01, 8'h00);
		set_time(8'h09, 8'h19, 8'h09, 8'h02, 8'h09, 8'h09, 8'h09); ticks(1); #1;
		expect_time("DIGIT_CARRY", 8'h00, 8'h10, 8'h19, 8'h09, 8'h02, 8'h09, 8'h09, 8'h09);
		// MAME's masked increment keeps the high bits of hours and date.
		set_time(8'h59, 8'h59, 8'hc5, 8'h02, 8'h49, 8'h09, 8'h09); ticks(1); #1;
		expect_time("MASKED", 8'h00, 8'h00, 8'h00, 8'hc6, 8'h02, 8'h49, 8'h09, 8'h09);

		// ST stops the oscillator; clearing it restarts.
		set_time(8'h80, 8'h00, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30); ticks(3); #1;
		expect_time("STOPPED", 8'h00, 8'h80, 8'h00, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30);
		set_time(8'h00, 8'h00, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30); ticks(3); #1;
		expect_time("RUNNING", 8'h00, 8'h03, 8'h00, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30);

		// R freezes the visible bytes; the counters keep running and leaving
		// R shows them.
		write_byte(0, 8'h40); ticks(2); #1;
		expect_time("READ_FROZEN", 8'h40, 8'h03, 8'h00, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30);
		write_byte(0, 8'h00); #1;
		expect_time("READ_RELEASED", 8'h00, 8'h05, 8'h00, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30);
		// W stops the counters while the game writes; a byte written without
		// W shows until the next tick replaces it.
		write_byte(0, 8'h80); ticks(2); write_byte(2, 8'h45); #1;
		expect_time("WRITE_HELD", 8'h80, 8'h05, 8'h45, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30);
		write_byte(0, 8'h00); ticks(1); #1;
		expect_time("WRITE_LOADED", 8'h00, 8'h06, 8'h45, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30);
		write_byte(3, 8'h01); #1;
		expect_time("STRAY_WRITE", 8'h00, 8'h06, 8'h45, 8'h01, 8'h02, 8'h01, 8'h06, 8'h30);
		ticks(1); #1;
		expect_time("STRAY_REPLACED", 8'h00, 8'h07, 8'h45, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30);

		// The game set its own time above: later RTC updates are ignored.
		send_rtc(8'h00, 8'h10, 8'h08, 8'h15, 8'h07, 8'h26, 8'd3); #1;
		expect_time("RTC_IGNORED", 8'h00, 8'h07, 8'h45, 8'h12, 8'h02, 8'h01, 8'h06, 8'h30);
		// A new game load restarts from the RTC and follows its updates.
		@(negedge clk); new_game = 1'b1; @(negedge clk); new_game = 1'b0; #1;
		expect_time("RELOAD", 8'h00, 8'h00, 8'h10, 8'h08, 8'h04, 8'h15, 8'h07, 8'h26);
		ticks(5);
		send_rtc(8'h00, 8'h11, 8'h08, 8'h15, 8'h07, 8'h26, 8'd3); #1;
		expect_time("RTC_FOLLOWED", 8'h00, 8'h00, 8'h11, 8'h08, 8'h04, 8'h15, 8'h07, 8'h26);
		// R also holds the visible bytes through an RTC update.
		write_byte(0, 8'h40);
		send_rtc(8'h30, 8'h11, 8'h08, 8'h15, 8'h07, 8'h26, 8'd3); #1;
		expect_time("RTC_UNDER_READ", 8'h40, 8'h00, 8'h11, 8'h08, 8'h04, 8'h15, 8'h07, 8'h26);
		write_byte(0, 8'h00); #1;
		expect_time("RTC_AFTER_READ", 8'h00, 8'h30, 8'h11, 8'h08, 8'h04, 8'h15, 8'h07, 8'h26);

		if (checks != 23) $fatal(1, "TIMEKEEPER_CASE_COUNT %0d", checks);
		$display("TIMEKEEPER_PASS checks=%0d", checks);
		$finish;
	end
endmodule
