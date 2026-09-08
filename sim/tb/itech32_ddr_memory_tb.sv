`timescale 1ns/1ps

module itech32_ddr_memory_tb;
	localparam integer SCAN_BURST_WORDS = 97;
	localparam logic [4:0] MEM_ST_IDLE       = 5'd0;
	localparam logic [4:0] MEM_ST_DISPATCH   = 5'd1;
	localparam logic [4:0] MEM_ST_ISSUE      = 5'd2;
	localparam logic [4:0] MEM_ST_WAIT_WRITE = 5'd4;
	localparam logic [4:0] MEM_ST_CAPTURE    = 5'd7;
	localparam logic [4:0] MEM_ST_RESPOND    = 5'd8;
	localparam logic [4:0] MEM_ST_LOOKUP_RESULT = 5'd9;
	localparam logic [4:0] MEM_ST_SELECT     = 5'd10;
	localparam logic [4:0] MEM_ST_VRAM_BURST_WRITE = 5'd19;
	localparam logic [1:0] SOUND_FRONT_MISS_WAIT = 2'd2;
	localparam logic [27:0] GROM_BASE    = 28'h050_0000;
	localparam logic [27:0] SOUND_BASE   = 28'h040_0000;
	localparam logic [27:0] SAMPLE0_BASE = 28'h260_0000;
	localparam logic [27:0] SAMPLE3_BASE = 28'h2a0_0000;
	localparam logic [27:0] VRAM_BASE    = 28'h2e0_0000;

	logic clk = 1'b0;
	logic reset = 1'b1;
	logic timekill_mode = 1'b0;
	logic quiesce = 1'b0;
	logic quiesce_ack;
	logic framework_reset = 1'b0;
	logic ioctl_download = 1'b0;
	logic ioctl_wr = 1'b0;
	logic [15:0] ioctl_index = 16'd0;
	logic [26:0] ioctl_addr = 27'd0;
	logic [15:0] ioctl_data = 16'd0;
	logic ioctl_wait;
	logic rom_loaded;
	logic vector_load_we;
	logic [4:0] vector_load_addr;
	logic [31:0] vector_load_wdata;
	logic [3:0] vector_load_be;
	logic [31:0] captured_vectors [0:31];
	integer vector_write_count;
	integer vector_pass_count;
	logic vector_sequence_active;
	logic [4:0] next_vector_addr;

	logic main_req = 1'b0;
	logic [21:0] main_addr = 22'd0;
	logic main_ack;
	logic [31:0] main_rdata;
	logic grom_req = 1'b0;
	logic [25:0] grom_addr = 26'd0;
	logic grom_ack;
	logic [63:0] grom_rdata;
	logic sound_req = 1'b0;
	logic [18:0] sound_addr = 19'd0;
	logic sound_ack;
	logic [7:0] sound_rdata;
	logic sample_req = 1'b0;
	logic [1:0] sample_bank = 2'd0;
	logic [21:0] sample_addr = 22'd0;
	logic sample_ack;
	logic [15:0] sample_rdata;
	logic vram_req = 1'b0;
	logic vram_we = 1'b0;
	logic [19:0] vram_addr = 20'd0;
	logic [15:0] vram_wdata = 16'd0;
	logic [1:0] vram_be = 2'b11;
	logic vram_ack;
	logic [15:0] vram_rdata;
	logic vram_qwrite_req = 1'b0;
	logic [17:0] vram_qwrite_addr = 18'd0;
	logic [63:0] vram_qwrite_data = 64'd0;
	logic [7:0] vram_qwrite_be = 8'd0;
	logic vram_qwrite_token = 1'b0;
	logic vram_qwrite_ack;
	logic scan_req = 1'b0;
	logic [19:0] scan_addr = 20'd0;
	logic scan_accept;
	logic scan_data_valid;
	logic [63:0] scan_rdata;
	logic scan_last;

	logic DDRAM_CLK;
	logic DDRAM_BUSY;
	logic [7:0] DDRAM_BURSTCNT;
	logic [28:0] DDRAM_ADDR;
	logic [63:0] DDRAM_DOUT;
	logic DDRAM_DOUT_READY;
	logic [63:0] DDRAM_DIN;
	logic [7:0] DDRAM_BE;
	logic DDRAM_RD;
	logic DDRAM_WE;
	logic core_DDRAM_BUSY;
	logic [7:0] core_DDRAM_BURSTCNT;
	logic [28:0] core_DDRAM_ADDR;
	logic [63:0] core_DDRAM_DOUT;
	logic core_DDRAM_DOUT_READY;
	logic [63:0] core_DDRAM_DIN;
	logic [7:0] core_DDRAM_BE;
	logic core_DDRAM_RD;
	logic core_DDRAM_WE;

	logic [7:0] low_memory [0:65535];
	logic [7:0] vram_memory [0:4095];
	logic model_active;
	logic model_armed;
	logic model_read;
	logic force_waitrequest = 1'b0;
	logic hold_read_returns = 1'b0;
	logic [7:0] grom_image_epoch = 8'd0;
	logic [27:0] model_line_addr;
	logic [63:0] model_read_data;
	logic [7:0] model_burst_count;
	logic [7:0] model_burst_beat;
	integer model_delay;
	integer ddr_transactions;
	integer ddr_write_bursts;
	logic [7:0] last_write_burst_count;
	logic [28:0] last_write_burst_addr;
	integer write_index;
	integer init_index;
	logic dispatch_commit_watch = 1'b0;
	integer dispatch_commit_count = 0;
	logic retained_vram_writes;
`ifdef ITECH32_WRITE_OVERLAP
	assign retained_vram_writes = dut.vram_write_buffer_valid ||
		dut.vram_fast_pending || dut.vram_drain_valid;
`else
	assign retained_vram_writes = dut.vram_write_buffer_valid || dut.vram_fast_pending;
`endif

	function automatic integer collect_slot(input logic [3:0] index);
`ifdef ITECH32_WRITE_OVERLAP
		return integer'({dut.vram_collect_bank, index});
`else
		return integer'(index);
