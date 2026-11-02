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

	// Main-CPU address map (MAME: itech020_map, timekill_map, bloodstm_map).
	localparam logic [1:0] MAP_ITECH020   = 2'd0;
	localparam logic [1:0] MAP_TIMEKILL   = 2'd1;
	localparam logic [1:0] MAP_BLOODSTORM = 2'd2;

	// Controller wiring onto the board's input ports.
	localparam logic [1:0] INPUTS_SFTM       = 2'd0;
	localparam logic [1:0] INPUTS_TIMEKILL   = 2'd1;
	localparam logic [1:0] INPUTS_BLOODSTORM = 2'd2;

	// Palette RAM layout presented to the video output.
	localparam logic [1:0] PALETTE_DIRECT     = 2'd0; // itech020 xRGB
	localparam logic [1:0] PALETTE_TIMEKILL   = 2'd1; // GRBx with global intensity
	localparam logic [1:0] PALETTE_BLOODSTORM = 2'd2; // swapped bytes, odd-word fold

	// Where each ES5506 sample bank lives in DDR.
	localparam logic [1:0] SAMPLE_EMPTY  = 2'd0; // reads return zero
	localparam logic [1:0] SAMPLE_SLOT_A = 2'd1; // SAMPLE0_BASE
	localparam logic [1:0] SAMPLE_SLOT_B = 2'd2; // SAMPLE3_BASE

	typedef struct packed {
		// 68000 at 12 MHz; otherwise 68EC020 at 25 MHz.
		logic        cpu_68000;
		logic [1:0]  memory_map;
		logic [1:0]  input_layout;
		logic [1:0]  palette_format;
		// Time Killers: two 512-row framebuffer planes composited at scanout.
		logic        vram_two_planes;
		// Rev-1 sound board: VIA FIRQ and a single command latch.
		logic        sound_rev1;
		// Highest valid value of the 6809 program-bank latch.
		logic [7:0]  sound_last_bank;
		// Battery RAM: a dedicated 128 KiB store at 0x600000, or the first
		// nvram_workram_bytes of work RAM.
		logic        nvram_dedicated;
		logic [16:0] nvram_workram_bytes;
		// Work-RAM byte returned by the itech020 protection read.
		logic [14:0] protection_address;
		// Blitter source bytes wrap modulo this many 512 KiB pages. The wrap
		// logic supports 16..127 pages (8 MiB..63.5 MiB).
		logic [6:0]  grom_pages;
		// Two bits per ES5506 bank, bank 0 in bits 1:0 (SAMPLE_* values).
		logic [7:0]  sample_slots;
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
			profile.sound_rev1          = 1'b0;
			profile.sound_last_bank     = 8'd13;
			profile.nvram_dedicated     = 1'b1;
			profile.nvram_workram_bytes = 17'h00000;
			profile.protection_address  = 15'h7a6a;
			profile.grom_pages          = 7'd65;
			profile.sample_slots        = {SAMPLE_SLOT_B, SAMPLE_EMPTY,
				SAMPLE_EMPTY, SAMPLE_SLOT_A};
			case (selector)
				SELECT_TIMEKILL: begin
					profile.cpu_68000           = 1'b1;
					profile.memory_map          = MAP_TIMEKILL;
					profile.input_layout        = INPUTS_TIMEKILL;
					profile.palette_format      = PALETTE_TIMEKILL;
					profile.vram_two_planes     = 1'b1;
					profile.sound_rev1          = 1'b1;
					profile.sound_last_bank     = 8'd5;
					profile.nvram_dedicated     = 1'b0;
					profile.nvram_workram_bytes = 17'h04000;
					profile.protection_address  = 15'h0000;
					profile.grom_pages          = 7'd17;
					profile.sample_slots        = {SAMPLE_EMPTY, SAMPLE_SLOT_A,
						SAMPLE_EMPTY, SAMPLE_EMPTY};
				end
				SELECT_BLOODSTORM: begin
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
					profile.grom_pages          = 7'd17;
					profile.sample_slots        = {SAMPLE_EMPTY, SAMPLE_SLOT_B,
						SAMPLE_EMPTY, SAMPLE_SLOT_A};
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
