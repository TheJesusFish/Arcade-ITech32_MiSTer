`timescale 1ns/1ps

// ROM-free regression for the SFTM protection-source read policy. Literal
// addresses and expected values are specified independently of the DUT decoder.
module itech32_sftm_protection_tb;
    /* verilator lint_off PROCASSINIT */
    logic clk = 1'b0;
    /* verilator lint_on PROCASSINIT */
    logic reset = 1'b1;
    logic timekill_mode = 1'b0;
    logic bloodstorm_mode = 1'b0;
    logic rom_buffer_invalidate = 1'b0;
    logic cpu_req = 1'b0;
    logic cpu_we = 1'b0;
    logic [23:0] cpu_addr = 24'd0;
    logic [31:0] cpu_wdata = 32'd0;
    logic [3:0] cpu_be = 4'd0;
    logic cpu_ack;
    logic [31:0] cpu_rdata;
    logic [14:0] protection_address = 15'd0;

    logic video_req;
    logic rom_req;
    logic sound_command_valid;
    logic watchdog_strobe;
    logic vint_ack_strobe;
    logic special_read_strobe;
    logic color0_strobe;
    logic color1_strobe;

    // This focused test intentionally observes only requests and architectural
    // side-effect strobes; payload outputs for services it never invokes remain
    // disconnected.
    /* verilator lint_off PINCONNECTEMPTY */
    itech32_main_bus dut (
        .clk(clk),
        .reset(reset),
        .timekill_mode(timekill_mode),
        .bloodstorm_mode(bloodstorm_mode),
        .rom_buffer_invalidate(rom_buffer_invalidate),
        .cpu_req(cpu_req),
        .cpu_we(cpu_we),
        .cpu_addr(cpu_addr),
        .cpu_wdata(cpu_wdata),
        .cpu_be(cpu_be),
        .cpu_ack(cpu_ack),
        .cpu_rdata(cpu_rdata),
        .input_p1(32'd0),
        .input_p2(32'd0),
        .input_p3(32'd0),
        .input_p4(32'd0),
        .input_dips(32'd0),
        .input_extra(32'd0),
        .protection_address(protection_address),
		.nvram_host_access(1'b0),
		.nvram_host_write(1'b0),
		.nvram_host_addr(17'd0),
		.nvram_host_wdata(16'd0),
		.nvram_host_rdata(),
		.nvram_cpu_write(),
        .video_req(video_req),
        .video_we(),
        .video_addr(),
        .video_wdata(),
        .video_be(),
        .video_ack(1'b0),
        .video_rdata(16'd0),
        .rom_req(rom_req),
        .rom_addr(),
        .rom_ack(1'b0),
        .rom_rdata(32'd0),
        .sound_command_valid(sound_command_valid),
        .sound_command(),
        .watchdog_strobe(watchdog_strobe),
        .vint_ack_strobe(vint_ack_strobe),
        .special_read_strobe(special_read_strobe),
        .color0_strobe(color0_strobe),
        .color1_strobe(color1_strobe),
        .color_data(),
        .plane_enable(),
        .grom_bank(),
        .palette_video_addr(15'd0),
        .palette_video_rgb()
    );
    /* verilator lint_on PINCONNECTEMPTY */

    always #5 clk = ~clk;

    initial begin
        #200000;
        $fatal(1, "SFTM_PROTECTION_GLOBAL_TIMEOUT");
    end

    task automatic access(
        input logic [23:0] address,
        input logic write_cycle,
        input logic [31:0] write_data,
        input logic [3:0] byte_enable,
        input logic [31:0] expected_data,
        input logic [31:0] compare_mask,
        input integer expected_ack_edges
    );
        integer wait_edges;
        begin
            @(negedge clk);
            #1;
            if (cpu_req || cpu_ack)
                $fatal(1, "SFTM_PROTECTION_UNDRAINED_START");
            cpu_addr = address;
            cpu_we = write_cycle;
            cpu_wdata = write_data;
            cpu_be = byte_enable;
            cpu_req = 1'b1;

            wait_edges = 0;
            do begin
                @(posedge clk);
                #1;
                wait_edges = wait_edges + 1;
                if (wait_edges > 16)
                    $fatal(1, "SFTM_PROTECTION_ACK_TIMEOUT addr=%06x", address);
            end while (!cpu_ack);

            if (wait_edges != expected_ack_edges)
                $fatal(1, "SFTM_PROTECTION_ACK_SCHEDULE addr=%06x got=%0d expected=%0d",
                    address, wait_edges, expected_ack_edges);
            if ((cpu_rdata & compare_mask) !== (expected_data & compare_mask))
                $fatal(1, "SFTM_PROTECTION_DATA addr=%06x got=%08x expected=%08x mask=%08x",
                    address, cpu_rdata, expected_data, compare_mask);

            repeat (2) begin
                @(posedge clk);
                #1;
                if (cpu_ack)
                    $fatal(1, "SFTM_PROTECTION_DUP_ACK addr=%06x", address);
            end
            @(negedge clk);
            #1;
            cpu_req = 1'b0;
            cpu_we = 1'b0;
            cpu_be = 4'd0;
            repeat (2) begin
                @(posedge clk);
                #1;
                if (cpu_ack)
                    $fatal(1, "SFTM_PROTECTION_LATE_ACK addr=%06x", address);
            end
        end
    endtask

    task automatic select_mode(input logic timekill, input logic bloodstorm);
        begin
            @(negedge clk);
            #1;
            timekill_mode = timekill;
            bloodstorm_mode = bloodstorm;
            repeat (2) @(negedge clk);
        end
    endtask

    initial begin
        repeat (4) @(negedge clk);
        #1;
        reset = 1'b0;
        repeat (2) @(negedge clk);

        // SFTM reaches this otherwise unpopulated 32 KiB window through a
        // signed, RAM-derived offset below the 0x580000 palette base.
        access(24'h578000, 1'b0, 32'd0, 4'hf, 32'h0000_0000, 32'hffff_ffff, 2);
        access(24'h578001, 1'b0, 32'd0, 4'h4, 32'h0000_0000, 32'h00ff_0000, 2);
        access(24'h57fffe, 1'b0, 32'd0, 4'h2, 32'h0000_0000, 32'h0000_ff00, 2);
        access(24'h57ffff, 1'b0, 32'd0, 4'h1, 32'h0000_0000, 32'h0000_00ff, 2);

        // The explicit window must agree with SFTM's established general
        // unmapped-read policy without changing the response cadence.
        access(24'h570000, 1'b0, 32'd0, 4'hf, 32'h0000_0000, 32'hffff_ffff, 2);

        // Independently, the explicit protection read must still return the
        // selected work-RAM byte on CPU address lane +2. This guards the
        // mapped target adjacent to the corrected window.
        access(24'h000100, 1'b1, 32'h1122_3344, 4'hf, 32'd0, 32'd0, 2);
        protection_address = 15'h0101;
        access(24'h680002, 1'b0, 32'd0, 4'h2, 32'h0000_2200, 32'h0000_ff00, 3);

        // The same physical address is ordinary open bus in the two 68000
        // profiles. Their all-ones policy is deliberately unchanged.
        select_mode(1'b1, 1'b0);
        access(24'h578000, 1'b0, 32'd0, 4'hf, 32'hffff_ffff, 32'hffff_ffff, 2);
        select_mode(1'b0, 1'b1);
        access(24'h578000, 1'b0, 32'd0, 4'hf, 32'hffff_ffff, 32'hffff_ffff, 2);

        select_mode(1'b0, 1'b0);
        access(24'h578000, 1'b0, 32'd0, 4'hf, 32'h0000_0000, 32'hffff_ffff, 2);

        if (video_req || rom_req || sound_command_valid || watchdog_strobe ||
            vint_ack_strobe || special_read_strobe || color0_strobe || color1_strobe)
            $fatal(1, "SFTM_PROTECTION_UNEXPECTED_SIDE_EFFECT");

        $display("SFTM_PROTECTION_PASS source_reads=5 protected_reads=1 profile_guards=2");
        $finish;
    end
endmodule
