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
module tb_irq_min;
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

    // Força mtip direto
    reg force_mtip;
    reg [7:0] uart_buf [0:15];
    reg [5:0] uart_count;

    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:511];

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

    // DMem: roteia UART em 0x1000_xxxx
    wire is_uart = (dmem_addr[31:16] == 16'h1000);
    always @(posedge clk) begin
        dmem_ready <= 0;
        if (dmem_req) begin
            if (is_uart && dmem_we) begin
                uart_buf[uart_count] <= dmem_wdata[7:0];
                uart_count <= uart_count + 1;
                dmem_ready <= 1;
            end else begin
                if (dmem_we) dmem[dmem_addr[12:3]] <= dmem_wdata;
                else         dmem_rdata <= dmem[dmem_addr[12:3]];
                dmem_ready <= 1;
            end
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

    // Trace do trap
    always @(posedge clk) begin
        if (rst_n && dut.u_pcu.u_csr_trap.trap_taken_w)
            $display("t=%0t TRAP! pc=%h cause=%h to_priv=%b",
                $time, dbg_pcu_pc, dut.u_pcu.u_csr_trap.trap_cause_w,
                dut.u_pcu.u_csr_trap.trap_priv_w);
    end

    always @(posedge clk) begin
        if (rst_n && dut.u_pcu.u_csr_trap.csr_req)
            $display("t=%0t PC=%h CSR req: addr=%h op=%b wdata=%h rd=x%0d",
                $time, dbg_pcu_pc, dut.u_pcu.u_csr_trap.csr_addr,
                dut.u_pcu.u_csr_trap.csr_op,
                dut.u_pcu.u_csr_trap.csr_wdata,
                dut.u_pcu.d_rd[0*5 +: 5]);
    end
    always @(posedge clk) begin
        if (rst_n && dut.u_pcu.pcu_stall_now === 0 && dut.u_pcu.alu_run[0])
            $display("t=%0t PC=%h ALU exec instr=%h rd=x%0d",
                $time, dbg_pcu_pc,
                dut.u_pcu.d_opcode[0*7 +: 7] ? dut.u_pcu.rs1_val[0*64 +: 64] : 0,
                0);
    end

    always @(posedge clk) begin
        if (rst_n)
            $display("t=%0t PC=%h instr=%h x5=%h",
                $time, dbg_pcu_pc,
                imem[dbg_pcu_pc[9:2]],
                dut.u_pcu.pcu_regs[5]);
    end

    initial begin


        for (i=0; i<256; i=i+1) imem[i] = 32'h00000013;
        for (i=0; i<512; i=i+1) dmem[i] = 0;
        for (i=0; i<16; i=i+1) uart_buf[i] = 0;
        uart_count = 0;
        force_mtip = 0;
        vmem_rdata = 0; vmem_ready = 0;
        pte_rdata = 0; pte_ready = 0;
        mmio_rdata = 0; mmio_ready = 0;
        dmem_rdata = 0; dmem_ready = 0;

        // Programa:
        //  0x00: lui  x1, 0x10000       # UART base
        //  0x04: lui  x6, 0x0           # (pra montar mtvec)
        //  0x08: addi x6, x6, 0x40      # mtvec = 0x40
        //  0x0C: csrw mtvec, x6
        //  0x10: addi x5, x0, 0x80      # MTIE bit
        //  0x14: csrrs x0, mie, x5      # habilita
        //  0x18: addi x5, x0, 8         # MIE
        //  0x1C: csrrs x0, mstatus, x5  # habilita
        //  0x20: jal x0, 0              # loop
        imem[0] = 32'h100000B7;
        imem[1] = 32'h00000337;
        imem[2] = 32'h04030313;
        imem[3] = 32'h30531073;
        imem[4] = 32'h08000293;
        imem[5] = 32'h3042A073;
        imem[6] = 32'h00800293;
        imem[7] = 32'h3002A073;
        imem[8] = 32'h0000006F;

        // Handler 0x40:
        //  0x40: addi x11, x0, 0x49     # 'I'
        //  0x44: sw x11, 0(x1)          # UART ← 'I'
        //  0x48: mret
        imem[16] = 32'h04900593;
        imem[17] = 32'h00B0A023;
        imem[18] = 32'h30200073;

        #20 rst_n = 1;

        $display("========================================");
        $display("  IRQ mínimo (mtip forçado)");
        $display("========================================");

        // Espera PCU configurar e entrar no loop
        repeat(60) @(posedge clk);
        @(negedge clk);

        $display("  Antes do IRQ: PC=%h, uart_count=%0d", dbg_pcu_pc, uart_count);
        $display("    mstatus=%h mie=%h mip=%h mtvec=%h",
            dut.u_pcu.u_csr_trap.mstatus_o,
            dut.u_pcu.u_csr_trap.mie_o,
            dut.u_pcu.u_csr_trap.mip_o,
                        dut.u_pcu.u_csr_trap.mtvec_o);
        check(uart_count == 0, "UART vazio antes do IRQ");

        // Força mtip
        force_mtip = 1;
        repeat(50) @(posedge clk);
        @(negedge clk);

        $display("  Depois do IRQ: PC=%h, uart_count=%0d", dbg_pcu_pc, uart_count);
        $display("    mstatus=%h mie=%h mip=%h mtvec=%h",
            dut.u_pcu.u_csr_trap.mstatus_o,
            dut.u_pcu.u_csr_trap.mie_o,
            dut.u_pcu.u_csr_trap.mip_o,
                        dut.u_pcu.u_csr_trap.mtvec_o);
        if (uart_count > 0) $display("  UART[0]=%c (0x%h)", uart_buf[0], uart_buf[0]);

        check(uart_count >= 1, "UART recebeu 1 byte após IRQ");
        check(uart_buf[0] == 8'h49, "UART[0] = 'I' (handler)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED — IRQ funciona");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
