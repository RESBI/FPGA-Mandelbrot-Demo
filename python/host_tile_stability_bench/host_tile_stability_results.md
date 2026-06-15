# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `1`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs previous 12M single-run |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 1/1 | 0/1 | 0 | `4.683` | `4.683` | `4.683` | `0.000` | `0.00%` | `442824.20` | `0.999x` |
| standard @64 | 1/1 | 1/1 | 0 | `5.782` | `5.782` | `5.782` | `0.000` | `0.00%` | `358640.05` | `0.727x` |
| Seahorse zoom @512 | 1/1 | 0/1 | 0 | `9.836` | `9.836` | `9.836` | `0.000` | `0.00%` | `210825.06` | `1.757x` |
| deep tendrils @8192 | 1/1 | 0/1 | 0 | `17.677` | `17.677` | `17.677` | `0.000` | `0.00%` | `117303.25` | `1.889x` |
| deep mini-brot @8192 | 1/1 | 0/1 | 0 | `44.146` | `44.146` | `44.146` | `0.000` | `0.00%` | `46971.46` | `1.890x` |
| deep Seahorse @1024 | 1/1 | 0/1 | 0 | `19.965` | `19.965` | `19.965` | `0.000` | `0.00%` | `103861.51` | `1.827x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 0 | `4.683` | `442824.20` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run1.log` |
| standard @64 | 1 | PASS | 0 | `5.782` | `358640.05` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run1.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `9.836` | `210825.06` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run1.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `17.677` | `117303.25` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run1.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `44.146` | `46971.46` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run1.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `19.965` | `103861.51` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run1.log` |
