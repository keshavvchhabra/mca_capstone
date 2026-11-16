# Synthesis Results (Yosys)

Design: `bpu_top` (predictor + BTB + update/selection logic + flush control), 32-bit PC, 16-entry BHT, 16-entry BTB, 32-bit performance counters.

## Generic gate-level synthesis (`synth -flatten`)

| Scheme | Total cells | Flip-flops | Latches | Logic depth (gates) | check -assert |
|---|---:|---:|---:|---:|---|
| Static NT | 1885 | 527 | 0 | 31 | passed |
| 1-bit BHT | 2921 | 1055 | 0 | 31 | passed |
| 2-bit BHT | 3029 | 1071 | 0 | 31 | passed |

## Xilinx 7-series FPGA mapping (`synth_xilinx -flatten`)

| Scheme | LUTs | Flip-flops (FDRE/FDSE) | CARRY4 | LUTRAM (RAM32M) | I/O buffers (IBUF/OBUF) |
|---|---:|---:|---:|---:|---:|
| Static NT | 135 | 111 | 42 | 5 | 334 |
| 1-bit BHT | 197 | 127 | 42 | 11 | 334 |
| 2-bit BHT | 214 | 143 | 42 | 11 | 334 |

Notes: the BTB tag/target arrays map to distributed LUTRAM (RAM32M), so they do not
appear as flip-flops in the FPGA mapping. The I/O buffer count reflects the wide
debug/counter ports of the standalone unit; inside a CPU these would be internal wires.
Per-cell breakdowns are in the `*.log` files in this folder.
Maximum frequency requires place-and-route with timing (e.g. Vivado); Yosys reports logic depth only.
