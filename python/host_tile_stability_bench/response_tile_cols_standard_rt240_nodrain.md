# Response Tile Width Standard Scene Benchmark

- Scene: `standard @64`
- Runs per width: `10`
- Host tile: `1920x120`
- Tile retries: `3`

| Response tile cols | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---:|---:|---:|---:|---:|---:|---:|
| `240` | 10/10 | 3 | `4.113` | `3.815` | `5.787` | `16.19%` | `513607.55` |

## Runs

| Response tile cols | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `240` | 1 | PASS | 0 | `3.815` | `543467.89` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run1.log` |
| `240` | 2 | PASS | 0 | `3.815` | `543473.57` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run2.log` |
| `240` | 3 | PASS | 0 | `3.816` | `543389.90` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run3.log` |
| `240` | 4 | PASS | 0 | `3.815` | `543608.37` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run4.log` |
| `240` | 5 | PASS | 2 | `5.787` | `358290.27` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run5.log` |
| `240` | 6 | PASS | 0 | `3.818` | `543125.59` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run6.log` |
| `240` | 7 | PASS | 0 | `3.822` | `542608.35` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run7.log` |
| `240` | 8 | PASS | 1 | `4.808` | `431275.82` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run8.log` |
| `240` | 9 | PASS | 0 | `3.815` | `543606.08` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run9.log` |
| `240` | 10 | PASS | 0 | `3.817` | `543229.64` | `python/host_tile_stability_bench/rtcols_nodrain_rt240_standard_run10.log` |
