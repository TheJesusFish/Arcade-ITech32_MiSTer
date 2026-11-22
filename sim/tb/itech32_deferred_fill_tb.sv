`timescale 1ns/1ps
// Deferred command 6 against an eager reference. The bench drives the blitter
// side of itech32_deferred_fill the way the blitter does (prepare, read and
// capture the source row, arm the destination rows) and mixes in pixel writes,
// reads and idle time. The reference applies every copy at once, as the
// original board and MAME do: each read must return the reference value, and
// once the background fill finishes the VRAM must equal the reference. The
// VRAM model acknowledges after a random delay (or in the same cycle) and
// checks that every held request keeps its payload. A disabled module must
// pass requests through in the same cycle and never write on its own.
module itech32_deferred_fill_tb;
	logic clk = 1'b0, reset = 1'b1;
	logic enable = 1'b1, rows_512 = 1'b0;
	logic prepare_req = 1'b0, prepare_plane = 1'b0, prepare_ready;
	logic capturing = 1'b0;
	logic capture_we, capture_plane;
	logic [8:0] capture_word;
	logic [15:0] capture_data;
	logic arm_req = 1'b0, arm_plane = 1'b0, arm_down = 1'b0, arm_ack;
	logic [9:0] arm_first_row = '0;
	logic [8:0] arm_rows = '0;
	logic background_ok = 1'b0;
	logic blit_req = 1'b0, blit_we = 1'b0, blit_plane = 1'b0, blit_ack;
	logic [18:0] blit_addr = '0;
	logic [15:0] blit_wdata = '0, blit_rdata;
	logic mem_req, mem_we, mem_plane, mem_ack;
	logic [18:0] mem_addr;
	logic [15:0] mem_wdata, mem_rdata;

	itech32_deferred_fill dut (.*);
	always #5 clk = ~clk;

	// The blitter captures each source word on its read's ACK cycle.
	assign capture_we = capturing && blit_ack;
	assign capture_plane = blit_plane;
	assign capture_word = blit_addr[8:0];
	assign capture_data = blit_rdata;

	logic [15:0] vram [0:1048575];
	logic [15:0] ref_vram [0:1048575];
	integer checks = 0;
	integer self_writes = 0;
	integer reads_checked = 0;

	// VRAM model: a held request is acknowledged in its first cycle when the
	// LFSR allows, otherwise after 1-3 cycles; its payload must not change.
	logic [15:0] lfsr = 16'hace1;
	logic        in_flight = 1'b0;
	logic [1:0]  wait_count = '0;
	logic        held_we, held_plane;
	logic [18:0] held_addr;
	logic [15:0] held_wdata;
	assign mem_ack = mem_req && (in_flight ? wait_count == 2'd0 : lfsr[0]);
	assign mem_rdata = vram[{mem_plane, mem_addr}];

	always_ff @(posedge clk) begin
		lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
		if (in_flight)
			assert ({mem_req, mem_we, mem_plane, mem_addr} == {1'b1, held_we, held_plane, held_addr} &&
				(!mem_we || mem_wdata == held_wdata))
				else $fatal(1, "DEFERRED_FILL held VRAM request changed");
		if (mem_ack) begin
			in_flight <= 1'b0;
			if (mem_we)
				vram[{mem_plane, mem_addr}] <= mem_wdata;
			if (mem_we && !blit_ack)
				self_writes <= self_writes + 1;
		end else if (mem_req && !in_flight) begin
			in_flight <= 1'b1;
			wait_count <= lfsr[2:1];
			held_we <= mem_we;
			held_plane <= mem_plane;
			held_addr <= mem_addr;
			held_wdata <= mem_wdata;
		end else if (in_flight) begin
			wait_count <= wait_count - 2'd1;
		end
		// The blitter side sees an ACK only for its own forwarded request.
		if (blit_ack)
			assert (mem_ack && mem_we == blit_we && mem_plane == blit_plane &&
				mem_addr == blit_addr)
				else $fatal(1, "DEFERRED_FILL blitter ACK without its request");
		// Background fill only while the blitter is idle or waiting on prepare.
		if (mem_req && !blit_req && !background_ok && !prepare_req)
			assert (dut.state == 3'd6 && dut.fill_o_valid)
				else $fatal(1, "DEFERRED_FILL wrote outside a fill");
	end

	function automatic logic [9:0] row_mask(input logic [9:0] row);
		return rows_512 ? {1'b0, row[8:0]} : row;
	endfunction

	// Returns just after the rising edge that completed the handshake.
	task automatic wait_blit_ack(output logic [15:0] got);
		#1;
		while (!blit_ack) begin
			@(negedge clk);
			#1;
		end
		got = blit_rdata;
		@(posedge clk);
		#1;
	endtask

	task automatic access(input logic we, input logic plane, input logic [18:0] addr,
		input logic [15:0] data, output logic [15:0] got);
		@(negedge clk);
		blit_req = 1'b1;
		blit_we = we;
		blit_plane = plane;
		blit_addr = addr;
		blit_wdata = data;
		wait_blit_ack(got);
		if (we)
			ref_vram[{plane, addr}] = data;
		blit_req = 1'b0;
	endtask

	task automatic write_pixel(input logic plane, input logic [9:0] row, input logic [8:0] x,
		input logic [15:0] data);
		logic [15:0] unused;
		access(1'b1, plane, {row_mask(row), x}, data, unused);
	endtask

	task automatic read_pixel(input logic plane, input logic [9:0] row, input logic [8:0] x);
		logic [15:0] got;
		logic [18:0] addr;
		addr = {row_mask(row), x};
		access(1'b0, plane, addr, 16'h0000, got);
		if (got !== ref_vram[{plane, addr}])
			$fatal(1, "DEFERRED_FILL read plane %0d row %0d x %0d got %04x expected %04x",
				plane, row_mask(row), x, got, ref_vram[{plane, addr}]);
		reads_checked++;
	endtask

	// Command 6 for one plane, as the blitter performs it: wait for prepare,
	// read the 512-word source row through the port while capturing it, then
	// arm rows source+-1 .. source+-(height-1).
	task automatic shift_copy(input logic plane, input logic [9:0] source, input logic down,
		input int height);
		logic [15:0] line [0:511];
		logic [15:0] got;
		logic [9:0] row;
		@(negedge clk);
		prepare_req = 1'b1;
		prepare_plane = plane;
		#1;
		while (!prepare_ready) begin
			@(negedge clk);
			#1;
		end
		@(negedge clk);
		prepare_req = 1'b0;
		capturing = 1'b1;
		for (int x = 0; x < 512; x++) begin
			@(negedge clk);
			blit_req = 1'b1;
			blit_we = 1'b0;
			blit_plane = plane;
			blit_addr = {row_mask(source), 9'(x)};
			wait_blit_ack(got);
			if (got !== ref_vram[{plane, row_mask(source), 9'(x)}])
				$fatal(1, "DEFERRED_FILL source read row %0d x %0d", row_mask(source), x);
			line[x] = got;
			blit_req = 1'b0;
		end
		capturing = 1'b0;
		row = source;
		for (int k = 1; k < height; k++) begin
			row = row_mask(down ? row - 10'd1 : row + 10'd1);
			for (int x = 0; x < 512; x++)
				ref_vram[{plane, row, 9'(x)}] = line[x];
		end
		@(negedge clk);
		arm_req = 1'b1;
		arm_plane = plane;
		arm_first_row = row_mask(down ? source - 10'd1 : source + 10'd1);
		arm_down = down;
		arm_rows = 9'(height - 1);
		#1;
		while (!arm_ack) begin
			@(negedge clk);
			#1;
		end
		// The blitter leaves its arm state on the edge that sees the ACK.
		@(posedge clk);
		#1;
		arm_req = 1'b0;
		checks++;
	endtask

	task automatic idle(input int cycles);
		@(negedge clk);
		background_ok = 1'b1;
		repeat (cycles) @(negedge clk);
		background_ok = 1'b0;
	endtask

	task automatic drain_and_compare(input string label);
		@(negedge clk);
		background_ok = 1'b1;
		while (!(dut.pending_count[0] == 10'd0 && dut.pending_count[1] == 10'd0 &&
			dut.state == 3'd1))
			@(negedge clk);
		background_ok = 1'b0;
		repeat (4) @(negedge clk);
		for (int i = 0; i < 1048576; i++)
			if (vram[i] !== ref_vram[i])
				$fatal(1, "DEFERRED_FILL_%s plane %0d row %0d x %0d got %04x expected %04x",
					label, i >> 19, (i >> 9) & 1023, i & 511, vram[i], ref_vram[i]);
		checks++;
	endtask

	task automatic pulse_reset;
		@(negedge clk);
		reset = 1'b1;
		repeat (3) @(negedge clk);
		reset = 1'b0;
		// The pending-bit sweep must finish before the port reopens.
		while (dut.state != 3'd1) @(negedge clk);
	endtask

	int op, len, writes_before;
	logic plane;
	logic [9:0] row;
	logic [8:0] x;

	initial begin
		for (int i = 0; i < 1048576; i++) begin
			vram[i] = 16'(i * 40503);
			ref_vram[i] = vram[i];
		end
		pulse_reset();

		// Directed: Golden Tee's copy (256 rows upward from a source row), a
		// write and a read inside the pending range, then the background.
		write_pixel(1'b0, 10'd767, 9'd5, 16'h1234);
		shift_copy(1'b0, 10'd767, 1'b1, 256);
		assert (dut.pending_count[0] == 10'd255)
			else $fatal(1, "DEFERRED_FILL pending count %0d", dut.pending_count[0]);
		write_pixel(1'b0, 10'd600, 9'd17, 16'habcd);
		read_pixel(1'b0, 10'd600, 9'd18);
		read_pixel(1'b0, 10'd513, 9'd511);
		read_pixel(1'b0, 10'd512, 9'd0);
		drain_and_compare("DIRECTED");

		// A new copy over the row last proved clean must not reuse that proof:
		// nothing is pending, so the source reads pass without a lookup.
		plane = dut.clean_plane;
		row = dut.clean_row;
		assert (dut.clean_valid)
			else $fatal(1, "DEFERRED_FILL expected a clean row after the drain");
		write_pixel(plane, row + 10'd1, 9'd77, 16'h7e57);
		shift_copy(plane, row + 10'd1, 1'b1, 4);
		read_pixel(plane, row, 9'd77);
		drain_and_compare("STALE_TAG");

		// Both planes, descending and ascending, with a wrap through row 0.
		shift_copy(1'b0, 10'd255, 1'b1, 256);
		shift_copy(1'b1, 10'd1000, 1'b0, 100);
		read_pixel(1'b1, 10'd1023, 9'd100);
		read_pixel(1'b1, 10'd60, 9'd7);
		write_pixel(1'b0, 10'd0, 9'd0, 16'h0f0f);
		idle(3000);
		// A second copy of a plane waits for its first to finish.
		shift_copy(1'b0, 10'd300, 1'b0, 50);
		drain_and_compare("TWO_PLANES");

		// Randomized mix.
		for (int round = 0; round < 120; round++) begin
			op = $urandom_range(0, 9);
			plane = 1'($urandom_range(0, 1));
			row = 10'($urandom_range(0, 1023));
			if (op == 0) begin
				shift_copy(plane, row, 1'($urandom_range(0, 1)), $urandom_range(2, 511));
			end else if (op < 5) begin
				len = $urandom_range(1, 40);
				x = 9'($urandom_range(0, 511));
				for (int i = 0; i < len; i++)
					write_pixel(plane, row + 10'($urandom_range(0, 3)), x + 9'(i), 16'($urandom));
			end else if (op < 8) begin
				for (int i = 0; i < 8; i++)
					read_pixel(plane, row + 10'(i), 9'($urandom_range(0, 511)));
			end else begin
				idle($urandom_range(1, 2000));
			end
		end
		drain_and_compare("RANDOM");

		// 512-row planes (Time Killers' geometry) wrap rows modulo 512.
		rows_512 = 1'b1;
		pulse_reset();
		shift_copy(1'b1, 10'd10, 1'b1, 200);
		read_pixel(1'b1, 10'd500, 9'd3);
		write_pixel(1'b1, 10'd400, 9'd9, 16'h5555);
		drain_and_compare("ROWS_512");
		rows_512 = 1'b0;

		// Disabled: same-cycle pass-through and no writes of its own.
		enable = 1'b0;
		pulse_reset();
		writes_before = self_writes;
		@(negedge clk);
		blit_req = 1'b1;
		blit_we = 1'b1;
		blit_plane = 1'b1;
		blit_addr = 19'h12345;
		blit_wdata = 16'h4242;
		#1;
		assert (mem_req && mem_we && mem_plane && mem_addr == 19'h12345 && mem_wdata == 16'h4242)
			else $fatal(1, "DEFERRED_FILL disabled pass-through");
		begin
			logic [15:0] unused;
			wait_blit_ack(unused);
		end
		ref_vram[{1'b1, 19'h12345}] = 16'h4242;
		blit_req = 1'b0;
		idle(2000);
		assert (self_writes == writes_before)
			else $fatal(1, "DEFERRED_FILL disabled module wrote %0d words",
				self_writes - writes_before);
		drain_and_compare("DISABLED");

		$display("DEFERRED_FILL_PASS checks=%0d reads=%0d", checks, reads_checked);
		$finish;
	end
endmodule
