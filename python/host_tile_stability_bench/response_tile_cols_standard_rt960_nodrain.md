# Response Tile Width Standard Scene Benchmark

- Scene: `standard @64`
- Runs per width: `10`
- Host tile: `1920x120`
- Tile retries: `3`

| Response tile cols | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---:|---:|---:|---:|---:|---:|---:|
| `960` | 10/10 | 0 | `3.725` | `3.724` | `3.728` | `0.04%` | `556588.74` |

## Runs

| Response tile cols | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `960` | 1 | PASS | 0 | `3.725` | `556650.44` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run1.log` |
| `960` | 2 | PASS | 0 | `3.725` | `556607.28` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run2.log` |
| `960` | 3 | PASS | 0 | `3.724` | `556757.14` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run3.log` |
| `960` | 4 | PASS | 0 | `3.728` | `556229.22` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run4.log` |
| `960` | 5 | PASS | 0 | `3.724` | `556770.46` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run5.log` |
| `960` | 6 | PASS | 0 | `3.727` | `556436.41` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run6.log` |
| `960` | 7 | PASS | 0 | `3.724` | `556767.26` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run7.log` |
| `960` | 8 | PASS | 0 | `3.725` | `556597.70` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run8.log` |
| `960` | 9 | PASS | 0 | `3.724` | `556772.56` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run9.log` |
| `960` | 10 | PASS | 0 | `3.727` | `556298.97` | `python/host_tile_stability_bench/rtcols_nodrain_rt960_standard_run10.log` |
