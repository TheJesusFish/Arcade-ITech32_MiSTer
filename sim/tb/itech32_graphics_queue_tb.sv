// SPDX-License-Identifier: GPL-3.0-or-later
// Actual board (blitter + gather/FIFO + forward slice) -> actual DDR service
// -> actual sys safe terminator -> synthetic, backpressured memory device.
// Only the CPU and external memory/scan consumer stimulus are modeled.
`timescale 1ns/1ps
module itech32_graphics_queue_tb;
    localparam int VRAM_QWORDS = 262144;
    localparam logic [28:0] VRAM_WORD_BASE = 29'h065c0000;
    localparam logic [28:0] GROM_WORD_BASE = 29'h060a0000;
    logic clk = 0, reset = 1, board_reset = 1, download = 0, loaded;
    always #5 clk = ~clk;
    logic grom_req, grom_ack;
    logic [25:0] grom_addr;
    logic [63:0] grom_data;
    logic vreq, vwe, vack;
    logic [19:0] vaddr;
    logic [15:0] vwdata, vrdata;
    logic [1:0] vbe;
    logic qreq, qack, qtoken;
    logic [17:0] qaddr;
    logic [63:0] qdata;
    logic [7:0] qbe;
    logic busy, done_irq;
    logic scan_probe = 0, scan_accept, scan_valid, scan_last;
    logic [19:0] scan_address = 0;
    logic [63:0] scan_data;
    logic board_scan_req;
    logic [19:0] board_scan_addr;
    logic cbusy, crd, cwe, cvalid;
    logic [28:0] caddr;
    logic [7:0] ccount, cbe;
    logic [63:0] cdin, cdout;
    logic mbusy, mrd, mwe, mvalid = 0;
    logic [28:0] maddr;
    logic [7:0] mcount, mbe;
    logic [63:0] mdin, mdout = 0;

    itech32_board board (
        .clk(clk), .reset(board_reset), .timekill_mode(1'b0), .bloodstorm_mode(1'b0),
        .rom_buffer_invalidate(1'b0), .ce_cpu(1'b0), .ce_pixel(1'b0),
        .vector_load_we(1'b0), .vector_load_addr(5'd0), .vector_load_wdata(32'd0), .vector_load_be(4'd0),
        .input_p1('1), .input_p2('1), .input_p3('1), .input_p4('1), .input_dips('1), .input_extra('1),
        .protection_address(15'd0), .nvram_host_access(1'b0), .nvram_host_write(1'b0),
        .nvram_host_addr(17'd0), .nvram_host_wdata(16'd0), .auxiliary_irq_level(3'd0),
        .program_rom_ack(1'b0), .program_rom_rdata(32'd0),
        .grom_req(grom_req), .grom_addr(grom_addr), .grom_ack(grom_ack), .grom_rdata(grom_data),
        .vram_mem_req(vreq), .vram_mem_we(vwe), .vram_mem_addr(vaddr), .vram_mem_wdata(vwdata),
        .vram_mem_be(vbe), .vram_mem_ack(vack), .vram_mem_rdata(vrdata),
        .vram_qwrite_req(qreq), .vram_qwrite_addr(qaddr), .vram_qwrite_data(qdata),
        .vram_qwrite_be(qbe), .vram_qwrite_token(qtoken), .vram_qwrite_ack(qack),
        .scanline_req(board_scan_req), .scanline_addr(board_scan_addr),
        .scanline_accept(scan_accept), .scanline_data_valid(scan_valid),
        .scanline_rdata(scan_data), .scanline_last(scan_last), .blitter_busy(busy), .irq_blitter(done_irq)
    );

    // A single-beat scan consumer makes read-after-completion checks precise.
    // The board raster stays unconfigured; no internal write connection is mocked.
    itech32_ddr_memory #(.VRAM_CLEAR_LINES(8), .VRAM_WRITE_COMBINE(1'b1), .SCAN_BURST_WORDS(1)) memory (
        .clk(clk), .reset(reset), .timekill_mode(1'b0), .bloodstorm_mode(1'b0),
        .quiesce(1'b0),
        .ioctl_download(download), .ioctl_wr(1'b0), .ioctl_index(16'd0),
        .ioctl_addr(27'd0), .ioctl_data(16'd0), .rom_loaded(loaded),
        .main_req(1'b0), .main_addr(22'd0),
        .grom_req(grom_req), .grom_addr(grom_addr), .grom_ack(grom_ack), .grom_rdata(grom_data),
        .sound_req(1'b0), .sound_addr(19'd0), .sample_req(1'b0), .sample_bank(2'd0), .sample_addr(22'd0),
        .vram_req(vreq), .vram_we(vwe), .vram_addr(vaddr), .vram_wdata(vwdata), .vram_be(vbe),
        .vram_ack(vack), .vram_rdata(vrdata),
        .vram_qwrite_req(qreq), .vram_qwrite_addr(qaddr), .vram_qwrite_data(qdata),
        .vram_qwrite_be(qbe), .vram_qwrite_token(qtoken), .vram_qwrite_ack(qack),
        .scan_req(scan_probe || board_scan_req), .scan_addr(scan_probe ? scan_address : board_scan_addr),
        .scan_accept(scan_accept), .scan_data_valid(scan_valid), .scan_rdata(scan_data), .scan_last(scan_last),
        .DDRAM_BUSY(cbusy), .DDRAM_ADDR(caddr), .DDRAM_BURSTCNT(ccount), .DDRAM_DIN(cdin),
        .DDRAM_BE(cbe), .DDRAM_RD(crd), .DDRAM_WE(cwe), .DDRAM_DOUT(cdout), .DDRAM_DOUT_READY(cvalid)
    );
    f2sdram_safe_terminator #(.DATA_WIDTH(64), .BURSTCOUNT_WIDTH(8)) terminator (
        .clk(clk), .rst_req_sync(reset), .waitrequest_master(mbusy), .burstcount_master(mcount),
        .address_master(maddr), .readdata_master(mdout), .readdatavalid_master(mvalid),
        .read_master(mrd), .writedata_master(mdin), .byteenable_master(mbe), .write_master(mwe),
        .waitrequest_slave(cbusy), .burstcount_slave(ccount), .address_slave(caddr),
        .readdata_slave(cdout), .readdatavalid_slave(cvalid), .read_slave(crd),
        .writedata_slave(cdin), .byteenable_slave(cbe), .write_slave(cwe)
    );

    logic [63:0] ram [0:VRAM_QWORDS-1];
    logic [63:0] expected [0:VRAM_QWORDS-1];
    logic [63:0] accepted_by_memory [0:VRAM_QWORDS-1];
    bit touched [0:VRAM_QWORDS-1];
    int last_pixel_qword = 0;
    logic [31:0] rng = 32'h1, seed;
    bit random_wait = 0, hold_writes = 0, monitor = 0;
    int read_left = 0, read_delay = 0, write_left = 0;
    logic [28:0] read_at, write_at;
    int memory_writes = 0, memory_reads = 0, wait_cycles = 0;

    function automatic logic [7:0] graphics_byte(input int address);
        return 8'(1 + address % 251);
    endfunction
    function automatic logic [7:0] rom_byte(input int address);
        int encoded;
        if (address >= 65536 && address < 98304) begin
            encoded=address-65536;
            // Authored RLE stream: 16-byte literal packets, not game data.
            if (encoded%17==0) return 8'h90;
            return graphics_byte((encoded/17)*16 + (encoded%17)-1);
        end
        return graphics_byte(address);
    endfunction
    function automatic logic [63:0] read_word(input logic [28:0] address);
        logic [63:0] value;
        value = 0;
        if (address >= VRAM_WORD_BASE && address < VRAM_WORD_BASE + 29'(VRAM_QWORDS))
            return ram[18'(address - VRAM_WORD_BASE)];
        if (address >= GROM_WORD_BASE && address < GROM_WORD_BASE + 29'h100000)
            for (int b=0; b<8; b++) value[b*8+:8] = rom_byte((int'(address)-int'(GROM_WORD_BASE))*8+b);
        return value;
    endfunction
    // Avalon accepts EVERY asserted beat with !waitrequest; no artificial
    // request-edge/re-arm filter that could conceal a duplicated write.
    always @(negedge clk) begin
        rng = {rng[30:0], rng[31]^rng[21]^rng[1]^rng[0]};
        mbusy = (read_left != 0) || (hold_writes && mwe) ||
                (random_wait && (rng[2:0] < 5));
    end
    always @(posedge clk) begin : external_memory
        logic [28:0] accepted_address;
        mvalid <= 0;
        if (!reset) begin
            if ((mrd || mwe) && mbusy) wait_cycles++;
            if (read_left != 0) begin
                if (read_delay != 0) read_delay--;
                else begin
                    mdout <= read_word(read_at); mvalid <= 1;
                    read_at++; read_left--;
                    read_delay = random_wait ? int'(rng[5:4]) : 0;
                end
            end
            if (mrd && !mbusy) begin
                assert (!mwe && read_left == 0 && write_left == 0 && mcount > 0)
                    else $fatal(1, "illegal external read overlap");
                read_at = maddr; read_left = int'(mcount); read_delay = 2;
                memory_reads++;
            end
            if (mwe && !mbusy) begin
                assert (!mrd && mcount > 0) else $fatal(1, "illegal external write");
                if (write_left == 0) begin write_at = maddr; write_left = int'(mcount); end
                accepted_address = write_at;
                assert (accepted_address >= VRAM_WORD_BASE && accepted_address < VRAM_WORD_BASE + 29'(VRAM_QWORDS))
                    else $fatal(1, "write outside synthetic VRAM %h", accepted_address);
                for (int b=0; b<8; b++) if (mbe[b])
                    ram[18'(accepted_address - VRAM_WORD_BASE)][b*8+:8] = mdin[b*8+:8];
                write_at++; write_left--; memory_writes++;
            end
        end
    end

    typedef logic [89:0] entry_t;
    entry_t gathered[$], sliced[$];
    int pixels = 0, emitted = 0, forwarded = 0, delivered = 0;
    int cancelled_queue = 0, cancelled_slice = 0;
    bit previous_token, token_seen = 0;
    int full_cycles = 0, simultaneous_fifo = 0, simultaneous_slice = 0;
    int wrap_writes = 0, wrap_reads = 0, stalled_tail = 0, completions = 0;
    bit check_completion = 0;
    always @(posedge clk) begin : scoreboard
        entry_t item;
        int address, lane;
        if (board_reset) begin
            cancelled_queue += gathered.size(); cancelled_slice += sliced.size();
            gathered.delete(); sliced.delete();
            token_seen=0;
        end else if (monitor) begin
            // Reference image follows accepted source pixels, independent of
            // gathering, FIFO, slice, byte masks, and DDR combining.
            if (board.blit_vram_req && board.blit_vram_we && board.blit_vram_ack) begin
                address = int'({board.blit_vram_plane,board.blit_vram_addr}) / 4;
                lane = int'(board.blit_vram_addr[1:0]);
                expected[address][lane*16+:16] = {board.blit_vram_wdata[7:0],board.blit_vram_wdata[15:8]};
                touched[address] = 1; last_pixel_qword = address;
                pixels++;
            end
            // Record actual gather emissions BEFORE the real queue. Compare
            // exact order/data/masks at both subsequent acceptance boundaries.
            if (board.vram_arbiter.emit_gather) begin
                gathered.push_back({board.vram_arbiter.gather_addr,
                                    board.vram_arbiter.gather_data,board.vram_arbiter.gather_be});
                emitted++;
            end
            if (board.arb_qwrite_req && board.arb_qwrite_ack) begin
                assert (gathered.size() != 0) else $fatal(1, "duplicate queue output");
                item = gathered.pop_front();
                assert (item === {board.arb_qwrite_addr,board.arb_qwrite_data,board.arb_qwrite_be})
                    else $fatal(1, "queue output lost/reordered/corrupted");
                sliced.push_back(item); forwarded++;
            end
            if (qreq && qack) begin
                assert (sliced.size() != 0) else $fatal(1, "duplicate slice output");
                item = sliced.pop_front();
                assert (item === {qaddr,qdata,qbe}) else $fatal(1, "slice output lost/reordered/corrupted");
                assert (!token_seen || qtoken != previous_token) else $fatal(1,"qword token did not advance");
                token_seen=1; previous_token=qtoken;
                for(int b=0;b<8;b++) if(qbe[b]) accepted_by_memory[qaddr][b*8+:8]=qdata[b*8+:8];
                delivered++;
            end
            if (board.vram_arbiter.fifo_full) full_cycles++;
            if (board.vram_arbiter.fifo_read && board.vram_arbiter.fifo_write) simultaneous_fifo++;
            if (qreq && qack && board.arb_qwrite_req && board.arb_qwrite_ack) simultaneous_slice++;
            if (board.vram_arbiter.fifo_write && board.vram_arbiter.fifo_wr_ptr == 8'hff) wrap_writes++;
            if (board.vram_arbiter.fifo_read && board.vram_arbiter.fifo_rd_ptr == 8'hff) wrap_reads++;
            if (check_completion && board.blitter.state == 4'd13 && board.vram_writes_pending) stalled_tail++;
            if (check_completion && board.blitter.blitter_done_pulse) begin
                assert (!board.vram_writes_pending && !board.vram_arbiter.writes_pending &&
                        !board.qwrite_slice_valid && gathered.size()==0 && sliced.size()==0)
                    else $fatal(1, "completion escaped pending graphics writes");
                completions++;
            end
            assert (!board_scan_req) else $fatal(1, "unexpected unconfigured raster request");
        end
    end

    task automatic cpu_write(input logic [23:0] address, input logic [31:0] data, input logic [3:0] be);
        logic [31:0] unused_result;
        board.main_cpu.transaction(1, address, data, be, unused_result);
    endtask
    task automatic reg_write(input logic [6:0] address, input logic [15:0] value);
        cpu_write(24'h500000 + 24'(address)*4, {value,16'd0}, 4'hc);
    endtask
    task automatic configure(input int width, height, x, y);
        reg_write(7'h03,16'h0400); reg_write(7'h06,16'(height)); reg_write(7'h07,16'(width));
        reg_write(7'h08,0); reg_write(7'h17,0);
        reg_write(7'h09,16'(x)); reg_write(7'h0a,16'(y));
        for (int r=11;r<=14;r++) reg_write(7'(r),16'h0100);
        reg_write(7'h0f,0); reg_write(7'h10,0);
        reg_write(7'h12,0); reg_write(7'h13,512); reg_write(7'h14,0); reg_write(7'h15,1024);
    endtask
    task automatic wait_done;
        int timeout;
        timeout=0;
        do begin
            @(negedge clk); timeout++;
            if (timeout>500000) $fatal(1,"drawing timeout state=%d",board.blitter.state);
        end while (busy);
        assert (gathered.size()==0 && sliced.size()==0 && !board.vram_writes_pending)
            else $fatal(1,"drawing idle before write queue empty");
    endtask
    task automatic scan_check(input int qword);
        int timeout;
        @(negedge clk); scan_address=20'(qword*4); scan_probe=1; timeout=0;
        do begin
            @(posedge clk); #1; timeout++;
            if(timeout>100000) $fatal(1,"scan accept timeout");
        end while (!scan_accept);
        @(negedge clk); scan_probe=0;
        do begin
            @(posedge clk); #1; timeout++;
            if(timeout>100000) $fatal(1,"scan data timeout");
        end while (!scan_valid);
        assert (scan_last && scan_data === expected[qword])
            else $fatal(1,"stale scan after completion addr=%h actual=%h expected=%h",qword,scan_data,expected[qword]);
    endtask
    task automatic check_image;
        // A read only guarantees visibility for its requested address; an
        // unrelated read need not flush the DDR collector. Probe the last
        // written word first, then every touched qword before checking RAM.
        scan_check(last_pixel_qword);
        for (int i=0;i<VRAM_QWORDS;i++) if (touched[i]) scan_check(i);
        for (int i=0;i<VRAM_QWORDS;i++)
            assert (ram[i] === expected[i]) else $fatal(1,"VRAM mismatch qword=%h actual=%h expected=%h",i,ram[i],expected[i]);
        assert (emitted==forwarded+cancelled_queue && forwarded==delivered+cancelled_slice)
            else $fatal(1,"lost queue entry");
    endtask

    initial begin : test_sequence
        int before_pixels, before_writes;
        seed=32'h12345678;
        if ($value$plusargs("SEED=%d",seed)) begin end
        rng=seed;
        for(int i=0;i<VRAM_QWORDS;i++) ram[i]=64'hadde_adde_adde_adde;
        repeat(8) @(negedge clk); reset=0;
        repeat(4) @(negedge clk); download=1;
        repeat(4) @(negedge clk); download=0;
        wait(loaded); repeat(4) @(negedge clk);
        for(int i=0;i<VRAM_QWORDS;i++) begin expected[i]=ram[i]; accepted_by_memory[i]=ram[i]; end
        board_reset=0; monitor=1; random_wait=1;
        cpu_write(24'h300003,32'h12,4'h1); cpu_write(24'h380003,32'h34,4'h1);
        cpu_write(24'h700002,32'h400,4'h3); // Plane 0 only.
        configure(509,8,1,4); check_completion=1;
        reg_write(7'h04,1); wait_done(); check_image();
        assert(pixels==4072) else $fatal(1,"raw drawing pixel count");
        // Independently check authored raw pixels and untouched edge lanes.
        for(int y=0;y<8;y++) for(int x=0;x<509;x++) begin
            int word_index;
            logic [15:0] raw_pixel;
            word_index=(4+y)*512+1+x;
            raw_pixel=ram[word_index/4][(word_index%4)*16+:16];
            assert(raw_pixel === {graphics_byte(y*509+x),8'h12}) else $fatal(1,"authored raw pattern mismatch");
        end

        // Command 6 first reads its 512-word source, then replays enough rows
        // to exceed the real 256-entry queue. Stall only after those reads.
        configure(1,9,0,4); before_pixels=pixels;
        reg_write(7'h04,6);
        wait(board.blit_vram_req && board.blit_vram_we);
        @(negedge clk); hold_writes=1;
        repeat(7000) @(negedge clk);
        assert(busy && full_cycles>0) else $fatal(1,"did not saturate actual queue");
        hold_writes=0;
        wait_done(); check_image();
        assert(pixels-before_pixels==4096) else $fatal(1,"command 6 pixel count");
        for(int y=5;y<=12;y++) for(int x=0;x<128;x++)
            assert(ram[y*128+x]===ram[4*128+x]) else $fatal(1,"ordered blitter read/copy mismatch");

        // Both planes, partial qwords, then same addresses with changed colors.
        cpu_write(24'h700002,0,4'h3);
        configure(13,3,3,20); reg_write(7'h04,1); wait_done();
        check_image();
        cpu_write(24'h300003,32'h56,4'h1); cpu_write(24'h380003,32'h78,4'h1);
        reg_write(7'h04,1); wait_done(); check_image();

        // Real RLE producer, both planes, including partial first/last qwords.
        configure(13,3,3,24); reg_write(7'h17,1);
        reg_write(7'h04,2); wait_done(); check_image();
        for(int y=0;y<3;y++) for(int x=0;x<13;x++) begin
            int word_index;
            word_index=(24+y)*512+3+x;
            assert(ram[word_index/4][(word_index%4)*16+:16] === {graphics_byte(y*13+x),8'h56})
                else $fatal(1,"authored RLE pattern mismatch");
        end

        // Retain a final tail under a write stall; completion must not escape.
        cpu_write(24'h700002,32'h400,4'h3);
        configure(1,2,0,4); reg_write(7'h04,6);
        wait(board.blit_vram_req && board.blit_vram_we);
        @(negedge clk); hold_writes=1;
        repeat(2500) @(negedge clk);
        assert(busy && board.vram_writes_pending) else $fatal(1,"tail test did not retain queue data");
        hold_writes=0; wait_done(); check_image();

        // Board reset intentionally cancels upstream queued work, but must not
        // replay it into the next command. Keep the real DDR service running
        // so previously accepted writes finish, as on a game warm reset.
        configure(1,9,0,4); reg_write(7'h04,6);
        wait(board.blit_vram_req && board.blit_vram_we);
        @(negedge clk); hold_writes=1;
        repeat(7000) @(negedge clk);
        assert(board.vram_arbiter.fifo_full && qreq && !qack)
            else $fatal(1,"reset case did not retain queue and slice");
        board_reset=1; check_completion=0;
        repeat(4) @(negedge clk);
        assert(!qreq && !board.vram_writes_pending && gathered.size()==0 && sliced.size()==0)
            else $fatal(1,"reset left queued write valid");
        // Only qwords already accepted by DDR survive a board reset. Its
        // collector may still hold them; ordered reads must make them visible.
        for(int i=0;i<VRAM_QWORDS;i++) expected[i]=accepted_by_memory[i];
        hold_writes=0; check_image();
        before_writes=memory_writes;
        board_reset=0;
        repeat(40) @(negedge clk);
        assert(memory_writes==before_writes && !qreq)
            else $fatal(1,"stale write replayed after reset writes=%0d/%0d qreq=%b state=%0d collect=%b drain=%b fast=%b",
                        memory_writes,before_writes,qreq,memory.state,memory.vram_write_buffer_valid,
                        memory.vram_drain_valid,memory.vram_fast_pending);
        cpu_write(24'h300003,32'h9a,4'h1);
        configure(17,2,2,40); check_completion=1;
        reg_write(7'h04,1); wait_done(); check_image();
        assert(cancelled_queue>0 && cancelled_slice>0) else $fatal(1,"reset cancellation not covered");

        assert(full_cycles>0 && wrap_writes>0 && wrap_reads>0 && simultaneous_fifo>0 &&
               simultaneous_slice>0 && stalled_tail>0)
            else $fatal(1,"missing queue stress coverage full=%0d wrap=%0d/%0d simultaneous=%0d tail=%0d",
                        full_cycles,wrap_writes,wrap_reads,simultaneous_fifo,stalled_tail);
        $display("PASS graphics queue seed=%0d pixels=%0d qwords=%0d full=%0d wraps=%0d/%0d fifo-rw=%0d slice-refill=%0d tail=%0d completions=%0d DDRwait=%0d reset-cancel=%0d/%0d",
                 seed,pixels,delivered,full_cycles,wrap_writes,wrap_reads,simultaneous_fifo,simultaneous_slice,stalled_tail,completions,wait_cycles,cancelled_queue,cancelled_slice);
        $finish;
    end
    initial begin #30ms; $fatal(1,"graphics queue watchdog"); end
endmodule
