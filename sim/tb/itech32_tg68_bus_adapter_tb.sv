`timescale 1ns/1ps

module itech32_tg68_bus_adapter_tb;
	logic clk = 1'b0;
	logic reset = 1'b1;
	logic [1:0] ce_div = 2'd0;
	logic cpu_ce;

	logic [1:0]  tg_busstate = 2'b01;
	logic [2:0]  tg_fc = 3'b101;
	logic [31:0] tg_addr = 32'd0;
	logic [15:0] tg_wdata = 16'd0;
	logic tg_nuds = 1'b1;
	logic tg_nlds = 1'b1;
	logic tg_clkena;
	logic [15:0] tg_rdata;

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
	logic [31:0] board_rdata = 32'h89ab_cdef;

	logic response_pending = 1'b0;
	integer stall_count = 0;
	integer board_transaction_count = 0;
	logic saw_ack_while_ce_low = 1'b0;
	logic [23:0] captured_addr;
	logic [31:0] captured_wdata;
	logic [3:0] captured_be;
	logic captured_we;

	always #5 clk = ~clk;

	always_ff @(posedge clk) begin
		if (reset)
			ce_div <= 2'd0;
		else
			ce_div <= ce_div + 2'd1;
	end
	assign cpu_ce = !reset && (ce_div == 2'd0);

	// A board target that deliberately responds between CPU enable pulses.
	assign board_ack = response_pending && (stall_count == 0);
	always_ff @(posedge clk) begin
		if (reset) begin
			response_pending <= 1'b0;
			stall_count <= 0;
		end else if (!board_req) begin
			response_pending <= 1'b0;
		end else if (!response_pending) begin
			response_pending <= 1'b1;
			stall_count <= 1;
			captured_we <= board_we;
			captured_addr <= board_addr;
			captured_wdata <= board_wdata;
			captured_be <= board_be;
			board_transaction_count <= board_transaction_count + 1;
		end else if (stall_count != 0) begin
			stall_count <= stall_count - 1;
		end

		if (!reset && board_ack && !cpu_ce)
			saw_ack_while_ce_low <= 1'b1;
		if (!reset && response_pending && board_req) begin
			assert ({board_we, board_addr, board_wdata, board_be} ==
			        {captured_we, captured_addr, captured_wdata, captured_be})
				else $fatal(1, "adapter changed board request while stalled");
		end
	end

	itech32_tg68_bus_adapter dut (
		.clk(clk), .reset(reset), .cpu_ce(cpu_ce),
		.tg_busstate(tg_busstate), .tg_fc(tg_fc), .tg_addr(tg_addr),
		.tg_wdata(tg_wdata), .tg_nuds(tg_nuds), .tg_nlds(tg_nlds),
		.tg_clkena(tg_clkena), .tg_rdata(tg_rdata),
		.vector_load_we(vector_load_we), .vector_load_addr(vector_load_addr),
		.vector_load_wdata(vector_load_wdata), .vector_load_be(vector_load_be),
		.board_req(board_req), .board_we(board_we), .board_addr(board_addr),
		.board_wdata(board_wdata), .board_be(board_be),
		.board_ack(board_ack), .board_rdata(board_rdata)
	);

	task automatic load_vector_dword(
		input logic [4:0] index,
		input logic [31:0] value,
		input logic [3:0] lanes
	);
		begin
			@(negedge clk);
			vector_load_addr = index;
			vector_load_wdata = value;
			vector_load_be = lanes;
			vector_load_we = 1'b1;
			@(negedge clk);
			vector_load_we = 1'b0;
		end
	endtask

	task automatic tg_cycle(
		input logic [1:0] cycle_state,
		input logic [31:0] address,
		input logic [15:0] write_data,
		input logic nuds,
		input logic nlds,
		output logic [15:0] read_data
	);
		integer timeout;
		begin
			@(negedge clk);
			tg_busstate = cycle_state;
			tg_addr = address;
			tg_wdata = write_data;
			tg_nuds = nuds;
			tg_nlds = nlds;
			// A registered idle advance may already be in flight when this
			// fixture presents the bus state that TG would produce from it.
			// Do not mistake that causal launch pulse for the later response.
			while (tg_clkena)
				@(posedge clk);
			timeout = 0;
			do begin
				@(posedge clk);
				timeout = timeout + 1;
				if (timeout > 100)
					$fatal(1, "TG cycle timed out at %08x", address);
			end while (!tg_clkena);
			#1 read_data = tg_rdata;
			@(negedge clk);
			tg_busstate = 2'b01;
			tg_nuds = 1'b1;
			tg_nlds = 1'b1;
		end
	endtask

	task automatic expect_board_write(
		input logic [31:0] address,
		input logic [15:0] value,
		input logic nuds,
		input logic nlds,
		input logic [23:0] expected_addr,
		input logic [31:0] expected_data,
		input logic [3:0] expected_be
	);
		logic [15:0] ignored;
		begin
			tg_cycle(2'b11, address, value, nuds, nlds, ignored);
			if (!captured_we || captured_addr !== expected_addr ||
			    captured_wdata !== expected_data || captured_be !== expected_be)
				$fatal(1,
					"lane map addr=%08x got we/a/d/be=%b/%06x/%08x/%x expected %06x/%08x/%x",
					address, captured_we, captured_addr, captured_wdata, captured_be,
					expected_addr, expected_data, expected_be);
		end
	endtask

	task automatic expect_resetless_payload_capture;
		integer timeout;
		begin
			// Exercise the only safety condition required by the resetless payload
			// bank: reset must suppress requests, and the first real cycle must
			// overwrite the bank one full MAP_CAPTURE edge before it is consumed.
			@(negedge clk);
			tg_busstate = 2'b11;
			tg_addr = 32'h0000_0100;
			tg_wdata = 16'hdeed;
			tg_nuds = 1'b0;
			tg_nlds = 1'b0;
			repeat (2) begin
				@(posedge clk);
				#1;
				if (board_req)
					$fatal(1, "board request escaped while reset was asserted");
			end

			@(negedge clk);
			tg_wdata = 16'h1357;
			reset = 1'b0;
			@(posedge clk);
			#1;
			if (board_req)
				$fatal(1, "board request skipped the MAP_CAPTURE stage");

			// Perturb TG's live payload after its capture edge.  The board request
			// on the following edge must contain the held value, with no latency
			// change and no dependency on the register's power-up contents.
			@(negedge clk);
			tg_wdata = 16'heca8;
			@(posedge clk);
			#1;
			if (!board_req || !board_we || board_addr !== 24'h000100 ||
			    board_wdata !== 32'h1357_0000 || board_be !== 4'b1100)
				$fatal(1,
					"resetless capture/latency got req/we/a/d/be=%b/%b/%06x/%08x/%x",
					board_req, board_we, board_addr, board_wdata, board_be);

			timeout = 0;
			do begin
				@(posedge clk);
				timeout = timeout + 1;
				if (timeout > 100)
					$fatal(1, "resetless payload transaction timed out");
			end while (!tg_clkena);
			@(negedge clk);
			tg_busstate = 2'b01;
			tg_nuds = 1'b1;
			tg_nlds = 1'b1;
		end
	endtask

	logic [15:0] got;
	integer before_count;
	initial begin
		// Prove that the vector loader operates while reset is asserted.
		load_vector_dword(5'd0, 32'h1122_3344, 4'hf);
		load_vector_dword(5'd1, 32'h5566_7788, 4'hf);
		load_vector_dword(5'd1, 32'haa00_cc00, 4'b1010);

		expect_resetless_payload_capture();
		before_count = board_transaction_count;
		tg_cycle(2'b10, 32'h0000_0000, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'h1122) $fatal(1, "vector upper word read %04x", got);
		tg_cycle(2'b10, 32'h0000_0004, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'haa66) $fatal(1, "vector byte merge/upper word read %04x", got);
		tg_cycle(2'b10, 32'h0000_0006, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'hcc88) $fatal(1, "vector byte merge/lower word read %04x", got);
		tg_cycle(2'b11, 32'h0000_0002, 16'hbeef, 1'b0, 1'b0, got);
		tg_cycle(2'b10, 32'h0000_0002, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'hbeef) $fatal(1, "CPU vector-window write %04x", got);
		if (board_transaction_count != before_count)
			$fatal(1, "vector window escaped onto board bus");

		// Every big-endian byte lane, then both possible 16-bit word lanes.
		expect_board_write(32'h0000_0100, 16'h5a00, 1'b0, 1'b1,
			24'h000100, 32'h5a00_0000, 4'b1000);
		expect_board_write(32'h0000_0101, 16'h00a5, 1'b1, 1'b0,
			24'h000101, 32'h00a5_0000, 4'b0100);
		expect_board_write(32'h0000_0102, 16'h3c00, 1'b0, 1'b1,
			24'h000102, 32'h0000_3c00, 4'b0010);
		expect_board_write(32'h0000_0103, 16'h00c3, 1'b1, 1'b0,
			24'h000103, 32'h0000_00c3, 4'b0001);
		expect_board_write(32'h0000_0100, 16'h1122, 1'b0, 1'b0,
			24'h000100, 32'h1122_0000, 4'b1100);
		expect_board_write(32'h0000_0102, 16'h3344, 1'b0, 1'b0,
			24'h000102, 32'h0000_3344, 4'b0011);

		tg_cycle(2'b10, 32'h0000_0100, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'h89ab) $fatal(1, "upper board read %04x", got);
		tg_cycle(2'b10, 32'h0000_0102, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'hcdef) $fatal(1, "lower board read %04x", got);

		// A 68020 autovectored interrupt still presents a CPU-space IACK read.
		// It must complete locally, while the same address at ordinary FC and
		// an FC=111 write remain observable board transactions.
		before_count = board_transaction_count;
		tg_fc = 3'b111;
		tg_cycle(2'b10, 32'hffff_fff4, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'hffff || board_transaction_count != before_count || board_req)
			$fatal(1, "IRQ2 IACK escaped onto board bus");
		tg_cycle(2'b10, 32'hffff_fff6, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'hffff || board_transaction_count != before_count || board_req)
			$fatal(1, "IRQ3 IACK escaped onto board bus");

		tg_fc = 3'b101;
		tg_cycle(2'b10, 32'hffff_fff4, 16'd0, 1'b0, 1'b0, got);
		if (got !== 16'h89ab || board_transaction_count != before_count + 1 ||
		    captured_we || captured_addr !== 24'hfffff4)
			$fatal(1, "ordinary FC near IACK window did not reach board");

		tg_fc = 3'b111;
		expect_board_write(32'hffff_fff4, 16'h5a5a, 1'b0, 1'b0,
			24'hfffff4, 32'h5a5a_0000, 4'b1100);
		if (board_transaction_count != before_count + 2)
			$fatal(1, "FC=111 write was incorrectly consumed as IACK");
		tg_fc = 3'b101;

		if (!saw_ack_while_ce_low)
			$fatal(1, "test never exercised board ack while cpu_ce was low");

		$display("PASS TG68-to-ITech32 adapter: reset shadow, stalls, byte lanes, local IACK");
		$finish;
	end

endmodule
