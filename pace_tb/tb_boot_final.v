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
// Boot test: PACE executa o sequência que OpenSBI faz no boot.
// - Escreve 'P' em UART (MMIO 0x10000000)
// - Configura mtvec, mie, mstatus
// - Espera timer IRQ
// - Handler escreve 'I' em UART
// - mret
// Sem CLINT real — testbench força mtip.
module tb_boot_final;
    reg clk=0, rst_n=0;
    integer i, t_run=0, t_pass=0, t_fail=0;
    reg [4:0] dbg_rs=0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_satp;
    wire dbg_satp_en;
    wire [63:0] imem_pc;
    wire [6*32-1:0] imem_instr;
    wire dmem_req, dmem_we;
    wire [63:0] dmem_addr, dmem_wdata;
    reg  [63:0] dmem_rdata;
    reg         dmem_ready;
    wire vmem_req, vmem_we;
    wire [63:0] vmem_addr, vmem_wdata;
    reg  [63:0] vmem_rdata; reg vmem_ready;
    wire pte_req; wire [63:0] pte_addr;
    reg [63:0] pte_rdata; reg pte_ready;
    wire dmmu_pf; wire [63:0] dmmu_fc, dmmu_fv;
    wire mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg  [63:0] mmio_rdata;
    reg         mmio_ready;

    reg force_mtip;
    reg [7:0] uart [0:15];
    reg [3:0] uart_n;

    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:255];

    top_pace_imem #(.HART_ID(0)) dut (
        .clk(clk), .rst_n(rst_n), .i_instr_count(4'd1),
        .imem_pc(imem_pc), .imem_instr(imem_instr),
        .dmem_req(dmem_req), .dmem_we(dmem_we),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata),
        .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .vmem_req(vmem_req), .vmem_we(vmem_we),
        .vmem_addr(vmem_addr), .vmem_wdata(vmem_wdata),
        .vmem_rdata(vmem_rdata), .vmem_ready(vmem_ready),
        .pte_req(pte_req), .pte_addr(pte_addr),
        .pte_rdata(pte_rdata), .pte_ready(pte_ready),
        .dmmu_page_fault(dmmu_pf),
        .dmmu_fault_cause(dmmu_fc), .dmmu_fault_va(dmmu_fv),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .i_mtip(force_mtip), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en)
    );

    always #5 clk = ~clk;

    wire [31:0] i0 = imem[imem_pc[9:2] + 0];
    wire [31:0] i1 = imem[imem_pc[9:2] + 1];
    wire [31:0] i2 = imem[imem_pc[9:2] + 2];
    wire [31:0] i3 = imem[imem_pc[9:2] + 3];
    wire [31:0] i4 = imem[imem_pc[9:2] + 4];
    wire [31:0] i5 = imem[imem_pc[9:2] + 5];
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    // Slave: roteia UART vs DRAM
    wire is_uart = (dmem_addr[31:16] == 16'h1000);
    reg pending;
    always @(posedge clk) begin
        dmem_ready <= 0;
        if (!dmem_req) pending <= 0;
        else if (!pending) begin
            pending <= 1;
            if (is_uart && dmem_we) begin
                uart[uart_n] <= dmem_wdata[7:0];
                uart_n <= uart_n + 1;
            end else if (dmem_we) dmem[dmem_addr[8:3]] <= dmem_wdata;
            else dmem_rdata <= dmem[dmem_addr[8:3]];
            dmem_ready <= 1;
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
        for (i=0; i<256; i=i+1) begin imem[i] = 32'h00000013; dmem[i] = 0; end
        for (i=0; i<16; i=i+1) uart[i] = 0;
        uart_n = 0; force_mtip = 0;
        vmem_rdata = 0; vmem_ready = 0;
        pte_rdata = 0; pte_ready = 0;
        mmio_rdata = 0; mmio_ready = 0;
        dmem_rdata = 0; dmem_ready = 0;

        // ====== Programa ======
        //  0x00: lui  x1, 0x10000       # x1 = 0x10000000 (UART)
        imem[0] = 32'h100000B7;
        //  0x04: addi x2, x0, 0x50      # 'P'
        imem[1] = 32'h05000113;
        //  0x08: sw   x2, 0(x1)         # UART ← 'P'
        imem[2] = 32'h0020A023;
        //  0x0C: addi x6, x0, 0x40      # mtvec = 0x40
        imem[3] = 32'h04000313;
        //  0x10: csrw mtvec, x6
        imem[4] = 32'h30531073;
        //  0x14: addi x5, x0, 0x80      # MTIE
        imem[5] = 32'h08000293;
        //  0x18: csrrs x0, mie, x5
        imem[6] = 32'h3042A073;
        //  0x1C: addi x5, x0, 8         # MIE
        imem[7] = 32'h00800293;
        //  0x20: csrrs x0, mstatus, x5
        imem[8] = 32'h3002A073;
        //  0x24: jal x0, 0              # loop
        imem[9] = 32'h0000006F;

        // ====== Handler em 0x40 ======
        //  0x40: addi x11, x0, 0x49     # 'I'
        imem[16] = 32'h04900593;
        //  0x44: sw x11, 0(x1)          # UART ← 'I'
        imem[17] = 32'h00B0A023;
        //  0x48: mret
        imem[18] = 32'h30200073;

        #20 rst_n = 1;

        $display("========================================");
        $display("  PACE boot test (UART + IRQ + trap)");
        $display("========================================");

        // Espera o boot code rodar
        repeat(80) @(posedge clk);
        @(negedge clk);

        $display("  Após boot: PC=%h uart_n=%0d", dbg_pcu_pc, uart_n);
        check(uart_n >= 1, "UART recebeu 1 byte (boot)");
        check(uart[0] == 8'h50, "UART[0] = 'P'");

        // Força IRQ
        force_mtip = 1;
        repeat(60) @(posedge clk);
        @(negedge clk);

        $display("  Após IRQ: PC=%h uart_n=%0d", dbg_pcu_pc, uart_n);
        check(uart_n >= 2, "UART recebeu 2 bytes (boot + handler)");
        check(uart[1] == 8'h49, "UART[1] = 'I' (handler)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED — BOOT + IRQ + HANDLER");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
