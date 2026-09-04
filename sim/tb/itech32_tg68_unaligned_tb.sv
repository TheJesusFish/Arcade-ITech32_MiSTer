`timescale 1ns/1ps

// Authored 68EC020 program exercising the odd-addressed longword read used by
// SFTM v1.10's palette loader.  This bench intentionally instantiates the real
// VHDL TG68K.C through ModelSim; it contains no game ROM bytes.
module itech32_tg68_unaligned_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic cpu_ce = 1'b1;
	logic vector_load_we = 1'b0;
	logic [4:0] vector_load_addr = 5'd0;
	logic [31:0] vector_load_wdata = 32'd0;
	logic [3:0] vector_load_be = 4'd0;
	logic board_req;
	logic board_we;
	logic [23:0] board_addr;
	logic [31:0] board_wdata;
	logic [3:0] board_be;
	logic board_ack;
	logic [31:0] board_rdata;
	logic [31:0] debug_addr;
	logic [1:0] debug_busstate;
	logic debug_nwr;
	logic debug_nuds;
	logic debug_nlds;
	logic [2:0] debug_fc;

	logic [7:0] memory [0:16'h07ff];
	integer cycles = 0;
	integer reads = 0;
	integer writes = 0;
	integer odd_reads = 0;
	integer lane;

	always #5 clk = ~clk;

	assign board_ack = board_req;
	always_comb begin
		board_rdata = {
			memory[{board_addr[15:2], 2'b00}],
			memory[{board_addr[15:2], 2'b01}],
			memory[{board_addr[15:2], 2'b10}],
			memory[{board_addr[15:2], 2'b11}]
		};
	end

	always @(posedge clk) begin
		cycles <= cycles + 1;
		if (board_req && board_ack) begin
			$display("TG68_BUS %s addr=%06x be=%x wdata=%08x rdata=%08x",
				board_we ? "W" : "R", board_addr, board_be, board_wdata, board_rdata);
			if (board_we) begin
				writes <= writes + 1;
				for (lane = 0; lane < 4; lane = lane + 1)
					if (board_be[lane])
						memory[{board_addr[15:2], (2'd3 - lane[1:0])}] <=
							board_wdata[lane*8 +: 8];
			end else begin
				reads <= reads + 1;
				if (board_addr[0]) odd_reads <= odd_reads + 1;
			end
		end

		if (cycles > 20000)
			$fatal(1, "TG68 unaligned program timed out pc=%08x bus=%02b", debug_addr, debug_busstate);
	end

	itech32_tg68_cpu dut (
		.clk(clk), .reset(reset), .cpu_68000(1'b0), .cpu_ce(cpu_ce),
		.irq_level(3'd0),
		.vector_load_we(vector_load_we), .vector_load_addr(vector_load_addr),
		.vector_load_wdata(vector_load_wdata), .vector_load_be(vector_load_be),
		.board_req(board_req), .board_we(board_we), .board_addr(board_addr),
		.board_wdata(board_wdata), .board_be(board_be), .board_ack(board_ack),
		.board_rdata(board_rdata), .debug_addr(debug_addr),
		.debug_busstate(debug_busstate), .debug_nwr(debug_nwr),
		.debug_nuds(debug_nuds), .debug_nlds(debug_nlds), .debug_fc(debug_fc)
	);

	task automatic load_vector(input logic [4:0] index, input logic [31:0] value);
		begin
			@(negedge clk);
			vector_load_addr = index;
			vector_load_wdata = value;
			vector_load_be = 4'hf;
			vector_load_we = 1'b1;
			@(negedge clk);
			vector_load_we = 1'b0;
		end
	endtask

	initial begin
		for (integer i = 0; i < 16'h0800; i = i + 1)
			memory[i] = 8'h00;

		// 00000100: movea.l #$00000300,A0
		memory[16'h0100] = 8'h20; memory[16'h0101] = 8'h7c;
		memory[16'h0102] = 8'h00; memory[16'h0103] = 8'h00;
		memory[16'h0104] = 8'h03; memory[16'h0105] = 8'h00;
		// 00000106: move.l (-$1,A0),D0 -- reads 0x02ff..0x0302.
		memory[16'h0106] = 8'h20; memory[16'h0107] = 8'h28;
		memory[16'h0108] = 8'hff; memory[16'h0109] = 8'hff;
		// 0000010a: move.l D0,$00000400.l
		memory[16'h010a] = 8'h23; memory[16'h010b] = 8'hc0;
		memory[16'h010c] = 8'h00; memory[16'h010d] = 8'h00;
		memory[16'h010e] = 8'h04; memory[16'h010f] = 8'h00;
		// 00000110: bra.s 00000110
		memory[16'h0110] = 8'h60; memory[16'h0111] = 8'hfe;

		memory[16'h02ff] = 8'h11;
		memory[16'h0300] = 8'h22;
		memory[16'h0301] = 8'h33;
		memory[16'h0302] = 8'h44;

		load_vector(5'd0, 32'h0000_0800);
		load_vector(5'd1, 32'h0000_0100);
		repeat (3) @(negedge clk);
		reset = 1'b0;

		wait (memory[16'h0400] != 8'h00 || cycles > 19000);
		repeat (20) @(posedge clk);
		if ({memory[16'h0400], memory[16'h0401], memory[16'h0402], memory[16'h0403]} !== 32'h1122_3344)
			$fatal(1, "TG68 odd longword mismatch got=%02x%02x%02x%02x reads=%0d odd=%0d writes=%0d pc=%08x",
				memory[16'h0400], memory[16'h0401], memory[16'h0402], memory[16'h0403],
				reads, odd_reads, writes, debug_addr);
		if (odd_reads == 0)
			$fatal(1, "TG68 test did not emit an odd-addressed read");
		$display("TG68_UNALIGNED_PASS value=%02x%02x%02x%02x reads=%0d odd_reads=%0d writes=%0d cycles=%0d",
			memory[16'h0400], memory[16'h0401], memory[16'h0402], memory[16'h0403],
			reads, odd_reads, writes, cycles);
		$finish;
	end
endmodule
