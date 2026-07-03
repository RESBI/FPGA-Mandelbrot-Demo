# Response Tile Width Standard Scene Benchmark

- Scene: `standard @64`
- Runs per width: `10`
- Host tile: `1920x120`
- Tile retries: `3`

| Response tile cols | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---:|---:|---:|---:|---:|---:|---:|
| `64` | 10/10 | 1 | `4.244` | `4.141` | `5.154` | `7.53%` | `490726.52` |

## Runs

| Response tile cols | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `64` | 1 | PASS | 0 | `4.147` | `500061.92` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run1.log` |
| `64` | 2 | PASS | 0 | `4.142` | `500567.59` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run2.log` |
| `64` | 3 | PASS | 0 | `4.142` | `500674.94` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run3.log` |
| `64` | 4 | PASS | 1 | `5.154` | `402322.29` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run4.log` |
| `64` | 5 | PASS | 0 | `4.142` | `500674.87` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run5.log` |
| `64` | 6 | PASS | 0 | `4.143` | `500560.98` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run6.log` |
| `64` | 7 | PASS | 0 | `4.142` | `500670.33` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run7.log` |
| `64` | 8 | PASS | 0 | `4.142` | `500684.70` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run8.log` |
| `64` | 9 | PASS | 0 | `4.141` | `500801.86` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run9.log` |
| `64` | 10 | PASS | 0 | `4.145` | `500245.74` | `python/host_tile_stability_bench/rtcols_nodrain_rt64_standard_run10.log` |
