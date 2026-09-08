// SPDX-License-Identifier: GPL-2.0-or-later
// MiSTer wrapper for the Incredible Technologies 68EC020 platform.

module emu
(
	`include "sys/emu_ports.vh"
);

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = '0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;
assign {SDRAM_DQ, SDRAM_A, SDRAM_BA, SDRAM_CLK, SDRAM_CKE,
        SDRAM_DQML, SDRAM_DQMH, SDRAM_nWE, SDRAM_nCAS,
        SDRAM_nRAS, SDRAM_nCS} = 'Z;

assign VGA_F1       = 1'b0;
assign VGA_SCALER   = 1'b0;
assign VGA_DISABLE  = 1'b0;
assign HDMI_FREEZE  = 1'b0;
assign HDMI_BLACKOUT = 1'b0;
assign HDMI_BOB_DEINT = 1'b0;

assign AUDIO_S   = 1'b1;
assign AUDIO_MIX = 2'b00;

assign LED_DISK  = 2'b00;
assign LED_POWER = 2'b00;
assign BUTTONS   = 2'b00;

wire [1:0] aspect = status[2:1];
assign VIDEO_ARX = (aspect == 0) ? 12'd4 : (aspect - 1'd1);
assign VIDEO_ARY = (aspect == 0) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"ITech32;;",
	"P1,Video Settings;",
	"D0P1O[2:1],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H1P1O[36],MAME Timings,Off,On;",
	"P1-;",
	"P1O[29:24],CRT H Adjust,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[35:30],CRT V Adjust,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[18],H-Scaler (Analog Out),Off,On;",
	"P1O[23:19],H-Scale,100%,101.25%,102.5%,103.75%,105%,106.25%,107.5%,108.75%,110%,111.25%,112.5%,113.75%,115%,116.25%,117.5%,118.75%,80%,81.25%,82.5%,83.75%,85%,86.25%,87.5%,88.75%,90%,91.25%,92.5%,93.75%,95%,96.25%,97.5%,98.75%;",
	"P1-;",
	"P1O[7:5],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P1-;",
	"-;",
	"DIP;",
	"T[0],Reset;",
	"J,B1,B2,B3,B4,B5,B6,Start,Coin;",
	"V,v",`BUILD_DATE,";"
};

wire         clk_board;
wire         clk_mame;
wire         clk_source;
wire         clk_sys;
wire         pll_board_locked;
wire         pll_mame_locked;
wire         pll_transport_locked;
wire         source_plls_ready = pll_board_locked & pll_mame_locked;
wire   [1:0] buttons;
wire [127:0] status;
wire         sftm_mode;
wire  [15:0] status_menumask = {14'd0, ~sftm_mode, 1'b0};
wire         forced_scandoubler;
wire  [21:0] gamma_bus;
wire         ioctl_download;
wire         ioctl_upload;
wire         ioctl_wr;
wire  [15:0] ioctl_index;
wire  [26:0] ioctl_addr;
wire  [15:0] ioctl_dout;
wire  [15:0] ioctl_din;
wire         ioctl_wait;
wire         nvram_dirty;
wire         ioctl_upload_req;
wire  [31:0] joystick_0;
wire  [31:0] joystick_1;
wire  [11:0] game_joystick_0;
wire  [11:0] game_joystick_1;

