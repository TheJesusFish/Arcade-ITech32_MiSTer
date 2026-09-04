// SPDX-License-Identifier: GPL-3.0-or-later
//
// Rev-2 ITech32 sound-program ROM banking. The logical image follows MAME's
// 0x48000-byte soundcpu region layout used by Street Fighter: The Movie.

`timescale 1ns/1ps

module itech32_sound_rom_map (
	input  logic        clk,
	input  logic        reset,
	input  logic        rev1_mode,

	// cpu_commit is a single-cycle accepted/committed CPU bus transaction.
	// cpu_valid remains asserted while a memory read waits for DDR acknowledgement.
	input  logic        cpu_commit,
	input  logic        cpu_valid,
	input  logic [15:0] cpu_addr,
	input  logic        cpu_write,
	input  logic [7:0]  cpu_wdata,

	output logic [7:0]  sound_bank,
	output logic        sound_req,
	output logic [18:0] sound_addr,
	output logic        bank_valid
);

	always_ff @(posedge clk) begin
		if (reset) begin
			sound_bank <= 8'd0;
			bank_valid <= 1'b1;
		end else if (cpu_commit && cpu_write && (cpu_addr == 16'h0c00)) begin
			sound_bank <= cpu_wdata;
			bank_valid <= rev1_mode ? (cpu_wdata <= 8'd5) :
				(cpu_wdata <= 8'd13);
		end
	end

	// SFTM's 0x38000-byte banked body has fourteen 0x4000-byte banks.  Keep
	// validity beside the bank latch instead of placing the comparator in the
	// sound-bus ready/6809 clock-enable cone.

	always_comb begin
		sound_req = 1'b0;
		sound_addr = 19'd0;
		if (cpu_valid && !cpu_write && cpu_addr[15]) begin
			// Fixed CPU $8000-$ffff comes from logical $08000-$0ffff.
			sound_req = 1'b1;
			sound_addr = {3'b000, cpu_addr};
		end else if (cpu_valid && !cpu_write &&
		             (cpu_addr[15:14] == 2'b01) && bank_valid) begin
			// Banked CPU $4000-$7fff comes from logical
			// $10000 + bank*$4000 + offset.
			sound_req = 1'b1;
			sound_addr = 19'h10000
			           + {1'b0, sound_bank[3:0], 14'd0}
			           + {5'd0, cpu_addr[13:0]};
		end
	end

endmodule
