# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `10`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`
- Run tag: `zu4ev200m_c12ctx8_10run`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 200MHz 6w/4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 10/10 | 0/10 | 4 | `4.563` | `4.146` | `7.261` | `1.002` | `21.96%` | `468446.75` | `1.017x` |
| standard @64 | 10/10 | 10/10 | 2 | `4.353` | `4.141` | `5.191` | `0.438` | `10.06%` | `480268.18` | `1.065x` |
| Seahorse zoom @512 | 10/10 | 0/10 | 2 | `4.499` | `4.288` | `6.371` | `0.658` | `14.62%` | `467436.73` | `1.270x` |
| deep tendrils @8192 | 10/10 | 0/10 | 3 | `4.739` | `4.417` | `5.492` | `0.511` | `10.79%` | `441838.90` | `1.808x` |
| deep mini-brot @8192 | 10/10 | 0/10 | 6 | `10.146` | `9.181` | `12.295` | `1.107` | `10.91%` | `206484.60` | `2.066x` |
| deep Seahorse @1024 | 10/10 | 0/10 | 2 | `4.967` | `4.754` | `5.805` | `0.441` | `8.89%` | `420129.06` | `1.946x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 3 | `7.261` | `285564.89` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run1.log` |
| fast escape @128 | 2 | PASS | 0 | `4.150` | `499666.17` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run2.log` |
| fast escape @128 | 3 | PASS | 0 | `4.160` | `498455.75` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run3.log` |
| fast escape @128 | 4 | PASS | 0 | `4.147` | `500065.09` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run4.log` |
| fast escape @128 | 5 | PASS | 0 | `4.147` | `500066.20` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run5.log` |
| fast escape @128 | 6 | PASS | 0 | `4.146` | `500164.31` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run6.log` |
| fast escape @128 | 7 | PASS | 0 | `4.146` | `500135.36` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run7.log` |
| fast escape @128 | 8 | PASS | 0 | `4.146` | `500193.88` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run8.log` |
| fast escape @128 | 9 | PASS | 0 | `4.146` | `500108.13` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run9.log` |
| fast escape @128 | 10 | PASS | 1 | `5.183` | `400047.68` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_fast_escape_128_run10.log` |
| standard @64 | 1 | PASS | 0 | `4.141` | `500766.98` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run1.log` |
| standard @64 | 2 | PASS | 0 | `4.147` | `500050.24` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run2.log` |
| standard @64 | 3 | PASS | 0 | `4.142` | `500678.92` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run3.log` |
| standard @64 | 4 | PASS | 0 | `4.142` | `500662.71` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run4.log` |
| standard @64 | 5 | PASS | 0 | `4.142` | `500674.02` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run5.log` |
| standard @64 | 6 | PASS | 0 | `4.157` | `498847.11` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run6.log` |
| standard @64 | 7 | PASS | 1 | `5.176` | `400612.40` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run7.log` |
| standard @64 | 8 | PASS | 0 | `4.144` | `500408.63` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run8.log` |
| standard @64 | 9 | PASS | 0 | `4.143` | `500543.96` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run9.log` |
| standard @64 | 10 | PASS | 1 | `5.191` | `399436.83` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_standard_64_run10.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `4.290` | `483367.13` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run1.log` |
| Seahorse zoom @512 | 2 | PASS | 0 | `4.289` | `483500.49` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run2.log` |
| Seahorse zoom @512 | 3 | PASS | 0 | `4.304` | `481748.29` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run3.log` |
| Seahorse zoom @512 | 4 | PASS | 0 | `4.288` | `483582.60` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run4.log` |
| Seahorse zoom @512 | 5 | PASS | 2 | `6.371` | `325495.75` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run5.log` |
| Seahorse zoom @512 | 6 | PASS | 0 | `4.291` | `483199.24` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run6.log` |
| Seahorse zoom @512 | 7 | PASS | 0 | `4.290` | `483384.82` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run7.log` |
| Seahorse zoom @512 | 8 | PASS | 0 | `4.289` | `483480.02` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run8.log` |
| Seahorse zoom @512 | 9 | PASS | 0 | `4.290` | `483310.88` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run9.log` |
| Seahorse zoom @512 | 10 | PASS | 0 | `4.291` | `483298.08` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_seahorse_zoom_512_run10.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `4.427` | `468350.11` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run1.log` |
| deep tendrils @8192 | 2 | PASS | 0 | `4.420` | `469118.29` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run2.log` |
| deep tendrils @8192 | 3 | PASS | 0 | `4.419` | `469218.13` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run3.log` |
| deep tendrils @8192 | 4 | PASS | 0 | `4.420` | `469155.10` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run4.log` |
| deep tendrils @8192 | 5 | PASS | 0 | `4.417` | `469511.41` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run5.log` |
| deep tendrils @8192 | 6 | PASS | 1 | `5.492` | `377560.87` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run6.log` |
| deep tendrils @8192 | 7 | PASS | 1 | `5.470` | `379070.39` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run7.log` |
| deep tendrils @8192 | 8 | PASS | 1 | `5.477` | `378623.98` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run8.log` |
| deep tendrils @8192 | 9 | PASS | 0 | `4.427` | `468448.85` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run9.log` |
| deep tendrils @8192 | 10 | PASS | 0 | `4.418` | `469331.92` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_tendrils_8192_run10.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `9.183` | `225809.37` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run1.log` |
| deep mini-brot @8192 | 2 | PASS | 1 | `10.873` | `190717.28` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run2.log` |
| deep mini-brot @8192 | 3 | PASS | 0 | `9.183` | `225816.75` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run3.log` |
| deep mini-brot @8192 | 4 | PASS | 0 | `9.185` | `225770.45` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run4.log` |
| deep mini-brot @8192 | 5 | PASS | 1 | `10.873` | `190702.91` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run5.log` |
| deep mini-brot @8192 | 6 | PASS | 0 | `9.181` | `225857.56` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run6.log` |
| deep mini-brot @8192 | 7 | PASS | 1 | `10.747` | `192948.62` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run7.log` |
| deep mini-brot @8192 | 8 | PASS | 2 | `12.295` | `168655.06` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run8.log` |
| deep mini-brot @8192 | 9 | PASS | 0 | `9.187` | `225703.80` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run9.log` |
| deep mini-brot @8192 | 10 | PASS | 1 | `10.752` | `192864.23` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_mini_brot_8192_run10.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `4.757` | `435881.87` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run1.log` |
| deep Seahorse @1024 | 2 | PASS | 0 | `4.754` | `436136.02` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run2.log` |
| deep Seahorse @1024 | 3 | PASS | 0 | `4.769` | `434853.67` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run3.log` |
| deep Seahorse @1024 | 4 | PASS | 0 | `4.757` | `435922.15` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run4.log` |
| deep Seahorse @1024 | 5 | PASS | 1 | `5.804` | `357281.35` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run5.log` |
| deep Seahorse @1024 | 6 | PASS | 0 | `4.754` | `436142.13` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run6.log` |
| deep Seahorse @1024 | 7 | PASS | 1 | `5.805` | `357216.08` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run7.log` |
| deep Seahorse @1024 | 8 | PASS | 0 | `4.760` | `435616.95` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run8.log` |
| deep Seahorse @1024 | 9 | PASS | 0 | `4.756` | `436038.75` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run9.log` |
| deep Seahorse @1024 | 10 | PASS | 0 | `4.754` | `436201.65` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_10run_deep_seahorse_1024_run10.log` |
