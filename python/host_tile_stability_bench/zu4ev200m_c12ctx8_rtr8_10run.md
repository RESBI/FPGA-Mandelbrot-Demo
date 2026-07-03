# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `10`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`
- Run tag: `zu4ev200m_c12ctx8_rtr8`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 10/10 | 0/10 | 3 | `6.984` | `3.721` | `34.398` | `9.641` | `138.03%` | `484383.85` | `0.670x` |
| standard @64 | 10/10 | 10/10 | 2 | `3.914` | `3.716` | `4.705` | `0.412` | `10.53%` | `534429.78` | `1.477x` |
| Seahorse zoom @512 | 10/10 | 0/10 | 3 | `4.168` | `3.864` | `4.875` | `0.484` | `11.62%` | `503091.85` | `2.360x` |
| deep tendrils @8192 | 4/4 | 0/4 | 2 | `11.918` | `3.992` | `35.692` | `15.849` | `132.99%` | `403965.51` | `1.483x` |
| deep mini-brot @8192 | 0/0 | 0/0 | 0 | `Fail` | `Fail` | `Fail` | `Fail` | `Fail%` | `Fail` | `Failx` |
| deep Seahorse @1024 | 0/0 | 0/0 | 0 | `Fail` | `Fail` | `Fail` | `Fail` | `Fail%` | `Fail` | `Failx` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 0 | `3.721` | `557323.91` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run1.log` |
| fast escape @128 | 2 | PASS | 1 | `4.703` | `440928.84` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run2.log` |
| fast escape @128 | 3 | PASS | 0 | `3.721` | `557321.24` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run3.log` |
| fast escape @128 | 4 | PASS | 1 | `4.695` | `441678.80` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run4.log` |
| fast escape @128 | 5 | PASS | 0 | `3.721` | `557324.67` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run5.log` |
| fast escape @128 | 6 | PASS | 0 | `3.721` | `557329.15` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run6.log` |
| fast escape @128 | 7 | PASS | 0 | `3.721` | `557314.02` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run7.log` |
| fast escape @128 | 8 | PASS | 1 | `34.398` | `60282.69` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run8.log` |
| fast escape @128 | 9 | PASS | 0 | `3.722` | `557166.76` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run9.log` |
| fast escape @128 | 10 | PASS | 0 | `3.722` | `557168.43` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_fast_escape_128_run10.log` |
| standard @64 | 1 | PASS | 1 | `4.705` | `440748.31` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run1.log` |
| standard @64 | 2 | PASS | 0 | `3.718` | `557780.79` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run2.log` |
| standard @64 | 3 | PASS | 1 | `4.688` | `442297.42` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run3.log` |
| standard @64 | 4 | PASS | 0 | `3.716` | `557977.23` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run4.log` |
| standard @64 | 5 | PASS | 0 | `3.724` | `556853.92` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run5.log` |
| standard @64 | 6 | PASS | 0 | `3.717` | `557920.67` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run6.log` |
| standard @64 | 7 | PASS | 0 | `3.717` | `557914.77` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run7.log` |
| standard @64 | 8 | PASS | 0 | `3.718` | `557705.93` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run8.log` |
| standard @64 | 9 | PASS | 0 | `3.722` | `557179.81` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run9.log` |
| standard @64 | 10 | PASS | 0 | `3.717` | `557918.98` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_standard_64_run10.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `3.866` | `536348.47` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run1.log` |
| Seahorse zoom @512 | 2 | PASS | 1 | `4.875` | `425339.94` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run2.log` |
| Seahorse zoom @512 | 3 | PASS | 0 | `3.865` | `536488.31` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run3.log` |
| Seahorse zoom @512 | 4 | PASS | 1 | `4.863` | `426409.22` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run4.log` |
| Seahorse zoom @512 | 5 | PASS | 0 | `3.872` | `535514.72` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run5.log` |
| Seahorse zoom @512 | 6 | PASS | 0 | `3.871` | `535731.97` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run6.log` |
| Seahorse zoom @512 | 7 | PASS | 0 | `3.864` | `536614.58` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run7.log` |
| Seahorse zoom @512 | 8 | PASS | 0 | `3.866` | `536343.69` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run8.log` |
| Seahorse zoom @512 | 9 | PASS | 0 | `3.866` | `536340.22` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run9.log` |
| Seahorse zoom @512 | 10 | PASS | 1 | `4.870` | `425787.40` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_seahorse_zoom_512_run10.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `3.992` | `519449.14` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deep_tendrils_8192_run1.log` |
| deep tendrils @8192 | 2 | PASS | 0 | `3.996` | `518928.35` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deep_tendrils_8192_run2.log` |
| deep tendrils @8192 | 3 | PASS | 2 | `35.692` | `58097.56` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deep_tendrils_8192_run3.log` |
| deep tendrils @8192 | 4 | PASS | 0 | `3.992` | `519386.99` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_rtr8_deep_tendrils_8192_run4.log` |
