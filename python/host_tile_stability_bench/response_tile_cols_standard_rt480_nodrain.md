# Response Tile Width Standard Scene Benchmark

- Scene: `standard @64`
- Runs per width: `10`
- Host tile: `1920x120`
- Tile retries: `3`

| Response tile cols | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---:|---:|---:|---:|---:|---:|---:|
| `480` | 10/10 | 4 | `7.119` | `3.747` | `35.464` | `140.01%` | `480402.36` |

## Runs

| Response tile cols | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `480` | 1 | PASS | 0 | `3.752` | `552628.86` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run1.log` |
| `480` | 2 | PASS | 1 | `4.743` | `437233.53` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run2.log` |
| `480` | 3 | PASS | 0 | `3.751` | `552780.28` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run3.log` |
| `480` | 4 | PASS | 0 | `3.749` | `553076.62` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run4.log` |
| `480` | 5 | PASS | 2 | `35.464` | `58470.13` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run5.log` |
| `480` | 6 | PASS | 0 | `3.751` | `552784.17` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run6.log` |
| `480` | 7 | PASS | 0 | `3.747` | `553380.08` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run7.log` |
| `480` | 8 | PASS | 1 | `4.738` | `437672.21` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run8.log` |
| `480` | 9 | PASS | 0 | `3.748` | `553219.04` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run9.log` |
| `480` | 10 | PASS | 0 | `3.751` | `552778.70` | `python/host_tile_stability_bench/rtcols_nodrain_rt480_standard_run10.log` |
