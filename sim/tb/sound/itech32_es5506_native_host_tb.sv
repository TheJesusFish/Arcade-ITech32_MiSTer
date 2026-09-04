// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1fs

// ROM-free native-carrier host/cadence stress. This tests the FPGA's asynchronous
// host abstraction, not pin-exact E/DTACK propagation timing. Manufacturer clock
// relation: ENSONIQ OTTO Rev.2.3, sections 2, 12-14 (https://gjcp.net/pdf/es5506.pdf).
module itech32_es5506_native_host_tb;
    localparam integer CARRIER_HZ = 47_727_273;
    localparam integer INPUT_HZ = 16_000_000;
    localparam realtime HALF_PERIOD_NS = 500_000_000.0 / CARRIER_HZ;
    // Fourteen ES input clocks plus six fabric edges for adapter capture/return.
    // This is a bounded FPGA integration expectation, not a pin-spec assertion.
    localparam integer HOST_BOUND = (14*CARRIER_HZ + INPUT_HZ-1)/INPUT_HZ + 6;
    logic clk = 0, reset = 1, enable_device_clock = 0, ce_16m = 0;
    integer ce_remainder = 0;
    logic host_req = 0, host_write = 0, host_ack;
    logic [5:0] host_addr = 0;
    logic [7:0] host_wdata = 0, host_rdata;
    logic sample_req, sample_ack = 0, sample_companded;
    logic [1:0] sample_bank;
    logic [21:0] sample_addr;
    logic [4:0] sample_voice;
    logic [15:0] sample_rdata = 0;
    logic signed [19:0] audio_left, audio_right;
    logic audio_strobe, irq, engine_busy;
    logic [7:0] irq_vector;
    logic [6:0] current_page;
    logic [4:0] active_voices, scan_voice;
    integer expected_voices = 5;
    integer current_mode = 0;
    integer carrier_cycles = 0, input_ticks = 0, slot_serial = 0;
    integer slot_origin = 0, frame_origin = 0, frames_launched = 0;
    integer frames_output = 0, output_lag = -1;
    integer last_slot_origin = 0, short_slots = 0, long_slots = 0;
    integer max_host_latency = 0, host_sweeps = 0, sample_returns = 0;
    integer late_ce14_attempts = 0;
    logic check_cadence = 0;
    logic [47:0] read_phases = 0, write_phases = 0;
    integer only_mode = -1, only_actv = -1, only_phase = -1, only_write = -1;
    always #(HALF_PERIOD_NS) clk = ~clk;

    // Exact integer ratio, independent of DUT phase counters. The physical
    // test clock is rounded by less than one femtosecond; checks use edge counts.
    always @(negedge clk) begin
        ce_16m = 0;
        if (reset || !enable_device_clock) ce_remainder = 0;
        else begin
            ce_remainder = ce_remainder + INPUT_HZ;
            if (ce_remainder >= CARRIER_HZ) begin
                ce_remainder = ce_remainder - CARRIER_HZ;
                ce_16m = 1;
            end
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

    logic sample_served = 0;
    logic [23:0] sample_signature = 0;
    always @(posedge clk) begin
        sample_ack <= 0;
        if (reset || !sample_req) sample_served <= 0;
        else if (!sample_served || sample_signature != {sample_bank,sample_addr}) begin
            sample_served <= 1;
            sample_signature <= {sample_bank,sample_addr};
            sample_rdata <= {sample_addr[7:0],sample_addr[15:8]} ^ 16'h3157;
            sample_ack <= 1;
        end
    end

    // Directed corner coverage uses pre-edge phase: accepting a pending host
    // read at count14 while CE is high leaves only one input interval before
    // launch. Observing it is not forcing a DUT state or defining IRQ timing.
    always @(posedge clk) begin
        if (reset) late_ce14_attempts <= 0;
        else if (host_req && dut.host_req_q && !dut.host_seen && !engine_busy &&
            dut.slot_count == 14 && ce_16m)
            late_ce14_attempts <= late_ce14_attempts + 1;
    end

    // This oracle derives full-scan launch times only from external CE and the
    // configured active count. Every output must correspond one-to-one with a
    // launch at a fixed fabric-clock lag. Counting CE between delayed strobes
    // alone would falsely call legitimate fractional-clock rounding a jitter.
    always @(posedge clk) begin
        #0.001;
        if (reset) begin
            carrier_cycles = 0; input_ticks = 0; slot_serial = 0;
            slot_origin = 0; frame_origin = 0; frames_launched = 0;
            frames_output = 0; output_lag = -1; last_slot_origin = 0;
            short_slots = 0; long_slots = 0; sample_returns = 0;
        end else begin
            carrier_cycles++;
            if (sample_ack) sample_returns++;
            if (enable_device_clock && ce_16m) begin
                input_ticks++;
                if ((input_ticks % 16) == 0) begin
                    slot_serial++;
                    slot_origin = carrier_cycles;
                    if (last_slot_origin != 0) begin
                        if (slot_origin - last_slot_origin == 47) short_slots++;
                        else if (slot_origin - last_slot_origin == 48) long_slots++;
                        else $fatal(1,"bad external native slot length");
                    end
                    last_slot_origin = slot_origin;
                end
                if ((input_ticks % (16*expected_voices)) == 0) begin
                    frame_origin = carrier_cycles;
                    frames_launched++;
                end
            end
            if (check_cadence && audio_strobe) begin
                assert (frames_launched == frames_output + 1)
                    else $fatal(1,"native cadence missing/duplicate output launched=%0d output=%0d",frames_launched,frames_output);
                assert (frame_origin != 0) else $fatal(1,"native output before first complete scan");
                if (output_lag < 0) output_lag = carrier_cycles-frame_origin;
                else assert (carrier_cycles-frame_origin == output_lag)
                    else $fatal(1,"native output phase moved expected_lag=%0d actual=%0d mode=%0d N=%0d",
                        output_lag,carrier_cycles-frame_origin,current_mode,expected_voices);
                frames_output++;
            end
        end
    end

    // Call after a falling edge has settled. Request fields stay held through
    // ACK and two further carrier edges; release is a separate request epoch.
    task automatic transfer_now(input logic wr, input logic [5:0] a,
        input logic [7:0] value, input logic measured);
        integer latency;
        host_req = 1; host_write = wr; host_addr = a; host_wdata = value;
        latency = 0;
        do begin @(posedge clk); #0.002; latency++; end while (!host_ack && latency <= HOST_BOUND+10);
        assert (host_ack) else $fatal(1,"native host timeout addr=%h mode=%0d N=%0d",a,current_mode,expected_voices);
        if (measured) begin
            assert (latency <= HOST_BOUND) else $fatal(1,"native host bound exceeded %0d>%0d",latency,HOST_BOUND);
            if (latency > max_host_latency) max_host_latency = latency;
        end
        repeat (2) begin @(posedge clk); #0.002; assert (!host_ack) else $fatal(1,"native host duplicate ACK"); end
        @(negedge clk); #0.002; host_req = 0;
        repeat (2) @(posedge clk);
        #0.002;
    endtask

    task automatic write_reg(input logic [3:0] slot, input logic [31:0] value);
        for (integer b=0; b<4; b++) begin
            @(negedge clk); #0.002;
            transfer_now(1,{slot,2'(b)},value[31-b*8 -: 8],0);
        end
    endtask

    task automatic setup(input integer actv, input integer running);
        enable_device_clock = 0; check_cadence = 0;
        @(negedge clk); #0.002; reset = 1; host_req = 0;
        repeat (5) @(negedge clk);
        #0.002; reset = 0;
        expected_voices = actv+1; current_mode = running;
        max_host_latency = 0; host_sweeps = 0;
        read_phases = 0; write_phases = 0;
        repeat (5) @(negedge clk);
        write_reg(4'hb,32'(actv));
        if (running != 0) begin
            for (integer voice=0; voice<=actv; voice++) begin
                write_reg(4'hf,32'(voice+32));
                write_reg(4'h1,32'd0);
                write_reg(4'h2,32'h00100000);
                write_reg(4'h3,32'd0);
                write_reg(4'hf,32'(voice));
                write_reg(4'h1,32'h00000800); // unity pitch, not a stopped shortcut
                write_reg(4'h6,32'd0);
                write_reg(4'h0,32'h00000008); // running unidirectional loop
            end
        end
        write_reg(4'hf,32'd0);
        // Prepare upper bytes for later lane3-only volume commits. ECOUNT stays
        // zero; a volume write may not pause the voice clock or corrupt cadence.
        write_reg(4'h2,32'h00008000);
        assert (active_voices == 5'(actv)) else $fatal(1,"ACTV setup failed");
        @(negedge clk); #0.002;
        check_cadence = 1; enable_device_clock = 1;
        while (frames_output < 2) begin @(negedge clk); #0.002; end
    endtask

    task automatic phase_request(input integer phase, input integer wr);
        integer timeout, old_slot;
        // Begin from a new slot, then wait for this actual carrier offset. Phase
        // 47 exists only in 48-clock slots; short slots are naturally skipped.
        old_slot = slot_serial;
        do begin @(negedge clk); #0.002; end while (slot_serial == old_slot);
        timeout = 0;
        while (carrier_cycles-slot_origin != phase && timeout < 500) begin
            @(negedge clk); #0.002; timeout++;
        end
        assert (timeout < 500) else $fatal(1,"native carrier phase %0d not reached",phase);
        $display("NATIVE_HOST launch mode=%0d ACTV=%0d write=%0d phase=%0d ESphase=%0d cycle=%0d remainder=%0d",
            current_mode,expected_voices-1,wr,phase,input_ticks%16,carrier_cycles,ce_remainder);
        if (wr != 0) write_phases[phase] = 1; else read_phases[phase] = 1;
        transfer_now(wr != 0,wr != 0 ? 6'h0b : 6'h08,8'(phase+32),1);
        host_sweeps++;
    endtask

    integer actv;
    initial begin
        if ($value$plusargs("ONLY_MODE=%d",only_mode)) begin end
        if ($value$plusargs("ONLY_ACTV=%d",only_actv)) begin end
        if ($value$plusargs("ONLY_PHASE=%d",only_phase)) begin end
        if ($value$plusargs("ONLY_WRITE=%d",only_write)) begin end
        for (integer running=0; running<2; running++) begin
            for (integer n=0; n<5; n++) begin
                case(n) 0:actv=4; 1:actv=7; 2:actv=15; 3:actv=23; default:actv=31; endcase
                if ((only_mode < 0 || only_mode == running) && (only_actv < 0 || only_actv == actv)) begin
                    setup(actv,running);
                    for (integer phase=0; phase<48; phase++)
                        for (integer wr=0; wr<2; wr++)
                            if ((only_phase < 0 || only_phase == phase) && (only_write < 0 || only_write == wr))
                                phase_request(phase,wr);
                    repeat (1600) @(negedge clk);
                    #0.002;
                    assert (short_slots != 0 && long_slots != 0) else $fatal(1,"fractional slot lengths not both covered");
                    assert (frames_launched-frames_output <= 1) else $fatal(1,"native frame output backlog");
                    if (only_phase < 0) begin
                        if (only_write < 0 || only_write == 0) assert (&read_phases) else $fatal(1,"read phase coverage incomplete");
                        if (only_write < 0 || only_write == 1) assert (&write_phases) else $fatal(1,"write phase coverage incomplete");
                        if (only_write < 0) assert (late_ce14_attempts != 0)
                            else $fatal(1,"same-edge count14/CE host corner not exercised");
                    end
                    if (running != 0) assert (sample_returns != 0) else $fatal(1,"running fixture fetched no samples");
                    $display("PASS NATIVE_HOST mode=%0d ACTV=%0d sweeps=%0d max_host_edges=%0d frame_lag=%0d frames=%0d slot47=%0d slot48=%0d late_ce14=%0d",
                        running,actv,host_sweeps,max_host_latency,output_lag,frames_output,short_slots,long_slots,late_ce14_attempts);
                end
            end
        end
        $finish;
    end

    initial begin
        #50ms;
        $fatal(1,"NATIVE_HOST watchdog mode=%0d N=%0d frames=%0d",current_mode,expected_voices,frames_output);
    end
endmodule
