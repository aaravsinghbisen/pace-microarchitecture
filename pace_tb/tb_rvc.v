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
module tb_rvc;
    reg  [15:0] i16;
    wire [31:0] i32;
    wire        is_c, ill;
    integer tests_run=0, tests_passed=0, tests_failed=0;

    rvc_decompress dut (.instr16(i16), .instr32(i32), .is_compressed(is_c), .illegal(ill));

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    initial begin
        $display("========================================");
        $display("  RVC Decompress Testbench");
        $display("========================================");

        // C.NOP = 0x0001 → addi x0, x0, 0 = 0x00000013
        i16 = 16'h0001; #1;
        check(is_c === 1'b1, "C.NOP: is_compressed");
        check(i32 === 32'h00000013, "C.NOP → addi x0,x0,0");
        $display("       got = %h", i32);

        // C.ADDI x5, 1 → addi x5, x5, 1
        //   c.rd = x5 = 00101, imm = 1 → 16-bit: 000_0_00001_00101_01
        //   f3=000, imm[5]=0, imm[4:0]=00001, rd=00101, op=01
        //   = 0000_0000_0100_0101 = 0x0045
        i16 = 16'h0285; #1;
        // esperado: addi x5, x5, 1 = 0x00128293
        check(is_c === 1'b1, "C.ADDI: is_compressed");
        $display("       C.ADDI got = %h (exp 0x00128293)", i32);
        check(i32 === 32'h00128293, "C.ADDI x5,1");

        // C.LI x5, 1 → addi x5, x0, 1 = 0x00100293
        //   f3=010, imm=1, rd=00101, op=01
        //   = 010_0_00001_00101_01 = 0x4045
        i16 = 16'h4285; #1;
        check(i32 === 32'h00100293, "C.LI x5,1");
        $display("       C.LI got = %h (exp 0x00100293)", i32);

        // C.MV x5, x6 → add x5, x0, x6
        //   f3=100, bit12=0, rd=x5, rs2=x6, op=10
        //   = 100_0_00110_00101_10 = 0x8316
        //   exp: add x5, x0, x6 = funct7=0, rs2=6, rs1=0, f3=0, rd=5, op=0110011
        //      = 0x006002B3
        i16 = 16'h829A; #1;
        check(i32 === 32'h006002B3, "C.MV x5, x6");
        $display("       C.MV got = %h (exp 0x006002b3)", i32);

        // Non-compressed: op = 2'b11
        i16 = 16'hFFFF; #1;
        check(is_c === 1'b0, "32-bit instr: not compressed");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
