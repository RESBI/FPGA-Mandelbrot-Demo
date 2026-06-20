# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `10`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`
- Run tag: `workers8_100mhz`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 10/10 | 0/10 | 4 | `5.141` | `4.692` | `6.938` | `0.783` | `15.23%` | `410573.69` | `0.911x` |
| standard @64 | 10/10 | 10/10 | 1 | `4.805` | `4.692` | `5.803` | `0.351` | `7.30%` | `433365.36` | `1.203x` |
| Seahorse zoom @512 | 10/10 | 0/10 | 2 | `7.450` | `7.217` | `8.381` | `0.489` | `6.56%` | `279322.03` | `1.320x` |
| deep tendrils @8192 | 10/10 | 0/10 | 1 | `12.660` | `12.454` | `14.504` | `0.648` | `5.12%` | `164136.95` | `1.396x` |
| deep mini-brot @8192 | 10/10 | 0/10 | 1 | `31.785` | `31.337` | `35.757` | `1.396` | `4.39%` | `65340.46` | `1.389x` |
| deep Seahorse @1024 | 10/10 | 0/10 | 1 | `14.319` | `14.117` | `16.118` | `0.632` | `4.41%` | `145041.76` | `1.394x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 0 | `4.698` | `441413.72` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run1.log` |
| fast escape @128 | 2 | PASS | 0 | `4.692` | `441970.50` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run2.log` |
| fast escape @128 | 3 | PASS | 1 | `5.809` | `356970.02` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run3.log` |
| fast escape @128 | 4 | PASS | 0 | `4.694` | `441779.04` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run4.log` |
| fast escape @128 | 5 | PASS | 0 | `4.692` | `441967.09` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run5.log` |
| fast escape @128 | 6 | PASS | 0 | `4.694` | `441776.19` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run6.log` |
| fast escape @128 | 7 | PASS | 0 | `4.693` | `441878.76` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run7.log` |
| fast escape @128 | 8 | PASS | 2 | `6.938` | `298883.00` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run8.log` |
| fast escape @128 | 9 | PASS | 1 | `5.805` | `357216.67` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run9.log` |
| fast escape @128 | 10 | PASS | 0 | `4.693` | `441881.93` | 2073588/2073600 | `python/host_tile_stability_bench/workers8_100mhz_fast_escape_128_run10.log` |
| standard @64 | 1 | PASS | 0 | `4.695` | `441681.01` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run1.log` |
| standard @64 | 2 | PASS | 0 | `4.694` | `441784.87` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run2.log` |
| standard @64 | 3 | PASS | 0 | `4.695` | `441682.88` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run3.log` |
| standard @64 | 4 | PASS | 0 | `4.692` | `441971.42` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run4.log` |
| standard @64 | 5 | PASS | 0 | `4.693` | `441884.70` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run5.log` |
| standard @64 | 6 | PASS | 0 | `4.692` | `441976.91` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run6.log` |
| standard @64 | 7 | PASS | 0 | `4.694` | `441789.15` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run7.log` |
| standard @64 | 8 | PASS | 0 | `4.694` | `441786.62` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run8.log` |
| standard @64 | 9 | PASS | 1 | `5.803` | `357311.59` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run9.log` |
| standard @64 | 10 | PASS | 0 | `4.694` | `441784.48` | 2073600/2073600 | `python/host_tile_stability_bench/workers8_100mhz_standard_64_run10.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `7.218` | `287298.52` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run1.log` |
| Seahorse zoom @512 | 2 | PASS | 0 | `7.220` | `287182.97` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run2.log` |
| Seahorse zoom @512 | 3 | PASS | 0 | `7.217` | `287307.70` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run3.log` |
| Seahorse zoom @512 | 4 | PASS | 1 | `8.373` | `247661.19` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run4.log` |
| Seahorse zoom @512 | 5 | PASS | 0 | `7.218` | `287267.15` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run5.log` |
| Seahorse zoom @512 | 6 | PASS | 0 | `7.219` | `287228.56` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run6.log` |
| Seahorse zoom @512 | 7 | PASS | 0 | `7.218` | `287267.61` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run7.log` |
| Seahorse zoom @512 | 8 | PASS | 1 | `8.381` | `247431.41` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run8.log` |
| Seahorse zoom @512 | 9 | PASS | 0 | `7.217` | `287308.09` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run9.log` |
| Seahorse zoom @512 | 10 | PASS | 0 | `7.218` | `287267.12` | 2072760/2073600 | `python/host_tile_stability_bench/workers8_100mhz_seahorse_zoom_512_run10.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `12.455` | `166486.57` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run1.log` |
| deep tendrils @8192 | 2 | PASS | 0 | `12.456` | `166478.39` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run2.log` |
| deep tendrils @8192 | 3 | PASS | 1 | `14.504` | `142968.65` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run3.log` |
| deep tendrils @8192 | 4 | PASS | 0 | `12.455` | `166491.24` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run4.log` |
| deep tendrils @8192 | 5 | PASS | 0 | `12.456` | `166478.99` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run5.log` |
| deep tendrils @8192 | 6 | PASS | 0 | `12.455` | `166491.58` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run6.log` |
| deep tendrils @8192 | 7 | PASS | 0 | `12.455` | `166491.71` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run7.log` |
| deep tendrils @8192 | 8 | PASS | 0 | `12.455` | `166491.11` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run8.log` |
| deep tendrils @8192 | 9 | PASS | 0 | `12.454` | `166499.12` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run9.log` |
| deep tendrils @8192 | 10 | PASS | 0 | `12.455` | `166492.13` | 2072027/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_tendrils_8192_run10.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `31.343` | `66159.18` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run1.log` |
| deep mini-brot @8192 | 2 | PASS | 0 | `31.341` | `66163.49` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run2.log` |
| deep mini-brot @8192 | 3 | PASS | 0 | `31.342` | `66161.40` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run3.log` |
| deep mini-brot @8192 | 4 | PASS | 0 | `31.337` | `66170.83` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run4.log` |
| deep mini-brot @8192 | 5 | PASS | 0 | `31.352` | `66139.85` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run5.log` |
| deep mini-brot @8192 | 6 | PASS | 1 | `35.757` | `57990.98` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run6.log` |
| deep mini-brot @8192 | 7 | PASS | 0 | `31.351` | `66141.95` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run7.log` |
| deep mini-brot @8192 | 8 | PASS | 0 | `31.349` | `66146.16` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run8.log` |
| deep mini-brot @8192 | 9 | PASS | 0 | `31.339` | `66167.28` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run9.log` |
| deep mini-brot @8192 | 10 | PASS | 0 | `31.341` | `66163.51` | 2058166/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_mini_brot_8192_run10.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `14.120` | `146850.41` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run1.log` |
| deep Seahorse @1024 | 2 | PASS | 0 | `14.120` | `146850.73` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run2.log` |
| deep Seahorse @1024 | 3 | PASS | 0 | `14.118` | `146872.48` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run3.log` |
| deep Seahorse @1024 | 4 | PASS | 0 | `14.119` | `146870.33` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run4.log` |
| deep Seahorse @1024 | 5 | PASS | 0 | `14.121` | `146840.85` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run5.log` |
| deep Seahorse @1024 | 6 | PASS | 0 | `14.120` | `146851.60` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run6.log` |
| deep Seahorse @1024 | 7 | PASS | 0 | `14.119` | `146861.99` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run7.log` |
| deep Seahorse @1024 | 8 | PASS | 0 | `14.117` | `146882.34` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run8.log` |
| deep Seahorse @1024 | 9 | PASS | 0 | `14.117` | `146882.80` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run9.log` |
| deep Seahorse @1024 | 10 | PASS | 1 | `16.118` | `128654.09` | 2049714/2073600 | `python/host_tile_stability_bench/workers8_100mhz_deep_seahorse_1024_run10.log` |
