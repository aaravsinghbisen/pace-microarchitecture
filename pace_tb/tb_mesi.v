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
module tb_mesi;
    reg clk=0, rst_n=0;
    reg         local_req, local_write, local_hit;
    wire        need_bus_rd, need_bus_rdx, need_bus_upgr;
    wire        local_done, flush_data_valid;
    wire [63:0] flush_data;
    reg         bus_rd, bus_rdx, bus_upgr;
    reg  [31:0] bus_addr;
    reg  [31:0] my_addr;
    wire [1:0]  state;
    reg  [63:0] write_data_in;
    wire [63:0] data_out;
    reg  [63:0] data_in_local;

    integer tests_run=0, tests_passed=0, tests_failed=0;

    mesi_ctrl dut (
        .clk(clk), .rst_n(rst_n),
        .local_req(local_req), .local_write(local_write), .local_hit(local_hit),
        .need_bus_rd(need_bus_rd), .need_bus_rdx(need_bus_rdx), .need_bus_upgr(need_bus_upgr),
        .local_done(local_done),
        .flush_data_valid(flush_data_valid), .flush_data(flush_data),
        .bus_rd(bus_rd), .bus_rdx(bus_rdx), .bus_upgr(bus_upgr),
        .bus_addr(bus_addr), .my_addr(my_addr),
        .state(state),
        .write_data_in(write_data_in),
        .data_out(data_out), .data_in_local(data_in_local)
    );

    always #5 clk = ~clk;

    localparam I = 2'b00, S = 2'b01, E = 2'b10, M = 2'b11;

    task check;
        input cond; input [255:0] name;
        begin
            tests_run = tests_run + 1;
            if (cond) begin tests_passed = tests_passed + 1; $display("[PASS] %0s", name); end
            else      begin tests_failed = tests_failed + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    task tick;
        begin @(posedge clk); @(negedge clk); end
    endtask

    initial begin
        local_req=0; local_write=0; local_hit=0;
        bus_rd=0; bus_rdx=0; bus_upgr=0;
        bus_addr=0; my_addr=32'h1000;
        write_data_in=0; data_in_local=0;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  MESI Testbench");
        $display("========================================");

        check(state === I, "T0: reset -> I");

        // ===== T1: local read miss -> bus_rd -> E =====
        write_data_in = 64'hDEADBEEF;
        local_req = 1; local_write = 0; tick();
        check(need_bus_rd === 1, "T1: read miss needs BusRd");
        local_req = 0;
        tick();
        check(state === E, "T1: state = E after BusRd");
        check(data_out === 64'hDEADBEEF, "T1: data loaded");

        // ===== T2: local write hit (E -> M) =====
        local_req = 1; local_write = 1; data_in_local = 64'hCAFE; tick();
        local_req = 0;
        check(state === M, "T2: E->M on write");
        check(data_out === 64'hCAFE, "T2: data updated");

        // ===== T3: snoop BusRd em M -> flush + S =====
        bus_addr = 32'h1000; bus_rd = 1;
        tick();
        check(flush_data_valid === 1, "T3: flush on BusRd");
        check(flush_data === 64'hCAFE, "T3: correct flush data");
        bus_rd = 0;
        check(state === S, "T3: M->S after BusRd");

        // ===== T4: snoop BusRdX em S -> I =====
        bus_addr = 32'h1000; bus_rdx = 1; tick();
        bus_rdx = 0;
        check(state === I, "T4: S->I on BusRdX");

        // ===== T5: local write miss -> BusRdX -> M =====
        local_req = 1; local_write = 1; data_in_local = 64'h1234; tick();
        check(need_bus_rdx === 1, "T5: write miss needs BusRdX");
        local_req = 0;
        check(state === M, "T5: I->M on write miss");
        check(data_out === 64'h1234, "T5: data stored");

        // ===== T6: BusRd em M -> S =====
        bus_addr = 32'h1000; bus_rd = 1; tick();
        bus_rd = 0;
        check(state === S, "T6: M->S");

        // ===== T7: local write hit em S -> BusUpgr -> M =====
        local_req = 1; local_write = 1; data_in_local = 64'h9999; tick();
        check(need_bus_upgr === 1, "T7: write hit on S needs BusUpgr");
        local_req = 0;
        check(state === M, "T7: S->M via upgrade");

        // ===== T8: snoop em outro endereço não afeta =====
        bus_addr = 32'h2000; bus_rd = 1; tick();
        bus_rd = 0;
        check(state === M, "T8: other addr doesn't affect");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", tests_run, tests_passed, tests_failed);
        if (tests_failed==0) $display("  ALL PASSED");
        else                 $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
