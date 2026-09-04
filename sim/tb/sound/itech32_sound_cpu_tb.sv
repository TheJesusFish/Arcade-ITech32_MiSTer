// SPDX-License-Identifier: GPL-3.0-or-later

`timescale 1ns/1ps

module itech32_sound_cpu_tb;

	logic         clk = 1'b0;
	logic         reset = 1'b1;
	logic         ce_8m = 1'b1;
	logic         mem_valid;
	logic [15:0]  mem_addr;
	logic         mem_write;
	logic [7:0]   mem_wdata;
	logic [7:0]   mem_rdata;
	logic         mem_ready = 1'b1;
	logic         irq = 1'b0;
	logic         firq = 1'b0;
	logic         nmi = 1'b0;
	logic         ce_e;
	logic         ce_q;
	logic         ce_cpu_2m;
	logic [1:0]   phase;
	logic         opcode_fetch;
	logic         bus_status;
	logic         bus_available;
	logic         cpu_busy;
	logic         last_instruction_cycle;
	logic [111:0] debug_regs;

	logic [7:0] memory [0:65535];
	integer       reset_vector_order = 0;
	integer       stack_write_count = 0;

	// Motorola documents the table in BA,BS order. SYNC acknowledge is 1,0.
	wire sync_ack = bus_available && !bus_status;

	always #5 clk = ~clk;
	assign mem_rdata = memory[mem_addr];

	itech32_sound_cpu dut (
		.clk                    (clk),
		.reset                  (reset),
		.ce_8m                  (ce_8m),
		.mem_valid              (mem_valid),
		.mem_addr               (mem_addr),
		.mem_write              (mem_write),
		.mem_wdata              (mem_wdata),
		.mem_rdata              (mem_rdata),
		.mem_ready              (mem_ready),
		.irq                    (irq),
		.firq                   (firq),
		.nmi                    (nmi),
		.ce_e                   (ce_e),
		.ce_q                   (ce_q),
		.ce_cpu_2m              (ce_cpu_2m),
		.phase                  (phase),
		.opcode_fetch           (opcode_fetch),
		.bus_status             (bus_status),
		.bus_available          (bus_available),
		.cpu_busy               (cpu_busy),
		.last_instruction_cycle (last_instruction_cycle),
		.debug_regs             (debug_regs)
	);

	// Zero-latency byte RAM/ROM model. Writes commit on Q, matching the
	// mc6809i/JTFRAME bus convention; read data remains combinational for E.
	always @(posedge clk) begin
		if (!reset && ce_q && mem_valid && mem_ready) begin
			if (mem_write) begin
				memory[mem_addr] <= mem_wdata;
				if (mem_addr >= 16'h7e00 && mem_addr < 16'h7f00)
					stack_write_count <= stack_write_count + 1;
			end else begin
				if (mem_addr == 16'hfffe && reset_vector_order == 0)
					reset_vector_order <= 1;
				if (mem_addr == 16'hffff && reset_vector_order == 1)
					reset_vector_order <= 2;
			end
		end
	end

	task automatic wait_for_byte(
		input logic [15:0] address,
		input logic [7:0] expected,
		input string       description
	);
		integer cycles;
		begin : wait_loop
			for (cycles = 0; cycles < 20000; cycles = cycles + 1) begin
				@(posedge clk);
				#1;
				if (memory[address] == expected)
					disable wait_loop;
			end
			$fatal(1, "timeout waiting for %s at %04x (got %02x, PC=%04x S=%04x CC=%02x bus=%04x RnW=%0d BA=%0d BS=%0d)",
			       description, address, memory[address], debug_regs[111:96],
			       debug_regs[63:48], debug_regs[87:80], mem_addr, !mem_write,
			       bus_available, bus_status);
		end
	endtask

	task automatic wait_for_sync(input string description);
		integer cycles;
		begin : wait_loop
			for (cycles = 0; cycles < 20000; cycles = cycles + 1) begin
				@(posedge clk);
				#1;
				if (sync_ack)
					disable wait_loop;
			end
			$fatal(1, "timeout waiting for %s SYNC acknowledgement", description);
		end
	endtask

	initial begin : watchdog
		repeat (150000) @(posedge clk);
		$fatal(1, "sound CPU regression watchdog expired at address %04x", mem_addr);
	end

	initial begin : test
		integer i;
		logic [15:0] held_addr;
		logic        held_write;
		logic [7:0]  held_wdata;
		logic [1:0]  held_phase;
		logic [111:0] held_regs;

		// NOP-fill all unprogrammed space so accidental fall-through is benign.
		for (i = 0; i < 65536; i = i + 1)
			memory[i] = 8'h12;

		// Synthetic sound program at $8000.
		//   LDS #$7f00; unmask IRQ/FIRQ; prove direct/extended reads and writes;
		//   then enter three SYNC points for IRQ, FIRQ, and NMI respectively.
		memory[16'h8000] = 8'h10; memory[16'h8001] = 8'hce;
		memory[16'h8002] = 8'h7f; memory[16'h8003] = 8'h00;
		memory[16'h8004] = 8'h1c; memory[16'h8005] = 8'haf;
		memory[16'h8006] = 8'h86; memory[16'h8007] = 8'h12;
		memory[16'h8008] = 8'h97; memory[16'h8009] = 8'h10;
		memory[16'h800a] = 8'hd6; memory[16'h800b] = 8'h20;
		memory[16'h800c] = 8'hd7; memory[16'h800d] = 8'h11;
		memory[16'h800e] = 8'hb6; memory[16'h800f] = 8'h12;
		memory[16'h8010] = 8'h34;
		memory[16'h8011] = 8'hb7; memory[16'h8012] = 8'h20;
		memory[16'h8013] = 8'h00;
		memory[16'h8014] = 8'h13;
		memory[16'h8015] = 8'h86; memory[16'h8016] = 8'h11;
		memory[16'h8017] = 8'hb7; memory[16'h8018] = 8'h20;
		memory[16'h8019] = 8'h10;
		memory[16'h801a] = 8'h13;
		memory[16'h801b] = 8'h86; memory[16'h801c] = 8'h22;
		memory[16'h801d] = 8'hb7; memory[16'h801e] = 8'h20;
		memory[16'h801f] = 8'h11;
		memory[16'h8020] = 8'h13;
		memory[16'h8021] = 8'h86; memory[16'h8022] = 8'h77;
		memory[16'h8023] = 8'hb7; memory[16'h8024] = 8'h20;
		memory[16'h8025] = 8'h04;
		memory[16'h8026] = 8'h20; memory[16'h8027] = 8'hfe;

		// Interrupt handlers: write a unique marker, then RTI.
		memory[16'h8100] = 8'h86; memory[16'h8101] = 8'h49;
		memory[16'h8102] = 8'hb7; memory[16'h8103] = 8'h20;
		memory[16'h8104] = 8'h01; memory[16'h8105] = 8'h3b;

		memory[16'h8120] = 8'h86; memory[16'h8121] = 8'h46;
		memory[16'h8122] = 8'hb7; memory[16'h8123] = 8'h20;
		memory[16'h8124] = 8'h02; memory[16'h8125] = 8'h3b;

		memory[16'h8140] = 8'h86; memory[16'h8141] = 8'h4e;
		memory[16'h8142] = 8'hb7; memory[16'h8143] = 8'h20;
		memory[16'h8144] = 8'h03; memory[16'h8145] = 8'h3b;

		// Big-endian 6809 vectors.
		memory[16'hfff6] = 8'h81; memory[16'hfff7] = 8'h20; // FIRQ
		memory[16'hfff8] = 8'h81; memory[16'hfff9] = 8'h00; // IRQ
		memory[16'hfffc] = 8'h81; memory[16'hfffd] = 8'h40; // NMI
		memory[16'hfffe] = 8'h80; memory[16'hffff] = 8'h00; // RESET

		memory[16'h0020] = 8'h34;
		memory[16'h1234] = 8'h5a;

		repeat (4) @(posedge clk);
		@(negedge clk);
		reset = 1'b0;

		// Force a multi-cycle wait on the extended read. An inactive phase may
		// advance to the next E/Q boundary, but neither active edge nor CPU
		// architectural state/request may advance before ready returns.
		wait (mem_valid && !mem_write && mem_addr == 16'h1234);
		@(negedge clk);
		mem_ready = 1'b0;
		held_addr = mem_addr;
		held_write = mem_write;
		held_wdata = mem_wdata;
		held_phase = phase;
		held_regs = debug_regs;
		repeat (9) begin
			@(posedge clk);
			if (ce_e || ce_q)
				$fatal(1, "E/Q consumed unready memory");
			#1;
			if (ce_e || ce_q)
				$fatal(1, "E/Q advanced during memory wait");
			if (mem_addr != held_addr || mem_write != held_write ||
			    mem_wdata != held_wdata || debug_regs != held_regs)
				$fatal(1, "memory request changed while stalled");
			if (phase != (held_phase[0] ? held_phase + 2'd1 : held_phase))
				$fatal(1, "phase advanced past the next active boundary while stalled");
		end
		@(negedge clk);
		mem_ready = 1'b1;

		wait_for_byte(16'h0010, 8'h12, "direct write");
		wait_for_byte(16'h0011, 8'h34, "direct read/write round trip");
		wait_for_byte(16'h2000, 8'h5a, "stalled extended read/write round trip");
		wait_for_sync("IRQ");

		@(negedge clk);
		irq = 1'b1;
		wait_for_byte(16'h2001, 8'h49, "IRQ handler");
		@(negedge clk);
		irq = 1'b0;
		wait_for_byte(16'h2010, 8'h11, "IRQ RTI return");
		wait_for_sync("FIRQ");

		@(negedge clk);
		firq = 1'b1;
		wait_for_byte(16'h2002, 8'h46, "FIRQ handler");
		@(negedge clk);
		firq = 1'b0;
		wait_for_byte(16'h2011, 8'h22, "FIRQ RTI return");
		wait_for_sync("NMI");

		@(negedge clk);
		nmi = 1'b1;
		wait_for_byte(16'h2003, 8'h4e, "NMI handler");
		@(negedge clk);
		nmi = 1'b0;
		wait_for_byte(16'h2004, 8'h77, "NMI RTI return and completion");

		if (reset_vector_order != 2)
			$fatal(1, "reset vector fetch order was not FFFE then FFFF");
		if (stack_write_count < 14)
			$fatal(1, "interrupt stack traffic was not observed (%0d writes)",
			       stack_write_count);
		if (memory[16'h0010] != 8'h12 || memory[16'h0011] != 8'h34 ||
		    memory[16'h2000] != 8'h5a || memory[16'h2001] != 8'h49 ||
		    memory[16'h2002] != 8'h46 || memory[16'h2003] != 8'h4e ||
		    memory[16'h2004] != 8'h77)
			$fatal(1, "final sound CPU memory signature mismatch");

		$display("PASS: mc6809i reset, vector, wait, R/W, IRQ, FIRQ, and NMI regression");
		$display("      interrupt stack writes observed: %0d", stack_write_count);
		$finish;
	end

endmodule
