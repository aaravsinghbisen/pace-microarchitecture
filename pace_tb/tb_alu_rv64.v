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

module tb_alu_rv64;

    // === Sinais do testbench ===
    reg         clk;
    reg  [63:0] in0_alu;
    reg  [63:0] in1_alu;
    reg  [3:0]  opcd_alu;
    wire [63:0] out_alu;

    // === Opcodes da ALU ===
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_XOR  = 4'b0100;
    localparam ALU_SLL  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;

    // === Contadores de resultado ===
    integer tests_run    = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;

    // === Instancia a ALU ===
    alu_rv64 dut (
        .in0_alu  (in0_alu),
        .in1_alu  (in1_alu),
        .opcd_alu (opcd_alu),
        .out_alu  (out_alu)
    );

    // === Clock (Verilator precisa pra avançar tempo) ===
    initial clk = 0;
    always #5 clk = ~clk;

    // === Task de checagem ===
    task check;
        input [63:0]  a;
        input [63:0]  b;
        input [3:0]   op;
        input [63:0]  expected;
        input [255:0] name;
        begin
            in0_alu  = a;
            in1_alu  = b;
            opcd_alu = op;
            @(posedge clk);
            tests_run = tests_run + 1;
            if (out_alu === expected) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s : a=%h b=%h op=%b -> out=%h",
                         name, a, b, op, out_alu);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s : a=%h b=%h op=%b -> out=%h (expected %h)",
                         name, a, b, op, out_alu, expected);
            end
        end
    endtask

    // === Sequência de testes ===
    initial begin
        in0_alu  = 0;
        in1_alu  = 0;
        opcd_alu = 0;

        $display("========================================");
        $display("  ALU RV64 Testbench - Starting");
        $display("========================================");

        // ADD
        check(64'd10, 64'd20, ALU_ADD, 64'd30, "ADD   10 + 20");
        check(64'd0,  64'd0,  ALU_ADD, 64'd0,  "ADD   0 + 0");
        check(64'hFFFFFFFFFFFFFFFF, 64'd1, ALU_ADD, 64'd0, "ADD   overflow wrap");

        // SUB
        check(64'd50, 64'd20, ALU_SUB, 64'd30, "SUB   50 - 20");
        check(64'd7,  64'd7,  ALU_SUB, 64'd0,  "SUB   equal -> 0");

        // AND / OR / XOR
        check(64'hFF00FF00FF00FF00, 64'h0FF00FF00FF00FF0,
              ALU_AND, 64'h0F000F000F000F00, "AND   mask");
        check(64'hFF00FF00FF00FF00, 64'h00FF00FF00FF00FF,
              ALU_OR, 64'hFFFFFFFFFFFFFFFF, "OR    all ones");
        check(64'hAAAAAAAAAAAAAAAA, 64'hFFFFFFFFFFFFFFFF,
              ALU_XOR, 64'h5555555555555555, "XOR   invert");

        // Shifts
        check(64'd1, 64'd4, ALU_SLL, 64'd16, "SLL   1 << 4");
        check(64'h8000000000000000, 64'd4, ALU_SRL, 64'h0800000000000000,
              "SRL   logical shift right");
        check(64'hF000000000000000, 64'd4, ALU_SRA, 64'hFF00000000000000,
              "SRA   arithmetic shift right");

        // SLT / SLTU
        check(64'd5,  64'd10, ALU_SLT, 64'd1, "SLT   5 < 10 (true)");
        check(64'd10, 64'd5,  ALU_SLT, 64'd0, "SLT   10 < 5 (false)");
        check(64'hFFFFFFFFFFFFFFFF, 64'd0, ALU_SLT, 64'd1,
              "SLT   -1 < 0 (signed)");
        check(64'd5, 64'd10, ALU_SLTU, 64'd1, "SLTU  5 < 10 (true)");
        check(64'hFFFFFFFFFFFFFFFF, 64'd0, ALU_SLTU, 64'd0,
              "SLTU  max < 0 (unsigned)");

        // Opcode inválido
        check(64'd10, 64'd20, 4'b1111, 64'd0, "DEFAULT invalid op -> 0");

        // === Sumário ===
        $display("========================================");
        $display("  Tests run:    %0d", tests_run);
        $display("  Tests passed: %0d", tests_passed);
        $display("  Tests failed: %0d", tests_failed);
        if (tests_failed == 0)
            $display("  RESULT: ALL TESTS PASSED");
        else
            $display("  RESULT: SOME TESTS FAILED");
        $display("========================================");

        $finish;
    end

endmodule
