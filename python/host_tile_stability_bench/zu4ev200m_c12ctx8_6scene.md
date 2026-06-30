# Host-Tiled 12 Mbaud Stability Benchmark

- Runs per scene: `1`
- Host tile: `1920x120`
- Tile retries: `3`
- UART baud: `12000000`
- Run tag: `zu4ev200m_c12ctx8`

## Summary

| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| fast escape @128 | 1/1 | 0/1 | 0 | `4.150` | `4.150` | `4.150` | `0.000` | `0.00%` | `499705.08` | `1.128x` |
| standard @64 | 1/1 | 1/1 | 0 | `4.143` | `4.143` | `4.143` | `0.000` | `0.00%` | `500531.67` | `1.396x` |
| Seahorse zoom @512 | 1/1 | 0/1 | 0 | `4.289` | `4.289` | `4.289` | `0.000` | `0.00%` | `483464.75` | `2.293x` |
| deep tendrils @8192 | 1/1 | 0/1 | 0 | `4.418` | `4.418` | `4.418` | `0.000` | `0.00%` | `469374.80` | `4.001x` |
| deep mini-brot @8192 | 1/1 | 0/1 | 0 | `9.183` | `9.183` | `9.183` | `0.000` | `0.00%` | `225810.49` | `4.807x` |
| deep Seahorse @1024 | 1/1 | 0/1 | 0 | `4.767` | `4.767` | `4.767` | `0.000` | `0.00%` | `435016.18` | `4.188x` |

## Runs

| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |
|---|---:|---|---:|---:|---:|---|---|
| fast escape @128 | 1 | PASS | 0 | `4.150` | `499705.08` | 2073588/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_fast_escape_128_run1.log` |
| standard @64 | 1 | PASS | 0 | `4.143` | `500531.67` | 2073600/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_standard_64_run1.log` |
| Seahorse zoom @512 | 1 | PASS | 0 | `4.289` | `483464.75` | 2072760/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_seahorse_zoom_512_run1.log` |
| deep tendrils @8192 | 1 | PASS | 0 | `4.418` | `469374.80` | 2072027/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_deep_tendrils_8192_run1.log` |
| deep mini-brot @8192 | 1 | PASS | 0 | `9.183` | `225810.49` | 2058166/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_deep_mini_brot_8192_run1.log` |
| deep Seahorse @1024 | 1 | PASS | 0 | `4.767` | `435016.18` | 2049714/2073600 | `python/host_tile_stability_bench/zu4ev200m_c12ctx8_deep_seahorse_1024_run1.log` |
