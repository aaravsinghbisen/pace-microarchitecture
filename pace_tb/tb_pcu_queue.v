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
module tb_pcu_queue;
    reg clk=0, rst_n=0;
    reg [4:0] dbg_rs = 0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_satp;
    wire        dbg_satp_en;
    wire [6*32-1:0] imem_instr;
    reg [31:0] imem [0:255];
    integer i, t_run=0, t_pass=0, t_fail=0;

    // Fila
    wire        mq_push_en, mq_full;
    wire [2:0]  mq_push_op;
    wire [63:0] mq_push_addr, mq_push_rs2;
    wire [4:0]  mq_push_rd, mq_push_amo_f5;
    wire [2:0]  mq_push_funct3;
    wire        mq_pop_en, mq_pop_valid;
    wire [2:0]  mq_op;
    wire [63:0] mq_addr, mq_rs2;
    wire [4:0]  mq_rd, mq_amo_f5;
    wire [2:0]  mq_funct3;

    // Instancia só o PCU (com stub para os outros sinais)
    wire [5:0] shdw_we;
    wire [6*5-1:0] shdw_rd;
    wire [6*64-1:0] shdw_data;
    wire [5:0] num_writes;
    wire br_valid, br_taken;
    wire [63:0] br_target;
    reg  redirect_valid=0;
    reg  [63:0] redirect_pc=0;

    pcu6_v #(.HART_ID(0)) u_pcu (
        .clk(clk), .rst_n(rst_n),
        .stall(1'b0), .fetch_stall(1'b0), .shdw_wr_ready(4'd6),
        .instr_count(4'd1),
        .instr_in(imem_instr),
        .pc_out(dbg_pcu_pc),
        .shadow_we(shdw_we), .shadow_rd(shdw_rd), .shadow_data(shdw_data),
        .num_writes(num_writes),
        .br_valid(br_valid), .br_taken(br_taken), .br_target(br_target),
        .redirect_valid(redirect_valid), .redirect_pc(redirect_pc),
        .ext_wr_en(1'b0), .ext_wr_addr(5'd0), .ext_wr_data(64'd0),
        .dbg_priv(),
        .dbg_satp(dbg_satp), .dbg_satp_enable(dbg_satp_en),
        .dbg_flush_tlb(), .dbg_trap_taken(),
        .dbg_advance(), .dbg_flush_fetch(), .dbg_new_pc(),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_vl(), .dbg_vtype(), .dbg_vrs(5'd0), .dbg_vrd(),
        .mq_push_en(mq_push_en), .mq_push_op(mq_push_op),
        .mq_push_addr(mq_push_addr), .mq_push_rs2(mq_push_rs2),
        .mq_push_rd(mq_push_rd), .mq_push_funct3(mq_push_funct3),
        .mq_push_amo_f5(mq_push_amo_f5), .mq_full(mq_full),
        .vmem_req(), .vmem_we(), .vmem_addr(), .vmem_wdata(),
        .vmem_rdata(64'd0), .vmem_ready(1'b0)
    );

    mem_queue #(.DEPTH(8)) u_mq (
        .clk(clk), .rst_n(rst_n),
        .push_en(mq_push_en), .push_op(mq_push_op),
        .push_addr(mq_push_addr), .push_rs2(mq_push_rs2),
        .push_rd(mq_push_rd), .push_funct3(mq_push_funct3),
        .push_amo_f5(mq_push_amo_f5),
        .push_ready(), .full(mq_full),
        .pop_en(mq_pop_en), .pop_op(mq_op),
        .pop_addr(mq_addr), .pop_rs2(mq_rs2),
        .pop_rd(mq_rd), .pop_funct3(mq_funct3),
        .pop_amo_f5(mq_amo_f5),
        .pop_valid(mq_pop_valid)
    );

    // Pop dummy: consome tudo imediatamente pra não encher
    assign mq_pop_en = mq_pop_valid;

    always #5 clk = ~clk;

    wire [31:0] i0 = imem[dbg_pcu_pc[9:2] + 0];
    wire [31:0] i1 = imem[dbg_pcu_pc[9:2] + 1];
    wire [31:0] i2 = imem[dbg_pcu_pc[9:2] + 2];
    wire [31:0] i3 = imem[dbg_pcu_pc[9:2] + 3];
    wire [31:0] i4 = imem[dbg_pcu_pc[9:2] + 4];
    wire [31:0] i5 = imem[dbg_pcu_pc[9:2] + 5];
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    // Captura o que passa pela fila
    reg captured;
    reg [2:0] cap_op;
    reg [63:0] cap_addr, cap_rs2;
    reg [4:0] cap_rd;

    always @(posedge clk) begin
        if (mq_push_en) begin
            cap_op   = mq_push_op;
            cap_addr = mq_push_addr;
            cap_rs2  = mq_push_rs2;
            cap_rd   = mq_push_rd;
            captured = 1;
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

    initial begin
        for (i=0; i<256; i=i+1) imem[i] = 32'h00000013;
        captured = 0;

        // Programa:
        //  0x00  addi x1, x0, 64
        //  0x04  addi x2, x0, 10
        //  0x08  sw x2, 0(x1)     ← deve ir pra fila
        //  0x0C  addi x3, x0, 5
        //  0x10  amoadd.d x4, x3, (x1)  ← deve ir pra fila
        //  0x14  jal x0, 0
        imem[0] = 32'h04000093;
        imem[1] = 32'h00A00113;
        imem[2] = 32'h0020B023;   // sw x2, 0(x1)
        imem[3] = 32'h00500193;
        imem[4] = 32'h0030B22F;   // amoadd.d x4, x3, (x1)
        imem[5] = 32'h0000006F;

        #20 rst_n = 1;

        $display("========================================");
        $display("  PCU -> Queue test");
        $display("========================================");

        // Espera o push
        for (i=0; i<50; i=i+1) begin
            @(posedge clk);
            if (mq_push_en) begin
                $display("  t=%0t push_en=%b op=%0d addr=%0d rs2=%0d rd=x%0d",
                         $time, mq_push_en, mq_push_op, mq_push_addr, mq_push_rs2, mq_push_rd);
            end
        end

        check(captured === 1'b1, "PCU empurrou algo pra fila");
        $display("  último capturado: op=%0d addr=%0d", cap_op, cap_addr);

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
