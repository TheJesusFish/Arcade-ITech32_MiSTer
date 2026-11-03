// SPDX-License-Identifier: GPL-2.0-or-later
// Complete ITech32 platform integration (SFTM, Time Killers, BloodStorm)
// below the MiSTer framework wrapper.

`timescale 1ns/1ps

module itech32_core
	import itech32_profile_pkg::*;
#(
	parameter integer LINE_PIXELS = 384,
	parameter integer VRAM_CLEAR_LINES = 262144
) (
	input  logic        clk,
	// `memory_reset` is startup/PLL-loss only. A MiSTer warm reset must not
	// forget that the ROM remains resident in DDR.
	input  logic        memory_reset,
	input  logic        memory_quiesce,
	input  logic        reset,
	// Freeze both CPUs and the sound clock enables (OSD pause). The raster and
	// DDR service keep running so every video output keeps its sync.
	input  logic        pause,
	input  logic [1:0]  audio_gain,

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
	input  logic [11:0] joystick_2,
	input  logic [11:0] joystick_3,
	// Trackball sources: left sticks, mouse packets, OSD-owned flag, speed.
	input  logic [15:0] analog_0,
	input  logic [15:0] analog_1,
	input  logic [24:0] ps2_mouse,
	input  logic        mouse_ignore,
	input  logic [1:0]  trackball_speed,
	// Light guns: absolute left sticks (MiSTer guns); crosshairs shown.
	input  logic        lightgun_absolute,
	input  logic        crosshair,
	// hps_io RTC (MSM6242B layout, [64] toggles per update).
	input  logic [64:0] rtc,

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
	output logic        core_active
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
	// Per-game hardware differences (itech32_profile_pkg), decoded from the
	// MRA selector byte and stable while the board runs.
	board_profile_t profile;
	wire game_selector_write = ioctl_wr && ioctl_index == 16'h0001 &&
		ioctl_addr == 27'd0;
	logic nvram_host_access;
	logic nvram_host_write;
	logic [17:0] nvram_host_addr;
	logic [15:0] nvram_host_wdata;
	logic [15:0] nvram_host_rdata;
	logic nvram_host_ready;
	logic nvram_cpu_write;
	logic nvram_ioctl_wait;
	logic nvram_runtime_hold;
	logic ddr_ioctl_wait;
	// An NVRAM upload or the OSD pause stops both CPUs and the sound enables.
	wire board_hold = nvram_runtime_hold || pause;

	logic [7:0] dip_switches;
	logic [31:0] input_p1;
	logic [31:0] input_p2;
	logic [31:0] input_p3;
	logic [31:0] input_p4;
	logic [31:0] input_dips;
	logic [31:0] input_extra;
	logic [15:0] trackball1;
	logic [15:0] trackball2;
	logic [16:0] lightgun1;
	logic [16:0] lightgun2;
	logic        lightgun2_active;
	logic [23:0] board_rgb;
	logic [7:0]  timekeeper_write_enable;
	logic [63:0] timekeeper_write_data;
	logic [63:0] timekeeper_clock;

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

	// Selector values are listed in itech32_profile_pkg. Unsupported selectors retain
	// the SFTM fallback, so an incomplete/older MRA cannot select another board.
	itech32_game_selector game_selector (
		.clk(clk), .write(game_selector_write), .data(ioctl_data[7:0]),
		.profile(profile)
	);

	itech32_platform_reset_boundary platform_reset_boundary (
		.clk(clk), .reset(reset), .ioctl_download(ioctl_download),
		.ioctl_index(ioctl_index), .rom_loaded(rom_loaded),
		.platform_reset(platform_reset)
	);

	// Index 2 is the physical battery-backed store. Upload freezes the two CPUs
	// but leaves the raster running, so direct video retains a valid signal while
	// the OSD saves. The main bus hands its RAM ports to the transfer only after
	// every CPU access accepted before the upload has finished (memory_ready).
	itech32_nvram_io nvram_io (
		.clk(clk), .reset(memory_reset), .new_game(game_selector_write),
		.ioctl_download(ioctl_download), .ioctl_upload(ioctl_upload),
		.ioctl_wr(ioctl_wr), .ioctl_index(ioctl_index),
		.ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_data),
		.cpu_write(nvram_cpu_write), .memory_dout(nvram_host_rdata),
		.memory_ready(nvram_host_ready),
		.memory_access(nvram_host_access), .memory_write(nvram_host_write),
		.memory_addr(nvram_host_addr),
		.memory_din(nvram_host_wdata), .ioctl_din(ioctl_din),
		.ioctl_wait(nvram_ioctl_wait), .runtime_hold(nvram_runtime_hold),
		.dirty(nvram_dirty)
	);
	assign ioctl_wait = ddr_ioctl_wait | nvram_ioctl_wait;

	// The tournament boards' M48T02 clock registers. Like the chip's own
	// battery, the clock keeps time through board resets; each game load
	// restarts it from the MiSTer RTC.
	itech32_timekeeper #(.CLK_HZ(47_727_273)) timekeeper (
		.clk(clk), .reset(memory_reset), .new_game(game_selector_write), .rtc(rtc),
		.write_enable(timekeeper_write_enable), .write_data(timekeeper_write_data),
		.read_data(timekeeper_clock)
	);

	// Main_MiSTer sends the complete eight-byte DIP payload at index 254.
	// With WIDE=1 only the first word (address zero) contains SFTM's SW1 bits.
	always_ff @(posedge clk) begin
		if (memory_reset)
			dip_switches <= 8'd0;
		else if (ioctl_wr && ioctl_index == 16'h00fe && ioctl_addr == 27'd0)
			dip_switches <= ioctl_data[7:0];
	end

	// One 6x-pixel carrier clocks the complete core and the stock MiSTer
	// mixer. CE_PIXEL is an exact divide by six, giving direct video a fixed
	// 3048-carrier-clock line. Arcade-ITech32.sdc's palette path budget and
	// Time Killers' intensity pipeline both rely on exactly six clocks/pixel.
	itech32_clock_enables #(.CLK_HZ(47_727_273), .PIXEL_DIV(6)) clocks (
		.clk(clk), .reset(platform_reset),
		.ce_cpu_25m(ce_cpu_25m), .ce_cpu_12m(ce_cpu_12m),
		.ce_ensoniq_16m(ce_ensoniq_16m),
		.ce_pixel(ce_pixel_board), .ce_sound_8m(ce_sound_8m),
		.ce_sound_2m(ce_sound_2m)
	);

	itech32_inputs #(.CLK_HZ(47_727_273)) inputs (
		.clk(clk), .reset(platform_reset), .profile(profile),
		.joystick_0(joystick_0), .joystick_1(joystick_1),
		.joystick_2(joystick_2), .joystick_3(joystick_3),
		.analog_0(analog_0), .analog_1(analog_1),
		.ps2_mouse(ps2_mouse), .mouse_ignore(mouse_ignore),
		.trackball_speed(trackball_speed),
		.lightgun_absolute(lightgun_absolute),
		.service_button(1'b0), .vblank(vblank),
		// MAME toggles the phase before returning the side-effecting special
		// read. Predict that value combinationally; the registered read strobe
		// advances the sound board's sole state bit one clock later.
		.sound_special(sound_special ^ sound_command_pending[0]),
		.dip_switches(dip_switches),
		.input_p1(input_p1), .input_p2(input_p2), .input_p3(input_p3),
		.input_p4(input_p4), .input_dips(input_dips), .input_extra(input_extra),
		.trackball1(trackball1), .trackball2(trackball2),
		.lightgun1(lightgun1), .lightgun2(lightgun2),
		.lightgun2_active(lightgun2_active)
	);

	itech32_board #(
		.LINE_PIXELS(LINE_PIXELS), .SCAN_ROW_WORDS(SCAN_ROW_WORDS)
	) board (
		.clk(clk), .reset(platform_reset), .profile(profile),
		.rom_buffer_invalidate(rom_buffer_invalidate),
		.ce_cpu(!board_hold && (profile.cpu_68000 ? ce_cpu_12m : ce_cpu_25m)),
		.ce_pixel(ce_pixel_board),
		.vector_load_we(vector_load_we), .vector_load_addr(vector_load_addr),
		.vector_load_wdata(vector_load_wdata), .vector_load_be(vector_load_be),
		.input_p1(input_p1), .input_p2(input_p2), .input_p3(input_p3),
		.input_p4(input_p4), .input_dips(input_dips), .input_extra(input_extra),
		.trackball1(trackball1), .trackball2(trackball2),
		.lightgun1(lightgun1), .lightgun2(lightgun2),
		.nvram_host_access(nvram_host_access),
		.nvram_host_write(nvram_host_write),
		.nvram_host_addr(nvram_host_addr),
		.nvram_host_wdata(nvram_host_wdata),
		.nvram_host_rdata(nvram_host_rdata),
		.nvram_host_ready(nvram_host_ready),
		.nvram_cpu_write(nvram_cpu_write),
		.timekeeper_clock(timekeeper_clock),
		.timekeeper_write_enable(timekeeper_write_enable),
		.timekeeper_write_data(timekeeper_write_data),
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
		.hsync(hsync), .vsync(vsync), .rgb(board_rgb),
		.pixel_data(), .pixel_index(), .pixel_valid(board_pixel_valid),
		.scanout_underflow(board_scanout_underflow),
		.video_configured(board_video_configured),
		.blitter_busy(board_blitter_busy),
		.irq_vblank(board_irq_vblank), .irq_blitter(board_irq_blitter),
		.irq_scanline(board_irq_scanline),
		.video_interrupt_state(), .cpu_irq_level(),
		.debug_cpu_addr(debug_cpu_addr), .debug_cpu_busstate(debug_cpu_busstate)
	);

	// Light-gun crosshairs over the board's RGB (Must Shoot TV only).
	// Player 2's appears once that gun has been aimed.
	itech32_crosshair crosshairs (
		.clk(clk), .ce_pixel(ce_pixel_board), .hblank(hblank), .vblank(vblank),
		.rgb_in(board_rgb),
		.enable({crosshair && profile.lightgun && lightgun2_active,
			crosshair && profile.lightgun}),
		.gun1_x(lightgun1[8:0]), .gun1_y(lightgun1[16:9]),
		.gun2_x(lightgun2[8:0]), .gun2_y(lightgun2[16:9]),
		.rgb_out(rgb)
	);

	itech32_sound_board sound_board (
		.clk(clk), .reset(platform_reset), .profile(profile),
		.ce_8m(ce_sound_8m && !board_hold),
		.ce_16m(ce_ensoniq_16m && !board_hold),
		.ce_2m(ce_sound_2m && !board_hold),
		.audio_gain(audio_gain),
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
		// The drain acknowledgement is verified by the DDR test but has no
		// production consumer since the runtime clock switch was removed.
		.clk(clk), .reset(memory_reset), .quiesce(memory_quiesce),
		.quiesce_ack(),
		.profile(profile),
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
