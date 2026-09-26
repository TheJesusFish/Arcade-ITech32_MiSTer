// SPDX-License-Identifier: GPL-2.0-or-later
// Test-only replacement for the CPU, NOT for any graphics/memory stage.
// Drives authored bus transactions through the production main bus. Do not
// include alongside the real TG68 wrapper or in production synthesis.
`timescale 1ns/1ps
module itech32_tg68_cpu (
    input logic clk, reset, cpu_68000, cpu_ce,
    input logic [2:0] irq_level,
    input logic vector_load_we,
    input logic [4:0] vector_load_addr,
    input logic [31:0] vector_load_wdata,
    input logic [3:0] vector_load_be,
    output logic board_req = 0, board_we = 0,
    output logic [23:0] board_addr = 0,
    output logic [31:0] board_wdata = 0,
    output logic [3:0] board_be = 0,
    input logic board_ack,
    input logic [31:0] board_rdata,
    output wire [31:0] debug_addr,
    output wire [1:0] debug_busstate,
    output wire debug_nwr, debug_nuds, debug_nlds,
    output wire [2:0] debug_fc
);
    assign debug_addr = {8'd0, board_addr};
    assign debug_busstate = 0;
    assign {debug_nwr, debug_nuds, debug_nlds, debug_fc} = '0;
    task automatic transaction(input bit write_cycle, input logic [23:0] address,
                               input logic [31:0] data, input logic [3:0] lanes,
                               output logic [31:0] result);
        int timeout;
        @(negedge clk);
        board_addr = address; board_wdata = data; board_be = lanes;
        board_we = write_cycle; board_req = 1;
        timeout = 0;
        do begin
            @(posedge clk); #1;
            timeout++;
            if (timeout > 200000) $fatal(1, "CPU BFM timeout address=%h", address);
        end while (!board_ack);
        result = board_rdata;
        @(negedge clk); board_req = 0;
        repeat (2) @(negedge clk);
    endtask
endmodule
