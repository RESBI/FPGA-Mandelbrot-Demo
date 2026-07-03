# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `1`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`
- Run tag: `rtr8_deferred_smoke`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 1/1 | 0/1 | 0 | `3.722` | `3.722` | `3.722` | `0.000` | `0.00%` | `557108.02` | `1.258x` |
| standard @64 | 1/1 | 1/1 | 0 | `3.716` | `3.716` | `3.716` | `0.000` | `0.00%` | `558066.89` | `1.556x` |
| Seahorse zoom @512 | 1/1 | 0/1 | 0 | `3.867` | `3.867` | `3.867` | `0.000` | `0.00%` | `536187.80` | `2.544x` |
| deep tendrils @8192 | 1/1 | 0/1 | 0 | `3.997` | `3.997` | `3.997` | `0.000` | `0.00%` | `518807.41` | `4.423x` |
| deep mini-brot @8192 | 1/1 | 0/1 | 0 | `9.166` | `9.166` | `9.166` | `0.000` | `0.00%` | `226232.08` | `4.816x` |
| deep Seahorse @1024 | 1/1 | 0/1 | 0 | `4.473` | `4.473` | `4.473` | `0.000` | `0.00%` | `463562.09` | `4.463x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 0 | `3.722` | `557108.02` | 2073588/2073600 | `python/host_tile_stability_bench/rtr8_deferred_smoke_fast_escape_128_run1.log` |
| standard @64 | 1 | PASS | 0 | `3.716` | `558066.89` | 2073600/2073600 | `python/host_tile_stability_bench/rtr8_deferred_smoke_standard_64_run1.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `3.867` | `536187.80` | 2072760/2073600 | `python/host_tile_stability_bench/rtr8_deferred_smoke_seahorse_zoom_512_run1.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `3.997` | `518807.41` | 2072027/2073600 | `python/host_tile_stability_bench/rtr8_deferred_smoke_deep_tendrils_8192_run1.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `9.166` | `226232.08` | 2058166/2073600 | `python/host_tile_stability_bench/rtr8_deferred_smoke_deep_mini_brot_8192_run1.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `4.473` | `463562.09` | 2049714/2073600 | `python/host_tile_stability_bench/rtr8_deferred_smoke_deep_seahorse_1024_run1.log` |
