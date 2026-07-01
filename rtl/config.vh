`ifndef CONFIG_VH
`define CONFIG_VH

// Central RTL configuration defaults. Build scripts may still override module
// parameters with Vivado generics; these macros define the source defaults.

`ifndef CFG_CLK_HZ
`define CFG_CLK_HZ 200000000
`endif

`ifndef CFG_DIRECT_200MHZ
`define CFG_DIRECT_200MHZ 1
`endif

`ifndef CFG_UART_BAUD
`define CFG_UART_BAUD 12000000
`endif

`ifndef CFG_UART_ACC_WIDTH
`define CFG_UART_ACC_WIDTH 32
`endif

`ifndef CFG_CORE_COUNT
`define CFG_CORE_COUNT 12
`endif

`ifndef CFG_CORE_FIFO_DEPTH
`define CFG_CORE_FIFO_DEPTH 4096
`endif

`ifndef CFG_OUTPUT_FIFO_DEPTH
`define CFG_OUTPUT_FIFO_DEPTH 1024
`endif

`ifndef CFG_RESPONSE_TILE_COLS
`define CFG_RESPONSE_TILE_COLS 64
`endif

`ifndef CFG_RESPONSE_TILE_GAP_CYCLES
`define CFG_RESPONSE_TILE_GAP_CYCLES 1000
`endif

`ifndef CFG_SCHED_MODE
`define CFG_SCHED_MODE 1
`endif

`ifndef CFG_DYNAMIC_OWNER_DEPTH
`define CFG_DYNAMIC_OWNER_DEPTH 4096
`endif

`ifndef CFG_WORKER_CONTEXTS
`define CFG_WORKER_CONTEXTS 8
`endif

`ifndef CFG_WORKER_ADD_UNITS
`define CFG_WORKER_ADD_UNITS 1
`endif

`ifndef CFG_WORKER_MUL_UNITS
`define CFG_WORKER_MUL_UNITS 1
`endif

`endif // CONFIG_VH
