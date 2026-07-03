# Response Tile Width Standard Scene Comparison

- Scene: `standard @64`
- Frame: `1920x1080`
- Host/compute tile: `1920x120`
- Runs per response tile width: `10`
- UART baud: `12000000`
- Retry policy: full compute tile is received first; failed response checksum tiles are retried as merged local rectangles without UART drain/reset when the response stream ended cleanly.

## Summary

| Response tile cols | Split per 1920-wide row | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps | vs rt64 |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `32` | 60 | 10/10 | 40 | `8.754` | `5.656` | `14.755` | `37.27%` | `263047.56` | `0.536x` |
| `64` | 30 | 10/10 | 1 | `4.244` | `4.141` | `5.154` | `7.53%` | `490726.52` | `1.000x` |
| `240` | 8 | 10/10 | 3 | `4.113` | `3.815` | `5.787` | `16.19%` | `513607.55` | `1.047x` |
| `480` | 4 | 10/10 | 4 | `7.119` | `3.747` | `35.464` | `140.01%` | `480402.36` | `0.979x` |
| `960` | 2 | 10/10 | 0 | `3.725` | `3.724` | `3.728` | `0.04%` | `556588.74` | `1.134x` |
| `1920` | 1 | 10/10 | 0 | `3.711` | `3.709` | `3.717` | `0.08%` | `558689.48` | `1.138x` |

## Interpretation

`1920` columns was the fastest measured point for the standard scene, reaching `558689.48 pps`. In this 10-run sample it had no retries, so the reduced `TD` header/checksum/gap overhead dominated.

`960` columns was nearly identical in throughput and also had no retries. It is the best balanced point from this sweep: almost the same clean-link throughput as `1920`, but half-row retry granularity if a checksum failure occurs.

`480` columns showed one severe long-tail run (`35.464s`) despite only four retry events in total. This looks like a transport recovery outlier rather than steady-state framing cost, but it makes the 10-run mean worse than `240` and `64`.

`240` columns was the best of the original measured points before adding larger granularities. It reduces per-row response framing/checksum/gap overhead while keeping retries much smaller than the full `1920x120` compute tile.

`64` columns remained a stable smaller-granularity point. It is slower than the larger `960`/`1920` points in clean-link runs, but limits retry work to smaller row segments.

`32` columns was too fine-grained for this UART path. The extra `TD` headers/checksums/gaps and the higher number of retry events dominated the benefit of smaller retries.

For the current standard-scene behavior, use `960` when balancing throughput and retry containment. Use `1920` when optimizing for clean-link throughput and accepting full-row retry granularity.

## Source Summaries

- `python/host_tile_stability_bench/response_tile_cols_standard_rt32_nodrain.md`
- `python/host_tile_stability_bench/response_tile_cols_standard_rt64_nodrain.md`
- `python/host_tile_stability_bench/response_tile_cols_standard_rt240_nodrain.md`
- `python/host_tile_stability_bench/response_tile_cols_standard_rt480_nodrain.md`
- `python/host_tile_stability_bench/response_tile_cols_standard_rt960_nodrain.md`
- `python/host_tile_stability_bench/response_tile_cols_standard_rt1920_nodrain.md`
