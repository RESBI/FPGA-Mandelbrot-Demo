# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `10`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`
- Run tag: `workers6_100mhz`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 10/10 | 0/10 | 3 | `5.027` | `4.692` | `5.816` | `0.539` | `10.72%` | `416435.88` | `0.931x` |
| standard @64 | 10/10 | 10/10 | 5 | `5.253` | `4.693` | `5.826` | `0.590` | `11.22%` | `399284.73` | `1.101x` |
| Seahorse zoom @512 | 10/10 | 0/10 | 4 | `9.672` | `9.135` | `10.838` | `0.706` | `7.30%` | `215385.85` | `1.017x` |
| deep tendrils @8192 | 10/10 | 0/10 | 3 | `16.971` | `16.244` | `18.735` | `1.167` | `6.88%` | `122678.93` | `1.042x` |
| deep mini-brot @8192 | 10/10 | 0/10 | 2 | `42.313` | `41.359` | `46.169` | `2.007` | `4.74%` | `49099.63` | `1.043x` |
| deep Seahorse @1024 | 10/10 | 0/10 | 3 | `19.070` | `18.450` | `22.590` | `1.395` | `7.31%` | `109198.64` | `1.047x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 1 | `5.814` | `356661.99` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run1.log` |
| fast escape @128 | 2 | PASS | 0 | `4.694` | `441784.61` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run2.log` |
| fast escape @128 | 3 | PASS | 0 | `4.692` | `441970.41` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run3.log` |
| fast escape @128 | 4 | PASS | 0 | `4.692` | `441972.49` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run4.log` |
| fast escape @128 | 5 | PASS | 0 | `4.693` | `441876.09` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run5.log` |
| fast escape @128 | 6 | PASS | 1 | `5.795` | `357833.79` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run6.log` |
| fast escape @128 | 7 | PASS | 1 | `5.816` | `356544.20` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run7.log` |
| fast escape @128 | 8 | PASS | 0 | `4.693` | `441877.64` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run8.log` |
| fast escape @128 | 9 | PASS | 0 | `4.693` | `441864.27` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run9.log` |
| fast escape @128 | 10 | PASS | 0 | `4.692` | `441973.27` | 2073588/2073600 | `python/host_tile_stability_bench/workers6_100mhz_fast_escape_128_run10.log` |
| standard @64 | 1 | PASS | 0 | `4.694` | `441784.30` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run1.log` |
| standard @64 | 2 | PASS | 0 | `4.694` | `441785.80` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run2.log` |
| standard @64 | 3 | PASS | 1 | `5.812` | `356792.04` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run3.log` |
| standard @64 | 4 | PASS | 0 | `4.693` | `441879.61` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run4.log` |
| standard @64 | 5 | PASS | 1 | `5.826` | `355935.59` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run5.log` |
| standard @64 | 6 | PASS | 1 | `5.817` | `356480.08` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run6.log` |
| standard @64 | 7 | PASS | 1 | `5.796` | `357775.19` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run7.log` |
| standard @64 | 8 | PASS | 1 | `5.811` | `356849.84` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run8.log` |
| standard @64 | 9 | PASS | 0 | `4.694` | `441781.03` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run9.log` |
| standard @64 | 10 | PASS | 0 | `4.694` | `441783.79` | 2073600/2073600 | `python/host_tile_stability_bench/workers6_100mhz_standard_64_run10.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `9.135` | `227003.30` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run1.log` |
| Seahorse zoom @512 | 2 | PASS | 1 | `10.838` | `191330.46` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run2.log` |
| Seahorse zoom @512 | 3 | PASS | 0 | `9.135` | `227002.89` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run3.log` |
| Seahorse zoom @512 | 4 | PASS | 0 | `9.136` | `226980.41` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run4.log` |
| Seahorse zoom @512 | 5 | PASS | 1 | `10.350` | `200351.84` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run5.log` |
| Seahorse zoom @512 | 6 | PASS | 0 | `9.136` | `226980.02` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run6.log` |
| Seahorse zoom @512 | 7 | PASS | 1 | `10.367` | `200023.81` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run7.log` |
| Seahorse zoom @512 | 8 | PASS | 0 | `9.136` | `226980.01` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run8.log` |
| Seahorse zoom @512 | 9 | PASS | 0 | `9.138` | `226930.27` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run9.log` |
| Seahorse zoom @512 | 10 | PASS | 1 | `10.354` | `200275.47` | 2072760/2073600 | `python/host_tile_stability_bench/workers6_100mhz_seahorse_zoom_512_run10.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `16.246` | `127636.63` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run1.log` |
| deep tendrils @8192 | 2 | PASS | 1 | `18.735` | `110683.28` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run2.log` |
| deep tendrils @8192 | 3 | PASS | 0 | `16.247` | `127628.03` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run3.log` |
| deep tendrils @8192 | 4 | PASS | 0 | `16.245` | `127643.95` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run4.log` |
| deep tendrils @8192 | 5 | PASS | 0 | `16.247` | `127628.61` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run5.log` |
| deep tendrils @8192 | 6 | PASS | 1 | `18.684` | `110979.83` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run6.log` |
| deep tendrils @8192 | 7 | PASS | 0 | `16.247` | `127628.14` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run7.log` |
| deep tendrils @8192 | 8 | PASS | 0 | `16.249` | `127612.50` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run8.log` |
| deep tendrils @8192 | 9 | PASS | 0 | `16.244` | `127652.24` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run9.log` |
| deep tendrils @8192 | 10 | PASS | 1 | `18.565` | `111696.13` | 2072027/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_tendrils_8192_run10.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `41.359` | `50136.17` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run1.log` |
| deep mini-brot @8192 | 2 | PASS | 0 | `41.359` | `50136.89` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run2.log` |
| deep mini-brot @8192 | 3 | PASS | 1 | `46.169` | `44913.49` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run3.log` |
| deep mini-brot @8192 | 4 | PASS | 0 | `41.363` | `50132.11` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run4.log` |
| deep mini-brot @8192 | 5 | PASS | 0 | `41.361` | `50134.15` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run5.log` |
| deep mini-brot @8192 | 6 | PASS | 0 | `41.360` | `50135.66` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run6.log` |
| deep mini-brot @8192 | 7 | PASS | 0 | `41.363` | `50132.00` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run7.log` |
| deep mini-brot @8192 | 8 | PASS | 0 | `41.362` | `50133.19` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run8.log` |
| deep mini-brot @8192 | 9 | PASS | 1 | `46.074` | `45005.64` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run9.log` |
| deep mini-brot @8192 | 10 | PASS | 0 | `41.359` | `50136.98` | 2058166/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_mini_brot_8192_run10.log` |
| deep Seahorse @1024 | 1 | PASS | 1 | `20.503` | `101136.12` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run1.log` |
| deep Seahorse @1024 | 2 | PASS | 0 | `18.450` | `112391.01` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run2.log` |
| deep Seahorse @1024 | 3 | PASS | 0 | `18.450` | `112391.17` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run3.log` |
| deep Seahorse @1024 | 4 | PASS | 0 | `18.452` | `112378.89` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run4.log` |
| deep Seahorse @1024 | 5 | PASS | 0 | `18.450` | `112391.16` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run5.log` |
| deep Seahorse @1024 | 6 | PASS | 0 | `18.454` | `112366.83` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run6.log` |
| deep Seahorse @1024 | 7 | PASS | 2 | `22.590` | `91794.17` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run7.log` |
| deep Seahorse @1024 | 8 | PASS | 0 | `18.453` | `112372.95` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run8.log` |
| deep Seahorse @1024 | 9 | PASS | 0 | `18.450` | `112391.29` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run9.log` |
| deep Seahorse @1024 | 10 | PASS | 0 | `18.453` | `112372.84` | 2049714/2073600 | `python/host_tile_stability_bench/workers6_100mhz_deep_seahorse_1024_run10.log` |
