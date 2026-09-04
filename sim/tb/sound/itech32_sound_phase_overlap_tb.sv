// SPDX-License-Identifier: GPL-3.0-or-later
// ROM-free architectural check for inactive-phase memory-latency overlap.
// The reference below retains the published whole-phase hold contract. This
// fixture uses native enable cadence and known data with adversarial readiness;
// it is not the real board's delayed-response bridge or a physical timing proof.
`timescale 1ns/1ps
module itech32_sound_phase_overlap_tb #(
    parameter bit EXPECT_OVERLAP = 1'b1
);
    logic clk = 0, reset = 1;
    logic ce_8m;
    logic [1:0] done, txn_valid;
    logic [24:0] txn [0:1];
    logic [111:0] regs [0:1];
    logic [63:0] carrier_count [0:1], overlap_count [0:1];
    logic [24:0] trace [0:1][0:2047];
    integer count [0:1];
    always #10.476 clk = ~clk;
    itech32_rate_enable #(.CLK_HZ(47727273), .RATE_HZ(8000000))
        rate8 (.clk(clk), .reset(reset), .ce(ce_8m));
    for (genvar n=0; n<2; n++) begin: g
        sound_phase_fixture #(.DUT(n != 0)) fixture (
            .clk(clk), .reset(reset), .ce_8m(ce_8m), .done(done[n]),
            .txn_valid(txn_valid[n]), .txn(txn[n]), .regs(regs[n]),
            .carrier_count(carrier_count[n]), .overlap_count(overlap_count[n])
        );
        always @(posedge clk) begin
            if (reset) count[n] = 0;
            else if (txn_valid[n]) begin
                if (count[n] >= 2048) $fatal(1, "architectural trace overflow");
                trace[n][count[n]] = txn[n];
                count[n] = count[n]+1;
            end
        end
    end
    initial begin
        repeat(8) @(posedge clk);
        @(negedge clk); reset=0;
        wait (&done);
        @(posedge clk); #1;
        if (count[0] != count[1]) $fatal(1, "transaction count mismatch %0d/%0d", count[0], count[1]);
        for (integer i=0; i<count[0]; i++)
            if (trace[0][i] !== trace[1][i])
                $fatal(1, "architectural divergence transaction=%0d ref=%07x dut=%07x", i, trace[0][i], trace[1][i]);
        if (regs[0] !== regs[1]) $fatal(1, "final architectural state mismatch");
        if (EXPECT_OVERLAP && (!overlap_count[1] || carrier_count[1] >= carrier_count[0]))
            $fatal(1, "overlap experiment did not save carrier clocks");
        $display("PASS: phase overlap architectural transactions=%0d ref_carriers=%0d dut_carriers=%0d inactive_overlap=%0d", count[0], carrier_count[0], carrier_count[1], overlap_count[1]);
        $finish;
    end
    initial begin
        repeat(200000) @(posedge clk);
        $fatal(1, "phase-overlap integration watchdog");
    end
endmodule

module sound_phase_fixture #(
    parameter bit DUT=1'b0
) (
    input logic clk, reset, ce_8m,
    output logic done=0, txn_valid,
    output logic [24:0] txn,
    output logic [111:0] regs,
    output logic [63:0] carrier_count=0, overlap_count=0
);
    logic valid, write, ready, ce_e, ce_q;
    logic [15:0] addr;
    logic [7:0] wdata, rdata;
    logic [1:0] phase;
    logic [7:0] memory [0:65535];
    logic irq=0, firq=0, nmi=0;
    logic [6:0] cpu_state;
    integer e_count=0, age=0, delay_count=11;
    integer last_active_edge=0;
    logic seen_active_edge=0;
    logic expect_q=0;
    logic previous_e=1, previous_wait=0;
    logic [24:0] previous_payload=0;
    function automatic integer latency(input integer ordinal);
        case(ordinal % 7)
            0: latency=0; 1: latency=5; 2: latency=8; 3: latency=11;
            4: latency=17; 5: latency=31; default: latency=48;
        endcase
    endfunction
    assign rdata=memory[addr];
    assign ready=!done && age >= delay_count;
    assign txn_valid=!reset && !done && valid && ready && ((ce_e && !write) || (ce_q && write));
    assign txn={write,addr,write ? wdata : rdata};
    if (DUT) begin: candidate
        itech32_sound_cpu cpu_wrapper (
            .clk(clk),.reset(reset),.ce_8m(ce_8m),.mem_valid(valid),
            .mem_addr(addr),.mem_write(write),.mem_wdata(wdata),
            .mem_rdata(rdata),.mem_ready(ready),.irq(irq),.firq(firq),.nmi(nmi),
            .ce_e(ce_e),.ce_q(ce_q),.ce_cpu_2m(),.phase(phase),
            .opcode_fetch(),.bus_status(),.bus_available(),.cpu_busy(),
            .last_instruction_cycle(),.debug_regs(regs)
        );
        assign cpu_state=cpu_wrapper.cpu.CpuState;
    end else begin: reference
        itech32_sound_cpu_phase_reference cpu_wrapper (
            .clk(clk),.reset(reset),.ce_8m(ce_8m),.mem_valid(valid),
            .mem_addr(addr),.mem_write(write),.mem_wdata(wdata),
            .mem_rdata(rdata),.mem_ready(ready),.irq(irq),.firq(firq),.nmi(nmi),
            .ce_e(ce_e),.ce_q(ce_q),.ce_cpu_2m(),.phase(phase),
            .opcode_fetch(),.bus_status(),.bus_available(),.cpu_busy(),
            .last_instruction_cycle(),.debug_regs(regs)
        );
        assign cpu_state=cpu_wrapper.cpu.CpuState;
    end
    always @(posedge clk) begin: monitor
        logic [118:0] old_state;
        logic [1:0] old_phase;
        logic old_e, old_q, overlap_opportunity;
        old_state={regs,cpu_state};
        old_phase=phase;
        old_e=ce_e; old_q=ce_q;
        overlap_opportunity=!reset && !done && ce_8m && valid && !ready && phase[0];
        if (reset) begin
            e_count=0; age<=0; delay_count<=11; done<=0;
            carrier_count=0; overlap_count=0; expect_q=0;
            last_active_edge=0; seen_active_edge=0;
            previous_e=1; previous_wait=0;
            irq<=0; firq<=0; nmi<=0;
        end else if (!done) begin
            carrier_count=carrier_count+1;
            if (ce_e && ce_q) $fatal(1,"E/Q overlap");
            if (ce_e || ce_q) begin
                // This exact native-enable minimum supports the existing
                // 11/10 setup/hold exception between mc6809 state registers.
                if (seen_active_edge && carrier_count-last_active_edge < 11)
                    $fatal(1,"active CPU edges violate native multicycle spacing");
                last_active_edge=integer'(carrier_count);
                seen_active_edge=1;
            end
            if ((ce_e || ce_q) && valid && !ready) $fatal(1,"active CPU edge consumed unready bus");
            if (previous_wait && !previous_e && valid && {write,addr,wdata} !== previous_payload)
                $fatal(1,"request payload changed during readiness wait");
            previous_payload={write,addr,wdata};
            previous_wait=valid && !ready;
            previous_e=ce_e;
            if (ce_e) begin
                if (expect_q) $fatal(1,"E repeated without Q");
                expect_q=1;
                e_count=e_count+1;
                age <= 0;
                delay_count <= latency(e_count);
                // Interrupt arrival is anchored to architectural E count, not
                // carrier time, so successful stall removal is not divergence.
                if(e_count==120) irq<=1;
                if(e_count==220) firq<=1;
                if(e_count==320) nmi<=1;
                if(e_count==500) begin
                    if(memory[16'h2000]!==8'h5a || memory[16'h2001]!==8'h49 ||
                       memory[16'h2002]!==8'h46 || memory[16'h2003]!==8'h4e)
                        $fatal(1,"program/IRQ/FIRQ/NMI markers missing");
                    done <= 1;
                end
            end else if (age<255) age<=age+1;
            if (ce_q) begin
                if (!expect_q) $fatal(1,"Q without preceding E");
                expect_q=0;
                if (valid && ready && write) begin
                    memory[addr]<=wdata;
                    if(addr==16'h2001) irq<=0;
                    if(addr==16'h2002) firq<=0;
                    if(addr==16'h2003) nmi<=0;
                end
            end
        end
        #1;
        if (!reset && !old_e && !old_q && {regs,cpu_state} !== old_state)
            $fatal(1,"CPU state changed without an E/Q edge");
        if (overlap_opportunity && phase != old_phase)
            overlap_count=overlap_count+1;
    end
    initial begin
        for(integer i=0;i<65536;i++) memory[i]=8'h12;
        memory[16'h8000]=8'h10; memory[16'h8001]=8'hce; memory[16'h8002]=8'h7f; memory[16'h8003]=0;
        memory[16'h8004]=8'h1c; memory[16'h8005]=8'haf;
        memory[16'h8006]=8'h86; memory[16'h8007]=8'h12;
        memory[16'h8008]=8'hb7; memory[16'h8009]=0; memory[16'h800a]=8'h10;
        memory[16'h800b]=8'hf6; memory[16'h800c]=0; memory[16'h800d]=8'h20;
        memory[16'h800e]=8'hf7; memory[16'h800f]=0; memory[16'h8010]=8'h11;
        memory[16'h8011]=8'hb6; memory[16'h8012]=8'h12; memory[16'h8013]=8'h34;
        memory[16'h8014]=8'hb7; memory[16'h8015]=8'h20; memory[16'h8016]=0;
        memory[16'h8017]=8'h12; memory[16'h8018]=8'h20; memory[16'h8019]=8'hfd;
        memory[16'h8100]=8'h86; memory[16'h8101]=8'h49; memory[16'h8102]=8'hb7;
        memory[16'h8103]=8'h20; memory[16'h8104]=1; memory[16'h8105]=8'h3b;
        memory[16'h8120]=8'h86; memory[16'h8121]=8'h46; memory[16'h8122]=8'hb7;
        memory[16'h8123]=8'h20; memory[16'h8124]=2; memory[16'h8125]=8'h3b;
        memory[16'h8140]=8'h86; memory[16'h8141]=8'h4e; memory[16'h8142]=8'hb7;
        memory[16'h8143]=8'h20; memory[16'h8144]=3; memory[16'h8145]=8'h3b;
        memory[16'hfff6]=8'h81; memory[16'hfff7]=8'h20;
        memory[16'hfff8]=8'h81; memory[16'hfff9]=0;
        memory[16'hfffc]=8'h81; memory[16'hfffd]=8'h40;
        memory[16'hfffe]=8'h80; memory[16'hffff]=0;
        memory[16'h0020]=8'h34; memory[16'h1234]=8'h5a;
        memory[16'h2000]=0; memory[16'h2001]=0; memory[16'h2002]=0; memory[16'h2003]=0;
    end
endmodule

// SPDX-License-Identifier: GPL-3.0-or-later
//
// Minimal ITech32 sound-board CPU wrapper around Greg Miller's mc6809i.
// The external memory contract is deliberately technology independent:
// mem_valid and the request payload remain asserted until mem_ready is high.

`timescale 1ns/1ps

