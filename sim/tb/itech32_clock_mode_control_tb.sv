// SPDX-License-Identifier: GPL-2.0-or-later
`timescale 1ns/1ps

module itech32_clock_mode_control_tb;
	logic ref_clk = 1'b0;
	logic pll_ready = 1'b0;
	logic transport_locked = 1'b0;
	logic memory_quiesced = 1'b0;
	logic request_mame = 1'b0;
	logic select_mame;
	logic switch_reset;
	logic transport_reset;
	logic preserve_memory;

	always #10 ref_clk = ~ref_clk;

	itech32_clock_mode_control #(
		.HOLD_CYCLES(4), .SETTLE_CYCLES(4), .LOCK_CYCLES(4)
	) dut (.*);

	task automatic tick;
		@(posedge ref_clk); #1;
	endtask

	task automatic lock_transport;
		transport_locked = 1'b1;
		wait (!switch_reset); #1;
	endtask

	task automatic switch_to(input logic mame);
		request_mame = mame;
		wait (switch_reset); #1;
		assert (preserve_memory && !transport_reset);
		assert (select_mame != mame);

		// The source carrier must continue until DDR explicitly acknowledges
		// that all accepted transactions have drained.
		repeat (6) tick();
		assert (!transport_reset && select_mame != mame);
		memory_quiesced = 1'b1;
		wait (transport_reset); #1;
		transport_locked = 1'b0;
		wait (select_mame == mame); #1;
		assert (switch_reset && transport_reset && preserve_memory);
		wait (!transport_reset); #1;
		assert (switch_reset && preserve_memory);

		transport_locked = 1'b1;
		wait (!switch_reset); #1;
		assert (!transport_reset && !preserve_memory && select_mame == mame);
		memory_quiesced = 1'b0;
	endtask

	initial begin
		#20000;
		$fatal(1, "clock-mode timeout state=%0d request=%0b select=%0b lock=%0b quiesced=%0b",
			dut.state, request_mame, select_mame, transport_locked,
			memory_quiesced);
	end

	initial begin
		repeat (3) tick();
		assert (switch_reset && transport_reset && !preserve_memory && !select_mame);

		pll_ready = 1'b1;
		wait (!transport_reset); #1;
		assert (switch_reset && !preserve_memory && !select_mame);
		repeat (6) tick();
		assert (switch_reset);
		lock_transport();
		assert (!switch_reset && !transport_reset && !preserve_memory);

		switch_to(1'b1);
		switch_to(1'b0);

		// An unrequested lock loss must not retain persistent memory state.
		transport_locked = 1'b0;
		wait (switch_reset); #1;
		assert (transport_reset && !preserve_memory);
		lock_transport();
		assert (!switch_reset && !select_mame);

		pll_ready = 1'b0;
		wait (transport_reset); #1;
		assert (switch_reset && !preserve_memory && !select_mame);

		$display("PASS quiesced dual-PLL clock mode sequencing and memory retention");
		$finish;
	end
endmodule
