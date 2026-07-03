# Response Tile Row-Split Standard Scene Benchmark

- Scene: `standard @64`
- Runs per split count: `10`
- Host/compute tile: `1920x120`
- Tile retries: `3`

| Row splits M | Height split | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |
|---:|---|---:|---:|---:|---:|---:|---:|---:|
| `4` | `4x30` | 0/10 | 40 | `Fail` | `Fail` | `Fail` | `Fail%` | `Fail` |

## Runs

| Row splits M | Run | Status | Retry events | FPGA s | pps | Log |
|---:|---:|---|---:|---:|---:|---|
| `4` | 1 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run1.log` |
| `4` | 2 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run2.log` |
| `4` | 3 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run3.log` |
| `4` | 4 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run4.log` |
| `4` | 5 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run5.log` |
| `4` | 6 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run6.log` |
| `4` | 7 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run7.log` |
| `4` | 8 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run8.log` |
| `4` | 9 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run9.log` |
| `4` | 10 | FAIL rc=1 | 4 | `Fail` | `Fail` | `python/host_tile_stability_bench/rtr_nodrain_rtr4_standard_run10.log` |
