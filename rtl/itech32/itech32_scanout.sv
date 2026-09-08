// SPDX-License-Identifier: GPL-2.0-or-later
// One-line-ahead framebuffer reader for the ITech32 512x1024x16 video memory.
`timescale 1ns/1ps

// This small RAM helper intentionally shares the scanout source file so its
// inference template cannot drift away from the only client.
/* verilator lint_off DECLFILENAME */
module itech32_line_buffer #(
	parameter integer LINE_WORDS = 128,
	parameter integer ADDR_WIDTH = (LINE_WORDS <= 2) ? 1 : $clog2(LINE_WORDS)
) (
	input  logic                  clk,
	input  logic                  write_enable,
	input  logic [ADDR_WIDTH-1:0] write_addr,
	input  logic [63:0]           write_data,
	input  logic                  read_enable,
	input  logic [ADDR_WIDTH-1:0] read_addr,
	output logic [63:0]           read_data
);
	(* ramstyle = "M10K, no_rw_check" *) logic [63:0] memory [0:LINE_WORDS-1];
	always_ff @(posedge clk) begin
		if (write_enable)
			memory[write_addr] <= write_data;
		if (read_enable)
			read_data <= memory[read_addr];
	end
endmodule
/* verilator lint_on DECLFILENAME */

module itech32_scanout #(
	parameter integer LINE_PIXELS = 384,
	parameter integer ROW_WORDS = (LINE_PIXELS + 6) / 4
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        timekill_mode,
	input  logic        ce_pixel,
	input  logic [9:0]  hpos,
	input  logic [9:0]  vpos,
	input  logic        hblank,
	input  logic        vblank,
	input  logic [9:0]  htotal,
	input  logic [9:0]  hblank_end,
	input  logic [9:0]  vtotal,
	input  logic [9:0]  vblank_start,
	input  logic [9:0]  vblank_end,
	input  logic [8:0]  display_xorigin,
	input  logic [9:0]  display_yorigin,
	input  logic [8:0]  display_xorigin2,
	input  logic [9:0]  display_yorigin2,
	input  logic [8:0]  display_xscroll2,
	input  logic [9:0]  display_yscroll2,

	// One request fetches the complete active linear window, qword-aligned at the
	// programmed source origin. MAME masks only the first source coordinate and
	// then walks linearly, so a 384-pixel line beginning near the end of a source
	// row legitimately continues into the next row. The low two origin bits can
	// add three pixels, making 97 qwords the exact worst case. The request remains
	// asserted until accepted; returned data beats cannot be backpressured and
	// therefore write directly into the inactive line RAM.
	output logic        fb_req,
	output logic [19:0] fb_addr,
	input  logic        fb_accept,
	input  logic        fb_data_valid,
	input  logic [63:0] fb_rdata,
	input  logic        fb_last,

	output logic [14:0] palette_addr,
	output logic [15:0] pixel_data,
	output logic        pixel_valid,
	output logic        underflow
);

	localparam integer FETCH_W = (ROW_WORDS <= 2) ? 1 : $clog2(ROW_WORDS);
	localparam logic [9:0] LINE_PIXELS_LIMIT = LINE_PIXELS[9:0];
	logic        buffer0_valid, buffer1_valid;
	logic [9:0]  buffer0_vtag, buffer1_vtag;
	logic [8:0]  buffer0_xorigin, buffer1_xorigin;
	logic [9:0]  buffer0_yorigin, buffer1_yorigin;
	logic [8:0]  buffer0_xorigin2, buffer1_xorigin2;
	logic [9:0]  buffer0_yorigin2, buffer1_yorigin2;
	logic [9:0]  buffer0_yscroll2, buffer1_yscroll2;

	logic                 fetch_busy;
	logic                 fetch_issued;
	logic                 fetch_target;
	logic                 fetch_plane;
	logic [FETCH_W-1:0]   fetch_index;
	logic [9:0]           fetch_y;
	logic [9:0]           fetch_y2;
	logic [9:0]           fetch_vtag;
	logic [8:0]           fetch_xorigin;
	logic [8:0]           fetch_xorigin2;
	logic [9:0]           fetch_yorigin;
	logic [9:0]           fetch_yorigin2;
	logic [9:0]           fetch_yscroll2;
	logic [9:0]           next_vpos;
	logic                 next_vblank;
	logic [9:0]           next_display_y;
	// One-pixel-old descriptors are identical throughout a raster line.  Keeping
	// the descriptor in this local stage splits vtotal/vblank arithmetic from the
	// tag retry and fetch-register enables without returning to an hpos-zero-only
	// launch policy.
	logic                 prefetch_visible_q;
	logic [9:0]           prefetch_vtag_q;
	logic [9:0]           prefetch_display_y_q;
	logic [9:0]           prefetch_yorigin_q;
	logic [9:0]           prefetch_yorigin2_q;
	logic [9:0]           prefetch_yscroll2_q;
	logic [8:0]           prefetch_xorigin_q;
	logic [8:0]           prefetch_xorigin2_q;
	// Pixel enables are separated by several clk cycles.  Capture the complete
	// descriptor on those intervening fabric edges so the pixel-enable edge only
	// sees local registers, not the programmable vertical wrap arithmetic.
	logic       prefetch_visible_calc_q;
	logic [9:0] prefetch_vtag_calc_q;
	logic [9:0] prefetch_display_y_calc_q;
	logic [9:0] prefetch_yorigin_calc_q;
	logic [9:0] prefetch_yorigin2_calc_q;
	logic [9:0] prefetch_yscroll2_calc_q;
	logic [8:0] prefetch_xorigin_calc_q;
	logic [8:0] prefetch_xorigin2_calc_q;
	logic                 previous_vblank;
	logic [9:0]           frame_first_vtag_d;
	logic [9:0]           frame_second_vtag_d;
	logic                 frame_first_visible_d;
	logic                 frame_second_visible_d;
	// The frame-start descriptor is deliberately preserved as a timing boundary.
	// Vblank geometry is programmable but stable for many raster clocks; it does
	// not need to share the single cycle that enables and initializes a line fetch.
	logic [9:0] frame_first_vtag_q;
	logic [9:0] frame_second_vtag_q;
	logic       frame_first_visible_q;
	logic       frame_second_visible_q;
	logic [9:0] frame_vblank_start_q;
	logic [9:0] frame_vblank_end_q;
	logic [9:0] frame_first_y_q;
	logic [9:0] frame_second_y_q;
	logic [9:0] frame_first_y2_q;
	logic [9:0] frame_second_y2_q;
	logic [8:0] frame_xorigin_q;
	logic [8:0] frame_xorigin2_q;
	logic [8:0] frame_xscroll2_q;
	logic [9:0] frame_yorigin_q;
	logic [9:0] frame_yorigin2_q;
	logic [9:0] frame_yscroll2_q;
	logic                 frame_first_buffered;
	logic [9:0]           display_x;
	// Upper address bits are intentionally unused only in reduced-size tests.
	/* verilator lint_off UNUSEDSIGNAL */
	logic [9:0]           read_window_offset;
	logic [9:0]           read_window_offset2;
	/* verilator lint_on UNUSEDSIGNAL */
	logic [1:0]           read_lane_q;
	logic [1:0]           read_lane2_q;
	logic [15:0]          selected_word_raw;
	logic [15:0]          selected_pixel;
	logic [63:0]          selected_line;
	logic [63:0]          selected_line2;
	logic [15:0]          selected_word_raw2;
	logic [15:0]          selected_pixel2;
	logic [63:0]          line_buffer0_q, line_buffer1_q;
	logic [63:0]          line_buffer0_plane2_q, line_buffer1_plane2_q;
	logic                 current_in_buffer0;
	logic                 prefetch_line_buffered;
	logic                 display_buffer_valid, display_buffer_select;
	logic [9:0]           display_vpos_after_tick;
	logic [9:0] display_vpos_after_tick_q;
	logic       vblank_local_q;
	logic [9:0]           read_hpos;
	// Only INDEX_W low bits address the parameterized line RAM. Upper bits are
	// intentionally discarded (and are visible only in reduced-size test builds).
	/* verilator lint_off UNUSEDSIGNAL */
	logic [9:0]           read_display_x;
	/* verilator lint_on UNUSEDSIGNAL */
	logic                 buffer0_write_enable, buffer1_write_enable;
	logic                 buffer0_plane2_write_enable, buffer1_plane2_write_enable;
	logic [8:0]           frame_effective_xorigin2;
	logic                 buffer0_matches_live, buffer1_matches_live;
	logic                 buffer0_matches_prefetch, buffer1_matches_prefetch;
	logic                 buffer0_matches_frame_first, buffer1_matches_frame_first;
	logic [9:0]           fetch_aligned_x;
	logic [9:0]           fetch_beat_x;
	logic [9:0]           fetch_row;
	logic                 fetch_guard_beat;
	logic [63:0]          fetch_write_data;

	function automatic logic interval_contains(
		input logic [9:0] position,
		input logic [9:0] first,
		input logic [9:0] last
	);
		if (first > last)
			interval_contains = (position >= first) || (position < last);
		else
			interval_contains = (position >= first) && (position < last);
	endfunction

	assign buffer0_write_enable = fetch_busy && fetch_issued &&
		fb_data_valid && !fetch_target && !fetch_plane;
	assign buffer1_write_enable = fetch_busy && fetch_issued &&
		fb_data_valid && fetch_target && !fetch_plane;
	assign buffer0_plane2_write_enable = timekill_mode && fetch_busy && fetch_issued &&
		fb_data_valid && !fetch_target && fetch_plane;
	assign buffer1_plane2_write_enable = timekill_mode && fetch_busy && fetch_issued &&
		fb_data_valid && fetch_target && fetch_plane;
	// MAME allocates guard rows outside each logical 512x1024 plane and fills
	// them with logical 16'h00ff. Physical MiSTer VRAM packs the two planes
	// contiguously, so replace any read-only overfetch beyond the last logical
	// row before it reaches the line RAM. DDR byte lanes hold each big-endian
	// framebuffer word swapped, hence logical 00ff is raw ff00 here.
	assign fetch_aligned_x = timekill_mode && fetch_plane
		? {1'b0, fetch_xorigin2[8:2], 2'b00}
		: {1'b0, fetch_xorigin[8:2], 2'b00};
	assign fetch_row = timekill_mode
		? (fetch_plane ? {1'b0, fetch_y2[8:0]} : {1'b0, fetch_y[8:0]})
		: (fetch_plane ? fetch_y2 : fetch_y);
	assign fetch_beat_x = fetch_aligned_x + (10'(fetch_index) << 2);
	assign fetch_guard_beat =
		fetch_row == (timekill_mode ? 10'h1ff : 10'h3ff) &&
		fetch_beat_x >= 10'd512;
	assign fetch_write_data = fetch_guard_beat
		? 64'hff00_ff00_ff00_ff00 : fb_rdata;

	itech32_line_buffer #(
		.LINE_WORDS(ROW_WORDS), .ADDR_WIDTH(FETCH_W)
	) line_buffer0 (
		.clk(clk), .write_enable(buffer0_write_enable),
		.write_addr(fetch_index), .write_data(fetch_write_data),
		.read_enable(ce_pixel),
		.read_addr(read_window_offset[FETCH_W+1:2]), .read_data(line_buffer0_q)
	);

	itech32_line_buffer #(
		.LINE_WORDS(ROW_WORDS), .ADDR_WIDTH(FETCH_W)
	) line_buffer1 (
		.clk(clk), .write_enable(buffer1_write_enable),
		.write_addr(fetch_index), .write_data(fetch_write_data),
		.read_enable(ce_pixel),
		.read_addr(read_window_offset[FETCH_W+1:2]), .read_data(line_buffer1_q)
	);

	itech32_line_buffer #(
		.LINE_WORDS(ROW_WORDS), .ADDR_WIDTH(FETCH_W)
	) line_buffer0_plane2 (
		.clk(clk), .write_enable(buffer0_plane2_write_enable),
		.write_addr(fetch_index), .write_data(fetch_write_data),
		.read_enable(ce_pixel),
		.read_addr(read_window_offset2[FETCH_W+1:2]), .read_data(line_buffer0_plane2_q)
	);

	itech32_line_buffer #(
		.LINE_WORDS(ROW_WORDS), .ADDR_WIDTH(FETCH_W)
	) line_buffer1_plane2 (
		.clk(clk), .write_enable(buffer1_plane2_write_enable),
		.write_addr(fetch_index), .write_data(fetch_write_data),
		.read_enable(ce_pixel),
		.read_addr(read_window_offset2[FETCH_W+1:2]), .read_data(line_buffer1_plane2_q)
	);

	always_comb begin
		// The display memories are synchronous.  Address the pixel that timing
		// will expose after the next ce_pixel edge so their registered outputs
		// stay aligned with hpos/vpos without adding a pixel of visible delay.
		if (htotal == 0 || hpos == htotal - 1'b1) begin
			read_hpos = 10'd0;
		end else begin
			read_hpos = hpos + 1'b1;
		end
		if (read_hpos >= hblank_end)
			read_display_x = read_hpos - hblank_end;
		else
			read_display_x = htotal - hblank_end + read_hpos;

		if (vtotal == 0 || vpos == vtotal - 1'b1)
			next_vpos = 10'd0;
		else
			next_vpos = vpos + 1'b1;
		next_vblank = interval_contains(next_vpos, vblank_start, vblank_end);
		if (next_vpos >= vblank_end)
			next_display_y = next_vpos - vblank_end;
		else
			next_display_y = vtotal - vblank_end + next_vpos;

		if (hpos >= hblank_end)
			display_x = hpos - hblank_end;
		else
			display_x = htotal - hblank_end + hpos;

		frame_effective_xorigin2 = frame_xorigin2_q + frame_xscroll2_q;
		buffer0_matches_live = buffer0_valid &&
			buffer0_xorigin == frame_xorigin_q &&
			buffer0_yorigin == frame_yorigin_q &&
			(!timekill_mode || (buffer0_xorigin2 == frame_effective_xorigin2 &&
			 buffer0_yorigin2 == frame_yorigin2_q &&
			 buffer0_yscroll2 == frame_yscroll2_q));
		buffer1_matches_live = buffer1_valid &&
			buffer1_xorigin == frame_xorigin_q &&
			buffer1_yorigin == frame_yorigin_q &&
			(!timekill_mode || (buffer1_xorigin2 == frame_effective_xorigin2 &&
			 buffer1_yorigin2 == frame_yorigin2_q &&
			 buffer1_yscroll2 == frame_yscroll2_q));
		buffer0_matches_prefetch = buffer0_valid &&
			buffer0_vtag == prefetch_vtag_q &&
			buffer0_xorigin == prefetch_xorigin_q &&
			buffer0_yorigin == prefetch_yorigin_q &&
			(!timekill_mode || (buffer0_xorigin2 == prefetch_xorigin2_q &&
			 buffer0_yorigin2 == prefetch_yorigin2_q &&
			 buffer0_yscroll2 == prefetch_yscroll2_q));
		buffer1_matches_prefetch = buffer1_valid &&
			buffer1_vtag == prefetch_vtag_q &&
			buffer1_xorigin == prefetch_xorigin_q &&
			buffer1_yorigin == prefetch_yorigin_q &&
			(!timekill_mode || (buffer1_xorigin2 == prefetch_xorigin2_q &&
			 buffer1_yorigin2 == prefetch_yorigin2_q &&
			 buffer1_yscroll2 == prefetch_yscroll2_q));
		buffer0_matches_frame_first = buffer0_valid &&
			buffer0_vtag == frame_first_vtag_q &&
			buffer0_xorigin == frame_xorigin_q &&
			buffer0_yorigin == frame_yorigin_q &&
			(!timekill_mode || (buffer0_xorigin2 == frame_effective_xorigin2 &&
			 buffer0_yorigin2 == frame_yorigin2_q &&
			 buffer0_yscroll2 == frame_yscroll2_q));
		buffer1_matches_frame_first = buffer1_valid &&
			buffer1_vtag == frame_first_vtag_q &&
			buffer1_xorigin == frame_xorigin_q &&
			buffer1_yorigin == frame_yorigin_q &&
			(!timekill_mode || (buffer1_xorigin2 == frame_effective_xorigin2 &&
			 buffer1_yorigin2 == frame_yorigin2_q &&
			 buffer1_yscroll2 == frame_yscroll2_q));
		current_in_buffer0 = buffer0_matches_live && buffer0_vtag == vpos;
		prefetch_line_buffered = buffer0_matches_prefetch || buffer1_matches_prefetch;
		if (vtotal != 0 && vblank_end >= vtotal)
			frame_first_vtag_d = 10'd0;
		else
			frame_first_vtag_d = vblank_end;
		if (vtotal == 0 || frame_first_vtag_d == vtotal - 1'b1)
			frame_second_vtag_d = 10'd0;
		else
			frame_second_vtag_d = frame_first_vtag_d + 1'b1;
		// Visibility is intentionally evaluated from the prior registered
		// descriptor/configuration stage.  Geometry is stable across the long
		// blanking interval, so this extra local edge costs no fetch budget and
		// avoids folding wrap arithmetic plus interval decode into one path.
		frame_first_visible_d = !interval_contains(frame_first_vtag_q,
			frame_vblank_start_q, frame_vblank_end_q);
		frame_second_visible_d = !interval_contains(frame_second_vtag_q,
			frame_vblank_start_q, frame_vblank_end_q);
		frame_first_buffered =
			buffer0_matches_frame_first || buffer1_matches_frame_first;
		// Keep the palette lookup address on the registered line-buffer/tag side
		// of the scanout.  Blanking still controls pixel_data/pixel_valid, but no
		// live hpos/vpos/blank comparator is allowed to become an M10K read enable.
		if (display_buffer_select)
			selected_line = line_buffer1_q;
		else
			selected_line = line_buffer0_q;
		if (display_buffer_select)
			selected_line2 = line_buffer1_plane2_q;
		else
			selected_line2 = line_buffer0_plane2_q;
		selected_word_raw = selected_line[read_lane_q * 16 +: 16];
		selected_word_raw2 = selected_line2[read_lane2_q * 16 +: 16];
		// DDR stores the lowest byte address in the low byte lane. Convert the
		// selected 16-bit framebuffer word back to the CPU-visible big-endian form.
		selected_pixel = {selected_word_raw[7:0], selected_word_raw[15:8]};
		selected_pixel2 = {selected_word_raw2[7:0], selected_word_raw2[15:8]};
		if (timekill_mode && selected_pixel[7:0] == 8'hff)
			selected_pixel = selected_pixel2;
		pixel_valid = !hblank && !vblank && display_x < LINE_PIXELS_LIMIT &&
			display_buffer_valid;
		pixel_data = pixel_valid ? selected_pixel : 16'h00ff;
		palette_addr = display_buffer_valid ? selected_pixel[14:0] : 15'h00ff;

		// Fetch a qword-aligned 512-pixel linear window beginning at the captured
		// origin. Only the low two origin bits remain as a line-RAM lane offset.
		fb_req = fetch_busy && !fetch_issued;
		if (timekill_mode && fetch_plane)
			fb_addr = {1'b1, fetch_row, fetch_xorigin2[8:2], 2'b00};
		else
			fb_addr = {1'b0, fetch_row, fetch_xorigin[8:2], 2'b00};
		read_window_offset = read_display_x + {8'd0, frame_xorigin_q[1:0]};
		read_window_offset2 = read_display_x +
			{8'd0, frame_effective_xorigin2[1:0]};

		// Predict the raster line visible immediately after the next pixel
		// enable.  Registering the matching line-buffer owner at that boundary
		// keeps the continuously changing palette address independent of the
		// vpos/tag comparison cone.
		display_vpos_after_tick = vpos;
		if (htotal != 0 && hpos == htotal - 1'b1) begin
			if (vtotal == 0 || vpos == vtotal - 1'b1)
				display_vpos_after_tick = 10'd0;
			else
				display_vpos_after_tick = vpos + 1'b1;
		end
	end

	always_ff @(posedge clk) begin
		// hpos/vpos and the timing outputs advance only on ce_pixel.  Therefore
		// these registers, sampled on the intervening fabric clocks, contain the
		// exact descriptor that the next ce_pixel edge previously computed live.
		prefetch_visible_calc_q   <= !next_vblank;
		prefetch_vtag_calc_q      <= next_vpos;
		prefetch_display_y_calc_q <= next_display_y;
		prefetch_yorigin_calc_q   <= frame_yorigin_q;
		prefetch_yorigin2_calc_q  <= frame_yorigin2_q;
		prefetch_yscroll2_calc_q  <= frame_yscroll2_q;
		prefetch_xorigin_calc_q   <= frame_xorigin_q;
		prefetch_xorigin2_calc_q  <= frame_effective_xorigin2;
		display_vpos_after_tick_q <= display_vpos_after_tick;
		vblank_local_q            <= vblank;
		if (ce_pixel) begin
			read_lane_q <= read_window_offset[1:0];
			read_lane2_q <= read_window_offset2[1:0];
		end

		// Register the complete next-frame fetch descriptors independently of the
		// pixel cadence.  The programmed geometry is already registered at the
		// board boundary; this second, local cut keeps its wrap/visibility decode
		// out of fetch_y/fetch_index control and data paths.
		frame_first_vtag_q   <= frame_first_vtag_d;
		frame_second_vtag_q  <= frame_second_vtag_d;
		frame_first_visible_q  <= frame_first_visible_d;
		frame_second_visible_q <= frame_second_visible_d;
		frame_vblank_start_q <= vblank_start;
		frame_vblank_end_q   <= vblank_end;
		// Origin and scroll programming is frame-atomic, matching MAME's complete
		// frame screen_update. SFTM can write these registers in the middle of an
		// active line; applying that live would make both already-buffered tags fail
		// their descriptor match and blank the rest of the line. Track the inputs
		// while raster reset is asserted, then adopt the complete set together at
		// vblank entry for the following active frame.
		if (reset || (ce_pixel && vblank_local_q && !previous_vblank)) begin
			frame_first_y_q      <= display_yorigin;
			frame_second_y_q     <= display_yorigin + 10'd1;
			frame_first_y2_q     <= display_yorigin2 + display_yscroll2;
			frame_second_y2_q    <= display_yorigin2 + display_yscroll2 + 10'd1;
			frame_xorigin_q      <= display_xorigin;
			frame_xorigin2_q     <= display_xorigin2;
			frame_xscroll2_q     <= display_xscroll2;
			frame_yorigin_q      <= display_yorigin;
			frame_yorigin2_q     <= display_yorigin2;
			frame_yscroll2_q     <= display_yscroll2;
		end

		if (reset) begin
			buffer0_valid <= 1'b0;
			buffer1_valid <= 1'b0;
			buffer0_vtag  <= 10'd0;
			buffer1_vtag  <= 10'd0;
			buffer0_xorigin <= 9'd0;
			buffer1_xorigin <= 9'd0;
			buffer0_yorigin <= 10'd0;
			buffer1_yorigin <= 10'd0;
			buffer0_xorigin2 <= 9'd0;
			buffer1_xorigin2 <= 9'd0;
			buffer0_yorigin2 <= 10'd0;
			buffer1_yorigin2 <= 10'd0;
			buffer0_yscroll2 <= 10'd0;
			buffer1_yscroll2 <= 10'd0;
			fetch_busy    <= 1'b0;
			fetch_issued  <= 1'b0;
			fetch_target  <= 1'b0;
			fetch_plane   <= 1'b0;
			fetch_index   <= '0;
			fetch_y       <= 10'd0;
			fetch_y2      <= 10'd0;
			fetch_vtag    <= 10'd0;
			fetch_xorigin <= 9'd0;
			fetch_xorigin2 <= 9'd0;
			fetch_yorigin <= 10'd0;
			fetch_yorigin2 <= 10'd0;
			fetch_yscroll2 <= 10'd0;
			read_lane_q   <= 2'd0;
			read_lane2_q  <= 2'd0;
			// Raster reset is held until the programmed geometry is stable.  Prime
			// the descriptor during that window so the first post-reset hpos-zero
			// edge retains the original full-line fetch budget.
			prefetch_visible_q   <= prefetch_visible_calc_q;
			prefetch_vtag_q      <= prefetch_vtag_calc_q;
			prefetch_display_y_q <= prefetch_display_y_calc_q;
			prefetch_yorigin_q   <= prefetch_yorigin_calc_q;
			prefetch_yorigin2_q  <= prefetch_yorigin2_calc_q;
			prefetch_yscroll2_q  <= prefetch_yscroll2_calc_q;
			prefetch_xorigin_q   <= prefetch_xorigin_calc_q;
			prefetch_xorigin2_q  <= prefetch_xorigin2_calc_q;
			previous_vblank      <= 1'b0;
			display_buffer_valid  <= 1'b0;
			display_buffer_select <= 1'b0;
			underflow     <= 1'b0;
		end else begin
			if (ce_pixel) begin
				// Pipeline the following-line descriptor.  At a line boundary the
				// previous descriptor names the newly current line; if it is already
				// buffered (the normal case), the tag check suppresses it while this
				// edge captures the next descriptor for the following retry.
				prefetch_visible_q   <= prefetch_visible_calc_q;
				prefetch_vtag_q      <= prefetch_vtag_calc_q;
				prefetch_display_y_q <= prefetch_display_y_calc_q;
				prefetch_yorigin_q   <= prefetch_yorigin_calc_q;
				prefetch_yorigin2_q  <= prefetch_yorigin2_calc_q;
				prefetch_yscroll2_q  <= prefetch_yscroll2_calc_q;
				prefetch_xorigin_q   <= prefetch_xorigin_calc_q;
				prefetch_xorigin2_q  <= prefetch_xorigin2_calc_q;
				previous_vblank      <= vblank_local_q;

				// Once the raster enters vblank, neither line retained from the
				// previous active interval is needed. Free both buffers so the
				// complete blanking interval can preload the next frame's first two
				// visible lines rather than beginning only one line before display.
				if (vblank_local_q && !previous_vblank) begin
					buffer0_valid       <= 1'b0;
					buffer1_valid       <= 1'b0;
					display_buffer_valid <= 1'b0;
					fetch_busy          <= 1'b0;
					fetch_issued        <= 1'b0;
					fetch_plane         <= 1'b0;
				end

				if (buffer0_matches_live &&
					buffer0_vtag == display_vpos_after_tick_q) begin
					display_buffer_valid  <= 1'b1;
					display_buffer_select <= 1'b0;
				end else if (buffer1_matches_live &&
					buffer1_vtag == display_vpos_after_tick_q) begin
					display_buffer_valid  <= 1'b1;
					display_buffer_select <= 1'b1;
				end else begin
					display_buffer_valid <= 1'b0;
				end
			end

			if (ce_pixel && !hblank && !vblank_local_q && display_x < LINE_PIXELS_LIMIT &&
				!display_buffer_valid)
				underflow <= 1'b1;

			// Request the following visible line as soon as the reader is idle.
			// Normally this is hpos zero, leaving the whole current line as fetch
			// time.  If the current-line read finishes just after hpos zero, retry
			// on a later pixel enable instead of silently skipping the next tag.
			// The valid tags suppress duplicate fetches after an early completion.
			// A vblank-entry edge updates the active-frame origin snapshot above.
			// Defer launch to the next pixel enable so no request can capture the
			// preceding frame's descriptor on that same nonblocking-assignment edge.
			if (ce_pixel && !fetch_busy &&
				!(vblank_local_q && !previous_vblank)) begin
				if (vblank_local_q && !buffer0_valid && !buffer1_valid &&
					frame_first_visible_q) begin
					fetch_busy    <= 1'b1;
					fetch_issued  <= 1'b0;
					fetch_index   <= '0;
					fetch_y       <= frame_first_y_q;
					fetch_y2      <= frame_first_y2_q;
					fetch_vtag    <= frame_first_vtag_q;
					fetch_xorigin <= frame_xorigin_q;
					fetch_xorigin2 <= frame_effective_xorigin2;
					fetch_yorigin <= frame_yorigin_q;
					fetch_yorigin2 <= frame_yorigin2_q;
					fetch_yscroll2 <= frame_yscroll2_q;
					fetch_plane   <= 1'b0;
					fetch_target  <= 1'b0;
					buffer0_valid <= 1'b0;
				end else if (vblank_local_q && (buffer0_valid ^ buffer1_valid) &&
					frame_first_buffered && frame_second_visible_q) begin
					fetch_busy    <= 1'b1;
					fetch_issued  <= 1'b0;
					fetch_index   <= '0;
					fetch_y       <= frame_second_y_q;
					fetch_y2      <= frame_second_y2_q;
					fetch_vtag    <= frame_second_vtag_q;
					fetch_xorigin <= frame_xorigin_q;
					fetch_xorigin2 <= frame_effective_xorigin2;
					fetch_yorigin <= frame_yorigin_q;
					fetch_yorigin2 <= frame_yorigin2_q;
					fetch_yscroll2 <= frame_yscroll2_q;
					fetch_plane   <= 1'b0;
					if (buffer0_valid) begin
						fetch_target  <= 1'b1;
						buffer1_valid <= 1'b0;
					end else begin
						fetch_target  <= 1'b0;
						buffer0_valid <= 1'b0;
					end
				end else if (prefetch_visible_q && !prefetch_line_buffered) begin
					fetch_busy    <= 1'b1;
					fetch_issued  <= 1'b0;
					fetch_index   <= '0;
					fetch_y       <= prefetch_yorigin_q + prefetch_display_y_q;
					fetch_y2      <= prefetch_yorigin2_q + prefetch_yscroll2_q +
						prefetch_display_y_q;
					fetch_vtag    <= prefetch_vtag_q;
					fetch_xorigin <= prefetch_xorigin_q;
					fetch_xorigin2 <= prefetch_xorigin2_q;
					fetch_yorigin <= prefetch_yorigin_q;
					fetch_yorigin2 <= prefetch_yorigin2_q;
					fetch_yscroll2 <= prefetch_yscroll2_q;
					fetch_plane   <= 1'b0;
					if (current_in_buffer0) begin
						fetch_target  <= 1'b1;
						buffer1_valid <= 1'b0;
					end else begin
						fetch_target  <= 1'b0;
						buffer0_valid <= 1'b0;
					end
				end
			end

			if (fetch_busy && !fetch_issued && fb_accept)
				fetch_issued <= 1'b1;

			if (fetch_busy && fetch_issued && fb_data_valid &&
				!(ce_pixel && vblank_local_q && !previous_vblank)) begin
				if (fb_last || fetch_index == FETCH_W'(ROW_WORDS - 1)) begin
					fetch_issued <= 1'b0;
					fetch_index <= '0;
					if (timekill_mode && !fetch_plane) begin
						// Plane 0 and plane 1 have independent display origins.  Keep
						// the line descriptor busy until both synchronous line RAMs hold
						// the same raster tag, then publish the pair atomically.
						fetch_plane <= 1'b1;
					end else begin
						fetch_busy <= 1'b0;
						fetch_plane <= 1'b0;
						if (fetch_target) begin
							buffer1_valid <= 1'b1;
							buffer1_vtag  <= fetch_vtag;
							buffer1_xorigin <= fetch_xorigin;
							buffer1_yorigin <= fetch_yorigin;
							buffer1_xorigin2 <= fetch_xorigin2;
							buffer1_yorigin2 <= fetch_yorigin2;
							buffer1_yscroll2 <= fetch_yscroll2;
						end else begin
							buffer0_valid <= 1'b1;
							buffer0_vtag  <= fetch_vtag;
							buffer0_xorigin <= fetch_xorigin;
							buffer0_yorigin <= fetch_yorigin;
							buffer0_xorigin2 <= fetch_xorigin2;
							buffer0_yorigin2 <= fetch_yorigin2;
							buffer0_yscroll2 <= fetch_yscroll2;
						end
					end
				end else begin
					fetch_index <= fetch_index + 1'b1;
				end
			end
		end
	end

`ifdef ITECH32_HW_PROBE
	// Debug-only, frame-coherent scanout census.  The JTAG probe is asynchronous
	// to clk, so expose a snapshot captured at vblank entry instead of live
	// counters that could tear while being read.  This block is omitted from the
	// release build unless the diagnostic QSF defines ITECH32_HW_PROBE.
	logic [15:0] hw_frame_counter = 16'd0;
	logic [15:0] hw_missing_pixels = 16'd0;
	logic [15:0] hw_fetch_age = 16'd0;
	logic [15:0] hw_max_fetch_age = 16'd0;
	logic [15:0] hw_fetch_completions = 16'd0;
	logic [9:0]  hw_first_miss_hpos = 10'd0;
	logic [9:0]  hw_first_miss_vpos = 10'd0;
	logic        hw_miss_seen = 1'b0;
	logic        hw_previous_vblank = 1'b0;
	logic [255:0] hw_probe = 256'd0;
	wire [0:0] hw_source;

	always_ff @(posedge clk) begin
		if (reset) begin
			hw_frame_counter    <= 16'd0;
			hw_missing_pixels   <= 16'd0;
			hw_fetch_age        <= 16'd0;
			hw_max_fetch_age    <= 16'd0;
			hw_fetch_completions <= 16'd0;
			hw_first_miss_hpos  <= 10'd0;
			hw_first_miss_vpos  <= 10'd0;
			hw_miss_seen        <= 1'b0;
			hw_previous_vblank  <= 1'b0;
			hw_probe            <= 256'd0;
		end else begin
			if (fetch_busy) begin
				if (hw_fetch_age != 16'hffff)
					hw_fetch_age <= hw_fetch_age + 1'b1;
			end else begin
				hw_fetch_age <= 16'd0;
			end

			if (fetch_busy && fetch_issued && fb_data_valid && fb_last) begin
				if (hw_fetch_completions != 16'hffff)
					hw_fetch_completions <= hw_fetch_completions + 1'b1;
				if (hw_fetch_age > hw_max_fetch_age)
					hw_max_fetch_age <= hw_fetch_age;
			end

			if (ce_pixel && !hblank && !vblank &&
				display_x < LINE_PIXELS_LIMIT && !display_buffer_valid) begin
				if (hw_missing_pixels != 16'hffff)
					hw_missing_pixels <= hw_missing_pixels + 1'b1;
				if (!hw_miss_seen) begin
					hw_first_miss_hpos <= hpos;
					hw_first_miss_vpos <= vpos;
				end
				hw_miss_seen <= 1'b1;
			end

			if (ce_pixel) begin
				hw_previous_vblank <= vblank;
				if (vblank && !hw_previous_vblank) begin
					hw_probe <= {
						8'ha5,
						hw_frame_counter,
						hw_missing_pixels,
						hw_max_fetch_age,
						hw_fetch_completions,
						hw_first_miss_hpos,
						hw_first_miss_vpos,
						htotal,
						hblank_end,
						vtotal,
						vblank_start,
						vblank_end,
						display_xorigin,
						buffer0_vtag,
						buffer1_vtag,
						fetch_vtag,
						fetch_y,
						{{(9-FETCH_W){1'b0}}, fetch_index},
						palette_addr,
						pixel_data,
						underflow,
						hw_miss_seen,
						buffer0_valid,
						buffer1_valid,
						display_buffer_valid,
						display_buffer_select,
						fetch_busy,
						fetch_target,
						fb_req,
						fb_data_valid,
						pixel_valid,
						hblank,
						vblank,
						ce_pixel,
						11'd0
					};
					hw_frame_counter <= hw_frame_counter + 1'b1;
					hw_missing_pixels <= 16'd0;
					hw_max_fetch_age <= 16'd0;
					hw_fetch_completions <= 16'd0;
					hw_first_miss_hpos <= 10'd0;
					hw_first_miss_vpos <= 10'd0;
					hw_miss_seen <= 1'b0;
			end
		end
	end
	end

	altsource_probe #(
		.sld_auto_instance_index("YES"),
		.sld_instance_index(0),
		.instance_id("IVD"),
		.probe_width(256),
		.source_width(1),
		.source_initial_value("0"),
		.enable_metastability("NO")
	) scanoutHardwareProbe (
		.probe(hw_probe),
		.source(hw_source)
	);
`endif

endmodule
