# Response Tile Row-Split Standard Scene Benchmark

- Scene: `standard @64`
- Runs per split count: `10`
- Host/compute tile: `1920x120`
- Tile retries: `3`

| Row splits M | Height split | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| `1` | `1x120` | 10/10 | 1 | `6.886` | `3.851` | `34.187` | `139.31%` | `490486.30` |

## Runs

| Row splits M | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `1` | 1 | PASS | 1 | `34.187` | `60654.43` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run1.log` |
| `1` | 2 | PASS | 0 | `3.853` | `538109.27` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run2.log` |
| `1` | 3 | PASS | 0 | `3.853` | `538199.85` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run3.log` |
| `1` | 4 | PASS | 0 | `3.851` | `538525.16` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run4.log` |
| `1` | 5 | PASS | 0 | `3.853` | `538225.08` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run5.log` |
| `1` | 6 | PASS | 0 | `3.853` | `538226.57` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run6.log` |
| `1` | 7 | PASS | 0 | `3.852` | `538318.30` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run7.log` |
| `1` | 8 | PASS | 0 | `3.852` | `538270.69` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run8.log` |
| `1` | 9 | PASS | 0 | `3.854` | `538020.92` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run9.log` |
| `1` | 10 | PASS | 0 | `3.852` | `538312.77` | `python/host_tile_stability_bench/rtr_nodrain_rtr1_standard_run10.log` |
