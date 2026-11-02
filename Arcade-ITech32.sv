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
assign AUDIO_MIX = status[4:3];

assign LED_DISK  = 2'b00;
assign LED_POWER = 2'b00;
assign BUTTONS   = 2'b00;

wire [1:0] aspect = status[2:1];
assign VIDEO_ARX = (aspect == 0) ? 12'd4 : (aspect - 1'd1);
assign VIDEO_ARY = (aspect == 0) ? 12'd3 : 12'd0;

// Status bit map (bump v,N below whenever an assignment moves):
//   0 Reset, 2:1 Aspect, 4:3 Stereo Mix, 7:5 Scandoubler Fx, 9:8 Audio Gain,
//   10 Pause, 18 H-Scaler, 23:19 H-Scale, 29:24 CRT H, 35:30 CRT V.
`include "build_id.v"
localparam CONF_STR = {
	"ITech32;;",
	"P1,Video Settings;",
	"P1O[2:1],Aspect Ratio,Original,Full Screen,[ARC1],[ARC2];",
	"P1-;",
	"P1O[29:24],CRT H Adjust,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[35:30],CRT V Adjust,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
	"P1O[18],H-Scaler (Analog Out),Off,On;",
	"P1O[23:19],H-Scale,100%,101.25%,102.5%,103.75%,105%,106.25%,107.5%,108.75%,110%,111.25%,112.5%,113.75%,115%,116.25%,117.5%,118.75%,80%,81.25%,82.5%,83.75%,85%,86.25%,87.5%,88.75%,90%,91.25%,92.5%,93.75%,95%,96.25%,97.5%,98.75%;",
	"P1-;",
	"P1O[7:5],Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",
	"P2,Audio Settings;",
	"P2O[4:3],Stereo Mix,None,25%,50%,100%;",
	"P2O[9:8],Audio Gain,1x,2x,4x;",
	"-;",
	"O[10],Pause When OSD Open,Off,On;",
	"-;",
	"DIP;",
	"T[0],Reset;",
	"J,B1,B2,B3,B4,B5,B6,Start,Coin;",
	"v,1;",
	"V,v",`BUILD_DATE,";"
};

wire         clk_sys;
wire         pll_locked;
wire   [1:0] buttons;
wire [127:0] status;
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
wire  [31:0] joystick_2;
wire  [31:0] joystick_3;
wire  [11:0] game_joystick_0;
wire  [11:0] game_joystick_1;
wire  [11:0] game_joystick_2;
wire  [11:0] game_joystick_3;

// One free-running core PLL, named and instantiated as the framework expects
// so sys_top.sdc constrains it. Never reset it: warm resets must not stop
// clk_sys, hps_io, or the DDR interface.
pll pll
(
	.refclk  (CLK_50M),
	.rst     (1'b0),
	.outclk_0(clk_sys),
	.locked  (pll_locked)
);

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io
(
	.clk_sys           (clk_sys),
	.HPS_BUS           (HPS_BUS),
	.EXT_BUS           (),
	.gamma_bus         (gamma_bus),
	.forced_scandoubler(forced_scandoubler),
	.buttons           (buttons),
	.status            (status),
	.status_menumask   (16'd0),
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
	.joystick_2        (joystick_2),
	.joystick_3        (joystick_3),
	.ps2_key           ()
);

// RESET includes HPS warm reset. Keep it away from the persistent DDR loader
// state so a warm reset restarts the board without requiring another ROM load.
// It is asynchronous to clk_sys, so assert immediately and release only after
// three clean edges. This early assertion also quiesces new DDR commands before
// the framework safe terminator reaches its own two-stage reset lock.
(* preserve, useioff = 0,
   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
logic [2:0] framework_reset_pipe = 3'b111;
always_ff @(posedge clk_sys or posedge RESET) begin
	if (RESET)
		framework_reset_pipe <= 3'b111;
	else
		framework_reset_pipe <= {framework_reset_pipe[1:0], 1'b0};
end
wire framework_reset = framework_reset_pipe[2];

// PLL lock is asynchronous to clk_sys. Assert reset immediately on lock loss,
// then release it only after three clean system-clock edges. Warm MiSTer resets
// intentionally do not clear the persistent DDR loader state.
(* preserve, useioff = 0,
   altera_attribute = {"-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS"} *)
logic [2:0] memory_reset_pipe = 3'b111;
always_ff @(posedge clk_sys or negedge pll_locked) begin
	if (!pll_locked)
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
assign game_joystick_2 = OSD_STATUS ? 12'd0 : joystick_2[11:0];
assign game_joystick_3 = OSD_STATUS ? 12'd0 : joystick_3[11:0];

itech32_core core
(
	.clk            (clk_sys),
	.memory_reset   (memory_reset),
	.memory_quiesce (framework_reset),
	.reset          (reset),
	.pause          (OSD_STATUS && status[10]),
	.audio_gain     (status[9:8]),
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
	.joystick_2     (game_joystick_2),
	.joystick_3     (game_joystick_3),
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
	.core_active    (core_active)
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

// The board keeps its blanking/validity decode out of the 24-bit palette
// datapath, and the framework mixer does not blank RGB itself. Analog sinks
// take their black level from the blanking interval, so force black here.
// Validity changes only with the raster position on CE_PIXEL; the mixer and
// H-scaler sample RGB on the next CE_PIXEL, six carrier clocks later. A copy
// registered every carrier clock is therefore aligned with RGB at that sample
// while keeping the deep validity cone off the colour bits. No RGB, blank, or
// sync recapture stage is added.
logic selected_video_valid_q = 1'b0;
always_ff @(posedge clk_sys)
	selected_video_valid_q <= selected_video_valid;
wire [23:0] visible_rgb = selected_video_valid_q ? selected_rgb : 24'd0;

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

itech32_video_path video_path (
	.clk(clk_sys),
	.core_ce_pixel(selected_ce_pixel),
	.core_rgb(visible_rgb),
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
assign LED_USER  = ioctl_download | core_active;

endmodule
