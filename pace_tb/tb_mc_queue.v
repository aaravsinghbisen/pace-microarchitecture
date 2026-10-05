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
module tb_mc_queue;
    reg clk=0, rst_n=0;
    reg push_en;
    reg [2:0] push_op;
    reg [63:0] push_addr, push_rs2;
    reg [4:0] push_rd, push_amo_f5;
    reg [2:0] push_funct3;
    wire full;
    wire pop_en, pop_valid;
    wire [2:0] pop_op;
    wire [63:0] pop_addr, pop_rs2;
    wire [4:0] pop_rd, pop_amo_f5;
    wire [2:0] pop_funct3;
    wire mc_shdw_we;
    wire [4:0] mc_shdw_rd;
    wire [63:0] mc_shdw_data;
    wire mc_shdw_exc;
    wire mc_ext_en;
    wire [4:0] mc_ext_addr;
    wire [63:0] mc_ext_data;
    wire mem_req, mem_we;
    wire [63:0] mem_addr, mem_wdata;
    reg [63:0] mem_rdata;
    reg mem_ready;
    reg [63:0] dmem [0:255];
    integer t_run=0, t_pass=0, t_fail=0;

    mem_queue #(.DEPTH(8)) u_mq (
        .clk(clk), .rst_n(rst_n),
        .push_en(push_en), .push_op(push_op),
        .push_addr(push_addr), .push_rs2(push_rs2),
        .push_rd(push_rd), .push_funct3(push_funct3),
        .push_amo_f5(push_amo_f5),
        .push_ready(), .full(full),
        .pop_en(pop_en), .pop_op(pop_op),
        .pop_addr(pop_addr), .pop_rs2(pop_rs2),
        .pop_rd(pop_rd), .pop_funct3(pop_funct3),
        .pop_amo_f5(pop_amo_f5),
        .pop_valid(pop_valid)
    );

    m_core u_mc (
        .clk(clk), .rst_n(rst_n),
        .mq_full(full),
        .mq_pop_valid(pop_valid), .mq_pop_en(pop_en),
        .mq_op(pop_op), .mq_addr(pop_addr), .mq_rs2(pop_rs2),
        .mq_rd(pop_rd), .mq_funct3(pop_funct3), .mq_amo_f5(pop_amo_f5),
        .shadow_we(mc_shdw_we), .shadow_rd(mc_shdw_rd),
        .shadow_data(mc_shdw_data), .shadow_exc(mc_shdw_exc),
        .ext_wr_en(mc_ext_en), .ext_wr_addr(mc_ext_addr),
        .ext_wr_data(mc_ext_data),
        .mem_req(mem_req), .mem_we(mem_we),
        .mem_addr(mem_addr), .mem_wdata(mem_wdata),
        .mem_rdata(mem_rdata), .mem_ready(mem_ready),
        .dbg_rs(5'd0), .dbg_rd()
    );

    always #5 clk = ~clk;

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
            t_run = t_run + 1;
            if (cond) begin t_pass = t_pass + 1; $display("[PASS] %0s", name); end
            else      begin t_fail = t_fail + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task push_op_task;
        input [2:0] op; input [63:0] a, d; input [4:0] rd;
        input [2:0] f3; input [4:0] amo5;
        begin
            @(negedge clk);
            push_en=1; push_op=op; push_addr=a; push_rs2=d;
            push_rd=rd; push_funct3=f3; push_amo_f5=amo5;
            @(posedge clk); @(negedge clk);
            push_en=0;
        end
    endtask

    initial begin
        for (integer i = 0; i < 256; i = i + 1) dmem[i] = 0;
        push_en=0; push_op=0; push_addr=0; push_rs2=0;
        push_rd=0; push_funct3=0; push_amo_f5=0;
        #20 rst_n = 1;

        $display("========================================");
        $display("  MC + Queue direct test");
        $display("========================================");

        // STORE 10 → dmem[8]
        push_op_task(3'd1, 64'd64, 64'd10, 5'd0, 3'b011, 5'd0);
        repeat(5) @(posedge clk);
        $display("  dmem[8] = %0d (exp 10)", dmem[8]);
        check(dmem[8] === 64'd10, "STORE dmem[8]=10");

        // AMOADD 5 → dmem[8], rd=x4
        push_op_task(3'd4, 64'd64, 64'd5, 5'd4, 3'b011, 5'b00000);
        repeat(10) @(posedge clk);
        $display("  dmem[8] = %0d (exp 15)", dmem[8]);
        check(dmem[8] === 64'd15, "AMOADD dmem[8]=15");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
