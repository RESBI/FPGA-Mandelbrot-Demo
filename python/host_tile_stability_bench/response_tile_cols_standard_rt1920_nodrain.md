# Response Tile Width Standard Scene Benchmark

- Scene: `standard @64`
- Runs per width: `10`
- Host tile: `1920x120`
- Tile retries: `3`

| Response tile cols | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---:|---:|---:|---:|---:|---:|---:|
| `1920` | 10/10 | 0 | `3.711` | `3.709` | `3.717` | `0.08%` | `558689.48` |

## Runs

| Response tile cols | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `1920` | 1 | PASS | 0 | `3.710` | `558868.28` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run1.log` |
| `1920` | 2 | PASS | 0 | `3.712` | `558649.69` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run2.log` |
| `1920` | 3 | PASS | 0 | `3.709` | `559029.28` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run3.log` |
| `1920` | 4 | PASS | 0 | `3.710` | `558862.32` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run4.log` |
| `1920` | 5 | PASS | 0 | `3.711` | `558732.83` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run5.log` |
| `1920` | 6 | PASS | 0 | `3.717` | `557898.34` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run6.log` |
| `1920` | 7 | PASS | 0 | `3.709` | `559026.71` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run7.log` |
| `1920` | 8 | PASS | 0 | `3.710` | `558886.24` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run8.log` |
| `1920` | 9 | PASS | 0 | `3.709` | `559036.13` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run9.log` |
| `1920` | 10 | PASS | 0 | `3.717` | `557905.03` | `python/host_tile_stability_bench/rtcols_nodrain_rt1920_standard_run10.log` |
