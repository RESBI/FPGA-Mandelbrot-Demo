# Response Tile Row-Split Standard Scene Benchmark

- Scene: `standard @64`
- Runs per split count: `10`
- Host/compute tile: `1920x120`
- Tile retries: `3`

| Row splits M | Height split | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| `15` | `15x8` | 10/10 | 1 | `3.807` | `3.707` | `4.689` | `8.14%` | `547351.22` |

## Runs

| Row splits M | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `15` | 1 | PASS | 0 | `3.709` | `559002.55` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run1.log` |
| `15` | 2 | PASS | 0 | `3.709` | `559095.97` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run2.log` |
| `15` | 3 | PASS | 0 | `3.707` | `559432.09` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run3.log` |
| `15` | 4 | PASS | 0 | `3.714` | `558381.33` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run4.log` |
| `15` | 5 | PASS | 0 | `3.709` | `559132.65` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run5.log` |
| `15` | 6 | PASS | 0 | `3.708` | `559276.80` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run6.log` |
| `15` | 7 | PASS | 0 | `3.707` | `559445.10` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run7.log` |
| `15` | 8 | PASS | 0 | `3.713` | `558395.96` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run8.log` |
| `15` | 9 | PASS | 1 | `4.689` | `442213.10` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run9.log` |
| `15` | 10 | PASS | 0 | `3.709` | `559136.60` | `python/host_tile_stability_bench/rtr_nodrain_rtr15_standard_run10.log` |
