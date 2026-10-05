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
// ============================================================
// PACE Core — Master File (all RTL modules via `include)
// ============================================================
`include "decoder.v"
`include "rvc_decompress.v"
`include "alu_rv64.v"
`include "alu_cluster.v"
`include "fpu_arith.v"
`include "atomic_unit.v"
`include "v_alu.v"
`include "vector_rf.v"
`include "v_csr.v"
`include "pcu6_v.v"
`include "b_core.v"
`include "m_core.v"
`include "fetch_buffer.v"
`include "mem_queue.v"
`include "shadow_rf_multi.v"
`include "register_file_multi.v"
`include "ao_core_multi.v"
`include "csr_file.v"
`include "trap_unit.v"
`include "csr_trap_unit.v"
`include "boot_sequencer.v"
`include "perf_counters.v"
`include "runahead_ctrl.v"
`include "l1i.v"
`include "l1d.v"
`include "l2.v"
`include "l1i_mmu.v"
`include "l1d_mmu.v"
`include "sv39_walker.v"
`include "tlb_l1.v"
`include "tlb_l2.v"
`include "mmu_sv39.v"
`include "dmem_mmu_wrap.v"
`include "mesi_ctrl.v"
`include "top_pace_imem.v"
`include "top_pace_mem.v"
`include "pace_ext_a.v"
