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
module tb_irq_simples;
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
    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:511];

    // Captura simples: qualquer write no dmem é registrado
    reg        cap_valid;
    reg [63:0] cap_addr, cap_data;

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

    // Memória simulada: qualquer write é capturado, qualquer read retorna 0
    always @(posedge clk) begin
        dmem_ready <= 0;
        cap_valid  <= 0;
        if (dmem_req) begin
            if (dmem_we) begin
                cap_valid <= 1;
                cap_addr  <= dmem_addr;
                cap_data  <= dmem_wdata;
                dmem[0] <= dmem[0];   // noop
            end else begin
                dmem_rdata <= 0;
            end
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
        for (i=0; i<256; i=i+1) imem[i] = 32'h00000013;
        for (i=0; i<512; i=i+1) dmem[i] = 0;
        force_mtip = 0; cap_valid = 0;
        vmem_rdata = 0; vmem_ready = 0;
        pte_rdata = 0; pte_ready = 0;
        mmio_rdata = 0; mmio_ready = 0;
        dmem_rdata = 0; dmem_ready = 0;

        // Programa:
        //  0x00: lui  x6, 0x0
        //  0x04: addi x6, x6, 0x40
        //  0x08: csrw mtvec, x6
        //  0x0C: addi x5, x0, 0x80
        //  0x10: csrrs x0, mie, x5
        //  0x14: addi x5, x0, 8
        //  0x18: csrrs x0, mstatus, x5
        //  0x1C: jal x0, 0
        imem[0] = 32'h00000337;
        imem[1] = 32'h04030313;
        imem[2] = 32'h30531073;
        imem[3] = 32'h08000293;
        imem[4] = 32'h3042A073;
        imem[5] = 32'h00800293;
        imem[6] = 32'h3002A073;
        imem[7] = 32'h0000006F;

        // Handler 0x40:
        //  0x40: addi x11, x0, 0x49
        //  0x44: sw x11, 0(x0)     ; addr=0, data=0x49
        //  0x48: mret
        imem[16] = 32'h04900593;
        imem[17] = 32'h00B02023;  // sw x11, 0(x0) = 0x00B02023
        imem[18] = 32'h30200073;

        #20 rst_n = 1;

        $display("========================================");
        $display("  IRQ mínimo (sem UART)");
        $display("========================================");

        // Espera PCU configurar
        repeat(60) @(posedge clk);
        @(negedge clk);

        $display("  Antes: PC=%h", dbg_pcu_pc);
        $display("    mie=%h mip=%h mstatus=%h mtvec=%h",
            dut.u_pcu.u_csr_trap.mie_o,
            dut.u_pcu.u_csr_trap.mip_o,
            dut.u_pcu.u_csr_trap.mstatus_o,
            dut.u_pcu.u_csr_trap.mtvec_o);

        // Força IRQ
        force_mtip = 1;
        repeat(60) @(posedge clk);
        @(negedge clk);

        $display("  Depois: PC=%h", dbg_pcu_pc);
        $display("    mie=%h mip=%h mstatus=%h",
            dut.u_pcu.u_csr_trap.mie_o,
            dut.u_pcu.u_csr_trap.mip_o,
            dut.u_pcu.u_csr_trap.mstatus_o);

        // Se o handler executou, PC passou de 0x40
        check(dbg_pcu_pc >= 64'h40, "PC chegou no handler (>= 0x40)");
        check(cap_valid === 1, "Algum store foi executado");
        check(cap_data === 64'h49, "Store do handler = 'I' (0x49)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED — IRQ + handler funcionam");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
