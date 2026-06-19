# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `10`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 10/10 | 0/10 | 6 | `5.072` | `4.424` | `5.515` | `0.557` | `10.99%` | `413592.02` | `0.923x` |
| standard @64 | 10/10 | 10/10 | 6 | `5.066` | `4.416` | `5.510` | `0.557` | `11.00%` | `414046.70` | `1.141x` |
| Seahorse zoom @512 | 10/10 | 0/10 | 6 | `7.879` | `6.979` | `13.245` | `1.968` | `24.98%` | `273303.15` | `1.248x` |
| deep tendrils @8192 | 10/10 | 0/10 | 3 | `12.820` | `12.229` | `14.231` | `0.952` | `7.43%` | `162504.12` | `1.379x` |
| deep mini-brot @8192 | 10/10 | 0/10 | 2 | `31.625` | `30.861` | `34.700` | `1.604` | `5.07%` | `65709.99` | `1.396x` |
| deep Seahorse @1024 | 10/10 | 0/10 | 0 | `13.886` | `13.885` | `13.887` | `0.001` | `0.01%` | `149325.97` | `1.438x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 1 | `5.496` | `377308.95` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run1.log` |
| fast escape @128 | 2 | PASS | 1 | `5.499` | `377102.43` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run2.log` |
| fast escape @128 | 3 | PASS | 0 | `4.424` | `468754.31` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run3.log` |
| fast escape @128 | 4 | PASS | 0 | `4.424` | `468757.49` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run4.log` |
| fast escape @128 | 5 | PASS | 1 | `5.515` | `376007.62` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run5.log` |
| fast escape @128 | 6 | PASS | 1 | `5.498` | `377170.20` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run6.log` |
| fast escape @128 | 7 | PASS | 1 | `5.496` | `377308.74` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run7.log` |
| fast escape @128 | 8 | PASS | 1 | `5.515` | `376008.12` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run8.log` |
| fast escape @128 | 9 | PASS | 0 | `4.424` | `468754.42` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run9.log` |
| fast escape @128 | 10 | PASS | 0 | `4.424` | `468747.92` | 2073588/2073600 | `python/host_tile_stability_bench/fast_escape_128_run10.log` |
| standard @64 | 1 | PASS | 1 | `5.493` | `377510.21` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run1.log` |
| standard @64 | 2 | PASS | 0 | `4.419` | `469286.75` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run2.log` |
| standard @64 | 3 | PASS | 0 | `4.419` | `469285.36` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run3.log` |
| standard @64 | 4 | PASS | 0 | `4.416` | `469579.38` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run4.log` |
| standard @64 | 5 | PASS | 1 | `5.491` | `377649.40` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run5.log` |
| standard @64 | 6 | PASS | 1 | `5.506` | `376623.19` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run6.log` |
| standard @64 | 7 | PASS | 1 | `5.493` | `377495.21` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run7.log` |
| standard @64 | 8 | PASS | 0 | `4.420` | `469176.52` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run8.log` |
| standard @64 | 9 | PASS | 1 | `5.493` | `377514.69` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run9.log` |
| standard @64 | 10 | PASS | 1 | `5.510` | `376346.26` | 2073600/2073600 | `python/host_tile_stability_bench/standard_64_run10.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `6.982` | `296971.56` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run1.log` |
| Seahorse zoom @512 | 2 | PASS | 1 | `8.328` | `248976.68` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run2.log` |
| Seahorse zoom @512 | 3 | PASS | 0 | `6.981` | `297022.19` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run3.log` |
| Seahorse zoom @512 | 4 | PASS | 1 | `8.351` | `248319.26` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run4.log` |
| Seahorse zoom @512 | 5 | PASS | 4 | `13.245` | `156556.66` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run5.log` |
| Seahorse zoom @512 | 6 | PASS | 0 | `6.980` | `297062.09` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run6.log` |
| Seahorse zoom @512 | 7 | PASS | 0 | `6.979` | `297104.70` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run7.log` |
| Seahorse zoom @512 | 8 | PASS | 0 | `6.981` | `297021.86` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run8.log` |
| Seahorse zoom @512 | 9 | PASS | 0 | `6.983` | `296935.00` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run9.log` |
| Seahorse zoom @512 | 10 | PASS | 0 | `6.980` | `297061.54` | 2072760/2073600 | `python/host_tile_stability_bench/seahorse_zoom_512_run10.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `12.229` | `169568.92` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run1.log` |
| deep tendrils @8192 | 2 | PASS | 0 | `12.229` | `169567.97` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run2.log` |
| deep tendrils @8192 | 3 | PASS | 0 | `12.229` | `169568.88` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run3.log` |
| deep tendrils @8192 | 4 | PASS | 1 | `14.193` | `146100.71` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run4.log` |
| deep tendrils @8192 | 5 | PASS | 0 | `12.229` | `169568.90` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run5.log` |
| deep tendrils @8192 | 6 | PASS | 0 | `12.231` | `169540.67` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run6.log` |
| deep tendrils @8192 | 7 | PASS | 0 | `12.229` | `169569.46` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run7.log` |
| deep tendrils @8192 | 8 | PASS | 1 | `14.176` | `146276.37` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run8.log` |
| deep tendrils @8192 | 9 | PASS | 1 | `14.231` | `145711.08` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run9.log` |
| deep tendrils @8192 | 10 | PASS | 0 | `12.229` | `169568.22` | 2072027/2073600 | `python/host_tile_stability_bench/deep_tendrils_8192_run10.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `30.865` | `67183.93` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run1.log` |
| deep mini-brot @8192 | 2 | PASS | 0 | `30.861` | `67192.51` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run2.log` |
| deep mini-brot @8192 | 3 | PASS | 0 | `30.866` | `67181.66` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run3.log` |
| deep mini-brot @8192 | 4 | PASS | 0 | `30.862` | `67189.39` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run4.log` |
| deep mini-brot @8192 | 5 | PASS | 0 | `30.867` | `67179.33` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run5.log` |
| deep mini-brot @8192 | 6 | PASS | 1 | `34.700` | `59757.98` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run6.log` |
| deep mini-brot @8192 | 7 | PASS | 0 | `30.867` | `67179.37` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run7.log` |
| deep mini-brot @8192 | 8 | PASS | 0 | `30.861` | `67192.30` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run8.log` |
| deep mini-brot @8192 | 9 | PASS | 0 | `30.866` | `67180.41` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run9.log` |
| deep mini-brot @8192 | 10 | PASS | 1 | `34.639` | `59863.03` | 2058166/2073600 | `python/host_tile_stability_bench/deep_mini_brot_8192_run10.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `13.885` | `149337.11` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run1.log` |
| deep Seahorse @1024 | 2 | PASS | 0 | `13.886` | `149331.29` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run2.log` |
| deep Seahorse @1024 | 3 | PASS | 0 | `13.887` | `149315.30` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run3.log` |
| deep Seahorse @1024 | 4 | PASS | 0 | `13.887` | `149314.80` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run4.log` |
| deep Seahorse @1024 | 5 | PASS | 0 | `13.886` | `149332.31` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run5.log` |
| deep Seahorse @1024 | 6 | PASS | 0 | `13.886` | `149326.00` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run6.log` |
| deep Seahorse @1024 | 7 | PASS | 0 | `13.885` | `149336.05` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run7.log` |
| deep Seahorse @1024 | 8 | PASS | 0 | `13.886` | `149325.74` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run8.log` |
| deep Seahorse @1024 | 9 | PASS | 0 | `13.887` | `149316.06` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run9.log` |
| deep Seahorse @1024 | 10 | PASS | 0 | `13.886` | `149325.02` | 2049714/2073600 | `python/host_tile_stability_bench/deep_seahorse_1024_run10.log` |
