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
// Boot protocol: PACE + CLINT (MMIO) + UART (MMIO) + timer interrupt + trap.
// Prova que o core executa o que OpenSBI precisa no boot.
module tb_boot_proto;
    reg clk=0, rst_n=0;
    integer i, t_run=0, t_pass=0, t_fail=0;

    // Core
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

    // Sinais de IRQ do CLINT pro PCU
    wire clint_mtip;
    reg  tick_1hz;

    reg [31:0] imem [0:255];
    reg [63:0] dmem [0:4095];

    // UART buffer (recebe os bytes)
    reg [7:0] uart_buf [0:63];
    reg [5:0] uart_count;

    // CLINT (integrado aqui — usa clint.v existente)
    wire clint_req_w, clint_we_w;
    wire [63:0] clint_addr_w, clint_wdata_w;
    wire [63:0] clint_rdata_w;
    wire clint_ready_w;

    // ===== Instancia PACE =====
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
        .i_mtip(clint_mtip), .i_msip(1'b0), .i_meip(1'b0),
        .i_seip(1'b0), .i_stip(1'b0), .i_ssip(1'b0),
        .dbg_rs(dbg_rs), .dbg_arch_rd(dbg_arch_rd),
        .dbg_pcu_pc(dbg_pcu_pc), .dbg_satp(dbg_satp), .dbg_satp_en(dbg_satp_en)
    );

    // ===== CLINT =====
    clint u_clint (
        .clk(clk), .rst_n(rst_n),
        .req(clint_req_w), .we(clint_we_w),
        .addr(clint_addr_w), .wdata(clint_wdata_w),
        .rdata(clint_rdata_w), .ready(clint_ready_w),
        .tick(tick_1hz),
        .mtip(clint_mtip), .msip_o()
    );

    // ===== Roteamento MMIO no testbench =====
    // dmem_addr do MC → decodifica:
    //   0x0200_xxxx → CLINT
    //   0x1000_xxxx → UART
    //   resto       → DRAM
    wire is_clint = (dmem_addr[31:16] == 16'h0200);
    wire is_uart  = (dmem_addr[31:16] == 16'h1000);

    assign clint_req_w   = dmem_req && is_clint;
    assign clint_we_w    = dmem_we;
    assign clint_addr_w  = dmem_addr;
    assign clint_wdata_w = dmem_wdata;

    always #5 clk = ~clk;

    // DRAM/UART/CLINT response — com flag "pending" (processa 1x por request)
    reg pending;
    always @(posedge clk) begin
        dmem_ready <= 0;
        if (!dmem_req) begin
            pending <= 0;
        end else if (!pending) begin
            pending <= 1;
            if (!is_clint) begin
                if (is_uart && dmem_we) begin
                    uart_buf[uart_count] <= dmem_wdata[7:0];
                    uart_count <= uart_count + 1;
                end else begin
                    if (dmem_we) dmem[dmem_addr[13:3]] <= dmem_wdata;
                    else         dmem_rdata <= dmem[dmem_addr[13:3]];
                end
            end
            dmem_ready <= 1;
        end
    end

    // IMem
    wire [31:0] i0 = imem[imem_pc[9:2] + 0];
    wire [31:0] i1 = imem[imem_pc[9:2] + 1];
    wire [31:0] i2 = imem[imem_pc[9:2] + 2];
    wire [31:0] i3 = imem[imem_pc[9:2] + 3];
    wire [31:0] i4 = imem[imem_pc[9:2] + 4];
    wire [31:0] i5 = imem[imem_pc[9:2] + 5];
    assign imem_instr = {i5, i4, i3, i2, i1, i0};

    // Tick ~1 a cada 20 ciclos
    integer tick_cnt = 0;
    always @(posedge clk) begin
        tick_cnt <= tick_cnt + 1;
        if (tick_cnt >= 19) begin
            tick_cnt <= 0;
            tick_1hz <= 1;
        end else tick_1hz <= 0;
    end

    task check;
        input cond; input [255:0] name;
        begin
            t_run = t_run + 1;
            if (cond) begin t_pass = t_pass + 1; $display("[PASS] %0s", name); end
            else      begin t_fail = t_fail + 1; $display("[FAIL] %0s", name); end
        end
    endtask

    // Encodings
    // LUI  rd, imm20:  (imm20 << 12) | (rd << 7) | 0x37
    // ADDI rd, rs1, imm: (imm[11:0] << 20) | (rs1 << 15) | (rd << 7) | 0x13
    // SW   rs2, imm(rs1): imm[11:5]<<25 | rs2<<20 | rs1<<15 | 010<<12 | imm[4:0]<<7 | 0x23
    // CSRRS rd, csr, rs1: csr<<20 | rs1<<15 | 010<<12 | rd<<7 | 0x73
    // CSRRW rd, csr, rs1: csr<<20 | rs1<<15 | 001<<12 | rd<<7 | 0x73
    // MRET: 0x30200073

    always @(posedge clk) begin
        if (rst_n && (dmem_req || mmio_req || dut.u_mc.mem_req))
            $display("t=%0t dmem_req=%b we=%b addr=%h wdata=%h | mmio_req=%b addr=%h | mc_req=%b mc_addr=%h",
                $time, dmem_req, dmem_we, dmem_addr, dmem_wdata,
                mmio_req, mmio_addr, dut.u_mc.mem_req, dut.u_mc.mem_addr);
    end

    // TRACE ciclo-a-ciclo
    reg [7:0] last_pc_idx = 8'hFF;
    reg       last_mtip = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            // Mudança de PC
            if (dbg_pcu_pc[9:2] !== last_pc_idx) begin
                $display("t=%0t PC=%h instr=%h",
                    $time, dbg_pcu_pc, imem[dbg_pcu_pc[9:2]]);
                last_pc_idx <= dbg_pcu_pc[9:2];
            end
            // Escrita dmem/UART/CLINT
            if (dmem_req && dmem_we)
                $display("t=%0t WRITE addr=%h data=%h", $time, dmem_addr, dmem_wdata);
            // mtip
            if (clint_mtip !== last_mtip) begin
                $display("t=%0t MTIP %b -> %b", $time, last_mtip, clint_mtip);
                last_mtip <= clint_mtip;
            end
            // Trap
            if (dut.u_pcu.trap_taken_w)
                $display("t=%0t >>> TRAP taken <<< PC=%h", $time, dbg_pcu_pc);
        end
    end

    // Trace CLINT e trap
    always @(posedge clk) begin
        if (rst_n && (dmem_req || clint_mtip))
            $display("t=%0t req=%b we=%b addr=%h wdata=%h | mtime=%0d mtimecmp=%0d mtip=%b",
                $time, dmem_req, dmem_we, dmem_addr, dmem_wdata,
                u_clint.mtime, u_clint.mtimecmp, clint_mtip);
    end

    initial begin



        for (i=0; i<256; i=i+1) imem[i] = 32'h00000013;
        for (i=0; i<4096; i=i+1) dmem[i] = 0;
        for (i=0; i<64; i=i+1) uart_buf[i] = 0;
        uart_count = 0;
        vmem_rdata = 0; vmem_ready = 0;
        pte_rdata = 0; pte_ready = 0;
        mmio_rdata = 0; mmio_ready = 0;
        dmem_rdata = 0; dmem_ready = 0;

        // ============================================
        // PROGRAMA (equivalente ao que OpenSBI faz no boot)
        // ============================================
        // 0x00: lui  x1, 0x10000       # x1 = 0x10000000 (UART)
        imem[0] = 32'h100000B7;
        // 0x04: addi x2, x0, 0x50      # 'P'
        imem[1] = 32'h05000113;
        // 0x08: sw   x2, 0(x1)         # UART ← 'P'
        imem[2] = 32'h0020A023;

        // 0x0C: lui  x3, 0x02004        # x3 = 0x02004000
        imem[3] = 32'h020041B7;
        // 0x10: sw   x0, 4(x3)          # mtimecmp_hi = 0
        imem[4] = 32'h0001A223;
        // 0x14: addi x4, x0, 200        # mtimecmp_lo = 200
        imem[5] = 32'h03200213;
        // 0x18: sw   x4, 0(x3)
        imem[6] = 32'h0041A023;

        // 0x1C: lui  x6, 0x0
        imem[7] = 32'h00000337;
        // 0x20: addi x6, x6, 0x40
        imem[8] = 32'h04030313;
        // 0x24: csrw mtvec, x6
        imem[9] = 32'h30531073;
        // 0x28: addi x5, x0, 0x80
        imem[10] = 32'h08000293;
        // 0x2C: csrrs x0, mie, x5
        imem[11] = 32'h3042A073;
        // 0x30: addi x5, x0, 8
        imem[12] = 32'h00800293;
        // 0x34: csrrs x0, mstatus, x5
        imem[13] = 32'h3002A073;
        // 0x38: nop
        imem[14] = 32'h00000013;
        // 0x3C: jal x0, 0
        imem[15] = 32'h0000006F;

        // ============================================
        // Handler em 0x40
        // ============================================
        // 0x40: csrrs x10, mcause, x0
        imem[16] = 32'h34202573;
        // 0x44: addi x11, x0, 0x49     # 'I'
        imem[17] = 32'h04900593;
        // 0x48: sw x11, 0(x1)          # UART ← 'I'
        imem[18] = 32'h00B0A023;
        // 0x4C: mret
        imem[19] = 32'h30200073;
        // 0x50: jal x0, 0
        imem[20] = 32'h0000006F;

        #20 rst_n = 1;

        $display("========================================");
        $display("  PACE boot protocol test");
        $display("========================================");

        // Espera: UART 'P', depois timer, trap, UART 'I'
        repeat(2000) @(posedge clk);
        @(negedge clk);

        $display("  UART buffer: count=%0d", uart_count);
        if (uart_count > 0) $display("  UART[0] = %c (0x%h)", uart_buf[0], uart_buf[0]);
        if (uart_count > 1) $display("  UART[1] = %c (0x%h)", uart_buf[1], uart_buf[1]);
        $display("  PC final = %h", dbg_pcu_pc);

        // Testes
        check(uart_count >= 1, "UART recebeu ao menos 1 byte (MMIO write)");
        check(uart_buf[0] == 8'h50, "UART[0] = 'P' (boot escreveu)");

        // Se o CLINT disparou o timer, handler escreveu 'I'
        check(uart_count >= 2, "UART recebeu 2 bytes (boot + trap handler)");
        check(uart_buf[1] == 8'h49, "UART[1] = 'I' (trap handler escreveu)");

        $display("========================================");
        $display("  Tests: run=%0d pass=%0d fail=%0d", t_run, t_pass, t_fail);
        if (t_fail == 0) $display("  ALL PASSED — boot protocol funciona");
        else             $display("  SOME FAILED");
        $display("========================================");
        $finish;
    end
endmodule
