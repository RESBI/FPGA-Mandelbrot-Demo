// Floating point parameter definitions
// Select FP64 or FP128 via `define FP128_MODE in build script

`ifdef FP128_MODE
    `define FP_WIDTH   128
    `define FP_EXP_W   15
    `define FP_MAN_W   112
    `define FP_BIAS    16383
    `define FP_EXP_MAX 32766
    `define FP_CE_DIV  2
`else
    `define FP_WIDTH   64
    `define FP_EXP_W   11
    `define FP_MAN_W   52
    `define FP_BIAS    1023
    `define FP_EXP_MAX 2046
    `define FP_CE_DIV  2
`endif

`define FP_SIGN_IDX   (`FP_WIDTH - 1)
`define FP_EXP_HI     (`FP_WIDTH - 2)
`define FP_EXP_LO     (`FP_MAN_W)
`define FP_MAN_HI     (`FP_MAN_W - 1)
`define FP_MAN_W1     (`FP_MAN_W + 1)
