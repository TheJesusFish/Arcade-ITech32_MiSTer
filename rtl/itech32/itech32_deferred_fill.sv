// SPDX-License-Identifier: GPL-2.0-or-later
// Deferred row fill for the blitter's command 6 (shift-register copy).
//
// The original board performs command 6 with the framebuffer VRAMs' internal
// row transfers, so the copy finishes almost at once; MAME's copy is instant.
// This core keeps the framebuffer in shared DDR, where writing 512 rows of 512
// pixels takes several milliseconds. Golden Tee starts that copy from its last
// scanline interrupt of the frame and polls the blitter status until it is
// idle before it arms the next frame's first scanline interrupt, so a long
// copy pushes that interrupt past its line and the game drops every other
// frame.
//
// On boards that enable it, the blitter instead captures the source row into
// this module's fill line, marks the destination rows pending and completes.
// A pending row logically holds the fill line. This module writes it to VRAM
// (materializes it) before any blitter read or write reaches that row, and
// otherwise in the background while the blitter is idle. Scanout reads DDR
// directly, so a pending row must be materialized before it is displayed;
// Golden Tee copies into the hidden buffer at least a frame before showing it,
// and the simulation check below reports any scan of a pending row.
//
// The blitter port passes straight through while no row is pending, so boards
// that never enable the deferred fill keep their exact VRAM timing.

