// SPDX-License-Identifier: GPL-3.0-or-later
`timescale 1ns/1fs

// Reuse the native host/voice phase sweep as legal external stimulus. This
// checker models only whether a synchronous M10K read is undefined after a
// mixed-port same-address write. It does not assume simulation's old data is
// available in fitted hardware and does not force any chip register contents.
module itech32_es5506_prefetch_collision_tb;
    itech32_es5506_native_host_tb fixture();
    localparam logic [2:0] ROW_READY = 3'd7, URGENT_GATHER = 3'd5;
    logic read_collision_q = 0;
    integer guarded_reads = 0, write_collisions = 0;

    always @(posedge fixture.clk) begin : check_read_ownership
        logic reject_row;
        logic [2:0] state_before;
        logic [24:0] descriptor_before;
        logic [4:0] row_before;
        state_before = fixture.dut.prefetch_state;
        descriptor_before = fixture.dut.prefetch_urgent_descriptor;
        row_before = fixture.dut.prefetch_row_voice_q;
        reject_row = !fixture.dut.local_reset && read_collision_q &&
            ((state_before == ROW_READY) || (state_before == URGENT_GATHER));
        if (fixture.dut.local_reset) read_collision_q = 0;
        else begin
            read_collision_q = fixture.dut.voice_write_en &&
                (fixture.dut.voice_write_addr == fixture.dut.voice_prefetch_read_addr) &&
                fixture.dut.voice_state_valid[fixture.dut.voice_prefetch_read_addr];
            if (read_collision_q) write_collisions++;
        end
        #0.001;
        if (reject_row) begin
            guarded_reads++;
            assert (fixture.dut.prefetch_state == state_before)
                else $fatal(1,"prefetch consumed undefined mixed-port row: state=%0d next=%0d",
                    state_before,fixture.dut.prefetch_state);
            assert (fixture.dut.prefetch_row_voice_q == row_before &&
                    fixture.dut.voice_prefetch_read_addr == row_before)
                else $fatal(1,"collision retry lost ownership of its held row");
            if (state_before == URGENT_GATHER)
                assert (fixture.dut.prefetch_urgent_descriptor == descriptor_before)
                    else $fatal(1,"urgent descriptor captured a colliding RAM read");
        end
    end

    final begin
        assert (guarded_reads != 0 && write_collisions != 0)
            else $fatal(1,"prefetch collision stimulus missed the target");
        $display("PASS PREFETCH_COLLISION writes=%0d rejected_consumptions=%0d",
            write_collisions,guarded_reads);
    end
endmodule
