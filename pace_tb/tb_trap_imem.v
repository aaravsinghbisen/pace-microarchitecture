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
module tb_trap_imem;
    reg clk=0, rst_n=0;
    reg [4:0] dbg_rs = 0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_satp;
    wire        dbg_satp_en;
    wire [63:0] imem_pc;
    wire [6*32-1:0] imem_instr;
    wire        dmem_req, dmem_we;
    wire [63:0] dmem_addr, dmem_wdata;
    reg  [63:0] dmem_rdata;
    reg         dmem_ready;
    wire        mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;

    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:255];

    integer i, tests_run=0, tests_passed=0, tests_failed=0;

    top_pace_imem dut (
        .clk(clk), .rst_n(rst_n),
        .imem_pc(imem_pc), .imem_instr(imem_instr),
        .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en)
    );

    always #5 clk = ~clk;

    // IMem: 6 instr alinhadas ao pcu_pc, exceto lane 0 que é a próxima do PCU
    wire [31:0] i0 = imem[imem_pc[9:2] + 0];
    wire [31:0] i1 = imem[imem_pc[9:2] + 1];
    wire [31:0] i2 = imem[imem_pc[9:2] + 2];
    wire [31:0] i3 = imem[imem_pc[9:2] + 3];
    wire [31:0] i4 = imem[imem_pc[9:2] + 4];
    wire [31:0] i5 = imem[imem_pc[9:2] + 5];
    // Ordem: lane5..lane0 = i5..i0
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    // DMem: 1-cycle
    always @(posedge clk) begin
        dmem_ready <= 0;
        if (dmem_req) begin
            if (dmem_we) dmem[dmem_addr[9:3]] <= dmem_wdata;
            else         dmem_rdata <= dmem[dmem_addr[9:3]];
            dmem_ready <= 1;
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
        for (i=0;i<256;i=i+1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 0;
        end

        // Programa (instruções caem em lanes via PCU 6-wide):
        //   0x00  addi x1, x0, 0x40
        //   0x04  csrrw x0, mtvec, x1
        //   0x08  ecall
        //   0x0C  addi x3, x0, 99
        //   0x10  addi x8, x0, 100
        //   0x14  jal x0, 0
        //   0x40  csrrs x5, mepc, x0
        //   0x44  addi x5, x5, 4
        //   0x48  csrrw x0, mepc, x5
        //   0x4C  mret
        imem[0]  = 32'h04000093;
        imem[1]  = 32'h30509073;
        imem[2]  = 32'h00000073;
        imem[3]  = 32'h06300193;
        imem[4]  = 32'h06400413;
        imem[5]  = 32'h0000006F;
        imem[16] = 32'h341022F3;   // 0x40
        imem[17] = 32'h00428293;   // 0x44
        imem[18] = 32'h34129073;   // 0x48
        imem[19] = 32'h30200073;   // 0x4C

        mmio_rdata = 0; mmio_ready = 0;
        rst_n = 0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  TOP PACE IMEM — Trap end-to-end");
        $display("========================================");

        repeat(200) @(posedge clk);
        @(negedge clk);

        $display("  PCU pc = %h", dbg_pcu_pc);

        check_arch(5'd1, 64'h40, "x1 = 0x40 (handler)");
        check_arch(5'd5, 64'h0C, "x5 = mepc+4");
        check_arch(5'd3, 64'd99, "x3 = 99 (rodou após mret)");
        check_arch(5'd8, 64'd100, "x8 = 100 (fim)");


        // ===== Teste RVC =====
        // Reinicia o estado com reset
        rst_n = 0;
        repeat(3) @(posedge clk);
        rst_n = 1;

        // Programa RVC:
        //  0x00: C.ADDI x5, 5   (16-bit) + padding
        //        = 0x0295 0000 (low half = RVC, high half = 0)
        //        Decompressed: addi x5, x5, 5
        //        Como x5 começa 0, resultado: x5 = 5
        //  0x04: addi x8, x0, 42 (32-bit normal)
        //  0x08: jal x0, 0
        for (i=0;i<256;i=i+1) begin
            imem[i] = 32'h00000013;
            dmem[i] = 0;
        end
        imem[0] = 32'h00000295;   // RVC C.ADDI x5, 5 (low) + 0 high
        imem[1] = 32'h02A00413;   // addi x8, x0, 42
        imem[2] = 32'h0000006F;   // jal x0, 0

        repeat(50) @(posedge clk);
        @(negedge clk);

        check_arch(5'd5, 64'd5, "RVC: x5 = 5 (via C.ADDI)");
        check_arch(5'd8, 64'd42, "RVC+normal: x8 = 42");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
