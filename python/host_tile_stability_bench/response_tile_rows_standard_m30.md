# Response Tile Row-Split Standard Scene Benchmark

- Scene: `standard @64`
- Runs per split count: `10`
- Host/compute tile: `1920x120`
- Tile retries: `3`

| Row splits M | Height split | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| `30` | `30x4` | 10/10 | 2 | `3.898` | `3.701` | `4.683` | `10.60%` | `536672.13` |

## Runs

| Row splits M | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `30` | 1 | PASS | 0 | `3.706` | `559574.80` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run1.log` |
| `30` | 2 | PASS | 0 | `3.702` | `560164.02` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run2.log` |
| `30` | 3 | PASS | 1 | `4.683` | `442755.03` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run3.log` |
| `30` | 4 | PASS | 0 | `3.701` | `560243.12` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run4.log` |
| `30` | 5 | PASS | 1 | `4.681` | `442957.76` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run5.log` |
| `30` | 6 | PASS | 0 | `3.703` | `560021.80` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run6.log` |
| `30` | 7 | PASS | 0 | `3.701` | `560320.50` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run7.log` |
| `30` | 8 | PASS | 0 | `3.701` | `560317.42` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run8.log` |
| `30` | 9 | PASS | 0 | `3.702` | `560181.59` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run9.log` |
| `30` | 10 | PASS | 0 | `3.702` | `560185.30` | `python/host_tile_stability_bench/rtr_nodrain_rtr30_standard_run10.log` |
