# Response Tile Width Standard Scene Benchmark

- Scene: `standard @64`
- Runs per width: `10`
- Host tile: `1920x120`
- Tile retries: `3`

| Response tile cols | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---:|---:|---:|---:|---:|---:|---:|
| `32` | 10/10 | 40 | `8.754` | `5.656` | `14.755` | `37.27%` | `263047.56` |

## Runs

| Response tile cols | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `32` | 1 | PASS | 3 | `7.788` | `266257.23` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run1.log` |
| `32` | 2 | PASS | 10 | `14.755` | `140535.71` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run2.log` |
| `32` | 3 | PASS | 1 | `5.656` | `366609.92` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run3.log` |
| `32` | 4 | PASS | 2 | `6.723` | `308454.70` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run4.log` |
| `32` | 5 | PASS | 2 | `6.718` | `308684.84` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run5.log` |
| `32` | 6 | PASS | 3 | `7.764` | `267089.63` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run6.log` |
| `32` | 7 | PASS | 3 | `7.778` | `266585.93` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run7.log` |
| `32` | 8 | PASS | 1 | `5.660` | `366365.71` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run8.log` |
| `32` | 9 | PASS | 6 | `11.001` | `188488.01` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run9.log` |
| `32` | 10 | PASS | 9 | `13.696` | `151403.88` | `python/host_tile_stability_bench/rtcols_nodrain_rt32_standard_run10.log` |
