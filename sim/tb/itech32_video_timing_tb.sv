`timescale 1ns/1ps

module itech32_video_timing_tb;
	logic clk;
	logic reset;
	logic ce_pixel;
	logic [9:0] htotal, hblank_start, hblank_end, hsync_start;
	logic [9:0] vtotal, vblank_start, vblank_end, vsync_start;
	logic [9:0] hpos, vpos;
	logic hblank, vblank, hsync, vsync;
	integer cycle;
	integer hb_count, vb_count, hs_count, vs_count;
	logic [9:0] held_h, held_v;

	always #5 clk = ~clk;

	itech32_video_timing dut (
		.clk(clk), .reset(reset), .ce_pixel(ce_pixel),
		.htotal(htotal), .hblank_start(hblank_start), .hblank_end(hblank_end),
		.hsync_start(hsync_start), .vtotal(vtotal),
		.vblank_start(vblank_start), .vblank_end(vblank_end), .vsync_start(vsync_start),
		.hpos(hpos), .vpos(vpos), .hblank(hblank), .vblank(vblank),
		.hsync(hsync), .vsync(vsync)
	);

	initial begin
		clk = 1'b0;
		reset = 1'b1;
		ce_pixel = 1'b1;
		htotal = 10'd64;
		hblank_start = 10'd48;
		hblank_end = 10'd8;
		hsync_start = 10'd56;
		vtotal = 10'd5;
		vblank_start = 10'd4;
		vblank_end = 10'd1;
		vsync_start = 10'd4;
		hb_count = 0; vb_count = 0; hs_count = 0; vs_count = 0;
		repeat (3) @(posedge clk);
		@(negedge clk); reset = 1'b0;

		for (cycle = 0; cycle < 320; cycle = cycle + 1) begin
			@(posedge clk); #1;
			hb_count = hb_count + hblank;
			vb_count = vb_count + vblank;
			hs_count = hs_count + hsync;
			vs_count = vs_count + vsync;
		end
		if (hpos != 0 || vpos != 0) $fatal(1, "raster wrap %0d,%0d", hpos, vpos);
		if (hb_count != 120 || hs_count != 160)
			$fatal(1, "horizontal intervals blank=%0d sync=%0d", hb_count, hs_count);
		if (vb_count != 128 || vs_count != 256)
			$fatal(1, "vertical intervals blank=%0d sync=%0d", vb_count, vs_count);

		held_h = hpos; held_v = vpos; ce_pixel = 1'b0;
		repeat (3) @(posedge clk);
		#1;
		if (hpos != held_h || vpos != held_v) $fatal(1, "CE hold failed");

		// With the raster held at 0,0, the original wrapped pulses are asserted.
		// Reprogram starts so the new intervals exclude 0,0: output must retain
		// the old geometry until the next core edge, then change exactly once.
		if (!hsync || !vsync) $fatal(1, "wrapped sync setup not asserted at 0,0");
		@(negedge clk);
		hsync_start = 10'd2;
		vsync_start = 10'd1;
		#1;
		if (!hsync || !vsync) $fatal(1, "sync programming bypassed local stage");
		@(posedge clk); #1;
		if (hsync || vsync) $fatal(1, "sync programming did not commit after one core clock");

		$display("PASS programmable video timing, fixed 32-pixel/4-line wrapped sync intervals, and one-clock sync commit");
		$finish;
	end
endmodule
