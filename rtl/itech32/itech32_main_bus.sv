// SPDX-License-Identifier: GPL-2.0-or-later
// SFTM 68EC020 address map. The bus uses big-endian byte lanes:
// address +0 -> data[31:24]/be[3], ... address +3 -> data[7:0]/be[0].
`timescale 1ns/1ps

/* verilator lint_off DECLFILENAME */
module itech32_work_ram (
	input  logic        clk,
	input  logic        write_enable,
	input  logic [3:0]  write_be,
	input  logic [13:0] write_addr,
	input  logic [31:0] write_data,
	input  logic [13:0] read_addr,
	output logic [31:0] read_data,
	// The HPS owns the read port only once the main bus has drained (see
	// nvram_host_owner_q). Host writes select the write port directly.
	input  logic        host_owner,
	input  logic        host_write_enable,
	input  logic [15:0] host_addr,
	input  logic [15:0] host_write_data,
	output logic [15:0] host_read_data
);
	// Quartus 17 does not infer byte enables from a loop over a 32-bit array
	// in this mixed-language hierarchy.  Four byte-wide banks make the four
	// physical write enables explicit and still present one 32-bit read word.
	// BloodStorm needs a physical 64 KiB aperture, not an A15 alias. Preserve
	// the qualified synchronous byte-bank template and its read/ACK schedule.
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] memory_lane0 [0:16383];
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] memory_lane1 [0:16383];
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] memory_lane2 [0:16383];
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] memory_lane3 [0:16383];

	// Configuration-time contents only: MAME's all-zero BloodStorm NVRAM
	// reproduces the invalid stock-score table; FF in bytes 8000..FFFF makes
	// the game's own ROM install its defaults.
	// This upper 32 KiB is outside both SFTM's and Time Killers' RAM maps.
	// Keep the lower region and the clocked RAM template below unchanged.
	// Two 4096-word blocks stay below Quartus 17's 5000-iteration loop limit.
	// These constants become M10K initialization bits, not a runtime clear.
	// The RAM process below is a plain `always` rather than `always_ff`:
	// strict SystemVerilog tools reject an always_ff variable that an initial
	// block also drives. Synthesis is identical.
	initial begin : bloodstorm_powerup_contents
		integer block_index;
		integer word_index;
		for (block_index = 2; block_index < 4; block_index = block_index + 1) begin
			for (word_index = 0; word_index < 4096; word_index = word_index + 1) begin
				memory_lane0[block_index * 4096 + word_index] = 8'hff;
				memory_lane1[block_index * 4096 + word_index] = 8'hff;
				memory_lane2[block_index * 4096 + word_index] = 8'hff;
				memory_lane3[block_index * 4096 + word_index] = 8'hff;
			end
		end
	end

	wire [13:0] port_a_addr = host_write_enable ? host_addr[15:2] : write_addr;
	wire [13:0] read_port_addr = host_owner ? host_addr[15:2] : read_addr;
	always @(posedge clk) begin
		if (host_write_enable) begin
			if (!host_addr[1]) begin
				memory_lane3[port_a_addr] <= host_write_data[7:0];
				memory_lane2[port_a_addr] <= host_write_data[15:8];
			end else begin
				memory_lane1[port_a_addr] <= host_write_data[7:0];
				memory_lane0[port_a_addr] <= host_write_data[15:8];
			end
		end else if (write_enable) begin
			if (write_be[0]) memory_lane0[port_a_addr] <= write_data[7:0];
			if (write_be[1]) memory_lane1[port_a_addr] <= write_data[15:8];
			if (write_be[2]) memory_lane2[port_a_addr] <= write_data[23:16];
			if (write_be[3]) memory_lane3[port_a_addr] <= write_data[31:24];
		end
		read_data[7:0]   <= memory_lane0[read_port_addr];
		read_data[15:8]  <= memory_lane1[read_port_addr];
		read_data[23:16] <= memory_lane2[read_port_addr];
		read_data[31:24] <= memory_lane3[read_port_addr];
	end

	// The HPS owns the existing read port only during an index-2 transfer.
	// WIDE=1 places the lower-addressed file byte in bits 7:0.
	always_comb begin
		if (!host_addr[1])
			host_read_data = {read_data[23:16], read_data[31:24]};
		else
			host_read_data = {read_data[7:0], read_data[15:8]};
	end
endmodule

// Quartus 17 reliably infers the Cyclone V true-dual-port M10K mode from one
// byte-wide memory per instance. Keeping the CPU and video ports in separate
// clocked processes is intentional: a packed 32768x32 array with four partial
// writes and two reads is expanded into logic instead of block RAM.
module itech32_bus_byte_ram_dp #(
	parameter logic INTERNAL_VIDEO_COLLISION_BYPASS = 1'b1
) (
	input  logic        clk,
	input  logic        cpu_write_enable,
	input  logic [14:0] cpu_addr,
	input  logic [7:0]  cpu_write_data,
	output logic [7:0]  cpu_read_data,
	input  logic [14:0] video_addr,
	output logic [7:0]  video_read_data
);
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] memory [0:32767];
	logic [7:0] video_ram_read_data;

	// Port A uses the canonical nonblocking old-data template.  Mixed-port
	// read-during-write is made deterministic outside the array: a CPU write to
	// the byte currently sampled by the video port returns the new CPU byte for
	// that registered video lookup. Keeping the bypass after the raw registered
	// read preserves the true-dual-port M10K inference shape and deterministic
	// new-data collision behavior.
	always_ff @(posedge clk) begin
		if (cpu_write_enable)
			memory[cpu_addr] <= cpu_write_data;
		cpu_read_data <= memory[cpu_addr];
	end

	always_ff @(posedge clk) begin
		video_ram_read_data <= memory[video_addr];
	end

	generate
		if (INTERNAL_VIDEO_COLLISION_BYPASS) begin : gen_internal_video_collision_bypass
			logic [7:0] video_collision_data_q;
			logic       video_collision_q;

			always_ff @(posedge clk) begin
				video_collision_q <= cpu_write_enable && (cpu_addr == video_addr);
				video_collision_data_q <= cpu_write_data;
			end

			assign video_read_data = video_collision_q ?
				video_collision_data_q : video_ram_read_data;
		end else begin : gen_external_video_collision_bypass
			assign video_read_data = video_ram_read_data;
		end
	endgenerate
endmodule

// NVRAM only needs the CPU read/write port. As with the palette RAM, splitting
// the four byte lanes into independent banks maps the byte enables onto four
// physical write enables without a read/modify/write data path.
module itech32_bus_byte_ram_sp #(
	parameter int ADDR_W = 15
) (
	input  logic        clk,
	input  logic        write_enable,
	input  logic [ADDR_W-1:0] addr,
	input  logic [7:0]  write_data,
	output logic [7:0]  read_data,
	// Host writes take the port directly; host reads only once the main bus
	// has drained, so an accepted CPU access always uses its own address.
	input  logic        host_owner,
	input  logic        host_write_enable,
	input  logic [ADDR_W-1:0] host_addr,
	input  logic [7:0]  host_write_data,
	output logic [7:0]  host_read_data
);
	(* ramstyle = "M10K, no_rw_check" *) logic [7:0] memory [0:(1 << ADDR_W) - 1];
	wire [ADDR_W-1:0] port_a_addr = (host_write_enable || host_owner) ? host_addr : addr;

	always_ff @(posedge clk) begin
		if (host_write_enable)
			memory[port_a_addr] <= host_write_data;
		else if (write_enable)
			memory[port_a_addr] <= write_data;
		read_data <= memory[port_a_addr];
	end
	assign host_read_data = read_data;
endmodule
/* verilator lint_on DECLFILENAME */

module itech32_main_bus
	import itech32_profile_pkg::*;
(
	input  logic        clk,
	input  logic        reset,
	input  board_profile_t profile,
	input  logic        rom_buffer_invalidate,
	input  logic        cpu_req,
	input  logic        cpu_we,
	input  logic [23:0] cpu_addr,
	input  logic [31:0] cpu_wdata,
	input  logic [3:0]  cpu_be,
	output logic        cpu_ack,
	output logic [31:0] cpu_rdata,

	input  logic [31:0] input_p1,
	input  logic [31:0] input_p2,
	input  logic [31:0] input_p3,
	input  logic [31:0] input_p4,
	input  logic [31:0] input_dips,
	input  logic [31:0] input_extra,
	// Trackball position counters, {Y, X}. 4-bit ports read the low nibbles.
	input  logic [15:0] trackball1,
	input  logic [15:0] trackball2,
	// Light-gun aim points in visible pixels, {Y[7:0], X[8:0]}.
	input  logic [16:0] lightgun1,
	input  logic [16:0] lightgun2,
	input  logic        nvram_host_access,
	input  logic        nvram_host_write,
	// Byte address: 0x00000-0x1ffff NVRAM, then the timekeeper from 0x20000.
	input  logic [17:0] nvram_host_addr,
	input  logic [15:0] nvram_host_wdata,
	output logic [15:0] nvram_host_rdata,
	// High once an index-2 transfer owns the RAM read ports (bus drained).
	output logic        nvram_host_ready,
	output logic        nvram_cpu_write,
	// M48T02 clock bytes (offsets 0x7f8-0x7ff, byte i at [8i+7:8i]) and the
	// CPU's writes to them.
	input  logic [63:0] timekeeper_clock,
	output logic [7:0]  timekeeper_write_enable,
	output logic [63:0] timekeeper_write_data,

	output logic        video_req,
	output logic        video_we,
	output logic [6:0]  video_addr,
	output logic [15:0] video_wdata,
	output logic [1:0]  video_be,
	input  logic        video_ack,
	input  logic [15:0] video_rdata,

	output logic        rom_req,
	output logic [21:0] rom_addr,
	input  logic        rom_ack,
	input  logic [31:0] rom_rdata,

	output logic        sound_command_valid,
	output logic [7:0]  sound_command,
	output logic        watchdog_strobe,
	output logic        vint_ack_strobe,
	output logic        special_read_strobe,
	// Reads of the light-gun interrupt clear windows (levels 5 and 6).
	output logic        gun_ack5,
	output logic        gun_ack6,
	output logic        color0_strobe,
	output logic        color1_strobe,
	output logic [7:0]  color_data,
	output logic [1:0]  plane_enable,
	output logic [1:0]  grom_bank,

	input  logic [14:0] palette_video_addr,
	output logic [23:0] palette_video_rgb
);

	logic [31:0] palette_cpu_read_data;
	logic [31:0] palette_video_ram_read_data;
	logic [31:0] palette_video_bypass_data_q;
	logic [3:0]  palette_video_bypass_be_q;
	logic [14:0] palette_video_collision_addr_q;
	logic [14:0] palette_cpu_collision_addr_q;
	wire palette_video_match =
		palette_cpu_collision_addr_q == palette_video_collision_addr_q;
	logic [31:0] palette_video_raw_data;
	logic [7:0]  timekill_intensity;
	(* multstyle = "dsp" *) logic [15:0] timekill_red_product_q;
	(* multstyle = "dsp" *) logic [15:0] timekill_green_product_q;
	(* multstyle = "dsp" *) logic [15:0] timekill_blue_product_q;
	(* multstyle = "dsp" *) logic [31:22] timekill_red_quotient_q;
	(* multstyle = "dsp" *) logic [31:22] timekill_green_quotient_q;
	(* multstyle = "dsp" *) logic [31:22] timekill_blue_quotient_q;
	logic [23:0] timekill_palette_rgb_q;
	logic [31:0] nvram_cpu_read_data;
	logic [31:0] nvram_host_read_data;
	logic [15:0] work_ram_host_read_data;
	logic        palette_write_enable;
	logic [3:0]  palette_write_be;
	logic [31:0] palette_write_data;
	logic        nvram_write_enable;
	logic        palette_read_pending;
	logic        nvram_read_pending;
	logic [31:0] timekeeper_cpu_read_data;
	logic [31:0] timekeeper_host_read_data;
	logic        timekeeper_ram_write;
	logic        timekeeper_host_write;
	logic        timekeeper_read_pending;
	logic [13:0] main_ram_read_addr;
	logic [13:0] main_ram_write_addr;
	logic [31:0] main_ram_read_data;
	logic        main_ram_read_pending;
	logic        main_ram_read_is_protection;
	logic        main_ram_protection_word;
	logic [1:0]  main_ram_protection_lane;
	logic        main_ram_write_enable;
	logic [3:0]  main_ram_write_be;
	logic [31:0] main_ram_write_data;
	logic        work_ram_host_write;
	logic        dedicated_nvram_host_write;
	logic        bus_held;
	logic        bus_pending;
	logic        bus_we_q;
	logic [16:1] bus_addr_q;
	logic [31:0] bus_wdata_q;
	logic [3:0]  bus_be_q;
	// (a) The index-2 transfer owns the shared RAM read ports. Set only once
	// every CPU access accepted before the transfer has completed; cleared one
	// edge after the transfer ends.
	logic        nvram_host_owner_q = 1'b0;

	// Classify a request when the request payload enters the existing boundary
	// registers.  The response cycle then selects from this small tag instead of
	// repeating the full 24-bit address map in front of cpu_rdata and cpu_ack.
	// Non-ROM responses and ROM misses retain this stage and its original cycle.
	// A locally retained ROM dword can instead complete at the acceptance edge;
	// cpu_ack/data are still registered and the CPU adapter boundary is unchanged.
	typedef enum logic [4:0] {
		TARGET_UNMAPPED,
		TARGET_MAIN_RAM,
		TARGET_VINT_P1,
		TARGET_P2,
		TARGET_P3,
		TARGET_P4,
		TARGET_DIPS,
		TARGET_COLOR1,
		TARGET_COLOR0,
		TARGET_WATCHDOG,
		TARGET_SOUND_COMMAND,
		TARGET_VIDEO,
		TARGET_OPEN_578,
		TARGET_PALETTE,
		TARGET_NVRAM,
		TARGET_PROTECTION_READ,
		TARGET_PROTECTION_RANGE,
		TARGET_PLANE,
		TARGET_ROM,
		TARGET_TIME_P1,
		TARGET_TIME_P2,
		TARGET_TIME_SYSTEM,
		TARGET_TIME_INTENSITY,
		TARGET_TIME_NOP,
		TARGET_SFTM_UNMAPPED,
		TARGET_EXTRA,
		TARGET_TRACKBALL,
		TARGET_PIC_RESULT,
		TARGET_PROTECTION_FIXED,
		TARGET_TIMEKEEPER,
		TARGET_GUN_ACK,
		TARGET_LIGHTGUN
	} bus_target_t;
	bus_target_t bus_target_q;
	bus_target_t accept_target;

	// Address-map family (MAME's itech020/timekill/bloodstm maps). Several game
	// families share a map; other per-board differences are separate profile
	// fields. MAP_* codes equal the former {bloodstorm, timekill} pair, so the
	// ROM-buffer tag bits are unchanged.
	wire map_timekill   = profile.memory_map == MAP_TIMEKILL;
	wire map_bloodstorm = profile.memory_map == MAP_BLOODSTORM;
	wire map_68000      = map_timekill || map_bloodstorm;

	// Gun register byte: gun 2 at +0x2000; X low byte, X bit 8, Y, zero at
	// +0x000/+0x800/+0x1000/+0x1800. MAME's X range 0x1c-0x19b spans the
	// 384 visible columns.
	wire [16:0] lightgun_selected = bus_addr_q[13] ? lightgun2 : lightgun1;
	wire [8:0] lightgun_x = lightgun_selected[8:0] + 9'd28;
	logic [7:0] lightgun_byte;
	always_comb begin
		case (bus_addr_q[12:11])
			2'd0: lightgun_byte = lightgun_x[7:0];
			2'd1: lightgun_byte = {7'd0, lightgun_x[8]};
			2'd2: lightgun_byte = lightgun_selected[16:9];
			default: lightgun_byte = 8'h00;
		endcase
	end

	// 4-bit trackball port byte, (Y << 4) | X.
	wire [7:0] trackball1_port = {trackball1[11:8], trackball1[3:0]};
	wire [7:0] trackball2_port = {trackball2[11:8], trackball2[3:0]};

	// (a) Retain one complete, immutable ROM response across bus transactions.
	// This is a board-side response buffer, not a modeled 68020 instruction cache.
	// Tag the raw aligned board address plus game mode; both halfwords and all
	// byte lanes are available without another memory request. Payload/tag need
	// no reset because valid is cleared at every ROM-image ownership boundary.
	logic [31:0] rom_buffer_data_q;
	logic [23:0] rom_buffer_tag_q;
	logic        rom_buffer_valid_q;
	// (a) A miss owns its accepted tag until ACK. Reuse bus_addr_q[16:2] for
	// its low bits; only the otherwise-discarded high address and mode need storage.
	logic [8:0]  rom_buffer_pending_tag_hi_q;
	// (a) Sticky cancellation prevents a late pre-invalidation ACK from filling
	// the entry, including two invalidations or a mode A->B->A before that ACK.
	logic        rom_buffer_pending_cancel_q;
	// (a) Detect mode changes even when a standalone board has no loader signal.
	logic [1:0]  rom_buffer_previous_mode_q;
	wire rom_buffer_cancel = rom_buffer_invalidate ||
		(profile.memory_map != rom_buffer_previous_mode_q);
	wire bus_idle = !bus_pending && !main_ram_read_pending &&
		!palette_read_pending && !nvram_read_pending && !timekeeper_read_pending;
	// runtime_hold stops the CPU from starting new cycles, but the TG68 adapter
	// still presents a cycle it captured just before an upload began. Leave that
	// request unaccepted (and unacknowledged) until the transfer has released
	// the RAM ports, so it can never be served from or written to the host's
	// address. The owner term covers the edge after the transfer ends.
	wire nvram_host_hold = nvram_host_access || nvram_host_owner_q;
	wire bus_accept = cpu_req && !bus_held && bus_idle && !nvram_host_hold;
	wire rom_buffer_hit = rom_buffer_valid_q && !rom_buffer_cancel &&
		(accept_target == TARGET_ROM) &&
		(rom_buffer_tag_q == {profile.memory_map, cpu_addr[23:2]});

	function automatic logic [7:0] select_addressed_byte(
		input logic [31:0] word_value,
		input logic [1:0] address_low
	);
		case (address_low)
			2'd0: select_addressed_byte = word_value[31:24];
			2'd1: select_addressed_byte = word_value[23:16];
			2'd2: select_addressed_byte = word_value[15:8];
			default: select_addressed_byte = word_value[7:0];
		endcase
	endfunction

	function automatic logic [31:0] place_addressed_byte(
		input logic [7:0] byte_value,
		input logic [1:0] address_low
	);
		logic [31:0] result;
		begin
			result = 32'd0;
			case (address_low)
				2'd0: result[31:24] = byte_value;
				2'd1: result[23:16] = byte_value;
				2'd2: result[15:8]  = byte_value;
				default: result[7:0] = byte_value;
			endcase
			place_addressed_byte = result;
		end
	endfunction

	function automatic bus_target_t decode_bus_target(
		input logic        write_cycle,
		input logic [23:0] address,
		input board_profile_t profile
	);
		logic [1:0] memory_map;
		begin
			memory_map = profile.memory_map;
			// Capture the board-specific open-read policy in the existing tag.
			// MAME's itech020_map uses zero for unhandled SFTM reads; the ROM's
			// 0x041107 probe relies on it. Keep the Time Killers map unchanged.
			decode_bus_target = (memory_map == MAP_TIMEKILL ||
				memory_map == MAP_BLOODSTORM) ? TARGET_UNMAPPED : TARGET_SFTM_UNMAPPED;
			if (memory_map == MAP_TIMEKILL) begin
				if (address < 24'h004000)
					decode_bus_target = TARGET_MAIN_RAM;
				else if (!write_cycle && address >= 24'h040000 && address <= 24'h040001)
					decode_bus_target = TARGET_TIME_P1;
				else if (!write_cycle && address >= 24'h048000 && address <= 24'h048001)
					decode_bus_target = TARGET_TIME_P2;
				else if (!write_cycle && address >= 24'h050000 && address <= 24'h050001)
					decode_bus_target = TARGET_TIME_SYSTEM;
				// A 68000 word write is presented at the even address with
				// BE[3:2]; the mapped odd byte is lane 2.  Decode the complete
				// word and let TARGET_TIME_INTENSITY gate the real byte lane.
				else if (write_cycle && address >= 24'h050000 && address <= 24'h050001)
					decode_bus_target = TARGET_TIME_INTENSITY;
				else if (address >= 24'h058000 && address <= 24'h058001)
					decode_bus_target = TARGET_DIPS;
				else if (write_cycle && address >= 24'h060000 && address <= 24'h060003)
					decode_bus_target = TARGET_COLOR0;
				else if (write_cycle && address >= 24'h068000 && address <= 24'h068003)
					decode_bus_target = TARGET_COLOR1;
				else if (write_cycle && address >= 24'h070000 && address <= 24'h070001)
					decode_bus_target = TARGET_TIME_NOP;
				else if (write_cycle && address == 24'h078001)
					decode_bus_target = TARGET_SOUND_COMMAND;
				else if (address >= 24'h080000 && address <= 24'h08007f)
					decode_bus_target = TARGET_VIDEO;
				else if (write_cycle && address >= 24'h0a0000 && address <= 24'h0a0001)
					decode_bus_target = TARGET_VINT_P1;
				else if (address >= 24'h0c0000 && address <= 24'h0c7fff)
					decode_bus_target = TARGET_PALETTE;
				else if (!write_cycle && address >= 24'h100000 && address <= 24'h17ffff)
					decode_bus_target = TARGET_ROM;
			end else if (memory_map == MAP_BLOODSTORM) begin
				if (address < 24'h010000)
					decode_bus_target = TARGET_MAIN_RAM;
				else if (address >= 24'h080000 && address <= 24'h080001)
					decode_bus_target = TARGET_VINT_P1;
				else if (!write_cycle && address >= 24'h100000 && address <= 24'h100001)
					decode_bus_target = TARGET_P2;
				else if (!write_cycle && address >= 24'h180000 && address <= 24'h180001)
					decode_bus_target = TARGET_P3;
				else if (address >= 24'h200000 && address <= 24'h200001)
					decode_bus_target = TARGET_P4;
				else if (!write_cycle && address >= 24'h280000 && address <= 24'h280001)
					decode_bus_target = TARGET_DIPS;
				else if (write_cycle && address >= 24'h300000 && address <= 24'h300001)
					decode_bus_target = TARGET_COLOR0;
				else if (write_cycle && address >= 24'h380000 && address <= 24'h380001)
					decode_bus_target = TARGET_COLOR1;
				else if (write_cycle && address >= 24'h400000 && address <= 24'h400001)
					decode_bus_target = TARGET_WATCHDOG;
				else if (write_cycle && address >= 24'h480000 && address <= 24'h480001)
					decode_bus_target = TARGET_SOUND_COMMAND;
				else if (address >= 24'h500000 && address <= 24'h5000ff)
					decode_bus_target = TARGET_VIDEO;
				else if (address >= 24'h580000 && address <= 24'h59ffff)
					decode_bus_target = TARGET_PALETTE;
				else if (write_cycle && address >= 24'h700000 && address <= 24'h700001)
					decode_bus_target = TARGET_PLANE;
				else if (!write_cycle && address >= 24'h780000 && address <= 24'h780001)
					decode_bus_target = TARGET_EXTRA;
				// ROM-board additions (MAME init_wcbowl/init_wcbowlj).
				else if (!write_cycle && profile.zero_578000 &&
					address >= 24'h578000 && address <= 24'h57ffff)
					decode_bus_target = TARGET_OPEN_578;
				else if (!write_cycle && profile.trackball != TRACKBALL_NONE &&
					address >= 24'h680000 && address <= 24'h680001)
					decode_bus_target = TARGET_TRACKBALL;
				else if (!write_cycle && profile.trackball == TRACKBALL_TWO &&
					address >= 24'h680040 && address <= 24'h680041)
					decode_bus_target = TARGET_TRACKBALL;
				else if (!write_cycle && profile.pic_result_read &&
					address >= 24'h680080 && address <= 24'h680081)
					decode_bus_target = TARGET_PIC_RESULT;
				else if (!write_cycle && address[23])
					decode_bus_target = TARGET_ROM;
			end else if (address < 24'h008000)
				decode_bus_target = TARGET_MAIN_RAM;
			else if (address >= 24'h080000 && address <= 24'h080003)
				decode_bus_target = TARGET_VINT_P1;
			else if (!write_cycle && address >= 24'h100000 && address <= 24'h100003)
				decode_bus_target = TARGET_P2;
			else if (!write_cycle && address >= 24'h180000 && address <= 24'h180003)
				decode_bus_target = TARGET_P3;
			// Must Shoot TV (MAME shoottv_map): reading 0x183000 clears the
			// guns' level-6 interrupt and 0x183800-0x188003 level 5; the gun
			// registers are the first dword of each 2 KiB step at 0x190000.
			else if (!write_cycle && profile.lightgun &&
				((address >= 24'h183000 && address <= 24'h183003) ||
				 (address >= 24'h183800 && address <= 24'h188003)))
				decode_bus_target = TARGET_GUN_ACK;
			else if (!write_cycle && profile.lightgun &&
				address >= 24'h190000 && address <= 24'h193803 && address[10:2] == 9'd0)
				decode_bus_target = TARGET_LIGHTGUN;
			// Shuffleshot, World Class Bowling and Golden Tee trackballs
			// (MAME init_shuffle_bowl_common, init_aama, init_s_ver,
			// init_gt3d, init_gt3dl).
			else if (!write_cycle && profile.trackball != TRACKBALL_NONE &&
				profile.trackball_port == TRACKBALL_AT_180800 &&
				address >= 24'h180800 && address <= 24'h180803)
				decode_bus_target = TARGET_TRACKBALL;
			else if (!write_cycle && profile.trackball == TRACKBALL_TWO &&
				profile.trackball_port == TRACKBALL_AT_180800 &&
				address >= 24'h181000 && address <= 24'h181003)
				decode_bus_target = TARGET_TRACKBALL;
			else if (!write_cycle && profile.trackball != TRACKBALL_NONE &&
				profile.trackball_port == TRACKBALL_AT_200200 &&
				address >= 24'h200200 && address <= 24'h200203)
				decode_bus_target = TARGET_TRACKBALL;
			// The three-tier Golden Tee 3D boards replace P4 with the ports.
			else if (!write_cycle && profile.trackball != TRACKBALL_NONE &&
				(profile.trackball_port == TRACKBALL_AT_200000 ||
				 profile.trackball_port == TRACKBALL_WIDE) &&
				address >= 24'h200000 && address <= 24'h200003)
				decode_bus_target = TARGET_TRACKBALL;
			else if (!write_cycle && address >= 24'h200000 && address <= 24'h200003)
				decode_bus_target = TARGET_P4;
			else if (!write_cycle && address >= 24'h280000 && address <= 24'h280003)
				decode_bus_target = TARGET_DIPS;
			else if (write_cycle && address >= 24'h300000 && address <= 24'h300003)
				// MAME installs SFTM's handler across this dword with a 000000ff
				// mask. Decode the full board range; TARGET_COLOR0 gates the actual
				// latch strictly with BE[0], so +0/+1/+2 have no side effect.
				decode_bus_target = profile.color_latch_swap ? TARGET_COLOR1 : TARGET_COLOR0;
			else if (write_cycle && address >= 24'h380000 && address <= 24'h380003)
				decode_bus_target = profile.color_latch_swap ? TARGET_COLOR0 : TARGET_COLOR1;
			else if (write_cycle && address >= 24'h400000 && address <= 24'h400003)
				decode_bus_target = TARGET_WATCHDOG;
			// MAME's byte handler at 0x480001 takes any write that includes that
			// byte: SFTM and the bowling games write the byte, Golden Tee a word
			// at 0x480000. TARGET_SOUND_COMMAND gates on byte lane +1 (BE[2]).
			else if (write_cycle && address >= 24'h480000 && address <= 24'h480003)
				decode_bus_target = TARGET_SOUND_COMMAND;
			else if (address >= 24'h500000 && address <= 24'h5000ff)
				decode_bus_target = TARGET_VIDEO;
			else if (!write_cycle && profile.zero_578000 &&
				address >= 24'h578000 && address <= 24'h57ffff)
				decode_bus_target = TARGET_OPEN_578;
			else if (address >= 24'h580000 && address <= 24'h59ffff)
				decode_bus_target = TARGET_PALETTE;
			else if (address >= 24'h600000 && address <= 24'h61ffff)
				decode_bus_target = TARGET_NVRAM;
			else if (!write_cycle && profile.protection_fixed &&
				address >= 24'h680000 && address <= 24'h680003)
				decode_bus_target = TARGET_PROTECTION_FIXED;
			else if (!write_cycle && address == 24'h680002)
				decode_bus_target = TARGET_PROTECTION_READ;
			else if (address >= 24'h680000 && address <= 24'h68083f)
				decode_bus_target = TARGET_PROTECTION_RANGE;
			// Tournament boards (MAME install_timekeeper): an 8-bit device on
			// every byte lane, so CPU address 0x681000 + n is offset n.
			else if (profile.timekeeper && address >= 24'h681000 && address <= 24'h6817ff)
				decode_bus_target = TARGET_TIMEKEEPER;
			else if (write_cycle && address == 24'h700002)
				decode_bus_target = TARGET_PLANE;
			else if (!write_cycle && address >= 24'h800000 && address <= 24'hbfffff)
				decode_bus_target = TARGET_ROM;
		end
	endfunction

	assign accept_target = decode_bus_target(cpu_we, cpu_addr, profile);
	// Ordinary work-RAM reads use the adapter's already-registered accepted
	// address for the synchronous probe, then the existing pending response
	// register. Protection, palette, NVRAM and writes keep their old schedule.
	wire main_ram_accept_read = bus_accept && !cpu_we &&
		accept_target == TARGET_MAIN_RAM;

	// Buffer ownership is independent of the existing bus response pipeline.
	// Invalidation cancels allocation, not delivery of an already-owned response.
	// No live address/mode or unowned ACK is used to allocate a completed miss.
	always_ff @(posedge clk) begin
		rom_buffer_previous_mode_q <= profile.memory_map;
		if (reset) begin
			rom_buffer_valid_q <= 1'b0;
			rom_buffer_pending_cancel_q <= 1'b0;
		end else begin
			if (rom_buffer_cancel) begin
				rom_buffer_valid_q <= 1'b0;
				rom_buffer_pending_cancel_q <= 1'b1;
			end
			if (bus_accept && (accept_target == TARGET_ROM) && !rom_buffer_hit) begin
				rom_buffer_pending_tag_hi_q <= {profile.memory_map, cpu_addr[23:17]};
				rom_buffer_pending_cancel_q <= rom_buffer_cancel;
			end
			if (bus_pending && (bus_target_q == TARGET_ROM) && rom_req && rom_ack &&
				!rom_buffer_pending_cancel_q && !rom_buffer_cancel) begin
				rom_buffer_data_q <= rom_rdata;
				rom_buffer_tag_q <= {rom_buffer_pending_tag_hi_q, bus_addr_q[16:2]};
				rom_buffer_valid_q <= 1'b1;
			end
		end
	end

	// No reset term: board reset clears the pending flags, so bus_idle already
	// lets a transfer that overlaps reset (an index-2 restore) take ownership.
	always_ff @(posedge clk)
		nvram_host_owner_q <= nvram_host_access && (nvram_host_owner_q || bus_idle);
	assign nvram_host_ready = nvram_host_owner_q;

	// Keep the main work RAM to one synchronous read port and one byte-enabled
	// write port.  Besides matching a real memory's latency, this form infers
	// Cyclone V block RAM; selecting main/protection addresses inside the bus
	// response process made Quartus implement the entire 32 KiB as registers.
	always_comb begin
		if (main_ram_accept_read)
			main_ram_read_addr = cpu_addr[15:2];
		else if (bus_target_q == TARGET_PROTECTION_READ ||
			bus_target_q == TARGET_PIC_RESULT)
			main_ram_read_addr = {1'b0, profile.protection_address[14:2]};
		else
			main_ram_read_addr = bus_addr_q[15:2];

		main_ram_write_addr = bus_addr_q[15:2];
		main_ram_write_enable = !reset && bus_pending && bus_we_q &&
			bus_target_q == TARGET_MAIN_RAM;
		main_ram_write_be = bus_be_q;
		main_ram_write_data = bus_wdata_q;
	end


	itech32_work_ram work_ram (
		.clk(clk), .write_enable(main_ram_write_enable),
		.write_be(main_ram_write_be), .write_addr(main_ram_write_addr),
		.write_data(main_ram_write_data), .read_addr(main_ram_read_addr),
		.read_data(main_ram_read_data),
		.host_owner(nvram_host_owner_q),
		.host_write_enable(work_ram_host_write),
		.host_addr(nvram_host_addr[15:0]),
		.host_write_data(nvram_host_wdata),
		.host_read_data(work_ram_host_read_data)
	);

	// Palette port A services CPU reads and byte-enabled writes. Port B is the
	// continuously running video lookup and retains the original one-clock
	// address-to-RGB latency.
	assign palette_write_enable = !reset && bus_pending && bus_we_q &&
		bus_target_q == TARGET_PALETTE;

	// MAME bloodstm_paletteram_w folds an odd-word MSB-only write onto
	// that word's LSB. Normalize once for both storage and collision bypass.
	// Full odd-word writes are not folded; CPU readback remains big-endian.
	always_comb begin
		palette_write_be = bus_be_q;
		palette_write_data = bus_wdata_q;
		if (profile.palette_format == PALETTE_BLOODSTORM && bus_addr_q[1] &&
			bus_be_q[1:0] == 2'b10) begin
			palette_write_be[1:0] = 2'b01;
			palette_write_data[7:0] = bus_wdata_q[15:8];
		end
	end

	// The live scanout address still enters every M10K on this edge. Capture that
	// address and the CPU write address in parallel with the bypass metadata, then
	// compare only the local registers after the edge. This preserves the proven
	// one-edge palette-RAM contract while removing the distant scanout mux from a
	// registered collision-decode cone. Do not feed the captured video address
	// back into the RAMs: that extra palette stage was hardware-rejected.
	always_ff @(posedge clk) begin
		palette_video_collision_addr_q <= palette_video_addr;
		palette_cpu_collision_addr_q <= bus_addr_q[16:2];
		palette_video_bypass_be_q <= palette_write_enable ?
			palette_write_be : 4'b0000;
		if (palette_write_enable)
			palette_video_bypass_data_q <= palette_write_data;
	end

	itech32_bus_byte_ram_dp #(.INTERNAL_VIDEO_COLLISION_BYPASS(1'b0)) palette_lane0 (
		.clk(clk), .cpu_write_enable(palette_write_enable && palette_write_be[0]),
		.cpu_addr(bus_addr_q[16:2]), .cpu_write_data(palette_write_data[7:0]),
		.cpu_read_data(palette_cpu_read_data[7:0]),
		.video_addr(palette_video_addr),
		.video_read_data(palette_video_ram_read_data[7:0])
	);
	itech32_bus_byte_ram_dp #(.INTERNAL_VIDEO_COLLISION_BYPASS(1'b0)) palette_lane1 (
		.clk(clk), .cpu_write_enable(palette_write_enable && palette_write_be[1]),
		.cpu_addr(bus_addr_q[16:2]), .cpu_write_data(palette_write_data[15:8]),
		.cpu_read_data(palette_cpu_read_data[15:8]),
		.video_addr(palette_video_addr),
		.video_read_data(palette_video_ram_read_data[15:8])
	);
	itech32_bus_byte_ram_dp #(.INTERNAL_VIDEO_COLLISION_BYPASS(1'b0)) palette_lane2 (
		.clk(clk), .cpu_write_enable(palette_write_enable && palette_write_be[2]),
		.cpu_addr(bus_addr_q[16:2]), .cpu_write_data(palette_write_data[23:16]),
		.cpu_read_data(palette_cpu_read_data[23:16]),
		.video_addr(palette_video_addr),
		.video_read_data(palette_video_ram_read_data[23:16])
	);
	itech32_bus_byte_ram_dp #(.INTERNAL_VIDEO_COLLISION_BYPASS(1'b0)) palette_lane3 (
		.clk(clk), .cpu_write_enable(palette_write_enable && palette_write_be[3]),
		.cpu_addr(bus_addr_q[16:2]), .cpu_write_data(palette_write_data[31:24]),
		.cpu_read_data(palette_cpu_read_data[31:24]),
		.video_addr(palette_video_addr),
		.video_read_data(palette_video_ram_read_data[31:24])
	);

	assign palette_video_raw_data[7:0] =
		(palette_video_match && palette_video_bypass_be_q[0]) ?
		palette_video_bypass_data_q[7:0] : palette_video_ram_read_data[7:0];
	assign palette_video_raw_data[15:8] =
		(palette_video_match && palette_video_bypass_be_q[1]) ?
		palette_video_bypass_data_q[15:8] : palette_video_ram_read_data[15:8];
	assign palette_video_raw_data[23:16] =
		(palette_video_match && palette_video_bypass_be_q[2]) ?
		palette_video_bypass_data_q[23:16] : palette_video_ram_read_data[23:16];
	assign palette_video_raw_data[31:24] =
		(palette_video_match && palette_video_bypass_be_q[3]) ?
		palette_video_bypass_data_q[31:24] : palette_video_ram_read_data[31:24];

	function automatic logic [7:0] saturate_timekill_component(
		input logic [9:0] quotient
	);
		if (|quotient[9:8])
			saturate_timekill_component = 8'hff;
		else
			saturate_timekill_component = quotient[7:0];
	endfunction

	// Time Killers applies one global contrast value to its GRBx_888 palette.
	// The exact floor(component*intensity/96) quotient is implemented with the
	// fixed reciprocal 43691/2^22, which is exact over the complete 8x8 product
	// domain. Two registered DSP-friendly stages settle many fabric clocks before
	// the next pixel-enable edge; the external video cadence is unchanged.
	always_ff @(posedge clk) begin
		timekill_red_product_q <= palette_video_raw_data[23:16] * timekill_intensity;
		timekill_green_product_q <= palette_video_raw_data[31:24] * timekill_intensity;
		timekill_blue_product_q <= palette_video_raw_data[15:8] * timekill_intensity;
		timekill_red_quotient_q <=
			10'((32'(timekill_red_product_q) * 32'd43691) >> 22);
		timekill_green_quotient_q <=
			10'((32'(timekill_green_product_q) * 32'd43691) >> 22);
		timekill_blue_quotient_q <=
			10'((32'(timekill_blue_product_q) * 32'd43691) >> 22);
		timekill_palette_rgb_q <= {
			saturate_timekill_component(timekill_red_quotient_q),
			saturate_timekill_component(timekill_green_quotient_q),
			saturate_timekill_component(timekill_blue_quotient_q)
		};
	end

	assign palette_video_rgb =
		(profile.palette_format == PALETTE_TIMEKILL) ? timekill_palette_rgb_q :
		(profile.palette_format == PALETTE_BLOODSTORM) ?
			{palette_video_raw_data[23:16], palette_video_raw_data[31:24],
			 palette_video_raw_data[7:0]} : palette_video_raw_data[23:0];

	assign nvram_write_enable = !reset && bus_pending && bus_we_q &&
		bus_target_q == TARGET_NVRAM;
	// Battery RAM is either the dedicated 128 KiB store or the low
	// nvram_workram_bytes of work RAM (where every work-RAM write is dirty).
	wire workram_host_in_range = nvram_host_addr < {1'b0, profile.nvram_workram_bytes};
	assign work_ram_host_write = nvram_host_write && !profile.nvram_dedicated &&
		workram_host_in_range;
	// The host image continues past the 128 KiB store with the timekeeper's
	// 2 KiB (byte n at image offset 0x20000 + n).
	wire timekeeper_host_select = profile.timekeeper && nvram_host_addr[17];
	assign dedicated_nvram_host_write = nvram_host_write && profile.nvram_dedicated &&
		!nvram_host_addr[17];
	assign timekeeper_host_write = nvram_host_write && timekeeper_host_select;
	assign timekeeper_ram_write = !reset && bus_pending && bus_we_q &&
		bus_target_q == TARGET_TIMEKEEPER;
	assign nvram_cpu_write = nvram_write_enable || timekeeper_ram_write ||
		(main_ram_write_enable && !profile.nvram_dedicated);
	wire [31:0] dedicated_host_read_data = timekeeper_host_select ?
		timekeeper_host_read_data : nvram_host_read_data;
	assign nvram_host_rdata = !profile.nvram_dedicated ?
		(workram_host_in_range ? work_ram_host_read_data : 16'd0) :
		(!nvram_host_addr[1] ?
			{dedicated_host_read_data[23:16], dedicated_host_read_data[31:24]} :
			{dedicated_host_read_data[7:0], dedicated_host_read_data[15:8]});
	itech32_bus_byte_ram_sp nvram_lane0 (
		.clk(clk), .write_enable(nvram_write_enable && bus_be_q[0]),
		.addr(bus_addr_q[16:2]), .write_data(bus_wdata_q[7:0]),
		.read_data(nvram_cpu_read_data[7:0]),
		.host_owner(nvram_host_owner_q),
		.host_write_enable(dedicated_nvram_host_write && nvram_host_addr[1]),
		.host_addr(nvram_host_addr[16:2]),
		.host_write_data(nvram_host_wdata[15:8]),
		.host_read_data(nvram_host_read_data[7:0])
	);
	itech32_bus_byte_ram_sp nvram_lane1 (
		.clk(clk), .write_enable(nvram_write_enable && bus_be_q[1]),
		.addr(bus_addr_q[16:2]), .write_data(bus_wdata_q[15:8]),
		.read_data(nvram_cpu_read_data[15:8]),
		.host_owner(nvram_host_owner_q),
		.host_write_enable(dedicated_nvram_host_write && nvram_host_addr[1]),
		.host_addr(nvram_host_addr[16:2]),
		.host_write_data(nvram_host_wdata[7:0]),
		.host_read_data(nvram_host_read_data[15:8])
	);
	itech32_bus_byte_ram_sp nvram_lane2 (
		.clk(clk), .write_enable(nvram_write_enable && bus_be_q[2]),
		.addr(bus_addr_q[16:2]), .write_data(bus_wdata_q[23:16]),
		.read_data(nvram_cpu_read_data[23:16]),
		.host_owner(nvram_host_owner_q),
		.host_write_enable(dedicated_nvram_host_write && !nvram_host_addr[1]),
		.host_addr(nvram_host_addr[16:2]),
		.host_write_data(nvram_host_wdata[15:8]),
		.host_read_data(nvram_host_read_data[23:16])
	);
	itech32_bus_byte_ram_sp nvram_lane3 (
		.clk(clk), .write_enable(nvram_write_enable && bus_be_q[3]),
		.addr(bus_addr_q[16:2]), .write_data(bus_wdata_q[31:24]),
		.read_data(nvram_cpu_read_data[31:24]),
		.host_owner(nvram_host_owner_q),
		.host_write_enable(dedicated_nvram_host_write && !nvram_host_addr[1]),
		.host_addr(nvram_host_addr[16:2]),
		.host_write_data(nvram_host_wdata[7:0]),
		.host_read_data(nvram_host_read_data[31:24])
	);

	// Timekeeper battery RAM, offsets 0x000-0x7ff in four byte lanes with the
	// NVRAM's host byte order. The clock bytes at 0x7f8-0x7ff are also written
	// here (MAME keeps them in its RAM image) but read from timekeeper_clock.
	genvar timekeeper_lane;
	generate
		for (timekeeper_lane = 0; timekeeper_lane < 4; timekeeper_lane++) begin : timekeeper_ram
			itech32_bus_byte_ram_sp #(.ADDR_W(9)) lane (
				.clk(clk),
				.write_enable(timekeeper_ram_write && bus_be_q[timekeeper_lane]),
				.addr(bus_addr_q[10:2]),
				.write_data(bus_wdata_q[8 * timekeeper_lane +: 8]),
				.read_data(timekeeper_cpu_read_data[8 * timekeeper_lane +: 8]),
				.host_owner(nvram_host_owner_q),
				.host_write_enable(timekeeper_host_write &&
					(nvram_host_addr[1] == (timekeeper_lane < 2))),
				.host_addr(nvram_host_addr[10:2]),
				.host_write_data((timekeeper_lane % 2 == 1) ? nvram_host_wdata[7:0] :
					nvram_host_wdata[15:8]),
				.host_read_data(timekeeper_host_read_data[8 * timekeeper_lane +: 8])
			);
		end
	endgenerate

	// Offsets 0x7f8-0x7fb (dword 0x6817f8) and 0x7fc-0x7ff (0x6817fc) are the
	// clock: offset +k of the dword is byte lane 3 - k.
	wire timekeeper_clock_dword = bus_addr_q[10:3] == 8'hff;
	always_comb begin
		for (int k = 0; k < 4; k++) begin
			timekeeper_write_enable[k] = timekeeper_ram_write && timekeeper_clock_dword &&
				!bus_addr_q[2] && bus_be_q[3 - k];
			timekeeper_write_enable[4 + k] = timekeeper_ram_write && timekeeper_clock_dword &&
				bus_addr_q[2] && bus_be_q[3 - k];
			timekeeper_write_data[8 * k +: 8] = bus_wdata_q[8 * (3 - k) +: 8];
			timekeeper_write_data[8 * (4 + k) +: 8] = bus_wdata_q[8 * (3 - k) +: 8];
		end
	end
	wire [31:0] timekeeper_clock_read = bus_addr_q[2] ?
		{timekeeper_clock[39:32], timekeeper_clock[47:40], timekeeper_clock[55:48],
		 timekeeper_clock[63:56]} :
		{timekeeper_clock[7:0], timekeeper_clock[15:8], timekeeper_clock[23:16],
		 timekeeper_clock[31:24]};

	always_ff @(posedge clk) begin
		cpu_ack             <= 1'b0;
		video_req           <= 1'b0;
		rom_req             <= 1'b0;
		sound_command_valid <= 1'b0;
		watchdog_strobe     <= 1'b0;
		gun_ack5            <= 1'b0;
		gun_ack6            <= 1'b0;
		vint_ack_strobe      <= 1'b0;
		special_read_strobe <= 1'b0;
		color0_strobe       <= 1'b0;
		color1_strobe       <= 1'b0;
		// Capture the outward-facing payloads independently of their high address
		// decodes. They are ignored unless the associated request is asserted, and
		// the upstream adapter holds them stable until cpu_ack.
		video_we             <= cpu_we;
		// Time Killers exposes the native 16-bit register spacing. SFTM's
		// bloodstm handlers divide the 32-bit aperture offset by two, so +0/+2
		// remain upper/lower aliases of one native register in that mode.
		video_addr           <= map_timekill ? cpu_addr[7:1] : cpu_addr[8:2];
		video_wdata          <= cpu_addr[1] ? cpu_wdata[15:0] : cpu_wdata[31:16];
		video_be             <= cpu_addr[1] ? cpu_be[1:0] : cpu_be[3:2];
		rom_addr             <= map_68000 ?
			{3'd0, cpu_addr[18:0]} : cpu_addr[21:0];

		if (reset) begin
			cpu_rdata                  <= 32'd0;
			plane_enable               <= profile.vram_two_planes ? 2'b11 : 2'b01;
			grom_bank                  <= 2'b00;
			color_data                 <= 8'd0;
			timekill_intensity          <= 8'h60;
			main_ram_read_pending       <= 1'b0;
			main_ram_read_is_protection <= 1'b0;
			main_ram_protection_word    <= 1'b0;
			main_ram_protection_lane    <= 2'd0;
			palette_read_pending         <= 1'b0;
			nvram_read_pending           <= 1'b0;
			timekeeper_read_pending      <= 1'b0;
			bus_held                     <= 1'b0;
			bus_pending                  <= 1'b0;
			bus_we_q                     <= 1'b0;
			bus_addr_q                   <= 16'd0;
			bus_wdata_q                  <= 32'd0;
			bus_be_q                     <= 4'd0;
			bus_target_q                 <= TARGET_UNMAPPED;
		end else begin
			if (!cpu_req)
				bus_held <= 1'b0;

			// The adapter holds this request through its response. A local ROM hit
			// registers the response here, then the unchanged adapter captures it on
			// the next carrier edge and consumes it only on a later CPU enable.
			if (bus_accept) begin
				bus_held <= 1'b1;
				bus_pending <= !(rom_buffer_hit || main_ram_accept_read);
				bus_we_q <= cpu_we;
				bus_addr_q <= cpu_addr[16:1];
				bus_wdata_q <= cpu_wdata;
				bus_be_q <= cpu_be;
				bus_target_q <= accept_target;
				if (main_ram_accept_read) begin
					main_ram_read_pending <= 1'b1;
					main_ram_read_is_protection <= 1'b0;
				end
				// Address is registered on this same edge. Begin the owned ROM
				// request with that payload; pending dispatch holds it until ACK.
				// This removes only the idle request-launch clock, not any
				// registered response or the adapter's CPU-enable boundary.
				if ((accept_target == TARGET_ROM) && !rom_buffer_hit)
					rom_req <= 1'b1;
				if (rom_buffer_hit) begin
					cpu_rdata <= rom_buffer_data_q;
					cpu_ack <= 1'b1;
				end
			end

			if (main_ram_read_pending) begin
				// The PIC result is a whole 68000 word; either bus half carries it.
				if (main_ram_read_is_protection && main_ram_protection_word)
					cpu_rdata <= {2{main_ram_protection_lane[1] ?
						main_ram_read_data[15:0] : main_ram_read_data[31:16]}};
				else if (main_ram_read_is_protection)
					cpu_rdata <= place_addressed_byte(
						select_addressed_byte(main_ram_read_data,
							main_ram_protection_lane), 2'd2);
				else
					cpu_rdata <= main_ram_read_data;
				cpu_ack <= 1'b1;
				main_ram_read_pending <= 1'b0;
			end else if (palette_read_pending) begin
				cpu_rdata <= palette_cpu_read_data;
				cpu_ack <= 1'b1;
				palette_read_pending <= 1'b0;
			end else if (nvram_read_pending) begin
				cpu_rdata <= nvram_cpu_read_data;
				cpu_ack <= 1'b1;
				nvram_read_pending <= 1'b0;
			end else if (timekeeper_read_pending) begin
				cpu_rdata <= timekeeper_clock_dword ? timekeeper_clock_read :
					timekeeper_cpu_read_data;
				cpu_ack <= 1'b1;
				timekeeper_read_pending <= 1'b0;
			end else if (bus_pending) begin
				cpu_rdata <= 32'hffff_ffff;

				case (bus_target_q)
					TARGET_MAIN_RAM: begin
						bus_pending <= 1'b0;
						if (bus_we_q)
							cpu_ack <= 1'b1;
						else begin
							main_ram_read_pending <= 1'b1;
							main_ram_read_is_protection <= 1'b0;
						end
					end
					TARGET_VINT_P1: begin
						if (bus_we_q)
							vint_ack_strobe <= 1'b1;
						else
							cpu_rdata <= input_p1;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_TIME_P1: begin
						cpu_rdata <= input_p1;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_TIME_P2: begin
						cpu_rdata <= input_p2;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_TIME_SYSTEM: begin
						cpu_rdata <= input_p3;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_TIME_INTENSITY: begin
						if (bus_be_q[2])
							timekill_intensity <= bus_wdata_q[23:16];
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_P2: begin
						cpu_rdata <= input_p2;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_P3: begin
						cpu_rdata <= input_p3;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_P4: begin
						cpu_rdata <= input_p4;
						if (map_bloodstorm && bus_we_q)
							watchdog_strobe <= 1'b1;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_EXTRA: begin
						cpu_rdata <= input_extra;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_DIPS: begin
						cpu_rdata <= input_dips;
						// TG68K.C exposes the 32-bit 020 bus as two 16-bit cycles.
						// The custom sound bit lives in the high half, so toggle only
						// for addresses +0/+1; a MOVE.L must not toggle again at +2.
						if (!bus_we_q && (map_68000 || !bus_addr_q[1]))
							special_read_strobe <= 1'b1;
						if (bus_we_q)
							watchdog_strobe <= 1'b1;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_COLOR1: begin
						if (map_timekill && (bus_be_q[2] || bus_be_q[0])) begin
							color1_strobe <= 1'b1;
							color_data <= bus_addr_q[1] ? bus_wdata_q[7:0] :
								bus_wdata_q[23:16];
						end else if (map_bloodstorm && bus_be_q[2]) begin
							color1_strobe <= 1'b1;
							color_data <= bus_wdata_q[23:16];
						end else if (!map_68000 && bus_be_q[0]) begin
							// SFTM's 0x000000ff handler mask selects only byte +3.
							color1_strobe <= 1'b1;
							color_data <= bus_wdata_q[7:0];
						end
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_COLOR0: begin
						if (map_timekill && (bus_be_q[2] || bus_be_q[0])) begin
							color0_strobe <= 1'b1;
							color_data <= bus_addr_q[1] ? bus_wdata_q[7:0] :
								bus_wdata_q[23:16];
							plane_enable[0] <= ~(bus_addr_q[1] ?
								bus_wdata_q[5] : bus_wdata_q[21]);
							plane_enable[1] <= ~(bus_addr_q[1] ?
								bus_wdata_q[7] : bus_wdata_q[23]);
						end else if (map_bloodstorm && bus_be_q[2]) begin
							color0_strobe <= 1'b1;
							color_data <= bus_wdata_q[23:16];
						end else if (!map_68000 && bus_be_q[0]) begin
							color0_strobe <= 1'b1;
							color_data <= bus_wdata_q[7:0];
						end
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_WATCHDOG: begin
						watchdog_strobe <= 1'b1;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_SOUND_COMMAND: begin
						sound_command_valid <= map_timekill || bus_be_q[2];
						sound_command <= bus_addr_q[1] ?
							bus_wdata_q[7:0] : bus_wdata_q[23:16];
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_VIDEO: begin
						video_req <= 1'b1;
						if (video_ack) begin
							cpu_rdata <= bus_addr_q[1] ? {16'd0, video_rdata} : {video_rdata, 16'd0};
							cpu_ack <= 1'b1;
							bus_pending <= 1'b0;
						end
					end
					TARGET_OPEN_578: begin
						// MAME 0.288 leaves this SFTM window unpopulated and returns
						// zero. The game indexes around 0x580000 with a signed,
						// RAM-derived offset; negative offsets enter 0x578xxx and
						// branch on the returned low bits.
						// Keep the registered response schedule; only correct the data.
						cpu_rdata <= 32'h0000_0000;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_PALETTE: begin
						bus_pending <= 1'b0;
						if (bus_we_q)
							cpu_ack <= 1'b1;
						else
							palette_read_pending <= 1'b1;
					end
					TARGET_NVRAM: begin
						bus_pending <= 1'b0;
						if (bus_we_q)
							cpu_ack <= 1'b1;
						else
							nvram_read_pending <= 1'b1;
					end
					TARGET_TIMEKEEPER: begin
						bus_pending <= 1'b0;
						if (bus_we_q)
							cpu_ack <= 1'b1;
						else
							timekeeper_read_pending <= 1'b1;
					end
					TARGET_PROTECTION_READ, TARGET_PIC_RESULT: begin
						bus_pending <= 1'b0;
						main_ram_read_pending <= 1'b1;
						main_ram_read_is_protection <= 1'b1;
						main_ram_protection_word <= bus_target_q == TARGET_PIC_RESULT;
						main_ram_protection_lane <= profile.protection_address[1:0];
					end
					TARGET_TRACKBALL: begin
						// bloodstm: the low byte of 0x680000 (second ball 0x680040).
						// itech020: bytes 1 and 3 of 0x180800 (second 0x181000) or
						// of 0x200200; gt3dl packs both balls into 0x200000, and
						// gt3d returns 8-bit counters in its low word.
						if (map_68000)
							cpu_rdata <= {8'h00, bus_addr_q[6] ? trackball2_port :
								trackball1_port, 16'h0000};
						else if (profile.trackball_port == TRACKBALL_AT_200000)
							cpu_rdata <= {2{trackball2_port, trackball1_port}};
						else if (profile.trackball_port == TRACKBALL_WIDE)
							cpu_rdata <= {16'h0000, trackball1};
						else
							cpu_rdata <= {2{8'h00, bus_addr_q[12] ? trackball2_port :
								trackball1_port}};
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_PROTECTION_FIXED: begin
						cpu_rdata <= profile.protection_fixed_data;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_GUN_ACK: begin
						// 0x183000 (bits 16:2 = 0xc00) is level 6; the rest
						// of the windows level 5. Both read zero.
						if (bus_addr_q[16:2] == 15'h0c00)
							gun_ack6 <= 1'b1;
						else
							gun_ack5 <= 1'b1;
						cpu_rdata <= 32'h0000_0000;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_LIGHTGUN: begin
						cpu_rdata <= {8'h00, lightgun_byte, 16'h0000};
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_PROTECTION_RANGE: begin
						cpu_rdata <= 32'hffff_ffff;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_PLANE: begin
						if (map_bloodstorm) begin
							if (bus_be_q[2]) begin
								plane_enable[0] <= ~bus_wdata_q[17];
								plane_enable[1] <= ~bus_wdata_q[18];
							end
						end else begin
							plane_enable[0] <= ~bus_wdata_q[9];
							plane_enable[1] <= ~bus_wdata_q[10];
							grom_bank <= profile.grom_banked ? bus_wdata_q[15:14] : 2'b00;
						end
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_TIME_NOP: begin
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					TARGET_ROM: begin
						rom_req <= 1'b1;
						if (rom_ack) begin
							cpu_rdata <= rom_rdata;
							cpu_ack <= 1'b1;
							bus_pending <= 1'b0;
						end
					end
					TARGET_SFTM_UNMAPPED: begin
						// Same registered ACK cycle and ignored-write behavior as before.
						// Explicit mapped/protection targets retain their own responses.
						if (!bus_we_q)
							cpu_rdata <= 32'h0000_0000;
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
					default: begin
						cpu_ack <= 1'b1;
						bus_pending <= 1'b0;
					end
				endcase
			end
		end
	end

`ifndef SYNTHESIS
	// While the transfer owns the RAM read ports, no CPU access may be in
	// flight: its address would be replaced by the host's.
	always_ff @(posedge clk) begin
		if (nvram_host_owner_q) begin
			assert (bus_idle && !bus_accept)
				else $fatal(1, "CPU access in flight while NVRAM host owns RAM");
			assert (!main_ram_write_enable && !nvram_write_enable && !timekeeper_ram_write)
				else $fatal(1, "CPU RAM write while NVRAM host owns RAM");
		end
	end
`endif
endmodule
