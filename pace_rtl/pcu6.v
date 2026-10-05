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
// PCU 6-wide: 6 lanes em paralelo, com forwarding intra-ciclo.
// Suporta R-type e I-type (ALU). FPU também via is_fpu.
// Quando encontra LOAD/STORE/BRANCH/CSR/SYSTEM numa das lanes, processa apenas
// as lanes anteriores neste ciclo, e o resto fica pra próximo.
module pcu6 (
    input  wire        clk, rst_n,
    input  wire        stall,
    input  wire        fetch_stall,
    input  wire [3:0]  shdw_wr_ready,       // espaços livres no shadow RF
    // 6 instruções por ciclo (192 bits)
    input  wire [6*32-1:0] instr_in,
    output wire [63:0] pc_out,
    // Saída pro shadow RF
    output wire [6-1:0]        shadow_we,
    output wire [6*5-1:0]      shadow_rd,
    output wire [6*64-1:0]     shadow_data,
    output wire [5:0]          num_writes,  // quantas escritas válidas
    // Controle de fluxo (redirecionamento)
    output wire        br_valid, br_taken,
    output wire [63:0] br_target,
    input  wire        redirect_valid,
    input  wire [63:0] redirect_pc,
    // Extensões (M-Core, CSRs)
    input  wire        ext_wr_en,
    input  wire [4:0]  ext_wr_addr,
    input  wire [63:0] ext_wr_data,
    output wire [1:0]  dbg_priv
);
    assign dbg_priv = 2'b11;

    // ============ Program Counter ============
    reg [63:0] pc;
    assign pc_out = pc;

    // ============ 6 decoders em paralelo ============
    wire [6*7-1:0]  d_opcode, d_funct7;
    wire [6*3-1:0]  d_funct3;
    wire [6*5-1:0]  d_rd, d_rs1, d_rs2;
    wire [6*64-1:0] d_imm;
    wire [6*3-1:0]  d_format;
    wire [6-1:0]    d_is_system, d_is_ecall, d_is_ebreak;
    wire [6-1:0]    d_is_mret, d_is_sret, d_is_csr;
    wire [6*12-1:0] d_csr_addr;

    genvar gi;
    generate
        for (gi = 0; gi < 6; gi = gi + 1) begin : g_dec
            decoder u_dec (
                .instr(instr_in[gi*32 +: 32]),
                .opcode(d_opcode[gi*7 +: 7]),
                .rd(d_rd[gi*5 +: 5]),
                .rs1(d_rs1[gi*5 +: 5]),
                .rs2(d_rs2[gi*5 +: 5]),
                .funct3(d_funct3[gi*3 +: 3]),
                .funct7(d_funct7[gi*7 +: 7]),
                .imm(d_imm[gi*64 +: 64]),
                .format(d_format[gi*3 +: 3]),
                .is_system(d_is_system[gi]),
                .is_ecall(d_is_ecall[gi]),
                .is_ebreak(d_is_ebreak[gi]),
                .is_mret(d_is_mret[gi]),
                .is_sret(d_is_sret[gi]),
                .is_csr(d_is_csr[gi]),
                .csr_addr(d_csr_addr[gi*12 +: 12])
            );
        end
    endgenerate

    // ============ Classificação ============
    // ALU: opcode 0110011 (R) ou 0010011 (I) e não é FPU
    // FPU: opcode 1010011 (OP-FP)
    // Mem: 0000011 (LOAD), 0100011 (STORE)
    // Branch: 1100011 (BRANCH), 1101111 (JAL), 1100111 (JALR)
    // System: 1110011 (CSR/mret/ecall)
    wire [6-1:0] is_alu, is_fpu, is_mem, is_br, is_sys;

    generate
        for (gi = 0; gi < 6; gi = gi + 1) begin : g_cls
            wire [6:0] opc = d_opcode[gi*7 +: 7];
            assign is_alu[gi] = (opc == 7'b0110011) || (opc == 7'b0010011);
            assign is_fpu[gi] = (opc == 7'b1010011);   // OP-FP
            assign is_mem[gi] = (opc == 7'b0000011) || (opc == 7'b0100011);
            assign is_br [gi] = (opc == 7'b1100011) || (opc == 7'b1101111) || (opc == 7'b1100111);
            assign is_sys[gi] = d_is_system[gi];
        end
    endgenerate

    // Escrevem no regfile? Só R-type, I-type e FPU (por enquanto)
    wire [6-1:0] wr_this_lane;
    generate
        for (gi = 0; gi < 6; gi = gi + 1) begin : g_wr
            assign wr_this_lane[gi] = (is_alu[gi] || is_fpu[gi]) &&
                                      (d_rd[gi*5 +: 5] != 5'd0);
        end
    endgenerate

    // ============ PCU's local reg mirror ============
    reg [63:0] pcu_regs [0:31];

    // rs1/rs2 values for each lane (combinational read)
    wire [6*64-1:0] rs1_val, rs2_val;
    generate
        for (gi = 0; gi < 6; gi = gi + 1) begin : g_regread
            assign rs1_val[gi*64 +: 64] = (d_rs1[gi*5 +: 5] == 5'd0) ? 64'd0 : pcu_regs[d_rs1[gi*5 +: 5]];
            assign rs2_val[gi*64 +: 64] = (d_rs2[gi*5 +: 5] == 5'd0) ? 64'd0 : pcu_regs[d_rs2[gi*5 +: 5]];
        end
    endgenerate

    // ============ alu_cluster: execução paralela com forwarding ============
    wire [6-1:0]     cluster_we;
    wire [6*5-1:0]   cluster_rd;
    wire [6*64-1:0]  cluster_result;

    alu_cluster #(.N(6)) u_cluster (
        .clk(clk), .rst_n(rst_n),
        .in_valid(wr_this_lane),
        .in_is_fpu(is_fpu),
        .in_opcode(d_opcode),
        .in_funct3(d_funct3),
        .in_funct7(d_funct7),
        .in_rs1(d_rs1), .in_rs2(d_rs2), .in_rd(d_rd),
        .in_rs1_val(rs1_val), .in_rs2_val(rs2_val), .in_imm(d_imm),
        .out_we(cluster_we), .out_rd(cluster_rd),
        .out_result(cluster_result)
    );

    // ============ Saída pro shadow RF ============
    assign shadow_we   = wr_this_lane;
    assign shadow_rd   = d_rd;
    assign shadow_data = cluster_result;

    // Conta quantas escritas válidas, truncado por espaço no shadow
    wire [5:0] wr_count_raw;
    assign wr_count_raw = {5'b0, wr_this_lane[0]} + {5'b0, wr_this_lane[1]} +
                          {5'b0, wr_this_lane[2]} + {5'b0, wr_this_lane[3]} +
                          {5'b0, wr_this_lane[4]} + {5'b0, wr_this_lane[5]};

    // Quantas lanes executaram até a primeira não-ALU/FPU
    // (para saber onde parar)
    wire [2:0] first_non_alu_idx;
    assign first_non_alu_idx = (!wr_this_lane[0]) ? 3'd0 :
                               (!wr_this_lane[1]) ? 3'd1 :
                               (!wr_this_lane[2]) ? 3'd2 :
                               (!wr_this_lane[3]) ? 3'd3 :
                               (!wr_this_lane[4]) ? 3'd4 : 3'd5;

    // ============ Branches (combinacional na lane 0, por simplicidade) ============
    wire is_branch = is_br[0];
    reg br_cond;
    always @(*) begin
        case (d_funct3[0*3 +: 3])
            3'b000: br_cond = (rs1_val[0*64 +: 64] == rs2_val[0*64 +: 64]);
            3'b001: br_cond = (rs1_val[0*64 +: 64] != rs2_val[0*64 +: 64]);
            3'b100: br_cond = ($signed(rs1_val[0*64 +: 64]) <  $signed(rs2_val[0*64 +: 64]));
            3'b101: br_cond = ($signed(rs1_val[0*64 +: 64]) >= $signed(rs2_val[0*64 +: 64]));
            3'b110: br_cond = (rs1_val[0*64 +: 64] <  rs2_val[0*64 +: 64]);
            3'b111: br_cond = (rs1_val[0*64 +: 64] >= rs2_val[0*64 +: 64]);
            default: br_cond = 1'b0;
        endcase
    end

    wire is_jal  = (d_opcode[0*7 +: 7] == 7'b1101111);
    wire is_jalr = (d_opcode[0*7 +: 7] == 7'b1100111);
    wire [63:0] jalr_target = (rs1_val[0*64 +: 64] + d_imm[0*64 +: 64]) & ~64'd1;
    wire [63:0] ctrl_target = is_jalr ? jalr_target : (pc + d_imm[0*64 +: 64]);
    wire ctrl_taken = is_jal ? 1'b1 : (is_jalr ? 1'b1 : br_cond);

    assign br_valid  = is_br[0];
    assign br_taken  = is_branch && ctrl_taken;
    assign br_target = ctrl_target;

    // ============ Stall condition ============
    // Stall se: PCU stall, fetch_stall, shadow cheio pra esta rodada,
    //           ou a lane 0 é uma operação não-ALU que precisa ser processada pelo M-Core/B-Core/CSR
    wire lane0_is_special = is_mem[0] || is_br[0] || is_sys[0];
    wire need_more_space = (wr_count_raw > {2'b0, shdw_wr_ready});
    wire pcu_stall_now = stall || fetch_stall || need_more_space;

    // ============ Controle de PC ============
    reg branch_pending;
    reg wait_load;

    wire is_load_0 = (d_opcode[0*7 +: 7] == 7'b0000011);
    wire is_mret_0 = d_is_mret[0];
    wire is_sret_0 = d_is_sret[0];

    // Quantas instruções efetivamente avançam o PC neste ciclo
    wire [2:0] advance_count;
    assign advance_count = wr_this_lane[5] ? 3'd6 :
                           wr_this_lane[4] ? 3'd5 :
                           wr_this_lane[3] ? 3'd4 :
                           wr_this_lane[2] ? 3'd3 :
                           wr_this_lane[1] ? 3'd2 :
                           wr_this_lane[0] ? 3'd1 : 3'd0;

    wire [63:0] pc_advance = {61'b0, advance_count} * 64'd4;

    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc <= 64'd0;
            branch_pending <= 0;
            wait_load <= 0;
            for (k = 0; k < 32; k = k + 1) pcu_regs[k] <= 64'd0;
        end else if (pcu_stall_now) begin
            if (ext_wr_en && ext_wr_addr != 5'd0)
                pcu_regs[ext_wr_addr] <= ext_wr_data;
        end else if (wait_load) begin
            if (ext_wr_en && ext_wr_addr != 5'd0)
                pcu_regs[ext_wr_addr] <= ext_wr_data;
            wait_load <= 0;
        end else if (branch_pending) begin
            if (redirect_valid) begin
                pc <= redirect_pc;
                branch_pending <= 0;
            end
        end else if (is_br[0]) begin
            branch_pending <= 1'b1;
        end else if (is_mret_0 || is_sret_0) begin
            pc <= pc + 4;
        end else begin
            // Atualiza pcu_regs com os resultados dos lanes
            for (k = 0; k < 6; k = k + 1) begin
                if (wr_this_lane[k] && (d_rd[k*5 +: 5] != 5'd0))
                    pcu_regs[d_rd[k*5 +: 5]] <= cluster_result[k*64 +: 64];
            end
            if (ext_wr_en && ext_wr_addr != 5'd0)
                pcu_regs[ext_wr_addr] <= ext_wr_data;

            // Avança o PC
            if (advance_count == 6) pc <= pc + 24;
            else                    pc <= pc + pc_advance;

            // Detecta LOAD na lane 0 → sinaliza pro M-Core
            if (is_load_0) wait_load <= 1;
        end
    end

    assign num_writes = wr_count_raw[3:0];
endmodule