`timescale 1ns/1ps

module itech32_deferred_fill #(
	parameter integer VRAM_ADDR_WIDTH = 19
) (
	input  logic                       clk,
	input  logic                       reset,
	// Static per loaded game (profile).
	input  logic                       enable,
	input  logic                       rows_512,

	// Command 6 control from the blitter. prepare_req is held while the blitter
	// waits to reuse a plane's fill line; prepare_ready reports that the plane
	// has no pending rows left. capture_* load the source row. arm_req is held
	// until the one-cycle arm_ack, after every destination row is marked.
	input  logic                       prepare_req,
	input  logic                       prepare_plane,
	output logic                       prepare_ready,
	input  logic                       capture_we,
	input  logic                       capture_plane,
	input  logic [8:0]                 capture_word,
	input  logic [15:0]                capture_data,
	input  logic                       arm_req,
	input  logic                       arm_plane,
	input  logic [9:0]                 arm_first_row,
	input  logic                       arm_down,
	input  logic [8:0]                 arm_rows,
	output logic                       arm_ack,
	// The blitter is idle: pending rows may be materialized in the background.
	input  logic                       background_ok,

	// Blitter side of the VRAM port.
	input  logic                       blit_req,
	input  logic                       blit_we,
	input  logic                       blit_plane,
	input  logic [VRAM_ADDR_WIDTH-1:0] blit_addr,
	input  logic [15:0]                blit_wdata,
	output logic                       blit_ack,
	output logic [15:0]                blit_rdata,

	// Arbiter side of the VRAM port.
	output logic                       mem_req,
	output logic                       mem_we,
	output logic                       mem_plane,
	output logic [VRAM_ADDR_WIDTH-1:0] mem_addr,
	output logic [15:0]                mem_wdata,
	input  logic                       mem_ack,
	input  logic [15:0]                mem_rdata
);

	typedef enum logic [2:0] {
		S_SWEEP      = 3'd0,
		S_IDLE       = 3'd1,
		S_ARM        = 3'd2,
		S_ARM_DONE   = 3'd3,
		S_LOOKUP     = 3'd4,
		S_SCAN_CHECK = 3'd5,
		S_FILL       = 3'd6
	} state_t;

	state_t state;

	// One pending bit per {plane, row}. The reset-free body is cleared by the
	// sweep after every reset; reads are registered (M10K template).
	(* ramstyle = "M10K, no_rw_check" *) logic pending_bits [0:2047];
	logic        bit_we;
	logic [10:0] bit_waddr;
	logic        bit_wdata;
	logic        bit_re;
	logic [10:0] bit_raddr;
	logic        bit_q;

	// Fill lines for both planes, indexed {plane, word}. Capture and fill of
	// the same plane never overlap: prepare drains a plane before its capture.
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] fill_line [0:1023];
	logic        fill_re;
	logic [9:0]  fill_raddr;
	logic [15:0] fill_q;

	logic [10:0] sweep_addr;
	logic [9:0]  pending_count [0:1];
	logic        none_pending_q;
	logic        clean_valid;
	logic        clean_plane;
	logic [9:0]  clean_row;
	logic        forward_active;

	logic        arm_plane_q;
	logic [9:0]  arm_row_q;
	logic        arm_down_q;
	logic [8:0]  arm_left_q;

	logic [9:0]  scan_row [0:1];
	logic        scan_down [0:1];
	logic        scan_plane_q;

	// Materialization of one row: a registered RAM stage (fill_q, held while
	// stalled) feeding a registered output that is held until mem_ack.
	logic        fill_plane;
	logic [9:0]  fill_row;
	logic [9:0]  fill_issue;
	logic        fill_r_valid;
	logic [8:0]  fill_r_word;
	logic        fill_o_valid;
	logic [8:0]  fill_o_word;
	logic [15:0] fill_o_data;

	logic [9:0]  blit_row;
	logic        fast_hit;
	logic        forward_now;
	logic        idle_free;
	logic        scan_wanted;
	logic        scan_plane;
	logic        fill_o_take;
	logic        fill_r_take;
	logic        fill_last_ack;

	function automatic logic [9:0] step_row(
		input logic [9:0] row,
		input logic down,
		input logic narrow
	);
		logic [9:0] next;
		begin
			next = down ? row - 10'd1 : row + 10'd1;
			step_row = narrow ? {1'b0, next[8:0]} : next;
		end
	endfunction

	assign blit_row = blit_addr[VRAM_ADDR_WIDTH-1:VRAM_ADDR_WIDTH-10];
	// A request may pass while no row is pending, or when it stays in the row
	// most recently proved clean. Rows only become pending in S_ARM, which
	// clears clean_valid, so neither term can go stale under a held request.
	assign fast_hit = !enable || none_pending_q ||
		(clean_valid && blit_plane == clean_plane && blit_row == clean_row);
	assign forward_now = blit_req &&
		(forward_active || ((state == S_IDLE || !enable) && fast_hit));
	assign idle_free = state == S_IDLE && !forward_active &&
		!(blit_req && fast_hit);
	assign scan_plane = prepare_req ? prepare_plane :
		(pending_count[0] != 10'd0 ? 1'b0 : 1'b1);
	assign scan_wanted = enable && !blit_req &&
		((prepare_req && pending_count[prepare_plane] != 10'd0) ||
		 (background_ok && !none_pending_q));
	assign prepare_ready = pending_count[prepare_plane] == 10'd0;
	assign arm_ack = state == S_ARM_DONE;

	assign fill_o_take = !fill_o_valid || mem_ack;
	assign fill_r_take = !fill_r_valid || fill_o_take;
	assign fill_last_ack = state == S_FILL && fill_o_valid && mem_ack &&
		fill_o_word == 9'd511;

	always_comb begin
		if (state == S_FILL) begin
			mem_req   = fill_o_valid;
			mem_we    = 1'b1;
			mem_plane = fill_plane;
			mem_addr  = {fill_row, fill_o_word};
			mem_wdata = fill_o_data;
		end else begin
			mem_req   = forward_now;
			mem_we    = blit_we;
			mem_plane = blit_plane;
			mem_addr  = blit_addr;
			mem_wdata = blit_wdata;
		end
		blit_ack = state != S_FILL && forward_now && mem_ack;
		blit_rdata = mem_rdata;
	end

	// Pending-bit port selection. Each state owns at most one write and one
	// read; a read never targets the address written on the same edge.
	always_comb begin
		bit_we = 1'b0;
		bit_waddr = sweep_addr;
		bit_wdata = 1'b0;
		bit_re = 1'b0;
		bit_raddr = {blit_plane, blit_row};
		case (state)
			S_SWEEP: bit_we = 1'b1;
			S_ARM: begin
				bit_we = 1'b1;
				bit_waddr = {arm_plane_q, arm_row_q};
				bit_wdata = 1'b1;
			end
			S_FILL: begin
				bit_we = fill_last_ack;
				bit_waddr = {fill_plane, fill_row};
			end
			S_IDLE: begin
				if (idle_free && !arm_req && enable) begin
					if (blit_req) begin
						bit_re = 1'b1;
					end else if (scan_wanted) begin
						bit_re = 1'b1;
						bit_raddr = {scan_plane, scan_row[scan_plane]};
					end
				end
			end
			default: begin end
		endcase
	end

	always_ff @(posedge clk) begin
		if (bit_we)
			pending_bits[bit_waddr] <= bit_wdata;
		if (bit_re)
			bit_q <= pending_bits[bit_raddr];
	end

	always_comb begin
		fill_re = state == S_FILL && fill_r_take && fill_issue[9] == 1'b0;
		fill_raddr = {fill_plane, fill_issue[8:0]};
	end

	always_ff @(posedge clk) begin
		if (capture_we)
			fill_line[{capture_plane, capture_word}] <= capture_data;
		if (fill_re)
			fill_q <= fill_line[fill_raddr];
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			state <= S_SWEEP;
			sweep_addr <= 11'd0;
			pending_count[0] <= 10'd0;
			pending_count[1] <= 10'd0;
			none_pending_q <= 1'b1;
			clean_valid <= 1'b0;
			clean_plane <= 1'b0;
			clean_row <= 10'd0;
			forward_active <= 1'b0;
			arm_plane_q <= 1'b0;
			arm_row_q <= 10'd0;
			arm_down_q <= 1'b0;
			arm_left_q <= 9'd0;
			scan_row[0] <= 10'd0;
			scan_row[1] <= 10'd0;
			scan_down[0] <= 1'b0;
			scan_down[1] <= 1'b0;
			scan_plane_q <= 1'b0;
			fill_plane <= 1'b0;
			fill_row <= 10'd0;
			fill_issue <= 10'd0;
			fill_r_valid <= 1'b0;
			fill_r_word <= 9'd0;
			fill_o_valid <= 1'b0;
			fill_o_word <= 9'd0;
			fill_o_data <= 16'd0;
		end else begin
			none_pending_q <= pending_count[0] == 10'd0 &&
				pending_count[1] == 10'd0;

			if (forward_now && !mem_ack && state != S_FILL)
				forward_active <= 1'b1;
			else if (forward_now && mem_ack)
				forward_active <= 1'b0;

			case (state)
				S_SWEEP: begin
					sweep_addr <= sweep_addr + 11'd1;
					if (sweep_addr == 11'h7ff)
						state <= S_IDLE;
				end

				S_IDLE: begin
					if (idle_free && enable) begin
						if (arm_req) begin
							clean_valid <= 1'b0;
							arm_plane_q <= arm_plane;
							arm_row_q <= rows_512 ?
								{1'b0, arm_first_row[8:0]} : arm_first_row;
							arm_down_q <= arm_down;
							arm_left_q <= arm_rows;
							scan_row[arm_plane] <= rows_512 ?
								{1'b0, arm_first_row[8:0]} : arm_first_row;
							scan_down[arm_plane] <= arm_down;
							state <= S_ARM;
						end else if (blit_req) begin
							state <= S_LOOKUP;
						end else if (scan_wanted) begin
							scan_plane_q <= scan_plane;
							state <= S_SCAN_CHECK;
						end
					end
				end

				// The blitter guarantees the plane has no pending rows and
				// arm_rows >= 1, so every marked row was clear before.
				S_ARM: begin
					pending_count[arm_plane_q] <= pending_count[arm_plane_q] + 10'd1;
					arm_row_q <= step_row(arm_row_q, arm_down_q, rows_512);
					arm_left_q <= arm_left_q - 9'd1;
					if (arm_left_q == 9'd1)
						state <= S_ARM_DONE;
				end

				S_ARM_DONE: state <= S_IDLE;

				// The blitter holds its request, so blit_plane/blit_row are the
				// address that was read.
				S_LOOKUP: begin
					if (bit_q) begin
						fill_plane <= blit_plane;
						fill_row <= blit_row;
						fill_issue <= 10'd0;
						fill_r_valid <= 1'b0;
						fill_o_valid <= 1'b0;
						state <= S_FILL;
					end else begin
						clean_valid <= 1'b1;
						clean_plane <= blit_plane;
						clean_row <= blit_row;
						state <= S_IDLE;
					end
				end

				S_SCAN_CHECK: begin
					if (bit_q) begin
						fill_plane <= scan_plane_q;
						fill_row <= scan_row[scan_plane_q];
						fill_issue <= 10'd0;
						fill_r_valid <= 1'b0;
						fill_o_valid <= 1'b0;
						state <= S_FILL;
					end else begin
						state <= S_IDLE;
					end
					scan_row[scan_plane_q] <= step_row(scan_row[scan_plane_q],
						scan_down[scan_plane_q], rows_512);
				end

				S_FILL: begin
					if (fill_o_take) begin
						fill_o_valid <= fill_r_valid;
						fill_o_word <= fill_r_word;
						fill_o_data <= fill_q;
					end
					if (fill_r_take) begin
						fill_r_valid <= fill_issue[9] == 1'b0;
						fill_r_word <= fill_issue[8:0];
						if (fill_issue[9] == 1'b0)
							fill_issue <= fill_issue + 10'd1;
					end
					if (fill_last_ack) begin
						fill_o_valid <= 1'b0;
						fill_r_valid <= 1'b0;
						pending_count[fill_plane] <= pending_count[fill_plane] - 10'd1;
						clean_valid <= 1'b1;
						clean_plane <= fill_plane;
						clean_row <= fill_row;
						state <= S_IDLE;
					end
				end

				default: state <= S_IDLE;
			endcase
		end
	end

`ifndef SYNTHESIS
	always_ff @(posedge clk) begin
		if (!reset) begin
			if (forward_active)
				assert (blit_req)
					else $fatal(1, "deferred fill: blitter dropped a forwarded request");
			if (state == S_FILL)
				assert (!forward_active)
					else $fatal(1, "deferred fill: row fill overlapped a forwarded request");
			if (state == S_ARM)
				assert (pending_count[arm_plane_q] != 10'h3ff)
					else $fatal(1, "deferred fill: pending count overflow");
			if (arm_req && state == S_IDLE && idle_free && enable)
				assert (pending_count[arm_plane] == 10'd0 && arm_rows != 9'd0)
					else $fatal(1, "deferred fill: arm without a drained plane");
		end
	end
`endif

endmodule
