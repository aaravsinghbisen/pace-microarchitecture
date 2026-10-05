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
module tb_mc_l1d;
    reg clk = 0, rst_n;
    wire mc_req, mc_we;
    wire [63:0] mc_addr, mc_wdata, mc_rdata;
    wire mc_ready;
    wire l1d_req, l1d_we;
    wire [63:0] l1d_addr, l1d_wdata;
    wire [511:0] l1d_rdata;
    wire l1d_ready;
    wire dram_req, dram_we;
    wire [63:0] dram_addr;
    wire [511:0] dram_wdata;
    reg [511:0] dram_rdata;
    reg dram_ready;
    wire shdw_we, shdw_exc, mc_busy;
    wire [4:0] shdw_rd;
    wire [63:0] shdw_data;
    reg [31:0] instr;
    reg [4:0] dbg_rs = 0;
    wire [63:0] dbg_rd;

    reg [511:0] dmem [0:127];
    reg [3:0] dram_delay;
    integer i;

    m_core u_mc (
        .clk(clk), .rst_n(rst_n),
        .stall_in(1'b0), .shdw_wr_ready(1'b1),
        .pc_out(), .instr_in(instr),
        .shadow_we(shdw_we), .shadow_rd(shdw_rd),
        .shadow_data(shdw_data), .shadow_exc(shdw_exc),
        .busy(mc_busy),
        .ext_wr_en(1'b0), .ext_wr_addr(5'd0), .ext_wr_data(64'd0),
        .mem_req(mc_req), .mem_we(mc_we),
        .mem_addr(mc_addr), .mem_wdata(mc_wdata),
        .mem_rdata(mc_rdata), .mem_ready(mc_ready),
        .dbg_rs(dbg_rs), .dbg_rd(dbg_rd)
    );

    l1d u_l1d (
        .clk(clk), .rst_n(rst_n),
        .cpu_req(mc_req), .cpu_we(mc_we),
        .cpu_addr(mc_addr), .cpu_wdata(mc_wdata),
        .cpu_rdata(mc_rdata), .cpu_ready(mc_ready),
        .l2_req(l1d_req), .l2_we(l1d_we),
        .l2_addr(l1d_addr), .l2_wdata(l1d_wdata),
        .l2_rdata(l1d_rdata), .l2_ready(l1d_ready),
        .snp_valid(1'b0), .snp_we(1'b0), .snp_addr(64'd0), .snp_wdata(64'd0)
    );

    l2 u_l2 (
        .clk(clk), .rst_n(rst_n),
        .p0_req(1'b0), .p0_addr(64'd0), .p0_rdata(), .p0_ready(),
        .p1_req(l1d_req), .p1_we(l1d_we),
        .p1_addr(l1d_addr), .p1_wdata({448'b0, l1d_wdata[63:0]}),
        .p1_rdata(l1d_rdata), .p1_ready(l1d_ready),
        .mem_req(dram_req), .mem_we(dram_we),
        .mem_addr(dram_addr), .mem_wdata(dram_wdata),
        .mem_rdata(dram_rdata), .mem_ready(dram_ready)
    );

    always @(posedge clk) begin
        dram_ready <= 0;
        if (dram_req && dram_delay == 0) dram_delay <= 8;
        else if (dram_delay > 0) begin
            dram_delay <= dram_delay - 1;
            if (dram_delay == 1) begin
                if (dram_we) dmem[dram_addr[12:6]][dram_addr[5:3]*64 +: 64] <= dram_wdata[63:0];
                else        dram_rdata <= dmem[dram_addr[12:6]];
                dram_ready <= 1;
            end
        end
    end

    always #5 clk = ~clk;

    // Full trace
    always @(posedge clk) begin
        if (rst_n)
            $display("t=%0t MC[st=%0d busy=%b req=%b addr=%h rdy=%b] L1[st=%0d rdy=%b] L2[st=%0d rdy=%b] DRAM[st=%0d rdy=%b] shdw_we=%b rd=x%0d data=%h",
                $time, u_mc.state, mc_busy, mc_req, mc_addr, mc_ready,
                u_l1d.state, mc_ready,
                u_l2.state, l1d_ready,
                dram_delay, dram_ready,
                shdw_we, shdw_rd, shdw_data);
    end

    integer tests_run=0, tests_passed=0, tests_failed=0;
    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    localparam NOP = 32'h00000013;
    reg [63:0] captured_data;
    reg [4:0]  captured_rd;

    // Capture first shadow write
    always @(posedge clk) begin
        if (shdw_we) begin
            captured_data <= shdw_data;
            captured_rd   <= shdw_rd;
        end
    end

    initial begin
        for (i=0; i<128; i=i+1) dmem[i] = 0;
        dmem[1][63:0] = 64'hCAFEBABE;

        rst_n = 0;
        instr = NOP;
        dram_delay = 0;
        #20 rst_n = 1;
        #10;

        $display("========================================");
        $display("  MC+Mem isolated (verbose)");
        $display("========================================");

        instr = 32'h04002283;   // lw x5, 64(x0)
        repeat(2) @(posedge clk);
        instr = NOP;

        // wait 200 cycles
        repeat(200) @(posedge clk);
        #1;

        $display("--- captured ---");
        $display("captured_rd=%0d captured_data=%h", captured_rd, captured_data);

        check(captured_rd === 5'd5, "captured rd = x5");
        check(captured_data === {{32{1'b1}}, 32'hCAFEBABE}, "captured data sign-extended");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        $display("========================================");
        $finish;
    end
endmodule
