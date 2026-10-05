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
module tb_trans;
    reg clk=0, rst_n=0;
    integer i, t_run=0, t_pass=0, t_fail=0;
    reg [4:0] dbg_rs=0;
    wire [63:0] dbg_arch_rd, dbg_pcu_pc, dbg_satp;
    wire dbg_satp_en;
    wire [63:0] imem_pc;
    wire [6*32-1:0] imem_instr;
    wire dram_req, dram_we;
    wire [63:0] dram_addr;
    wire [511:0] dram_wdata;
    reg [511:0] dram_rdata;
    reg dram_ready;
    wire mmio_req, mmio_we;
    wire [63:0] mmio_addr, mmio_wdata;
    reg [63:0] mmio_rdata;
    reg mmio_ready;

    reg [31:0] imem [0:1023];
    reg [511:0] dmem [0:8191];        // 512 KB DRAM (linhas de 64 bytes)
    reg [3:0] dram_delay;

    top_pace_mem #(.HART_ID(0)) dut (
        .clk(clk), .rst_n(rst_n), .i_instr_count(4'd1),
        .imem_pc(imem_pc), .imem_instr(imem_instr),
        .dram_req(dram_req), .dram_we(dram_we),
        .dram_addr(dram_addr), .dram_wdata(dram_wdata),
        .dram_rdata(dram_rdata), .dram_ready(dram_ready),
        .mmio_req(mmio_req), .mmio_we(mmio_we),
        .mmio_addr(mmio_addr), .mmio_wdata(mmio_wdata),
        .mmio_rdata(mmio_rdata), .mmio_ready(mmio_ready),
        .i_mtip(1'b0), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en)
    );

    always #5 clk = ~clk;

    wire [31:0] i0 = imem[imem_pc[11:2] + 0];
    wire [31:0] i1 = imem[imem_pc[11:2] + 1];
    wire [31:0] i2 = imem[imem_pc[11:2] + 2];
    wire [31:0] i3 = imem[imem_pc[11:2] + 3];
    wire [31:0] i4 = imem[imem_pc[11:2] + 4];
    wire [31:0] i5 = imem[imem_pc[11:2] + 5];
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    // DRAM ~8 ciclos
    always @(posedge clk) begin
        dram_ready <= 0;
        if (dram_req && dram_delay == 0) dram_delay <= 8;
        else if (dram_delay > 0) begin
            dram_delay <= dram_delay - 1;
            if (dram_delay == 1) begin
                if (dram_we) dmem[dram_addr[14:6]][dram_addr[5:3]*64 +: 64] <= dram_wdata[63:0];
                else         dram_rdata <= dmem[dram_addr[14:6]];
                dram_ready <= 1;
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

    // Trace do MMU + L1d + walker
    reg [7:0] last_pc = 8'hFF;
    always @(posedge clk) begin
        if (rst_n) begin
            // PC muda
            if (imem_pc[11:2] !== last_pc) begin
                $display("t=%0t PC=%h priv=%b satp_en=%b",
                    $time, imem_pc, dut.priv_mode, dut.satp_en_w);
                last_pc <= imem_pc[11:2];
            end
            // Walker req
            if (dut.u_l1d.pte_req || dut.u_l1d.pte_ready)
                $display("t=%0t WALKER: pte_req=%b pte_addr=%h pte_rdata=%h pte_ready=%b",
                    $time, dut.u_l1d.pte_req, dut.u_l1d.pte_addr,
                    dut.u_l1d.pte_rdata, dut.u_l1d.pte_ready);
            // MC acesso
            if (dut.mc_req)
                $display("t=%0t MC: req=%b we=%b addr=%h wdata=%h rdata=%h ready=%b",
                    $time, dut.mc_req, dut.mc_we, dut.mc_addr, dut.mc_wdata,
                    dut.mc_rdata, dut.mc_ready);
        end
    end

    initial begin

        for (i=0; i<1024; i=i+1) imem[i] = 32'h00000013;
        for (i=0; i<8192; i=i+1) dmem[i] = 512'd0;
        mmio_rdata = 0; mmio_ready = 0;
        dram_rdata = 512'd0; dram_ready = 0; dram_delay = 0;

        // ===== Page tables em PA 0x1000, 0x2000, 0x3000 =====
        // Root @ 0x1000 (line 0x1000>>6 = 0x40): PTE ptr -> PT1 (PPN=2)
        dmem[64'h1000 >> 6][63:0] = 64'h0000_0000_0000_0801;
        // PT1 @ 0x2000 (line 0x80): PTE ptr -> PT0 (PPN=3)
        dmem[64'h2000 >> 6][63:0] = 64'h0000_0000_0000_0C01;
        // PT0 @ 0x3000 (line 0xC0): leaf -> PA 0x5000 (PPN=5, R|W|A|D|V)
        dmem[64'h3000 >> 6][63:0] = 64'h0000_0000_0000_14C7;

        // Dado em PA 0x5000 (line 0x140) = 0xDEADCAFE
        dmem[64'h5000 >> 6][63:0] = 64'hDEAD_CAFE;

        // ===== Programa =====
        //  M-mode: monta page tables na memória
        imem[0]  = 32'h000010B7;   // lui  x1, 0x1        # x1 = 0x1000
        imem[1]  = 32'h80110113;   // addi x2, x0, -0x7FF # x2 = 0xFFFF800000000801? no, wrong
        // corrigindo: queremos x2 = 0x801
        imem[1]  = 32'h80100113;   // addi x2, x0, -0x7FF → x2 = 0xFFFFFFFFFFFFF801 (sign ext)
        // melhor usar lui + addi:
        imem[1]  = 32'h00000137;   // lui  x2, 0x0
        imem[2]  = 32'h80110113;   // addi x2, x2, -0x7FF  → x2 = -0x7FF = 0xFFFFFFFFFFFFF801
        // hmm, PTE precisa ter só bits baixos. 0x801 = PPN=2 (bits 10:12) + V=1
        // 0x801 = 1000 0000 0001 → bit 11 = 1, bit 0 = 1. Correto: PPN=2 → 2<<10 = 0x800, +V=1
        // Vamos por: x2 = 0x800 | 0x1 = 0x801
        imem[1]  = 32'h80000137;   // lui  x2, 0x80000 → x2 = 0x80000000 (bit 31)
        imem[2]  = 32'h00B10113;   // slli x2, x2, 0xC? não.
        // Simplifica: usa LUI com valor pequeno
        imem[1]  = 32'h00000137;   // lui  x2, 0x0
        imem[2]  = 32'h80100113;   // addi x2, x0, 0x801 (mas addi só 12 bits signed)
        // 0x801 como signed 12-bit = -2047. Encoding: imm[11:0]=0x801
        // Para simplicidade: escreve direto via lw de memória ou aceita
        // Vou usar LUI + addi pra construir 0x801:
        imem[1]  = 32'h00000137;   // lui x2, 0 (x2 = 0)
        imem[2]  = 32'h80110113;   // addi x2, x2, -0x7FF = 0xFFFFFFFFFFFFF801
        // Isso vai como PTE. Bits baixos: V=1, R=0... PPN é 0x3FF...
        // Não vai funcionar.

        // Approach correto: usar lui x2, 0x1 → x2 = 0x1000. addi -0x7FF → x2 = 0x801. Não.
        // lui x2, 0x1 = 0x1000. addi -0x7FF = 0x801. ✓
        imem[1]  = 32'h00001137;   // lui x2, 0x1 → x2 = 0x1000
        imem[2]  = 32'h80110113;   // addi x2, x2, -0x7FF → x2 = 0x1000 - 0x7FF = 0x801 ✓

        imem[3]  = 32'h0020A023;   // sw x2, 0(x1)   # root[0] = 0x801 (PTE ptr → PT1)

        imem[4]  = 32'h000020B7;   // lui x1, 0x2    # x1 = 0x2000
        imem[5]  = 32'h00002137;   // lui x2, 0x2    # x2 = 0x2000
        imem[6]  = 32'h80110113;   // addi x2, x2, -0x7FF → x2 = 0x2000 - 0x7FF = 0xC01 ✓
        imem[7]  = 32'h0020A023;   // sw x2, 0(x1)   # PT1[0] = 0xC01

        imem[8]  = 32'h000030B7;   // lui x1, 0x3    # x1 = 0x3000
        imem[9]  = 32'h00003137;   // lui x2, 0x3
        // queremos x2 = 0x14C7. lui 0x1 → 0x1000. addi 0x4C7 = +1223
        imem[10] = 32'h00001137;   // lui x2, 0x1
        imem[11] = 32'h4C710113;   // addi x2, x2, 0x4C7 → x2 = 0x14C7 ✓
        imem[12] = 32'h0020A023;   // sw x2, 0(x1)   # PT0[0] = 0x14C7

        // Ativa Sv39: satp = 0x80000000_00000001
        imem[13] = 32'h000022B7;   // lui x5, 0x2
        imem[14] = 32'h000022B7;   // (NOP)

        // Approach: satp = (8<<60) | (PPN=1)
        imem[13] = 32'h800002B7;   // lui x5, 0x80000 → x5 = 0x80000000
        imem[14] = 32'h02029293;   // slli x5, x5, 0x20 → x5 = 0x8000000000000000
        imem[15] = 32'h00128293;   // addi x5, x5, 1 → x5 = 0x8000000000000001
        imem[16] = 32'h18029073;   // csrw satp, x5

        // mstatus: MPP=S (01) + MPIE
        imem[17] = 32'h00000337;   // lui x6, 0x0
        imem[18] = 32'h08100313;   // addi x6, x0, 0x81 → x6 = 0x81
        // 0x81 = MPIE(bit7) + SPP? não. Pra MPP=S(01) + MPIE=1: bits 12:11=01, bit 7=1
        // = 0x800 + 0x80 = 0x880
        imem[18] = 32'h88000313;   // addi x6, x0, -0x780 = 0xFFFFFFFFFFFFF880 (sign ext)
        // Não. addi imm 12-bit signed, max 0x7FF.
        // 0x880 não cabe. Divide: lui 0x0 + addi 0x7FF + addi 0x81 = 0x880
        imem[18] = 32'h7FF00313;   // addi x6, x0, 0x7FF → x6 = 0x7FF
        imem[19] = 32'h08130313;   // addi x6, x6, 0x81 → x6 = 0x7FF + 0x81 = 0x880 ✓
        imem[20] = 32'h30031073;   // csrw mstatus, x6

        // mepc = 0x100
        imem[21] = 32'h10000393;   // addi x7, x0, 0x100 → x7 = 0x100
        imem[22] = 32'h34139073;   // csrw mepc, x7

        // mret → S-mode
        imem[23] = 32'h30200073;

        // S-mode entry @ 0x100 (imem[64])
        //  0x100: lw x8, 0(x0)   # VA=0 → PA=0x5000
        imem[64] = 32'h00002403;
        //  0x104: addi x9, x0, 0x55
        imem[65] = 32'h05500493;
        //  0x108: jal x0, 0
        imem[66] = 32'h0000006F;

        #20 rst_n = 1;

        $display("========================================");
        $display("  M-mode -> S-mode com Sv39 (top_pace_mem)");
        $display("========================================");

        repeat(500) @(posedge clk);
        @(negedge clk);

        $display("  PC=%h satp=%h satp_en=%b", dbg_pcu_pc, dbg_satp, dbg_satp_en);

        dbg_rs = 5'd8; #1;
        $display("  x8 = %h (exp DEADCAFE)", dbg_arch_rd);
        check(dbg_arch_rd === 64'hDEAD_CAFE, "S-mode LOAD via VA traduzido");

        dbg_rs = 5'd9; #1;
        check(dbg_arch_rd === 64'h55, "S-mode executou addi (x9=0x55)");
        check(dbg_satp_en === 1'b1, "satp_enable ativo (Sv39)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED — M→S + Sv39");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