`endif
	endfunction

	always #5 clk = ~clk;

	initial begin : protocol_watchdog
		#5ms;
		$display("DDR TB timeout state=%0d main=%b grom=%b sound=%b sample=%b vram=%b scan=%b download=%b active=%b ended=%b loaded=%b model=%b beat=%0d/%0d delay=%0d busy=%b ready=%b scanbeat=%0d",
			dut.state, main_req, grom_req, sound_req, sample_req, vram_req,
			scan_req, ioctl_download, dut.rom_download_active,
			dut.download_ended, rom_loaded, model_active, model_burst_beat,
			model_burst_count, model_delay, DDRAM_BUSY, DDRAM_DOUT_READY,
			dut.scan_beat);
		$fflush();
		$fatal(1, "DDR TB timeout state=%0d main=%b grom=%b sound=%b sample=%b vram=%b scan=%b download=%b active=%b ended=%b loaded=%b model=%b",
			dut.state, main_req, grom_req, sound_req, sample_req, vram_req,
			scan_req, ioctl_download, dut.rom_download_active,
			dut.download_ended, rom_loaded, model_active);
	end

	itech32_ddr_memory #(.VRAM_CLEAR_LINES(8)) dut (
		.clk(clk), .reset(reset), .timekill_mode(timekill_mode), .bloodstorm_mode(1'b0),
		.quiesce(quiesce), .quiesce_ack(quiesce_ack),
		.ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
		.ioctl_index(ioctl_index), .ioctl_addr(ioctl_addr),
		.ioctl_data(ioctl_data), .ioctl_wait(ioctl_wait),
		.rom_loaded(rom_loaded), .vector_load_we(vector_load_we),
		.vector_load_addr(vector_load_addr), .vector_load_wdata(vector_load_wdata),
		.vector_load_be(vector_load_be),
		.main_req(main_req), .main_addr(main_addr), .main_ack(main_ack),
		.main_rdata(main_rdata),
		.grom_req(grom_req), .grom_addr(grom_addr), .grom_ack(grom_ack),
		.grom_rdata(grom_rdata),
		.sound_req(sound_req), .sound_addr(sound_addr), .sound_ack(sound_ack),
		.sound_rdata(sound_rdata),
		.sample_req(sample_req), .sample_bank(sample_bank),
		.sample_addr(sample_addr), .sample_ack(sample_ack),
		.sample_rdata(sample_rdata),
		.vram_req(vram_req), .vram_we(vram_we), .vram_addr(vram_addr),
		.vram_wdata(vram_wdata), .vram_be(vram_be), .vram_ack(vram_ack),
		.vram_rdata(vram_rdata),
		.vram_qwrite_req(vram_qwrite_req),
		.vram_qwrite_addr(vram_qwrite_addr),
		.vram_qwrite_data(vram_qwrite_data),
		.vram_qwrite_be(vram_qwrite_be),
		.vram_qwrite_token(vram_qwrite_token),
		.vram_qwrite_ack(vram_qwrite_ack),
		.scan_req(scan_req), .scan_addr(scan_addr),
		.scan_accept(scan_accept), .scan_data_valid(scan_data_valid),
		.scan_rdata(scan_rdata), .scan_last(scan_last),
		.DDRAM_CLK(DDRAM_CLK), .DDRAM_BUSY(core_DDRAM_BUSY),
		.DDRAM_BURSTCNT(core_DDRAM_BURSTCNT), .DDRAM_ADDR(core_DDRAM_ADDR),
		.DDRAM_DOUT(core_DDRAM_DOUT),
		.DDRAM_DOUT_READY(core_DDRAM_DOUT_READY),
		.DDRAM_DIN(core_DDRAM_DIN), .DDRAM_BE(core_DDRAM_BE),
		.DDRAM_RD(core_DDRAM_RD), .DDRAM_WE(core_DDRAM_WE)
	);

	// Use the same reset-side bus guard instantiated by MiSTer's sysmem.  The
	// DUT is its Avalon master (slave-side ports below); the deterministic DDR
	// model remains on the terminator's master-facing side.
	f2sdram_safe_terminator #(
		.DATA_WIDTH(64),
		.BURSTCOUNT_WIDTH(8)
	) terminator (
		.clk(clk),
		.rst_req_sync(framework_reset),
		.waitrequest_master(DDRAM_BUSY),
		.burstcount_master(DDRAM_BURSTCNT),
		.address_master(DDRAM_ADDR),
		.readdata_master(DDRAM_DOUT),
		.readdatavalid_master(DDRAM_DOUT_READY),
		.read_master(DDRAM_RD),
		.writedata_master(DDRAM_DIN),
		.byteenable_master(DDRAM_BE),
		.write_master(DDRAM_WE),
		.waitrequest_slave(core_DDRAM_BUSY),
		.burstcount_slave(core_DDRAM_BURSTCNT),
		.address_slave(core_DDRAM_ADDR),
		.readdata_slave(core_DDRAM_DOUT),
		.readdatavalid_slave(core_DDRAM_DOUT_READY),
		.read_slave(core_DDRAM_RD),
		.writedata_slave(core_DDRAM_DIN),
		.byteenable_slave(core_DDRAM_BE),
		.write_slave(core_DDRAM_WE)
	);

	always_ff @(posedge clk) begin
		if (reset) begin
			vector_write_count <= 0;
			vector_pass_count <= 0;
			vector_sequence_active <= 1'b0;
			next_vector_addr <= 5'd0;
		end else if (vector_load_we) begin
			assert (vector_load_be == 4'hf)
				else $fatal(1, "partial reset-vector write");
			captured_vectors[vector_load_addr] <= vector_load_wdata;
			vector_write_count <= vector_write_count + 1;
			if (vector_load_addr == 5'd0) begin
				vector_sequence_active <= 1'b1;
				next_vector_addr <= 5'd1;
			end else begin
				assert (vector_sequence_active && vector_load_addr == next_vector_addr)
					else $fatal(1, "reset-vector sequence skipped/repeated address %0d expected %0d",
						vector_load_addr, next_vector_addr);
				if (vector_load_addr == 5'd31) begin
					vector_sequence_active <= 1'b0;
					vector_pass_count <= vector_pass_count + 1;
				end else begin
					next_vector_addr <= next_vector_addr + 1'b1;
				end
			end
		end
	end

	// Count the sole ST_IDLE commit edge for the directed fallback-dispatch
	// regression below. The producer ACK is intentionally one edge earlier,
	// when the payload becomes durable in vram_fast_*.
	always_ff @(posedge clk) begin
		if (reset)
			dispatch_commit_count <= 0;
		else if (dispatch_commit_watch && dut.vram_buffer_commit)
			dispatch_commit_count <= dispatch_commit_count + 1;
	end

	function automatic logic [7:0] model_byte(input logic [27:0] address);
		logic [27:0] relative;
		begin
			if (address < 28'h001_0000)
				model_byte = low_memory[address[15:0]];
			else if (address >= GROM_BASE && address < GROM_BASE + 28'h208_0000) begin
				relative = address - GROM_BASE;
				model_byte = 8'h40 ^ relative[7:0] ^ relative[15:8] ^
					relative[23:16] ^ {6'd0, relative[25:24]} ^ grom_image_epoch;
			end else if (address >= SOUND_BASE && address < SOUND_BASE + 28'h004_8000) begin
				relative = address - SOUND_BASE;
				model_byte = 8'ha0 ^ relative[7:0] ^ relative[15:8];
			end else if (address >= SAMPLE0_BASE && address < SAMPLE0_BASE + 28'h040_0000) begin
				relative = address - SAMPLE0_BASE;
				model_byte = 8'h80 ^ relative[7:0] ^ relative[15:8];
			end else if (address >= SAMPLE3_BASE && address < SAMPLE3_BASE + 28'h040_0000) begin
				relative = address - SAMPLE3_BASE;
				model_byte = 8'he0 ^ relative[7:0] ^ relative[15:8];
			end else if (address >= VRAM_BASE && address < VRAM_BASE + 28'h000_1000) begin
				relative = address - VRAM_BASE;
				model_byte = vram_memory[relative[11:0]];
			end else
				model_byte = 8'd0;
		end
	endfunction

	task automatic model_write_byte(
		input logic [27:0] address,
		input logic [7:0] value
	);
		logic [27:0] relative;
		begin
			if (address < 28'h001_0000)
				low_memory[address[15:0]] = value;
			else if (address >= VRAM_BASE && address < VRAM_BASE + 28'h000_1000) begin
				relative = address - VRAM_BASE;
				vram_memory[relative[11:0]] = value;
			end
		end
	endtask

	function automatic logic [63:0] model_line(input logic [27:0] address);
		logic [63:0] result;
		integer byte_index;
		begin
			result = 64'd0;
			for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1)
				result[byte_index * 8 +: 8] = model_byte(address + 28'(byte_index));
			model_line = result;
		end
	endfunction

	function automatic logic [27:0] logical_line_addr(input logic [28:0] word_addr);
		logic [31:0] byte_address;
		begin
			byte_address = {word_addr, 3'b000};
			logical_line_addr = byte_address - 32'h3000_0000;
		end
	endfunction

	// Deterministic, variable-latency MiSTer DDR model. A request is accepted
	// once until RD/WE return low; BUSY then lasts 1..4 clocks.
	always_ff @(posedge clk) begin
		DDRAM_DOUT_READY <= 1'b0;
		if (reset) begin
			DDRAM_BUSY <= 1'b0;
			DDRAM_DOUT <= 64'd0;
			DDRAM_DOUT_READY <= 1'b0;
			model_active <= 1'b0;
			model_armed <= 1'b1;
			model_read <= 1'b0;
			model_line_addr <= 28'd0;
			model_read_data <= 64'd0;
			model_burst_count <= 8'd1;
			model_burst_beat <= 8'd0;
			model_delay <= 0;
			ddr_transactions <= 0;
			ddr_write_bursts <= 0;
			last_write_burst_count <= 8'd0;
			last_write_burst_addr <= 29'd0;
		end else if (hold_read_returns && model_active && model_read) begin
			// Accepted read remains outstanding; no return beat is published.
		end else if (force_waitrequest) begin
			// Assert Avalon waitrequest before the pending command is accepted.
			DDRAM_BUSY <= 1'b1;
		end else begin
			// Release a test-forced waitrequest one cycle before accepting the
			// still-held command.
			if (DDRAM_BUSY && !model_active)
				DDRAM_BUSY <= 1'b0;
			if (!DDRAM_RD && !DDRAM_WE)
				model_armed <= 1'b1;

			if (!model_active && model_armed && !DDRAM_BUSY && (DDRAM_RD || DDRAM_WE)) begin
				assert ((DDRAM_RD && (DDRAM_BURSTCNT == 8'd1 ||
					DDRAM_BURSTCNT == 8'd16 ||
					DDRAM_BURSTCNT == 8'(SCAN_BURST_WORDS))) ||
					(DDRAM_WE && DDRAM_BURSTCNT >= 8'd1 &&
					DDRAM_BURSTCNT <= 8'd16))
					else $fatal(1, "unexpected DDR burst count %0d", DDRAM_BURSTCNT);
				model_active <= DDRAM_RD || DDRAM_BURSTCNT != 8'd1;
				model_armed <= 1'b0;
				model_read <= DDRAM_RD;
				model_line_addr <= logical_line_addr(DDRAM_ADDR);
				model_read_data <= model_line(logical_line_addr(DDRAM_ADDR));
				model_burst_count <= DDRAM_BURSTCNT;
				model_burst_beat <= DDRAM_WE ? 8'd1 : 8'd0;
				model_delay <= (ddr_transactions % 4) + 1;
				ddr_transactions <= ddr_transactions + 1;
				if (DDRAM_WE) begin
					ddr_write_bursts <= ddr_write_bursts + 1;
					last_write_burst_count <= DDRAM_BURSTCNT;
					last_write_burst_addr <= DDRAM_ADDR;
				end
				DDRAM_BUSY <= DDRAM_RD || DDRAM_BURSTCNT != 8'd1;
				if (DDRAM_WE)
					for (write_index = 0; write_index < 8; write_index = write_index + 1)
						if (DDRAM_BE[write_index])
							model_write_byte(
								logical_line_addr(DDRAM_ADDR) + 28'(write_index),
								DDRAM_DIN[write_index * 8 +: 8]);
			end else if (model_active) begin
				if (model_delay != 0)
					model_delay <= model_delay - 1;
				else if (DDRAM_BUSY) begin
					DDRAM_BUSY <= 1'b0;
				end else begin
					if (model_read) begin
						DDRAM_DOUT <= model_line(model_line_addr +
							{17'd0, model_burst_beat, 3'b000});
						DDRAM_DOUT_READY <= 1'b1;
						if (model_burst_beat + 1'b1 == model_burst_count) begin
							model_active <= 1'b0;
						end else begin
							model_burst_beat <= model_burst_beat + 1'b1;
						end
					end else begin
						for (write_index = 0; write_index < 8; write_index = write_index + 1)
							if (DDRAM_BE[write_index])
								model_write_byte(model_line_addr +
									{17'd0, model_burst_beat, 3'b000} + 28'(write_index),
									DDRAM_DIN[write_index * 8 +: 8]);
						if (model_burst_beat + 1'b1 == model_burst_count) begin
							model_active <= 1'b0;
						end else begin
							model_burst_beat <= model_burst_beat + 1'b1;
							model_delay <= (ddr_transactions + model_burst_beat) % 4 + 1;
							DDRAM_BUSY <= 1'b1;
						end
					end
				end
			end
		end
	end

	task automatic loader_word(input logic [26:0] address, input logic [15:0] value);
		begin
			while (ioctl_wait)
				@(negedge clk);
			ioctl_addr = address;
			ioctl_data = value;
			ioctl_wr = 1'b1;
			@(negedge clk);
			ioctl_wr = 1'b0;
		end
	endtask

	integer expected_main_hit_edges=3;
	task automatic main_read(input logic [21:0] address, input logic [31:0] expected,
		input integer expected_edges=0);
		integer timeout;
		begin
			main_addr = address;
			main_req = 1'b1;
			timeout = 0;
			while (!main_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (main_ack && main_rdata == expected)
				else $fatal(1, "main read %x returned %x", address, main_rdata);
			if(expected_edges != 0) begin
				assert(timeout == expected_edges)
					else $fatal(1,"main hit latency address=%x got=%0d expected=%0d",address,timeout,expected_edges);
				$display("MAIN_HIT_LATENCY address=%x edges=%0d",address,timeout);
			end
			main_req = 1'b0;
			@(negedge clk);
		end
	endtask

	task automatic grom_read(input logic [25:0] address, input logic [7:0] expected);
		integer timeout;
		begin
			grom_addr = address;
			grom_req = 1'b1;
			timeout = 0;
			while (!grom_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (grom_ack &&
				grom_rdata[address[2:0] * 8 +: 8] == expected)
				else $fatal(1, "grom read %x returned qword %x", address, grom_rdata);
			grom_req = 1'b0;
			@(negedge clk);
		end
	endtask

	// Only local ownership must be free: shared DDR state is deliberately not
	// a prerequisite for the two-edge resident response.
	task automatic grom_cached_fast_read(
		input logic [25:0] address,
		input logic [7:0] expected
	);
		integer transaction_before;
		integer ack_count;
		begin
			while (dut.grom_front_state != 3'd0)
				@(negedge clk);
			transaction_before = ddr_transactions;
			grom_addr = address;
			grom_req = 1'b1;
			@(negedge clk);
			assert (!grom_ack && dut.grom_front_state == 3'd1 &&
				dut.grom_front_addr_q == address &&
				ddr_transactions == transaction_before)
				else $fatal(1, "GROM request did not cross local capture boundary");
			@(negedge clk);
			assert (grom_ack &&
				grom_rdata[address[2:0] * 8 +: 8] == expected &&
				dut.grom_front_state == 3'd2 &&
				ddr_transactions == transaction_before)
				else $fatal(1, "GROM hit did not ACK after synchronous local probe");
			ack_count = 1;
			repeat (3) begin
				@(negedge clk);
				if (grom_ack)
					ack_count = ack_count + 1;
			end
			assert (ack_count == 1 && ddr_transactions == transaction_before)
				else $fatal(1, "held GROM fast hit ACKed twice or touched DDR");
			grom_req = 1'b0;
			@(negedge clk);
		end
	endtask

	// Explicit expected effective addresses avoid using the DUT's wrap/tag
	// calculation in the payload oracle. Every byte of the returned qword is
	// checked against the memory model, not only the addressed byte.
	task automatic grom_full_read(input logic [25:0] address,
		input logic [25:0] effective);
		integer timeout;
		begin
			grom_addr=address; grom_req=1'b1; timeout=0;
			do begin @(negedge clk); timeout++; end while (!grom_ack && timeout<3000);
			assert(grom_ack && grom_rdata==model_line(GROM_BASE+{2'd0,effective[25:3],3'b0}))
				else $fatal(1,"GROM full payload mismatch request=%x effective=%x actual=%x",address,effective,grom_rdata);
			// Consume on the rising edge before releasing/changing a request.
			@(negedge clk); grom_req=1'b0;
			@(negedge clk);
		end
	endtask

	task automatic grom_resident_stream(input integer expected_shared_state);
		integer transactions_before;
		integer j;
		logic [25:0] address;
		begin
			while(dut.grom_front_state!=3'd0) @(negedge clk);
			transactions_before=ddr_transactions;
			// Covers all 16 qwords and every low-byte signature with no low gap.
			for(j=0;j<128;j++) begin
				address=26'h001200+26'(j);
				grom_req=1'b1;grom_addr=address;
				@(negedge clk);
				assert(!grom_ack && dut.grom_front_state==3'd1)
					else $fatal(1,"GROM capture latency changed item=%0d",j);
				@(negedge clk);
				assert(grom_ack && grom_rdata==model_line(GROM_BASE+{2'd0,address[25:3],3'b0}))
					else $fatal(1,"resident stream payload/latency item=%0d",j);
				assert(!dut.pending_clients[1] && !dut.pending_clients_q[1] &&
					ddr_transactions==transactions_before)
					else $fatal(1,"resident hit entered shared arbitration/DDR");
				if(expected_shared_state>=0)
					assert(integer'(dut.state)==expected_shared_state)
						else $fatal(1,"held unrelated owner changed during cached hit");
				@(negedge clk);
				assert(!grom_ack) else $fatal(1,"GROM ACK repeated on consumed request");
			end
			repeat(12) begin
				@(negedge clk);
				assert(!grom_ack) else $fatal(1,"held unchanged GROM request ACKed twice");
			end
			grom_req=1'b0;@(negedge clk);
		end
	endtask

	task automatic grom_front_suite;
		integer owner;
		integer timeout;
		integer shared_state;
		begin
			grom_full_read(26'h001200,26'h001200);
			grom_resident_stream(-1);
			$display("PASS GROM idle: 128 full-qword/byte-signature two-edge hits");
			for(owner=0;owner<4;owner++) begin
				case(owner)
					0: begin main_addr=22'h034500;main_req=1;end
					1: begin sound_addr=19'h032100;sound_req=1;end
					2: begin sample_addr=22'h054300;sample_bank=0;sample_req=1;end
					3: begin scan_addr=20'h00400;scan_req=1;end
				endcase
				timeout=0;
				while(!(model_active && model_read) && timeout<3000) begin @(negedge clk);timeout++;end
				assert(model_active && model_read) else $fatal(1,"concurrent read did not launch");
				hold_read_returns=1;shared_state=integer'(dut.state);
				if(owner==3) scan_req=0;
				grom_resident_stream(shared_state);
				hold_read_returns=0;timeout=0;
				case(owner)
					0: begin
						while(!main_ack && timeout<3000) begin @(negedge clk);timeout++;end
						assert(main_ack) else $fatal(1,"main client starved");main_req=0;
					end
					1: begin
						while(!sound_ack && timeout<3000) begin @(negedge clk);timeout++;end
						assert(sound_ack) else $fatal(1,"sound client starved");sound_req=0;
					end
					2: begin
						while(!sample_ack && timeout<3000) begin @(negedge clk);timeout++;end
						assert(sample_ack) else $fatal(1,"sample client starved");sample_req=0;
					end
					3: begin
						while(!scan_last && timeout<3000) begin @(negedge clk);timeout++;end
						assert(scan_last) else $fatal(1,"scan client starved");
					end
				endcase
				repeat(3) @(negedge clk);
				$display("PASS GROM unrelated read owner=%0d shared_state=%0d",owner,shared_state);
			end

			// More than one buffered qword forces a real multi-beat writeback.
			for(owner=0;owner<16;owner++) vram_write(20'(owner),16'h5a00+16'(owner),2'b11);
			vram_req=1;vram_we=0;vram_addr=20'd3;timeout=0;
			while(!(dut.state==MEM_ST_VRAM_BURST_WRITE && model_active && !model_read && DDRAM_BUSY) && timeout<3000)
				begin @(negedge clk);timeout++;end
			assert(timeout<3000) else $fatal(1,"writeback owner was not reached");
			force_waitrequest=1;
			grom_resident_stream(19);
			force_waitrequest=0;timeout=0;
			while(!vram_ack && timeout<3000) begin @(negedge clk);timeout++;end
			assert(vram_ack && vram_rdata==16'h5a03) else $fatal(1,"writeback/read data or progress failed");
			vram_req=0;@(negedge clk);
			$display("PASS GROM independent of stalled VRAM writeback");

			// Different bank/tag and explicit loaded-size wrap, with full qwords.
			grom_full_read(26'h1012340,26'h1012340);
			grom_full_read(26'h0012340,26'h0012340);
			grom_full_read(26'h207ffff,26'h207ffff);
			grom_full_read(26'h2080000,26'h0000000);
			grom_full_read(26'h2100007,26'h0080007);
			grom_full_read(26'h3ffffff,26'h1f7ffff);
			grom_full_read(26'h001200,26'h001200);
			$display("PASS GROM bank, tag alias, size wrap and full-qword payload");

			// Cancel during local probe. No return from canceled ownership.
			grom_req=1;grom_addr=26'h001208;@(negedge clk);
			assert(dut.grom_front_state==3'd1) else $fatal(1,"probe cancellation not exercised");
			quiesce=1;@(negedge clk);
			assert(!grom_ack && dut.grom_front_state==3'd0) else $fatal(1,"probe survived quiesce");
			repeat(3) @(negedge clk);
			quiesce=0;
			grom_full_read(26'h001208,26'h001208);

			// Cancel at RESPONSE: a pre-edge ACK is ignored by board reset;
			// no stale ACK may survive that cancel edge or the quiescent span.
			grom_req=1;grom_addr=26'h001210;@(negedge clk);@(negedge clk);
			assert(grom_ack && dut.grom_front_state==3'd2) else $fatal(1,"response cancellation not exercised");
			quiesce=1;@(negedge clk);
			assert(!grom_ack && dut.grom_front_state==3'd0) else $fatal(1,"response survived cancel edge");
			repeat(3) begin @(negedge clk);assert(!grom_ack) else $fatal(1,"ACK while quiescent");end
			quiesce=0;grom_full_read(26'h001210,26'h001210);

			// Last refill data is pending at the same edge as a new-image start.
			grom_req=1;grom_addr=26'h009800;timeout=0;
			while(!(dut.state==5'd15 && dut.grom_prefetch_beat==4'd15 && core_DDRAM_DOUT_READY) && timeout<3000)
				begin @(negedge clk);timeout++;end
			assert(timeout<3000) else $fatal(1,"refill-last cancellation not exercised");
			ioctl_download=1;grom_image_epoch=8'h93;
			@(negedge clk);
			assert(!grom_ack && !dut.grom_read_ahead_valid) else $fatal(1,"old refill published at reload");
			repeat(3) @(negedge clk);
			ioctl_download=0;timeout=0;
			while(!rom_loaded && timeout<3000) begin @(negedge clk);timeout++;end
			assert(rom_loaded) else $fatal(1,"reload did not release core");
			grom_full_read(26'h009800,26'h009800);
			$display("PASS GROM probe/response cancellation and refill-final-beat reload discard");
			$display("PASS: independent GROM front contract, full payloads and concurrent owners");
		end
	endtask

	task automatic sound_read(input logic [18:0] address, input logic [7:0] expected);
		integer timeout;
		begin
			sound_addr = address;
			sound_req = 1'b1;
			timeout = 0;
			while (!sound_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (sound_ack && sound_rdata == expected)
				else $fatal(1, "sound read %x returned %x", address, sound_rdata);
			sound_req = 1'b0;
			@(negedge clk);
		end
	endtask

	task automatic sample_read(
		input logic [1:0] bank,
		input logic [21:0] address,
		input logic [15:0] expected
	);
		integer timeout;
		begin
			sample_bank = bank;
			sample_addr = address;
			sample_req = 1'b1;
			timeout = 0;
			while (!sample_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (sample_ack && sample_rdata == expected)
				else $fatal(1, "sample read bank %0d addr %x returned %x",
					bank, address, sample_rdata);
			sample_req = 1'b0;
			@(negedge clk);
		end
	endtask

	task automatic grom_read_pair_no_gap(
		input logic [25:0] address0,
		input logic [7:0] expected0,
		input logic [25:0] address1,
		input logic [7:0] expected1
	);
		integer timeout;
		begin
			grom_addr = address0;
			grom_req = 1'b1;
			timeout = 0;
			while (!grom_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (grom_ack &&
				grom_rdata[address0[2:0] * 8 +: 8] == expected0)
				else $fatal(1, "first no-gap GROM read failed");
			grom_addr = address1;
			@(negedge clk);
			timeout = 0;
			while (!grom_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (grom_ack &&
				grom_rdata[address1[2:0] * 8 +: 8] == expected1)
				else $fatal(1, "second no-gap GROM read failed");
			grom_req = 1'b0;
			@(negedge clk);
		end
	endtask

	task automatic sample_read_pair_no_gap(
		input logic [21:0] address0,
		input logic [15:0] expected0,
		input logic [21:0] address1,
		input logic [15:0] expected1
	);
		integer timeout;
		begin
			sample_bank = 2'd0;
			sample_addr = address0;
			sample_req = 1'b1;
			timeout = 0;
			while (!sample_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (sample_ack && sample_rdata == expected0)
				else $fatal(1, "first no-gap sample read failed");
			sample_addr = address1;
			@(negedge clk);
			timeout = 0;
			while (!sample_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (sample_ack && sample_rdata == expected1)
				else $fatal(1, "second no-gap sample read failed");
			sample_req = 1'b0;
			@(negedge clk);
		end
	endtask

	// Model a synchronous producer which only reacts to ACK on a clock edge.
	// It deliberately holds the completed payload for three more clocks, then
	// advances the address without ever dropping req. The memory must neither
	// duplicate the held transfer nor require a low bubble for the next one.
	task automatic main_read_pair_registered_hold(
		input logic [21:0] address0,
		input logic [31:0] expected0,
		input logic [21:0] address1,
		input logic [31:0] expected1
	);
		integer timeout;
		integer ack_count;
		begin
			@(posedge clk);
			main_addr <= address0;
			main_req <= 1'b1;
			timeout = 0;
			ack_count = 0;
			while (ack_count == 0 && timeout < 100) begin
				@(negedge clk);
				if (main_ack) begin
					ack_count = ack_count + 1;
					assert (main_rdata == expected0)
						else $fatal(1, "registered first main read returned %x", main_rdata);
				end
				timeout = timeout + 1;
			end
			assert (ack_count == 1)
				else $fatal(1, "registered first main read timed out");

			repeat (3) begin
				@(negedge clk);
				if (main_ack)
					ack_count = ack_count + 1;
			end
			assert (ack_count == 1)
				else $fatal(1, "unchanged registered request was ACKed twice");

			// This NBA deliberately changes the payload as a registered producer
			// would, while req remains asserted.
			@(posedge clk);
			main_addr <= address1;
			timeout = 0;
			while (ack_count == 1 && timeout < 100) begin
				@(negedge clk);
				if (main_ack) begin
					ack_count = ack_count + 1;
					assert (main_rdata == expected1)
						else $fatal(1, "registered second main read returned %x", main_rdata);
				end
				timeout = timeout + 1;
			end
			assert (ack_count == 2)
				else $fatal(1, "changed registered request was not accepted");

			repeat (3) begin
				@(negedge clk);
				if (main_ack)
					ack_count = ack_count + 1;
			end
			assert (ack_count == 2)
				else $fatal(1, "second unchanged registered request was ACKed twice");
			@(posedge clk);
			main_req <= 1'b0;
			@(negedge clk);
		end
	endtask

	task automatic vram_write(
		input logic [19:0] address,
		input logic [15:0] value,
		input logic [1:0] enables
	);
		integer timeout;
		logic saw_capture;
		logic saw_fast;
		logic [63:0] expected_payload;
		logic [7:0] expected_be;
		logic [3:0] buffer_index;
		logic [27:0] expected_line;
		logic [27:0] expected_block;
		begin
			expected_payload = 64'd0;
			expected_be = 8'd0;
			expected_payload[address[1:0] * 16 +: 16] =
				{value[7:0], value[15:8]};
			expected_be[address[1:0] * 2 +: 2] = {enables[0], enables[1]};
			buffer_index = address[5:2];
			expected_line = VRAM_BASE + {7'd0, address[19:2], 3'b000};
			expected_block = {expected_line[27:7], 7'b000_0000};
			vram_addr = address;
			vram_wdata = value;
			vram_be = enables;
			vram_we = 1'b1;
			vram_req = 1'b1;
			timeout = 0;
			saw_capture = 1'b0;
			saw_fast = 1'b0;
			while (!vram_ack && timeout < 100) begin
				@(negedge clk);
				if (dut.state == MEM_ST_CAPTURE && dut.op_client == 3'd4)
					saw_capture = 1'b1;
				if (dut.state == MEM_ST_DISPATCH && dut.op_client == 3'd4) begin
					assert (saw_capture && dut.op_write &&
						dut.op_wdata == expected_payload && dut.op_be == expected_be)
						else $fatal(1, "VRAM payload capture stage packed the wrong data/BE");
				end
				timeout = timeout + 1;
			end
			if (vram_ack && !saw_capture &&
				(dut.state == MEM_ST_IDLE || dut.state == MEM_ST_VRAM_BURST_WRITE) &&
				dut.vram_fast_pending && dut.vram_fast_base_q == expected_block)
				saw_fast = 1'b1;
			assert (vram_ack && (saw_capture || saw_fast))
				else $fatal(1, "VRAM write timed out or used no valid path");
			if (saw_fast) begin
				assert (dut.vram_fast_index_q == buffer_index &&
					(dut.vram_fast_be_q & expected_be) == expected_be)
					else $fatal(1, "VRAM fast write lost byte enables");
				for (integer byte_index = 0; byte_index < 8; byte_index = byte_index + 1)
					if (expected_be[byte_index])
						assert (dut.vram_fast_data_q[byte_index * 8 +: 8] ==
							expected_payload[byte_index * 8 +: 8])
							else $fatal(1, "VRAM fast write packed byte %0d incorrectly", byte_index);
			end
			vram_req = 1'b0;
			vram_we = 1'b0;
			@(negedge clk);
		end
	endtask

	task automatic vram_read(input logic [19:0] address, input logic [15:0] expected);
		integer timeout;
		begin
			vram_addr = address;
			vram_we = 1'b0;
			vram_req = 1'b1;
			timeout = 0;
			while (!vram_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (vram_ack && vram_rdata == expected)
				else $fatal(1, "VRAM read %x returned %x", address, vram_rdata);
			vram_req = 1'b0;
			@(negedge clk);
		end
	endtask

	task automatic qwrite_pair_no_gap(
		input logic [17:0] address,
		input logic [63:0] first_data,
		input logic [7:0] first_be,
		input logic [63:0] second_data,
		input logic [7:0] second_be
	);
		integer timeout;
		integer ack_count;
		begin
			vram_qwrite_addr = address;
			vram_qwrite_data = first_data;
			vram_qwrite_be = first_be;
			vram_qwrite_token = 1'b0;
			vram_qwrite_req = 1'b1;
			timeout = 0;
			ack_count = 0;
			while (!vram_qwrite_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (vram_qwrite_ack)
				else $fatal(1, "first gathered qword timed out");
			ack_count = ack_count + 1;
			// Keep request asserted, but require the first one-cycle ACK to
			// retire before presenting the next token.  This prevents the
			// test from accidentally counting one level twice.
			@(negedge clk);
			assert (!vram_qwrite_ack)
				else $fatal(1, "gathered qword ACK did not pulse low");
			vram_qwrite_data = second_data;
			vram_qwrite_be = second_be;
			vram_qwrite_token = 1'b1;
			timeout = 0;
			while (!vram_qwrite_ack && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (vram_qwrite_ack)
				else $fatal(1, "second same-address gathered qword timed out");
			ack_count = ack_count + 1;
			@(negedge clk);
			vram_qwrite_req = 1'b0;
			vram_qwrite_be = 8'd0;
			assert (ack_count == 2)
				else $fatal(1, "gathered qword pair ACK count mismatch");
		end
	endtask

	task automatic dispatch_combine_then_scan(
		input logic [19:0] address,
		input logic [15:0] prior_value,
		input logic [15:0] new_value
	);
		integer timeout;
		integer ack_count;
		integer beat;
		logic [63:0] prior_payload;
		logic [63:0] expected_payload;
		logic [7:0] expected_be;
		logic [3:0] buffer_index;
		logic [19:0] row_address;
		logic [27:0] expected_line;
		logic [27:0] expected_block;
		logic [27:0] scan_base;
		logic [135:0] held_stage;
		begin
			// Seed a compatible retained window through the normal one-edge path.
			// The force below suppresses only that shortcut for the following write,
			// making the otherwise equivalent ST_DISPATCH fallback observable.
			vram_write(address, prior_value, 2'b11);
			buffer_index = address[5:2];
			prior_payload = 64'd0;
			prior_payload[address[1:0] * 16 +: 16] =
				{prior_value[7:0], prior_value[15:8]};
			expected_payload = 64'd0;
			expected_payload[address[1:0] * 16 +: 16] =
				{new_value[7:0], new_value[15:8]};
			expected_be = 8'd0;
			expected_be[address[1:0] * 2 +: 2] = 2'b11;
			expected_line = VRAM_BASE + {7'd0, address[19:2], 3'b000};
			expected_block = {expected_line[27:7], 7'b000_0000};
			row_address = {address[19:9], 9'd0};
			scan_base = VRAM_BASE + {7'd0, row_address, 1'b0};
			assert (dut.vram_write_buffer_valid && !dut.vram_fast_pending &&
				dut.vram_write_buffer_base == expected_block &&
				dut.vram_write_buffer_data[collect_slot(buffer_index)]
					[address[1:0] * 16 +: 16] ==
					prior_payload[address[1:0] * 16 +: 16])
				else $fatal(1, "dispatch regression did not seed its retained window");

			dispatch_commit_watch = 1'b1;
			vram_addr = address;
			vram_wdata = new_value;
			vram_be = 2'b11;
			vram_we = 1'b1;
			vram_req = 1'b1;
		force dut.vram_fast_write = 1'b0;
			timeout = 0;
			while (dut.state != MEM_ST_DISPATCH && timeout < 100) begin
				@(negedge clk);
				timeout = timeout + 1;
			end
			assert (dut.state == MEM_ST_DISPATCH && dut.op_client == 3'd4 &&
				dut.op_write && dut.op_wdata == expected_payload &&
				dut.op_be == expected_be && !vram_ack &&
				!dut.vram_fast_pending && dispatch_commit_count == 0)
				else $fatal(1, "directed VRAM request did not reach uncommitted dispatch");
			assert (dut.vram_write_buffer_data[collect_slot(buffer_index)]
				[address[1:0] * 16 +: 16] ==
				prior_payload[address[1:0] * 16 +: 16])
				else $fatal(1, "dispatch payload committed before producer ACK");
		release dut.vram_fast_write;

			@(posedge clk); #1;
			ack_count = vram_ack ? 1 : 0;
			assert (vram_ack && dut.state == MEM_ST_IDLE &&
				dut.vram_fast_pending && dispatch_commit_count == 0 &&
				dut.vram_fast_base_q == expected_block &&
				dut.vram_fast_index_q == buffer_index &&
				dut.vram_fast_select_q == (32'b1 << collect_slot(buffer_index)) &&
				dut.vram_fast_data_q == expected_payload &&
				dut.vram_fast_be_q == expected_be)
				else $fatal(1, "dispatch ACK did not retain the exact pending payload");
			assert (dut.vram_write_buffer_data[collect_slot(buffer_index)]
				[address[1:0] * 16 +: 16] ==
				prior_payload[address[1:0] * 16 +: 16])
				else $fatal(1, "dispatch ACK and combine-window commit collapsed together");
			held_stage = {dut.vram_fast_base_q, dut.vram_fast_index_q,
				dut.vram_fast_select_q, dut.vram_fast_data_q, dut.vram_fast_be_q};

			@(negedge clk);
			vram_req = 1'b0;
			vram_we = 1'b0;
			quiesce = 1'b1;
			repeat (3) begin
				@(posedge clk); #1;
				if (vram_ack)
					ack_count = ack_count + 1;
				assert (dut.vram_fast_pending && dispatch_commit_count == 0 &&
					{dut.vram_fast_base_q, dut.vram_fast_index_q,
					 dut.vram_fast_select_q, dut.vram_fast_data_q,
					 dut.vram_fast_be_q} == held_stage &&
					dut.vram_write_buffer_data[collect_slot(buffer_index)]
						[address[1:0] * 16 +: 16] ==
						prior_payload[address[1:0] * 16 +: 16])
					else $fatal(1, "pending dispatch payload changed during quiesce");
			end

			// Present a same-row scan before releasing the held stage. ST_IDLE must
			// commit once, flush the conflicting window, and only then accept scanout.
			@(negedge clk);
			scan_addr = row_address;
			scan_req = 1'b1;
			quiesce = 1'b0;
			@(posedge clk); #1;
			if (vram_ack)
				ack_count = ack_count + 1;
			assert (dispatch_commit_count == 1 && !dut.vram_fast_pending &&
				!scan_accept && dut.vram_write_buffer_data[collect_slot(buffer_index)]
					[address[1:0] * 16 +: 16] ==
					expected_payload[address[1:0] * 16 +: 16])
				else $fatal(1, "pending dispatch payload did not commit exactly once");

			timeout = 0;
			while (!scan_accept && timeout < 1000) begin
				@(posedge clk); #1;
				if (vram_ack)
					ack_count = ack_count + 1;
				assert (dispatch_commit_count == 1)
					else $fatal(1, "dispatch payload committed more than once");
				timeout = timeout + 1;
			end
			assert (scan_accept && !dut.vram_write_buffer_valid &&
				vram_memory[address * 2] == new_value[15:8] &&
				vram_memory[address * 2 + 1] == new_value[7:0])
				else $fatal(1, "same-row scan passed the retained dispatch payload");
			@(negedge clk);
			scan_req = 1'b0;

			beat = 0;
			timeout = 0;
			while (beat < SCAN_BURST_WORDS && timeout < 2000) begin
				@(posedge clk); #1;
				if (vram_ack)
					ack_count = ack_count + 1;
				assert (dispatch_commit_count == 1)
					else $fatal(1, "scan replayed the staged dispatch commit");
				if (scan_data_valid) begin
					assert (scan_rdata == model_line(scan_base + 28'(beat * 8)) &&
						scan_last == (beat == SCAN_BURST_WORDS - 1))
						else $fatal(1, "same-row dispatch scan mismatch at beat %0d", beat);
					beat = beat + 1;
				end
				timeout = timeout + 1;
			end
			assert (beat == SCAN_BURST_WORDS && ack_count == 1 &&
				dispatch_commit_count == 1)
				else $fatal(1, "dispatch/scan completion counts ack=%0d commit=%0d beat=%0d",
					ack_count, dispatch_commit_count, beat);
			dispatch_commit_watch = 1'b0;
		end
	endtask

	task automatic second_row_combine_then_linear_scan;
		integer timeout;
		integer beat;
		integer transaction_start;
		localparam logic [19:0] WRITE_ADDRESS = 20'h00440;
		localparam logic [19:0] SCAN_ADDRESS = 20'h00380;
		localparam logic [15:0] WRITE_VALUE = 16'h5aa5;
		logic [27:0] scan_base;
		logic [27:0] write_byte_addr;
		begin
			// The aligned active-window scan beginning at row 1, x=384 covers
			// the tail of row 1 and part of row 2. Retain a write in row 2 and
			// prove the linear scan cannot pass it.
			vram_write(WRITE_ADDRESS, WRITE_VALUE, 2'b11);
			write_byte_addr = VRAM_BASE + {7'd0, WRITE_ADDRESS, 1'b0};
			assert (dut.vram_write_buffer_valid &&
				dut.vram_write_buffer_base[27:10] ==
				write_byte_addr[27:10])
				else $fatal(1, "cross-row scan test did not retain its write window");
			transaction_start = ddr_transactions;
			scan_base = VRAM_BASE + {7'd0, SCAN_ADDRESS, 1'b0};
			scan_addr = SCAN_ADDRESS;
			scan_req = 1'b1;
			@(posedge clk); #1;
			assert (!scan_accept && dut.vram_write_buffer_valid)
				else $fatal(1, "linear scan accepted before second-row window flush");
			timeout = 0;
			while (!scan_accept && timeout < 1000) begin
				@(posedge clk); #1;
				timeout = timeout + 1;
			end
			assert (scan_accept && !dut.vram_write_buffer_valid &&
				vram_memory[WRITE_ADDRESS * 2] == WRITE_VALUE[15:8] &&
				vram_memory[WRITE_ADDRESS * 2 + 1] == WRITE_VALUE[7:0])
				else $fatal(1, "linear scan passed stale second-row data");
			@(negedge clk);
			scan_req = 1'b0;
			beat = 0;
			timeout = 0;
			while (beat < SCAN_BURST_WORDS && timeout < 2000) begin
				@(posedge clk); #1;
				if (scan_data_valid) begin
					assert (scan_rdata == model_line(scan_base + 28'(beat * 8)) &&
						scan_last == (beat == SCAN_BURST_WORDS - 1))
						else $fatal(1, "linear cross-row scan mismatch at beat %0d", beat);
					beat = beat + 1;
				end
				timeout = timeout + 1;
			end
			assert (beat == SCAN_BURST_WORDS &&
				ddr_transactions == transaction_start + 2)
				else $fatal(1, "linear scan used wrong write/read transaction count");
		end
	endtask

	integer transaction_snapshot;
	integer fairness_timeout;
	integer reset_timeout;
	integer reset_ack_count;
	integer scan_beat_count;
	logic scan_previous_valid;
	logic terminator_dummy_seen;
	logic [4:0] fairness_seen;
`include "itech32_write_reset_probe.svh"
`ifdef ITECH32_WRITE_OVERLAP
`include "itech32_write_overlap_tasks.svh"
`endif
	initial begin
		for (init_index = 0; init_index < 65536; init_index = init_index + 1)
			low_memory[init_index] = 8'd0;
		for (init_index = 0; init_index < 4096; init_index = init_index + 1)
			vram_memory[init_index] = 8'h00;

		repeat (5) @(negedge clk);
		reset = 1'b0;
		ioctl_download = 1'b1;
		loader_word(27'd0, 16'h2211);
		loader_word(27'd2, 16'h4433);
		loader_word(27'd4, 16'h6655);
		loader_word(27'd6, 16'h8877);
		while (ioctl_wait)
			@(negedge clk);
		ioctl_download = 1'b0;
		while (!rom_loaded)
			@(negedge clk);
		assert (vector_write_count == 32 &&
			captured_vectors[0] == 32'h1122_3344 &&
			captured_vectors[1] == 32'h5566_7788)
			else $fatal(1, "ordinary-download reset-vector copy failed count=%0d %x %x",
				vector_write_count, captured_vectors[0], captured_vectors[1]);
		for (init_index = 0; init_index < 32; init_index = init_index + 1)
			assert ({vram_memory[init_index * 2],
				vram_memory[init_index * 2 + 1]} == 16'h00ff)
				else $fatal(1, "framebuffer clear produced wrong logical pixel %0d", init_index);

		// MiSTer sends DIP updates as a separate index-254 download.  It must
		// neither recopy vectors nor clear/release the already running ROM.
		transaction_snapshot = ddr_transactions;
		ioctl_index = 16'h00fe;
		ioctl_download = 1'b1;
		loader_word(27'd0, 16'h000b);
		loader_word(27'd2, 16'h0000);
		loader_word(27'd4, 16'h0000);
		loader_word(27'd6, 16'h0000);
		ioctl_download = 1'b0;
		repeat (20) @(negedge clk);
		assert (rom_loaded && vector_write_count == 32 &&
			ddr_transactions == transaction_snapshot)
			else $fatal(1, "DIP download disturbed loaded ROM state");

		// The loader index is 16 bits in Main_MiSTer. An extended index whose
		// low byte is zero must not alias the ROM stream.
		ioctl_index = 16'h0100;
		ioctl_download = 1'b1;
		loader_word(27'd0, 16'hbeef);
		ioctl_download = 1'b0;
		repeat (20) @(negedge clk);
		assert (rom_loaded && vector_write_count == 32 &&
			ddr_transactions == transaction_snapshot)
			else $fatal(1, "extended ioctl index aliased ROM index zero");
		ioctl_index = 16'h0000;
		if ($test$plusargs("EARLY_RESET_PROBE")) begin
			early_write_reset_probe();
			$finish;
		end
`ifdef ITECH32_WRITE_OVERLAP
		if ($test$plusargs("WRITE_OVERLAP_ONLY")) begin
			write_overlap_suite();
			$finish;
		end
