// SPDX-License-Identifier: GPL-2.0-or-later
// Board profiles: the per-game hardware differences of the ITech32 family.
//
// Each MRA writes one selector byte at index 1 before its ROM stream. The core
// decodes it once into a registered board_profile_t, and every block reads the
// independent feature it needs (memory map, palette format, NVRAM layout, ...)
// instead of testing game identities. Memory-map names follow MAME's itech32.cpp
// address maps, which several game families share. To add a game, add a
// selector and its profile here, then implement any new feature value.
`timescale 1ns/1ps

package itech32_profile_pkg;

	// MRA index-1 selector bytes. Unsupported values fall back to SFTM, so an
	// incomplete or older MRA cannot select another board.
	localparam logic [7:0] SELECT_SFTM       = 8'h00;
	localparam logic [7:0] SELECT_TIMEKILL   = 8'h01;
	localparam logic [7:0] SELECT_BLOODSTORM = 8'h02;
	localparam logic [7:0] SELECT_HARDYARD   = 8'h03;
	localparam logic [7:0] SELECT_PAIRS      = 8'h04; // also Hot Memory, Pairs Redemption
	localparam logic [7:0] SELECT_WCBOWL     = 8'h05; // World Class Bowling v1.0-1.5
	localparam logic [7:0] SELECT_WCBOWL_J   = 8'h06; // World Class Bowling v1.3J
	localparam logic [7:0] SELECT_WCBOWL_020 = 8'h07; // World Class Bowling v1.6-1.66
	localparam logic [7:0] SELECT_WCBOWL_DX  = 8'h08; // World Class Bowling Deluxe
	localparam logic [7:0] SELECT_SHUFSHOT   = 8'h09; // Shuffleshot
	// Golden Tee (MAME init_aama, init_gt2kp, init_gtclasscp, init_s_ver,
	// init_gt3d, init_gt3dl).
	localparam logic [7:0] SELECT_GT_AAMA    = 8'h0a; // single-board sets
	localparam logic [7:0] SELECT_GT2K_P     = 8'h0b; // GT 2K, alternate protection
	localparam logic [7:0] SELECT_GTCLASSC_P = 8'h0c; // GT Classic, alternate protection
	localparam logic [7:0] SELECT_GT_S       = 8'h0d; // one-trackball "S" sets
	localparam logic [7:0] SELECT_GT3D_SHORT = 8'h0e; // GT 3D v1.4-1.92S, short ROM board
	localparam logic [7:0] SELECT_GT3D_LONG  = 8'h0f; // GT 3D v1.9L-1.92L, long ROM board
	localparam logic [7:0] SELECT_PUBBALL    = 8'h10; // Power Up Baseball (prototype)
	// Tournament editions: the boards above plus the M48T02 timekeeper.
	localparam logic [7:0] SELECT_GT_AAMA_T  = 8'h11; // Golden Tee (init_aamat)
	localparam logic [7:0] SELECT_WCBOWL_T   = 8'h12; // World Class Bowling (init_wcbowlt)
	localparam logic [7:0] SELECT_SHOOTTV    = 8'h13; // Must Shoot TV (prototype)

	// Main-CPU address map (MAME: itech020_map, timekill_map, bloodstm_map).
	localparam logic [1:0] MAP_ITECH020   = 2'd0;
	localparam logic [1:0] MAP_TIMEKILL   = 2'd1;
	localparam logic [1:0] MAP_BLOODSTORM = 2'd2;

	// Controller wiring onto the board's input ports.
	localparam logic [3:0] INPUTS_SFTM       = 4'd0;
	localparam logic [3:0] INPUTS_TIMEKILL   = 4'd1;
	localparam logic [3:0] INPUTS_BLOODSTORM = 4'd2;
	localparam logic [3:0] INPUTS_HARDYARD   = 4'd3; // four players on P1..P4
	localparam logic [3:0] INPUTS_PAIRS      = 4'd4; // one button per player
	localparam logic [3:0] INPUTS_WCBOWL     = 4'd5; // two hook buttons, no joystick
	localparam logic [3:0] INPUTS_SHUFFLE_BOWL = 4'd6; // 32-bit ports, two buttons
	localparam logic [3:0] INPUTS_GOLDEN_TEE   = 4'd7; // as Shuffle, plus volume buttons
	localparam logic [3:0] INPUTS_PUBBALL      = 4'd8; // as Shuffle, five buttons
	localparam logic [3:0] INPUTS_SHOOTTV      = 4'd9; // coins, starts, gun triggers

	// Trackball ports: two 4-bit position counters per trackball, read as
	// (Y << 4) | X. bloodstm map: the low byte of 0x680000 (second ball
	// 0x680040). itech020 map: bytes 1 and 3 of 0x180800 (second 0x181000).
	localparam logic [1:0] TRACKBALL_NONE    = 2'd0;
	localparam logic [1:0] TRACKBALL_ONE     = 2'd1;
	localparam logic [1:0] TRACKBALL_TWO     = 2'd2;

	// Where the itech020 ROM board wires the trackballs (the bloodstm map has
	// one wiring). Golden Tee's three-tier boards move them to 0x200000.
	localparam logic [1:0] TRACKBALL_AT_180800 = 2'd0; // init_shuffle_bowl_common, init_aama
	localparam logic [1:0] TRACKBALL_AT_200200 = 2'd1; // init_s_ver: one ball, as 0x180800
	localparam logic [1:0] TRACKBALL_AT_200000 = 2'd2; // init_gt3dl: bytes {2, 1, 2, 1}
	localparam logic [1:0] TRACKBALL_WIDE      = 2'd3; // init_gt3d: low word {Y, X}, 8-bit

	// Count release rates. Each keeps the longest gap between the game's
	// trackball reads (MAME 0.288, plus margin for this core's frame rate)
	// inside the counters' reach: 7 counts on 4-bit ports, 127 on 8-bit ones.
	localparam logic [1:0] TRACKBALL_RATE_1600 = 2'd0; // 3.8 ms gaps: bowling, Shuffleshot, gt3dl
	localparam logic [1:0] TRACKBALL_RATE_3600 = 2'd1; // 1.6 ms gaps: Golden Tee single-board, S
	localparam logic [1:0] TRACKBALL_RATE_2200 = 2'd2; // 50 ms gaps, 8-bit: init_gt3d

	// Palette RAM layout presented to the video output.
	localparam logic [1:0] PALETTE_DIRECT     = 2'd0; // itech020 xRGB
	localparam logic [1:0] PALETTE_TIMEKILL   = 2'd1; // GRBx with global intensity
	localparam logic [1:0] PALETTE_BLOODSTORM = 2'd2; // swapped bytes, odd-word fold

	// Where each ES5506 sample bank lives in DDR.
	localparam logic [1:0] SAMPLE_EMPTY  = 2'd0; // reads return zero
	localparam logic [1:0] SAMPLE_SLOT_A = 2'd1; // SAMPLE0_BASE
	localparam logic [1:0] SAMPLE_SLOT_B = 2'd2; // SAMPLE3_BASE
	// The top 4 MiB of the GROM window: only for grom_pages of 58 or fewer.
	localparam logic [1:0] SAMPLE_SLOT_C = 2'd3; // SAMPLEC_BASE

	typedef struct packed {
		// 68000 at 12 MHz; otherwise 68EC020 at 25 MHz.
		logic        cpu_68000;
		logic [1:0]  memory_map;
		logic [3:0]  input_layout;
		logic [1:0]  palette_format;
		// Two framebuffer planes composited at scanout (MAME m_planes = 2):
		// Time Killers and Golden Tee.
		logic        vram_two_planes;
		// 512-row planes (Time Killers' vram_height); otherwise 1024 rows.
		logic        vram_512_rows;
		// itech020 map: 0x300003 loads colour latch 1 and 0x380003 latch 0
		// (MAME's base itech020_map). init_sftm_common and
		// init_shuffle_bowl_common install them the other way round.
		logic        color_latch_swap;
		// Rev-1 sound board: VIA FIRQ and a single command latch.
		logic        sound_rev1;
		// Highest valid value of the 6809 program-bank latch.
		logic [7:0]  sound_last_bank;
		// Battery RAM: a dedicated 128 KiB store at 0x600000, or the first
		// nvram_workram_bytes of work RAM.
		logic        nvram_dedicated;
		logic [16:0] nvram_workram_bytes;
		// Work-RAM address returned by the protection read: the byte read at
		// itech020 0x680002, or the word read at 0x680080 with pic_result_read.
		logic [14:0] protection_address;
		// 68000 bowling ROM board: reads of 0x680080 return the security PIC's
		// result, which MAME models as the work-RAM word at protection_address.
		logic        pic_result_read;
		// Reads of the unpopulated 0x578000-0x57ffff window return zero
		// (MAME nop_read) instead of the board's open bus.
		logic        zero_578000;
		// init_gt2kp/init_gtclasscp: reads of 0x680000-0x680003 return
		// protection_fixed_data instead of the protection byte.
		logic        protection_fixed;
		logic [31:0] protection_fixed_data;
		logic [1:0]  trackball;
		logic [1:0]  trackball_port;
		logic [1:0]  trackball_rate;
		// Blitter source bytes wrap modulo this many 512 KiB pages. The wrap
		// logic supports 16..127 pages (8 MiB..63.5 MiB) with grom_banked, and
		// 4..127 pages without it, where addresses stay below 16 MiB.
		logic [6:0]  grom_pages;
		// The itech020 plane latch's bits 7:6 select a 16 MiB GROM bank. MAME
		// masks them with (GROM length >> 24), so only SFTM's 32.5 MiB GROM
		// uses them.
		logic        grom_banked;
		// Video status (register 0) bits 7:6 report the blitter: 01 busy, 10
		// ready. MAME's blits are instant, so it returns the written value
		// (always "ready"); Golden Tee waits on these bits before switching its
		// blitter interrupt off, and deadlocks its command queue without them.
		logic        blitter_status_live;
		// Two bits per ES5506 bank, bank 0 in bits 1:0 (SAMPLE_* values).
		logic [7:0]  sample_slots;
		// itech020 map: the M48T02 timekeeper's 2 KiB at 0x681000-0x6817ff,
		// one byte per address, saved after the 128 KiB NVRAM.
		logic        timekeeper;
		// Must Shoot TV: two light guns (positions at 0x190000/0x192000)
		// with their scanline interrupts on levels 5 and 6.
		logic        lightgun;
		// The board ignores the vertical-blank interrupt (MAME's shoottv
		// update_interrupts drops VINT).
		logic        vint_disabled;
	} board_profile_t;

	function automatic board_profile_t profile_for_selector(input logic [7:0] selector);
		board_profile_t profile;
		begin
			// Street Fighter: The Movie. MAME's v1.10/v1.11 init address made
			// those sets hang on MiSTer; every hardware-qualified SFTM
			// revision uses the common 0x7a6a protection profile.
			profile.cpu_68000           = 1'b0;
			profile.memory_map          = MAP_ITECH020;
			profile.input_layout        = INPUTS_SFTM;
			profile.palette_format      = PALETTE_DIRECT;
			profile.vram_two_planes     = 1'b0;
			profile.vram_512_rows       = 1'b0;
			profile.color_latch_swap    = 1'b0;
			profile.sound_rev1          = 1'b0;
			profile.sound_last_bank     = 8'd13;
			profile.nvram_dedicated     = 1'b1;
			profile.nvram_workram_bytes = 17'h00000;
			profile.protection_address  = 15'h7a6a;
			profile.pic_result_read     = 1'b0;
			profile.zero_578000         = 1'b1;
			profile.protection_fixed    = 1'b0;
			profile.protection_fixed_data = 32'h0000_0000;
			profile.trackball           = TRACKBALL_NONE;
			profile.trackball_port      = TRACKBALL_AT_180800;
			profile.trackball_rate      = TRACKBALL_RATE_1600;
			profile.grom_pages          = 7'd65;
			profile.grom_banked         = 1'b1;
			profile.blitter_status_live = 1'b0;
			profile.sample_slots        = {SAMPLE_SLOT_B, SAMPLE_EMPTY,
				SAMPLE_EMPTY, SAMPLE_SLOT_A};
			profile.timekeeper          = 1'b0;
			profile.lightgun            = 1'b0;
			profile.vint_disabled       = 1'b0;
			case (selector)
				SELECT_TIMEKILL: begin
					profile.cpu_68000           = 1'b1;
					profile.memory_map          = MAP_TIMEKILL;
					profile.input_layout        = INPUTS_TIMEKILL;
					profile.palette_format      = PALETTE_TIMEKILL;
					profile.vram_two_planes     = 1'b1;
					profile.vram_512_rows       = 1'b1;
					profile.sound_rev1          = 1'b1;
					profile.sound_last_bank     = 8'd5;
					profile.nvram_dedicated     = 1'b0;
					profile.nvram_workram_bytes = 17'h04000;
					profile.protection_address  = 15'h0000;
					profile.zero_578000         = 1'b0;
					profile.grom_pages          = 7'd17;
					profile.grom_banked         = 1'b0;
					profile.sample_slots        = {SAMPLE_EMPTY, SAMPLE_SLOT_A,
						SAMPLE_EMPTY, SAMPLE_EMPTY};
				end
				// MAME's bloodstm machine: BloodStorm, Hard Yardage, the Pairs
				// family and the 68000 World Class Bowling sets share the board.
				SELECT_BLOODSTORM, SELECT_HARDYARD, SELECT_PAIRS,
				SELECT_WCBOWL, SELECT_WCBOWL_J: begin
					profile.cpu_68000           = 1'b1;
					profile.memory_map          = MAP_BLOODSTORM;
					profile.input_layout        = INPUTS_BLOODSTORM;
					profile.palette_format      = PALETTE_BLOODSTORM;
					profile.vram_two_planes     = 1'b0;
					profile.sound_rev1          = 1'b1;
					profile.sound_last_bank     = 8'd5;
					profile.nvram_dedicated     = 1'b0;
					profile.nvram_workram_bytes = 17'h10000;
					profile.protection_address  = 15'h0000;
					profile.zero_578000         = 1'b0;
					case (selector)
						SELECT_HARDYARD: profile.input_layout = INPUTS_HARDYARD;
						SELECT_PAIRS:    profile.input_layout = INPUTS_PAIRS;
						SELECT_WCBOWL, SELECT_WCBOWL_J: begin
							// MAME init_wcbowl/init_wcbowlj: the ROM board adds
							// trackball ports, the security PIC result, and a
							// zero-reading window. v1.3J wires a second trackball.
							profile.input_layout       = INPUTS_WCBOWL;
							profile.trackball          = (selector == SELECT_WCBOWL_J) ?
								TRACKBALL_TWO : TRACKBALL_ONE;
							profile.pic_result_read    = 1'b1;
							profile.protection_address = 15'h111c;
							profile.zero_578000        = 1'b1;
						end
						default: begin end
					endcase
					profile.grom_pages          = 7'd17;
					profile.grom_banked         = 1'b0;
					profile.sample_slots        = {SAMPLE_EMPTY, SAMPLE_SLOT_B,
						SAMPLE_EMPTY, SAMPLE_SLOT_A};
				end
				// MAME's sftm machine with init_shuffle_bowl_common: the SFTM
				// board plus two trackball ports, a 0x28000 sound ROM, and
				// samples in ES5506 banks 0 and 1. Shuffleshot has no bank 1
				// data; its slot is zero-filled. The tournament sets
				// (init_wcbowlt) take the Deluxe protection address and add the
				// timekeeper.
				SELECT_WCBOWL_020, SELECT_WCBOWL_DX, SELECT_SHUFSHOT, SELECT_WCBOWL_T: begin
					profile.input_layout        = INPUTS_SHUFFLE_BOWL;
					profile.trackball           = TRACKBALL_TWO;
					profile.grom_banked         = 1'b0;
					profile.sound_last_bank     = 8'd5;
					profile.sample_slots        = {SAMPLE_EMPTY, SAMPLE_EMPTY,
						SAMPLE_SLOT_B, SAMPLE_SLOT_A};
					case (selector)
						SELECT_WCBOWL_020: begin
							profile.protection_address = 15'h1116; // init_wcbowln
							profile.grom_pages         = 7'd17;
						end
						SELECT_WCBOWL_DX, SELECT_WCBOWL_T: begin
							profile.protection_address = 15'h111a; // init_shufshot
							profile.grom_pages         = 7'd17;
							profile.timekeeper         = selector == SELECT_WCBOWL_T;
						end
						default: begin
							profile.protection_address = 15'h111a;
							profile.grom_pages         = 7'd16;
						end
					endcase
				end
				// MAME's sftm machine with init_gt_common: two 1024-row planes,
				// the base map's colour latches, the protection byte at 0x112f,
				// and a 6 MiB GROM. The boards differ in trackball wiring and
				// which ES5506 banks hold samples.
				SELECT_GT_AAMA, SELECT_GT2K_P, SELECT_GTCLASSC_P, SELECT_GT_S,
				SELECT_GT3D_SHORT, SELECT_GT3D_LONG, SELECT_GT_AAMA_T: begin
					profile.input_layout        = INPUTS_GOLDEN_TEE;
					profile.vram_two_planes     = 1'b1;
					profile.color_latch_swap    = 1'b1;
					profile.sound_last_bank     = 8'd5;
					profile.protection_address  = 15'h112f;
					profile.grom_pages          = 7'd12;
					profile.grom_banked         = 1'b0;
					profile.blitter_status_live = 1'b1;
					case (selector)
						SELECT_GT_S: begin
							profile.trackball      = TRACKBALL_ONE;
							profile.trackball_port = TRACKBALL_AT_200200;
							profile.trackball_rate = TRACKBALL_RATE_3600;
							profile.sample_slots   = {SAMPLE_EMPTY, SAMPLE_SLOT_A,
								SAMPLE_EMPTY, SAMPLE_EMPTY};
						end
						SELECT_GT3D_SHORT: begin
							profile.trackball      = TRACKBALL_ONE;
							profile.trackball_port = TRACKBALL_WIDE;
							profile.trackball_rate = TRACKBALL_RATE_2200;
							profile.sample_slots   = {SAMPLE_SLOT_C, SAMPLE_SLOT_B,
								SAMPLE_EMPTY, SAMPLE_SLOT_A};
						end
						SELECT_GT3D_LONG: begin
							profile.trackball      = TRACKBALL_TWO;
							profile.trackball_port = TRACKBALL_AT_200000;
							profile.sample_slots   = {SAMPLE_SLOT_C, SAMPLE_SLOT_B,
								SAMPLE_EMPTY, SAMPLE_SLOT_A};
						end
						default: begin
							// Single board (AAMA serial numbers 676266 and up);
							// init_aamat adds the tournament timekeeper.
							profile.timekeeper     = selector == SELECT_GT_AAMA_T;
							profile.trackball      = TRACKBALL_TWO;
							profile.trackball_rate = TRACKBALL_RATE_3600;
							profile.sample_slots   = {SAMPLE_EMPTY, SAMPLE_EMPTY,
								SAMPLE_EMPTY, SAMPLE_SLOT_A};
							if (selector == SELECT_GT2K_P) begin
								profile.protection_fixed      = 1'b1;
								profile.protection_fixed_data = 32'h0001_0000;
							end else if (selector == SELECT_GTCLASSC_P) begin
								profile.protection_fixed      = 1'b1;
								profile.protection_fixed_data = 32'h0000_8000;
							end
						end
					endcase
				end
				// MAME's pubball machine: the SFTM board with init_pubball's
				// two 1024-row planes, a 14 MiB GROM, two trackballs at
				// 0x180800, and samples in ES5506 banks 0 and 1. MAME never
				// sets its protection address, so the read returns work-RAM
				// byte 0.
				SELECT_PUBBALL: begin
					profile.input_layout        = INPUTS_PUBBALL;
					profile.vram_two_planes     = 1'b1;
					profile.sound_last_bank     = 8'd5;
					profile.protection_address  = 15'h0000;
					profile.trackball           = TRACKBALL_TWO;
					profile.grom_pages          = 7'd28;
					profile.grom_banked         = 1'b0;
					profile.sample_slots        = {SAMPLE_EMPTY, SAMPLE_EMPTY,
						SAMPLE_SLOT_B, SAMPLE_SLOT_A};
				end
				// MAME's shoottv machine: the SFTM board with two 1024-row
				// planes, SFTM's colour latches, a fixed security-PIC result at
				// 0x680000, a 17-page GROM, samples in bank 0, and two light
				// guns whose interrupts replace VINT.
				SELECT_SHOOTTV: begin
					profile.input_layout          = INPUTS_SHOOTTV;
					profile.vram_two_planes       = 1'b1;
					profile.sound_last_bank       = 8'd5;
					profile.protection_address    = 15'h0000;
					profile.protection_fixed      = 1'b1;
					profile.protection_fixed_data = 32'h0000_2000;
					profile.grom_pages            = 7'd17;
					profile.grom_banked           = 1'b0;
					profile.sample_slots          = {SAMPLE_EMPTY, SAMPLE_EMPTY,
						SAMPLE_EMPTY, SAMPLE_SLOT_A};
					profile.lightgun              = 1'b1;
					profile.vint_disabled         = 1'b1;
				end
				default: begin end
			endcase
			profile_for_selector = profile;
		end
	endfunction

	function automatic logic [1:0] sample_slot(input board_profile_t profile,
		input logic [1:0] bank);
		sample_slot = profile.sample_slots[bank * 2 +: 2];
	endfunction

endpackage
