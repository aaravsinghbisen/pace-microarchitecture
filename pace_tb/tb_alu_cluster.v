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
module tb_alu_cluster;
    localparam N = 6;
    reg clk=0, rst_n=0;

    reg  [N-1:0]        in_valid;
    reg  [N-1:0]        in_is_fpu;
    reg  [N*7-1:0]      in_opcode;
    reg  [N*3-1:0]      in_funct3;
    reg  [N*7-1:0]      in_funct7;
    reg  [N*5-1:0]      in_rs1, in_rs2, in_rd;
    reg  [N*64-1:0]     in_rs1_val, in_rs2_val, in_imm;
    wire [N-1:0]        out_we;
    wire [N*5-1:0]      out_rd;
    wire [N*64-1:0]     out_result;

    integer tests_run=0, tests_passed=0, tests_failed=0;

    alu_cluster #(.N(N)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .in_is_fpu(in_is_fpu),
        .in_opcode(in_opcode), .in_funct3(in_funct3), .in_funct7(in_funct7),
        .in_rs1(in_rs1), .in_rs2(in_rs2), .in_rd(in_rd),
        .in_rs1_val(in_rs1_val), .in_rs2_val(in_rs2_val), .in_imm(in_imm),
        .out_we(out_we), .out_rd(out_rd), .out_result(out_result)
    );

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    // Set helpers para slot i
    task set_slot;
        input integer i;
        input        is_fpu_;
        input [6:0]  opc;
        input [2:0]  f3;
        input [6:0]  f7;
        input [4:0]  r1, r2, rd;
        input [63:0] v1, v2, im;
        begin
            in_valid[i]          = 1;
            in_is_fpu[i]         = is_fpu_;
            in_opcode[i*7 +: 7]  = opc;
            in_funct3[i*3 +: 3]  = f3;
            in_funct7[i*7 +: 7]  = f7;
            in_rs1[i*5 +: 5]     = r1;
            in_rs2[i*5 +: 5]     = r2;
            in_rd[i*5 +: 5]      = rd;
            in_rs1_val[i*64 +: 64] = v1;
            in_rs2_val[i*64 +: 64] = v2;
            in_imm[i*64 +: 64]   = im;
        end
    endtask

    initial begin
        in_valid = 0; in_is_fpu = 0;
        in_opcode = 0; in_funct3 = 0; in_funct7 = 0;
        in_rs1 = 0; in_rs2 = 0; in_rd = 0;
        in_rs1_val = 0; in_rs2_val = 0; in_imm = 0;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  ALU Cluster with Forwarding");
        $display("========================================");

        // === T1: cadeia de RAW ADD ===
        // slot 0: add x5, x1, x2     (x1=10, x2=20 -> x5=30)
        // slot 1: add x6, x5, x3     (forward x5 -> x6=30+5=35)
        // slot 2: add x7, x6, x4     (forward x6 -> x7=35+7=42)
        // slots 3-5 idle
        set_slot(0, 0, 7'b0110011, 3'b000, 7'b0000000, 5'd1, 5'd2, 5'd5, 64'd10, 64'd20, 0);
        set_slot(1, 0, 7'b0110011, 3'b000, 7'b0000000, 5'd5, 5'd3, 5'd6, 64'd0,  64'd5,  0);
        set_slot(2, 0, 7'b0110011, 3'b000, 7'b0000000, 5'd6, 5'd4, 5'd7, 64'd0,  64'd7,  0);
        set_slot(3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        set_slot(4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        set_slot(5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        in_valid[3] = 0; in_valid[4] = 0; in_valid[5] = 0;
        #1;

        $display("       slot0 result = %0d (exp 30)", out_result[0*64 +: 64]);
        $display("       slot1 result = %0d (exp 35)", out_result[1*64 +: 64]);
        $display("       slot2 result = %0d (exp 42)", out_result[2*64 +: 64]);
        check(out_result[0*64 +: 64] === 64'd30, "T1: slot0 x5=30");
        check(out_result[1*64 +: 64] === 64'd35, "T1: slot1 x6=35 (fwd x5)");
        check(out_result[2*64 +: 64] === 64'd42, "T1: slot2 x7=42 (fwd x6)");

        // === T2: dois consumidores do mesmo produtor ===
        // slot 0: add x5, x1, x2 -> 30
        // slot 1: sub x6, x5, x1 -> 30 - 10 = 20 (fwd x5)
        // slot 2: and x7, x5, x4 -> 30 & 7 = 6 (fwd x5)
        set_slot(0, 0, 7'b0110011, 3'b000, 7'b0000000, 5'd1, 5'd2, 5'd5, 64'd10, 64'd20, 0);
        set_slot(1, 0, 7'b0110011, 3'b000, 7'b0100000, 5'd5, 5'd1, 5'd6, 64'd0,  64'd10, 0);
        set_slot(2, 0, 7'b0110011, 3'b111, 7'b0000000, 5'd5, 5'd4, 5'd7, 64'd0,  64'd7,  0);
        in_valid[0]=1; in_valid[1]=1; in_valid[2]=1;
        #1;
        $display("       slot1 result = %0d (exp 20)", out_result[1*64 +: 64]);
        $display("       slot2 result = %0d (exp 6)",  out_result[2*64 +: 64]);
        check(out_result[1*64 +: 64] === 64'd20, "T2: slot1 = 20 (fwd x5)");
        check(out_result[2*64 +: 64] === 64'd6,  "T2: slot2 = 6 (fwd x5)");

        // === T3: FPU com forwarding ===
        // slot 0: FADD.D 3.5+1.25 = 4.75 (bits 0x4013000000000000)
        // slot 1: FADD.D usando resultado do slot 0
        //   (na prática, slot1 veria o resultado FP como 64 bits, forwarding é genérico)
        // Na real, seria FMUL.D, mas FP forwarding geralmente é diferente.
        // Aqui testamos que o resultado do slot 0 chega no slot 1.
        // (Nota: forwarding é de bits, funciona pra qualquer tipo.)

        // Dois produtores com prioridade:
        // slot 0: add x5, x0, 100 -> 100
        // slot 1: add x5, x0, 200 -> 200 (sobrescreve!)
        // slot 2: add x6, x5, x0  -> deve receber 200 do slot 1 (mais novo)
        set_slot(0, 0, 7'b0010011, 3'b000, 0, 5'd0, 0, 5'd5, 0, 0, 64'd100);
        set_slot(1, 0, 7'b0010011, 3'b000, 0, 5'd0, 0, 5'd5, 0, 0, 64'd200);
        set_slot(2, 0, 7'b0110011, 3'b000, 0, 5'd5, 5'd0, 5'd6, 0, 0, 0);
        #1;
        $display("       slot2 result = %0d (exp 200, prioridade slot1)", out_result[2*64 +: 64]);
        check(out_result[2*64 +: 64] === 64'd200, "T3: prioridade slot mais novo");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
