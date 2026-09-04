// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1ps

// Independent directed expectations from ENSONIQ OTTO Specification Rev. 2.3:
// https://gjcp.net/pdf/es5506.pdf
// Sections 2 (printed p5), 13 (pp38-39), 14 (p41).
// No manufacturer scan, game program, or ROM-derived stimulus is embedded here.
// CASE=protocol, deferred, deferred-running, stacked, global, multiple-acked,
// or deferred-underrun. Keep protocol
// passes separate from interrupt counterexamples while implementing the spec.
module itech32_es5506_host_spec_tb;
    logic clk = 0, reset = 1, enable_device_clock = 0, ce_16m = 0;
    logic host_req = 0, host_write = 0, host_ack;
    logic [5:0] host_addr = 0;
    logic [7:0] host_wdata = 0, host_rdata;
    logic sample_req, sample_ack = 0;
    logic hold_sample_returns = 0;
    logic [1:0] sample_bank;
    logic [21:0] sample_addr;
    logic [15:0] sample_rdata = 0;
    logic sample_companded;
    logic [4:0] sample_voice;
    logic signed [19:0] audio_left, audio_right;
    logic audio_strobe, irq, engine_busy;
    logic [7:0] irq_vector;
    logic [6:0] current_page;
    logic [4:0] active_voices, scan_voice;
    integer ce_phase = 0;
    integer completed [0:31];
    integer underrun_count = 0;
    logic previous_busy = 0;
    logic [4:0] processing_voice = 0;
    string test_case = "protocol";
    always #5 clk = ~clk;

    // A16 MHz input enable in a synthetic100 MHz unit-test carrier: four pulses per
    // twenty-five clocks, sixteen pulses per voice slot. Never accelerate a
    // stopped voice or pause the device clock during host transactions.
    always @(negedge clk) begin
        ce_16m = 0;
        if (reset || !enable_device_clock) ce_phase = 0;
        else begin
            ce_phase = ce_phase + 16;
            if (ce_phase >= 100) begin ce_phase = ce_phase - 100; ce_16m = 1; end
        end
    end

    itech32_es5506 dut (
        .clk(clk), .reset(reset), .ce_16m(ce_16m),
        .host_req(host_req), .host_write(host_write), .host_addr(host_addr),
        .host_wdata(host_wdata), .host_rdata(host_rdata), .host_ack(host_ack),
		.par_comparator_tripped(1'b0), .par_discharge(),
		.sample_req(sample_req), .sample_bank(sample_bank),
        .sample_addr(sample_addr), .sample_companded(sample_companded),
        .sample_voice(sample_voice), .sample_rdata(sample_rdata), .sample_ack(sample_ack),
        .audio_left(audio_left), .audio_right(audio_right), .audio_strobe(audio_strobe),
        .irq(irq), .irq_vector(irq_vector), .current_page(current_page),
        .active_voices(active_voices), .scan_voice(scan_voice), .engine_busy(engine_busy)
    );

    // Registered synthetic ROM service, including no-gap next-word requests.
    logic sample_served = 0;
    logic [23:0] sample_signature = 0;
    always @(posedge clk) begin
        sample_ack <= 0;
        if (reset || !sample_req) sample_served <= 0;
        else if (!hold_sample_returns &&
            (!sample_served || sample_signature != {sample_bank,sample_addr})) begin
            sample_signature <= {sample_bank,sample_addr};
            sample_rdata <= {sample_addr[7:0], sample_addr[15:8]};
            sample_ack <= 1;
            sample_served <= 1;
        end
    end

    always @(posedge clk) begin
        if (reset) underrun_count <= 0;
        else if (dut.sample_underrun) underrun_count <= underrun_count + 1;
    end

    // Public engine-busy and scan outputs identify completed processing slots.
    // Expectations below do not call the RTL's next-control/IRQ helper logic.
    always @(negedge clk) begin
        if (reset) begin
            previous_busy = 0;
            for (integer i=0; i<32; i++) completed[i] = 0;
        end else begin
            if (!previous_busy && engine_busy) processing_voice = scan_voice;
            if (previous_busy && !engine_busy) completed[processing_voice]++;
            previous_busy = engine_busy;
        end
    end

    task automatic transfer(input logic wr, input logic [5:0] a,
        input logic [7:0] data, output logic [7:0] result);
        integer timeout;
        // This suite does not assign a priority to undocumented exact same-edge
        // voice/host RAM collisions. Start in the early idle part of a real slot;
        // a separate timing/port-arbitration test owns arbitrary-phase traffic.
        @(negedge clk);
        while (enable_device_clock && (engine_busy || dut.slot_count > 8)) @(negedge clk);
        host_req = 1; host_write = wr; host_addr = a; host_wdata = data;
        timeout = 0;
        do begin @(posedge clk); #1; timeout++; end while (!host_ack && timeout < 150);
        assert (host_ack) else $fatal(1, "HOST_SPEC timeout address=%h", a);
        result = host_rdata;
        // Deliberately hold the acknowledged request: it must not commit twice.
        repeat (2) begin @(posedge clk); #1; assert (!host_ack) else $fatal(1, "duplicate host ACK"); end
        @(negedge clk); host_req = 0;
        repeat (2) @(posedge clk);
        #1;
    endtask

    task automatic write_byte(input logic [5:0] a, input logic [7:0] data);
        logic [7:0] ignored;
        transfer(1, a, data, ignored);
    endtask

    task automatic read_byte(input logic [5:0] a, output logic [7:0] data);
        transfer(0, a, 0, data);
    endtask

    task automatic write_reg(input logic [3:0] slot, input logic [31:0] data);
        for (integer i=0; i<4; i++) write_byte({slot,2'(i)}, data[31-i*8 -: 8]);
    endtask

    task automatic read_reg(input logic [3:0] slot, output logic [31:0] data);
        for (integer i=0; i<4; i++) read_byte({slot,2'(i)}, data[31-i*8 -: 8]);
    endtask

    task automatic page(input logic [6:0] p);
        write_reg(4'hf, {25'd0,p});
        assert (current_page == p) else $fatal(1, "PAGE write failed %h -> %h", p,current_page);
    endtask

    task automatic expect_reg(input logic [3:0] slot, input logic [31:0] expected,
        input string label_text);
        logic [31:0] observed;
        read_reg(slot, observed);
        assert (observed == expected) else $fatal(1, "%s expected=%h observed=%h",
            label_text,expected,observed);
    endtask

    task automatic wait_vector(input logic [4:0] expected);
        integer timeout;
        timeout = 0;
        while (!irq && timeout < 4000) begin @(negedge clk); timeout++; end
        #1; // Let the independent slot-completion monitor settle on this edge.
        assert (irq && !irq_vector[7] && irq_vector[4:0] == expected)
            else $fatal(1, "IRQ vector expected=%0d actual=%h irq=%b", expected,irq_vector,irq);
    endtask

    task automatic wait_processed(input logic [4:0] voice, input integer old_count);
        integer timeout;
        timeout = 0;
        while (completed[voice] <= old_count && timeout < 4000) begin @(negedge clk); timeout++; end
        assert (completed[voice] > old_count) else $fatal(1, "voice %0d never processed",voice);
    endtask

    task automatic configure_voice(input logic [4:0] voice, input logic running);
        page({2'b01,voice});
        write_reg(4'h1,32'd0);       // START
        write_reg(4'h2,32'h00100000);// END, never reached with FC=0
        write_reg(4'h3,32'd0);       // ACCUM
        page({2'b00,voice});
        write_reg(4'h1,32'd0);       // FC: no fresh boundary event after forced IRQ
        write_reg(4'h6,32'd0);       // ECOUNT: no envelope mutations
        // Force IRQ using documented IRQE+IRQ. STOPped and running paths both
        // participate in the active scan; neither creates recurring loop IRQs.
        write_reg(4'h0, running ? 32'h000000a0 : 32'h000000a3);
    endtask

    task automatic protocol_case;
        logic [7:0] byte0,b1,b2,b3;
        logic [31:0] snapshot;
        integer p;
        // STOP and ECOUNT=0 remove dynamic volume/register writes from this
        // byte protocol test while the actual voice scheduler keeps advancing.
        write_reg(4'hb,32'd4); // documented minimum: five active voice slots
        enable_device_clock = 1;
        write_reg(4'h0,32'd3);
        write_reg(4'h6,32'd0);
        write_reg(4'h2,32'h00001234);
        write_byte(6'h08,8'hde);
        write_byte(6'h09,8'had);
        write_byte(6'h0a,8'h56);
        expect_reg(4'h2,32'h00001234,"H02 bytes0-2 must not commit LVOL");
        write_byte(6'h0b,8'h78);
        expect_reg(4'h2,32'h00005678,"H02 byte3 commits assembled LVOL");
        read_byte(6'h08,byte0);
        write_reg(4'h2,32'h0000abcd);
        read_byte(6'h09,b1); read_byte(6'h0a,b2); read_byte(6'h0b,b3);
        snapshot = {byte0,b1,b2,b3};
        assert (snapshot == 32'h00005678) else $fatal(1,"H03 snapshot mutated %h",snapshot);
        expect_reg(4'h2,32'h0000abcd,"H03 fresh byte0 takes new snapshot");
        // Defined voice0/15/16/31 pages; no extrapolation to undefined aliases.
        for (integer i=0; i<4; i++) begin
            case(i) 0:p=0; 1:p=15; 2:p=16; default:p=31; endcase
            page(7'(p)); write_reg(4'h1,32'h00010000 + 32'(p));
            page(7'(p+32)); write_reg(4'h3,32'h12345600 + 32'(p));
        end
        for (integer i=0; i<4; i++) begin
            case(i) 0:p=0; 1:p=15; 2:p=16; default:p=31; endcase
            page(7'(p)); expect_reg(4'h1,32'h00010000 + 32'(p),"H04 low page isolation");
            page(7'(p+32)); expect_reg(4'h3,32'h12345600 + 32'(p),"H04 high page isolation");
        end
        page(7'h40);
		expect_reg(4'hd,32'h000003ff,"H04 page40 PAR");
        expect_reg(4'he,32'h00000080,"H04 page40 idle IRQV");
        expect_reg(4'hf,32'h00000040,"H04 page40 PAGE");
        page(7'h00);
        assert (active_voices == 4 && completed[0] != 0)
            else $fatal(1,"protocol test failed to exercise valid active scan");
        $display("PASS ES_HOST_SPEC protocol H02/H03/H04 defined pages, byte3 commit, byte0 snapshot, real CE");
    endtask

    task automatic deferred_case(input logic running);
        logic [31:0] control_before, control_after;
        logic [7:0] ignored;
        integer count_before;
        write_reg(4'hb,32'd4);
        configure_voice(0,running);
        enable_device_clock = 1;
        wait_vector(0);
        // This host read occurs while the vector remains pending, before any
        // IRQV read. CR.IRQ must still be one, even if the voice is reprocessed.
        read_reg(4'h0,control_before);
        assert (control_before[7]) else $fatal(1,
            "I02 CR.IRQ cleared before IRQV read: control=%h running=%0d",control_before,running);
        assert (irq && irq_vector[4:0] == 0) else $fatal(1,"CR read acknowledged IRQ");
        // Read IRQV byte0 near the start of voice1's interval. The causative
        // voice0 cannot be processed for several slots after this transaction.
        while (scan_voice != 1 || engine_busy) @(negedge clk);
        count_before = completed[0];
        read_byte(6'h38,ignored);
        assert (!irq && irq_vector[7]) else $fatal(1,"I02 IRQV byte0 did not deassert IRQ");
        read_reg(4'h0,control_after);
        assert (completed[0] == count_before && control_after[7])
            else $fatal(1,"I02 CR.IRQ clear must wait for causative voice processing");
        wait_processed(0,count_before);
        read_reg(4'h0,control_after);
        assert (!control_after[7] && !irq)
            else $fatal(1,"I02 deferred clear missing or old IRQ replayed: CR=%h irq=%b",control_after,irq);
        $display("PASS ES_HOST_SPEC I02 deferred CR.IRQ clear running=%0d",running);
    endtask

    task automatic stacked_case;
        logic [31:0] pending_control;
        logic [7:0] ignored, old_vector_byte;
        integer count_before;
        write_reg(4'hb,32'd4);
        configure_voice(0,0); configure_voice(2,0); page(0);
        enable_device_clock = 1;
        wait_vector(0);
        count_before = completed[2];
        wait_processed(2,count_before);
        assert (irq && irq_vector[4:0] == 0) else $fatal(1,"I03 stacked voice overwrote busy vector");
        page(2); read_reg(0,pending_control);
        assert (pending_control[7]) else $fatal(1,"I03 stacked pending CR.IRQ lost");
        // Non-IRQV byte0 read and IRQV trailing-byte read must not acknowledge.
        read_byte(6'h3c,ignored); read_byte(6'h3b,old_vector_byte);
        assert (irq && irq_vector[4:0] == 0) else $fatal(1,"H08 trailing byte or PAGE read cleared IRQ");
        read_byte(6'h38,ignored);
        assert (!irq) else $fatal(1,"I03 IRQV read failed to free old vector");
        wait_vector(2);
        // The old 32-bit snapshot must survive a newly advertised interrupt.
        read_byte(6'h3b,old_vector_byte);
        assert (old_vector_byte == 0 && irq && irq_vector[4:0] == 2)
            else $fatal(1,"H08 old IRQV snapshot acknowledged/replaced new vector");
        read_byte(6'h38,ignored);
        count_before = completed[2];
        wait_processed(2,count_before);
        repeat (600) @(negedge clk);
        assert (!irq) else $fatal(1,"I03 acknowledged forced interrupt replayed");
        $display("PASS ES_HOST_SPEC I03 stacked host-forced IRQ and H08 one read side effect");
    endtask

    task automatic global_case;
        logic [7:0] ignored;
        write_reg(4'hb,32'd4);
        configure_voice(0,0);
        enable_device_clock = 1;
        wait_vector(0);
        page(7'h40);
		expect_reg(4'hd,32'h000003ff,"page40 live PAR");
        expect_reg(4'hf,32'h00000040,"page40 live PAGE");
        assert (irq) else $fatal(1,"PAGE/PAR unexpectedly acknowledged IRQ");
        read_byte(6'h38,ignored);
        assert (!irq && irq_vector[7]) else $fatal(1,
            "H04/H08 global IRQV read at page40 did not acknowledge: IRQV=%h",irq_vector);
        $display("PASS ES_HOST_SPEC page40 global PAGE/PAR/IRQV including IRQ acknowledgement");
    endtask

    task automatic multiple_acked_case;
        logic [7:0] ignored;
        integer count0,count2;
        write_reg(4'hb,32'd4);
        configure_voice(0,0); configure_voice(2,0); page(0);
        enable_device_clock = 1;
        wait_vector(0);
        count0 = completed[0];
        read_byte(6'h38,ignored);
        wait_vector(2);
        count2 = completed[2];
        read_byte(6'h38,ignored);
        assert (completed[0] == count0) else $fatal(1,"multiple-ACK fixture missed pre-revisit window");
        wait_processed(0,count0);
        wait_processed(2,count2);
        repeat (600) @(negedge clk);
        assert (!irq) else $fatal(1,"I02 per-voice deferred clear lost after two vector acknowledgements");
        $display("PASS ES_HOST_SPEC independent deferred clear for two acknowledged voices");
    endtask

    task automatic underrun_case;
        logic [7:0] ignored;
        logic [31:0] control_after;
        integer count_before,underruns_before;
        write_reg(4'hb,32'd4);
        configure_voice(0,1);
        enable_device_clock = 1;
        wait_vector(0);
        while (scan_voice != 1 || engine_busy) @(negedge clk);
        read_byte(6'h38,ignored);
        assert (!irq) else $fatal(1,"underrun fixture could not acknowledge initial IRQ");
        hold_sample_returns = 1;
        underruns_before = underrun_count;
        // Change only the zero-frequency oscillator's address, not its CR.
        // FC=0 and the new ACCUM remains strictly between START and END, so no
        // new boundary event can explain a subsequent interrupt.
        page(7'h20); write_reg(4'h3,32'h00080000); page(0);
        count_before = completed[0];
        wait_processed(0,count_before);
        count_before = completed[0];
        wait_processed(0,count_before);
        assert (underrun_count > underruns_before)
            else $fatal(1,"deferred-clear test did not create an actual sample underrun");
        assert (!irq) else $fatal(1,"acknowledged IRQ replayed during sample underrun");
        hold_sample_returns = 0;
        repeat (1800) @(negedge clk);
        read_reg(0,control_after);
        assert (!irq && !control_after[7]) else $fatal(1,
            "I02 deferred clear lost across no-writeback underrun: CR=%h IRQV=%h",control_after,irq_vector);
        $display("PASS ES_HOST_SPEC deferred clear survives genuine sample underrun and refill");
    endtask

    initial begin
        if ($value$plusargs("CASE=%s",test_case)) begin end
        repeat (5) @(negedge clk);
        reset = 0;
        repeat (5) @(negedge clk);
        case (test_case)
            "protocol": protocol_case();
            "deferred": deferred_case(0);
            "deferred-running": deferred_case(1);
            "stacked": stacked_case();
            "global": global_case();
            "multiple-acked": multiple_acked_case();
            "deferred-underrun": underrun_case();
            default: $fatal(1,"unknown CASE=%s",test_case);
        endcase
        $finish;
    end

    initial begin
        #2ms;
        $fatal(1,"ES_HOST_SPEC watchdog CASE=%s IRQV=%h scan=%0d",test_case,irq_vector,scan_voice);
    end
endmodule