module itech32_sound_cpu_phase_reference #(
	parameter ILLEGAL_INSTRUCTIONS = "GHOST"
) (
	input  logic         clk,
	input  logic         reset,
	input  logic         ce_8m,

	output logic         mem_valid,
	output logic [15:0]  mem_addr,
	output logic         mem_write,
	output logic [7:0]   mem_wdata,
	input  logic [7:0]   mem_rdata,
	input  logic         mem_ready,

	input  logic         irq,
	input  logic         firq,
	input  logic         nmi,

	output logic         ce_e,
	output logic         ce_q,
	output logic         ce_cpu_2m,
	output logic [1:0]   phase,
	output logic         opcode_fetch,
	output logic         bus_status,
	output logic         bus_available,
	output logic         cpu_busy,
	output logic         last_instruction_cycle,
	output logic [111:0] debug_regs
);

	logic       core_rnw;
	logic       core_avma;
	logic       core_op;
	logic       core_bs;
	logic       core_ba;
	logic       core_busy;
	logic       core_lic;
	logic       wait_hold;

	assign mem_write              = ~core_rnw;
	assign opcode_fetch           = core_op;
	assign bus_status             = core_bs;
	assign bus_available          = core_ba;
	assign cpu_busy               = core_busy;
	assign last_instruction_cycle = core_lic;

	// AVMA describes the bus cycle that becomes active after an E edge. Latch
	// it exactly as the established JTFRAME 6809 wrapper does. The resulting
	// request is stable through Q and until the following accepted E edge.
	always_ff @(posedge clk) begin
		if (reset)
			mem_valid <= 1'b1;
		else if (ce_e)
			mem_valid <= core_avma;
	end

	// Freeze the complete E/Q phase machine while the active request waits.
	assign wait_hold = mem_valid && !mem_ready;

	itech32_6809_phase_enable phase_enable (
		.clk       (clk),
		.reset     (reset),
		.ce_8m     (ce_8m),
		.hold      (wait_hold),
		.ce_e      (ce_e),
		.ce_q      (ce_q),
		.ce_cpu_2m (ce_cpu_2m),
		.phase     (phase)
	);

	mc6809i #(
		.ILLEGAL_INSTRUCTIONS(ILLEGAL_INSTRUCTIONS)
	) cpu (
		.D        (mem_rdata),
		.DOut     (mem_wdata),
		.ADDR     (mem_addr),
		.RnW      (core_rnw),
		.clk      (clk),
		.cen_E    (ce_e),
		.cen_Q    (ce_q),
		.BS       (core_bs),
		.BA       (core_ba),
		.nIRQ     (~irq),
		.nFIRQ    (~firq),
		.nNMI     (~nmi),
		.AVMA     (core_avma),
		.BUSY     (core_busy),
		.LIC      (core_lic),
		.nHALT    (1'b1),
		.nRESET   (~reset),
		.nDMABREQ (1'b1),
		.OP       (core_op),
		.RegData  (debug_regs)
	);

endmodule
