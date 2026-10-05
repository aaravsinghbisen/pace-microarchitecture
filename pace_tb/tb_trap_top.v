// Copyright (c) 2026 uppmpt (https://github.com/uppmpt)
// Contact: pacesolodev@gmail.com
//
// This source describes Open Hardware and is licensed under the
// CERN-OHL-W v2.
//
// You may redistribute and modify this source and make products
// using it under the terms of the CERN-OHL-W v2
// (https://ohwr.org/cern_ohl_w_v2.txt).
//
// This source is distributed WITHOUT ANY EXPRESS OR IMPLIED
// WARRANTY, INCLUDING THE IMPLIED WARRANTIES OF MERCHANTABILITY,
// SATISFACTORY QUALITY AND FITNESS FOR A PARTICULAR PURPOSE.
// Please see the CERN-OHL-W v2 for applicable conditions.
//
// Source location: https://github.com/uppmpt/pace-microarchitecture
`timescale 1ns/1ps
module tb_trap_top;
    reg clk=0, rst_n=0;
    reg [4:0] dbg_rs = 0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc;
    wire [7:0]  dbg_vl;
    wire [63:0] dbg_vtype, dbg_instr_count;
    wire [31:0] dbg_ipc_x1000;
    wire [63:0] imem_addr;
    reg  [31:0] imem_rdata;

    // Sinais do top_pace_full (todos dummy)
    wire mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;
    wire dram_req, dram_we;
    wire [63:0] dram_addr;
    wire [511:0] dram_wdata;
    reg  [511:0] dram_rdata;
    reg         dram_ready;

    reg [511:0] dmem [0:1023];
    reg [3:0] dram_delay;
    reg [3:0] mmio_delay;
    reg mmio_inflight;
    integer i, tests_run=0, tests_passed=0, tests_failed=0;

    top_pace_full dut (
        .clk(clk), .rst_n_in(rst_n),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .dram_req(dram_req), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata),
        .dram_rdata(dram_rdata), .dram_ready(dram_ready),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_vl(dbg_vl), .dbg_vtype(dbg_vtype),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_instr_count(dbg_instr_count), .dbg_ipc_x1000(dbg_ipc_x1000)
    );

    always #5 clk = ~clk;

    // DRAM
    always @(posedge clk) begin
        dram_ready <= 0;
        if (dram_req && dram_delay == 0) dram_delay <= 8;
        else if (dram_delay > 0) begin
            dram_delay <= dram_delay - 1;
            if (dram_delay == 1) begin
                if (dram_we) dmem[dram_addr[15:6]][dram_addr[5:3]*64 +: 64] <= dram_wdata[63:0];
                else        dram_rdata <= dmem[dram_addr[15:6]];
                dram_ready <= 1;
            end
        end
    end

    // MMIO
    always @(posedge clk) begin
        mmio_ready <= 0;
        if (!mmio_inflight && mmio_req) begin
            mmio_inflight <= 1; mmio_delay <= 2;
        end else if (mmio_inflight) begin
            if (mmio_delay == 0) begin
                mmio_rdata <= mmio_addr ^ 64'hAAAA_0000_0000_0000;
                mmio_ready <= 1; mmio_inflight <= 0;
            end else mmio_delay <= mmio_delay - 1;
        end
    end

    task check_arch;
        input [4:0] r; input [63:0] e; input [255:0] n;
        begin
            dbg_rs = r; #1; tests_run = tests_run + 1;
            if (dbg_arch_rd === e) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s : x%0d = %0d", n, r, dbg_arch_rd);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s : x%0d = %0d (exp %0d)", n, r, dbg_arch_rd, e);
            end
        end
    endtask

    initial begin
        for (i=0;i<1024;i=i+1) dmem[i] = 0;

        // Programa (line 0 do DRAM, PA 0):
        //   0x00  addi x1, x0, 0x40       ; handler em 0x40
        //   0x04  csrrw x0, mtvec, x1     ; mtvec = 0x40
        //   0x08  ecall                   ; trap → 0x40
        //   0x0C  addi x3, x0, 99         ; roda depois do mret
        //   0x10  addi x8, x0, 100        ; fim
        //   0x14  jal x0, 0               ; loop
        //   ...(NOP)...
        //   0x40  csrrs x5, mepc, x0      ; x5 = 0x08 (PC do ecall)
        //   0x44  addi x5, x5, 4          ; x5 = 0x0C
        //   0x48  csrrw x0, mepc, x5      ; mepc = 0x0C
        //   0x4C  mret                    ; retorna pra 0x0C
        dmem[0][31:0]    = 32'h04000093;
        dmem[0][63:32]   = 32'h30509073;
        dmem[0][95:64]   = 32'h00000073;
        dmem[0][127:96]  = 32'h06300193;
        dmem[0][159:128] = 32'h06400413;
        dmem[0][191:160] = 32'h0000006F;
        // Padding até 0x40 = line 1 word 0
        for (i=6; i<8; i=i+1) dmem[0][i*32 +: 32] = 32'h00000013;
        // dmem[1] = line 0x40
        dmem[1] = 0;
        dmem[1][31:0]    = 32'h341022F3;  // csrrs x5, mepc, x0
        dmem[1][63:32]   = 32'h00428293;  // addi x5, x5, 4
        dmem[1][95:64]   = 32'h34129073;  // csrrw x0, mepc, x5
        dmem[1][127:96]  = 32'h30200073;  // mret
        dmem[1][159:128] = 32'h0000006F;  // jal x0, 0
        for (i=5; i<8; i=i+1) dmem[1][i*32 +: 32] = 32'h00000013;

        rst_n = 0;
        dram_delay = 0;
        mmio_delay = 0;
        mmio_inflight = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  TOP FULL — Trap end-to-end");
        $display("========================================");

        repeat(600) @(posedge clk);
        @(negedge clk);

        $display("  PCU pc = %h", dbg_pcu_pc);
        check_arch(5'd1, 64'h40, "x1 = handler addr (0x40)");
        check_arch(5'd5, 64'h0C, "x5 = mepc (0x0C após +4)");
        check_arch(5'd3, 64'd99, "x3 = 99 (rodou após mret)");
        check_arch(5'd8, 64'd100, "x8 = 100 (fim)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
