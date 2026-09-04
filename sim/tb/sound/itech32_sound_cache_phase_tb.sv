// SPDX-License-Identifier: GPL-3.0-or-later
// ROM-free integration check: real sound CPU, board bridges, SOUND cache and
// upstream DDR terminator. The tiny program below is authored test stimulus.
// This proves resident latency fits native CPU phases in an unloaded fixture;
// it does not prove full-game pace, cache miss bounds or physical DDR timing.
`timescale 1ns/1ps
module itech32_sound_cache_phase_tb;
    localparam integer CLK_HZ = 47_727_273;
    localparam integer WINDOW_CYCLES = 500_000;
    logic clk = 0, reset = 1, download = 0;
    wire loaded, board_reset = reset || !loaded;
    always #10.476 clk = ~clk;
    wire ce8, ce16, ce2;
    itech32_rate_enable #(.CLK_HZ(CLK_HZ), .RATE_HZ(8_000_000)) n8(clk,board_reset,ce8);
    itech32_rate_enable #(.CLK_HZ(CLK_HZ), .RATE_HZ(16_000_000)) n16(clk,board_reset,ce16);
    itech32_rate_enable #(.CLK_HZ(CLK_HZ), .RATE_HZ(2_000_000)) n2(clk,board_reset,ce2);
    wire sound_req, sound_ack, sample_req, sample_ack;
    wire [18:0] sound_addr;
    wire [7:0] sound_data;
    wire [1:0] sample_bank;
    wire [21:0] sample_addr;
    wire [15:0] sample_data;
    itech32_sound_board sound(
        .clk(clk), .reset(board_reset), .rev1_mode(1'b0),
        .ce_8m(ce8), .ce_16m(ce16), .ce_2m(ce2),
        .main_command_valid(1'b0), .main_command(8'd0), .main_command_ready(),
        .main_special_read(1'b0), .sound_special(), .command_pending(),
        .sound_req(sound_req), .sound_addr(sound_addr), .sound_ack(sound_ack), .sound_rdata(sound_data),
		.sample_req(sample_req), .sample_bank(sample_bank), .sample_addr(sample_addr),
		.sample_ack(sample_ack), .sample_rdata(sample_data),
		.pot_compare_pin_i(1'b0), .pot_res_pin_o(),
		.audio_left(), .audio_right(), .audio_strobe(), .sound_irq(), .sound_firq(),
        .es_irq_debug(), .sound_bank(), .cpu_mem_valid(), .cpu_addr(), .cpu_write(),
        .cpu_wdata(), .cpu_debug_regs());
    wire cbusy, crd, cwe, crvalid;
    wire [7:0] cburst, cbe;
    wire [28:0] caddr;
    wire [63:0] crdata, cwdata;
    itech32_ddr_memory #(.VRAM_CLEAR_LINES(8)) memory(
        .clk(clk), .reset(reset), .timekill_mode(1'b0), .bloodstorm_mode(1'b0), .quiesce(1'b0),
        .ioctl_download(download), .ioctl_wr(1'b0), .ioctl_index(16'd0), .ioctl_addr(27'd0),
        .ioctl_data(16'd0), .ioctl_wait(), .rom_loaded(loaded), .vector_load_we(),
        .vector_load_addr(), .vector_load_wdata(), .vector_load_be(),
        .main_req(1'b0), .main_addr(22'd0), .main_ack(), .main_rdata(),
        .grom_req(1'b0), .grom_addr(26'd0), .grom_ack(), .grom_rdata(),
        .sound_req(sound_req), .sound_addr(sound_addr), .sound_ack(sound_ack), .sound_rdata(sound_data),
        .sample_req(sample_req), .sample_bank(sample_bank), .sample_addr(sample_addr),
        .sample_ack(sample_ack), .sample_rdata(sample_data),
        .vram_req(1'b0), .vram_we(1'b0), .vram_addr(20'd0), .vram_wdata(16'd0), .vram_be(2'd0),
        .vram_ack(), .vram_rdata(), .vram_qwrite_req(1'b0), .vram_qwrite_addr(18'd0),
        .vram_qwrite_data(64'd0), .vram_qwrite_be(8'd0), .vram_qwrite_token(1'b0), .vram_qwrite_ack(),
        .scan_req(1'b0), .scan_addr(20'd0), .scan_accept(), .scan_data_valid(), .scan_rdata(), .scan_last(),
        .DDRAM_CLK(), .DDRAM_BUSY(cbusy), .DDRAM_BURSTCNT(cburst), .DDRAM_ADDR(caddr),
        .DDRAM_DOUT(crdata), .DDRAM_DOUT_READY(crvalid), .DDRAM_DIN(cwdata), .DDRAM_BE(cbe),
        .DDRAM_RD(crd), .DDRAM_WE(cwe));
    logic busy = 0, rvalid = 0;
    logic [63:0] rdata = 0;
    wire rd, we;
    wire [7:0] burst, be;
    wire [28:0] addr;
    wire [63:0] wdata;
    f2sdram_safe_terminator #(.DATA_WIDTH(64), .BURSTCOUNT_WIDTH(8)) terminator(
        .clk(clk), .rst_req_sync(reset), .waitrequest_master(busy), .burstcount_master(burst),
        .address_master(addr), .readdata_master(rdata), .readdatavalid_master(rvalid),
        .read_master(rd), .writedata_master(wdata), .byteenable_master(be), .write_master(we),
        .waitrequest_slave(cbusy), .burstcount_slave(cburst), .address_slave(caddr),
        .readdata_slave(crdata), .readdatavalid_slave(crvalid), .read_slave(crd),
        .writedata_slave(cwdata), .byteenable_slave(cbe), .write_slave(cwe));

    function automatic logic [7:0] authored_byte(input logic [27:0] a);
        // The production fixed map preserves CPU $F000 as sound offset $0F000.
        case (a)
            28'h040f000: return 8'h86; // LDA #$5A
            28'h040f001: return 8'h5a;
            28'h040f002: return 8'hb7; // STA $2000
            28'h040f003: return 8'h20;
            28'h040f004: return 8'h00;
            28'h040f005: return 8'hb6; // LDA $2000
            28'h040f006: return 8'h20;
            28'h040f007: return 8'h00;
            28'h040f008: return 8'h20; // BRA $F002
            28'h040f009: return 8'hf8;
            28'h040fffe: return 8'hf0;
            28'h040ffff: return 8'h00;
            default: return 8'h12; // Authored NOP padding, not a ROM dump.
        endcase
    endfunction
    function automatic logic [63:0] authored_line(input logic [27:0] a);
        logic [63:0] q;
        for (integer k=0;k<8;k++) q[k*8+:8]=authored_byte(a+28'(k));
        return q;
    endfunction
    wire [27:0] logical_address = {addr[24:0],3'b000};
    bit model_active = 0, armed = 1;
    integer delay_left = 0, transactions = 0, physical_sound_reads = 0;
    logic [27:0] held_address = 0;
    always @(posedge clk) begin
        rvalid <= 0;
        if (reset) begin busy<=0; model_active<=0; armed<=1; transactions<=0; end
        else begin
            if (!rd && !we) armed<=1;
            if (!model_active && armed && !busy && (rd || we)) begin
                assert (burst==1 && !(rd&&we)) else $fatal(1,"unexpected DDR burst");
                assert (logical_address<28'h100 ||
                    (rd && logical_address>=28'h0400000 && logical_address<28'h0480000) ||
                    (we && logical_address>=28'h2e00000 && logical_address<28'h2e00040))
                    else $fatal(1,"unexpected DDR address %h",logical_address);
                if (rd && logical_address>=28'h0400000 && logical_address<28'h0480000)
                    physical_sound_reads++;
                armed<=0; model_active<=rd; busy<=rd;
                held_address<=logical_address;
                delay_left<=(transactions%4)+1; transactions<=transactions+1;
            end else if (model_active) begin
                if (delay_left!=0) delay_left<=delay_left-1;
                else if (busy) busy<=0;
                else begin rdata<=authored_line(held_address); rvalid<=1; model_active<=0; end
            end
        end
    end

    integer writes=0, reads=0, window_writes=0, window_reads=0;
    integer cycles=0, window_cycles=0, nominal_e=0, accepted_e=0, blocked_ce8=0;
    integer warm_ddr_reads=0, resident_acks=0, interval23=0, interval24=0, last_e=0;
    bit measuring=0;
    integer trace_commits=0;
    always @(posedge clk) begin
        if (!board_reset) begin
            cycles++;
            if ($test$plusargs("TRACE") && trace_commits<150 &&
                (sound.cpu_read_commit || sound.cpu_write_commit)) begin
                trace_commits++;
                $display("TRACE cycle=%0d PC=%h addr=%h write=%0b wdata=%h rdata=%h phase=%0d",
                    cycles,sound.cpu_debug_regs[111:96],sound.cpu_bus_addr_q,
                    sound.cpu_write_commit,sound.cpu_bus_wdata_q,sound.cpu_rdata,sound.cpu_phase);
            end
            assert (!sample_req) else $fatal(1,"stopped ES unexpectedly fetched a sample");
            if (sound_ack)
                assert (sound_data==authored_byte(28'h0400000+{9'd0,sound_addr}))
                    else $fatal(1,"wrong SOUND byte %h: %h",sound_addr,sound_data);
            if (sound.cpu_write_commit && sound.cpu_bus_addr_q==16'h2000) begin
                assert (sound.cpu_bus_wdata_q==8'h5a) else $fatal(1,"RAM write corruption");
                writes++;
                if (measuring) window_writes++;
            end
            if (sound.cpu_read_commit && sound.cpu_bus_addr_q==16'h2000) begin
                // Extended STA may perform an initial target read before its
                // first write. RAM's pre-store value is not program output.
                if (writes>0) begin
                    assert (sound.cpu_rdata==8'h5a)
                        else $fatal(1,"RAM read corruption data=%h PC=%h writes=%0d",
                            sound.cpu_rdata,sound.cpu_debug_regs[111:96],writes);
                    reads++;
                    if (measuring) window_reads++;
                end
            end
            if (measuring) begin
                window_cycles++;
                if (ce2) nominal_e++;
                if (ce8 && sound.sound_cpu.wait_hold) blocked_ce8++;
                if (sound_ack) resident_acks++;
                if (sound.cpu_ce_e) begin
                    accepted_e++;
                    if (last_e) begin
                        assert (cycles-last_e==23 || cycles-last_e==24)
                            else $fatal(1,"resident E interval %0d carriers",cycles-last_e);
                        if (cycles-last_e==23) interval23++; else interval24++;
                    end
                    last_e=cycles;
                end
                assert (physical_sound_reads==warm_ddr_reads)
                    else $fatal(1,"resident program returned to external DDR");
                if (window_cycles==WINDOW_CYCLES) begin
                    assert (blocked_ce8==0) else $fatal(1,"resident cache blocked %0d CE8",blocked_ce8);
                    assert (accepted_e>=nominal_e-1 && accepted_e<=nominal_e+1)
                        else $fatal(1,"E count actual=%0d nominal=%0d",accepted_e,nominal_e);
                    assert (window_writes>500 && window_reads>500 && resident_acks>3000)
                        else $fatal(1,"insufficient useful program work");
                    assert (interval23>0 && interval24>0) else $fatal(1,"native cadence classes absent");
                    $display("PASS SOUND_CACHE_PHASE resident_carriers=%0d blocked_CE8=%0d E=%0d nominal_E=%0d writes=%0d reads=%0d resident_ACK=%0d cold_DDR_reads=%0d E23=%0d E24=%0d",
                        window_cycles,blocked_ce8,accepted_e,nominal_e,window_writes,window_reads,
                        resident_acks,warm_ddr_reads,interval23,interval24);
                    $finish;
                end
            end else if (writes>=64 && reads>=64) begin
				assert ((memory.sound_cache_valid_way0[0] ||
					memory.sound_cache_valid_way1[0]) &&
					(memory.sound_cache_valid_way0[1] ||
					 memory.sound_cache_valid_way1[1]))
                    else $fatal(1,"both code qwords are not resident");
                assert (physical_sound_reads>=3) else $fatal(1,"cold fill not exercised");
                warm_ddr_reads=physical_sound_reads;
                measuring=1;
                $display("WARMUP carriers=%0d writes=%0d reads=%0d DDR_reads=%0d",cycles,writes,reads,warm_ddr_reads);
            end
        end
    end
    initial begin
        repeat (20) @(negedge clk); reset=0;
        repeat (4) @(negedge clk); download=1;
        repeat (4) @(negedge clk); download=0;
    end
    initial begin
        repeat (1_000_000) @(negedge clk);
        $fatal(1,"cache/phase watchdog PC=%h writes=%0d reads=%0d",sound.cpu_debug_regs[111:96],writes,reads);
    end
endmodule
