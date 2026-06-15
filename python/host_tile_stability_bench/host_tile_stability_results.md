# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `1`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs previous 12M single-run |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 1/1 | 0/1 | 0 | `5.127` | `5.127` | `5.127` | `0.000` | `0.00%` | `404464.49` | `0.912x` |
| standard @64 | 1/1 | 1/1 | 0 | `4.731` | `4.731` | `4.731` | `0.000` | `0.00%` | `438328.75` | `0.888x` |
| Seahorse zoom @512 | 1/1 | 0/1 | 0 | `19.440` | `19.440` | `19.440` | `0.000` | `0.00%` | `106668.12` | `0.889x` |
| deep tendrils @8192 | 1/1 | 0/1 | 0 | `37.326` | `37.326` | `37.326` | `0.000` | `0.00%` | `55553.03` | `0.895x` |
| deep mini-brot @8192 | 1/1 | 0/1 | 0 | `83.561` | `83.561` | `83.561` | `0.000` | `0.00%` | `24815.51` | `0.998x` |
| deep Seahorse @1024 | 1/1 | 0/1 | 0 | `36.626` | `36.626` | `36.626` | `0.000` | `0.00%` | `56615.56` | `0.996x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 0 | `5.127` | `404464.49` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run1.log` |
| standard @64 | 1 | PASS | 0 | `4.731` | `438328.75` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run1.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `19.440` | `106668.12` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run1.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `37.326` | `55553.03` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run1.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `83.561` | `24815.51` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run1.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `36.626` | `56615.56` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run1.log` |
