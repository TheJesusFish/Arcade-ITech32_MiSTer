// SPDX-License-Identifier: GPL-2.0-or-later
//
// Executable ITech32 board slice.  This module owns protocol integration, not
// physical storage: program ROM, graphics ROM, and dual-plane framebuffer
// memory remain explicit request/ack interfaces for SDRAM/DDR selection above.
`timescale 1ns/1ps

module itech32_board #(
	parameter integer LINE_PIXELS = 384,
	parameter integer SCAN_ROW_WORDS = (LINE_PIXELS + 6) / 4
) (
	input  logic        clk,
	input  logic        reset,
	input  logic        timekill_mode,
	input  logic        bloodstorm_mode,
	input  logic        rom_buffer_invalidate,
	input  logic        ce_cpu,
	input  logic        ce_pixel,

	// Boot-vector copy port.  Load dword indices 0..31 while reset is held.
	input  logic        vector_load_we,
	input  logic [4:0]  vector_load_addr,
	input  logic [31:0] vector_load_wdata,
	input  logic [3:0]  vector_load_be,

	input  logic [31:0] input_p1,
	input  logic [31:0] input_p2,
	input  logic [31:0] input_p3,
	input  logic [31:0] input_p4,
	input  logic [31:0] input_dips,
	input  logic [31:0] input_extra,
	input  logic [14:0] protection_address,
	input  logic        nvram_host_access,
	input  logic        nvram_host_write,
	input  logic [16:0] nvram_host_addr,
	input  logic [15:0] nvram_host_wdata,
	output logic [15:0] nvram_host_rdata,
	output logic        nvram_cpu_write,

	// Reserved for sound/board sources owned by another integration block.
	// The encoded active-high level is priority-combined with video IRQs.
	input  logic [2:0]  auxiliary_irq_level,
	output logic        sound_command_valid,
	output logic [7:0]  sound_command,
	output logic        special_read_strobe,
	output logic        watchdog_strobe,

	output logic        program_rom_req,
	output logic [21:0] program_rom_addr,
	input  logic        program_rom_ack,
	input  logic [31:0] program_rom_rdata,

	output logic        grom_req,
	output logic [25:0] grom_addr,
	input  logic        grom_ack,
	input  logic [63:0] grom_rdata,

	output logic        vram_mem_req,
	output logic        vram_mem_we,
	output logic [19:0] vram_mem_addr,
	output logic [15:0] vram_mem_wdata,
	output logic [1:0]  vram_mem_be,
	input  logic        vram_mem_ack,
	input  logic [15:0] vram_mem_rdata,
	output logic        vram_qwrite_req,
	output logic [17:0] vram_qwrite_addr,
	output logic [63:0] vram_qwrite_data,
	output logic [7:0]  vram_qwrite_be,
	output logic        vram_qwrite_token,
	input  logic        vram_qwrite_ack,

	output logic        scanline_req,
	output logic [19:0] scanline_addr,
	input  logic        scanline_accept,
	input  logic        scanline_data_valid,
	input  logic [63:0] scanline_rdata,
	input  logic        scanline_last,

	output logic [9:0]  hpos,
	output logic [9:0]  vpos,
	output logic        hblank,
	output logic        vblank,
	output logic        hsync,
	output logic        vsync,
	output logic [15:0] pixel_data,
	output logic [14:0] pixel_index,
	output logic [23:0] rgb,
	output logic        pixel_valid,
	output logic        scanout_underflow,
	output logic        video_configured,

	output logic        blitter_busy,
	output logic        irq_vblank,
	output logic        irq_blitter,
	output logic        irq_scanline,
	output logic [15:0] video_interrupt_state,
	output logic [2:0]  cpu_irq_level,

	output logic [31:0] debug_cpu_addr,
	output logic [1:0]  debug_cpu_busstate
);

	logic        cpu_req;
	logic        cpu_we;
	logic [23:0] cpu_addr;
	logic [31:0] cpu_wdata;
	logic [3:0]  cpu_be;
	logic        cpu_ack;
	logic [31:0] cpu_rdata;
	logic        debug_nwr, debug_nuds, debug_nlds;
	logic [2:0]  debug_fc;

	logic        video_req;
	logic        video_we;
	logic [6:0]  video_addr;
	logic [15:0] video_wdata;
	logic [1:0]  video_be;
	logic        video_ack;
	logic [15:0] video_rdata;
	logic        color0_strobe, color1_strobe;
	logic        vint_ack_strobe;
	logic [7:0]  color_data;
	logic [1:0]  plane_enable;
	logic [1:0]  grom_bank;

	logic [15:0] timing_int_scanline;
	logic [15:0] timing_vtotal, timing_vsync;
	logic [15:0] timing_vblank_start, timing_vblank_end;
	logic [15:0] timing_htotal, timing_hsync;
	logic [15:0] timing_hblank_start, timing_hblank_end;
	logic [15:0] display_xorigin1, display_yorigin1;
	logic [15:0] display_xorigin2, display_yorigin2;
	logic [15:0] display_xscroll2, display_yscroll2;
	logic [9:0]  timing_int_scanline_q;
	logic [9:0]  timing_vtotal_q, timing_vsync_q;
	logic [9:0]  timing_vblank_start_q, timing_vblank_end_q;
	logic [9:0]  timing_htotal_q, timing_hsync_q;
	logic [9:0]  timing_hblank_start_q, timing_hblank_end_q;
	logic [8:0]  display_xorigin1_q;
	logic [9:0]  display_yorigin1_q;
	logic [8:0]  display_xorigin2_q, display_xscroll2_q;
	logic [9:0]  display_yorigin2_q, display_yscroll2_q;
	logic        scanline_event;
	logic        raster_reset;

	logic        blit_vram_req, blit_vram_we, blit_vram_plane;
	logic [18:0] blit_vram_addr;
	logic [15:0] blit_vram_wdata, blit_vram_rdata;
	logic        blit_vram_ack;
	logic        scan_vram_req;
	logic [19:0] scan_vram_addr;
	logic        vram_writes_pending;
	logic        vram_arbiter_writes_pending;
	logic        arb_qwrite_req;
	logic [17:0] arb_qwrite_addr;
	logic [63:0] arb_qwrite_data;
	logic [7:0]  arb_qwrite_be;
	logic        arb_qwrite_token;
	logic        arb_qwrite_ack;
	// TimeQuest identified the arbiter front-valid to DDR capture boundary as
	// the routed global limiter.  Keep one complete qword transaction in a
	// registered elastic stage so payload and valid cross that hierarchy
	// together and remain frozen under backpressure.
	logic        qwrite_slice_valid;
	logic [17:0] qwrite_slice_addr;
	logic [63:0] qwrite_slice_data;
	logic [7:0]  qwrite_slice_be;
	logic        qwrite_slice_token;
	wire qwrite_slice_ready = !qwrite_slice_valid || vram_qwrite_ack;
	logic [14:0] palette_addr;
	logic [23:0] palette_rgb;

	logic       previous_vblank;
	logic [2:0] video_irq_level;

	// Video registers live in the blitter block but feed several physically
	// distant timing/scanout comparators.  Snapshot the live programming once
	// at that boundary; software-visible writes take effect one fabric cycle
	// later, while no raw register bit crosses the whole video datapath.
	always_ff @(posedge clk) begin
		if (reset) begin
			timing_int_scanline_q <= 10'd0;
			timing_vtotal_q <= 10'd0;
			timing_vsync_q <= 10'd0;
			timing_vblank_start_q <= 10'd0;
			timing_vblank_end_q <= 10'd0;
			timing_htotal_q <= 10'd0;
			timing_hsync_q <= 10'd0;
			timing_hblank_start_q <= 10'd0;
			timing_hblank_end_q <= 10'd0;
			display_xorigin1_q <= 9'd0;
			display_yorigin1_q <= 10'd0;
			display_xorigin2_q <= 9'd0;
			display_yorigin2_q <= 10'd0;
			display_xscroll2_q <= 9'd0;
			display_yscroll2_q <= 10'd0;
		end else begin
			timing_int_scanline_q <= timing_int_scanline[9:0];
			timing_vtotal_q <= timing_vtotal[9:0];
			timing_vsync_q <= timing_vsync[9:0];
			timing_vblank_start_q <= timing_vblank_start[9:0];
			timing_vblank_end_q <= timing_vblank_end[9:0];
			timing_htotal_q <= timing_htotal[9:0];
			timing_hsync_q <= timing_hsync[9:0];
			timing_hblank_start_q <= timing_hblank_start[9:0];
			timing_hblank_end_q <= timing_hblank_end[9:0];
			display_xorigin1_q <= display_xorigin1[8:0];
			display_yorigin1_q <= display_yorigin1[9:0];
			display_xorigin2_q <= display_xorigin2[8:0];
			display_yorigin2_q <= display_yorigin2[9:0];
			display_xscroll2_q <= display_xscroll2[8:0];
			display_yscroll2_q <= display_yscroll2[9:0];
		end
	end

	assign video_configured = (timing_htotal_q > 10'd1) &&
	                          (timing_vtotal_q > 10'd1);
	assign raster_reset = reset || !video_configured;
	assign scanline_event = video_configured && ce_pixel &&
	                        (hpos == 10'd0) &&
	                        (vpos == timing_int_scanline_q);

	assign video_irq_level = irq_scanline ? 3'd3 :
	                         irq_blitter  ? 3'd2 :
	                         irq_vblank  ? 3'd1 : 3'd0;
	always_comb begin
		if (auxiliary_irq_level > video_irq_level)
			cpu_irq_level = auxiliary_irq_level;
		else
			cpu_irq_level = video_irq_level;
	end

	// SFTM's VINT is a latched level-1 source.  A write to the P1/VINT
	// acknowledge window clears it; entering the programmed wrapped vblank
	// interval sets it again.  The first valid raster starts in vblank and is
	// intentionally treated as an entry, matching boot-time interrupt use.
	always_ff @(posedge clk) begin
		if (reset || !video_configured) begin
			previous_vblank <= 1'b0;
			irq_vblank <= 1'b0;
		end else begin
			previous_vblank <= vblank;
			if (vblank && !previous_vblank)
				irq_vblank <= 1'b1;
			if (vint_ack_strobe)
				irq_vblank <= 1'b0;
		end
	end

	assign pixel_index = pixel_data[14:0];
	// Keep live raster-valid/blanking decode out of the 24-bit color datapath.
	// The MiSTer boundary pipelines this raw palette value together with the
	// separate pixel_valid signal and performs the final black clamp locally.
	assign rgb = palette_rgb;

	itech32_tg68_cpu main_cpu (
		.clk(clk), .reset(reset), .cpu_68000(timekill_mode || bloodstorm_mode),
		.cpu_ce(ce_cpu), .irq_level(cpu_irq_level),
		.vector_load_we(vector_load_we), .vector_load_addr(vector_load_addr),
		.vector_load_wdata(vector_load_wdata), .vector_load_be(vector_load_be),
		.board_req(cpu_req), .board_we(cpu_we), .board_addr(cpu_addr),
		.board_wdata(cpu_wdata), .board_be(cpu_be),
		.board_ack(cpu_ack), .board_rdata(cpu_rdata),
		.debug_addr(debug_cpu_addr), .debug_busstate(debug_cpu_busstate),
		.debug_nwr(debug_nwr), .debug_nuds(debug_nuds), .debug_nlds(debug_nlds),
		.debug_fc(debug_fc)
	);

	// One-deep elastic forward slice for the measured arbiter-valid -> DDR
	// payload critical path.  This is intentionally not a two-entry skid buffer:
	// the routed failure was in the forward bundle, not the return-ready path.
	// Revisit the canonical two-entry pattern only if TimeQuest later identifies
	// arb_qwrite_ack/qwrite_slice_ready as the limiting combinational chain.
	// Cycle schedule for the registered qword boundary:
	//   E0: an empty/consumed stage accepts the arbiter's held transaction and
	//       acknowledges that producer; valid and all payload fields register.
	//   E1: DDR observes the registered transaction.  If it acknowledges, the
	//       stage may simultaneously refill from the arbiter's next transaction.
	//   stall: valid and every payload bit hold until DDR acknowledges.
	// The upstream completion fence includes both the arbiter backlog and this
	// stage, so accepting into the slice cannot make a blit complete early.
	always_ff @(posedge clk) begin
		if (reset) begin
			qwrite_slice_valid <= 1'b0;
		end else if (qwrite_slice_ready) begin
			qwrite_slice_valid <= arb_qwrite_req;
			if (arb_qwrite_req) begin
				qwrite_slice_addr <= arb_qwrite_addr;
				qwrite_slice_data <= arb_qwrite_data;
				qwrite_slice_be <= arb_qwrite_be;
				qwrite_slice_token <= arb_qwrite_token;
			end
		end
	end

	assign arb_qwrite_ack = arb_qwrite_req && qwrite_slice_ready;
	assign vram_qwrite_req = qwrite_slice_valid;
	assign vram_qwrite_addr = qwrite_slice_addr;
	assign vram_qwrite_data = qwrite_slice_data;
	assign vram_qwrite_be = qwrite_slice_be;
	assign vram_qwrite_token = qwrite_slice_token;
	assign vram_writes_pending = vram_arbiter_writes_pending ||
		qwrite_slice_valid;

	itech32_main_bus main_bus (
		.clk(clk), .reset(reset), .timekill_mode(timekill_mode),
		.bloodstorm_mode(bloodstorm_mode),
		.rom_buffer_invalidate(rom_buffer_invalidate),
		.cpu_req(cpu_req), .cpu_we(cpu_we), .cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata), .cpu_be(cpu_be),
		.cpu_ack(cpu_ack), .cpu_rdata(cpu_rdata),
		.input_p1(input_p1), .input_p2(input_p2),
		.input_p3(input_p3), .input_p4(input_p4), .input_dips(input_dips),
		.input_extra(input_extra),
		.protection_address(protection_address),
		.nvram_host_access(nvram_host_access),
		.nvram_host_write(nvram_host_write),
		.nvram_host_addr(nvram_host_addr),
		.nvram_host_wdata(nvram_host_wdata),
		.nvram_host_rdata(nvram_host_rdata),
		.nvram_cpu_write(nvram_cpu_write),
		.video_req(video_req), .video_we(video_we), .video_addr(video_addr),
		.video_wdata(video_wdata), .video_be(video_be),
		.video_ack(video_ack), .video_rdata(video_rdata),
		.rom_req(program_rom_req), .rom_addr(program_rom_addr),
		.rom_ack(program_rom_ack), .rom_rdata(program_rom_rdata),
		.sound_command_valid(sound_command_valid), .sound_command(sound_command),
		.watchdog_strobe(watchdog_strobe), .vint_ack_strobe(vint_ack_strobe),
		.special_read_strobe(special_read_strobe),
		.color0_strobe(color0_strobe), .color1_strobe(color1_strobe),
		.color_data(color_data), .plane_enable(plane_enable), .grom_bank(grom_bank),
		.palette_video_addr(palette_addr), .palette_video_rgb(palette_rgb)
	);

	itech32_blitter blitter (
		.clk(clk), .reset(reset), .timekill_mode(timekill_mode),
		.reg_req(video_req), .reg_we(video_we), .reg_addr(video_addr),
		.reg_wdata(video_wdata), .reg_be(video_be),
		.reg_ack(video_ack), .reg_rdata(video_rdata),
		.color0_we(color0_strobe), .color1_we(color1_strobe),
		.color_data(color_data), .plane_enable(plane_enable), .grom_bank(grom_bank),
		.scanline_event(scanline_event),
		.irq_blitter(irq_blitter), .irq_scanline(irq_scanline),
		.interrupt_state(video_interrupt_state), .busy(blitter_busy),
		.timing_int_scanline(timing_int_scanline),
		.timing_vtotal(timing_vtotal), .timing_vsync(timing_vsync),
		.timing_vblank_start(timing_vblank_start),
		.timing_vblank_end(timing_vblank_end),
		.timing_htotal(timing_htotal), .timing_hsync(timing_hsync),
		.timing_hblank_start(timing_hblank_start),
		.timing_hblank_end(timing_hblank_end),
		.display_xorigin1(display_xorigin1), .display_yorigin1(display_yorigin1),
		.display_xorigin2(display_xorigin2), .display_yorigin2(display_yorigin2),
		.display_xscroll2(display_xscroll2), .display_yscroll2(display_yscroll2),
		.grom_req(grom_req), .grom_addr(grom_addr),
		.grom_ack(grom_ack), .grom_rdata(grom_rdata),
		.vram_req(blit_vram_req), .vram_we(blit_vram_we),
		.vram_plane(blit_vram_plane), .vram_addr(blit_vram_addr),
		.vram_wdata(blit_vram_wdata), .vram_ack(blit_vram_ack),
		.vram_rdata(blit_vram_rdata),
		.vram_writes_pending(vram_writes_pending)
	);

	itech32_video_timing timing (
		.clk(clk), .reset(raster_reset), .ce_pixel(ce_pixel),
		.htotal(timing_htotal_q),
		.hblank_start(timing_hblank_start_q),
		.hblank_end(timing_hblank_end_q),
		.hsync_start(timing_hsync_q),
		.vtotal(timing_vtotal_q),
		.vblank_start(timing_vblank_start_q),
		.vblank_end(timing_vblank_end_q),
		.vsync_start(timing_vsync_q),
		.hpos(hpos), .vpos(vpos), .hblank(hblank), .vblank(vblank),
		.hsync(hsync), .vsync(vsync)
	);

	itech32_scanout #(
		.LINE_PIXELS(LINE_PIXELS), .ROW_WORDS(SCAN_ROW_WORDS)
	) scanout (
		.clk(clk), .reset(raster_reset), .timekill_mode(timekill_mode),
		.ce_pixel(ce_pixel),
		.hpos(hpos), .vpos(vpos), .hblank(hblank), .vblank(vblank),
		.htotal(timing_htotal_q), .hblank_end(timing_hblank_end_q),
		.vtotal(timing_vtotal_q),
		.vblank_start(timing_vblank_start_q),
		.vblank_end(timing_vblank_end_q),
		.display_xorigin(display_xorigin1_q),
		.display_yorigin(display_yorigin1_q),
		.display_xorigin2(display_xorigin2_q),
		.display_yorigin2(display_yorigin2_q),
		.display_xscroll2(display_xscroll2_q),
		.display_yscroll2(display_yscroll2_q),
		.fb_req(scan_vram_req), .fb_addr(scan_vram_addr),
		.fb_accept(scanline_accept),
		.fb_data_valid(scanline_data_valid), .fb_rdata(scanline_rdata),
		.fb_last(scanline_last),
		.palette_addr(palette_addr), .pixel_data(pixel_data),
		.pixel_valid(pixel_valid), .underflow(scanout_underflow)
	);

	itech32_vram_arbiter vram_arbiter (
		.clk(clk), .reset(reset),
		.blit_req(blit_vram_req), .blit_we(blit_vram_we),
		.blit_plane(blit_vram_plane), .blit_addr(blit_vram_addr),
		.blit_wdata(blit_vram_wdata),
		.blit_ack(blit_vram_ack), .blit_rdata(blit_vram_rdata),
		.writes_pending(vram_arbiter_writes_pending),
		.downstream_write_pending(qwrite_slice_valid),
		.mem_req(vram_mem_req), .mem_we(vram_mem_we),
		.mem_addr(vram_mem_addr), .mem_wdata(vram_mem_wdata),
		.mem_be(vram_mem_be), .mem_ack(vram_mem_ack),
		.mem_rdata(vram_mem_rdata),
		.qwrite_req(arb_qwrite_req), .qwrite_addr(arb_qwrite_addr),
		.qwrite_data(arb_qwrite_data), .qwrite_be(arb_qwrite_be),
		.qwrite_token(arb_qwrite_token), .qwrite_ack(arb_qwrite_ack)
	);

	// Scanout remains independent and deadline-priority in the shared DDR
	// scheduler. A live scan may overtake pixels from an in-progress command;
	// the blitter's completion fence prevents software from publishing that
	// command as done until its accepted-write tail reaches shared memory.
	assign scanline_req = scan_vram_req;
	assign scanline_addr = scan_vram_addr;

`ifndef SYNTHESIS
	logic        held_qwrite_slice_valid;
	logic [17:0] held_qwrite_slice_addr;
	logic [63:0] held_qwrite_slice_data;
	logic [7:0]  held_qwrite_slice_be;
	logic        held_qwrite_slice_token;
	always_ff @(posedge clk) begin
		if (reset) begin
			held_qwrite_slice_valid <= 1'b0;
		end else begin
			if (qwrite_slice_valid && !vram_qwrite_ack &&
			    !held_qwrite_slice_valid) begin
				held_qwrite_slice_valid <= 1'b1;
				held_qwrite_slice_addr <= qwrite_slice_addr;
				held_qwrite_slice_data <= qwrite_slice_data;
				held_qwrite_slice_be <= qwrite_slice_be;
				held_qwrite_slice_token <= qwrite_slice_token;
			end
			if (held_qwrite_slice_valid && !vram_qwrite_ack) begin
				assert (qwrite_slice_valid &&
					{qwrite_slice_addr, qwrite_slice_data,
					 qwrite_slice_be, qwrite_slice_token} ==
					{held_qwrite_slice_addr, held_qwrite_slice_data,
					 held_qwrite_slice_be, held_qwrite_slice_token})
					else $fatal(1,
						"qwrite register-slice payload changed while stalled");
			end
			if (held_qwrite_slice_valid && vram_qwrite_ack)
				held_qwrite_slice_valid <= 1'b0;
			assert (!vram_qwrite_ack || qwrite_slice_valid)
				else $fatal(1, "DDR acknowledged an empty qwrite slice");
		end
	end
`endif

endmodule
