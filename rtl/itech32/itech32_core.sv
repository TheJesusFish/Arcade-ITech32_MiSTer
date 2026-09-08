// SPDX-License-Identifier: GPL-2.0-or-later
// Complete SFTM platform integration below the MiSTer framework wrapper.

`timescale 1ns/1ps

module itech32_core #(
	parameter integer LINE_PIXELS = 384,
	parameter integer VRAM_CLEAR_LINES = 262144
) (
	input  logic        clk,
	// `memory_reset` is startup/PLL-loss only. A MiSTer warm reset must not
	// forget that the ROM remains resident in DDR.
	input  logic        memory_reset,
	input  logic        memory_quiesce,
	output logic        memory_quiesced,
	input  logic        reset,

	input  logic        ioctl_download,
	input  logic        ioctl_upload,
	input  logic        ioctl_wr,
	input  logic [15:0] ioctl_index,
	input  logic [26:0] ioctl_addr,
	input  logic [15:0] ioctl_data,
	output logic [15:0] ioctl_din,
	output logic        ioctl_wait,
	output logic        nvram_dirty,

	input  logic [11:0] joystick_0,
	input  logic [11:0] joystick_1,
	input  logic        mame_timing,

	output logic        DDRAM_CLK,
	input  logic        DDRAM_BUSY,
	output logic [7:0]  DDRAM_BURSTCNT,
	output logic [28:0] DDRAM_ADDR,
	input  logic [63:0] DDRAM_DOUT,
	input  logic        DDRAM_DOUT_READY,
	output logic [63:0] DDRAM_DIN,
	output logic [7:0]  DDRAM_BE,
	output logic        DDRAM_RD,
	output logic        DDRAM_WE,

	output logic        ce_pixel,
	output logic        hblank,
	output logic        vblank,
	output logic        hsync,
	output logic        vsync,
	output logic [23:0] rgb,
	output logic        video_valid,
	output logic        video_configured,
	output logic signed [15:0] audio_left,
	output logic signed [15:0] audio_right,
	output logic        audio_strobe,
	output logic        core_active,
	output logic        sftm_mode
);
	// The scan address is qword aligned, so a 384-pixel active line can consume
	// at most 384 + 3 source pixels. Ninety-seven qwords cover that complete
	// window without spending DDR service time on the unused tail of a 512-pixel
	// framebuffer row.
	localparam integer SCAN_ROW_WORDS = (LINE_PIXELS + 6) / 4;

	logic ce_cpu_25m;
	logic ce_cpu_12m;
	logic ce_ensoniq_16m;
	logic ce_pixel_board;
	logic ce_sound_8m;
	logic ce_sound_2m;
	logic platform_reset;
	logic rom_loaded;
	logic timekill_mode;
	logic bloodstorm_mode;
	// Every hardware-qualified SFTM revision uses the common board profile.
	// MAME's separate v1.10/v1.11 init address made those sets hang on MiSTer.
	wire [14:0] protection_address = 15'h7a6a;
	wire rev1_mode = timekill_mode || bloodstorm_mode;
	assign sftm_mode = !rev1_mode;
	wire game_selector_write = ioctl_wr && ioctl_index == 16'h0001 &&
		ioctl_addr == 27'd0;
	logic nvram_host_access;
	logic nvram_host_write;
	logic [16:0] nvram_host_addr;
	logic [15:0] nvram_host_wdata;
	logic [15:0] nvram_host_rdata;
	logic nvram_cpu_write;
	logic nvram_ioctl_wait;
	logic nvram_runtime_hold;
	logic ddr_ioctl_wait;

	logic [7:0] dip_switches;
	logic [31:0] input_p1;
	logic [31:0] input_p2;
	logic [31:0] input_p3;
	logic [31:0] input_p4;
	logic [31:0] input_dips;
	logic [31:0] input_extra;

	logic vector_load_we;
	logic [4:0] vector_load_addr;
	logic [31:0] vector_load_wdata;
	logic [3:0] vector_load_be;

	logic main_req;
	logic [21:0] main_addr;
	logic main_ack;
	logic [31:0] main_rdata;
	logic grom_req;
	logic [25:0] grom_addr;
	logic grom_ack;
	logic [63:0] grom_rdata;
	logic vram_req;
	logic vram_we;
	logic [19:0] vram_addr;
	logic [15:0] vram_wdata;
	logic [1:0] vram_be;
	logic vram_ack;
	logic [15:0] vram_rdata;
	logic vram_qwrite_req;
	logic [17:0] vram_qwrite_addr;
	logic [63:0] vram_qwrite_data;
	logic [7:0] vram_qwrite_be;
	logic vram_qwrite_token;
	logic vram_qwrite_ack;
	logic scanline_req;
	logic [19:0] scanline_addr;
	logic scanline_accept;
	logic scanline_data_valid;
	logic [63:0] scanline_rdata;
	logic scanline_last;

	logic sound_rom_req;
	logic [18:0] sound_rom_addr;
	logic sound_rom_ack;
	logic [7:0] sound_rom_rdata;
	logic sample_req;
	logic [1:0] sample_bank;
	logic [21:0] sample_addr;
	logic sample_ack;
	logic [15:0] sample_rdata;

	logic sound_command_valid;
	logic [7:0] sound_command;
	logic special_read_strobe;
	logic sound_special;
	logic sound_command_ready;
	logic [1:0] sound_command_pending;
	logic sound_irq;
	logic sound_firq;
	logic es_irq_debug;
	logic [7:0] sound_bank;
	logic sound_cpu_mem_valid;
	logic [15:0] sound_cpu_addr;
	logic sound_cpu_write;
	logic [7:0] sound_cpu_wdata;
	logic [111:0] sound_cpu_debug;

	logic watchdog_strobe;
	logic [9:0] hpos;
	logic [9:0] vpos;
	logic [31:0] debug_cpu_addr;
	logic [1:0] debug_cpu_busstate;
	logic board_pixel_valid;
	logic board_scanout_underflow;
	logic board_video_configured;
	logic board_blitter_busy;
	logic board_irq_vblank;
	logic board_irq_blitter;
	logic board_irq_scanline;

	assign ce_pixel = ce_pixel_board;
	assign core_active = rom_loaded;
	assign video_valid = board_pixel_valid;
	assign video_configured = board_video_configured;

	// The retained main-ROM response belongs to one loaded image and board mode.
	// Observe raw loader/reset/quiesce boundaries before the registered platform
	// reset arrives. Re-sending the same mode still starts a new ownership epoch.
	wire rom_buffer_invalidate = reset || memory_reset || memory_quiesce ||
		(ioctl_download && ioctl_index == 16'h0000) ||
		(ioctl_wr && ioctl_index == 16'h0001 && ioctl_addr == 27'd0);

	// 00=SFTM, 01=Time Killers, and 02=BloodStorm. Unsupported selectors retain
	// the SFTM fallback, so an incomplete/older MRA cannot select another board.
	itech32_game_selector game_selector (
		.clk(clk), .write(game_selector_write), .data(ioctl_data[7:0]),
		.timekill_mode(timekill_mode), .bloodstorm_mode(bloodstorm_mode)
	);

	itech32_platform_reset_boundary platform_reset_boundary (
		.clk(clk), .reset(reset), .ioctl_download(ioctl_download),
		.ioctl_index(ioctl_index), .rom_loaded(rom_loaded),
		.platform_reset(platform_reset)
	);

	// Index 2 is the physical battery-backed store. Upload freezes the two CPUs
	// but leaves the raster running, so direct video retains a valid signal while
	// the OSD saves. A short prefetch window also drains any accepted CPU write.
	itech32_nvram_io nvram_io (
		.clk(clk), .reset(memory_reset), .new_game(game_selector_write),
		.ioctl_download(ioctl_download), .ioctl_upload(ioctl_upload),
		.ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index),
		.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_data),
		.cpu_write(nvram_cpu_write), .memory_dout(nvram_host_rdata),
		.memory_access(nvram_host_access), .memory_write(nvram_host_write),
		.memory_addr(nvram_host_addr),
		.memory_din(nvram_host_wdata), .ioctl_din(ioctl_din),
		.ioctl_wait(nvram_ioctl_wait), .runtime_hold(nvram_runtime_hold),
		.dirty(nvram_dirty)
	);
	assign ioctl_wait = ddr_ioctl_wait | nvram_ioctl_wait;

	// Main_MiSTer sends the complete eight-byte DIP payload at index 254.
	// With WIDE=1 only the first word (address zero) contains SFTM's SW1 bits.
	always_ff @(posedge clk) begin
		if (memory_reset)
			dip_switches <= 8'd0;
		else if (ioctl_wr && ioctl_index == 16'h00fe && ioctl_addr == 27'd0)
			dip_switches <= ioctl_data[7:0];
	end

	// One selected 6x-pixel carrier clocks the complete core and the stock
	// MiSTer mixer. CE_PIXEL remains an exact divide by six in both modes,
	// giving direct video a fixed 3048-carrier-clock line. CPU and sound rates
	// retain their board frequencies when the 48 MHz MAME carrier is selected.
	itech32_clock_enables #(
		.CLK_HZ(47_727_273), .ALT_CLK_HZ(48_000_000), .PIXEL_DIV(6)
	) clocks (
		.clk(clk), .reset(platform_reset),
		.alternate_clock(mame_timing),
		.ce_cpu_25m(ce_cpu_25m), .ce_cpu_12m(ce_cpu_12m),
		.ce_ensoniq_16m(ce_ensoniq_16m),
		.ce_pixel(ce_pixel_board), .ce_sound_8m(ce_sound_8m),
		.ce_sound_2m(ce_sound_2m)
	);

	itech32_inputs inputs (
		.clk(clk), .reset(platform_reset),
		.timekill_mode(timekill_mode),
		.bloodstorm_mode(bloodstorm_mode),
		.joystick_0(joystick_0), .joystick_1(joystick_1),
		.service_button(1'b0), .vblank(vblank),
		// MAME toggles the phase before returning the side-effecting special
		// read. Predict that value combinationally; the registered read strobe
		// advances the sound board's sole state bit one clock later.
		.sound_special(sound_special ^ sound_command_pending[0]),
		.dip_switches(dip_switches),
		.input_p1(input_p1), .input_p2(input_p2), .input_p3(input_p3),
		.input_p4(input_p4), .input_dips(input_dips), .input_extra(input_extra)
	);

	itech32_board #(
		.LINE_PIXELS(LINE_PIXELS), .SCAN_ROW_WORDS(SCAN_ROW_WORDS)
	) board (
		.clk(clk), .reset(platform_reset),
		.timekill_mode(timekill_mode),
		.bloodstorm_mode(bloodstorm_mode),
		.rom_buffer_invalidate(rom_buffer_invalidate),
		.ce_cpu(!nvram_runtime_hold && (rev1_mode ? ce_cpu_12m : ce_cpu_25m)),
		.ce_pixel(ce_pixel_board),
		.vector_load_we(vector_load_we), .vector_load_addr(vector_load_addr),
		.vector_load_wdata(vector_load_wdata), .vector_load_be(vector_load_be),
		.input_p1(input_p1), .input_p2(input_p2), .input_p3(input_p3),
		.input_p4(input_p4), .input_dips(input_dips), .input_extra(input_extra),
		.protection_address(protection_address),
		.nvram_host_access(nvram_host_access),
		.nvram_host_write(nvram_host_write),
		.nvram_host_addr(nvram_host_addr),
		.nvram_host_wdata(nvram_host_wdata),
		.nvram_host_rdata(nvram_host_rdata),
		.nvram_cpu_write(nvram_cpu_write),
		.auxiliary_irq_level(3'd0),
		.sound_command_valid(sound_command_valid), .sound_command(sound_command),
		.special_read_strobe(special_read_strobe),
		.watchdog_strobe(watchdog_strobe),
		.program_rom_req(main_req), .program_rom_addr(main_addr),
		.program_rom_ack(main_ack), .program_rom_rdata(main_rdata),
		.grom_req(grom_req), .grom_addr(grom_addr),
		.grom_ack(grom_ack), .grom_rdata(grom_rdata),
		.vram_mem_req(vram_req), .vram_mem_we(vram_we),
		.vram_mem_addr(vram_addr), .vram_mem_wdata(vram_wdata),
		.vram_mem_be(vram_be), .vram_mem_ack(vram_ack),
		.vram_mem_rdata(vram_rdata),
		.vram_qwrite_req(vram_qwrite_req),
		.vram_qwrite_addr(vram_qwrite_addr),
		.vram_qwrite_data(vram_qwrite_data),
		.vram_qwrite_be(vram_qwrite_be),
		.vram_qwrite_token(vram_qwrite_token),
		.vram_qwrite_ack(vram_qwrite_ack),
		.scanline_req(scanline_req), .scanline_addr(scanline_addr),
		.scanline_accept(scanline_accept),
		.scanline_data_valid(scanline_data_valid),
		.scanline_rdata(scanline_rdata), .scanline_last(scanline_last),
		.hpos(hpos), .vpos(vpos), .hblank(hblank), .vblank(vblank),
		.hsync(hsync), .vsync(vsync), .rgb(rgb),
		.pixel_data(), .pixel_index(), .pixel_valid(board_pixel_valid),
		.scanout_underflow(board_scanout_underflow),
		.video_configured(board_video_configured),
		.blitter_busy(board_blitter_busy),
		.irq_vblank(board_irq_vblank), .irq_blitter(board_irq_blitter),
		.irq_scanline(board_irq_scanline),
		.video_interrupt_state(), .cpu_irq_level(),
		.debug_cpu_addr(debug_cpu_addr), .debug_cpu_busstate(debug_cpu_busstate)
	);

	itech32_sound_board sound_board (
		.clk(clk), .reset(platform_reset),
		.rev1_mode(rev1_mode),
		.ce_8m(ce_sound_8m && !nvram_runtime_hold),
		.ce_16m(ce_ensoniq_16m && !nvram_runtime_hold),
		.ce_2m(ce_sound_2m && !nvram_runtime_hold),
		.main_command_valid(sound_command_valid), .main_command(sound_command),
		.main_command_ready(sound_command_ready),
		.main_special_read(special_read_strobe), .sound_special(sound_special),
		.command_pending(sound_command_pending),
		.sound_req(sound_rom_req), .sound_addr(sound_rom_addr),
		.sound_ack(sound_rom_ack), .sound_rdata(sound_rom_rdata),
		.sample_req(sample_req), .sample_bank(sample_bank),
		.sample_addr(sample_addr), .sample_ack(sample_ack),
		.sample_rdata(sample_rdata),
		.pot_compare_pin_i(1'b0), .pot_res_pin_o(),
		.audio_left(audio_left), .audio_right(audio_right),
		.audio_strobe(audio_strobe),
		.sound_irq(sound_irq), .sound_firq(sound_firq),
		.es_irq_debug(es_irq_debug), .sound_bank(sound_bank),
		.cpu_mem_valid(sound_cpu_mem_valid), .cpu_addr(sound_cpu_addr),
		.cpu_write(sound_cpu_write), .cpu_wdata(sound_cpu_wdata),
		.cpu_debug_regs(sound_cpu_debug)
	);

	itech32_ddr_memory #(
		.VRAM_CLEAR_LINES(VRAM_CLEAR_LINES),
		.VRAM_WRITE_COMBINE(1'b1),
		.SCAN_BURST_WORDS(SCAN_ROW_WORDS)
	) memory (
		.clk(clk), .reset(memory_reset), .quiesce(memory_quiesce),
		.quiesce_ack(memory_quiesced),
		.timekill_mode(timekill_mode),
		.bloodstorm_mode(bloodstorm_mode),
		.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
		.ioctl_index(ioctl_index), .ioctl_addr(ioctl_addr),
		.ioctl_data(ioctl_data), .ioctl_wait(ddr_ioctl_wait),
		.rom_loaded(rom_loaded),
		.vector_load_we(vector_load_we), .vector_load_addr(vector_load_addr),
		.vector_load_wdata(vector_load_wdata), .vector_load_be(vector_load_be),
		.main_req(main_req), .main_addr(main_addr),
		.main_ack(main_ack), .main_rdata(main_rdata),
		.grom_req(grom_req), .grom_addr(grom_addr),
		.grom_ack(grom_ack), .grom_rdata(grom_rdata),
		.sound_req(sound_rom_req), .sound_addr(sound_rom_addr),
		.sound_ack(sound_rom_ack), .sound_rdata(sound_rom_rdata),
		.sample_req(sample_req), .sample_bank(sample_bank),
		.sample_addr(sample_addr), .sample_ack(sample_ack),
		.sample_rdata(sample_rdata),
		.vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr),
		.vram_wdata(vram_wdata), .vram_be(vram_be),
		.vram_ack(vram_ack), .vram_rdata(vram_rdata),
		.vram_qwrite_req(vram_qwrite_req),
		.vram_qwrite_addr(vram_qwrite_addr),
		.vram_qwrite_data(vram_qwrite_data),
		.vram_qwrite_be(vram_qwrite_be),
		.vram_qwrite_token(vram_qwrite_token),
		.vram_qwrite_ack(vram_qwrite_ack),
		.scan_req(scanline_req), .scan_addr(scanline_addr),
		.scan_accept(scanline_accept), .scan_data_valid(scanline_data_valid),
		.scan_rdata(scanline_rdata), .scan_last(scanline_last),
		.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(DDRAM_BUSY),
		.DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
		.DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
		.DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE),
		.DDRAM_RD(DDRAM_RD), .DDRAM_WE(DDRAM_WE)
	);

`ifdef ITECH32_HW_PROBE
	// Diagnostic-only, frame-coherent execution census. The scanout probe
	// proves the DDR row-burst deadline independently; this second probe tells
	// hardware bring-up whether the CPUs, blitter, and RGB path continue to
	// advance after the real ROM hands control to the board. It is omitted from
	// production builds unless the diagnostic QSF defines ITECH32_HW_PROBE.
	logic [31:0] hw_main_ack_count = 32'd0;
	logic [31:0] hw_nonzero_rgb_count = 32'd0;
	logic [21:0] hw_last_main_addr = 22'd0;
	logic [23:0] hw_last_nonzero_rgb = 24'd0;
	logic [9:0]  hw_last_nonzero_hpos = 10'd0;
	logic [9:0]  hw_last_nonzero_vpos = 10'd0;
	logic [15:0] hw_blit_count = 16'd0;
	logic [15:0] hw_vblank_count = 16'd0;
	logic        hw_rgb_seen = 1'b0;
	logic        hw_previous_blitter_busy = 1'b0;
	logic        hw_previous_vblank = 1'b0;
	// The probe is observational only.  Register one pixel sample before the
	// counters so programmable blanking/palette logic does not share a cycle
	// with the wide diagnostic counter enables and coordinate muxes.
	logic        hw_pixel_sample_valid = 1'b0;
	logic        hw_pixel_source_valid = 1'b0;
	logic [23:0] hw_pixel_sample_rgb = 24'd0;
	logic [9:0]  hw_pixel_sample_hpos = 10'd0;
	logic [9:0]  hw_pixel_sample_vpos = 10'd0;
	logic [255:0] hw_progress_probe = 256'd0;
	wire [0:0] hw_progress_source;
	// GROM-bank census for real-hardware graphics diagnosis.  Keep this in a
	// separate probe so the established scanout/performance snapshots retain
	// their layout.  The counters observe completed client transfers, after the
	// blitter address and DDR response have both been held stable through ACK.
	logic [31:0] hw_grom_ack_count = 32'd0;
	logic [31:0] hw_grom_bank0_count = 32'd0;
	logic [31:0] hw_grom_bank1_count = 32'd0;
	logic [31:0] hw_grom_bank2_count = 32'd0;
	logic [31:0] hw_grom_bank3_count = 32'd0;
	logic [25:0] hw_last_grom_addr = 26'd0;
	logic [7:0]  hw_last_grom_data = 8'd0;
	logic [255:0] hw_grom_probe = 256'd0;
	wire [0:0] hw_grom_source;

	always_ff @(posedge clk) begin
		if (platform_reset) begin
			hw_main_ack_count <= 32'd0;
			hw_nonzero_rgb_count <= 32'd0;
			hw_last_main_addr <= 22'd0;
			hw_last_nonzero_rgb <= 24'd0;
			hw_last_nonzero_hpos <= 10'd0;
			hw_last_nonzero_vpos <= 10'd0;
			hw_blit_count <= 16'd0;
			hw_vblank_count <= 16'd0;
			hw_rgb_seen <= 1'b0;
			hw_previous_blitter_busy <= 1'b0;
			hw_previous_vblank <= 1'b0;
			hw_pixel_sample_valid <= 1'b0;
			hw_pixel_source_valid <= 1'b0;
			hw_pixel_sample_rgb <= 24'd0;
			hw_pixel_sample_hpos <= 10'd0;
			hw_pixel_sample_vpos <= 10'd0;
			hw_progress_probe <= 256'd0;
			hw_grom_ack_count <= 32'd0;
			hw_grom_bank0_count <= 32'd0;
			hw_grom_bank1_count <= 32'd0;
			hw_grom_bank2_count <= 32'd0;
			hw_grom_bank3_count <= 32'd0;
			hw_last_grom_addr <= 26'd0;
			hw_last_grom_data <= 8'd0;
			hw_grom_probe <= 256'd0;
		end else begin
			hw_previous_blitter_busy <= board_blitter_busy;
			hw_previous_vblank <= vblank;
			// First capture the CE-qualified validity and payload, then evaluate
			// the nonzero diagnostic on the following 100 MHz edge.  Keeping the
			// wide RGB/blanking cone out of this counter enable avoids making an
			// observational SignalTap probe a timing endpoint for the video path.
			hw_pixel_source_valid <= 1'b0;
			hw_pixel_sample_valid <= hw_pixel_source_valid &&
				(hw_pixel_sample_rgb != 24'd0);
			if (ce_pixel_board) begin
				hw_pixel_source_valid <= board_pixel_valid;
				hw_pixel_sample_rgb <= rgb;
				hw_pixel_sample_hpos <= hpos;
				hw_pixel_sample_vpos <= vpos;
			end

			if (main_ack) begin
				hw_main_ack_count <= hw_main_ack_count + 1'b1;
				hw_last_main_addr <= main_addr;
			end

			if (hw_pixel_sample_valid) begin
				hw_nonzero_rgb_count <= hw_nonzero_rgb_count + 1'b1;
				hw_last_nonzero_rgb <= hw_pixel_sample_rgb;
				hw_last_nonzero_hpos <= hw_pixel_sample_hpos;
				hw_last_nonzero_vpos <= hw_pixel_sample_vpos;
				hw_rgb_seen <= 1'b1;
			end

			if (board_blitter_busy && !hw_previous_blitter_busy)
				hw_blit_count <= hw_blit_count + 1'b1;

			if (grom_ack) begin
				hw_grom_ack_count <= hw_grom_ack_count + 1'b1;
				case (grom_addr[25:24])
					2'd0: hw_grom_bank0_count <= hw_grom_bank0_count + 1'b1;
					2'd1: hw_grom_bank1_count <= hw_grom_bank1_count + 1'b1;
					2'd2: hw_grom_bank2_count <= hw_grom_bank2_count + 1'b1;
					2'd3: hw_grom_bank3_count <= hw_grom_bank3_count + 1'b1;
				endcase
				hw_last_grom_addr <= grom_addr;
				hw_last_grom_data <= grom_rdata[grom_addr[2:0] * 8 +: 8];
			end

			// vblank changes only on a pixel-enable edge. At this hierarchy its
			// registered transition is visible one fabric clock later, so do not
			// require a second (mutually exclusive) pixel-enable pulse here.
			if (vblank && !hw_previous_vblank) begin
				hw_progress_probe <= {
					8'ha6,
					8'h01,
					hw_vblank_count,
					hw_main_ack_count,
					hw_last_main_addr,
					debug_cpu_addr,
					debug_cpu_busstate,
					sound_cpu_debug[111:96],
					hw_nonzero_rgb_count,
					hw_last_nonzero_rgb,
					hw_last_nonzero_hpos,
					hw_last_nonzero_vpos,
					hw_blit_count,
					scanline_addr,
					board_video_configured,
					board_blitter_busy,
					board_irq_vblank,
					board_irq_blitter,
					board_irq_scanline,
					board_scanout_underflow,
					hw_rgb_seen,
					platform_reset,
					rom_loaded
				};
				hw_grom_probe <= {
					8'ha7,
					8'h01,
					hw_vblank_count,
					hw_grom_ack_count,
					hw_grom_bank0_count,
					hw_grom_bank1_count,
					hw_grom_bank2_count,
					hw_grom_bank3_count,
					hw_last_grom_addr,
					hw_last_grom_data,
					30'd0
				};
				hw_vblank_count <= hw_vblank_count + 1'b1;
			end
		end
	end

	altsource_probe #(
		.sld_auto_instance_index("YES"),
		.sld_instance_index(1),
		.instance_id("IPR"),
		.probe_width(256),
		.source_width(1),
		.source_initial_value("0"),
		.enable_metastability("NO")
	) progressHardwareProbe (
		.probe(hw_progress_probe),
		.source(hw_progress_source)
	);

	altsource_probe #(
		.sld_auto_instance_index("YES"),
		.sld_instance_index(2),
		.instance_id("IGR"),
		.probe_width(256),
		.source_width(1),
		.source_initial_value("0"),
		.enable_metastability("NO")
	) gromHardwareProbe (
		.probe(hw_grom_probe),
		.source(hw_grom_source)
	);
`endif

endmodule

// Collapse the framework/HPS reset sources into one small registered boundary.
// Every source below is already produced in clk_sys. Sampling the combined
// request here avoids feeding equality/decode glitches into asynchronous reset
// pins, while the two-bit pipe holds reset for a clean two-clock release.
/* verilator lint_off DECLFILENAME */
module itech32_platform_reset_boundary (
	input  logic        clk,
	input  logic        reset,
	input  logic        ioctl_download,
	input  logic [15:0] ioctl_index,
	input  logic        rom_loaded,
	output logic        platform_reset
);

	logic platform_reset_request;
	logic [1:0] platform_reset_pipe = 2'b11;

	assign platform_reset_request = reset ||
		(ioctl_download &&
		 (ioctl_index == 16'h0000 || ioctl_index == 16'h0002)) ||
		!rom_loaded;

	always_ff @(posedge clk) begin
		if (platform_reset_request)
			platform_reset_pipe <= 2'b11;
		else
			platform_reset_pipe <= {platform_reset_pipe[0], 1'b0};
	end

	assign platform_reset = platform_reset_pipe[1];

endmodule
/* verilator lint_on DECLFILENAME */
