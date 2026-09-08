`timescale 1ns/1ps

// Scaffold through DDR model is copied from the pinned DDR-memory fixture.
// Only this module name differs in that 409-line prefix.
module itech32_audio_qword_tb;
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
	localparam logic [27:0] GROM_BASE    = 28'h050_0000;
	localparam logic [27:0] SOUND_BASE   = 28'h040_0000;
	localparam logic [27:0] SAMPLE0_BASE = 28'h260_0000;
	localparam logic [27:0] SAMPLE3_BASE = 28'h2a0_0000;
	localparam logic [27:0] VRAM_BASE    = 28'h2e0_0000;

	logic clk = 1'b0;
	logic reset = 1'b1;
	logic timekill_mode = 1'b0;
	logic quiesce = 1'b0;
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

	itech32_ddr_memory #(
		.VRAM_CLEAR_LINES(8), .SCAN_BURST_WORDS(SCAN_BURST_WORDS)
	) dut (
		.clk(clk), .reset(reset), .timekill_mode(timekill_mode), .bloodstorm_mode(1'b0),
		.quiesce(quiesce),
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

    // Simulation-only producers. All request changes occur through nonblocking
    // assignments on posedges, just like the actual ES fetcher's ACK consumer.
    localparam integer WRITE_COUNT = 1024;
    localparam integer SAMPLE_COUNT = 128;
    localparam integer SERVICE_BOUND = 512;
    // The exact source hashes are checked by the runner. This Verilator build
    // breaks hierarchical enum references through the parameterized DUT clone;
    // use the inherited, pinned state constants and the pinned SAMPLE enum3.
    localparam logic [2:0] MEM_CLIENT_SAMPLE = 3'd3;
    integer case_id = 0;
    bit control_measure = 0;
    bit enforce_grace = 1;
    bit edge_only = 0;
    integer grace_eligible = 0, grace_commits = 0, grace_front_merges = 0;
    integer word3_opportunities = 0, word3_work_commits = 0;
    integer ack_priority_exceptions = 0, scan_on_ack = 0;
    integer grace_payload_checks = 0;
    bit enforce_service = 1;
    bit run_enable = 0;
    bit cancel_test = 0;
    integer writer_acks = 0, sample_acks = 0, sample_age = 0, writer_age = 0;
    integer sample_max = 0, writer_max = 0, sample_during_writes = 0;
    integer ordinary_turns = 0, ordinary_work_turns = 0, front_merge_grants = 0;
    integer sample_ddr_reads = 0, expected_sample_ddr_reads = 0;
    integer expected_hits = 0, expected_empty = 0, held_ack_clocks = 0;
    integer scan_age = 0, scan_accept_age = 0, scan_beats = 0;
    integer sample_hold_left = 0;
    integer cycles = 0, write_finish_cycle = 0, sample_finish_cycle = 0;
    bit writer_done = 0, sample_done = 0, sample_waiting = 0;
    bit sample_started = 0, scan_started = 0, scan_done = 0, scan_active = 0;
    logic [27:0] expected_cache_tag = 0;
    bit expected_cache_valid = 0;
    logic [7:0] expected_vram [0:4095];
    logic [7:0] scan_expected [0:1023];
    logic [63:0] write_hash = 64'hcbf29ce484222325;
    logic [63:0] sample_hash = 64'hcbf29ce484222325;
    logic [63:0] final_hash = 64'hcbf29ce484222325;
    logic [90:0] previous_qwrite;
    logic [23:0] previous_sample;
    bit qwrite_was_held = 0, sample_was_held = 0;
    bit ddr_was_held = 0;
    logic [110:0] previous_ddr;
    bit sample_grant_watch = 0, grant_had_front = 0;
    logic [135:0] grant_front;
    integer cancel_ack_count = 0;

    function automatic logic [63:0] hash_byte(input logic [63:0] value,
                                             input logic [7:0] data);
        return (value ^ {56'd0, data}) * 64'h00000100000001b3;
    endfunction
    function automatic logic [63:0] write_data_for(input integer index);
        logic [63:0] result;
        for(integer b=0;b<8;b++)
            result[b*8+:8] = 8'(index) ^ 8'(index>>8) ^ 8'(b*29) ^ 8'h53;
        return result;
    endfunction
    function automatic logic [7:0] write_mask_for(input integer index);
        case(index%8)
            0:return 8'hff; 1:return 8'h55; 2:return 8'haa; 3:return 8'h0f;
            4:return 8'hf0; 5:return 8'h81; 6:return 8'h18; default:return 8'h00;
        endcase
    endfunction
    function automatic logic [1:0] bank_for(input integer index);
        if(case_id==1) return index[0] ? 2'd2 : 2'd1;
        if(case_id==2) return 2'd2;
        if(case_id==3) begin
            case(index%3) 0:return 2'd0;1:return 2'd1;default:return 2'd3;endcase
        end
        return ((index/16)%2) ? 2'd3 : 2'd0;
    endfunction
    function automatic logic [21:0] address_for(input integer index);
        // Every populated group has four miss lines and twelve same-line hits.
        // Odd addresses in alternate groups test the word-alignment contract.
        return 22'h100 + 22'((index%16)*2) + 22'((index/16)%2);
    endfunction
    function automatic bit empty_bank(input logic [1:0] bank);
        return timekill_mode ? bank!=2 : (bank==1 || bank==2);
    endfunction
    function automatic logic [27:0] sample_byte_address(input logic [1:0] bank,
                                                       input logic [21:0] address);
        return (timekill_mode || bank==0 ? SAMPLE0_BASE : SAMPLE3_BASE) +
            {6'd0,address[21:1],1'b0};
    endfunction
    function automatic logic [15:0] sample_expected(input logic [1:0] bank,
                                                   input logic [21:0] address);
        logic [27:0] a;
        a=sample_byte_address(bank,address);
        return empty_bank(bank) ? 16'd0 : {model_byte(a),model_byte(a+1'b1)};
    endfunction

    always_ff @(posedge clk) begin : registered_writer
        if(reset) begin
            vram_qwrite_req<=0;vram_qwrite_addr<=0;vram_qwrite_data<=0;
            vram_qwrite_be<=0;vram_qwrite_token<=0;
            writer_acks<=0;writer_done<=0;writer_age<=0;writer_max<=0;
            write_finish_cycle<=0;
        end else if(run_enable && !writer_done && !cancel_test) begin
            if(!vram_qwrite_req) begin
                vram_qwrite_req<=1;vram_qwrite_addr<=0;
                vram_qwrite_data<=write_data_for(0);
                vram_qwrite_be<=write_mask_for(0);vram_qwrite_token<=1;
                writer_age<=0;
            end else if(vram_qwrite_ack) begin
                assert(vram_qwrite_addr==18'(writer_acks%512) &&
                       vram_qwrite_data==write_data_for(writer_acks) &&
                       vram_qwrite_be==write_mask_for(writer_acks))
                    else $fatal(1,"AUDIO_WRITE_OWNERSHIP index=%0d",writer_acks);
                for(integer b=0;b<8;b++) begin
                    if(vram_qwrite_be[b])
                        expected_vram[(writer_acks%512)*8+b] =
                            vram_qwrite_data[b*8+:8];
                    write_hash=hash_byte(write_hash,vram_qwrite_data[b*8+:8]);
                end
                write_hash=hash_byte(write_hash,vram_qwrite_be);
                if(writer_age>writer_max)writer_max<=writer_age;
                writer_acks<=writer_acks+1;writer_age<=0;
                if(writer_acks+1==WRITE_COUNT) begin
                    vram_qwrite_req<=0;writer_done<=1;write_finish_cycle<=cycles;
                end else begin
                    vram_qwrite_addr<=18'((writer_acks+1)%512);
                    vram_qwrite_data<=write_data_for(writer_acks+1);
                    vram_qwrite_be<=write_mask_for(writer_acks+1);
                    vram_qwrite_token<=!vram_qwrite_token;
                end
            end else begin
                writer_age<=writer_age+1;
                assert(writer_age<SERVICE_BOUND)
                    else $fatal(1,"AUDIO_VRAM_PROGRESS_DEADLINE age=%0d",writer_age);
            end
        end
    end

    always_ff @(posedge clk) begin : registered_sample
        logic [27:0] line_tag;
        if(reset) begin
            sample_req<=0;sample_bank<=0;sample_addr<=0;
            sample_acks<=0;sample_done<=0;sample_waiting<=0;sample_started<=0;
            sample_age<=0;sample_max<=0;sample_during_writes<=0;
            sample_hold_left<=0;sample_finish_cycle<=0;
        end else if(run_enable && !sample_done && !cancel_test) begin
            if(!sample_started && writer_acks>=32) begin
                sample_req<=1;sample_bank<=bank_for(0);sample_addr<=address_for(0);
                sample_started<=1;sample_waiting<=1;sample_age<=0;
            end else if(sample_ack) begin
                assert(sample_req && sample_waiting &&
                       sample_bank==bank_for(sample_acks) &&
                       sample_addr==address_for(sample_acks) &&
                       sample_rdata==sample_expected(sample_bank,sample_addr))
                    else $fatal(1,"AUDIO_SAMPLE_OWNERSHIP index=%0d bank=%0d addr=%x data=%x expected=%x",
                        sample_acks,sample_bank,sample_addr,sample_rdata,
                        sample_expected(sample_bank,sample_addr));
                line_tag=sample_byte_address(sample_bank,sample_addr);
                line_tag[2:0]=3'b000;
                if(empty_bank(sample_bank)) expected_empty++;
                else begin
                    if(!expected_cache_valid || line_tag!=expected_cache_tag)
                        expected_sample_ddr_reads++;
                    else expected_hits++;
                    expected_cache_valid=1;expected_cache_tag=line_tag;
                end
                sample_hash=hash_byte(hash_byte(sample_hash,sample_rdata[15:8]),
                                     sample_rdata[7:0]);
                if(sample_age>sample_max)sample_max<=sample_age;
                if(!writer_done)sample_during_writes<=sample_during_writes+1;
                sample_acks<=sample_acks+1;sample_age<=0;
                if(sample_acks+1==SAMPLE_COUNT) begin
                    sample_req<=0;sample_done<=1;sample_waiting<=0;
                    sample_finish_cycle<=cycles;
                end else if(sample_acks==0) begin
                    // Keep the first completed signature asserted three clocks.
                    sample_hold_left<=3;sample_waiting<=0;
                end else begin
                    sample_bank<=bank_for(sample_acks+1);
                    sample_addr<=address_for(sample_acks+1);
                end
            end else if(sample_hold_left!=0) begin
                held_ack_clocks++;
                sample_hold_left<=sample_hold_left-1;
                if(sample_hold_left==1) begin
                    sample_bank<=bank_for(sample_acks);sample_addr<=address_for(sample_acks);
                    sample_waiting<=1;sample_age<=0;
                end
            end else if(sample_waiting) begin
                sample_age<=sample_age+1;
                if(enforce_service)
                    assert(sample_age<SERVICE_BOUND)
                        else $fatal(1,"AUDIO_SERVICE_DEADLINE case=%0d age=%0d writer_acks=%0d state=%0d",
                            case_id,sample_age,writer_acks,dut.state);
            end
        end
    end

    always_ff @(posedge clk) begin : optional_scan
        logic [63:0] wanted;
        if(reset) begin
            scan_req<=0;scan_addr<=20'h100;scan_started<=0;scan_done<=0;
            scan_active<=0;scan_beats<=0;scan_age<=0;scan_accept_age<=0;
        end else if(run_enable && !cancel_test) begin
            if(!scan_started &&
               ((case_id==4 && writer_acks>=32) ||
                (case_id==5 && dut.state==MEM_ST_CAPTURE &&
                 dut.op_client==MEM_CLIENT_SAMPLE) ||
                (case_id==6 && dut.state==MEM_ST_RESPOND &&
                 dut.response_clients[MEM_CLIENT_SAMPLE] &&
                 dut.response_byte_index[2:1]==2'd0) ||
                (case_id==7 && dut.state==MEM_ST_IDLE && sample_ack &&
                 dut.response_byte_index[2:1]==2'd0))) begin
                scan_req<=1;scan_started<=1;scan_age<=0;
            end else if(scan_req && !scan_accept) begin
                scan_age<=scan_age+1;
                assert(scan_age<SERVICE_BOUND)
                    else $fatal(1,"AUDIO_SCAN_ACCEPT_DEADLINE age=%0d",scan_age);
            end
            if(scan_accept) begin
                assert(scan_req && !scan_active)
                    else $fatal(1,"AUDIO_SCAN_DUPLICATE_ACCEPT");
                scan_req<=0;scan_active<=1;scan_accept_age<=scan_age;
                for(integer b=0;b<SCAN_BURST_WORDS*8;b++)
                    scan_expected[b]=expected_vram[512+b];
            end
            if(scan_data_valid) begin
                assert(scan_active && scan_beats<SCAN_BURST_WORDS)
                    else $fatal(1,"AUDIO_SCAN_UNOWNED_BEAT");
                for(integer b=0;b<8;b++)wanted[b*8+:8]=scan_expected[scan_beats*8+b];
                assert(scan_rdata==wanted &&
                       scan_last==(scan_beats==SCAN_BURST_WORDS-1))
                    else $fatal(1,"AUDIO_SCAN_DATA beat=%0d got=%x expected=%x",
                                scan_beats,scan_rdata,wanted);
                scan_beats<=scan_beats+1;
                if(scan_beats==SCAN_BURST_WORDS-1) begin
                    scan_active<=0;scan_done<=1;
                end
            end
        end
    end

    always @(posedge clk) begin : protocol_monitor
        if(reset) begin
            cycles<=0;qwrite_was_held<=0;sample_was_held<=0;ddr_was_held<=0;
            sample_grant_watch<=0;
        end else begin
            cycles<=cycles+1;
            if(qwrite_was_held && !cancel_test)
                assert(vram_qwrite_req &&
                       {vram_qwrite_addr,vram_qwrite_data,vram_qwrite_be,
                        vram_qwrite_token}==previous_qwrite)
                    else $fatal(1,"AUDIO_WRITE_CHANGED_WHILE_HELD");
            if(sample_was_held && !cancel_test)
                assert(sample_req && {sample_bank,sample_addr}==previous_sample)
                    else $fatal(1,"AUDIO_SAMPLE_CHANGED_WHILE_HELD");
            qwrite_was_held<=vram_qwrite_req&&!vram_qwrite_ack;
            // An acknowledged signature may be held arbitrarily then changed;
            // only a still-owned, unacknowledged request must remain immutable.
            sample_was_held<=sample_req&&sample_waiting&&!sample_ack;
            previous_qwrite<={vram_qwrite_addr,vram_qwrite_data,vram_qwrite_be,
                              vram_qwrite_token};
            previous_sample<={sample_bank,sample_addr};
            if(ddr_was_held && !framework_reset)
                assert({DDRAM_RD,DDRAM_WE,DDRAM_ADDR,DDRAM_BURSTCNT,
                        DDRAM_DIN,DDRAM_BE}==previous_ddr)
                    else $fatal(1,"AUDIO_DDR_CHANGED_WHILE_BUSY");
            ddr_was_held<=(DDRAM_RD||DDRAM_WE)&&DDRAM_BUSY;
            previous_ddr<={DDRAM_RD,DDRAM_WE,DDRAM_ADDR,DDRAM_BURSTCNT,
                           DDRAM_DIN,DDRAM_BE};
            if(DDRAM_RD && !DDRAM_BUSY && !model_active && model_armed &&
               logical_line_addr(DDRAM_ADDR)>=SAMPLE0_BASE &&
               logical_line_addr(DDRAM_ADDR)<VRAM_BASE)
                sample_ddr_reads++;
            if(sample_ack && !cancel_test) begin
                assert(dut.state==MEM_ST_IDLE && !dut.pending_clients[MEM_CLIENT_SAMPLE])
                    else $fatal(1,"AUDIO_NO_ORDINARY_IDLE_AFTER_ACK");
                ordinary_turns++;
                if(vram_qwrite_req &&
                   (dut.vram_buffer_commit || dut.vram_fast_write ||
                    (dut.vram_write_buffer_valid &&
                     dut.live_vram_block_addr!=dut.vram_write_buffer_base)))
                    ordinary_work_turns++;
            end
            if(sample_grant_watch) begin
                assert(dut.state==MEM_ST_CAPTURE && dut.op_client==MEM_CLIENT_SAMPLE &&
                       !vram_qwrite_ack)
                    else $fatal(1,"AUDIO_SAMPLE_GRANT_REPLACED_WRITE");
                if(grant_had_front) begin
                    assert(!dut.vram_fast_pending)
                        else $fatal(1,"AUDIO_SAMPLE_GRANT_LOST_FRONT_RETIREMENT");
                    front_merge_grants++;
                end
            end
            sample_grant_watch<=!control_measure && !cancel_test &&
                dut.state==MEM_ST_IDLE && !dut.main_front_cancel && !scan_req &&
                dut.pending_clients[MEM_CLIENT_SAMPLE] &&
                !dut.vram_write_buffer_retry && !dut.clear_active &&
                !dut.rom_download_active && !dut.download_ended;
            grant_had_front<=dut.vram_fast_pending;
            grant_front<={dut.vram_fast_base_q,dut.vram_fast_index_q,
                         dut.vram_fast_select_q,dut.vram_fast_data_q,dut.vram_fast_be_q};
        end
    end

    task automatic flush_and_score;
        integer timeout;
        begin
            @(negedge clk);vram_req=1;vram_we=0;vram_addr=0;
            timeout=0;
            do begin @(posedge clk);#1;timeout++;end while(!vram_ack && timeout<2000);
            assert(vram_ack) else $fatal(1,"AUDIO_FINAL_WRITE_FENCE_TIMEOUT");
            assert(vram_rdata=={expected_vram[0],expected_vram[1]})
                else $fatal(1,"AUDIO_FINAL_READ_DATA");
            @(negedge clk);vram_req=0;
            repeat(4)@(negedge clk);
            assert(!retained_vram_writes)
                else $fatal(1,"AUDIO_FINAL_RETAINED_WRITE");
            for(integer b=0;b<4096;b++) begin
                assert(vram_memory[b]==expected_vram[b])
                    else $fatal(1,"AUDIO_FINAL_BYTE address=%x got=%x expected=%x",
                                b,vram_memory[b],expected_vram[b]);
                final_hash=hash_byte(final_hash,vram_memory[b]);
            end
        end
    endtask

`include "itech32_audio_service_cancel_tasks.svh"
`include "itech32_audio_qword_edges.svh"

    initial begin : test
        integer timeout;
        void'($value$plusargs("CASE=%d",case_id));
        control_measure=$test$plusargs("CONTROL");
        enforce_service=1;
        enforce_grace=!control_measure || $test$plusargs("REQUIRE_GRACE");
        edge_only=$test$plusargs("EDGE_ONLY");
        assert(case_id>=0 && case_id<=7) else $fatal(1,"AUDIO_BAD_CASE");
        timekill_mode=(case_id==2 || case_id==3);
        for(integer b=0;b<65536;b++)low_memory[b]=0;
        for(integer b=0;b<4096;b++)begin vram_memory[b]=0;expected_vram[b]=0;end
        repeat(5)@(negedge clk);reset=0;
        // A legal empty loader transaction boots the synthetic-memory fixture.
        // This is not actual-game loader/ROM evidence.
        ioctl_download=1;repeat(2)@(negedge clk);ioctl_download=0;
        timeout=0;
        while(!rom_loaded && timeout<2000)begin @(negedge clk);timeout++;end
        assert(rom_loaded)else $fatal(1,"AUDIO_SYNTHETIC_BOOT_TIMEOUT");
        repeat(4)@(negedge clk);
        for(integer b=0;b<4096;b++)expected_vram[b]=vram_memory[b];
        if(edge_only) begin
            audio_qword_edge_suite();
            $display("PASS: audio qword boundary suite exact bytes and bounded ownership");
            $finish;
        end
        run_enable=1;
        timeout=0;
        while((!writer_done || !sample_done ||
               (case_id>=4 && !scan_done)) && timeout<100000)begin
            @(negedge clk);timeout++;
        end
        assert(writer_done && sample_done &&
               (case_id<4 || scan_done))
            else $fatal(1,"AUDIO_TEST_TIMEOUT writes=%0d samples=%0d scan=%0d",
                        writer_acks,sample_acks,scan_beats);
        run_enable=0;
        flush_and_score();
        assert(writer_acks==WRITE_COUNT && sample_acks==SAMPLE_COUNT &&
               held_ack_clocks==3 && ordinary_turns==SAMPLE_COUNT &&
               sample_ddr_reads==expected_sample_ddr_reads)
            else $fatal(1,"AUDIO_CONSERVATION writes=%0d samples=%0d holds=%0d turns=%0d DDR=%0d expectedDDR=%0d",
                        writer_acks,sample_acks,held_ack_clocks,ordinary_turns,
                        sample_ddr_reads,expected_sample_ddr_reads);
        if(case_id==1 || case_id==3)
            assert(expected_empty==SAMPLE_COUNT && sample_ddr_reads==0)
                else $fatal(1,"AUDIO_EMPTY_BANK_DDR");
        else
            assert(expected_hits>0 && sample_ddr_reads>0 && expected_empty==0)
                else $fatal(1,"AUDIO_CACHE_CASE_VACUOUS");
        if(!control_measure)
            assert(sample_during_writes>0 && ordinary_work_turns>0 &&
                   sample_max<SERVICE_BOUND && writer_max<SERVICE_BOUND)
                else $fatal(1,"AUDIO_NO_BOUNDED_CONCURRENT_PROGRESS");

        assert(grace_eligible+word3_opportunities+ack_priority_exceptions==SAMPLE_COUNT)
            else $fatal(1,"AUDIO_QWORD_ACK_PARTITION");
        if(case_id<4) begin
            assert(grace_eligible==96 && word3_opportunities==32 &&
                   ack_priority_exceptions==0)
                else $fatal(1,"AUDIO_QWORD_96_32_COVERAGE grace=%0d ordinary=%0d other=%0d",
                    grace_eligible,word3_opportunities,ack_priority_exceptions);
        end
        if(enforce_grace) begin
            assert(grace_commits==grace_eligible && grace_payload_checks==grace_eligible &&
                   word3_work_commits>0)
                else $fatal(1,"AUDIO_QWORD_NO_USEFUL_GRACE");
            if(case_id==6) assert(scan_on_ack>0)
                else $fatal(1,"AUDIO_QWORD_SCAN_ACK_CASE_VACUOUS");
        end
        $display("AUDIO_QWORD_POLICY ack_consumptions=%0d grace_eligible=%0d grace_commits=%0d grace_front_merges=%0d grace_payload_checks=%0d word3_opportunities=%0d word3_work_commits=%0d priority_exceptions=%0d scan_on_ack=%0d",
            ordinary_turns,grace_eligible,grace_commits,grace_front_merges,
            grace_payload_checks,word3_opportunities,word3_work_commits,
            ack_priority_exceptions,scan_on_ack);
        $display("AUDIO_RESULT case=%0d control=%0d writes=%0d samples=%0d write_hash=%016x sample_hash=%016x final_hash=%016x sample_max=%0d writer_max=%0d sample_ddr=%0d hits=%0d empty=%0d sample_during_writes=%0d ordinary_turns=%0d ordinary_work_turns=%0d front_merge_grants=%0d scan_beats=%0d scan_accept_age=%0d write_finish=%0d sample_finish=%0d",
            case_id,control_measure,writer_acks,sample_acks,write_hash,sample_hash,final_hash,
            sample_max,writer_max,sample_ddr_reads,expected_hits,expected_empty,
            sample_during_writes,ordinary_turns,ordinary_work_turns,front_merge_grants,
            scan_beats,scan_accept_age,write_finish_cycle,sample_finish_cycle);
        if(case_id==0)audio_cancel_suite();
        $display("PASS: audio qword exact bytes, registered ownership and finite workload");
        $finish;
    end
endmodule
