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
module fetch_buffer (
    input  wire clk, rst_n,
    input  wire [31:0] in_instr,
    input  wire        in_valid,
    input  wire        flush,
    input  wire [63:0] flush_pc,
    input  wire [2:0]  consume_count,
    output wire [63:0] next_fetch_pc,
    output reg  [6*32-1:0] out_instrs,
    output reg  [63:0]     out_pc,
    output reg             out_valid
);
    reg [31:0] b0,b1,b2,b3,b4,b5,b6,b7;
    reg [3:0]  count;
    reg [63:0] head_pc;       // PC da entrada buf[0]
    reg [63:0] fetch_pc;      // PC da próxima instr a buscar

    wire [3:0] cnt_after = (count >= {1'b0, consume_count}) ?
                            (count - {1'b0, consume_count}) : 4'd0;
    wire can_fill = in_valid && (cnt_after < 4'd8);

    reg [31:0] n0, n1, n2, n3, n4, n5, n6, n7;
    always @(*) begin
        case (consume_count)
            3'd0: begin n0=b0; n1=b1; n2=b2; n3=b3; n4=b4; n5=b5; n6=b6; n7=b7; end
            3'd1: begin n0=b1; n1=b2; n2=b3; n3=b4; n4=b5; n5=b6; n6=b7; n7=32'h13; end
            3'd2: begin n0=b2; n1=b3; n2=b4; n3=b5; n4=b6; n5=b7; n6=32'h13; n7=32'h13; end
            3'd3: begin n0=b3; n1=b4; n2=b5; n3=b6; n4=b7; n5=32'h13; n6=32'h13; n7=32'h13; end
            3'd4: begin n0=b4; n1=b5; n2=b6; n3=b7; n4=32'h13; n5=32'h13; n6=32'h13; n7=32'h13; end
            3'd5: begin n0=b5; n1=b6; n2=b7; n3=32'h13; n4=32'h13; n5=32'h13; n6=32'h13; n7=32'h13; end
            3'd6: begin n0=b6; n1=b7; n2=32'h13; n3=32'h13; n4=32'h13; n5=32'h13; n6=32'h13; n7=32'h13; end
            default: begin n0=b0; n1=b1; n2=b2; n3=b3; n4=b4; n5=b5; n6=b6; n7=b7; end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            b0<=32'h13; b1<=32'h13; b2<=32'h13; b3<=32'h13;
            b4<=32'h13; b5<=32'h13; b6<=32'h13; b7<=32'h13;
            count <= 0;
            head_pc  <= 0;
            fetch_pc <= 0;
        end else if (flush) begin
            b0<=32'h13; b1<=32'h13; b2<=32'h13; b3<=32'h13;
            b4<=32'h13; b5<=32'h13; b6<=32'h13; b7<=32'h13;
            count    <= 0;
            head_pc  <= flush_pc;
            fetch_pc <= flush_pc;
        end else begin
            reg [31:0] w0, w1, w2, w3, w4, w5, w6, w7;
            w0 = n0; w1 = n1; w2 = n2; w3 = n3;
            w4 = n4; w5 = n5; w6 = n6; w7 = n7;

            if (can_fill) begin
                case (cnt_after)
                    4'd0: w0 = in_instr;
                    4'd1: w1 = in_instr;
                    4'd2: w2 = in_instr;
                    4'd3: w3 = in_instr;
                    4'd4: w4 = in_instr;
                    4'd5: w5 = in_instr;
                    4'd6: w6 = in_instr;
                    4'd7: w7 = in_instr;
                endcase
            end

            b0<=w0; b1<=w1; b2<=w2; b3<=w3;
            b4<=w4; b5<=w5; b6<=w6; b7<=w7;

            count   <= can_fill ? (cnt_after + 1) : cnt_after;
            head_pc <= head_pc + {61'b0, consume_count} * 4;
            if (can_fill)
                fetch_pc <= fetch_pc + 4;
        end
    end

    assign next_fetch_pc = fetch_pc;

    always @(*) begin
        out_instrs[0*32 +: 32] = b0;
        out_instrs[1*32 +: 32] = b1;
        out_instrs[2*32 +: 32] = b2;
        out_instrs[3*32 +: 32] = b3;
        out_instrs[4*32 +: 32] = b4;
        out_instrs[5*32 +: 32] = b5;
        out_pc    = head_pc;
        out_valid = (count >= 6);
    end
endmodule
