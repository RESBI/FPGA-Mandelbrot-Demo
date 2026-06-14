# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `5`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs previous 12M single-run |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 5/5 | 0/5 | 0 | `4.844` | `4.843` | `4.845` | `0.001` | `0.02%` | `428068.64` | `0.966x` |
| standard @64 | 5/5 | 5/5 | 0 | `4.450` | `4.449` | `4.451` | `0.001` | `0.02%` | `466030.04` | `0.944x` |
| Seahorse zoom @512 | 5/5 | 0/5 | 1 | `17.598` | `17.081` | `19.657` | `1.151` | `6.54%` | `118207.86` | `0.982x` |
| deep tendrils @8192 | 5/5 | 0/5 | 1 | `34.026` | `33.186` | `37.377` | `1.873` | `5.51%` | `61080.26` | `0.981x` |
| deep mini-brot @8192 | 5/5 | 0/5 | 0 | `83.281` | `83.280` | `83.282` | `0.001` | `0.00%` | `24898.89` | `1.002x` |
| deep Seahorse @1024 | 5/5 | 0/5 | 0 | `36.343` | `36.341` | `36.345` | `0.002` | `0.00%` | `57056.36` | `1.004x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 0 | `4.845` | `427973.42` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run1.log` |
| fast escape @128 | 2 | PASS | 0 | `4.844` | `428079.51` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run2.log` |
| fast escape @128 | 3 | PASS | 0 | `4.845` | `428030.22` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run3.log` |
| fast escape @128 | 4 | PASS | 0 | `4.843` | `428178.68` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run4.log` |
| fast escape @128 | 5 | PASS | 0 | `4.844` | `428081.37` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run5.log` |
| standard @64 | 1 | PASS | 0 | `4.449` | `466101.59` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run1.log` |
| standard @64 | 2 | PASS | 0 | `4.449` | `466103.83` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run2.log` |
| standard @64 | 3 | PASS | 0 | `4.451` | `465900.77` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run3.log` |
| standard @64 | 4 | PASS | 0 | `4.449` | `466085.48` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run4.log` |
| standard @64 | 5 | PASS | 0 | `4.450` | `465958.54` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run5.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `17.083` | `121384.83` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run1.log` |
| Seahorse zoom @512 | 2 | PASS | 0 | `17.084` | `121380.24` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run2.log` |
| Seahorse zoom @512 | 3 | PASS | 0 | `17.083` | `121386.98` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run3.log` |
| Seahorse zoom @512 | 4 | PASS | 1 | `19.657` | `105488.05` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run4.log` |
| Seahorse zoom @512 | 5 | PASS | 0 | `17.081` | `121399.19` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run5.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `33.188` | `62480.65` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run1.log` |
| deep tendrils @8192 | 2 | PASS | 0 | `33.188` | `62479.89` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run2.log` |
| deep tendrils @8192 | 3 | PASS | 0 | `33.186` | `62483.77` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run3.log` |
| deep tendrils @8192 | 4 | PASS | 1 | `37.377` | `55477.53` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run4.log` |
| deep tendrils @8192 | 5 | PASS | 0 | `33.189` | `62479.47` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run5.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `83.280` | `24899.10` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run1.log` |
| deep mini-brot @8192 | 2 | PASS | 0 | `83.280` | `24899.24` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run2.log` |
| deep mini-brot @8192 | 3 | PASS | 0 | `83.282` | `24898.57` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run3.log` |
| deep mini-brot @8192 | 4 | PASS | 0 | `83.282` | `24898.42` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run4.log` |
| deep mini-brot @8192 | 5 | PASS | 0 | `83.280` | `24899.10` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run5.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `36.341` | `57059.05` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run1.log` |
| deep Seahorse @1024 | 2 | PASS | 0 | `36.342` | `57057.58` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run2.log` |
| deep Seahorse @1024 | 3 | PASS | 0 | `36.342` | `57057.42` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run3.log` |
| deep Seahorse @1024 | 4 | PASS | 0 | `36.344` | `57055.29` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run4.log` |
| deep Seahorse @1024 | 5 | PASS | 0 | `36.345` | `57052.46` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run5.log` |
