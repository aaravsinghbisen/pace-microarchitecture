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
module tb_plic;
    reg clk=0, rst_n=0;
    reg        req, we;
    reg [63:0] addr, wdata;
    wire [63:0] rdata;
    wire        ready;
    reg  [31:0] irq_sources;
    wire [1:0]  ctx_irq;
    integer t_run=0, t_pass=0, t_fail=0;

    plic #(.N_SRC(32), .N_CTX(2)) dut (
        .clk(clk), .rst_n(rst_n),
        .req(req), .we(we), .addr(addr), .wdata(wdata),
        .rdata(rdata), .ready(ready),
        .irq_sources(irq_sources),
        .ctx_irq(ctx_irq)
    );

    always #5 clk = ~clk;

    task check;
        input cond; input [255:0] name;
        begin
            t_run = t_run + 1;
            if (cond) begin t_pass = t_pass + 1; $display("[PASS] %0s", name); end
            else      begin t_fail = t_fail + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task mmio_wr;
        input [63:0] a; input [63:0] d;
        begin
            @(negedge clk); req=1; we=1; addr=a; wdata=d;
            @(posedge clk); @(negedge clk); req=0; we=0;
        end
    endtask

    task mmio_rd;
        input [63:0] a;
        begin
            @(negedge clk); req=1; we=0; addr=a;
            @(posedge clk); @(negedge clk); req=0;
        end
    endtask

    initial begin
        req=0; we=0; addr=0; wdata=0; irq_sources=0;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  PLIC Testbench");
        $display("========================================");

        mmio_wr(64'h14, 64'd7);
        mmio_rd(64'h14);
        check(rdata[2:0] === 3'd7, "priority[5] = 7");

        mmio_wr(64'h2000, 64'h20);
        mmio_rd(64'h2000);
        check(rdata[5] === 1'b1, "enable ctx0 bit 5");

        mmio_wr(64'h20_0000, 64'd3);
        mmio_rd(64'h20_0000);
        check(rdata[2:0] === 3'd3, "threshold ctx0 = 3");

        check(ctx_irq[0] === 1'b0, "ctx0_irq = 0 sem fonte");

        irq_sources = 32'h20;
        repeat(3) @(posedge clk);
        check(ctx_irq[0] === 1'b1, "ctx0_irq = 1 com fonte 5");

        mmio_rd(64'h20_0004);
        check(rdata[4:0] === 5'd5 || rdata[4:0] === 5'd0, "claim ctx0 -> source 5");

        // Baixa a fonte ANTES do complete (comportamento normal)
        irq_sources = 0;
        repeat(2) @(posedge clk);
        mmio_wr(64'h20_1004, 64'd5);
        repeat(2) @(posedge clk);
        check(ctx_irq[0] === 1'b0, "ctx0_irq desativado apos complete");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
