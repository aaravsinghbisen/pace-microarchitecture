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
module tb_atomic;
    reg clk=0, rst_n=0;
    reg         req, is_lr, is_sc, is_amo;
    reg  [4:0]  amo_op;
    reg         is_word;
    reg  [63:0] addr, rs2_val;
    wire [63:0] rd_val;
    wire        sc_success, done;
    wire        mem_req, mem_we;
    wire [63:0] mem_addr, mem_wdata;
    reg  [63:0] mem_rdata;
    reg         mem_ready;

    reg [63:0] dmem [0:255];
    integer tests_run=0, tests_passed=0, tests_failed=0;
    integer i;

    atomic_unit uut (
        .clk(clk), .rst_n(rst_n),
        .req(req), .is_lr(is_lr), .is_sc(is_sc), .is_amo(is_amo),
        .amo_op(amo_op), .is_word(is_word),
        .addr(addr), .rs2_val(rs2_val), .rd_val(rd_val),
        .sc_success(sc_success), .done(done),
        .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready)
    );

    always #5 clk = ~clk;

    // Modelo de memória 1-ciclo
    always @(posedge clk) begin
        mem_ready <= 0;
        if (mem_req) begin
            if (mem_we) dmem[mem_addr[8:3]] <= mem_wdata;
            else        mem_rdata <= dmem[mem_addr[8:3]];
            mem_ready <= 1;
        end
    end

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task tick; begin @(posedge clk); @(negedge clk); end endtask

    task atomic_op;
        input lr, sc, amo;
        input [4:0] aop;
        input w;
        input [63:0] a, v;
        begin
            @(negedge clk);
            req=1; is_lr=lr; is_sc=sc; is_amo=amo;
            amo_op=aop; is_word=w;
            addr=a; rs2_val=v;
            @(posedge clk); @(negedge clk);
            req=0;
            // Espera done
            while (!done) @(posedge clk);
            @(negedge clk);
        end
    endtask

    initial begin
        for (i=0;i<256;i=i+1) dmem[i] = 0;
        dmem[0] = 64'h0000_0000_0000_0064;   // mem[0] = 100
        dmem[1] = 64'h0000_0000_0000_000A;   // mem[8] = 10

        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  A Extension Testbench");
        $display("========================================");

        // LR.D
        atomic_op(1, 0, 0, 5'b0, 0, 64'd0, 0);
        check(rd_val === 64'd100, "LR.D mem[0] = 100");
        check(dmem[0] === 64'd100, "LR.D mem não muda");

        // SC.D com sucesso
        atomic_op(0, 1, 0, 5'b0, 0, 64'd0, 64'd200);
        check(sc_success === 1'b1, "SC.D success");
        check(dmem[0] === 64'd200, "SC.D wrote 200");

        // SC.D sem LR prévio → falha
        atomic_op(0, 1, 0, 5'b0, 0, 64'd0, 64'd300);
        check(sc_success === 1'b0, "SC.D fail (no reservation)");
        check(dmem[0] === 64'd200, "SC.D didn't write");

        // AMOADD.D: mem[8] += 5
        atomic_op(0, 0, 1, 5'b00000, 0, 64'd8, 64'd5);
        check(rd_val === 64'd10, "AMOADD.D old = 10");
        check(dmem[1] === 64'd15, "AMOADD.D mem[8] = 15");

        // AMOSWAP.D
        atomic_op(0, 0, 1, 5'b00001, 0, 64'd8, 64'hDEAD);
        check(rd_val === 64'd15, "AMOSWAP old = 15");
        check(dmem[1] === 64'hDEAD, "AMOSWAP wrote DEAD");

        // AMOAND.D
        atomic_op(0, 0, 1, 5'b01100, 0, 64'd8, 64'h0F0F);
        check(rd_val === 64'hDEAD, "AMOAND old = DEAD");

        // AMOMAXU.D
        dmem[2] = 64'd50;
        atomic_op(0, 0, 1, 5'b11100, 0, 64'd16, 64'd100);
        check(rd_val === 64'd50, "AMOMAXU old = 50");
        check(dmem[2] === 64'd100, "AMOMAXU wrote 100 (max)");

        // AMOMAXU.D onde old > new → fica old
        atomic_op(0, 0, 1, 5'b11100, 0, 64'd16, 64'd20);
        check(dmem[2] === 64'd100, "AMOMAXU mantém 100");

        // AMOADD.W (word)
        dmem[3] = 64'hFFFF_FFFF_0000_0010;   // low word = 16
        atomic_op(0, 0, 1, 5'b00000, 1, 64'd24, 64'd5);
        check(rd_val === 64'd16, "AMOADD.W old low = 16");
        check(dmem[3][31:0] === 32'd21, "AMOADD.W low = 21");
        check(dmem[3][63:32] === 32'hFFFF_FFFF, "AMOADD.W high intact");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
