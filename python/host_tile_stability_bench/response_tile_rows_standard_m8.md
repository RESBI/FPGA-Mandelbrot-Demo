# Response Tile Row-Split Standard Scene Benchmark

- Scene: `standard @64`
- Runs per split count: `10`
- Host/compute tile: `1920x120`
- Tile retries: `3`

| Row splits M | Height split | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| `8` | `8x15` | 10/10 | 0 | `3.718` | `3.716` | `3.722` | `0.05%` | `557751.55` |

## Runs

| Row splits M | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `8` | 1 | PASS | 0 | `3.717` | `557907.04` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run1.log` |
| `8` | 2 | PASS | 0 | `3.718` | `557687.90` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run2.log` |
| `8` | 3 | PASS | 0 | `3.717` | `557937.77` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run3.log` |
| `8` | 4 | PASS | 0 | `3.717` | `557921.17` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run4.log` |
| `8` | 5 | PASS | 0 | `3.717` | `557921.98` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run5.log` |
| `8` | 6 | PASS | 0 | `3.719` | `557543.68` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run6.log` |
| `8` | 7 | PASS | 0 | `3.722` | `557060.38` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run7.log` |
| `8` | 8 | PASS | 0 | `3.717` | `557927.13` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run8.log` |
| `8` | 9 | PASS | 0 | `3.716` | `558058.24` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run9.log` |
| `8` | 10 | PASS | 0 | `3.719` | `557550.23` | `python/host_tile_stability_bench/rtr_nodrain_rtr8_standard_run10.log` |
