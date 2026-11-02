// SPDX-License-Identifier: GPL-3.0-or-later
// Test helpers: build a board profile from a bench's timekill/bloodstorm mode
// bits, as the production selector would from the matching MRA selector byte.
`timescale 1ns/1ps

package itech32_profile_tb_pkg;
	import itech32_profile_pkg::*;

	function automatic board_profile_t mode_profile(input logic timekill,
		input logic bloodstorm);
		mode_profile = profile_for_selector(timekill ? SELECT_TIMEKILL :
			bloodstorm ? SELECT_BLOODSTORM : SELECT_SFTM);
	endfunction

	// Benches that exercise a specific protection read address.
	function automatic board_profile_t mode_profile_protection(input logic timekill,
		input logic bloodstorm, input logic [14:0] protection_address);
		board_profile_t profile;
		begin
			profile = mode_profile(timekill, bloodstorm);
			profile.protection_address = protection_address;
			mode_profile_protection = profile;
		end
	endfunction
endpackage
