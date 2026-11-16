# Branch Prediction Results

All values are computed from Icarus Verilog simulations of the RTL (`results/simulation_results.csv`); each run was checked branch-by-branch against the Python golden model.

**Assumptions:** base CPI = 1.0, branch frequency = 0.2, misprediction penalty = 2 cycles, BHT = 16 entries, BTB = 16 entries.  
**CPI** = base CPI + branch frequency x misprediction rate x penalty.  
**Accuracy** = correct direction predictions / branches. **Misprediction** = pipeline flush (wrong direction or wrong target).

## 1. Overall comparison of the three strategies (all traces pooled)

| Scheme | Branches | Correct | Accuracy % | Mispredictions | Mispredict rate % | CPI | Speedup vs NT |
|---|---:|---:|---:|---:|---:|---:|---:|
| Static NT | 1256 | 381 | 30.33 | 875 | 69.67 | 1.2787 | 1.000 |
| 1-bit BHT | 1256 | 778 | 61.94 | 478 | 38.06 | 1.1522 | 1.110 |
| 2-bit BHT | 1256 | 858 | 68.31 | 398 | 31.69 | 1.1268 | 1.135 |

## 2. Per-trace results

| Trace | Branches | Scheme | Accuracy % | Mispredictions | Mispredict rate % | BTB hit % | CPI | Speedup vs NT |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| loop10 | 100 | Static NT | 10.00 | 90 | 90.00 | 99.00 | 1.3600 | 1.000 |
| loop10 | 100 | 1-bit BHT | 80.00 | 20 | 20.00 | 99.00 | 1.0800 | 1.259 |
| loop10 | 100 | 2-bit BHT | 89.00 | 11 | 11.00 | 99.00 | 1.0440 | 1.303 |
| loop100 | 300 | Static NT | 1.00 | 297 | 99.00 | 99.67 | 1.3960 | 1.000 |
| loop100 | 300 | 1-bit BHT | 98.00 | 6 | 2.00 | 99.67 | 1.0080 | 1.385 |
| loop100 | 300 | 2-bit BHT | 98.67 | 4 | 1.33 | 99.67 | 1.0053 | 1.389 |
| nested | 50 | Static NT | 22.00 | 39 | 78.00 | 96.00 | 1.3120 | 1.000 |
| nested | 50 | 1-bit BHT | 56.00 | 22 | 44.00 | 96.00 | 1.1760 | 1.116 |
| nested | 50 | 2-bit BHT | 74.00 | 13 | 26.00 | 96.00 | 1.1040 | 1.188 |
| array_sum | 16 | Static NT | 37.50 | 10 | 62.50 | 81.25 | 1.2500 | 1.000 |
| array_sum | 16 | 1-bit BHT | 62.50 | 6 | 37.50 | 81.25 | 1.1500 | 1.087 |
| array_sum | 16 | 2-bit BHT | 62.50 | 6 | 37.50 | 81.25 | 1.1500 | 1.087 |
| mixed | 240 | Static NT | 42.08 | 139 | 57.92 | 97.08 | 1.2317 | 1.000 |
| mixed | 240 | 1-bit BHT | 51.25 | 117 | 48.75 | 97.08 | 1.1950 | 1.031 |
| mixed | 240 | 2-bit BHT | 72.50 | 66 | 27.50 | 97.08 | 1.1100 | 1.110 |
| multi_alias | 250 | Static NT | 44.00 | 140 | 56.00 | 58.80 | 1.2240 | 1.000 |
| multi_alias | 250 | 1-bit BHT | 51.60 | 121 | 48.40 | 58.80 | 1.1936 | 1.025 |
| multi_alias | 250 | 2-bit BHT | 55.20 | 112 | 44.80 | 58.80 | 1.1792 | 1.038 |
| random | 200 | Static NT | 45.00 | 110 | 55.00 | 99.50 | 1.2200 | 1.000 |
| random | 200 | 1-bit BHT | 57.00 | 86 | 43.00 | 99.50 | 1.1720 | 1.041 |
| random | 200 | 2-bit BHT | 57.00 | 86 | 43.00 | 99.50 | 1.1720 | 1.041 |
| alternating | 100 | Static NT | 50.00 | 50 | 50.00 | 99.00 | 1.2000 | 1.000 |
| alternating | 100 | 1-bit BHT | 0.00 | 100 | 100.00 | 99.00 | 1.4000 | 0.857 |
| alternating | 100 | 2-bit BHT | 0.00 | 100 | 100.00 | 99.00 | 1.4000 | 0.857 |

## 3. BHT size sensitivity (accuracy %, BTB fixed at 16 entries)

| Trace | Scheme | 4 entries | 8 entries | 16 entries | 32 entries | 64 entries |
|---|---|---:|---:|---:|---:|---:|
| nested | 1-bit BHT | 56.00 | 56.00 | 56.00 | 56.00 | 56.00 |
| nested | 2-bit BHT | 74.00 | 74.00 | 74.00 | 74.00 | 74.00 |
| mixed | 1-bit BHT | 52.92 | 52.92 | 51.25 | 51.25 | 51.25 |
| mixed | 2-bit BHT | 71.25 | 71.25 | 72.50 | 72.50 | 72.50 |
| multi_alias | 1-bit BHT | 51.60 | 51.60 | 51.60 | 91.20 | 91.20 |
| multi_alias | 2-bit BHT | 55.20 | 55.20 | 55.20 | 94.80 | 94.80 |
| random | 1-bit BHT | 57.00 | 57.00 | 57.00 | 57.00 | 57.00 |
| random | 2-bit BHT | 57.00 | 57.00 | 57.00 | 57.00 | 57.00 |