pll pll_board
(
	.refclk  (CLK_50M),
	.rst     (1'b0),
	.outclk_0(clk_board),
	.locked  (pll_board_locked)
);

itech32_mame_pll mame_pll (
	.refclk(CLK_50M),
	.reset(1'b0),
	.outclk(clk_mame),
	.locked(pll_mame_locked)
);

wire mame_timing_request = sftm_mode && status[36];
wire mame_timing_active;
wire mode_switch_reset;
wire transport_pll_reset;
wire preserve_memory;
wire memory_quiesced;
itech32_clock_mode_control clock_mode_control (
	.ref_clk(CLK_50M),
	.pll_ready(source_plls_ready),
	.transport_locked(pll_transport_locked),
	.memory_quiesced(memory_quiesced),
	.request_mame(mame_timing_request),
	.select_mame(mame_timing_active),
	.switch_reset(mode_switch_reset),
	.transport_reset(transport_pll_reset),
	.preserve_memory(preserve_memory)
);

// Both PLLs run continuously. The Cyclone V clock-control primitive is the
// dedicated, non-fabric mux used to put exactly one carrier on the common core,
// video, analog, Direct Video, and DDR clock domain.
cyclonev_clkselect core_clock_switch (
	.clkselect({1'b1, mame_timing_active}),
	.inclk({clk_mame, clk_board, 2'b00}),
	.outclk(clk_source)
);

// MiSTer's sys_top selects CLK_VIDEO again for Direct Video and analog output.
// A Cyclone V clock-selector output cannot legally feed that second selector,
// so a unity-ratio PLL provides the required direct-PLL framework boundary.
itech32_transport_pll transport_pll (
	.refclk(clk_source),
	.reset(transport_pll_reset),
	.outclk(clk_sys),
	.locked(pll_transport_locked)
);

// The mode controller holds the selected domain in reset long enough for this
// static control to settle before any rate accumulator or raster state runs.
(* preserve, useioff = 0,
   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
logic [1:0] mame_timing_pipe;
always_ff @(posedge clk_sys)
	mame_timing_pipe <= {mame_timing_pipe[0], mame_timing_active};
wire mame_timing_selected = mame_timing_pipe[1];

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys           (clk_sys),
	.HPS_BUS           (HPS_BUS),
	.EXT_BUS           (),
	.gamma_bus         (gamma_bus),
	.forced_scandoubler(forced_scandoubler),
	.buttons           (buttons),
	.status            (status),
	.status_menumask   (status_menumask),
	.new_vmode         (mame_timing_selected),
	.ioctl_upload      (ioctl_upload),
	.ioctl_upload_req  (ioctl_upload_req),
	.ioctl_upload_index(8'h02),
	.ioctl_download    (ioctl_download),
	.ioctl_rd          (),
	.ioctl_wr          (ioctl_wr),
	.ioctl_index       (ioctl_index),
	.ioctl_addr        (ioctl_addr),
	.ioctl_dout        (ioctl_dout),
	.ioctl_din         (ioctl_din),
	.ioctl_wait        (ioctl_wait),
	.joystick_0        (joystick_0),
	.joystick_1        (joystick_1),
	.ps2_key           ()
);

// RESET includes HPS warm reset. Keep it away from the persistent DDR loader
// state so a warm reset restarts the board without requiring another ROM load.
// It is asynchronous to clk_sys, so assert immediately and release only after
// three clean edges. This early assertion also quiesces new DDR commands before
// the framework safe terminator reaches its own two-stage reset lock.
wire core_async_reset = RESET | mode_switch_reset;
(* preserve, useioff = 0,
   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
logic [2:0] framework_reset_pipe = 3'b111;
always_ff @(posedge clk_sys or posedge core_async_reset) begin
	if (core_async_reset)
		framework_reset_pipe <= 3'b111;
	else
		framework_reset_pipe <= {framework_reset_pipe[1:0], 1'b0};
end
wire framework_reset = framework_reset_pipe[2];

// A source-PLL failure is always a cold-memory boundary. A transport-lock drop
// is cold only when it was not requested by the protected carrier switch. The
// controller asserts preserve_memory before stopping the transport and keeps it
// asserted until the replacement clock has been stably locked.
wire memory_clock_ready = source_plls_ready &
	(pll_transport_locked | preserve_memory);
(* preserve, useioff = 0,
   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
logic [2:0] memory_reset_pipe = 3'b111;
always_ff @(posedge clk_sys or negedge memory_clock_ready) begin
	if (!memory_clock_ready)
		memory_reset_pipe <= 3'b111;
	else
		memory_reset_pipe <= {memory_reset_pipe[1:0], 1'b0};
end
wire memory_reset = memory_reset_pipe[2];

// Match the established Cave/Batsugun convention: request one automatic save
// when the OSD opens and the backing store is dirty.  Requesting on every
// clean-to-dirty transition retriggers forever for BloodStorm because its
// battery-backed region is also active work RAM.
itech32_nvram_save_request nvram_save_request (
	.clk(clk_sys), .reset(memory_reset), .dirty(nvram_dirty),
	.osd_status(OSD_STATUS), .upload_req(ioctl_upload_req)
);

wire reset = framework_reset | memory_reset | status[0] | buttons[1];
wire ce_pixel;
wire hblank;
wire vblank;
wire hsync;
wire vsync;
wire [23:0] rgb;
wire video_valid;
wire video_configured;
wire core_active;
wire signed [15:0] core_audio_left;
wire signed [15:0] core_audio_right;
wire core_audio_strobe;
// The framework owns the OSD while it is open.  Keep board inputs quiet during
// that interval, but otherwise pass the mapped controller payload unchanged.
assign game_joystick_0 = OSD_STATUS ? 12'd0 : joystick_0[11:0];
assign game_joystick_1 = OSD_STATUS ? 12'd0 : joystick_1[11:0];

itech32_core core
(
	.clk            (clk_sys),
	.memory_reset   (memory_reset),
	.memory_quiesce (framework_reset),
	.memory_quiesced(memory_quiesced),
	.reset          (reset),
	.ioctl_download (ioctl_download),
	.ioctl_upload   (ioctl_upload),
	.ioctl_wr       (ioctl_wr),
	.ioctl_index    (ioctl_index),
	.ioctl_addr     (ioctl_addr),
	.ioctl_data     (ioctl_dout),
	.ioctl_din      (ioctl_din),
	.ioctl_wait     (ioctl_wait),
	.nvram_dirty    (nvram_dirty),
	.joystick_0     (game_joystick_0),
	.joystick_1     (game_joystick_1),
	.mame_timing    (mame_timing_selected),
	.DDRAM_CLK      (DDRAM_CLK),
	.DDRAM_BUSY     (DDRAM_BUSY),
	.DDRAM_BURSTCNT (DDRAM_BURSTCNT),
	.DDRAM_ADDR     (DDRAM_ADDR),
	.DDRAM_DOUT     (DDRAM_DOUT),
	.DDRAM_DOUT_READY(DDRAM_DOUT_READY),
	.DDRAM_DIN      (DDRAM_DIN),
	.DDRAM_BE       (DDRAM_BE),
	.DDRAM_RD       (DDRAM_RD),
	.DDRAM_WE       (DDRAM_WE),
	.ce_pixel       (ce_pixel),
	.hblank         (hblank),
	.vblank         (vblank),
	.hsync          (hsync),
	.vsync          (vsync),
	.rgb            (rgb),
	.video_valid    (video_valid),
	.video_configured(video_configured),
	.audio_left     (core_audio_left),
	.audio_right    (core_audio_right),
	.audio_strobe   (core_audio_strobe),
	.core_active    (core_active),
	.sftm_mode      (sftm_mode)
);

// Direct video has no framework-generated output raster. Keep a legal
// 508x286 raster running while ROM loading and while the game CRTC is
// unprogrammed, then enter the game raster only on its VSYNC boundary. This
// keeps the direct-video clock/sync contract alive even if software has not
// reached the CRTC setup yet; it also leaves a visible OSD over black.
wire fallback_ce_pixel;
wire fallback_hblank;
wire fallback_vblank;
wire fallback_hsync;
wire fallback_vsync;
wire [23:0] fallback_rgb;
itech32_fallback_raster fallback_raster (
	.clk(clk_sys),
	.reset(memory_reset),
	.ce_pixel(fallback_ce_pixel),
	.hblank(fallback_hblank),
	.vblank(fallback_vblank),
	.hsync(fallback_hsync),
	.vsync(fallback_vsync),
	.rgb(fallback_rgb)
);

logic core_vsync_q;
logic core_video_selected;
always_ff @(posedge clk_sys) begin
	if (reset || !video_configured) begin
		core_vsync_q <= 1'b0;
		core_video_selected <= 1'b0;
	end else if (ce_pixel) begin
		core_vsync_q <= vsync;
		if (vsync && !core_vsync_q)
			core_video_selected <= 1'b1;
	end
end

wire selected_ce_pixel = core_video_selected ? ce_pixel : fallback_ce_pixel;
wire selected_hblank = core_video_selected ? hblank : fallback_hblank;
wire selected_vblank = core_video_selected ? vblank : fallback_vblank;
wire selected_hsync = core_video_selected ? hsync : fallback_hsync;
wire selected_vsync = core_video_selected ? vsync : fallback_vsync;
wire [23:0] selected_rgb = core_video_selected ? rgb : fallback_rgb;
wire selected_video_valid = core_video_selected ? video_valid : 1'b1;

assign AUDIO_L = core_audio_left;
assign AUDIO_R = core_audio_right;

assign CLK_VIDEO = clk_sys;

wire signed [5:0] crt_h_offset;
wire signed [5:0] crt_v_offset;
wire signed [4:0] hscale = status[23:19];
itech32_crt_adjust_decode crt_adjust_decode (
	.h_trim_code(status[29:24]),
	.v_trim_code(status[35:30]),
	.h_offset(crt_h_offset),
	.v_offset(crt_v_offset)
);
`ifdef ITECH32_DIAG_RAW_VIDEO
// Hardware-bisect branch: retain the pre-accuracy registered MiSTer boundary
// while compiling the H-scale/resync/mixer branch completely out. This is a
// synthesis-time cut, not a live mux, so its routed resource/timing result can
// distinguish video-path placement load from the remaining accuracy changes.
logic [7:0] raw_vga_r;
logic [7:0] raw_vga_g;
logic [7:0] raw_vga_b;
logic raw_vga_de;
logic raw_vga_hs;
logic raw_vga_vs;
itech32_video_output raw_video_boundary (
	.clk(clk_sys),
	.reset(reset),
	.ce_pixel(selected_ce_pixel),
	.rgb_in(selected_rgb),
	.pixel_valid_in(selected_video_valid),
	.hblank_in(selected_hblank),
	.vblank_in(selected_vblank),
	.hsync_in(selected_hsync),
	.vsync_in(selected_vsync),
	.vga_r(raw_vga_r),
	.vga_g(raw_vga_g),
	.vga_b(raw_vga_b),
	.vga_de(raw_vga_de),
	.vga_hs(raw_vga_hs),
	.vga_vs(raw_vga_vs),
	.vga_hblank(),
	.vga_vblank()
);
assign CE_PIXEL = selected_ce_pixel;
assign VGA_R = raw_vga_r;
assign VGA_G = raw_vga_g;
assign VGA_B = raw_vga_b;
assign VGA_DE = raw_vga_de;
assign VGA_HS = raw_vga_hs;
assign VGA_VS = raw_vga_vs;
assign VGA_SL = 2'd0;
`elsif ITECH32_DIAG_RESYNC_ONLY
// Bounded analog-path bisect: retain the hardware-proven direct framework
// mixer and add only the CRT sync repositioner. RGB, blanking, and CE remain
// on the accepted direct path; H-scale and its wide live branch mux are
// compiled out. At zero offsets the resync module is a literal sync bypass.
logic resync_adjusted_hs;
logic resync_adjusted_vs;
logic resync_mixer_freeze_sync_unused;
wire [2:0] resync_mixer_fx = status[7:5];
wire resync_mixer_hq2x = resync_mixer_fx == 3'd1;
wire resync_mixer_scandoubler = forced_scandoubler ||
	resync_mixer_fx != 3'd0;

itech32_video_resync diagnostic_resync (
	.clk(clk_sys),
	.ce_pixel(selected_ce_pixel),
	.hsync_in(selected_hsync),
	.vsync_in(selected_vsync),
	.hblank_in(selected_hblank),
	.vblank_in(selected_vblank),
	.h_offset(crt_h_offset),
	.v_offset(crt_v_offset),
	.hsync_out(resync_adjusted_hs),
	.vsync_out(resync_adjusted_vs)
);

video_mixer #(
	.LINE_LENGTH(388),
	.HALF_DEPTH(0),
	.GAMMA(1)
) diagnostic_resync_mixer (
	.CLK_VIDEO(clk_sys),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(selected_ce_pixel),
	.scandoubler(resync_mixer_scandoubler),
	.hq2x(resync_mixer_hq2x),
	.gamma_bus(gamma_bus),
	.R(selected_rgb[23:16]),
	.G(selected_rgb[15:8]),
	.B(selected_rgb[7:0]),
	.HSync(resync_adjusted_hs),
	.VSync(resync_adjusted_vs),
	.HBlank(selected_hblank),
	.VBlank(selected_vblank),
	.HDMI_FREEZE(1'b0),
	.freeze_sync(resync_mixer_freeze_sync_unused),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

assign VGA_SL = resync_mixer_fx == 3'd0 ? 2'd0 :
	(resync_mixer_fx[1:0] - 2'd1);
`elsif ITECH32_DIAG_MIXER_ONLY
// Bounded analog-path bisect: use the framework video_mixer exactly at the
// already-registered core video boundary, matching the proven Cave pattern.
// The custom resync and H-scale stages are compiled out so this build answers
// only whether the standard mixer/scandoubler path is hardware-clean.
logic mixer_freeze_sync_unused;
wire [2:0] mixer_fx = status[7:5];
wire mixer_hq2x = mixer_fx == 3'd1;
wire mixer_scandoubler = forced_scandoubler || mixer_fx != 3'd0;

video_mixer #(
	.LINE_LENGTH(388),
	.HALF_DEPTH(0),
	.GAMMA(1)
) diagnostic_mixer (
	.CLK_VIDEO(clk_sys),
	.CE_PIXEL(CE_PIXEL),
	.ce_pix(selected_ce_pixel),
	.scandoubler(mixer_scandoubler),
	.hq2x(mixer_hq2x),
	.gamma_bus(gamma_bus),
	.R(selected_rgb[23:16]),
	.G(selected_rgb[15:8]),
	.B(selected_rgb[7:0]),
	.HSync(selected_hsync),
	.VSync(selected_vsync),
	.HBlank(selected_hblank),
	.VBlank(selected_vblank),
	.HDMI_FREEZE(1'b0),
	.freeze_sync(mixer_freeze_sync_unused),
	.VGA_R(VGA_R),
	.VGA_G(VGA_G),
	.VGA_B(VGA_B),
	.VGA_VS(VGA_VS),
	.VGA_HS(VGA_HS),
	.VGA_DE(VGA_DE)
);

assign VGA_SL = mixer_fx == 3'd0 ? 2'd0 :
	(mixer_fx[1:0] - 2'd1);
`else
itech32_video_path video_path (
		.clk(clk_sys),
		.core_ce_pixel(selected_ce_pixel),
		.core_rgb(selected_rgb),
		.core_hblank(selected_hblank),
		.core_vblank(selected_vblank),
		.core_hsync(selected_hsync),
		.core_vsync(selected_vsync),
		.scandoubler_fx(status[7:5]),
		.forced_scandoubler(forced_scandoubler),
		.crt_h_offset(crt_h_offset),
		.crt_v_offset(crt_v_offset),
		.hscale_enable(status[18]),
		.hscale(hscale),
		.gamma_bus(gamma_bus),
		.ce_pixel(CE_PIXEL),
		.vga_r(VGA_R),
		.vga_g(VGA_G),
		.vga_b(VGA_B),
		.vga_hs(VGA_HS),
		.vga_vs(VGA_VS),
		.vga_de(VGA_DE),
		.vga_sl(VGA_SL)
);
`endif
assign LED_USER  = ioctl_download | core_active;

endmodule

// Always-running black raster for direct-video acquisition before the board
// CRTC is programmed. Geometry matches SFTM's programmed frame totals and uses
// the same exact /6 cadence as the selected game path.
module itech32_fallback_raster (
	input  logic        clk,
	input  logic        reset,
	output logic        ce_pixel,
	output logic        hblank,
	output logic        vblank,
	output logic        hsync,
	output logic        vsync,
	output logic [23:0] rgb
);
	logic [2:0] pixel_div;
	logic [8:0] hpos;
	logic [8:0] vpos;

	always_ff @(posedge clk) begin
		if (reset) begin
			pixel_div <= 3'd0;
			hpos <= 9'd0;
			vpos <= 9'd0;
			ce_pixel <= 1'b0;
		end else if (pixel_div == 3'd5) begin
			pixel_div <= 3'd0;
			ce_pixel <= 1'b1;
			if (hpos == 9'd507) begin
				hpos <= 9'd0;
				vpos <= (vpos == 9'd285) ? 9'd0 : vpos + 9'd1;
			end else begin
				hpos <= hpos + 9'd1;
			end
		end else begin
			pixel_div <= pixel_div + 3'd1;
			ce_pixel <= 1'b0;
		end
	end

	always_comb begin
		hblank = hpos >= 9'd384;
		vblank = vpos >= 9'd240;
		hsync = (hpos >= 9'd408) && (hpos < 9'd448);
		vsync = (vpos >= 9'd248) && (vpos < 9'd252);
		rgb = 24'd0;
	end
endmodule
