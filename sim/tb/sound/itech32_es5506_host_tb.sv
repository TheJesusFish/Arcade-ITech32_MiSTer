// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module itech32_es5506_host_tb;

	logic clk = 1'b0;
	logic reset = 1'b1;
	logic ce_16m = 1'b0;
	logic host_req = 1'b0;
	logic host_write = 1'b0;
	logic [5:0] host_addr = 6'd0;
	logic [7:0] host_wdata = 8'd0;
	logic [7:0] host_rdata;
	logic host_ack;
	logic sample_req;
	logic [1:0] sample_bank;
	logic [21:0] sample_addr;
	logic sample_companded;
	logic [4:0] sample_voice;
	logic [15:0] sample_rdata = 16'd0;
	logic sample_ack = 1'b0;
	logic signed [19:0] audio_left;
	logic signed [19:0] audio_right;
	logic audio_strobe;
	logic irq;
	logic [7:0] irq_vector;
	logic [6:0] current_page;
	logic [4:0] active_voices;
	logic [4:0] scan_voice;
	logic engine_busy;
	always #5 clk = ~clk;

	itech32_es5506 dut (
		.clk              (clk),
		.reset            (reset),
		.ce_16m           (ce_16m),
		.host_req         (host_req),
		.host_write       (host_write),
		.host_addr        (host_addr),
		.host_wdata       (host_wdata),
		.host_rdata       (host_rdata),
		.host_ack         (host_ack),
		.par_comparator_tripped (1'b0),
		.par_discharge    (),
		.sample_req       (sample_req),
		.sample_bank      (sample_bank),
		.sample_addr      (sample_addr),
		.sample_companded (sample_companded),
		.sample_voice     (sample_voice),
		.sample_rdata     (sample_rdata),
		.sample_ack       (sample_ack),
		.audio_left       (audio_left),
		.audio_right      (audio_right),
		.audio_strobe     (audio_strobe),
		.irq              (irq),
		.irq_vector       (irq_vector),
		.current_page     (current_page),
		.active_voices    (active_voices),
		.scan_voice       (scan_voice),
		.engine_busy      (engine_busy)
	);

	task automatic host_transfer(
		input  logic       write_cycle,
		input  logic [5:0] address,
		input  logic [7:0] write_data,
		output logic [7:0] read_data
	);
		integer timeout;
		begin
			@(negedge clk);
			host_req = 1'b1;
			host_write = write_cycle;
			host_addr = address;
			host_wdata = write_data;
			begin : wait_ack
				for (timeout = 0; timeout < 100; timeout = timeout + 1) begin
					@(posedge clk);
					#1;
					if (host_ack)
						disable wait_ack;
				end
				$fatal(1, "host transaction timed out at %02x", address);
			end
			read_data = host_rdata;
			@(negedge clk);
			host_req = 1'b0;
			host_write = 1'b0;
			@(posedge clk);
			#1;
		end
	endtask

	task automatic write_byte(input logic [5:0] address, input logic [7:0] data);
		logic [7:0] ignored;
		begin
			host_transfer(1'b1, address, data, ignored);
		end
	endtask

	task automatic read_byte(input logic [5:0] address, output logic [7:0] data);
		begin
			host_transfer(1'b0, address, 8'd0, data);
		end
	endtask

	task automatic write_reg(input logic [3:0] slot, input logic [31:0] data);
		begin
			write_byte({slot, 2'd0}, data[31:24]);
			write_byte({slot, 2'd1}, data[23:16]);
			write_byte({slot, 2'd2}, data[15:8]);
			write_byte({slot, 2'd3}, data[7:0]);
		end
	endtask

	task automatic read_reg(input logic [3:0] slot, output logic [31:0] data);
		logic [7:0] b0;
		logic [7:0] b1;
		logic [7:0] b2;
		logic [7:0] b3;
		begin
			read_byte({slot, 2'd0}, b0);
			read_byte({slot, 2'd1}, b1);
			read_byte({slot, 2'd2}, b2);
			read_byte({slot, 2'd3}, b3);
			data = {b0, b1, b2, b3};
		end
	endtask

	task automatic set_page(input logic [6:0] page);
		begin
			write_reg(4'hf, {25'd0, page});
			if (current_page != page)
				$fatal(1, "PAGE write failed: expected %02x got %02x", page, current_page);
		end
	endtask

	task automatic expect_reg(
		input logic [3:0] slot,
		input logic [31:0] expected,
		input string description
	);
		logic [31:0] actual;
		begin
			read_reg(slot, actual);
			if (actual !== expected)
				$fatal(1, "%s: expected %08x got %08x", description,
				       expected, actual);
		end
	endtask

	initial begin : watchdog
		repeat (20000) @(posedge clk);
		$fatal(1, "ES5506 host regression watchdog expired");
	end

	initial begin : test
		logic [7:0] byte_value;
		logic [7:0] snap1;
		logic [7:0] snap2;
		logic [7:0] snap3;

		repeat (4) @(posedge clk);
		@(negedge clk);
		reset = 1'b0;
		@(posedge clk);

		if (current_page != 0 || active_voices != 5'h1f || irq_vector != 8'h80)
			$fatal(1, "bad ES5506 reset state");
		expect_reg(4'h0, 32'h00000003, "reset CR");
		expect_reg(4'h2, 32'h00008000, "reset LVOL");
		expect_reg(4'h4, 32'h00008000, "reset RVOL");
		expect_reg(4'hc, 32'h00000017, "reset MODE");

		// MAME commits the four-byte write latch only on the final byte.
		write_byte(6'h00, 8'h12);
		write_byte(6'h01, 8'h34);
		write_byte(6'h02, 8'h56);
		expect_reg(4'h0, 32'h00000003, "CR before final write byte");
		write_byte(6'h03, 8'h78);
		expect_reg(4'h0, 32'h00005678, "CR after atomic commit");

		// Lane zero snapshots all 32 bits. Later lanes must remain from that
		// snapshot even if the underlying register changes in between.
		read_byte(6'h00, byte_value);
		if (byte_value != 8'h00)
			$fatal(1, "CR snapshot high byte mismatch");
		write_reg(4'h0, 32'h0000abcd);
		read_byte(6'h01, snap1);
		read_byte(6'h02, snap2);
		read_byte(6'h03, snap3);
		if ({byte_value, snap1, snap2, snap3} != 32'h00005678)
			$fatal(1, "read latch changed after lane-zero snapshot");

		// Voice pages are isolated and masks match MAME's ES5506 register map.
		set_page(7'h05);
		write_reg(4'h1, 32'hdeadbeef);
		write_reg(4'h2, 32'h00001234);
		write_reg(4'h3, 32'h0000ab00);
		write_reg(4'h8, 32'h0000fe01);
		expect_reg(4'h1, 32'h0001beef, "17-bit FC mask");
		expect_reg(4'h2, 32'h00001234, "LVOL round trip");
		expect_reg(4'h3, 32'h0000ab00, "LVRAMP round trip");
		expect_reg(4'h8, 32'h0000fe01, "signed slow K2 ramp round trip");

		set_page(7'h06);
		expect_reg(4'h1, 32'h00000000, "voice page isolation");
		set_page(7'h25);
		write_reg(4'h1, 32'h12345678);
		write_reg(4'h2, 32'h12345678);
		write_reg(4'h3, 32'h89abcdef);
		write_reg(4'h4, 32'h0003ffff);
		expect_reg(4'h1, 32'h12345000, "START mask");
		expect_reg(4'h2, 32'h12345600, "END mask");
		expect_reg(4'h3, 32'h89abcdef, "ACCUM round trip");
		expect_reg(4'h4, 32'h0003ffff, "18-bit signed filter state");

		// PAR/IRQV/PAGE are visible through every page, including test pages.
		expect_reg(4'hd, 32'h000003ff, "high-page PAR");
		set_page(7'h55);
		expect_reg(4'hd, 32'h000003ff, "test-page PAR");
		expect_reg(4'he, 32'h00000080, "test-page IRQV");
		expect_reg(4'hf, 32'h00000055, "test-page PAGE");

		if (sample_req || audio_strobe || engine_busy || irq)
			$fatal(1, "inactive host test unexpectedly ran audio engine");

		$display("PASS: ES5506 host pages, atomic byte latches, masks, and readback");
		$finish;
	end

endmodule
