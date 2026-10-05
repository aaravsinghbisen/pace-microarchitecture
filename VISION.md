# PACE — Vision

## What PACE Is

PACE (Pre-computing Antecipatory Core Engine) is a modular, in-order RV64 microarchitecture built around scout-based pre-computation. It is founded on its own original design ideas — not derived from, nor inspired by, existing microarchitectures.

## What PACE Is Not

- PACE is **not** an out-of-order (OoO) core.
- PACE is **not** a fork, port, or reimplementation of Rocket, BOOM, CVA6, VexRiscv, or any other existing RISC-V core.
- PACE is **not** a general-purpose replacement for high-performance OoO cores.

## Design Principles

1. **Originality** — PACE explores ideas not present in mainstream cores.
2. **Modularity** — every consumer (caches, extensions, peripherals) plugs through a well-defined port group.
3. **Verifiability** — every module has a dedicated testbench.
4. **Honesty** — limitations are documented openly.

## What PACE Targets

Embedded, edge, and real-time systems where area, energy, and determinism matter more than peak single-thread performance.

## How Decisions Are Made

PACE is founded and led by @uppmpt. Major architectural decisions are made by the maintainer, with community input via GitHub issues and discussions. Forks are welcome under the terms of CERN-OHL-W v2.
