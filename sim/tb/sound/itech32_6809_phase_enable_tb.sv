// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module itech32_6809_phase_enable_tb;

	logic       clk = 1'b0;
	logic       reset = 1'b1;
	logic       ce_8m = 1'b1;
	logic       hold = 1'b0;
	logic       ce_e;
	logic       ce_q;
	logic       ce_cpu_2m;
	logic [1:0] phase;

	integer e_count = 0;
	integer q_count = 0;
	logic   expect_q = 1'b0;

	always #5 clk = ~clk;

	itech32_6809_phase_enable dut (
		.clk       (clk),
		.reset     (reset),
		.ce_8m     (ce_8m),
		.hold      (hold),
		.ce_e      (ce_e),
		.ce_q      (ce_q),
		.ce_cpu_2m (ce_cpu_2m),
		.phase     (phase)
	);

	always @(posedge clk) begin
		if (!reset) begin
			if (ce_e && ce_q)
				$fatal(1, "E and Q enables overlapped");
			if (ce_cpu_2m != ce_e)
				$fatal(1, "2 MHz cycle enable must track E");

			if (ce_e) begin
				if (expect_q)
					$fatal(1, "E repeated before Q");
				e_count <= e_count + 1;
				expect_q <= 1'b1;
			end

			if (ce_q) begin
				if (!expect_q)
					$fatal(1, "Q occurred before E");
				q_count <= q_count + 1;
				expect_q <= 1'b0;
			end
		end
	end

	initial begin
		integer e_before;
		integer q_before;
		logic [1:0] held_phase;

		repeat (3) @(posedge clk);
		@(negedge clk);
		reset = 1'b0;

		// Sixteen accepted 8 MHz enables must make four 2 MHz cycles.
		repeat (16) @(posedge clk);
		#1;
		if (e_count != 4 || q_count != 4 || phase != 2'b00)
			$fatal(1, "bad divide-by-four result: E=%0d Q=%0d phase=%0d",
			       e_count, q_count, phase);

		// A memory wait freezes the complete E/Q state, not just E.
		@(negedge clk);
		hold = 1'b1;
		held_phase = phase;
		e_before = e_count;
		q_before = q_count;
		repeat (7) @(posedge clk);
		#1;
		if (phase != held_phase || e_count != e_before || q_count != q_before)
			$fatal(1, "hold did not freeze the E/Q generator");

		@(negedge clk);
		hold = 1'b0;
		repeat (4) @(posedge clk);
		#1;
		if (e_count != e_before + 1 || q_count != q_before + 1)
			$fatal(1, "phase generator did not resume cleanly after hold");

		// No input CE means no phase progress.
		@(negedge clk);
		ce_8m = 1'b0;
		held_phase = phase;
		e_before = e_count;
		q_before = q_count;
		repeat (5) @(posedge clk);
		#1;
		if (phase != held_phase || e_count != e_before || q_count != q_before)
			$fatal(1, "phase advanced without ce_8m");

		@(negedge clk);
		ce_8m = 1'b1;
		repeat (8) @(posedge clk);
		#1;
		if (e_count != e_before + 2 || q_count != q_before + 2)
			$fatal(1, "phase generator frequency changed after CE pause");

		$display("PASS: 6809 E/Q phase generator (E=%0d Q=%0d)", e_count, q_count);
		$finish;
	end

endmodule
