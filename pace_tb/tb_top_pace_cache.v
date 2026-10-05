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
module tb_top_pace_cache;
    reg clk = 0, rst_n_pcu, rst_n_ao;
    wire [63:0] dbg_pcu_pc, dbg_ao_pc, dbg_arch_rd;
    reg  [4:0]  dbg_rs;

    // DRAM (top)
    wire        dram_req, dram_we;
    wire [63:0] dram_addr;
    wire [511:0] dram_wdata;
    reg  [511:0] dram_rdata;
    reg         dram_ready;

    // MMIO (top)
    wire        mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;

    // Debug
    wire [5:0] shdw_wr_ptr, shdw_rd_ptr;
    wire shdw_empty, shdw_full;
    wire pcu_shdw_we, mc_shdw_we, rf_wr_en, redir_v;
    wire [4:0] pcu_shdw_rd, mc_shdw_rd;
    wire [63:0] pcu_shdw_data, mc_shdw_data;

    // Internal l1d/l2 probes (via hierarchical paths)
    wire        mc_req      = dut.mc_req;
    wire        mc_we       = dut.mc_we;
    wire [63:0] mc_addr     = dut.mc_addr;
    wire        mc_ready    = dut.mc_ready;
    wire [63:0] mc_rdata    = dut.mc_rdata;
    wire        l1d_l2_req  = dut.l1d_l2_req;
    wire [63:0] l1d_l2_addr = dut.l1d_l2_addr;
    wire        l1d_l2_ready= dut.l1d_l2_ready;
    wire [511:0]l1d_l2_rdata= dut.l1d_l2_rdata;
    wire        pcu_l2_req  = dut.pcu_l2_req;

    integer i;
    reg [511:0] dmem [0:127];

    top_pace_cache dut (
        .clk(clk), .rst_n_pcu(rst_n_pcu), .rst_n_ao(rst_n_ao),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_ao_pc(dbg_ao_pc),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dram_req(dram_req), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata),
        .dram_rdata(dram_rdata), .dram_ready(dram_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .dbg_shdw_wr_ptr(shdw_wr_ptr), .dbg_shdw_rd_ptr(shdw_rd_ptr),
        .dbg_shdw_empty(shdw_empty), .dbg_shdw_full(shdw_full),
        .dbg_pcu_shdw_we(pcu_shdw_we), .dbg_mc_shdw_we(mc_shdw_we),
        .dbg_pcu_shdw_rd(pcu_shdw_rd), .dbg_mc_shdw_rd(mc_shdw_rd),
        .dbg_pcu_shdw_data(pcu_shdw_data), .dbg_mc_shdw_data(mc_shdw_data),
        .dbg_rf_wr_en(rf_wr_en), .dbg_redir_v(redir_v)
    );

    always #5 clk = ~clk;

    // DRAM ~8 cycle latency
    reg [3:0] dram_delay;
    always @(posedge clk) begin
        dram_ready <= 0;
        if (dram_req && dram_delay == 0) dram_delay <= 8;
        else if (dram_delay > 0) begin
            dram_delay <= dram_delay - 1;
            if (dram_delay == 1) begin
                if (dram_we) dmem[dram_addr[12:6]][dram_addr[5:3]*64 +: 64] <= dram_wdata[63:0];
                else         dram_rdata <= dmem[dram_addr[12:6]];
                dram_ready <= 1;
            end
        end
    end

    // MMIO: 2-cycle latency, just returns the address XOR'd with magic
    reg [2:0] mmio_delay;
    reg       mmio_inflight;
    always @(posedge clk) begin
        mmio_ready <= 0;
        if (!mmio_inflight && mmio_req) begin
            mmio_inflight <= 1;
            mmio_delay <= 2;
        end else if (mmio_inflight) begin
            if (mmio_delay == 0) begin
                mmio_rdata <= 64'hA5A5_0000_0000_0000 | mmio_addr;
                mmio_ready <= 1;
                mmio_inflight <= 0;
            end else mmio_delay <= mmio_delay - 1;
        end
    end

    // Debug trace
    always @(posedge clk) begin
        if (rst_n_pcu) begin
            if (dut.u_l1d.state != 0 || mc_req || l1d_l2_req)
                $display("t=%0t L1d[st=%0d mmio=%b] L2[st=%0d p0r=%b p1r=%b rdy=%b] MC[req=%b we=%b addr=%h rdy=%b rdata=%h]",
                    $time, dut.u_l1d.state, dut.u_l1d.is_mmio_x,
                    dut.u_l2.state, pcu_l2_req, l1d_l2_req, l1d_l2_ready,
                    mc_req, mc_we, mc_addr, mc_ready, mc_rdata);
            if (pcu_shdw_we || mc_shdw_we || rf_wr_en)
                $display("t=%0t PCU_WR=%b MC_WR=%b COMMIT=%b x%0d<=%h",
                    $time, pcu_shdw_we, mc_shdw_we, rf_wr_en, dut.rf_wr_addr, dut.rf_wr_data);
        end
    end

    integer tests_run=0, tests_passed=0, tests_failed=0;
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

    localparam NOP = 32'h00000013;

    initial begin
        // Program at DRAM 0x8000_0000 (line 0 of dmem)
        // But dmem index uses addr[12:6]. Program instruction fetch goes through L1i/L2 too.
        // We use address 0x8000_0000 for both code and data.
        // PC starts at 0. Hmm, but PC = 0 maps to line 0 too...
        // Actually the top's PC starts at 0 and fetches instruction from l1i.
        // We need to set up L2's initial content. The dmem array represents L2 backing store.
        // Line 0 contains instructions, line 1 contains data.

        // Instructions (in dmem[0], 8 words = 8 instrs)
        dmem[0] = 512'd0;
        dmem[0][31:0]    = 32'h00500093;   // 0x00 addi x1, x0, 5
        dmem[0][63:32]   = 32'h00300113;   // 0x04 addi x2, x0, 3
        dmem[0][95:64]   = 32'h002081B3;   // 0x08 add  x3, x1, x2 = 8
        dmem[0][127:96]  = 32'h40208233;   // 0x0C sub  x4, x1, x2 = 2
        dmem[0][159:128] = 32'h04003303;   // 0x10 ld   x6, 64(x0)  -- will use addr=64
        dmem[0][191:160] = 32'h00134333;   // 0x14 xor  x6, x6, x1
        dmem[0][223:192] = NOP;
        dmem[0][255:224] = NOP;

        // Data at line 1 (addr 64)
        dmem[1] = 512'd0;
        dmem[1][63:0] = 64'hCAFEBABE;

        for (i=2; i<128; i=i+1) dmem[i] = 0;

        rst_n_pcu = 0; rst_n_ao = 0; dbg_rs = 0;
        dram_delay = 0;
        mmio_delay = 0;
        mmio_inflight = 0;
        mmio_rdata = 0;
        mmio_ready = 0;

        $display("========================================");
        $display("  PACE + Caches + MMIO");
        $display("========================================");

        #20 rst_n_pcu = 1;
        $display("[BOOT] PCU+M-Core enabled");
        repeat(150) @(posedge clk);
        @(negedge clk);

        $display("[BOOT] Enabling AO-Core");
        rst_n_ao = 1;
        repeat(150) @(posedge clk);
        @(negedge clk);

        check_arch(5'd1, 64'd5,          "x1");
        check_arch(5'd2, 64'd3,          "x2");
        check_arch(5'd3, 64'd8,          "x3");
        check_arch(5'd4, 64'd2,          "x4");
        check_arch(5'd6, 64'hCAFEBABB, "x6 = CAFEBABE ^ 5");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
