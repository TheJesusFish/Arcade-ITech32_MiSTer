`timescale 1ns/1ps
// SPDX-License-Identifier: GPL-3.0-or-later
// Synthetic SOUND cache/arbitration regression. No game program or ROM assets.
// The cycle bounds below describe this finite-latency model, not the DDR device
// or the ES5506's end-to-end sample deadline.
module itech32_sound_service_tb;
    localparam logic [27:0] SOUND_BASE = 28'h040_0000;
    localparam logic [27:0] SAMPLE_BASE = 28'h260_0000;
    localparam logic [27:0] VRAM_BASE = 28'h2e0_0000;
    localparam logic [4:0] MEM_ST_CAPTURE = 5'd7;
    localparam logic [4:0] MEM_ST_VRAM_BURST_WRITE = 5'd19;
    localparam logic [2:0] CLIENT_SOUND = 3'd2;
    localparam logic [2:0] CLIENT_SAMPLE = 3'd3;

    logic clk = 0;
    always #5 clk = ~clk;
    logic reset = 1, quiesce = 0, framework_reset = 0;
    logic ioctl_download = 0, ioctl_wr = 0;
    logic [26:0] ioctl_addr = 0;
    logic [15:0] ioctl_data = 0;
    logic ioctl_wait, rom_loaded;
    logic sound_req = 0, sound_ack;
    logic [18:0] sound_addr = 0;
    logic [7:0] sound_rdata;
    logic sample_req = 0, sample_ack;
    logic [21:0] sample_addr = 22'h010000;
    logic [15:0] sample_rdata;
    logic qwrite_req = 0, qwrite_ack, qwrite_token = 0;
    logic [17:0] qwrite_addr = 0;
    logic [63:0] qwrite_data = 0;
    logic scan_req = 0, scan_accept, scan_valid, scan_last;
    logic [63:0] scan_data;

    logic busy, rd, we, ready;
    logic [7:0] burst, be;
    logic [28:0] addr;
    logic [63:0] din, dout;
    logic core_busy, core_rd, core_we, core_ready;
    logic [7:0] core_burst, core_be;
    logic [28:0] core_addr;
    logic [63:0] core_din, core_dout;

    itech32_ddr_memory #(.VRAM_CLEAR_LINES(8)) dut (
        .clk(clk), .reset(reset), .timekill_mode(1'b0), .bloodstorm_mode(1'b0),
        .quiesce(quiesce), .ioctl_download(ioctl_download), .ioctl_wr(ioctl_wr),
        .ioctl_index(16'd0), .ioctl_addr(ioctl_addr), .ioctl_data(ioctl_data),
        .ioctl_wait(ioctl_wait), .rom_loaded(rom_loaded),
        .vector_load_we(), .vector_load_addr(), .vector_load_wdata(), .vector_load_be(),
        .main_req(1'b0), .main_addr(22'd0), .main_ack(), .main_rdata(),
        .grom_req(1'b0), .grom_addr(26'd0), .grom_ack(), .grom_rdata(),
        .sound_req(sound_req), .sound_addr(sound_addr), .sound_ack(sound_ack),
        .sound_rdata(sound_rdata), .sample_req(sample_req), .sample_bank(2'd0),
        .sample_addr(sample_addr), .sample_ack(sample_ack), .sample_rdata(sample_rdata),
        .vram_req(1'b0), .vram_we(1'b0), .vram_addr(20'd0), .vram_wdata(16'd0),
        .vram_be(2'b11), .vram_ack(), .vram_rdata(),
        .vram_qwrite_req(qwrite_req), .vram_qwrite_addr(qwrite_addr),
        .vram_qwrite_data(qwrite_data), .vram_qwrite_be(8'hff),
        .vram_qwrite_token(qwrite_token), .vram_qwrite_ack(qwrite_ack),
        .scan_req(scan_req), .scan_addr(20'd0), .scan_accept(scan_accept),
        .scan_data_valid(scan_valid), .scan_rdata(scan_data), .scan_last(scan_last),
        .DDRAM_CLK(), .DDRAM_BUSY(core_busy), .DDRAM_BURSTCNT(core_burst),
        .DDRAM_ADDR(core_addr), .DDRAM_DOUT(core_dout), .DDRAM_DOUT_READY(core_ready),
        .DDRAM_DIN(core_din), .DDRAM_BE(core_be), .DDRAM_RD(core_rd), .DDRAM_WE(core_we)
    );

    // The real framework guard must drain an already accepted read on reset.
    f2sdram_safe_terminator #(.DATA_WIDTH(64), .BURSTCOUNT_WIDTH(8)) terminator (
        .clk(clk), .rst_req_sync(framework_reset),
        .waitrequest_master(busy), .burstcount_master(burst), .address_master(addr),
        .readdata_master(dout), .readdatavalid_master(ready), .read_master(rd),
        .writedata_master(din), .byteenable_master(be), .write_master(we),
        .waitrequest_slave(core_busy), .burstcount_slave(core_burst),
        .address_slave(core_addr), .readdata_slave(core_dout),
        .readdatavalid_slave(core_ready), .read_slave(core_rd),
        .writedata_slave(core_din), .byteenable_slave(core_be), .write_slave(core_we)
    );

    logic force_busy = 0, hold_returns = 0;
    logic model_active = 0, model_read = 0, model_armed = 1;
    logic [27:0] model_address;
    integer model_count, model_beat, model_delay;
    integer sound_reads = 0, sample_reads = 0, scans = 0, writes = 0;
    integer ack_count = 0, scan_beats = 0;
    logic [7:0] image_epoch = 0;
    logic [7:0] vram [0:4095];
    wire [27:0] logical_address = {addr[24:0], 3'b000};

    function automatic logic [7:0] pattern(input logic [27:0] a);
        logic [27:0] relative_address;
        if (a >= SOUND_BASE && a < SOUND_BASE + 28'h008_0000) begin
            relative_address = a - SOUND_BASE;
            // Include every bank bit, not just the low 16 address bits.
            return 8'ha0 ^ relative_address[7:0] ^ relative_address[15:8] ^
                {5'd0, relative_address[18:16]} ^ image_epoch;
        end
        if (a >= VRAM_BASE && a < VRAM_BASE + 28'd4096)
            return vram[12'(a - VRAM_BASE)];
        return 8'h53 ^ a[7:0] ^ a[15:8] ^ a[23:16];
    endfunction

    function automatic logic [63:0] pattern_line(input logic [27:0] a);
        logic [63:0] result;
        for (integer i=0; i<8; i++) result[i*8 +: 8] = pattern(a + 28'(i));
        return result;
    endfunction

    task automatic store_write(input logic [27:0] a);
        for (integer i=0; i<8; i++)
            if (be[i] && a + 28'(i) >= VRAM_BASE && a + 28'(i) < VRAM_BASE + 28'd4096)
                vram[12'(a + 28'(i) - VRAM_BASE)] = din[i*8 +: 8];
    endtask

    // Bounded deterministic waitrequest/read latency. Accepted bursts are never
    // aborted by the stimulus: quiesce suppresses client responses while the
    // framework guard and this model complete the outstanding physical command.
    always @(posedge clk) begin
        ready <= 0;
        if (reset) begin
            busy <= 1;
            model_active <= 0;
            model_armed <= 1;
            model_delay <= 0;
            dout <= 0;
        end else begin
            if (!rd && !we) model_armed <= 1;
            if (force_busy) busy <= 1;
            else if (model_active) begin
                if (model_delay > 0) begin
                    model_delay <= model_delay - 1;
                    busy <= 1;
                end else if (model_read) begin
                    busy <= 1;
                    if (!hold_returns) begin
                        dout <= pattern_line(model_address + 28'(model_beat*8));
                        ready <= 1;
                        model_beat <= model_beat + 1;
                        if (model_beat + 1 == model_count) begin
                            model_active <= 0;
                            busy <= 0;
                        end
                    end
                end else if (busy) busy <= 0;
                else if (we) begin
                    store_write(model_address + 28'(model_beat*8));
                    model_beat <= model_beat + 1;
                    if (model_beat + 1 == model_count) model_active <= 0;
                    else begin model_delay <= 1; busy <= 1; end
                end
            end else if (busy) busy <= 0;
            else if (model_armed && (rd || we)) begin
                assert (!(rd && we)) else $fatal(1, "DDR read/write overlap");
                assert (burst != 0) else $fatal(1, "zero DDR burst");
                model_address <= logical_address;
                model_count <= integer'(burst);
                model_beat <= rd ? 0 : 1;
                model_read <= rd;
                model_delay <= 3;
                model_active <= rd || burst != 1;
                model_armed <= 0;
                busy <= rd || burst != 1;
                if (rd) begin
                    if (logical_address >= SOUND_BASE && logical_address < SOUND_BASE + 28'h008_0000)
                        sound_reads <= sound_reads + 1;
                    if (logical_address >= SAMPLE_BASE && logical_address < SAMPLE_BASE + 28'h040_0000)
                        sample_reads <= sample_reads + 1;
                    if (burst == 128) scans <= scans + 1;
                end else begin store_write(logical_address); writes <= writes + 1; end
            end
        end
    end

    always @(posedge clk) begin
        if (!reset && sound_ack) ack_count <= ack_count + 1;
        if (!reset && scan_valid) begin
            assert (scan_data == pattern_line(VRAM_BASE + 28'(scan_beats*8)))
                else $fatal(1, "scan data changed at beat %0d", scan_beats);
            assert (scan_last == (scan_beats == 127))
                else $fatal(1, "scan last/order mismatch");
            scan_beats <= scan_beats + 1;
        end
    end

    // A held Avalon request must not mutate while physical waitrequest is high.
    logic held = 0;
    logic [110:0] held_payload;
    always @(posedge clk) begin
        if (reset || framework_reset) held <= 0;
        else begin
            if (held) assert ({rd,we,addr,burst,din,be} == held_payload)
                else $fatal(1, "DDR request changed under waitrequest");
            held <= busy && (rd || we);
            held_payload <= {rd,we,addr,burst,din,be};
        end
    end

    task automatic wait_loaded;
        integer timeout;
        timeout = 0;
        while (!rom_loaded && timeout < 4000) begin @(negedge clk); timeout++; end
        assert (rom_loaded) else $fatal(1, "synthetic load timed out state=%0d", dut.state);
    endtask

    task automatic drop_sound;
        @(negedge clk); sound_req = 0;
        @(posedge clk); #1;
    endtask

    integer hit_during_drain = 0;
    task automatic sound_read(input logic [18:0] a, input integer expected_edges = 0);
        integer edges;
        @(negedge clk); sound_addr = a; sound_req = 1;
        edges = 0;
        do begin
            @(posedge clk); #1; edges++;
            if (expected_edges == 3 && dut.state == MEM_ST_VRAM_BURST_WRITE)
                hit_during_drain++;
        end while (!sound_ack && edges < 1024);
        assert (sound_ack) else $fatal(1, "SOUND timeout %h state=%0d", a, dut.state);
        assert (sound_rdata == pattern(SOUND_BASE + {9'd0,a}))
            else $fatal(1, "SOUND wrong byte %h got=%h expected=%h", a, sound_rdata,
                pattern(SOUND_BASE + {9'd0,a}));
        if (expected_edges != 0) assert (edges == expected_edges)
            else $fatal(1, "SOUND hit %h took %0d edges expected %0d", a, edges, expected_edges);
        repeat (3) begin @(posedge clk); #1; assert (!sound_ack) else $fatal(1, "duplicate SOUND ACK"); end
    endtask

    task automatic no_sound_ack(input integer clocks);
        repeat (clocks) begin @(posedge clk); #1; assert (!sound_ack) else $fatal(1, "cancelled SOUND ACK"); end
    endtask

    task automatic cancel_and_replace(input logic [18:0] first_address,
                                      input logic [18:0] replacement);
        integer reads_before, clocks;
        reads_before = sound_reads;
        @(negedge clk); hold_returns = 1; sound_addr = first_address; sound_req = 1;
        clocks = 0;
        while (!(model_active && model_read && model_address == SOUND_BASE + {9'd0,first_address}) && clocks < 500) begin
            @(negedge clk); clocks++;
        end
        assert (clocks < 500) else $fatal(1, "replacement fixture was not cold");
        sound_req = 0;
        @(posedge clk); #1;
        @(negedge clk); sound_addr = replacement; sound_req = 1;
        no_sound_ack(8);
        @(negedge clk); hold_returns = 0;
        clocks = 0;
        do begin @(posedge clk); #1; clocks++; end while (!sound_ack && clocks < 1024);
        assert (sound_ack && sound_rdata == pattern(SOUND_BASE + {9'd0,replacement}))
            else $fatal(1, "replacement signature/data failed");
        // Even exact A->cancel->A is a fresh transaction: the abandoned refill
        // must not ACK it or become a hit merely because the addresses match.
        assert (sound_reads == reads_before+2)
            else $fatal(1, "abandoned refill completed replacement without a new request");
        repeat (3) begin @(posedge clk); #1; assert (!sound_ack) else $fatal(1, "replacement ACK repeated"); end
        drop_sound();
        sound_read(replacement, 3); drop_sound();
    endtask

    // Boundary 0=quiesce on returned data, 1=quiesce at registered response,
    // 2=reload on returned data. Data already published BEFORE quiesce remains
    // a valid immutable cache entry; data canceled ON refill may not publish.
    task automatic refill_boundary(input logic [18:0] a, input integer boundary);
        integer reads_before, clocks;
        reads_before = sound_reads;
        @(negedge clk); hold_returns = 1; sound_addr = a; sound_req = 1;
        clocks = 0;
        while (!(model_active && model_read && model_address == SOUND_BASE + {9'd0,a}) && clocks < 500) begin
            @(negedge clk); clocks++;
        end
        assert (clocks < 500) else $fatal(1, "refill boundary was not cold");
        hold_returns = 0;
        clocks = 0;
        while (!(boundary == 1 ? dut.state == 5'd8 : core_ready) && clocks < 500) begin
            @(negedge clk); clocks++;
        end
        assert (clocks < 500 && !sound_ack) else $fatal(1, "refill boundary missed");
        if (boundary == 2) begin ioctl_download = 1; image_epoch = image_epoch ^ 8'h36; end
        else quiesce = 1;
        no_sound_ack(5);
        @(negedge clk); sound_req = 0;
        no_sound_ack(2);
        @(negedge clk);
        if (boundary == 2) begin ioctl_download = 0; wait_loaded(); end
        else quiesce = 0;
        sound_read(a, boundary == 1 ? 3 : 0); drop_sound();
        assert (sound_reads == reads_before + (boundary == 1 ? 1 : 2))
            else $fatal(1, "wrong publication across refill boundary %0d", boundary);
    endtask

    // Registered clients consume ACK on the following rising edge, just as the
    // real ES prefetcher and VRAM producer do. Changing on ACK assertion's falling
    // edge would incorrectly remove the important one-edge consumption grace.
    logic traffic = 0, continuous_sample = 1;
    integer sample_pause = 0;
    integer samples_done = 0, qwrites_done = 0;
    always @(posedge clk) begin
        if (traffic) begin
            if (sample_pause != 0) begin
                sample_req <= 0;
                sample_pause <= sample_pause - 1;
            end else if (!sample_req) sample_req <= 1;
            else if (sample_ack) begin
                assert (sample_rdata == {pattern(SAMPLE_BASE + {6'd0,sample_addr}),
                    pattern(SAMPLE_BASE + {6'd0,sample_addr} + 1)})
                    else $fatal(1, "SAMPLE data mismatch during SOUND fairness");
                samples_done <= samples_done + 1;
                sample_addr <= sample_addr + 22'd2;
                if (!continuous_sample && sample_addr[2:1] == 2'd3) begin
                    sample_req <= 0;
                    sample_pause <= 40;
                end
            end
            if (!qwrite_req) begin
                qwrite_req <= 1; qwrite_addr <= 18'd128;
                qwrite_data <= 64'h0123456789abcdef;
            end else if (qwrite_ack) begin
                qwrites_done <= qwrites_done + 1;
                qwrite_addr <= qwrite_addr + 18'd1;
                qwrite_token <= !qwrite_token;
                qwrite_data <= qwrite_data + 64'd1;
            end
        end else begin sample_req <= 0; qwrite_req <= 0; end
    end

    logic fairness_watch = 0;
    integer grants_waiting = 0, sound_grants = 0, max_grants = 0;
    // These are actual scheduler grants (entry into the existing CAPTURE state),
    // not ACKs or wall-clock estimates. Observe combinational pending ownership
    // on that edge: a SOUND grant itself intentionally suppresses miss_pending.
    always @(posedge clk) begin
        if (!fairness_watch) grants_waiting <= 0;
        else if (dut.state == MEM_ST_CAPTURE) begin
            if (dut.op_client == CLIENT_SAMPLE && dut.sound_miss_pending) begin
                grants_waiting <= grants_waiting + 1;
                assert (grants_waiting < 4) else $fatal(1, "SOUND starved beyond four SAMPLE grants");
            end else if (dut.op_client == CLIENT_SOUND) begin
                sound_grants <= sound_grants + 1;
                if (grants_waiting > max_grants) max_grants <= grants_waiting;
                grants_waiting <= 0;
            end
        end
    end

    integer before_reads, before_acks, timeout;
    initial begin
        for (integer i=0; i<4096; i++) vram[i] = 0;
        repeat (5) @(negedge clk);
        reset = 0;
        ioctl_download = 1;
        repeat (2) @(negedge clk);
        ioctl_download = 0;
        wait_loaded();

        sound_read(19'h10020); drop_sound();
        before_reads = sound_reads;
        for (integer i=0; i<8; i++) sound_read(19'h10020 + 19'(i), 3);
        assert (sound_reads == before_reads) else $fatal(1, "resident bytes issued DDR reads");
        drop_sound();

        // A blocked shared DDR command cannot delay a resident SOUND hit.
        @(negedge clk); force_busy = 1;
        repeat (3) @(negedge clk);
        for (integer i=0; i<8; i++) sound_read(19'h10020 + 19'(i), 3);
        drop_sound();
        @(negedge clk); force_busy = 0;

        // A genuine, accepted scan burst owns DDR while resident hits bypass it.
        @(negedge clk); hold_returns = 1; scan_req = 1;
        timeout = 0;
        while (!(model_active && model_read && model_count == 128) && timeout < 500) begin
            @(negedge clk); timeout++;
        end
        assert (timeout < 500) else $fatal(1, "scan never reached DDR");
        scan_req = 0;
        for (integer i=0; i<8; i++) sound_read(19'h10020 + 19'(i), 3);
        drop_sound();
        assert (sound_reads == before_reads) else $fatal(1, "busy/scan hit issued DDR read");
        @(negedge clk); hold_returns = 0;
        timeout = 0;
        while (scan_beats < 128 && timeout < 500) begin @(negedge clk); timeout++; end
        assert (scan_beats == 128) else $fatal(1, "scan failed after SOUND hits");

		// Populate two complete 512-qword cohorts with identical indices and
		// distinct full tags, then revisit both edge bytes of both cohorts with no
		// physical reads. This proves 8 KiB of actual two-way residency rather than
		// a duplicated output register or a truncated index.
		for (integer i=0; i<512; i++) begin
			sound_read(19'h20000 + 19'(i*8)); drop_sound();
		end
		for (integer i=0; i<512; i++) begin
			sound_read(19'h30000 + 19'(i*8)); drop_sound();
		end
		before_reads = sound_reads;
		for (integer i=511; i>=0; i--) begin
			sound_read(19'h20000 + 19'(i*8), 3);
			sound_read(19'h20007 + 19'(i*8), 3);
			sound_read(19'h30000 + 19'(i*8), 3);
			sound_read(19'h30007 + 19'(i*8), 3);
			drop_sound();
		end
		assert (sound_reads == before_reads)
			else $fatal(1, "SOUND two-way full indexed working set was not resident");

		// Every high physical tag bit must participate in matching. Two aliases
		// with the same index must coexist after the second line fills.
		sound_read(19'h20aa0); drop_sound();
		for (integer bit_number=12; bit_number<19; bit_number++) begin
			sound_read(19'h00028); drop_sound();
			before_reads = sound_reads;
			sound_read(19'h00028 ^ (19'd1 << bit_number)); drop_sound();
			assert (sound_reads == before_reads+1)
				else $fatal(1, "SOUND physical tag bit %0d aliased", bit_number);
			sound_read(19'h00028, 3); drop_sound();
			sound_read(19'h00028 ^ (19'd1 << bit_number), 3); drop_sound();
			assert (sound_reads == before_reads+1)
				else $fatal(1, "SOUND two-way alias residency failed at bit %0d", bit_number);
			sound_read(19'h20aa0, 3); drop_sound();
		end

		// The fixed ROM and one banked ROM line share this exact cache index. Warm
		// both, touch fixed then banked, and insert a third tag. Deterministic LRU
		// must retain banked+third and evict fixed without a fourth hit edge.
		sound_read(19'h08020); drop_sound();
		sound_read(19'h10020); drop_sound();
		sound_read(19'h08020, 3); drop_sound();
		sound_read(19'h10020, 3); drop_sound();
		before_reads = sound_reads;
		sound_read(19'h14020); drop_sound();
		sound_read(19'h10020, 3); drop_sound();
		sound_read(19'h14020, 3); drop_sound();
		assert (sound_reads == before_reads+1)
			else $fatal(1, "SOUND third-tag fill displaced a recently used way");
		sound_read(19'h08020); drop_sound();
		assert (sound_reads == before_reads+2)
			else $fatal(1, "SOUND deterministic victim was not the fixed line");

		// Straddle both the 8-byte line and the 16-KiB ROM-bank boundary.
		sound_read(19'h44020); drop_sound();
		sound_read(19'h47fff); drop_sound();
		sound_read(19'h48000); drop_sound();

        // Abort a resident probe before its response edge, including a changed
        // unacknowledged signature (adversarial cancellation, not normal CPU use).
        sound_read(19'h10020); drop_sound();
        @(negedge clk); sound_addr = 19'h10021; sound_req = 1;
        @(posedge clk); #1; assert (!sound_ack) else $fatal(1, "combinational/early hit ACK");
        @(negedge clk); quiesce = 1;
        no_sound_ack(4);
        @(negedge clk); sound_req = 0; quiesce = 0;
        no_sound_ack(2);
        sound_read(19'h10021, 3);
        drop_sound();
        // Cancel after synchronous RAM/tag evaluation, immediately before the
        // third response edge. A precomputed hit is not permission to ACK.
        @(negedge clk); sound_addr = 19'h10022; sound_req = 1;
        repeat (2) begin @(posedge clk); #1; assert (!sound_ack) else $fatal(1, "early registered hit"); end
        @(negedge clk); quiesce = 1;
        no_sound_ack(4);
        @(negedge clk); sound_req = 0; quiesce = 0;
        no_sound_ack(2);
        sound_read(19'h10022, 3);
        before_acks = ack_count;
        @(negedge clk); quiesce = 1;
        no_sound_ack(3);
        @(negedge clk); quiesce = 0;
        no_sound_ack(3);
        assert (ack_count == before_acks) else $fatal(1, "quiesce replayed an ACKed held request");
        drop_sound();
        @(negedge clk); sound_addr = 19'h10022; sound_req = 1;
        @(posedge clk); #1;
        @(negedge clk); sound_addr = 19'h10023;
        @(posedge clk); #1; assert (!sound_ack) else $fatal(1, "old signature ACKed replacement");
        drop_sound();
        sound_read(19'h10023, 3); drop_sound();

        // Changing a canceled outstanding miss to a resident index must wait
        // for the old physical refill to drain. It cannot read RAM during that
        // write edge, ACK the old signature, or publish the canceled cache line.
        before_reads = sound_reads;
        @(negedge clk); hold_returns = 1; sound_addr = 19'h33180; sound_req = 1;
        timeout = 0;
        while (!(model_active && model_read && model_address == SOUND_BASE + 28'h33180) && timeout < 500) begin
            @(negedge clk); timeout++;
        end
        assert (timeout < 500) else $fatal(1, "cancel/refill miss not accepted");
        sound_addr = 19'h20aa0;
        no_sound_ack(8);
        @(negedge clk); hold_returns = 0;
        timeout = 0;
        do begin @(posedge clk); #1; timeout++; end while (!sound_ack && timeout < 500);
        assert (sound_ack && sound_rdata == pattern(SOUND_BASE + 28'h20aa0))
            else $fatal(1, "canceled refill escaped instead of resident replacement");
		assert (sound_reads == before_reads+1 &&
			!(dut.sound_cache_valid_way0[9'h030] &&
			  dut.sound_cache_way0[9'h030][70:64] == 7'h33) &&
			!(dut.sound_cache_valid_way1[9'h030] &&
			  dut.sound_cache_way1[9'h030][70:64] == 7'h33))
			else $fatal(1, "canceled refill was published or replacement missed");
		drop_sound();
		sound_read(19'h30180, 3); drop_sound();
		assert (sound_reads == before_reads+1)
			else $fatal(1, "canceled refill displaced the untouched resident way");
		sound_read(19'h33180); drop_sound();
        assert (sound_reads == before_reads+2)
            else $fatal(1, "canceled SOUND refill supplied a later cache hit");

        cancel_and_replace(19'h501c0, 19'h501c0);
        cancel_and_replace(19'h501e0, 19'h601e0);
        refill_boundary(19'h541d0, 0);
        refill_boundary(19'h641d0, 1);
        refill_boundary(19'h741d0, 2);

        // Warm reset while a cold read is already accepted must drain silently.
        @(negedge clk); hold_returns = 1; sound_addr = 19'h32120; sound_req = 1;
        timeout = 0;
        while (!(model_active && model_read && model_address == SOUND_BASE + 28'h32120) && timeout < 500) begin
            @(negedge clk); timeout++;
        end
        assert (timeout < 500) else $fatal(1, "cold SOUND miss never accepted");
        quiesce = 1; framework_reset = 1; sound_req = 0;
        no_sound_ack(8);
        @(negedge clk); hold_returns = 0;
        no_sound_ack(20);
        @(negedge clk); framework_reset = 0;
        no_sound_ack(5);
        @(negedge clk); quiesce = 0;
        sound_read(19'h32120); drop_sound();
        sound_read(19'h20aa0); drop_sound();

        // Both download boundaries invalidate the resident cache. The synthetic
        // epoch changes the same physical byte without introducing any ROM data.
        before_reads = sound_reads;
        @(negedge clk); sound_addr = 19'h32121; sound_req = 1;
        @(posedge clk); #1; assert (!sound_ack) else $fatal(1, "early pre-loader ACK");
        @(negedge clk); ioctl_download = 1; image_epoch = 8'h69;
        no_sound_ack(4);
        @(negedge clk); assert (!ioctl_wait) else $fatal(1, "loader not ready");
        ioctl_wr = 1; ioctl_addr = 27'd0; ioctl_data = 16'h1234;
        @(posedge clk); #1; assert (ioctl_wait && !sound_ack) else $fatal(1, "loader capture failed");
        @(negedge clk); ioctl_wr = 0;
        no_sound_ack(20);
		@(negedge clk); sound_req = 0; ioctl_download = 0;
		wait_loaded();
		assert (dut.sound_cache_valid_way0 == '0 && dut.sound_cache_valid_way1 == '0)
			else $fatal(1, "reload left a valid SOUND cache way");
		sound_read(19'h32120); drop_sound();
		sound_read(19'h20aa0); drop_sound();
		assert (sound_reads == before_reads+2)
			else $fatal(1, "reload failed to invalidate every SOUND index");

        // Persistent SAMPLE and VRAM producers cannot starve an unrelated SOUND
        // miss. Include resident SOUND hits while drains and collector run.
        @(negedge clk); traffic = 1; fairness_watch = 1;
        repeat (20) @(negedge clk);
        for (integer j=0; j<12; j++) begin
            sound_read(19'h30020 + 19'(j*16));
            for (integer i=1; i<4; i++) sound_read(19'h30020 + 19'(j*16+i), 3);
            drop_sound();
        end
        // Strictly continuous SAMPLE has priority over VRAM by design. Restore
        // realistic finite gaps after complete four-word fetches, then require
        // VRAM progress while SOUND hits and misses continue.
        @(negedge clk); continuous_sample = 0;
        for (integer j=0; j<12; j++) begin
            sound_read(19'h34020 + 19'(j*16));
            for (integer i=1; i<4; i++) sound_read(19'h34020 + 19'(j*16+i), 3);
            drop_sound();
        end
        @(negedge clk); traffic = 0; fairness_watch = 0;
        repeat (100) @(negedge clk);
        assert (samples_done > 16 && qwrites_done > 16 && sound_grants >= 12)
            else $fatal(1, "fairness fixture made insufficient progress sample=%0d vram=%0d sound=%0d",
                samples_done, qwrites_done, sound_grants);
        assert (max_grants <= 4) else $fatal(1, "quota exceeded");
        assert (hit_during_drain != 0) else $fatal(1, "resident-hit/write-drain overlap not exercised");
		$display("PASS SOUND_SERVICE resident=3 edges 2way/512sets/fulltag/LRU/byte/bank/signature/reset/reload/scan/fairness sample=%0d vram=%0d sound_grants=%0d max_sample_grants=%0d hit_drain_edges=%0d",
            samples_done, qwrites_done, sound_grants, max_grants, hit_during_drain);
        $finish;
    end

    initial begin
        #2ms;
        $fatal(1, "SOUND_SERVICE watchdog state=%0d front=%0d", dut.state, dut.sound_front_state);
    end
endmodule
