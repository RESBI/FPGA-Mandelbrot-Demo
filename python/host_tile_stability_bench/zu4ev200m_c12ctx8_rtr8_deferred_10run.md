# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `10`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`
- Run tag: `zu4ev200m_c12ctx8_rtr8_deferred`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 10/10 | 0/10 | 1 | `3.821` | `3.720` | `4.702` | `0.310` | `8.11%` | `545436.22` | `1.226x` |
| standard @64 | 10/10 | 10/10 | 1 | `3.816` | `3.715` | `4.696` | `0.309` | `8.10%` | `546090.60` | `1.515x` |
| Seahorse zoom @512 | 10/10 | 0/10 | 1 | `3.964` | `3.864` | `4.855` | `0.313` | `7.89%` | `525491.58` | `2.481x` |
| deep tendrils @8192 | 10/10 | 0/10 | 0 | `3.994` | `3.991` | `3.997` | `0.002` | `0.04%` | `519243.89` | `4.426x` |
| deep mini-brot @8192 | 10/10 | 0/10 | 0 | `9.166` | `9.164` | `9.168` | `0.002` | `0.02%` | `226235.12` | `4.816x` |
| deep Seahorse @1024 | 10/10 | 0/10 | 1 | `4.575` | `4.472` | `5.485` | `0.320` | `6.99%` | `454952.34` | `4.364x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 1 | `4.702` | `440981.95` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run1.log` |
| fast escape @128 | 2 | PASS | 0 | `3.723` | `556951.49` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run2.log` |
| fast escape @128 | 3 | PASS | 0 | `3.728` | `556284.36` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run3.log` |
| fast escape @128 | 4 | PASS | 0 | `3.721` | `557302.40` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run4.log` |
| fast escape @128 | 5 | PASS | 0 | `3.721` | `557329.66` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run5.log` |
| fast escape @128 | 6 | PASS | 0 | `3.721` | `557321.96` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run6.log` |
| fast escape @128 | 7 | PASS | 0 | `3.726` | `556513.79` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run7.log` |
| fast escape @128 | 8 | PASS | 0 | `3.725` | `556725.65` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run8.log` |
| fast escape @128 | 9 | PASS | 0 | `3.720` | `557472.25` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run9.log` |
| fast escape @128 | 10 | PASS | 0 | `3.720` | `557478.74` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_fast_escape_128_run10.log` |
| standard @64 | 1 | PASS | 0 | `3.717` | `557861.87` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run1.log` |
| standard @64 | 2 | PASS | 0 | `3.725` | `556722.58` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run2.log` |
| standard @64 | 3 | PASS | 1 | `4.696` | `441565.20` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run3.log` |
| standard @64 | 4 | PASS | 0 | `3.717` | `557924.17` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run4.log` |
| standard @64 | 5 | PASS | 0 | `3.718` | `557786.88` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run5.log` |
| standard @64 | 6 | PASS | 0 | `3.720` | `557473.44` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run6.log` |
| standard @64 | 7 | PASS | 0 | `3.717` | `557931.18` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run7.log` |
| standard @64 | 8 | PASS | 0 | `3.715` | `558227.98` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run8.log` |
| standard @64 | 9 | PASS | 0 | `3.717` | `557926.15` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run9.log` |
| standard @64 | 10 | PASS | 0 | `3.720` | `557486.52` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_standard_64_run10.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `3.864` | `536625.52` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run1.log` |
| Seahorse zoom @512 | 2 | PASS | 0 | `3.869` | `535962.22` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run2.log` |
| Seahorse zoom @512 | 3 | PASS | 0 | `3.864` | `536623.48` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run3.log` |
| Seahorse zoom @512 | 4 | PASS | 1 | `4.855` | `427102.43` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run4.log` |
| Seahorse zoom @512 | 5 | PASS | 0 | `3.864` | `536635.02` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run5.log` |
| Seahorse zoom @512 | 6 | PASS | 0 | `3.865` | `536449.06` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run6.log` |
| Seahorse zoom @512 | 7 | PASS | 0 | `3.864` | `536623.17` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run7.log` |
| Seahorse zoom @512 | 8 | PASS | 0 | `3.864` | `536629.70` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run8.log` |
| Seahorse zoom @512 | 9 | PASS | 0 | `3.871` | `535645.55` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run9.log` |
| Seahorse zoom @512 | 10 | PASS | 0 | `3.864` | `536619.67` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_seahorse_zoom_512_run10.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `3.997` | `518762.85` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run1.log` |
| deep tendrils @8192 | 2 | PASS | 0 | `3.993` | `519331.79` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run2.log` |
| deep tendrils @8192 | 3 | PASS | 0 | `3.996` | `518971.37` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run3.log` |
| deep tendrils @8192 | 4 | PASS | 0 | `3.993` | `519282.10` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run4.log` |
| deep tendrils @8192 | 5 | PASS | 0 | `3.991` | `519579.65` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run5.log` |
| deep tendrils @8192 | 6 | PASS | 0 | `3.993` | `519245.66` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run6.log` |
| deep tendrils @8192 | 7 | PASS | 0 | `3.994` | `519164.91` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run7.log` |
| deep tendrils @8192 | 8 | PASS | 0 | `3.993` | `519318.83` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run8.log` |
| deep tendrils @8192 | 9 | PASS | 0 | `3.993` | `519331.41` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run9.log` |
| deep tendrils @8192 | 10 | PASS | 0 | `3.992` | `519450.33` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_tendrils_8192_run10.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `9.165` | `226259.43` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run1.log` |
| deep mini-brot @8192 | 2 | PASS | 0 | `9.165` | `226260.99` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run2.log` |
| deep mini-brot @8192 | 3 | PASS | 0 | `9.165` | `226259.80` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run3.log` |
| deep mini-brot @8192 | 4 | PASS | 0 | `9.168` | `226183.05` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run4.log` |
| deep mini-brot @8192 | 5 | PASS | 0 | `9.168` | `226183.76` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run5.log` |
| deep mini-brot @8192 | 6 | PASS | 0 | `9.164` | `226282.32` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run6.log` |
| deep mini-brot @8192 | 7 | PASS | 0 | `9.164` | `226280.61` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run7.log` |
| deep mini-brot @8192 | 8 | PASS | 0 | `9.167` | `226198.03` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run8.log` |
| deep mini-brot @8192 | 9 | PASS | 0 | `9.168` | `226185.03` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run9.log` |
| deep mini-brot @8192 | 10 | PASS | 0 | `9.165` | `226258.23` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_mini_brot_8192_run10.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `4.473` | `463605.07` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run1.log` |
| deep Seahorse @1024 | 2 | PASS | 0 | `4.473` | `463603.99` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run2.log` |
| deep Seahorse @1024 | 3 | PASS | 0 | `4.473` | `463595.58` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run3.log` |
| deep Seahorse @1024 | 4 | PASS | 0 | `4.478` | `463090.26` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run4.log` |
| deep Seahorse @1024 | 5 | PASS | 1 | `5.485` | `378068.03` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run5.log` |
| deep Seahorse @1024 | 6 | PASS | 0 | `4.474` | `463479.29` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run6.log` |
| deep Seahorse @1024 | 7 | PASS | 0 | `4.472` | `463716.67` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run7.log` |
| deep Seahorse @1024 | 8 | PASS | 0 | `4.474` | `463503.52` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run8.log` |
| deep Seahorse @1024 | 9 | PASS | 0 | `4.477` | `463152.00` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run9.log` |
| deep Seahorse @1024 | 10 | PASS | 0 | `4.472` | `463709.02` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deferred_deep_seahorse_1024_run10.log` |
