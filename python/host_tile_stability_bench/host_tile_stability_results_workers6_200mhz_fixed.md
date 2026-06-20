# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `10`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`
- Run tag: `workers6_200mhz_fixed`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 10/10 | 0/10 | 2 | `4.641` | `4.423` | `6.592` | `0.686` | `14.77%` | `453333.47` | `1.009x` |
| standard @64 | 10/10 | 10/10 | 2 | `4.636` | `4.416` | `5.515` | `0.460` | `9.92%` | `450824.12` | `1.247x` |
| Seahorse zoom @512 | 10/10 | 0/10 | 2 | `5.715` | `5.418` | `6.937` | `0.621` | `10.87%` | `366227.26` | `1.721x` |
| deep tendrils @8192 | 10/10 | 0/10 | 1 | `8.567` | `8.409` | `9.968` | `0.492` | `5.75%` | `242675.75` | `2.063x` |
| deep mini-brot @8192 | 10/10 | 0/10 | 0 | `20.963` | `20.962` | `20.965` | `0.001` | `0.00%` | `98916.27` | `2.106x` |
| deep Seahorse @1024 | 10/10 | 0/10 | 1 | `9.668` | `9.511` | `11.065` | `0.491` | `5.08%` | `214934.36` | `2.065x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 0 | `4.425` | `468647.82` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run1.log` |
| fast escape @128 | 2 | PASS | 2 | `6.592` | `314569.73` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run2.log` |
| fast escape @128 | 3 | PASS | 0 | `4.425` | `468646.20` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run3.log` |
| fast escape @128 | 4 | PASS | 0 | `4.424` | `468749.85` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run4.log` |
| fast escape @128 | 5 | PASS | 0 | `4.423` | `468854.69` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run5.log` |
| fast escape @128 | 6 | PASS | 0 | `4.424` | `468752.69` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run6.log` |
| fast escape @128 | 7 | PASS | 0 | `4.423` | `468857.81` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run7.log` |
| fast escape @128 | 8 | PASS | 0 | `4.425` | `468648.25` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run8.log` |
| fast escape @128 | 9 | PASS | 0 | `4.423` | `468856.90` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run9.log` |
| fast escape @128 | 10 | PASS | 0 | `4.424` | `468750.81` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_fast_escape_128_run10.log` |
| standard @64 | 1 | PASS | 0 | `4.417` | `469498.90` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run1.log` |
| standard @64 | 2 | PASS | 0 | `4.418` | `469392.21` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run2.log` |
| standard @64 | 3 | PASS | 0 | `4.416` | `469605.38` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run3.log` |
| standard @64 | 4 | PASS | 1 | `5.502` | `376899.46` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run4.log` |
| standard @64 | 5 | PASS | 0 | `4.419` | `469285.29` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run5.log` |
| standard @64 | 6 | PASS | 0 | `4.417` | `469493.10` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run6.log` |
| standard @64 | 7 | PASS | 0 | `4.418` | `469381.54` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run7.log` |
| standard @64 | 8 | PASS | 0 | `4.418` | `469390.57` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run8.log` |
| standard @64 | 9 | PASS | 1 | `5.515` | `376010.56` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run9.log` |
| standard @64 | 10 | PASS | 0 | `4.419` | `469284.18` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_standard_64_run10.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `5.421` | `382498.78` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run1.log` |
| Seahorse zoom @512 | 2 | PASS | 0 | `5.421` | `382495.16` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run2.log` |
| Seahorse zoom @512 | 3 | PASS | 0 | `5.419` | `382645.39` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run3.log` |
| Seahorse zoom @512 | 4 | PASS | 1 | `6.848` | `302790.77` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run4.log` |
| Seahorse zoom @512 | 5 | PASS | 0 | `5.418` | `382712.63` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run5.log` |
| Seahorse zoom @512 | 6 | PASS | 0 | `5.421` | `382505.38` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run6.log` |
| Seahorse zoom @512 | 7 | PASS | 1 | `6.937` | `298904.94` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run7.log` |
| Seahorse zoom @512 | 8 | PASS | 0 | `5.421` | `382503.17` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run8.log` |
| Seahorse zoom @512 | 9 | PASS | 0 | `5.421` | `382500.56` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run9.log` |
| Seahorse zoom @512 | 10 | PASS | 0 | `5.418` | `382715.82` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_seahorse_zoom_512_run10.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `8.411` | `246528.31` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run1.log` |
| deep tendrils @8192 | 2 | PASS | 0 | `8.411` | `246528.12` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run2.log` |
| deep tendrils @8192 | 3 | PASS | 0 | `8.411` | `246521.18` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run3.log` |
| deep tendrils @8192 | 4 | PASS | 0 | `8.410` | `246556.13` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run4.log` |
| deep tendrils @8192 | 5 | PASS | 0 | `8.413` | `246467.99` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run5.log` |
| deep tendrils @8192 | 6 | PASS | 0 | `8.414` | `246440.36` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run6.log` |
| deep tendrils @8192 | 7 | PASS | 1 | `9.968` | `208016.50` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run7.log` |
| deep tendrils @8192 | 8 | PASS | 0 | `8.410` | `246555.45` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run8.log` |
| deep tendrils @8192 | 9 | PASS | 0 | `8.409` | `246585.68` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run9.log` |
| deep tendrils @8192 | 10 | PASS | 0 | `8.410` | `246557.78` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_tendrils_8192_run10.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `20.965` | `98905.82` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run1.log` |
| deep mini-brot @8192 | 2 | PASS | 0 | `20.963` | `98919.36` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run2.log` |
| deep mini-brot @8192 | 3 | PASS | 0 | `20.963` | `98915.17` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run3.log` |
| deep mini-brot @8192 | 4 | PASS | 0 | `20.962` | `98919.64` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run4.log` |
| deep mini-brot @8192 | 5 | PASS | 0 | `20.963` | `98918.97` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run5.log` |
| deep mini-brot @8192 | 6 | PASS | 0 | `20.963` | `98914.92` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run6.log` |
| deep mini-brot @8192 | 7 | PASS | 0 | `20.962` | `98924.05` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run7.log` |
| deep mini-brot @8192 | 8 | PASS | 0 | `20.964` | `98910.23` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run8.log` |
| deep mini-brot @8192 | 9 | PASS | 0 | `20.962` | `98919.57` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run9.log` |
| deep mini-brot @8192 | 10 | PASS | 0 | `20.963` | `98914.99` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_mini_brot_8192_run10.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `9.513` | `217977.46` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run1.log` |
| deep Seahorse @1024 | 2 | PASS | 1 | `11.065` | `187402.29` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run2.log` |
| deep Seahorse @1024 | 3 | PASS | 0 | `9.512` | `218001.48` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run3.log` |
| deep Seahorse @1024 | 4 | PASS | 0 | `9.514` | `217953.17` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run4.log` |
| deep Seahorse @1024 | 5 | PASS | 0 | `9.511` | `218025.05` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run5.log` |
| deep Seahorse @1024 | 6 | PASS | 0 | `9.511` | `218024.45` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run6.log` |
| deep Seahorse @1024 | 7 | PASS | 0 | `9.513` | `217977.91` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run7.log` |
| deep Seahorse @1024 | 8 | PASS | 0 | `9.511` | `218024.46` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run8.log` |
| deep Seahorse @1024 | 9 | PASS | 0 | `9.512` | `218002.04` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run9.log` |
| deep Seahorse @1024 | 10 | PASS | 0 | `9.514` | `217955.29` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_200mhz_fixed_deep_seahorse_1024_run10.log` |