`endif
		if($test$plusargs("GROM_FRONT_ONLY")) begin
			grom_front_suite();
			$finish;
		end

		main_read(22'd0, 32'h1122_3344);
		void'($value$plusargs("EXPECT_MAIN_HIT_EDGES=%d",expected_main_hit_edges));
		transaction_snapshot = ddr_transactions;
		main_read(22'd2, 32'h1122_3344,expected_main_hit_edges);
		main_read(22'd4, 32'h5566_7788,expected_main_hit_edges);
		main_read(22'h00007c, 32'h0000_0000,expected_main_hit_edges);
		assert (ddr_transactions == transaction_snapshot)
			else $fatal(1, "main 128-byte read-ahead line missed unexpectedly");
		main_read(22'h000080, 32'h0000_0000);
		assert (ddr_transactions == transaction_snapshot + 1)
			else $fatal(1, "main read-ahead cache did not refill at a line boundary");

		grom_read(26'h001234, model_byte(GROM_BASE + 28'h001234));
		transaction_snapshot = ddr_transactions;
		// Cross the old eight-byte cache boundary while remaining in the new
		// 128-byte M10K line. This must not issue a second DDR transaction.
		grom_cached_fast_read(26'h00127f, model_byte(GROM_BASE + 28'h00127f));
		assert (ddr_transactions == transaction_snapshot)
			else $fatal(1, "GROM line cache missed unexpectedly");
		grom_read_pair_no_gap(26'h00223f, model_byte(GROM_BASE + 28'h00223f),
			26'h002240, model_byte(GROM_BASE + 28'h002240));
		grom_read(26'h207ffff, model_byte(GROM_BASE + 28'h207ffff));
		grom_read(26'h2080000, model_byte(GROM_BASE));
		grom_read(26'h2100000, model_byte(GROM_BASE + 28'h0080000));
		sound_read(19'h02345, model_byte(SOUND_BASE + 28'h02345));
		sound_read(19'h47ffe, model_byte(SOUND_BASE + 28'h47ffe));
		sound_read(19'h47fff, 8'h20);
		sample_read(2'd0, 22'h001020,
			{model_byte(SAMPLE0_BASE + 28'h001020), model_byte(SAMPLE0_BASE + 28'h001021)});
		sample_read(2'd3, 22'h002030,
			{model_byte(SAMPLE3_BASE + 28'h002030), model_byte(SAMPLE3_BASE + 28'h002031)});
		sample_read_pair_no_gap(22'h00303e,
			{model_byte(SAMPLE0_BASE + 28'h00303e), model_byte(SAMPLE0_BASE + 28'h00303f)},
			22'h003040,
			{model_byte(SAMPLE0_BASE + 28'h003040), model_byte(SAMPLE0_BASE + 28'h003041)});
		transaction_snapshot = ddr_transactions;
		sample_read(2'd1, 22'h001000, 16'd0);
		assert (ddr_transactions == transaction_snapshot)
			else $fatal(1, "empty sample bank generated DDR traffic");

		// Time Killers packages its three even-lane sample ROMs in ES bank 2.
		// The logical bank address starts at the same 4 MiB sample-region base;
		// every other ES bank is open and must avoid DDR traffic.
		timekill_mode = 1'b1;
		sample_read(2'd2, 22'h001020,
			{model_byte(SAMPLE0_BASE + 28'h001020),
			 model_byte(SAMPLE0_BASE + 28'h001021)});
		for (init_index = 0; init_index < 4; init_index = init_index + 1) begin
			if (init_index != 2) begin
				transaction_snapshot = ddr_transactions;
				sample_read(2'(init_index), 22'h001000, 16'd0);
				assert (ddr_transactions == transaction_snapshot)
					else $fatal(1, "Time Killers empty sample bank %0d used DDR",
						init_index);
			end
		end
		timekill_mode = 1'b0;

		vram_write(20'd5, 16'habcd, 2'b11);
		vram_read(20'd5, 16'habcd);
		vram_write(20'd5, 16'h1200, 2'b10);
		vram_read(20'd5, 16'h12cd);
		// Consecutive gathered qwords may retain the request level and address.
		// The token must make the second payload independently eligible, and its
		// partial lane update must merge into the first qword exactly.
		qwrite_pair_no_gap(18'd64,
			64'h8877_6655_4433_2211, 8'hff,
			64'hddcc_bbaa_9988_7766, 8'h30);
		vram_read(20'd256, 16'h1122);
		vram_read(20'd258, 16'haabb);
		dispatch_combine_then_scan(20'h00240, 16'h1357, 16'h2468);
		second_row_combine_then_linear_scan();

		// Four adjacent pixels occupy one 64-bit DDR beat. They must merge
		// locally with no physical transaction, then a conflicting read must
		// flush exactly one combined write before issuing its read.
		transaction_snapshot = ddr_transactions;
		vram_write(20'd8, 16'h1020, 2'b11);
		vram_write(20'd9, 16'h3040, 2'b11);
		vram_write(20'd10, 16'h5060, 2'b11);
		vram_write(20'd11, 16'h7080, 2'b11);
		assert (ddr_transactions == transaction_snapshot)
			else $fatal(1, "adjacent VRAM pixels were not write-combined");
		vram_read(20'd10, 16'h5060);
		assert (ddr_transactions == transaction_snapshot + 2)
			else $fatal(1, "combined VRAM beat used %0d DDR operations instead of write+read",
				ddr_transactions - transaction_snapshot);

		// Fill ten qwords within one 128-byte write window. The conflict read
		// must produce one fixed-address ten-beat Avalon burst, not ten commands.
		transaction_snapshot = ddr_transactions;
		for (init_index = 16; init_index < 56; init_index = init_index + 1)
			vram_write(20'(init_index), 16'h8000 + 16'(init_index), 2'b11);
		assert (ddr_transactions == transaction_snapshot)
			else $fatal(1, "multi-qword VRAM window wrote DDR before a conflict");
		vram_read(20'd35, 16'h8023);
		assert (ddr_transactions == transaction_snapshot + 2 &&
			last_write_burst_count == 8'd10 &&
			last_write_burst_addr == 29'h065c_0004)
			else $fatal(1, "VRAM window did not use one ten-beat burst count=%0d addr=%x tx=%0d",
				last_write_burst_count, last_write_burst_addr,
				ddr_transactions - transaction_snapshot);
		for (init_index = 16; init_index < 56; init_index = init_index + 1) begin
			assert (vram_memory[init_index * 2] == (8'h80) &&
				vram_memory[init_index * 2 + 1] == init_index[7:0])
				else $fatal(1, "VRAM burst payload mismatch at pixel %0d: %x %x",
					init_index, vram_memory[init_index * 2],
					vram_memory[init_index * 2 + 1]);
		end

		if ($test$plusargs("FASTPATH_ONLY")) begin
			$display("PASS: two-edge independent GROM hit and retained VRAM write-combine paths");
			$finish;
		end

		// A scanline is one accepted DDR command followed by the exact aligned
		// active-window qword count. Independent reads cannot meet SFTM's 8 MHz
		// raster-line deadline.
		transaction_snapshot = ddr_transactions;
		scan_addr = 19'd0;
		scan_req = 1'b1;
		while (!scan_accept)
			@(negedge clk);
		scan_req = 1'b0;
		scan_beat_count = 0;
		scan_previous_valid = 1'b0;
		while (scan_beat_count < SCAN_BURST_WORDS) begin
			@(negedge clk);
			if (scan_data_valid) begin
				if (scan_beat_count != 0)
					assert (scan_previous_valid)
						else $fatal(1, "scan burst inserted a bubble after beat %0d",
							scan_beat_count - 1);
				assert (scan_rdata == model_line(VRAM_BASE + 28'(scan_beat_count * 8)))
					else $fatal(1, "scan burst beat %0d payload mismatch", scan_beat_count);
				assert (scan_last == (scan_beat_count == SCAN_BURST_WORDS - 1))
					else $fatal(1, "scan burst last mismatch at beat %0d", scan_beat_count);
				scan_beat_count = scan_beat_count + 1;
			end
			scan_previous_valid = scan_data_valid;
		end
		assert (ddr_transactions == transaction_snapshot + 1)
			else $fatal(1, "scanline used %0d DDR commands instead of one",
				ddr_transactions - transaction_snapshot);

		// An accepted burst cannot be cancelled at the Avalon boundary. If the
		// framework quiesces during it, drain all remaining beats but expose none
		// of the old response to scanout. A later row request starts normally.
		transaction_snapshot = ddr_transactions;
		scan_addr = 19'h00200;
		scan_req = 1'b1;
		while (!scan_accept)
			@(negedge clk);
		scan_req = 1'b0;
		scan_beat_count = 0;
		while (scan_beat_count < 8) begin
			@(negedge clk);
			if (scan_data_valid)
				scan_beat_count = scan_beat_count + 1;
		end
		quiesce = 1'b1;
		assert (!quiesce_ack)
			else $fatal(1, "quiesce acknowledged before accepted scan burst drained");
		while (model_active) begin
			@(negedge clk);
			assert (!scan_data_valid && !scan_last)
				else $fatal(1, "quiesced scan burst leaked a response beat");
			assert (!quiesce_ack)
				else $fatal(1, "quiesce acknowledged while DDR burst remained active");
		end
		repeat (3) begin
			@(negedge clk);
			assert (!scan_data_valid && !scan_last)
				else $fatal(1, "discarded scan burst completed visibly");
		end
		assert (ddr_transactions == transaction_snapshot + 1)
			else $fatal(1, "quiesced scan burst issued more than one command");
		assert (quiesce_ack && !core_DDRAM_RD && !core_DDRAM_WE)
			else $fatal(1, "DDR service did not acknowledge its drained quiescent state");
		quiesce = 1'b0;
		#1;
		assert (!quiesce_ack)
			else $fatal(1, "quiesce acknowledgement remained set after release");

		low_memory[16'h0120] = 8'hde;
		low_memory[16'h0121] = 8'had;
		low_memory[16'h0122] = 8'hbe;
		low_memory[16'h0123] = 8'hef;
		low_memory[16'h0128] = 8'h12;
		low_memory[16'h0129] = 8'h34;
		low_memory[16'h012a] = 8'h56;
		low_memory[16'h012b] = 8'h78;
		main_read_pair_registered_hold(
			22'h000120, 32'hdead_beef,
			22'h000128, 32'h1234_5678);

		// Five simultaneous cold misses must all complete under round-robin
		// service despite variable DDR latency.
		main_addr = 22'h000100;
		grom_addr = 26'h002100;
		sound_addr = 19'h003100;
		sample_bank = 2'd0;
		sample_addr = 22'h004100;
		vram_addr = 20'h000100;
		vram_we = 1'b0;
		main_req = 1'b1;
		grom_req = 1'b1;
		sound_req = 1'b1;
		sample_req = 1'b1;
		vram_req = 1'b1;
		fairness_seen = 5'd0;
		fairness_timeout = 0;
		while (fairness_seen != 5'b11111 && fairness_timeout < 300) begin
			@(negedge clk);
			if (main_ack) begin fairness_seen[0] = 1'b1; main_req = 1'b0; end
			if (grom_ack) begin fairness_seen[1] = 1'b1; grom_req = 1'b0; end
			if (sound_ack) begin fairness_seen[2] = 1'b1; sound_req = 1'b0; end
			if (sample_ack) begin fairness_seen[3] = 1'b1; sample_req = 1'b0; end
			if (vram_ack) begin fairness_seen[4] = 1'b1; vram_req = 1'b0; end
			fairness_timeout = fairness_timeout + 1;
		end
		assert (fairness_seen == 5'b11111)
			else $fatal(1, "DDR arbitration starved clients: %b", fairness_seen);

		// A download with no ioctl writes models MiSTer's fast staging path.
		// Start it while an old-image read is in flight: that completion must
		// be discarded and must not repopulate a cache after invalidation.
		for (init_index = 0; init_index < 8; init_index = init_index + 1)
			low_memory[16'h0208 + init_index] = 8'h20 + init_index[7:0];
		main_addr = 22'h000208;
		main_req = 1'b1;
		while (!(model_active && model_read))
			@(negedge clk);
		for (init_index = 0; init_index < 128; init_index = init_index + 1)
			low_memory[init_index] = 8'h80 + init_index[7:0];
		ioctl_download = 1'b1;
		for (init_index = 0; init_index < 8; init_index = init_index + 1)
			low_memory[16'h0208 + init_index] = 8'hd0 + init_index[7:0];
		main_req = 1'b0;
		while (model_active)
			@(negedge clk);
		repeat (3) @(negedge clk);
		ioctl_download = 1'b0;
		while (rom_loaded)
			@(negedge clk);
		while (!rom_loaded)
			@(negedge clk);
		assert (vector_write_count == 64 &&
			captured_vectors[0] == 32'h8081_8283 &&
			captured_vectors[31] == 32'hfcfd_feff)
			else $fatal(1, "fast-download reset-vector copy failed count=%0d %x %x",
				vector_write_count, captured_vectors[0], captured_vectors[31]);
		main_read(22'd0, 32'h8081_8283);
		main_read(22'h000208, 32'hd0d1_d2d3);

		// Interrupt a vector pass with a new fast reload. Its end boundary must
		// restart the next reset-vector sequence at address zero.
		ioctl_download = 1'b1;
		for (init_index = 0; init_index < 128; init_index = init_index + 1)
			low_memory[init_index] = 8'h20 + init_index[7:0];
		repeat (3) @(negedge clk);
		ioctl_download = 1'b0;
		while (!(vector_load_we && vector_load_addr == 5'd4))
			@(negedge clk);
		for (init_index = 0; init_index < 128; init_index = init_index + 1)
			low_memory[init_index] = 8'h40 + init_index[7:0];
		ioctl_download = 1'b1;
		repeat (20) begin
			@(negedge clk);
			assert (!rom_loaded)
				else $fatal(1, "rom_loaded rose during vector-interrupt reload");
		end
		ioctl_download = 1'b0;
		while (!rom_loaded)
			@(negedge clk);
		assert (vector_pass_count == 3 &&
			captured_vectors[0] == 32'h4041_4243 &&
			captured_vectors[31] == 32'hbcbd_bebf)
			else $fatal(1, "vector-interrupt reload did not restart cleanly passes=%0d",
				vector_pass_count);

		// Begin reload D on the exact edge reload C's final framebuffer-clear
		// write completes. The old completion must not win the rom_loaded NBA.
		ioctl_download = 1'b1;
		for (init_index = 0; init_index < 128; init_index = init_index + 1)
			low_memory[init_index] = 8'h60 + init_index[7:0];
		repeat (3) @(negedge clk);
		ioctl_download = 1'b0;
		while (!(dut.clear_active && dut.clear_line == 7 &&
			DDRAM_WE && !DDRAM_BUSY))
			@(negedge clk);
		for (init_index = 0; init_index < 128; init_index = init_index + 1)
			low_memory[init_index] = 8'h80 + init_index[7:0];
		ioctl_download = 1'b1;
		@(negedge clk);
		assert (!rom_loaded)
			else $fatal(1, "old clear completion released core during reload");
		repeat (20) begin
			@(negedge clk);
			assert (!rom_loaded)
				else $fatal(1, "rom_loaded rose during active fast reload");
		end
		ioctl_download = 1'b0;
		while (!rom_loaded)
			@(negedge clk);
		assert (vector_pass_count == 5 &&
			captured_vectors[0] == 32'h8081_8283 &&
			captured_vectors[31] == 32'hfcfd_feff)
			else $fatal(1, "collision reload vector copy failed passes=%0d %x %x",
				vector_pass_count, captured_vectors[0], captured_vectors[31]);
		main_read(22'd0, 32'h8081_8283);

		// Hold an old clear write busy across both edges of another fast
		// download. Releasing that stale write after the fall must not advance
		// the new clear counter or assert rom_loaded ahead of the new vectors.
		ioctl_download = 1'b1;
		for (init_index = 0; init_index < 128; init_index = init_index + 1)
			low_memory[init_index] = 8'ha0 + init_index[7:0];
		repeat (3) @(negedge clk);
		ioctl_download = 1'b0;
		while (!(dut.clear_active && dut.state == MEM_ST_ISSUE &&
			dut.op_client == 3'd7))
			@(negedge clk);
		force_waitrequest = 1'b1;
		for (init_index = 0; init_index < 128; init_index = init_index + 1)
			low_memory[init_index] = 8'hc0 + init_index[7:0];
		ioctl_download = 1'b1;
		repeat (5) begin
			@(negedge clk);
			assert (!rom_loaded)
				else $fatal(1, "held old clear released core during download");
		end
		ioctl_download = 1'b0;
		repeat (5) begin
			@(negedge clk);
			assert (!rom_loaded)
				else $fatal(1, "held old clear released core before new vectors");
		end
		force_waitrequest = 1'b0;
		while (!rom_loaded)
			@(negedge clk);
		assert (vector_pass_count == 7 &&
			captured_vectors[0] == 32'hc0c1_c2c3 &&
			captured_vectors[31] == 32'h3c3d_3e3f)
			else $fatal(1, "held-clear reload failed passes=%0d %x %x",
				vector_pass_count, captured_vectors[0], captured_vectors[31]);
		main_read(22'd0, 32'hc0c1_c2c3);

		// Quiesce after the SOUND miss has a registered grant but before payload
		// capture/DDR issue. SOUND now bypasses the ordinary selector, so its
		// cancellation boundary is ST_CAPTURE rather than a pending-mask snapshot.
		// The held request must retry exactly once after the boundary clears.
		transaction_snapshot = ddr_transactions;
		sound_addr = 19'h031a0;
		sound_req = 1'b1;
		while (!(dut.state == MEM_ST_CAPTURE && dut.op_client == 3'd2))
			@(negedge clk);
		assert (dut.sound_front_state == SOUND_FRONT_MISS_WAIT && !sound_ack)
			else $fatal(1, "SOUND capture-boundary request lost miss ownership");
		framework_reset = 1'b1;
		quiesce = 1'b1;
		repeat (3) @(negedge clk);
		assert (dut.state == MEM_ST_IDLE && !sound_ack &&
			!DDRAM_RD && !DDRAM_WE && ddr_transactions == transaction_snapshot)
			else $fatal(1, "quiesced SOUND grant escaped to DDR or ACK");
		framework_reset = 1'b0;
		quiesce = 1'b0;
		fairness_timeout = 0;
		while (!sound_ack && fairness_timeout < 100) begin
			@(negedge clk);
			fairness_timeout = fairness_timeout + 1;
		end
		assert (sound_ack && sound_rdata == model_byte(SOUND_BASE + 28'h031a0) &&
			ddr_transactions == transaction_snapshot + 1)
			else $fatal(1, "SOUND capture-boundary request did not retry exactly once");
		sound_req = 1'b0;
		@(negedge clk);

		// A read already accepted by the real MiSTer safe terminator must drain
		// across framework reset. Persistent loader state remains valid and the
		// scheduler must accept a later request after the terminator unlocks.
		low_memory[16'h0180] = 8'h91;
		low_memory[16'h0181] = 8'h82;
		low_memory[16'h0182] = 8'h73;
		low_memory[16'h0183] = 8'h64;
		main_addr = 22'h000180;
		main_req = 1'b1;
		while (!(model_active && model_read))
			@(negedge clk);
		framework_reset = 1'b1;
		quiesce = 1'b1;
		main_req = 1'b0;
		while (model_active)
			@(negedge clk);
		repeat (4) @(negedge clk);
		assert (rom_loaded)
			else $fatal(1, "framework reset cleared persistent ROM state");
		framework_reset = 1'b0;
		quiesce = 1'b0;
		repeat (4) @(negedge clk);
		main_read(22'h000180, 32'h9182_7364);

		// If reset arrives while the scheduler is waiting to issue (RD/WE have
		// never reached the terminator), quiesce must cancel that operation.  A
		// masked command must not appear later or leave the scheduler waiting for
		// readdatavalid forever.
		transaction_snapshot = ddr_transactions;
		force_waitrequest = 1'b1;
		sound_addr = 19'h031c0;
		sound_req = 1'b1;
		while (dut.state != MEM_ST_ISSUE)
			@(negedge clk);
		assert (!core_DDRAM_RD && !core_DDRAM_WE)
			else $fatal(1, "pre-issue reset test already asserted a command");
		framework_reset = 1'b1;
		quiesce = 1'b1;
		sound_req = 1'b0;
		repeat (5) @(negedge clk);
		assert (dut.state == MEM_ST_IDLE && !DDRAM_RD && !DDRAM_WE &&
			ddr_transactions == transaction_snapshot)
			else $fatal(1, "pre-issue command escaped through reset terminator");
		force_waitrequest = 1'b0;
		framework_reset = 1'b0;
		quiesce = 1'b0;
		repeat (5) @(negedge clk);
		sound_read(19'h031c0, model_byte(SOUND_BASE + 28'h031c0));

		// A buffered write flush stalled at framework reset is replaced by a
		// zero-BE beat by the safe terminator. The already-acknowledged local
		// write must remain buffered and retry durably after reset.
		vram_memory[12'h400] = 8'ha5;
		vram_memory[12'h401] = 8'h5a;
		vram_write(20'h00200, 16'h1357, 2'b11);
		// Scan the same 1 KiB plane row as word 0x200 so the buffered beat
		// must flush before the scan burst. An unrelated row is allowed to pass.
		// Stall before presenting the conflict: ST_VRAM_BURST_WRITE asserts
		// the first Avalon beat as soon as it is entered, unlike the old
		// ST_ISSUE pre-command state.
		force_waitrequest = 1'b1;
		scan_addr = 19'h00200;
		scan_req = 1'b1;
		while (!(dut.state == MEM_ST_VRAM_BURST_WRITE &&
			core_DDRAM_WE && core_DDRAM_BUSY))
			@(negedge clk);
		terminator_dummy_seen = 1'b0;
		framework_reset = 1'b1;
		quiesce = 1'b1;
		repeat (3) begin
			@(negedge clk);
			if (DDRAM_WE && DDRAM_BE == 8'h00)
				terminator_dummy_seen = 1'b1;
			assert (!vram_ack)
				else $fatal(1, "stalled write ACKed during framework reset");
		end
		force_waitrequest = 1'b0;
		while (model_active)
			@(negedge clk);
		repeat (3) @(negedge clk);
		assert (terminator_dummy_seen && !vram_ack &&
			vram_memory[12'h400] == 8'ha5 &&
			vram_memory[12'h401] == 8'h5a)
			else $fatal(1, "terminator dummy was absent, ACKed, or modified backing DDR");
		// The buffered retry is already durable; do not leave the scan request
		// competing for service while reset is released.
		scan_req = 1'b0;
		framework_reset = 1'b0;
		quiesce = 1'b0;
		reset_timeout = 0;
		while (retained_vram_writes && reset_timeout < 100) begin
			@(negedge clk);
			reset_timeout = reset_timeout + 1;
		end
		assert (!retained_vram_writes && vram_memory[12'h400] == 8'h13 &&
			vram_memory[12'h401] == 8'h57)
			else $fatal(1, "quiesced buffered write did not retry after reset");
		repeat (3) begin
			@(negedge clk);
			assert (!vram_ack)
				else $fatal(1, "buffer flush produced a duplicate client ACK");
		end

		// Exercise the same reset retry on an ordinary ioctl loader beat. Its
		// pending flag is the durability contract: the host remains throttled
		// until the original byte enables have reached backing DDR.
		low_memory[16'h0200] = 8'h11;
		low_memory[16'h0201] = 8'h22;
		ioctl_download = 1'b1;
		ioctl_addr = 27'h0000200;
		ioctl_data = 16'h5aa5;
		ioctl_wr = 1'b1;
		@(negedge clk);
		ioctl_wr = 1'b0;
		while (!(dut.state == MEM_ST_ISSUE && dut.op_client == 3'd5))
			@(negedge clk);
		force_waitrequest = 1'b1;
		while (!(dut.state == MEM_ST_WAIT_WRITE && core_DDRAM_WE && core_DDRAM_BUSY))
			@(negedge clk);
		terminator_dummy_seen = 1'b0;
		framework_reset = 1'b1;
		quiesce = 1'b1;
		repeat (3) begin
			@(negedge clk);
			if (DDRAM_WE && DDRAM_BE == 8'h00)
				terminator_dummy_seen = 1'b1;
			assert (dut.loader_pending && ioctl_wait)
				else $fatal(1, "loader beat was falsely completed during reset");
		end
		force_waitrequest = 1'b0;
		while (dut.state != MEM_ST_IDLE)
			@(negedge clk);
		repeat (3) @(negedge clk);
		assert (terminator_dummy_seen && dut.loader_pending && ioctl_wait &&
			low_memory[16'h0200] == 8'h11 && low_memory[16'h0201] == 8'h22)
			else $fatal(1, "loader dummy altered memory or released host throttle");
		framework_reset = 1'b0;
		quiesce = 1'b0;
		reset_timeout = 0;
		while (dut.loader_pending && reset_timeout < 100) begin
			@(negedge clk);
			reset_timeout = reset_timeout + 1;
		end
		assert (!dut.loader_pending && !ioctl_wait &&
			low_memory[16'h0200] == 8'ha5 && low_memory[16'h0201] == 8'h5a)
			else $fatal(1, "loader beat did not retry after reset");
		ioctl_download = 1'b0;
		while (!rom_loaded)
			@(negedge clk);

		// Finally interrupt the first internal framebuffer-clear qword. The
		// clear counter must not advance on the terminator's dummy write, then
		// the same line must be retried before rom_loaded can rise.
		for (init_index = 0; init_index < 8; init_index = init_index + 1)
			vram_memory[init_index] = 8'h30 + init_index[7:0];
		ioctl_download = 1'b1;
		repeat (3) @(negedge clk);
		ioctl_download = 1'b0;
		while (!(dut.state == MEM_ST_ISSUE && dut.op_client == 3'd7 &&
			dut.clear_line == 0))
			@(negedge clk);
		force_waitrequest = 1'b1;
		while (!(dut.state == MEM_ST_WAIT_WRITE && core_DDRAM_WE && core_DDRAM_BUSY))
			@(negedge clk);
		terminator_dummy_seen = 1'b0;
		framework_reset = 1'b1;
		quiesce = 1'b1;
		repeat (3) begin
			@(negedge clk);
			if (DDRAM_WE && DDRAM_BE == 8'h00)
				terminator_dummy_seen = 1'b1;
			assert (dut.clear_active && dut.clear_line == 0 && !rom_loaded)
				else $fatal(1, "clear advanced during reset-stalled write");
		end
		force_waitrequest = 1'b0;
		while (dut.state != MEM_ST_IDLE)
			@(negedge clk);
		repeat (3) @(negedge clk);
		assert (terminator_dummy_seen && dut.clear_active &&
			dut.clear_line == 0 && !rom_loaded)
			else $fatal(1, "clear dummy advanced line or released core");
		for (init_index = 0; init_index < 8; init_index = init_index + 1)
			assert (vram_memory[init_index] == 8'h30 + init_index[7:0])
				else $fatal(1, "clear dummy modified byte %0d", init_index);
		framework_reset = 1'b0;
		quiesce = 1'b0;
		while (!rom_loaded)
			@(negedge clk);
		for (init_index = 0; init_index < 4; init_index = init_index + 1)
			assert ({vram_memory[init_index * 2],
				vram_memory[init_index * 2 + 1]} == 16'h00ff)
				else $fatal(1, "retried clear produced wrong logical pixel %0d", init_index);

		$display("PASS: DDR loader/reload, terminator reset safety, DIP isolation, endian/cache/signature clients, empty banks, VRAM BE, fairness");
		$finish;
	end

endmodule
