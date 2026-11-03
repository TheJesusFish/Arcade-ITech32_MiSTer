`timescale 1ns/1ps
// Crosshair overlay on a synthetic raster (CE_PIXEL every six clocks, 384x256
// active within blanking). Every active pixel is sampled at the next CE_PIXEL,
// as the MiSTer mixer does, and compared with a reference: arms of six pixels
// around each aim point, the aim point itself clear, gun 1 over gun 2,
// disabled guns invisible, and the RGB never delayed.
module itech32_crosshair_tb;
	localparam int H_ACTIVE = 384, H_TOTAL = 400, V_ACTIVE = 256, V_TOTAL = 262;
	logic clk = 1'b0, ce_pixel = 1'b0, hblank = 1'b1, vblank = 1'b1;
	logic [23:0] rgb_in = '0;
	logic [1:0] enable = 2'b11;
	logic [8:0] gun1_x = 9'd100, gun2_x = 9'd383;
	logic [7:0] gun1_y = 8'd50, gun2_y = 8'd255;
	logic [23:0] rgb_out;
	integer checks = 0, hits1, hits2;
	// Crosshair pixels at the mixer's sample edges, counted outside the
	// frame task (this Verilator loses writes made inside the timed task).
	integer total1 = 0, total2 = 0;
	always @(posedge clk)
		if (ce_pixel) begin
			if (rgb_out == 24'hff2020) total1 <= total1 + 1;
			if (rgb_out == 24'h2090ff) total2 <= total2 + 1;
		end

	itech32_crosshair dut (.*);
	always #5 clk = ~clk;

	function automatic int distance(input int a, input int b);
		return a > b ? a - b : b - a;
	endfunction

	function automatic logic on_cross(input int col, input int row, input int x, input int y);
		return (row == y && col != x && distance(col, x) <= 6) ||
			(col == x && row != y && distance(row, y) <= 6);
	endfunction

	task automatic frame(input string label);
		int col_q, row_q;
		logic active_q;
		logic [23:0] expected;
		for (int v = 0; v < V_TOTAL; v++)
			for (int h = 0; h < H_TOTAL; h++) begin
				// One raster position per CE_PIXEL; the board updates RGB and
				// blanking at that edge.
				@(negedge clk);
				ce_pixel = 1'b1;
				@(posedge clk); #1;
				ce_pixel = 1'b0;
				// The mixer samples the previous position at this edge.
				if (v > 0 || h > 0) begin
					if (active_q) begin
						expected = (enable[0] && on_cross(col_q, row_q, gun1_x, gun1_y)) ? 24'hff2020 :
							(enable[1] && on_cross(col_q, row_q, gun2_x, gun2_y)) ? 24'h2090ff :
							{8'(col_q), 8'(row_q), 8'h5a};
						if (rgb_out !== expected)
							$fatal(1, "CROSSHAIR_%s col=%0d row=%0d got=%06x expected=%06x",
								label, col_q, row_q, rgb_out, expected);
						checks++;
					end
				end
				hblank = h >= H_ACTIVE;
				vblank = v >= V_ACTIVE;
				rgb_in = {8'(h), 8'(v), 8'h5a};
				active_q = !hblank && !vblank;
				col_q = h; row_q = v;
				repeat (5) @(posedge clk);
			end
	endtask

	initial begin
		hits1 = total1; hits2 = total2;
		frame("FRAME1");
		@(negedge clk);
		hits1 = total1 - hits1; hits2 = total2 - hits2;
		if (hits1 != 24 || hits2 != 12) $fatal(1, "CROSSHAIR_HITS %0d %0d", hits1, hits2);
		// Overlap: gun 1 wins; disabled gun 2 shows nothing.
		gun2_x = 9'd100; gun2_y = 8'd52;
		hits1 = total1; hits2 = total2;
		frame("OVERLAP");
		@(negedge clk);
		hits1 = total1 - hits1; hits2 = total2 - hits2;
		if (hits1 != 24 || hits2 != 15) $fatal(1, "CROSSHAIR_OVERLAP %0d %0d", hits1, hits2);
		enable = 2'b01;
		hits1 = total1; hits2 = total2;
		frame("ONE_GUN");
		@(negedge clk);
		hits1 = total1 - hits1; hits2 = total2 - hits2;
		if (hits1 != 24 || hits2 != 0) $fatal(1, "CROSSHAIR_ONE_GUN %0d %0d", hits1, hits2);
		enable = 2'b00;
		hits1 = total1; hits2 = total2;
		frame("OFF");
		@(negedge clk);
		hits1 = total1 - hits1; hits2 = total2 - hits2;
		if (hits1 != 0) $fatal(1, "CROSSHAIR_OFF %0d", hits1);
		$display("CROSSHAIR_PASS pixels=%0d", checks);
		$finish;
	end
endmodule
