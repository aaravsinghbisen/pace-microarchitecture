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
// L1d: 32KB, 4-way, 128 sets, 64B/line, write-through, non-inclusive
// Two output paths:
//   - L2 path    : cacheable (DRAM) accesses
//   - MMIO path  : uncached accesses (addr < 0x8000_0000)
module l1d #(
    parameter ADDR_W  = 64,
    parameter DATA_W  = 64,
    parameter SETS    = 128,
    parameter WAYS    = 4,
    parameter LINE_WORDS = 8
)(
    input  wire clk, rst_n,
    input  wire                  cpu_req,
    input  wire                  cpu_we,
    input  wire [ADDR_W-1:0]     cpu_addr,
    input  wire [DATA_W-1:0]     cpu_wdata,
    output reg  [DATA_W-1:0]     cpu_rdata,
    output reg                   cpu_ready,

    output reg                   l2_req,
    output reg                   l2_we,
    output reg  [ADDR_W-1:0]     l2_addr,
    output reg  [DATA_W-1:0]     l2_wdata,
    input  wire [LINE_WORDS*DATA_W-1:0] l2_rdata,
    input  wire                  l2_ready,

    output reg                   mmio_req,
    output reg                   mmio_we,
    output reg  [ADDR_W-1:0]     mmio_addr,
    output reg  [DATA_W-1:0]     mmio_wdata,
    input  wire [DATA_W-1:0]     mmio_rdata,
    input  wire                  mmio_ready,

    input  wire                  snp_valid,
    input  wire                  snp_we,
    input  wire [ADDR_W-1:0]     snp_addr,
    input  wire [DATA_W-1:0]     snp_wdata
);
    localparam WORD_BYTES = DATA_W/8;
    localparam LINE_BYTES = LINE_WORDS * WORD_BYTES;
    localparam OFF_W      = $clog2(LINE_BYTES);
    localparam IDX_W      = $clog2(SETS);
    localparam TAG_W      = ADDR_W - OFF_W - IDX_W;
    localparam LINE_W     = LINE_WORDS * DATA_W;
    localparam WAY_W      = $clog2(WAYS);

    reg [LINE_W-1:0] data_arr  [0:SETS-1][0:WAYS-1];
    reg [TAG_W-1:0]  tag_arr   [0:SETS-1][0:WAYS-1];
    reg              valid_arr [0:SETS-1][0:WAYS-1];
    reg [7:0]        age_arr   [0:SETS-1][0:WAYS-1];

    wire [OFF_W-1:0] offset   = cpu_addr[OFF_W-1:0];
    wire [IDX_W-1:0] index    = cpu_addr[OFF_W+IDX_W-1:OFF_W];
    wire [TAG_W-1:0] tag      = cpu_addr[ADDR_W-1:OFF_W+IDX_W];
    wire [2:0]       word_off = offset[OFF_W-1:3];

    // MMIO detection: any address not in DRAM region (top bit = 0)
    wire is_mmio = !(cpu_addr[63:31] != 0 || cpu_addr[31] == 1'b1);
    // Simpler: MMIO if top 33 bits are not all-zero-prefixed-with-1-at-31
    // DRAM is 0x8000_0000..0xFFFF_FFFF_FFFF_FFFF
    wire dram_region = (cpu_addr[63:32] != 0) || (cpu_addr[31:28] >= 4'h8) || (cpu_addr[31:28] == 4'h0);
    wire is_mmio_x = !dram_region;

    wire [WAYS-1:0] hit_vec;
    genvar gi;
    generate
        for (gi = 0; gi < WAYS; gi = gi + 1) begin : g_hit
            assign hit_vec[gi] = valid_arr[index][gi] && (tag_arr[index][gi] == tag);
        end
    endgenerate
    wire hit = |hit_vec;

    reg [WAY_W-1:0] hit_way;
    integer hw;
    always @(*) begin
        hit_way = 0;
        for (hw = 0; hw < WAYS; hw = hw + 1)
            if (hit_vec[hw]) hit_way = hw[WAY_W-1:0];
    end

    reg [WAY_W-1:0] victim_way;
    reg             victim_is_invalid;
    integer vi;
    always @(*) begin
        victim_way        = 0;
        victim_is_invalid = 0;
        for (vi = 0; vi < WAYS; vi = vi + 1) begin
            if (!valid_arr[index][vi]) begin
                victim_way        = vi[WAY_W-1:0];
                victim_is_invalid = 1;
            end
        end
        if (!victim_is_invalid) begin
            victim_way = 0;
            for (vi = 1; vi < WAYS; vi = vi + 1)
                if (age_arr[index][vi] > age_arr[index][victim_way])
                    victim_way = vi[WAY_W-1:0];
        end
    end

    localparam S_IDLE     = 3'd0;
    localparam S_MEM_REQ  = 3'd1;
    localparam S_MEM_WAIT = 3'd2;
    localparam S_FILL     = 3'd3;
    localparam S_MMIO     = 3'd4;

    reg [2:0] state;
    reg       fill_was_write;
    reg       rsp_done;   // set when a response completed; cleared when cpu_req drops

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            cpu_ready <= 0;
            cpu_rdata <= 0;
            l2_req    <= 0;  l2_we    <= 0;  l2_addr  <= 0;  l2_wdata <= 0;
            mmio_req  <= 0;  mmio_we  <= 0;  mmio_addr<= 0;  mmio_wdata <= 0;
            fill_was_write <= 0;
            rsp_done  <= 0;
            for (integer s = 0; s < SETS; s = s + 1)
                for (integer w = 0; w < WAYS; w = w + 1) begin
                    valid_arr[s][w] <= 0; tag_arr[s][w] <= 0;
                    age_arr[s][w]   <= 0; data_arr[s][w] <= 0;
                end
        end else begin
            // Snoop
            if (snp_valid && snp_we) begin
                for (integer sw = 0; sw < WAYS; sw = sw + 1) begin
                    if (valid_arr[snp_addr[OFF_W+IDX_W-1:OFF_W]][sw] &&
                        tag_arr  [snp_addr[OFF_W+IDX_W-1:OFF_W]][sw] ==
                        snp_addr [ADDR_W-1:OFF_W+IDX_W]) begin
                        data_arr[snp_addr[OFF_W+IDX_W-1:OFF_W]][sw]
                          [snp_addr[OFF_W-1:3]*DATA_W +: DATA_W] <= snp_wdata;
                    end
                end
            end

            // Clear ready+rsp_done when master drops request
            if (!cpu_req) begin
                cpu_ready <= 0;
                rsp_done  <= 0;
            end

            case (state)
                S_IDLE: begin
                    l2_req    <= 0; l2_we <= 0;
                    mmio_req  <= 0; mmio_we <= 0;

                    // Only accept a NEW request if we haven't already completed one
                    if (cpu_req && !rsp_done) begin
                        if (is_mmio_x) begin
                            mmio_req   <= 1;
                            mmio_we    <= cpu_we;
                            mmio_addr  <= cpu_addr;
                            mmio_wdata <= cpu_wdata;
                            state      <= S_MMIO;
                        end else if (hit) begin
                            if (cpu_we) begin
                                data_arr[index][hit_way]
                                  [word_off*DATA_W +: DATA_W] <= cpu_wdata;
                                l2_req   <= 1; l2_we <= 1;
                                l2_addr  <= cpu_addr;
                                l2_wdata <= cpu_wdata;
                                cpu_ready <= 1;
                                rsp_done  <= 1;
                                age_arr[index][hit_way] <= 0;
                            end else begin
                                cpu_rdata <= data_arr[index][hit_way]
                                               [word_off*DATA_W +: DATA_W];
                                cpu_ready <= 1;
                                rsp_done  <= 1;
                                age_arr[index][hit_way] <= 0;
                            end
                        end else begin
                            state          <= S_MEM_REQ;
                            l2_req         <= 1;
                            l2_we          <= 0;
                            l2_addr        <= {cpu_addr[ADDR_W-1:OFF_W], {OFF_W{1'b0}}};
                            fill_was_write <= cpu_we;
                        end
                    end
                end

                S_MEM_REQ: state <= S_MEM_WAIT;

                S_MEM_WAIT: if (l2_ready) begin l2_req <= 0; state <= S_FILL; end

                S_FILL: begin
                    data_arr[index][victim_way]   <= l2_rdata;
                    tag_arr [index][victim_way]   <= tag;
                    valid_arr[index][victim_way] <= 1'b1;
                    age_arr[index][victim_way]   <= 8'd0;

                    if (fill_was_write) begin
                        data_arr[index][victim_way]
                          [word_off*DATA_W +: DATA_W] <= cpu_wdata;
                        l2_req   <= 1; l2_we <= 1;
                        l2_addr  <= cpu_addr;
                        l2_wdata <= cpu_wdata;
                        cpu_ready <= 1;
                        rsp_done  <= 1;
                        state    <= S_IDLE;
                    end else begin
                        cpu_rdata <= l2_rdata[word_off*DATA_W +: DATA_W];
                        cpu_ready <= 1;
                        rsp_done  <= 1;
                        state     <= S_IDLE;
                    end
                end

                S_MMIO: begin
                    if (mmio_ready) begin
                        mmio_req  <= 0;
                        cpu_rdata <= mmio_rdata;
                        cpu_ready <= 1;
                        rsp_done  <= 1;
                        state     <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
