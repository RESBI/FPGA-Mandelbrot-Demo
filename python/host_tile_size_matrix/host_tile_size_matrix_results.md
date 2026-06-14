# Host Tile Size Matrix

- Resolution: `1920x1080`
- UART baud: `12000000`
- Runs: one run per scene and tile size
- Verification: disabled by default; this matrix measures FPGA/transport elapsed time

## By Scene

| Scene | Tile | Host tiles/frame | Status | Retry events | FPGA s | pps |
|---|---:|---:|---|---:|---:|---:|
| fast escape @128 | `80x60` | 432 | PASS | 0 | `13.433` | `154363.40` |
| fast escape @128 | `320x120` | 54 | PASS | 1 | `6.992` | `296574.69` |
| fast escape @128 | `960x120` | 18 | PASS | 0 | `5.597` | `370479.83` |
| fast escape @128 | `1920x120` | 9 | PASS | 0 | `4.845` | `428018.56` |
| fast escape @128 | `1920x240` | 5 | PASS | 0 | `4.759` | `435684.75` |
| standard @64 | `80x60` | 432 | PASS | 0 | `12.977` | `159793.15` |
| standard @64 | `320x120` | 54 | PASS | 1 | `6.491` | `319454.03` |
| standard @64 | `960x120` | 18 | PASS | 0 | `4.641` | `446829.80` |
| standard @64 | `1920x120` | 9 | PASS | 1 | `5.450` | `380460.83` |
| standard @64 | `1920x240` | 5 | PASS | 0 | `4.355` | `476132.62` |
| Seahorse zoom @512 | `80x60` | 432 | PASS | 0 | `24.975` | `83027.43` |
| Seahorse zoom @512 | `320x120` | 54 | PASS | 1 | `18.605` | `111454.73` |
| Seahorse zoom @512 | `960x120` | 18 | PASS | 0 | `17.231` | `120341.89` |
| Seahorse zoom @512 | `1920x120` | 9 | PASS | 0 | `17.085` | `121367.92` |
| Seahorse zoom @512 | `1920x240` | 5 | PASS | 0 | `16.951` | `122328.78` |
| deep tendrils @8192 | `80x60` | 432 | PASS | 0 | `40.828` | `50788.35` |
| deep tendrils @8192 | `320x120` | 54 | PASS | 0 | `33.966` | `61049.00` |
| deep tendrils @8192 | `960x120` | 18 | PASS | 0 | `33.355` | `62167.04` |
| deep tendrils @8192 | `1920x120` | 9 | PASS | 1 | `37.524` | `55260.36` |
| deep tendrils @8192 | `1920x240` | 5 | PASS | 0 | `33.077` | `62690.67` |
| deep mini-brot @8192 | `80x60` | 432 | PASS | 0 | `91.297` | `22712.76` |
| deep mini-brot @8192 | `320x120` | 54 | PASS | 0 | `84.214` | `24622.84` |
| deep mini-brot @8192 | `960x120` | 18 | PASS | 0 | `83.505` | `24832.16` |
| deep mini-brot @8192 | `1920x120` | 9 | PASS | 0 | `83.280` | `24899.18` |
| deep mini-brot @8192 | `1920x240` | 5 | PASS | 0 | `83.179` | `24929.33` |
| deep Seahorse @1024 | `80x60` | 432 | PASS | 0 | `44.215` | `46898.41` |
| deep Seahorse @1024 | `320x120` | 54 | PASS | 0 | `37.236` | `55687.48` |
| deep Seahorse @1024 | `960x120` | 18 | PASS | 0 | `36.534` | `56757.75` |
| deep Seahorse @1024 | `1920x120` | 9 | PASS | 0 | `36.340` | `57061.07` |
| deep Seahorse @1024 | `1920x240` | 5 | PASS | 0 | `36.243` | `57213.83` |

## By Tile Size

| Tile | Host tiles/frame | Passed scenes | Total FPGA s | Mean pps | Retry events |
|---:|---:|---:|---:|---:|---:|
| `80x60` | 432 | 6/6 | `227.725` | `86263.92` | 0 |
| `320x120` | 54 | 6/6 | `187.504` | `144807.13` | 3 |
| `960x120` | 18 | 6/6 | `180.863` | `180234.74` | 0 |
| `1920x120` | 9 | 6/6 | `184.524` | `177844.65` | 2 |
| `1920x240` | 5 | 6/6 | `178.564` | `196496.66` | 0 |
