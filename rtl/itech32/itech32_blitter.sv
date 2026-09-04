// SPDX-License-Identifier: GPL-2.0-or-later
// Incredible Technologies 32-bit framebuffer blitter.
//
// This is a sequential, stall-safe implementation of the behavior modeled by
// MAME's itech32_v.cpp.  Register addresses are 16-bit word indices, matching
// itech32_main_bus.video_addr (CPU byte offset >> 1).

`timescale 1ns/1ps

module itech32_blitter #(
	parameter integer GROM_ADDR_WIDTH = 26,
	parameter integer VRAM_ADDR_WIDTH = 19
) (
	input  logic                         clk,
	input  logic                         reset,
	input  logic                         timekill_mode,

	input  logic                         reg_req,
	input  logic                         reg_we,
	input  logic [6:0]                   reg_addr,
	input  logic [15:0]                  reg_wdata,
	input  logic [1:0]                   reg_be,
	output logic                         reg_ack,
	output logic [15:0]                  reg_rdata,

	input  logic                         color0_we,
	input  logic                         color1_we,
	input  logic [7:0]                   color_data,
	input  logic [1:0]                   plane_enable,
	input  logic [1:0]                   grom_bank,

	input  logic                         scanline_event,
	output logic                         irq_blitter,
	output logic                         irq_scanline,
	output logic [15:0]                  interrupt_state,
	output logic                         busy,
	output logic [15:0]                  timing_int_scanline,
	output logic [15:0]                  timing_vtotal,
	output logic [15:0]                  timing_vsync,
	output logic [15:0]                  timing_vblank_start,
	output logic [15:0]                  timing_vblank_end,
	output logic [15:0]                  timing_htotal,
	output logic [15:0]                  timing_hsync,
	output logic [15:0]                  timing_hblank_start,
	output logic [15:0]                  timing_hblank_end,
	output logic [15:0]                  display_xorigin1,
	output logic [15:0]                  display_yorigin1,
	output logic [15:0]                  display_xorigin2,
	output logic [15:0]                  display_yorigin2,
	output logic [15:0]                  display_xscroll2,
	output logic [15:0]                  display_yscroll2,

	output logic                         grom_req,
	output logic [GROM_ADDR_WIDTH-1:0]   grom_addr,
	input  logic                         grom_ack,
	input  logic [63:0]                  grom_rdata,

	output logic                         vram_req,
	output logic                         vram_we,
	output logic                         vram_plane,
	output logic [VRAM_ADDR_WIDTH-1:0]   vram_addr,
	output logic [15:0]                  vram_wdata,
	input  logic                         vram_ack,
	input  logic [15:0]                  vram_rdata,
	// A write ACK transfers ownership to the downstream FIFO; it does not make
	// the pixel visible to later commands or scanout.  Write-producing commands
	// remain busy until that retained tail reaches the shared-memory boundary.
	input  logic                         vram_writes_pending
);

	localparam logic [15:0] INT_SCANLINE = 16'h0004;
	localparam logic [15:0] INT_BLITTER  = 16'h0040;

	localparam logic [15:0] FLAG_TRANSPARENT = 16'h0001;
	localparam logic [15:0] FLAG_XFLIP       = 16'h0002;
	localparam logic [15:0] FLAG_YFLIP       = 16'h0004;
	localparam logic [15:0] FLAG_DSTXSCALE   = 16'h0008;
	localparam logic [15:0] FLAG_DYDXSIGN    = 16'h0010;
	localparam logic [15:0] FLAG_DXDYSIGN    = 16'h0020;
	localparam logic [15:0] FLAG_CLIP         = 16'h0400;
	localparam logic [15:0] FLAG_WIDTHPIX     = 16'h8000;

	localparam logic [6:0] REG_STATUS      = 7'h00;
	localparam logic [6:0] REG_INTSTATE    = 7'h01;
	localparam logic [6:0] REG_TRANSFER    = 7'h02;
	localparam logic [6:0] REG_FLAGS       = 7'h03;
	localparam logic [6:0] REG_COMMAND     = 7'h04;
	localparam logic [6:0] REG_INTENABLE   = 7'h05;
	localparam logic [6:0] REG_HEIGHT      = 7'h06;
	localparam logic [6:0] REG_WIDTH       = 7'h07;
	localparam logic [6:0] REG_ADDRLO      = 7'h08;
	localparam logic [6:0] REG_X           = 7'h09;
	localparam logic [6:0] REG_Y           = 7'h0a;
	localparam logic [6:0] REG_SRC_YSTEP   = 7'h0b;
	localparam logic [6:0] REG_SRC_XSTEP   = 7'h0c;
	localparam logic [6:0] REG_DST_XSTEP   = 7'h0d;
	localparam logic [6:0] REG_DST_YSTEP   = 7'h0e;
	localparam logic [6:0] REG_YSTEP_PER_X = 7'h0f;
	localparam logic [6:0] REG_XSTEP_PER_Y = 7'h10;
	localparam logic [6:0] REG_LEFTCLIP    = 7'h12;
	localparam logic [6:0] REG_RIGHTCLIP   = 7'h13;
	localparam logic [6:0] REG_TOPCLIP     = 7'h14;
	localparam logic [6:0] REG_BOTTOMCLIP  = 7'h15;
	localparam logic [6:0] REG_INTSCANLINE = 7'h16;
	localparam logic [6:0] REG_ADDRHI      = 7'h17;
	localparam logic [6:0] REG_VTOTAL      = 7'h19;
	localparam logic [6:0] REG_VSYNC       = 7'h1a;
	localparam logic [6:0] REG_VBLANKSTART = 7'h1b;
	localparam logic [6:0] REG_VBLANKEND   = 7'h1c;
	localparam logic [6:0] REG_HTOTAL      = 7'h1d;
	localparam logic [6:0] REG_HSYNC       = 7'h1e;
	localparam logic [6:0] REG_HBLANKSTART = 7'h1f;
	localparam logic [6:0] REG_HBLANKEND   = 7'h20;
	localparam logic [6:0] REG_YORIGIN1    = 7'h22;
	localparam logic [6:0] REG_YORIGIN2    = 7'h23;
	localparam logic [6:0] REG_YSCROLL2    = 7'h24;
	localparam logic [6:0] REG_XORIGIN1    = 7'h26;
	localparam logic [6:0] REG_XORIGIN2    = 7'h27;
	localparam logic [6:0] REG_XSCROLL2    = 7'h28;

	typedef enum logic [3:0] {
		ST_IDLE              = 4'd0,
		ST_RAW_CHECK         = 4'd1,
		ST_RAW_ROW_ADVANCE   = 4'd2,
		ST_RAW_GROM_ADDR     = 4'd3,
		ST_RAW_PROCESS       = 4'd4,
		ST_RAW_ADVANCE       = 4'd5,
		ST_RLE_STREAM        = 4'd6,
		ST_XFER_READ         = 4'd7,
		ST_XFER_WRITE        = 4'd8,
		ST_SHIFT_READ        = 4'd9,
		ST_RLE_FETCH_DRAIN   = 4'd10,
		ST_SHIFT_BUFFER_READ = 4'd11,
		ST_WAIT_DRAIN        = 4'd13,
		ST_SHIFT_REPLAY      = 4'd14
	} state_t;

	state_t state;
	logic [15:0] video_regs [0:127];
	logic [15:0] color_latch [0:1];
	logic reg_held;
	logic reg_pending;
	logic reg_we_q;
	logic [6:0] reg_addr_q;
	logic [15:0] reg_wdata_q;
	logic [1:0] reg_be_q;
	// Preserve this transaction-stage decode as registers.  Besides making the
	// general write a local one-bit enable at each video register, the explicit
	// stage prevents Quartus from rebuilding the former 128-way encoded-address
	// mux on every register D input.
	logic [127:0] reg_write_sel_q;
	logic reg_command_write_q;
	logic reg_transfer_write_q;
	logic reg_intstate_write_q;
	logic reg_transfer_active_q;
	logic [15:0] reg_transfer_width_q;
	logic [11:0] reg_transfer_x_q;
	logic [15:0] reg_read_value;
	logic blitter_done_pulse;
	logic [15:0] command_value_q;
	logic [15:0] command_flags_q;
	logic [15:0] command_width_q;
	logic [8:0] command_height_q;
	logic [11:0] command_x_q;
	logic [11:0] command_y_q;
	logic [15:0] command_addrlo_q;
	logic [7:0] command_addrhi_q;
	logic [15:0] command_src_xstep_q;
	logic [15:0] command_src_ystep_q;
	logic [15:0] command_dst_xstep_q;
	logic [15:0] command_dst_ystep_q;
	logic [15:0] command_ystep_per_x_q;
	logic [15:0] command_xstep_per_y_q;
	logic [15:0] command_leftclip_q;
	logic [15:0] command_rightclip_q;
	logic [15:0] command_topclip_q;
	logic [15:0] command_bottomclip_q;

	logic [15:0] op_flags;
	logic [15:0] op_width;
	logic [8:0]  op_height;
	logic [11:0] op_x;
	logic [11:0] op_y;
	logic [15:0] op_src_xstep;
	logic [15:0] op_src_ystep;
	logic [15:0] op_ystep_per_x;
	logic signed [31:0] op_clip_min_x;
	logic signed [31:0] op_clip_max_x;
	logic signed [31:0] op_clip_min_y;
	logic signed [31:0] op_clip_max_y;
	logic signed [31:0] op_dx;
	logic signed [31:0] op_dy;
	logic signed [31:0] op_dty;
	logic signed [31:0] op_row_skew;
	logic [GROM_ADDR_WIDTH-1:0] op_grom_base;
	logic [15:0] op_color [0:1];
	logic op_plane1_enabled;
	logic op_rle_slow;
	logic current_plane;

	logic [31:0] src_x_acc;
	logic [31:0] src_y_acc;
	logic [31:0] pixel_width_acc;
	logic signed [31:0] dst_x_acc;
	logic signed [31:0] dst_y_acc;
	logic signed [31:0] dst_ty_acc;
	logic signed [31:0] row_start_x;
	logic [GROM_ADDR_WIDTH-1:0] raw_row_base;
	logic raw_clip_skip_eight_q;

	logic [15:0] rle_row;
	// RLE column state feeds parser completion, clip, and held GROM-request
	// qualification.
	logic [15:0] rle_col;
	logic [6:0] rle_count;
	logic rle_literal;
	logic [7:0] rle_repeat_value;
	logic [GROM_ADDR_WIDTH-1:0] rle_pointer;
	// Keep the request boundary local to the parser. These registers advance
	// with rle_pointer/rle_col, so they remove the wide live comparisons from
	// the DDR request cone without inserting a request or pixel cycle.
	logic [GROM_ADDR_WIDTH-1:0] rle_request_addr;
	logic rle_position_active;
	logic rle_wait_repeat;
	logic rle_qword_valid;
	logic [63:0] rle_qword_data;
	// One sequential qword may be fetched while the parser consumes the current
	// one. Addresses are implicit, so the registered DDR request cone contains no
	// wide tag comparison. If demand catches the prefetch, only its role changes;
	// the held request payload remains stable through acknowledgement.
	logic rle_next_qword_valid;
	logic [63:0] rle_next_qword_data;
	logic rle_fetch_valid;
	logic rle_fetch_next;
	logic rle_fetch_drain_restart_plane;
	logic rle_output_valid;
	logic [VRAM_ADDR_WIDTH-1:0] rle_output_addr;
	logic [15:0] rle_output_data;
	logic rle_output_plane;

	logic [7:0] pixel_value;
	logic [15:0] xfer_xcount;
	logic [15:0] xfer_ycount;
	logic [15:0] xfer_xcur;
	logic [15:0] xfer_ycur;
	logic [7:0] xfer_cpu_pixel;
	logic [15:0] xfer_old_pixel;
	logic xfer_plane;

	logic [8:0] shift_row;
	logic [9:0] shift_word;
	logic [VRAM_ADDR_WIDTH-1:0] shift_source_base;
	logic [VRAM_ADDR_WIDTH-1:0] shift_dest_base;
	// Command 6 copies the same 512-word source row into every following row.
	// Keep that hot row in one M10K after the first DDR pass instead of reading
	// it again for every destination.  The data body is intentionally reset-free;
	// state/word counters make it unreachable until all 512 entries are filled.
	// Source filling and later replay never overlap, so same-address RDW is
	// architecturally don't-care and no_rw_check is valid.
	(* ramstyle = "M10K, no_rw_check" *) logic [15:0] shift_line [0:511];
	logic [15:0] shift_line_q;
	logic [8:0] shift_line_read_addr;
	logic       shift_line_read_enable;
	logic [8:0] shift_fetch_word;
	logic       shift_fetch_valid;
	logic [8:0] shift_output_word;
	logic       shift_output_valid;
	logic [15:0] shift_output_data;

	// Pre-stage the raw-pixel GROM address independently of the clip/row
	// decision.  The following state copies it into the held request payload,
	// keeping accumulator/clip control out of the GROM address register enable.
	logic [GROM_ADDR_WIDTH-1:0] grom_addr_prep;
	// RAW scaling often revisits bytes in the same returned qword. Retain one
	// full-address-tagged word for this command only. CHECK registers both the
	// prepared address and its hit, keeping the comparator off the request cone.
	logic [63:0] raw_qword_data;
	logic [GROM_ADDR_WIDTH-1:3] raw_qword_tag;
	logic raw_qword_valid;
	logic raw_qword_hit_q;
	// Separate clip/transparency decisions from the shared VRAM address mux.
	// Preserve the stage so Quartus cannot fold the accumulator comparison cone
	// back into vram_addr_hold's D input.
	logic [VRAM_ADDR_WIDTH-1:0] vram_addr_prep;
	logic [VRAM_ADDR_WIDTH-1:0] vram_addr_hold;
	logic [15:0] vram_wdata_hold;
	logic vram_plane_hold;

	integer index;

	function automatic logic [15:0] merge_word(
		input logic [15:0] old_value,
		input logic [15:0] new_value,
		input logic [1:0] byte_enable
	);
		logic [15:0] result;
		begin
			result = old_value;
			if (byte_enable[0]) result[7:0]  = new_value[7:0];
			if (byte_enable[1]) result[15:8] = new_value[15:8];
			merge_word = result;
		end
	endfunction

	function automatic logic [127:0] decode_register_write(input logic [6:0] address);
		logic [127:0] result;
		begin
			result = '0;
			result[address] = 1'b1;
			decode_register_write = result;
		end
	endfunction

	// These helpers intentionally discard the documented packed/masked bits.
	/* verilator lint_off UNUSEDSIGNAL */
	function automatic logic [8:0] adjusted_height(input logic [15:0] value);
		adjusted_height = {value[9], value[7:0]};
	endfunction

	function automatic logic [VRAM_ADDR_WIDTH-1:0] integer_vram_address(
		input logic [11:0] x_value,
		input logic [11:0] y_value
	);
		if (timekill_mode)
			integer_vram_address = {1'b0, y_value[8:0], x_value[8:0]};
		else
			integer_vram_address = {y_value[9:0], x_value[8:0]};
	endfunction

	function automatic logic [VRAM_ADDR_WIDTH-1:0] fixed_vram_address(
		input logic signed [31:0] x_value,
		input logic signed [31:0] y_value
	);
		if (timekill_mode)
			fixed_vram_address = {1'b0, y_value[16:8], x_value[16:8]};
		else
			fixed_vram_address = {y_value[17:8], x_value[16:8]};
	endfunction
	/* verilator lint_on UNUSEDSIGNAL */

	function automatic logic [15:0] active_color(input logic plane_number);
		active_color = plane_number ? op_color[1] : op_color[0];
	endfunction

	function automatic logic [7:0] grom_line_byte(
		input logic [63:0] line,
		input logic [2:0] index_value
	);
		grom_line_byte = line[index_value * 8 +: 8];
	endfunction

	function automatic logic raw_inside_clip;
		logic y_inside;
		begin
			if (op_ystep_per_x == 16'd0)
				y_inside = (dst_y_acc >= op_clip_min_y) && (dst_y_acc < op_clip_max_y);
			else
				// MAME rectangle::contains() is inclusive at the bottom edge.
				y_inside = (dst_ty_acc >= op_clip_min_y) && (dst_ty_acc <= op_clip_max_y);
			raw_inside_clip = (dst_x_acc >= op_clip_min_x) &&
				(dst_x_acc < op_clip_max_x) && y_inside;
		end
	endfunction

	function automatic logic rle_inside_clip;
		logic x_inside;
		begin
			if (!op_rle_slow && op_flags[1])
				x_inside = (dst_x_acc > op_clip_min_x) && (dst_x_acc <= op_clip_max_x);
			else
				x_inside = (dst_x_acc >= op_clip_min_x) && (dst_x_acc < op_clip_max_x);
			rle_inside_clip = x_inside &&
				(dst_y_acc >= op_clip_min_y) && (dst_y_acc < op_clip_max_y);
		end
	endfunction

	// Register the request at the module boundary.  The upstream bus holds a
	// transaction until reg_ack, so this one-entry stage preserves ordering while
	// keeping its high-fanout address/data out of the command-state next-state cone.
	wire [15:0] accepted_command_value = merge_word(video_regs[REG_COMMAND], reg_wdata, reg_be);
	wire [15:0] merged_transfer_value = merge_word(video_regs[REG_TRANSFER], reg_wdata_q, reg_be_q);
	wire [15:0] write_one_mask = {
		reg_be_q[1] ? reg_wdata_q[15:8] : 8'h00,
		reg_be_q[0] ? reg_wdata_q[7:0]  : 8'h00
	};
	wire [15:0] interrupt_clear_now =
		(reg_pending && reg_intstate_write_q) ? write_one_mask : 16'd0;
	// A valid current slot always owns the qword containing rle_pointer. The
	// optional next slot is exactly one aligned qword later.
	wire rle_qword_hit = rle_qword_valid;
	wire [7:0] rle_stream_byte = grom_line_byte(rle_qword_data,
		rle_pointer[2:0]);
	wire [7:0] grom_response_byte = grom_line_byte(grom_rdata,
		grom_addr[2:0]);
	wire [GROM_ADDR_WIDTH-1:0] raw_grom_addr_next = op_grom_base +
		GROM_ADDR_WIDTH'(raw_row_base) + GROM_ADDR_WIDTH'(src_x_acc >> 8);
	wire raw_qword_fill = (state == ST_RAW_GROM_ADDR) &&
		!raw_qword_hit_q && grom_ack;
	// A zero per-X Y step makes an outside-Y row wholly invisible. Reuse the
	// ordinary row transition rather than walking X or guessing a future row.
	wire raw_row_outside_y = (op_ystep_per_x == 16'd0) &&
		((dst_y_acc < op_clip_min_y) || (dst_y_acc >= op_clip_max_y));
	// Retire only eight unit-X positions proven invisible on the SAME side of
	// the clip rectangle. Widen before adding: wrap inside positions0..7 must
	// not turn an apparent outside interval into one crossing the visible area.
	// Wrap on the final (eighth) update is legal and rechecked by the next CHECK.
	wire signed [32:0] raw_x_seventh = $signed({dst_x_acc[31], dst_x_acc}) +
		(op_dx[31] ? -33'sd1792 : 33'sd1792);
	wire [32:0] raw_src_x_plus_eight = {1'b0, src_x_acc} +
		{14'd0, op_src_xstep, 3'b000};
	wire [32:0] raw_width_plus_eight = {1'b0, pixel_width_acc} + 33'd2048;
	wire [32:0] raw_width_limit = {9'd0, op_width, 8'd0};
	wire raw_clip_skip_eight = (op_ystep_per_x == 16'd0) &&
		((op_dx == 32'sd256) || (op_dx == -32'sd256)) &&
		(raw_x_seventh[32] == raw_x_seventh[31]) &&
		(((dst_x_acc < op_clip_min_x) &&
		  (raw_x_seventh < $signed({op_clip_min_x[31], op_clip_min_x}))) ||
		 ((dst_x_acc >= op_clip_max_x) &&
		  (raw_x_seventh >= $signed({op_clip_max_x[31], op_clip_max_x})))) &&
		(((op_flags & FLAG_WIDTHPIX) != 16'd0) ?
		 (raw_width_plus_eight <= raw_width_limit) :
		 (raw_src_x_plus_eight <= raw_width_limit));
	wire rle_output_ready = !rle_output_valid || vram_ack;
	// Fast RLE uses a unit signed X step. Eight transparent repeat pixels
	// have no source-byte or VRAM side effect, so retire them together. The
	// widened row bound prevents column wrap at widths near 65535. Literal,
	// scaled/skewed, packet-tail and row-tail work keeps the original path.
	wire [16:0] rle_col_plus_eight = {1'b0, rle_col} + 17'd8;
	wire rle_skip_eight = !op_rle_slow && op_flags[0] &&
		!rle_literal && rle_repeat_value == 8'hff && rle_count >= 7'd8 &&
		rle_col_plus_eight <= {1'b0, op_width};
	// This is the sole source-byte retirement predicate. Row/column decisions
	// precede byte parsing in ST_RLE_STREAM, and literal bytes also wait for the
	// registered output slot. Slot promotion can therefore use this predicate
	// without advancing any architectural parser state on a speculative ACK.
	wire rle_byte_consumed = (state == ST_RLE_STREAM) && rle_output_ready &&
		rle_position_active && rle_qword_hit &&
		rle_row < {7'd0,op_height} && rle_col < op_width &&
		(rle_wait_repeat || rle_count == 7'd0 || rle_literal);
	wire rle_boundary_consumed = rle_byte_consumed &&
		rle_pointer[2:0] == 3'b111;

	always_comb begin
		case (reg_addr_q)
			REG_STATUS:   reg_read_value = (video_regs[REG_STATUS] & 16'hfff7) | 16'h0005;
			REG_INTSTATE: reg_read_value = interrupt_state;
			REG_FLAGS:    reg_read_value = 16'h00ef;
			default:      reg_read_value = video_regs[reg_addr_q];
		endcase
	end

	always_comb begin
		grom_req  = 1'b0;
		grom_addr = '0;
		vram_req   = 1'b0;
		vram_we    = 1'b0;
		vram_plane = vram_plane_hold;
		vram_addr  = vram_addr_hold;
		vram_wdata = vram_wdata_hold;
		if (state == ST_RLE_STREAM) begin
			vram_req = rle_output_valid;
			vram_we = rle_output_valid;
			vram_plane = rle_output_plane;
			vram_addr = rle_output_addr;
			vram_wdata = rle_output_data;
		end
		if ((state == ST_RLE_STREAM || state == ST_RLE_FETCH_DRAIN) &&
			rle_fetch_valid) begin
			grom_req = 1'b1;
			grom_addr = rle_request_addr;
		end

		if (state == ST_RAW_GROM_ADDR)
			grom_addr = grom_addr_prep;
		if (state == ST_RAW_PROCESS)
			vram_addr = vram_addr_prep;
		if (state == ST_RAW_PROCESS) begin
			vram_plane = current_plane;
			vram_wdata = active_color(current_plane) | {8'd0, pixel_value};
			if (!(((op_flags & FLAG_TRANSPARENT) != 16'd0) &&
				pixel_value == 8'hff)) begin
				vram_req = 1'b1;
				vram_we = 1'b1;
			end
		end
		case (state)
			ST_RAW_GROM_ADDR: grom_req = !raw_qword_hit_q;

			ST_XFER_WRITE: begin
				vram_req = 1'b1;
				vram_we  = 1'b1;
			end
			ST_SHIFT_REPLAY: begin
				vram_req = shift_output_valid;
				vram_we = shift_output_valid;
				vram_plane = current_plane;
				vram_addr = shift_dest_base +
					VRAM_ADDR_WIDTH'(shift_output_word);
				vram_wdata = shift_output_data;
			end

			ST_XFER_READ,
			ST_SHIFT_READ: begin
				vram_req = 1'b1;
				vram_we  = 1'b0;
			end

			default: begin end
		endcase
	end

	assign busy = (state != ST_IDLE);
	assign irq_blitter = |(interrupt_state & video_regs[REG_INTENABLE] & INT_BLITTER);
	assign irq_scanline = |(interrupt_state & video_regs[REG_INTENABLE] & INT_SCANLINE);
	assign timing_int_scanline = video_regs[REG_INTSCANLINE];
	assign timing_vtotal       = video_regs[REG_VTOTAL];
	assign timing_vsync        = video_regs[REG_VSYNC];
	assign timing_vblank_start = video_regs[REG_VBLANKSTART];
	assign timing_vblank_end   = video_regs[REG_VBLANKEND];
	assign timing_htotal       = video_regs[REG_HTOTAL];
	assign timing_hsync        = video_regs[REG_HSYNC];
	assign timing_hblank_start = video_regs[REG_HBLANKSTART];
	assign timing_hblank_end   = video_regs[REG_HBLANKEND];
	assign display_xorigin1    = video_regs[REG_XORIGIN1];
	assign display_yorigin1    = video_regs[REG_YORIGIN1];
	assign display_xorigin2    = video_regs[REG_XORIGIN2];
	assign display_yorigin2    = video_regs[REG_YORIGIN2];
	assign display_xscroll2    = video_regs[REG_XSCROLL2];
	assign display_yscroll2    = video_regs[REG_YSCROLL2];

	// Present one address and one enable to the synchronous read port.  Keeping
	// the two replay cases out of separate array-read statements is required for
	// Quartus 17 to recognize this as one simple-dual-port M10K.  Command 6 fills
	// the complete source line before replay starts, so read-during-write is
	// unreachable.  shift_line_q is the first entry of the two-entry elastic
	// replay pipeline and holds while the output is stalled.
	always_comb begin
		shift_line_read_addr = 9'd0;
		shift_line_read_enable = 1'b0;
		if (state == ST_SHIFT_BUFFER_READ) begin
			shift_line_read_enable = 1'b1;
		end else if (state == ST_SHIFT_REPLAY && shift_fetch_valid &&
			(!shift_output_valid || vram_ack) && shift_fetch_word != 9'd511) begin
			shift_line_read_addr = shift_fetch_word + 9'd1;
			shift_line_read_enable = 1'b1;
		end
	end

	always_ff @(posedge clk) begin
		if (state == ST_SHIFT_READ && vram_ack)
			shift_line[shift_word[8:0]] <= vram_rdata;
		if (shift_line_read_enable)
			shift_line_q <= shift_line[shift_line_read_addr];
	end

	always_ff @(posedge clk) begin
		if (reset) begin
			interrupt_state <= 16'd0;
		end else begin
			interrupt_state <= (interrupt_state & ~interrupt_clear_now) |
				(scanline_event ? INT_SCANLINE : 16'd0) |
				(blitter_done_pulse ? INT_BLITTER : 16'd0);
		end
	end

	// The data/tag body is reset-free and is written only by an owned RAW miss
	// response. RLE replies and stray ACKs cannot publish or replace this slot.
	always_ff @(posedge clk) begin
		if (!reset && raw_qword_fill) begin
			raw_qword_data <= grom_rdata;
			raw_qword_tag <= grom_addr_prep[GROM_ADDR_WIDTH-1:3];
		end
		if (!reset && state == ST_RAW_CHECK)
			raw_qword_hit_q <= raw_qword_valid &&
				raw_qword_tag == raw_grom_addr_next[GROM_ADDR_WIDTH-1:3];
	end

	always_ff @(posedge clk) begin
		if (reset)
			raw_qword_valid <= 1'b0;
		// Invalidate at execution, not while the next command is fenced behind
		// the active blit. CHECK always recomputes hit before entering ADDR.
		else if (reg_pending && reg_command_write_q && state == ST_IDLE)
			raw_qword_valid <= 1'b0;
		else if (raw_qword_fill)
			raw_qword_valid <= 1'b1;
	end

	// CHECK is mandatory before ADVANCE, so this scheduling bit is reset-free
	// and state-masked. Keep wide eligibility comparisons off accumulator adds.
	always_ff @(posedge clk) begin
		if (!reset && state == ST_RAW_CHECK)
			raw_clip_skip_eight_q <= raw_clip_skip_eight;
	end

	always_ff @(posedge clk) begin
		reg_ack <= 1'b0;
		blitter_done_pulse <= 1'b0;

		if (reset) begin
			state <= ST_IDLE;
			reg_rdata <= 16'd0;
			reg_held <= 1'b0;
			reg_pending <= 1'b0;
			reg_we_q <= 1'b0;
			reg_addr_q <= 7'd0;
			reg_wdata_q <= 16'd0;
			reg_be_q <= 2'b00;
			reg_write_sel_q <= '0;
			reg_command_write_q <= 1'b0;
			reg_transfer_write_q <= 1'b0;
			reg_intstate_write_q <= 1'b0;
			reg_transfer_active_q <= 1'b0;
			reg_transfer_width_q <= 16'd0;
			reg_transfer_x_q <= 12'd0;
			command_value_q <= 16'd0;
			command_flags_q <= 16'd0;
			command_width_q <= 16'd0;
			command_height_q <= 9'd0;
			command_x_q <= 12'd0;
			command_y_q <= 12'd0;
			command_addrlo_q <= 16'd0;
			command_addrhi_q <= 8'd0;
			command_src_xstep_q <= 16'd0;
			command_src_ystep_q <= 16'd0;
			command_dst_xstep_q <= 16'd0;
			command_dst_ystep_q <= 16'd0;
			command_ystep_per_x_q <= 16'd0;
			command_xstep_per_y_q <= 16'd0;
			command_leftclip_q <= 16'd0;
			command_rightclip_q <= 16'd0;
			command_topclip_q <= 16'd0;
			command_bottomclip_q <= 16'd0;
			grom_addr_prep <= '0;
			vram_addr_prep <= '0;
			rle_wait_repeat <= 1'b0;
			rle_qword_valid <= 1'b0;
			rle_qword_data <= 64'd0;
			rle_next_qword_valid <= 1'b0;
			rle_next_qword_data <= 64'd0;
			rle_fetch_valid <= 1'b0;
			rle_fetch_next <= 1'b0;
			rle_fetch_drain_restart_plane <= 1'b0;
			rle_request_addr <= '0;
			rle_position_active <= 1'b0;
			rle_output_valid <= 1'b0;
			rle_output_addr <= '0;
			rle_output_data <= 16'd0;
			rle_output_plane <= 1'b0;
			shift_fetch_word <= 9'd0;
			shift_fetch_valid <= 1'b0;
			shift_output_word <= 9'd0;
			shift_output_valid <= 1'b0;
			shift_output_data <= 16'd0;
			for (index = 0; index < 128; index = index + 1)
				video_regs[index] <= 16'd0;
			color_latch[0] <= 16'd0;
			color_latch[1] <= 16'd0;
			xfer_xcount <= 16'd0;
			xfer_ycount <= 16'd0;
			xfer_xcur <= 16'd0;
			xfer_ycur <= 16'd0;
		end else begin
			// The GROM client returns the registered fetch role. A current response
			// advances the registered fetch address but does not request ahead until
			// the parser consumes a byte from that qword. This leaves seven or more
			// useful byte clocks to hide service while preventing a promoted-but-unused
			// qword from chaining a second unused request at command completion. A next
			// response fills the look-ahead slot, except on an exactly coincident
			// byte-seven retirement, where it becomes current directly.
			if (state == ST_RLE_STREAM && grom_ack && rle_fetch_valid) begin
				if (!rle_fetch_next) begin
					rle_qword_valid <= 1'b1;
					rle_qword_data <= grom_rdata;
					rle_request_addr <= rle_request_addr + GROM_ADDR_WIDTH'(8);
					rle_fetch_valid <= 1'b0;
					rle_fetch_next <= 1'b1;
				end else if (rle_boundary_consumed) begin
					rle_qword_valid <= 1'b1;
					rle_qword_data <= grom_rdata;
					rle_next_qword_valid <= 1'b0;
					rle_request_addr <= rle_request_addr + GROM_ADDR_WIDTH'(8);
					rle_fetch_valid <= 1'b0;
					rle_fetch_next <= 1'b1;
				end else begin
					rle_next_qword_valid <= 1'b1;
					rle_next_qword_data <= grom_rdata;
					rle_fetch_valid <= 1'b0;
				end
			end
			if (state == ST_RLE_STREAM && rle_boundary_consumed &&
				!(grom_ack && rle_fetch_valid && rle_fetch_next)) begin
				if (rle_next_qword_valid) begin
					rle_qword_valid <= 1'b1;
					rle_qword_data <= rle_next_qword_data;
					rle_next_qword_valid <= 1'b0;
					rle_request_addr <= rle_request_addr + GROM_ADDR_WIDTH'(8);
					rle_fetch_valid <= 1'b0;
					rle_fetch_next <= 1'b1;
				end else begin
					// The already-held next request is now demanded current data.
					rle_qword_valid <= 1'b0;
					rle_fetch_valid <= 1'b1;
					rle_fetch_next <= 1'b0;
				end
			end
			if (state == ST_RLE_STREAM && rle_byte_consumed &&
				!rle_boundary_consumed && !rle_next_qword_valid &&
				!rle_fetch_valid) begin
				// The current qword has now proved useful. Begin exactly one
				// sequential look-ahead request; no third slot can be generated.
				rle_fetch_valid <= 1'b1;
				rle_fetch_next <= 1'b1;
			end
			if (state == ST_RLE_STREAM && rle_output_valid && vram_ack)
				rle_output_valid <= 1'b0;
			if (state == ST_SHIFT_REPLAY && shift_fetch_valid &&
				(!shift_output_valid || vram_ack)) begin
				shift_output_valid <= 1'b1;
				shift_output_word <= shift_fetch_word;
				shift_output_data <= shift_line_q;
			end

			if (!reg_req)
				reg_held <= 1'b0;

			if (reg_req && !reg_held && !reg_pending) begin
				reg_pending <= 1'b1;
				reg_held <= 1'b1;
				reg_we_q <= reg_we;
				reg_addr_q <= reg_addr;
				reg_wdata_q <= reg_wdata;
				reg_be_q <= reg_be;
				// Command and interrupt-state accesses always have dedicated
				// semantics below.  Transfer writes use their dedicated path only
				// while command 3 is active, then deliberately fall through to an
				// ordinary register write.  Decode that address along with every
				// general write so reg_addr_q is absent from register D/WE.
				if (reg_we && reg_addr != REG_COMMAND && reg_addr != REG_INTSTATE)
					reg_write_sel_q <= decode_register_write(reg_addr);
				else
					reg_write_sel_q <= '0;
				reg_command_write_q <= reg_we && reg_addr == REG_COMMAND;
				reg_transfer_write_q <= reg_we && reg_addr == REG_TRANSFER;
				reg_intstate_write_q <= reg_we && reg_addr == REG_INTSTATE;
				reg_transfer_active_q <= reg_we && reg_addr == REG_TRANSFER &&
					video_regs[REG_COMMAND] == 16'd3 && xfer_ycount != 16'd0;

				if (reg_we && reg_addr == REG_TRANSFER) begin
					// Width/X are live command-3 row-reload values in MAME.  The
					// CPU cannot change them while this held transfer is in flight,
					// so capturing them here preserves that behavior and removes the
					// register-file path from the eventual VRAM completion edge.
					reg_transfer_width_q <= video_regs[REG_WIDTH];
					reg_transfer_x_q <= video_regs[REG_X][11:0];
				end

				if (reg_we && reg_addr == REG_COMMAND) begin
					// Snapshot the video register file at the existing request stage.
					// Command execution is already one cycle later (reg_pending), so
					// derived state can be initialized solely from these narrow banks.
					command_value_q <= accepted_command_value;
					command_flags_q <= video_regs[REG_FLAGS];
					command_width_q <= video_regs[REG_WIDTH];
					command_height_q <= adjusted_height(video_regs[REG_HEIGHT]);
					command_x_q <= video_regs[REG_X][11:0];
					command_y_q <= video_regs[REG_Y][11:0];
					command_addrlo_q <= video_regs[REG_ADDRLO];
					command_addrhi_q <= video_regs[REG_ADDRHI][7:0];
					command_src_xstep_q <= video_regs[REG_SRC_XSTEP];
					command_src_ystep_q <= video_regs[REG_SRC_YSTEP];
					command_dst_xstep_q <= video_regs[REG_DST_XSTEP];
					command_dst_ystep_q <= video_regs[REG_DST_YSTEP];
					command_ystep_per_x_q <= video_regs[REG_YSTEP_PER_X];
					command_xstep_per_y_q <= video_regs[REG_XSTEP_PER_Y];
					command_leftclip_q <= video_regs[REG_LEFTCLIP];
					command_rightclip_q <= video_regs[REG_RIGHTCLIP];
					command_topclip_q <= video_regs[REG_TOPCLIP];
					command_bottomclip_q <= video_regs[REG_BOTTOMCLIP];
				end
			end

			if (color0_we) begin
				if (timekill_mode)
					color_latch[0] <= {4'd0, color_data[3:0], 8'h00};
				else
					color_latch[0] <= {color_data, 8'h00} & 16'h7f00;
			end
			if (color1_we) begin
				if (timekill_mode)
					color_latch[1] <= {3'd0, 1'b1, color_data[7:4], 8'h00};
				else
					color_latch[1] <= {color_data, 8'h00} & 16'h7f00;
			end

			// Register accesses other than a command are allowed while the engine
			// is running.  Command writes wait until the current command is idle.
			if (reg_pending && !(reg_command_write_q && state != ST_IDLE)) begin
				reg_pending <= 1'b0;
				if (!reg_we_q) begin
					reg_rdata <= reg_read_value;
					reg_ack <= 1'b1;
				end else if (reg_intstate_write_q) begin
					reg_ack <= 1'b1;
				end else if (reg_transfer_write_q && reg_transfer_active_q) begin
					xfer_cpu_pixel <= reg_wdata_q[7:0];
					video_regs[REG_TRANSFER] <= merged_transfer_value;
					if (plane_enable[0] || plane_enable[1]) begin
						xfer_plane <= plane_enable[0] ? 1'b0 : 1'b1;
						vram_plane_hold <= plane_enable[0] ? 1'b0 : 1'b1;
						vram_addr_hold <= integer_vram_address(xfer_xcur[11:0], xfer_ycur[11:0]);
						state <= ST_XFER_READ;
					end else begin
						if (xfer_xcount > 16'd1) begin
							xfer_xcount <= xfer_xcount - 16'd1;
							xfer_xcur <= xfer_xcur + 16'd1;
						end else if (xfer_ycount > 16'd1) begin
							xfer_xcount <= reg_transfer_width_q;
							xfer_ycount <= xfer_ycount - 16'd1;
							xfer_xcur <= {4'd0, reg_transfer_x_q};
							xfer_ycur <= xfer_ycur + 16'd1;
						end else begin
							xfer_xcount <= 16'd0;
							xfer_ycount <= 16'd0;
						end
						reg_ack <= 1'b1;
					end
				end else if (reg_command_write_q) begin
					video_regs[REG_COMMAND] <= command_value_q;
					reg_ack <= 1'b1;

					// Snapshot every operand; software may update registers while the
					// sequential engine is active without perturbing this command.
					op_flags <= command_flags_q;
					op_width <= command_width_q;
					op_height <= command_height_q;
					op_x <= command_x_q;
					op_y <= command_y_q;
					op_src_xstep <= command_src_xstep_q;
					op_src_ystep <= command_src_ystep_q;
					op_ystep_per_x <= command_ystep_per_x_q;
					op_grom_base <= {grom_bank, command_addrhi_q, command_addrlo_q};
					op_color[0] <= color_latch[0];
					op_color[1] <= color_latch[1];
					op_plane1_enabled <= plane_enable[1];

					if ((command_flags_q & FLAG_CLIP) != 16'd0) begin
						op_clip_min_x <= $signed({16'd0, command_leftclip_q}) <<< 8;
						op_clip_max_x <= $signed({16'd0, command_rightclip_q}) <<< 8;
						op_clip_min_y <= $signed({16'd0, command_topclip_q}) <<< 8;
						op_clip_max_y <= $signed({16'd0, command_bottomclip_q}) <<< 8;
					end else begin
						op_clip_min_x <= 32'sd0;
						op_clip_max_x <= 32'sh000fff00;
						op_clip_min_y <= 32'sd0;
						op_clip_max_y <= 32'sh000fff00;
					end

					op_dx <= ((command_flags_q & FLAG_XFLIP) != 16'd0) ?
						-$signed({16'd0, ((command_flags_q & FLAG_DSTXSCALE) != 16'd0) ? command_dst_xstep_q : 16'h0100}) :
						 $signed({16'd0, ((command_flags_q & FLAG_DSTXSCALE) != 16'd0) ? command_dst_xstep_q : 16'h0100});
					op_dy <= ((command_flags_q & FLAG_YFLIP) != 16'd0) ?
						-$signed({16'd0, command_dst_ystep_q}) :
						 $signed({16'd0, command_dst_ystep_q});
					op_dty <= ((command_flags_q & FLAG_DYDXSIGN) != 16'd0) ?
						-$signed({16'd0, command_ystep_per_x_q}) :
						 $signed({16'd0, command_ystep_per_x_q});
					op_row_skew <= ((command_flags_q & FLAG_DXDYSIGN) != 16'd0) ?
						 $signed({16'd0, command_xstep_per_y_q}) :
						-$signed({16'd0, command_xstep_per_y_q});
					op_rle_slow <= (((command_flags_q & FLAG_DSTXSCALE) != 0) && command_dst_xstep_q != 16'h0100) ||
						(command_xstep_per_y_q != 16'd0);

					current_plane <= plane_enable[0] ? 1'b0 : 1'b1;
					case (command_value_q)
						16'd1: begin
							if (!(plane_enable[0] || plane_enable[1]) || command_width_q == 16'd0 ||
								command_height_q == 9'd0 ||
								command_src_xstep_q == 16'd0 || command_src_ystep_q == 16'd0) begin
								blitter_done_pulse <= 1'b1;
							end else begin
								src_x_acc <= 32'd0;
								src_y_acc <= 32'd0;
								pixel_width_acc <= 32'd0;
								dst_x_acc <= $signed({20'd0, command_x_q}) <<< 8;
								dst_y_acc <= $signed({20'd0, command_y_q}) <<< 8;
								dst_ty_acc <= $signed({20'd0, command_y_q}) <<< 8;
								row_start_x <= $signed({20'd0, command_x_q}) <<< 8;
								raw_row_base <= '0;
								state <= ST_RAW_CHECK;
							end
						end

						16'd2: begin
							if (!(plane_enable[0] || plane_enable[1]) || command_height_q == 9'd0) begin
								blitter_done_pulse <= 1'b1;
							end else begin
								rle_row <= 16'd0;
								rle_col <= 16'd0;
							rle_count <= 7'd0;
							rle_literal <= 1'b0;
								rle_wait_repeat <= 1'b0;
								rle_qword_valid <= 1'b0;
								rle_next_qword_valid <= 1'b0;
								rle_fetch_valid <= 1'b1;
								rle_fetch_next <= 1'b0;
								rle_fetch_drain_restart_plane <= 1'b0;
								rle_output_valid <= 1'b0;
								rle_pointer <= {grom_bank, command_addrhi_q, command_addrlo_q};
								rle_request_addr <= {grom_bank, command_addrhi_q,
									command_addrlo_q[15:3], 3'b000};
								rle_position_active <= command_width_q != 16'd0;
								dst_x_acc <= $signed({20'd0, command_x_q}) <<< 8;
								dst_y_acc <= $signed({20'd0, command_y_q}) <<< 8;
								row_start_x <= $signed({20'd0, command_x_q}) <<< 8;
								state <= ST_RLE_STREAM;
							end
						end

						16'd3: begin
							xfer_xcount <= command_width_q;
							xfer_ycount <= {7'd0, command_height_q};
							xfer_xcur <= {4'd0, command_x_q};
							xfer_ycur <= {4'd0, command_y_q};
							blitter_done_pulse <= 1'b1;
						end

						16'd6: begin
							if (!(plane_enable[0] || plane_enable[1]) || command_height_q <= 9'd1) begin
								blitter_done_pulse <= 1'b1;
							end else begin
								shift_row <= 9'd1;
								shift_word <= 10'd0;
								shift_fetch_word <= 9'd0;
								shift_fetch_valid <= 1'b0;
								shift_output_word <= 9'd0;
								shift_output_valid <= 1'b0;
								shift_source_base <= integer_vram_address(command_x_q, command_y_q);
								if ((command_flags_q & FLAG_YFLIP) != 16'd0)
									shift_dest_base <= integer_vram_address(command_x_q, command_y_q - 12'd1);
								else
									shift_dest_base <= integer_vram_address(command_x_q, command_y_q + 12'd1);
								vram_plane_hold <= plane_enable[0] ? 1'b0 : 1'b1;
								vram_addr_hold <= integer_vram_address(command_x_q, command_y_q);
								state <= ST_SHIFT_READ;
							end
						end

						default: blitter_done_pulse <= 1'b1;
					endcase
				end else begin
					// Byte merging is expressed per lane at the selected register.
					// This is behaviorally identical to merge_word(old, data, be),
					// while each destination sees only its registered one-hot bit.
					for (index = 0; index < 128; index = index + 1) begin
						if (reg_write_sel_q[index]) begin
							if (reg_be_q[0])
								video_regs[index][7:0] <= reg_wdata_q[7:0];
							if (reg_be_q[1])
								video_regs[index][15:8] <= reg_wdata_q[15:8];
						end
					end
					reg_ack <= 1'b1;
				end
			end

			case (state)
				ST_IDLE: begin end

				ST_RAW_CHECK: begin
					// This value is harmless on clipped/end-of-row cycles.  Computing it
					// unconditionally prevents those decisions from becoming the write
					// enable on the downstream held GROM address.
					grom_addr_prep <= raw_grom_addr_next;
					// Prepare the destination while the GROM fetch is outstanding.  The
					// later PROCESS state can therefore enter the write FIFO directly
					// without placing the accumulator cone on the M10K data input.
					vram_addr_prep <= fixed_vram_address(dst_x_acc,
						(op_ystep_per_x == 16'd0) ? dst_y_acc : dst_ty_acc);
					if (src_y_acc >= ({23'd0, op_height} << 8)) begin
						if (!current_plane && op_plane1_enabled) begin
							current_plane <= 1'b1;
							src_x_acc <= 32'd0;
							src_y_acc <= 32'd0;
							pixel_width_acc <= 32'd0;
							dst_x_acc <= $signed({20'd0, op_x}) <<< 8;
							dst_y_acc <= $signed({20'd0, op_y}) <<< 8;
							dst_ty_acc <= $signed({20'd0, op_y}) <<< 8;
							row_start_x <= $signed({20'd0, op_x}) <<< 8;
							raw_row_base <= '0;
						end else begin
							state <= ST_WAIT_DRAIN;
						end
					end else if (((op_flags & FLAG_WIDTHPIX) != 0 && pixel_width_acc >= ({16'd0, op_width} << 8)) ||
						((op_flags & FLAG_WIDTHPIX) == 0 && src_x_acc >= ({16'd0, op_width} << 8)) ||
						(op_ystep_per_x != 16'd0 && dst_x_acc >= op_clip_max_x)) begin
						state <= ST_RAW_ROW_ADVANCE;
					end else if (raw_row_outside_y) begin
						state <= ST_RAW_ROW_ADVANCE;
					end else if (!raw_inside_clip()) begin
						state <= ST_RAW_ADVANCE;
					end else begin
						state <= ST_RAW_GROM_ADDR;
					end
				end

				// Keep the row-end comparison out of the accumulator feedback cone.
				// ST_RAW_CHECK selects this state; the updates are otherwise exactly
				// the original row-advance operation and preserve nonblocking ordering.
				ST_RAW_ROW_ADVANCE: begin
					src_y_acc <= src_y_acc + {16'd0, op_src_ystep};
					raw_row_base <= GROM_ADDR_WIDTH'(((src_y_acc + {16'd0, op_src_ystep}) >> 8) * op_width);
					src_x_acc <= 32'd0;
					pixel_width_acc <= 32'd0;
					dst_y_acc <= dst_y_acc + op_dy;
					row_start_x <= row_start_x + op_row_skew;
					dst_x_acc <= row_start_x + op_row_skew;
					dst_ty_acc <= dst_y_acc + op_dy;
					state <= ST_RAW_CHECK;
				end

				ST_RAW_GROM_ADDR: begin
					if (raw_qword_hit_q) begin
						pixel_value <= grom_line_byte(raw_qword_data, grom_addr_prep[2:0]);
						state <= ST_RAW_PROCESS;
					end else if (grom_ack) begin
						pixel_value <= grom_response_byte;
						state <= ST_RAW_PROCESS;
					end
				end

				ST_RAW_PROCESS: begin
					if ((((op_flags & FLAG_TRANSPARENT) != 16'd0) && pixel_value == 8'hff) ||
						vram_ack) begin
						src_x_acc <= src_x_acc + {16'd0, op_src_xstep};
						pixel_width_acc <= pixel_width_acc + 32'h100;
						dst_x_acc <= dst_x_acc + op_dx;
						dst_ty_acc <= dst_ty_acc + op_dty;
						state <= ST_RAW_CHECK;
					end
				end

				ST_RAW_ADVANCE: begin
					src_x_acc <= src_x_acc + (raw_clip_skip_eight_q ?
						{13'd0, op_src_xstep, 3'b000} : {16'd0, op_src_xstep});
					pixel_width_acc <= pixel_width_acc +
						(raw_clip_skip_eight_q ? 32'd2048 : 32'd256);
					dst_x_acc <= dst_x_acc + (raw_clip_skip_eight_q ?
						(op_dx[31] ? -32'sd2048 : 32'sd2048) : op_dx);
					dst_ty_acc <= dst_ty_acc + op_dty;
					state <= ST_RAW_CHECK;
				end

				// Throughput-oriented command-2 engine.  Parser state advances only
				// when the registered output slot is empty or accepted.  The output
				// payload is therefore stable throughout backpressure, while accepted
				// visible pixels can be replaced every fabric clock. Control bytes and
				// row transitions consume parser cycles but no longer round-trip through
				// the legacy CHECK/PROCESS FSM for every decoded pixel.
				ST_RLE_STREAM: if (rle_output_ready) begin
					if (rle_row >= {7'd0, op_height}) begin
						if (!current_plane && op_plane1_enabled) begin
							if (rle_fetch_valid && !grom_ack) begin
								// A speculative request is already owned by the memory
								// front. Hold its valid/address through ACK, discard the
								// response, then restart plane 1 at the frozen base.
								rle_position_active <= 1'b0;
								rle_qword_valid <= 1'b0;
								rle_next_qword_valid <= 1'b0;
								rle_fetch_drain_restart_plane <= 1'b1;
								state <= ST_RLE_FETCH_DRAIN;
							end else begin
								current_plane <= 1'b1;
								rle_row <= 16'd0;
								rle_col <= 16'd0;
								rle_count <= 7'd0;
								rle_literal <= 1'b0;
								rle_wait_repeat <= 1'b0;
								rle_qword_valid <= 1'b0;
								rle_next_qword_valid <= 1'b0;
								rle_fetch_valid <= 1'b1;
								rle_fetch_next <= 1'b0;
								rle_fetch_drain_restart_plane <= 1'b0;
								rle_pointer <= op_grom_base;
								rle_request_addr <= {op_grom_base[GROM_ADDR_WIDTH-1:3],
									3'b000};
								rle_position_active <= op_width != 16'd0 &&
									op_height != 9'd0;
								dst_x_acc <= $signed({20'd0, op_x}) <<< 8;
								dst_y_acc <= $signed({20'd0, op_y}) <<< 8;
								row_start_x <= $signed({20'd0, op_x}) <<< 8;
							end
						end else begin
							rle_position_active <= 1'b0;
							rle_qword_valid <= 1'b0;
							rle_next_qword_valid <= 1'b0;
							if (rle_fetch_valid && !grom_ack) begin
								rle_fetch_drain_restart_plane <= 1'b0;
								state <= ST_RLE_FETCH_DRAIN;
							end else begin
								rle_fetch_valid <= 1'b0;
								rle_fetch_drain_restart_plane <= 1'b0;
								state <= ST_WAIT_DRAIN;
							end
						end
					end else if (rle_col >= op_width) begin
						rle_row <= rle_row + 16'd1;
						rle_col <= 16'd0;
						rle_position_active <= op_width != 16'd0 &&
							(rle_row + 16'd1) < {7'd0, op_height};
						dst_y_acc <= dst_y_acc + op_dy;
						if (op_rle_slow) begin
							row_start_x <= row_start_x + op_row_skew;
							dst_x_acc <= row_start_x + op_row_skew;
						end else begin
							dst_x_acc <= $signed({20'd0, op_x}) <<< 8;
						end
					end else if (rle_wait_repeat) begin
						if (rle_qword_hit) begin
							rle_repeat_value <= rle_stream_byte;
							rle_pointer <= rle_pointer + 1'b1;
							rle_wait_repeat <= 1'b0;
						end
					end else if (rle_count == 7'd0) begin
						if (rle_qword_hit) begin
							rle_pointer <= rle_pointer + 1'b1;
							if (rle_stream_byte[6:0] == 7'd0) begin
								rle_position_active <= 1'b0;
								rle_qword_valid <= 1'b0;
								rle_next_qword_valid <= 1'b0;
								if (rle_fetch_valid && !grom_ack) begin
									rle_fetch_drain_restart_plane <= 1'b0;
									state <= ST_RLE_FETCH_DRAIN;
								end else begin
									rle_fetch_valid <= 1'b0;
									rle_fetch_drain_restart_plane <= 1'b0;
									state <= ST_WAIT_DRAIN;
								end
							end else begin
								rle_count <= rle_stream_byte[6:0];
								rle_literal <= rle_stream_byte[7];
								rle_wait_repeat <= !rle_stream_byte[7];
							end
						end
					end else if (rle_skip_eight) begin
						rle_count <= rle_count - 7'd8;
						rle_col <= rle_col_plus_eight[15:0];
						rle_position_active <= rle_col_plus_eight < {1'b0, op_width};
						dst_x_acc <= dst_x_acc + (op_flags[1] ? -32'sd2048 : 32'sd2048);
						rle_output_valid <= 1'b0;
					end else if (!rle_literal || rle_qword_hit) begin
						if (rle_literal) begin
							rle_pointer <= rle_pointer + 1'b1;
						end
						rle_count <= rle_count - 7'd1;
						rle_col <= rle_col + 16'd1;
						rle_position_active <=
							(rle_col + 16'd1) < op_width;
						dst_x_acc <= dst_x_acc + op_dx;
						rle_output_addr <= fixed_vram_address(dst_x_acc,
							dst_y_acc);
						rle_output_plane <= current_plane;
						rle_output_data <= active_color(current_plane) |
							{8'd0, rle_literal ? rle_stream_byte :
								rle_repeat_value};
						rle_output_valid <= rle_inside_clip() &&
							!(((op_flags & FLAG_TRANSPARENT) != 16'd0) &&
							 (rle_literal ? rle_stream_byte :
								rle_repeat_value) == 8'hff);
					end
				end

				ST_XFER_READ: if (vram_ack) begin
					xfer_old_pixel <= vram_rdata;
					// Command 3 uses the live color latch on every port write.
					vram_wdata_hold <= color_latch[xfer_plane] | {8'd0, xfer_cpu_pixel};
					state <= ST_XFER_WRITE;
				end

				ST_XFER_WRITE: if (vram_ack) begin
					video_regs[REG_TRANSFER] <= xfer_old_pixel;
					if (!xfer_plane && plane_enable[1]) begin
						xfer_plane <= 1'b1;
						vram_plane_hold <= 1'b1;
						vram_addr_hold <= integer_vram_address(xfer_xcur[11:0], xfer_ycur[11:0]);
						state <= ST_XFER_READ;
					end else begin
						if (xfer_xcount > 16'd1) begin
							xfer_xcount <= xfer_xcount - 16'd1;
							xfer_xcur <= xfer_xcur + 16'd1;
						end else if (xfer_ycount > 16'd1) begin
							xfer_xcount <= reg_transfer_width_q;
							xfer_ycount <= xfer_ycount - 16'd1;
							xfer_xcur <= {4'd0, reg_transfer_x_q};
							xfer_ycur <= xfer_ycur + 16'd1;
						end else begin
							xfer_xcount <= 16'd0;
							xfer_ycount <= 16'd0;
						end
						state <= ST_IDLE;
						reg_ack <= 1'b1;
					end
				end

				ST_SHIFT_READ: if (vram_ack) begin
					if (shift_word == 10'd511) begin
						shift_word <= 10'd0;
						// The entire 512-word source snapshot is now durable in the
						// M10K.  Only after this edge may destination traffic begin.
						shift_fetch_word <= 9'd0;
						shift_fetch_valid <= 1'b0;
						shift_output_valid <= 1'b0;
						state <= ST_SHIFT_BUFFER_READ;
					end else begin
						shift_word <= shift_word + 10'd1;
						vram_addr_hold <= shift_source_base + VRAM_ADDR_WIDTH'(shift_word) + 1'b1;
					end
				end

				ST_SHIFT_BUFFER_READ: begin
					shift_fetch_word <= 9'd0;
					shift_fetch_valid <= 1'b1;
					shift_output_valid <= 1'b0;
					state <= ST_SHIFT_REPLAY;
				end

				// A two-entry elastic pipe surrounds the one-cycle M10K read.  Its
				// output payload is registered and remains stable while vram_ack is
				// low.  On every accepted word the next RAM result replaces it and a
				// new read is issued, so steady-state replay is one word per clock.
				ST_SHIFT_REPLAY: begin
					if (!shift_output_valid || vram_ack) begin
						if (shift_fetch_valid) begin
							if (shift_fetch_word != 9'd511) begin
								shift_fetch_word <= shift_fetch_word + 1'b1;
								shift_fetch_valid <= 1'b1;
							end else begin
								shift_fetch_valid <= 1'b0;
							end
						end else if (!shift_output_valid) begin
							shift_fetch_word <= 9'd0;
							shift_fetch_valid <= 1'b1;
						end
					end

					if (shift_output_valid && vram_ack &&
						shift_output_word == 9'd511) begin
						shift_fetch_valid <= 1'b0;
						if (shift_row + 9'd1 >= op_height) begin
							if (!current_plane && op_plane1_enabled) begin
								current_plane <= 1'b1;
								vram_plane_hold <= 1'b1;
								shift_row <= 9'd1;
								shift_word <= 10'd0;
								vram_addr_hold <= shift_source_base;
								shift_dest_base <= integer_vram_address(op_x,
									(op_flags & FLAG_YFLIP) != 16'd0 ?
										(op_y - 12'd1) : (op_y + 12'd1));
								shift_fetch_valid <= 1'b0;
								shift_output_valid <= 1'b0;
								state <= ST_SHIFT_READ;
							end else begin
								shift_output_valid <= 1'b0;
								state <= ST_WAIT_DRAIN;
							end
						end else begin
							shift_row <= shift_row + 9'd1;
							if ((op_flags & FLAG_YFLIP) != 16'd0)
								shift_dest_base <= integer_vram_address(op_x,
									op_y - {3'd0, (shift_row + 9'd1)});
							else
								shift_dest_base <= integer_vram_address(op_x,
									op_y + {3'd0, (shift_row + 9'd1)});
							state <= ST_SHIFT_BUFFER_READ;
						end
					end
				end

				// MAME raises the blitter interrupt only after the command has
				// synchronously mutated VRAM.  The FPGA write port instead ACKs when
				// its FIFO retains a pixel, so wait for that accepted sequence to
				// drain before publishing completion.  No wide payload depends on
				// this signal; it controls only this narrow state transition.
				ST_RLE_FETCH_DRAIN: begin
					// The compressed stream no longer needs this speculative
					// response, but an asserted request remains owned until ACK.
					// Do not change its registered address or expose its data.
					if (grom_ack) begin
						rle_qword_valid <= 1'b0;
						rle_next_qword_valid <= 1'b0;
						if (rle_fetch_drain_restart_plane) begin
							current_plane <= 1'b1;
							rle_row <= 16'd0;
							rle_col <= 16'd0;
							rle_count <= 7'd0;
							rle_literal <= 1'b0;
							rle_wait_repeat <= 1'b0;
							rle_fetch_valid <= 1'b1;
							rle_fetch_next <= 1'b0;
							rle_fetch_drain_restart_plane <= 1'b0;
							rle_pointer <= op_grom_base;
							rle_request_addr <= {op_grom_base[GROM_ADDR_WIDTH-1:3],
								3'b000};
							rle_position_active <= op_width != 16'd0 &&
								op_height != 9'd0;
							dst_x_acc <= $signed({20'd0, op_x}) <<< 8;
							dst_y_acc <= $signed({20'd0, op_y}) <<< 8;
							row_start_x <= $signed({20'd0, op_x}) <<< 8;
							state <= ST_RLE_STREAM;
						end else begin
							rle_fetch_valid <= 1'b0;
							rle_fetch_next <= 1'b0;
							rle_fetch_drain_restart_plane <= 1'b0;
							state <= ST_WAIT_DRAIN;
						end
					end
				end

				ST_WAIT_DRAIN: if (!vram_writes_pending) begin
					state <= ST_IDLE;
					blitter_done_pulse <= 1'b1;
				end

				default: state <= ST_IDLE;
			endcase
		end
	end

`ifdef VERILATOR
	logic sim_raw_grom_held;
	logic [GROM_ADDR_WIDTH-1:0] sim_raw_grom_addr;
	logic sim_rle_grom_held;
	logic [GROM_ADDR_WIDTH-1:0] sim_rle_grom_addr;
	logic sim_rle_output_stalled;
	logic [VRAM_ADDR_WIDTH-1:0] sim_rle_output_addr;
	logic [15:0] sim_rle_output_data;
	logic sim_rle_output_plane;

	always_ff @(posedge clk) begin
		if (reset) begin
			sim_raw_grom_held <= 1'b0;
			sim_raw_grom_addr <= '0;
			sim_rle_grom_held <= 1'b0;
			sim_rle_grom_addr <= '0;
			sim_rle_output_stalled <= 1'b0;
			sim_rle_output_addr <= '0;
			sim_rle_output_data <= '0;
			sim_rle_output_plane <= 1'b0;
		end else begin
			if (sim_raw_grom_held) begin
				assert (grom_req && grom_addr == sim_raw_grom_addr)
					else $fatal(1,"RAW GROM payload changed before ACK");
			end
			sim_raw_grom_held <= state == ST_RAW_GROM_ADDR && grom_req && !grom_ack;
			sim_raw_grom_addr <= grom_addr;
			if (state == ST_RAW_GROM_ADDR && raw_qword_hit_q) begin
				assert (raw_qword_valid && !grom_req &&
					raw_qword_tag == grom_addr_prep[GROM_ADDR_WIDTH-1:3])
					else $fatal(1,"RAW held qword lacks matching unique owner");
			end
			// A demand boundary may reclassify next as current but cannot alter
			// the held transaction. Explicit stream completion/restart first clears
			// rle_position_active and is the only cancellation exception.
			if (sim_rle_grom_held) begin
				assert (grom_req && grom_addr == sim_rle_grom_addr)
					else $fatal(1,"RLE GROM payload changed before ACK");
			end
			sim_rle_grom_held <= (state == ST_RLE_STREAM ||
				state == ST_RLE_FETCH_DRAIN) && grom_req && !grom_ack;
			sim_rle_grom_addr <= grom_addr;

			if (sim_rle_output_stalled) begin
				assert (rle_output_valid && rle_output_addr == sim_rle_output_addr &&
					rle_output_data == sim_rle_output_data &&
					rle_output_plane == sim_rle_output_plane)
					else $fatal(1,"RLE output payload changed while stalled");
			end
			sim_rle_output_stalled <= state == ST_RLE_STREAM &&
				rle_output_valid && !vram_ack;
			sim_rle_output_addr <= rle_output_addr;
			sim_rle_output_data <= rle_output_data;
			sim_rle_output_plane <= rle_output_plane;

			if (state == ST_RLE_STREAM) begin
				assert (!(rle_next_qword_valid &&
					(!rle_qword_valid || rle_fetch_valid)))
					else $fatal(1,"RLE next slot lacks unique current owner");
				if (rle_fetch_valid && rle_fetch_next)
					assert (rle_qword_valid)
						else $fatal(1,"RLE next fetch lacks current slot");
				if (rle_fetch_valid && !rle_fetch_next)
					assert (!rle_qword_valid)
						else $fatal(1,"RLE current fetch overlaps current slot");
				if (rle_position_active && !rle_qword_valid &&
					(rle_wait_repeat || rle_count == 7'd0 || rle_literal))
					assert (rle_fetch_valid && !rle_fetch_next)
						else $fatal(1,"RLE demanded byte has no current fetch owner");
			end
			if (state == ST_RLE_FETCH_DRAIN) begin
				assert (rle_fetch_valid && !rle_position_active)
					else $fatal(1,"RLE fetch drain lost its sole request owner");
			end
		end
	end
`endif

endmodule
