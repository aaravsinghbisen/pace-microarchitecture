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
module tb_uart;
    reg clk=0, rst_n=0;
    reg        req, we;
    reg [63:0] addr, wdata;
    wire [63:0] rdata;
    wire        ready;
    wire        tx;
    reg         rx;
    wire        irq;
    integer t_run=0, t_pass=0, t_fail=0;
    integer i;

    uart dut (.clk(clk), .rst_n(rst_n),
              .req(req), .we(we), .addr(addr), .wdata(wdata),
              .rdata(rdata), .ready(ready),
              .tx(tx), .rx(rx), .irq(irq));

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
        input [7:0] off; input [7:0] data;
        begin
            @(negedge clk);
            req=1; we=1; addr={56'b0, off}; wdata={56'b0, data};
            @(posedge clk); @(negedge clk);
            req=0; we=0;
        end
    endtask

    task mmio_rd;
        input [7:0] off;
        begin
            @(negedge clk);
            req=1; we=0; addr={56'b0, off};
            @(posedge clk); @(negedge clk);
            req=0;
        end
    endtask

    // Espera tx terminar
    task wait_tx;
        begin
            // Espera TX começar (busy sobe)
            repeat(200) @(posedge clk);
            // Espera TX terminar (busy desce) + margem
            while (dut.tx_busy) @(posedge clk);
            repeat(10) @(posedge clk);
        end
    endtask

    // Trace contínuo
    always @(posedge clk) begin
        if (rst_n && (dut.tx_busy || dut.tx_count > 0 || dut.tx_state != 0))
            $display("t=%0t tx_st=%0d busy=%b cnt=%0d rd=%0d wr=%0d tx=%b tick=%b",
                $time, dut.tx_state, dut.tx_busy, dut.tx_count,
                dut.tx_rd_ptr, dut.tx_wr_ptr, dut.tx, dut.sample_tick);
    end

    initial begin
        req=0; we=0; addr=0; wdata=0; rx=1;
        #20 rst_n = 1; #5;

        $display("========================================");
        $display("  UART 16550 Testbench");
        $display("========================================");

        // Teste 1: scratch register
        mmio_wr(8'h07, 8'hA5);
        mmio_rd(8'h07);
        check(rdata[7:0] === 8'hA5, "SCR write/read 0xA5");

        // Teste 2: escrita em THR (TX)
        mmio_wr(8'h03, 8'h03);  // LCR = 8 bits, 1 stop, sem paridade
        mmio_wr(8'h00, 8'h48);  // 'H'
        wait_tx();
        $display("  [DBG] tx_count=%0d tx_busy=%b tx_state=%0d", dut.tx_count, dut.tx_busy, dut.tx_state);
        check(dut.tx_count === 0, "TX esvaziou FIFO após 'H'");

        // Teste 3: Múltiplos bytes em sequência
        mmio_wr(8'h00, 8'h65);  // 'e'
        mmio_wr(8'h00, 8'h6C);  // 'l'
        mmio_wr(8'h00, 8'h6C);  // 'l'
        mmio_wr(8'h00, 8'h6F);  // 'o'
        repeat(1500) @(posedge clk);
        check(dut.tx_count === 0, "TX esvaziou FIFO após 'ello'");

        // Teste 4: LSR (line status)
        mmio_rd(8'h05);
        check(rdata[5] === 1'b1 || rdata[6] === 1'b1, "LSR bit 5/6 setado");

        // Teste 5: Divisor latch
        mmio_wr(8'h03, 8'h80);  // DLAB=1
        mmio_wr(8'h00, 8'h05);  // DLL = 5
        mmio_wr(8'h01, 8'h00);  // DLM = 0
        mmio_rd(8'h00);         // lê DLL
        check(rdata[7:0] === 8'h05, "DLL = 5 (divisor)");
        mmio_rd(8'h01);
        check(rdata[7:0] === 8'h00, "DLM = 0");
        mmio_wr(8'h03, 8'h03);  // DLAB=0

        // Teste 6: IER (interrupt enable)
        mmio_wr(8'h01, 8'h03);  // habilitar RX data + TX empty IRQ
        mmio_rd(8'h01);
        check(rdata[1:0] === 2'b11, "IER = 0x03");

        // Teste 7: FCR (FIFO control)
        mmio_wr(8'h02, 8'h07);  // habilita FIFO + clear
        mmio_rd(8'h02);
        check(rdata[7:6] === 2'b11, "IIR: FIFO enabled");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
