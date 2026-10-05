# Contributing to PACE

Thanks for your interest in PACE! This is a personal research project,
maintained on a best-effort basis. Contributions of all kinds are
welcome — code, documentation, bug reports, benchmarks, and reviews.

## How to Contribute

### Reporting Bugs

Open an issue on GitHub. Please include:

- **What you did** (exact commands or steps)
- **What you expected to happen**
- **What actually happened** (error message, log, waveform if possible)
- **Your environment** (Verilator version, OS, toolchain)

For failing testbenches, please mention the testbench name and attach
the relevant part of the output.

### Suggesting Features

Open an issue with the `enhancement` label and describe:

- **The problem** you are trying to solve
- **Your proposed solution**
- **Alternatives** you considered

Please note: PACE is **not** a general-purpose OoO core. Suggestions
that would turn PACE into an out-of-order design, or that would make it
a clone of an existing core, will be declined. See `VISION.md` for
the project's principles.

### Submitting Code

1. Fork the repository.
2. Create a branch with a descriptive name (e.g. `fix/tb-top-wiring`).
3. Make your changes.
4. Ensure your changes do not break the existing testbenches.
5. Open a Pull Request with a clear description.

For larger changes, please open an issue first to discuss the design
before writing code.

## Coding Guidelines

- **Language:** pure Verilog (IEEE 1364, Verilog-2001). Do **not** use
  SystemVerilog constructs.
- **Style:** 2-space indentation, one module per file, file name matches
  the module name.
- **Headers:** keep the CERN-OHL-W v2 notice at the top of every file.
- **Testbenches:** every new module should come with a dedicated
  testbench, named `tb_<module>.v` and placed in `pace_tb/`.
- **Simulator:** Verilator is the reference simulator.

## What We Are Looking For

- Bug fixes in RTL or testbenches
- Fixes for failing integration testbenches
- Yosys synthesis results (LUT/FF counts, Fmax on FPGA)
- CoreMark / Dhrystone benchmark setups
- RISC-V compliance test integration (riscv-arch-test)
- Documentation improvements
- Additional testbenches for uncovered modules

## What We Are Not Looking For

- Rewrites in SystemVerilog
- Conversion to out-of-order
- Ports from other cores (Rocket, BOOM, CVA6, VexRiscv, etc.)
- Removal of the CERN-OHL-W v2 license

## License

By contributing, you agree that your contributions will be licensed
under the **CERN-OHL-W v2**, the same license as the project.

## Questions

Open a GitHub issue or start a discussion. Please be patient — this is
a personal project and responses may take time.
