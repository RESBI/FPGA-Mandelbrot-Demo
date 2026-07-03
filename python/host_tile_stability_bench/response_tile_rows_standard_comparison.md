# Response Tile Row-Split Standard Scene Comparison

- Scene: `standard @64`
- Image: `1920x1080`
- Host/compute tile: `1920x120`
- UART: `12 Mbaud`
- FPGA: VMC_RTSB ZU4EV, `12 workers / 8 contexts`, `200 MHz`
- Runs per valid split count: `10`

This compares the build-time `RESPONSE_TILE_ROW_SPLITS=M` setting. Each retry tile spans the full compute tile width and covers a slice of the compute tile height. The host still receives one full compute tile response, but checksum/retry recovery is localized to the failed row-split retry tile.

## Summary

| Row splits M | Retry tile shape | Build | Standard result | Retry events | Mean FPGA s | Mean pps | Clean-run mean pps | Notes |
|---:|---|---|---:|---:|---:|---:|---:|---|
| `1` | `1920x120` | PASS | 10/10 | 1 | `6.886` | `490486.30` | `538245.40` | One full-tile retry produced a 34.187s tail. |
| `2` | `1920x60` | PASS | invalid | 216 before abort | invalid | invalid | invalid | Tested before host failure classification fix; logs show systematic incomplete payloads, so the apparent PASS results are not valid. |
| `4` | `1920x30` | PASS | 0/10 | 40 | Fail | Fail | Fail | Re-run after host fix; first standard compute tile loses framing and fails after retries. Small `160x120` verify still passes. |
| `8` | `1920x15` | PASS | 10/10 | 0 | `3.718` | `557751.55` | `557751.55` | Stable default candidate. |
| `15` | `1920x8` | PASS | 10/10 | 1 | `3.807` | `547351.22` | `559033.23` | One localized retry; timing margin was thin, about `WNS=0.009ns`. |
| `30` | `1920x4` | PASS | 10/10 | 2 | `3.898` | `536672.13` | `560126.07` | Two localized retries; clean runs are fastest but retry exposure is higher. |

## PPS Ranking

Whole-system mean pps, including retry tails:

| Rank | Row splits M | Mean pps | Delta vs M=8 |
|---:|---:|---:|---:|
| 1 | `8` | `557751.55` | baseline |
| 2 | `15` | `547351.22` | `-1.86%` |
| 3 | `30` | `536672.13` | `-3.78%` |
| 4 | `1` | `490486.30` | `-12.06%` |

Clean-run mean pps, excluding runs with retry events:

| Rank | Row splits M | Clean-run mean pps | Delta vs M=8 |
|---:|---:|---:|---:|
| 1 | `30` | `560126.07` | `+0.43%` |
| 2 | `15` | `559033.23` | `+0.23%` |
| 3 | `8` | `557751.55` | baseline |
| 4 | `1` | `538245.40` | `-3.50%` |

## Interpretation

- `M=8` is the best practical default from this sweep: it passed 10/10 with zero retry events and no retry-tail penalty.
- `M=15` and `M=30` reduce clean-link transmit overhead slightly, but the 10-run whole-system mean is lower because localized retries occurred.
- `M=30` has the highest clean-run pps, but it creates 30 checksum packets per compute tile and saw 2 retry events in 10 runs.
- `M=1` has less header overhead but poor recovery granularity; one full compute-tile retry dominated the 10-run mean.
- `M=2` and `M=4` should not be selected. `M=2` data was gathered before fixing host failure classification and shows repeated incomplete payloads; `M=4` was re-run after the host fix and failed 10/10 on the standard scene.

## Source Summaries

- `python/host_tile_stability_bench/response_tile_rows_standard_m1.md`
- `python/host_tile_stability_bench/response_tile_rows_standard_m2.md`
- `python/host_tile_stability_bench/response_tile_rows_standard_m4.md`
- `python/host_tile_stability_bench/response_tile_rows_standard_m8.md`
- `python/host_tile_stability_bench/response_tile_rows_standard_m15.md`
- `python/host_tile_stability_bench/response_tile_rows_standard_m30.md`
