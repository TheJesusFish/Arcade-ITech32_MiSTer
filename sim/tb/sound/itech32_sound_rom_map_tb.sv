// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module itech32_sound_rom_map_tb;

	logic clk = 1'b0;
	logic reset = 1'b1;
	logic rev1_mode = 1'b0;
	logic cpu_commit = 1'b0;
	logic cpu_valid = 1'b0;
	logic [15:0] cpu_addr = 16'd0;
	logic cpu_write = 1'b0;
	logic [7:0] cpu_wdata = 8'd0;
	logic [7:0] sound_bank;
	logic sound_req;
	logic [18:0] sound_addr;
	logic bank_valid;

	always #5 clk = ~clk;

	itech32_sound_rom_map dut (
		.clk        (clk),
		.reset      (reset),
		.rev1_mode  (rev1_mode),
		.cpu_commit (cpu_commit),
		.cpu_valid  (cpu_valid),
		.cpu_addr   (cpu_addr),
		.cpu_write  (cpu_write),
		.cpu_wdata  (cpu_wdata),
		.sound_bank (sound_bank),
		.sound_req  (sound_req),
		.sound_addr (sound_addr),
		.bank_valid (bank_valid)
	);

	task automatic set_bank(input logic [7:0] bank);
		begin
			@(negedge clk);
			cpu_addr = 16'h0c00;
			cpu_write = 1'b1;
			cpu_wdata = bank;
			cpu_commit = 1'b1;
			@(posedge clk);
			#1;
			@(negedge clk);
			cpu_commit = 1'b0;
			cpu_write = 1'b0;
		end
	endtask

	task automatic expect_map(
		input logic [15:0] address,
		input logic expected_cs,
		input logic [18:0] expected_address,
		input string description
	);
		begin
			cpu_addr = address;
			cpu_valid = 1'b1;
			cpu_write = 1'b0;
			#1;
			if (sound_req !== expected_cs ||
			    (expected_cs && sound_addr !== expected_address))
				$fatal(1, "%s: cs=%0d/%0d addr=%05x/%05x",
				       description, sound_req, expected_cs, sound_addr, expected_address);
		end
	endtask

	initial begin
		repeat (3) @(posedge clk);
		@(negedge clk);
		reset = 1'b0;
		#1;

		if (sound_bank != 0 || !bank_valid)
			$fatal(1, "sound bank reset state mismatch");
		cpu_addr = 16'h8000;
		cpu_valid = 1'b0;
		#1;
		if (sound_req)
			$fatal(1, "idle CPU incorrectly requested sound ROM");
		expect_map(16'h0000, 1'b0, 19'd0, "I/O is not ROM");
		expect_map(16'h3fff, 1'b0, 19'd0, "RAM boundary is not ROM");
		expect_map(16'h4000, 1'b1, 19'h10000, "bank 0 base");
		expect_map(16'h7fff, 1'b1, 19'h13fff, "bank 0 end");
		expect_map(16'h8000, 1'b1, 19'h08000, "fixed base");
		expect_map(16'hffff, 1'b1, 19'h0ffff, "fixed end");

		set_bank(8'd13);
		if (sound_bank != 13 || !bank_valid)
			$fatal(1, "bank 13 did not latch");
		expect_map(16'h4000, 1'b1, 19'h44000, "last SFTM bank base");
		expect_map(16'h7fff, 1'b1, 19'h47fff, "last SFTM image byte");
		expect_map(16'h8000, 1'b1, 19'h08000, "fixed window ignores bank");

		// A non-committed write must not repeat or alter the bank latch.
		cpu_addr = 16'h0c00;
		cpu_write = 1'b1;
		cpu_wdata = 8'd4;
		#1;
		if (sound_bank != 13)
			$fatal(1, "uncommitted bank write changed state");

		set_bank(8'd14);
		if (bank_valid)
			$fatal(1, "bank 14 should be outside the SFTM sound image");
		expect_map(16'h4000, 1'b0, 19'd0, "invalid bank is not requested");
		expect_map(16'h8000, 1'b1, 19'h08000, "fixed ROM survives invalid bank");

		set_bank(8'd6);
		expect_map(16'h4000, 1'b1, 19'h28000, "restored bank 6 base");

		// Rev-1 has a 0x28000-byte program image: fixed 0x08000..0x0ffff
		// plus six banked 0x4000-byte pages at 0x10000..0x27fff.
		@(negedge clk); reset = 1'b1; rev1_mode = 1'b1;
		repeat (2) @(posedge clk);
		@(negedge clk); reset = 1'b0;
		set_bank(8'd5);
		if (!bank_valid) $fatal(1, "Rev-1 bank 5 rejected");
		expect_map(16'h4000, 1'b1, 19'h24000, "Rev-1 last bank base");
		expect_map(16'h7fff, 1'b1, 19'h27fff, "Rev-1 image end");
		set_bank(8'd6);
		if (bank_valid) $fatal(1, "Rev-1 bank 6 should be invalid");
		expect_map(16'h4000, 1'b0, 19'd0, "Rev-1 invalid bank");
		expect_map(16'h8000, 1'b1, 19'h08000, "Rev-1 fixed window");

		cpu_addr = 16'h4000;
		cpu_valid = 1'b1;
		cpu_write = 1'b1;
		#1;
		if (sound_req)
			$fatal(1, "CPU write incorrectly selected sound ROM");

		$display("PASS: SFTM Rev-2 and Time Killers Rev-1 sound ROM maps");
		$finish;
	end

endmodule
