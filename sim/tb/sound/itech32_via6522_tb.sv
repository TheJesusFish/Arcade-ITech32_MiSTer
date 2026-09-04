// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps

module itech32_via6522_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic ce_2m = 1'b0;
	logic read_commit = 1'b0;
	logic write_commit = 1'b0;
	logic [3:0] addr = 4'd0;
	logic [7:0] wdata = 8'd0;
	logic [7:0] rdata;
	logic irq;

	always #5 clk = ~clk;

	itech32_via6522 dut (
		.clk(clk), .reset(reset), .ce_2m(ce_2m),
		.read_commit(read_commit), .write_commit(write_commit),
		.addr(addr), .wdata(wdata), .rdata(rdata), .irq(irq)
	);

	task automatic via_write(input logic [3:0] reg_addr,
		input logic [7:0] value);
		begin
			@(negedge clk); addr=reg_addr; wdata=value; write_commit=1'b1;
			@(posedge clk); #1;
			@(negedge clk); write_commit=1'b0;
		end
	endtask

	task automatic via_read(input logic [3:0] reg_addr,
		output logic [7:0] value);
		begin
			@(negedge clk); addr=reg_addr; read_commit=1'b1;
			#1 value=rdata;
			@(posedge clk); #1;
			@(negedge clk); read_commit=1'b0;
		end
	endtask

	task automatic timer_ticks(input integer count);
		begin
			repeat (count) begin
				@(negedge clk); ce_2m=1'b1;
				@(posedge clk); #1;
				@(negedge clk); ce_2m=1'b0;
			end
		end
	endtask

	logic [7:0] got;
	initial begin
		repeat (3) @(posedge clk);
		@(negedge clk); reset=1'b0;

		via_read(4'he, got);
		if (got !== 8'h80 || irq) $fatal(1, "VIA reset IER/IRQ %02x/%b", got, irq);
		via_write(4'h2, 8'ha5);
		via_write(4'h3, 8'h5a);
		via_write(4'h0, 8'hc3);
		via_write(4'hf, 8'h3c);
		via_read(4'h2, got); if (got !== 8'ha5) $fatal(1, "VIA DDRB %02x", got);
		via_read(4'h3, got); if (got !== 8'h5a) $fatal(1, "VIA DDRA %02x", got);
		via_read(4'h0, got); if (got !== 8'hc3) $fatal(1, "VIA ORB %02x", got);
		via_read(4'h1, got); if (got !== 8'h3c) $fatal(1, "VIA ORA %02x", got);

		// Enable Timer 1, load three, and prove the one-shot interrupt edge and
		// the architectural low-counter-read clear behavior.
		via_write(4'he, 8'hc0);
		via_write(4'h4, 8'h03);
		via_write(4'h5, 8'h00);
		timer_ticks(3);
		if (irq) $fatal(1, "VIA Timer 1 fired before zero underflow");
		timer_ticks(1);
		via_read(4'hd, got);
		if (!irq || got[7:6] !== 2'b11)
			$fatal(1, "VIA Timer 1 IFR/IRQ %02x/%b", got, irq);
		via_read(4'h4, got);
		if (irq) $fatal(1, "VIA Timer 1 low read did not clear IRQ");

		// Continuous Timer 1 must reload and assert again after software clears.
		via_write(4'hb, 8'h40);
		via_write(4'h4, 8'h01);
		via_write(4'h5, 8'h00);
		timer_ticks(2);
		if (!irq) $fatal(1, "VIA continuous Timer 1 did not fire");
		via_write(4'hd, 8'h40);
		if (irq) $fatal(1, "VIA IFR W1C failed");
		timer_ticks(2);
		if (!irq) $fatal(1, "VIA continuous Timer 1 did not reload");
		via_read(4'h4, got);

		// Timer 2 is a one-shot timed interrupt when ACR[5] is clear.
		via_write(4'he, 8'ha0);
		via_write(4'h8, 8'h00);
		via_write(4'h9, 8'h00);
		timer_ticks(1);
		via_read(4'hd, got);
		if (!irq || !got[5]) $fatal(1, "VIA Timer 2 IFR/IRQ %02x/%b", got, irq);
		via_read(4'h8, got);
		if (irq) $fatal(1, "VIA Timer 2 low read did not clear IRQ");

		via_write(4'he, 8'h60);
		via_read(4'he, got);
		if (got !== 8'h80) $fatal(1, "VIA IER clear semantics %02x", got);

		$display("PASS Time Killers Rev-1 VIA ports, timers, IFR/IER, and FIRQ source");
		$finish;
	end
endmodule
