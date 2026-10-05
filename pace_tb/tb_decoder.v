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

module tb_decoder;

    reg  [31:0] instr;
    wire [6:0]  opcode;
    wire [4:0]  rd, rs1, rs2;
    wire [2:0]  funct3;
    wire [6:0]  funct7;
    wire [63:0] imm;
    wire [2:0]  format;

    integer tests_run    = 0;
    integer tests_passed = 0;
    integer tests_failed = 0;

    decoder dut (
        .instr(instr), .opcode(opcode), .rd(rd), .rs1(rs1), .rs2(rs2),
        .funct3(funct3), .funct7(funct7), .imm(imm), .format(format)
    );

    task check;
        input        cond;
        input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin
                tests_passed = tests_passed + 1;
                $display("[PASS] %0s", name);
            end else begin
                tests_failed = tests_failed + 1;
                $display("[FAIL] %0s", name);
            end
        end
    endtask

    initial begin
        $display("========================================");
        $display("  Decoder Testbench - Starting");
        $display("========================================");

        // === R-type: add x5, x6, x7 ===
        instr = 32'h007302B3;
        #1;
        check(opcode === 7'b0110011, "add: opcode");
        check(rd     === 5'd5,        "add: rd=5");
        check(rs1    === 5'd6,        "add: rs1=6");
        check(rs2    === 5'd7,        "add: rs2=7");
        check(funct3 === 3'b000,      "add: funct3=0");
        check(funct7 === 7'b0000000,  "add: funct7=0");
        check(format === 3'd0,        "add: format=R");

        // === I-type: addi x5, x6, -1 ===
        instr = 32'hFFF30293;
        #1;
        check(opcode === 7'b0010011, "addi: opcode");
        check(rd     === 5'd5,        "addi: rd=5");
        check(rs1    === 5'd6,        "addi: rs1=6");
        check(format === 3'd1,        "addi: format=I");
        check(imm    === 64'hFFFFFFFFFFFFFFFF, "addi: imm=-1");

        // === S-type: sw x5, 0(x6) ===
        instr = 32'h00532023;
        #1;
        check(opcode === 7'b0100011, "sw: opcode");
        check(funct3 === 3'b010,      "sw: funct3=2");
        check(rs1    === 5'd6,        "sw: rs1=6");
        check(rs2    === 5'd5,        "sw: rs2=5");
        check(format === 3'd2,        "sw: format=S");
        check(imm    === 64'd0,       "sw: imm=0");

        // === U-type: lui x5, 0x12345 ===
        instr = 32'h123452B7;
        #1;
        check(opcode === 7'b0110111, "lui: opcode");
        check(rd     === 5'd5,        "lui: rd=5");
        check(format === 3'd4,        "lui: format=U");
        check(imm    === 64'h0000000012345000, "lui: imm=0x12345000");

        // === J-type: jal x1, 4 ===
        instr = 32'h004000EF;
        #1;
        check(opcode === 7'b1101111, "jal: opcode");
        check(rd     === 5'd1,        "jal: rd=1");
        check(format === 3'd5,        "jal: format=J");
        check(imm    === 64'd4,       "jal: imm=4");

        // === Unknown opcode ===
        instr = 32'h00000000;
        #1;
        check(format === 3'd7, "invalid: format=UNKNOWN");

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
