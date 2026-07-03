# Response Tile Row-Split Standard Scene Benchmark

- Scene: `standard @64`
- Runs per split count: `10`
- Host/compute tile: `1920x120`
- Tile retries: `3`

| Row splits M | Height split | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| `2` | `2x60` | 6/6 | 216 | `1094.234` | `1069.607` | `1099.163` | `1.10%` | `1895.22` |

## Runs

| Row splits M | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `2` | 1 | PASS | 36 | `1099.158` | `1886.53` | `python/host_tile_stability_bench/rtr_nodrain_rtr2_standard_run1.log` |
| `2` | 2 | PASS | 36 | `1099.152` | `1886.55` | `python/host_tile_stability_bench/rtr_nodrain_rtr2_standard_run2.log` |
| `2` | 3 | PASS | 36 | `1099.163` | `1886.53` | `python/host_tile_stability_bench/rtr_nodrain_rtr2_standard_run3.log` |
| `2` | 4 | PASS | 36 | `1099.163` | `1886.53` | `python/host_tile_stability_bench/rtr_nodrain_rtr2_standard_run4.log` |
| `2` | 5 | PASS | 36 | `1099.163` | `1886.53` | `python/host_tile_stability_bench/rtr_nodrain_rtr2_standard_run5.log` |
| `2` | 6 | PASS | 36 | `1069.607` | `1938.66` | `python/host_tile_stability_bench/rtr_nodrain_rtr2_standard_run6.log` |
