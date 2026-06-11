// Generic Mandelbrot worker pipeline scheduler simulator.
//
// This is a compute-only model: it intentionally ignores UART bandwidth so it
// can estimate the FPGA-side throughput of different in-worker context counts
// and FP-unit allocations.

#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
    SCHED_DYNAMIC = 0,
    SCHED_STATIC = 1,
} sched_mode_t;

typedef enum {
    CTX_FULL = 0,
    CTX_ESCAPE = 1,
} ctx_mode_t;

typedef struct {
    int width;
    int height;
    int max_iter;
    double center_re;
    double center_im;
    double step;
    int contexts;
    int adders;
    int multipliers;
    int workers;
    int add_lat;
    int mul_lat;
    double clock_hz;
    sched_mode_t scheduler;
    int self_test;
    int verbose;
    int sweep;
    int exact;
} options_t;

typedef struct {
    int active;
    int result_valid;
    int seq;
    int iter_count;
    int full_done;
    ctx_mode_t mode;
    int phase;
    uint64_t ready_cycle;
    uint64_t last_issue_cycle;
} context_t;

static void usage(const char *prog) {
    printf("Usage: %s [host-like options] [pipeline options]\n", prog);
    printf("\nHost-like options:\n");
    printf("  --center RE IM        Complex center point (default: -0.5 0.0)\n");
    printf("  --step S              Pixel step size (default: 0.005)\n");
    printf("  --max-iter N          Maximum iterations (default: 256)\n");
    printf("  --width W             Image width (default: 160)\n");
    printf("  --height H            Image height (default: 120)\n");
    printf("  --mode fp64|fp128     Accepted for CLI compatibility; model uses double\n");
    printf("  --output PATH         Ignored, accepted for host CLI compatibility\n");
    printf("  --format FMT          Ignored, accepted for host CLI compatibility\n");
    printf("  --port COMx           Ignored, accepted for host CLI compatibility\n");
    printf("  --timeout SEC         Ignored, accepted for host CLI compatibility\n");
    printf("  --verify              Ignored, accepted for host CLI compatibility\n");
    printf("\nPipeline options:\n");
    printf("  --contexts K          Pixel contexts per worker (default: 2)\n");
    printf("  --adders A            FP adders per worker (default: 1)\n");
    printf("  --multipliers M       FP multipliers per worker (default: 1)\n");
    printf("  --workers N           Worker count (default: 4)\n");
    printf("  --add-lat N           Adder issue-to-result latency (default: 7)\n");
    printf("  --mul-lat N           Multiplier issue-to-result latency (default: 6)\n");
    printf("  --clock-hz HZ         Compute clock in Hz (default: 100000000)\n");
    printf("  --scheduler MODE      dynamic or static row assignment (default: dynamic)\n");
    printf("  --self-test           Run iteration-count checks and exit\n");
    printf("  --sweep               Run documented K/A/M configuration sweep\n");
    printf("  --exact               Use exact per-stage scheduler; intended for small frames\n");
    printf("  --verbose             Print per-worker cycle totals\n");
}

static int parse_int(const char *s, const char *name) {
    char *end = NULL;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || end == s || *end != '\0' || v < 0 || v > 2147483647L) {
        fprintf(stderr, "ERROR: invalid %s: %s\n", name, s);
        exit(2);
    }
    return (int)v;
}

static double parse_double(const char *s, const char *name) {
    char *end = NULL;
    errno = 0;
    double v = strtod(s, &end);
    if (errno || end == s || *end != '\0' || !isfinite(v)) {
        fprintf(stderr, "ERROR: invalid %s: %s\n", name, s);
        exit(2);
    }
    return v;
}

static void default_options(options_t *opt) {
    opt->width = 160;
    opt->height = 120;
    opt->max_iter = 256;
    opt->center_re = -0.5;
    opt->center_im = 0.0;
    opt->step = 0.005;
    opt->contexts = 2;
    opt->adders = 1;
    opt->multipliers = 1;
    opt->workers = 4;
    opt->add_lat = 7;
    opt->mul_lat = 6;
    opt->clock_hz = 100000000.0;
    opt->scheduler = SCHED_DYNAMIC;
    opt->self_test = 0;
    opt->verbose = 0;
    opt->sweep = 0;
    opt->exact = 0;
}

static void parse_args(int argc, char **argv, options_t *opt) {
    default_options(opt);
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "--help") || !strcmp(a, "-h")) {
            usage(argv[0]);
            exit(0);
        } else if (!strcmp(a, "--center")) {
            if (i + 2 >= argc) { fprintf(stderr, "ERROR: --center needs RE IM\n"); exit(2); }
            opt->center_re = parse_double(argv[++i], "center real");
            opt->center_im = parse_double(argv[++i], "center imag");
        } else if (!strcmp(a, "--step")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --step needs value\n"); exit(2); }
            opt->step = parse_double(argv[i], "step");
        } else if (!strcmp(a, "--max-iter")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --max-iter needs value\n"); exit(2); }
            opt->max_iter = parse_int(argv[i], "max_iter");
        } else if (!strcmp(a, "--width")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --width needs value\n"); exit(2); }
            opt->width = parse_int(argv[i], "width");
        } else if (!strcmp(a, "--height")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --height needs value\n"); exit(2); }
            opt->height = parse_int(argv[i], "height");
        } else if (!strcmp(a, "--contexts")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --contexts needs value\n"); exit(2); }
            opt->contexts = parse_int(argv[i], "contexts");
        } else if (!strcmp(a, "--adders")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --adders needs value\n"); exit(2); }
            opt->adders = parse_int(argv[i], "adders");
        } else if (!strcmp(a, "--multipliers")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --multipliers needs value\n"); exit(2); }
            opt->multipliers = parse_int(argv[i], "multipliers");
        } else if (!strcmp(a, "--workers")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --workers needs value\n"); exit(2); }
            opt->workers = parse_int(argv[i], "workers");
        } else if (!strcmp(a, "--add-lat")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --add-lat needs value\n"); exit(2); }
            opt->add_lat = parse_int(argv[i], "add latency");
        } else if (!strcmp(a, "--mul-lat")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --mul-lat needs value\n"); exit(2); }
            opt->mul_lat = parse_int(argv[i], "mul latency");
        } else if (!strcmp(a, "--clock-hz")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --clock-hz needs value\n"); exit(2); }
            opt->clock_hz = parse_double(argv[i], "clock_hz");
        } else if (!strcmp(a, "--scheduler")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --scheduler needs value\n"); exit(2); }
            if (!strcmp(argv[i], "dynamic")) opt->scheduler = SCHED_DYNAMIC;
            else if (!strcmp(argv[i], "static")) opt->scheduler = SCHED_STATIC;
            else { fprintf(stderr, "ERROR: --scheduler must be dynamic or static\n"); exit(2); }
        } else if (!strcmp(a, "--mode") || !strcmp(a, "--output") ||
                   !strcmp(a, "--format") || !strcmp(a, "--port") ||
                   !strcmp(a, "--timeout")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: %s needs value\n", a); exit(2); }
        } else if (!strcmp(a, "--verify")) {
            // Accepted for host CLI compatibility. This simulator always computes
            // the software iteration trace before scheduling it.
        } else if (!strcmp(a, "--self-test")) {
            opt->self_test = 1;
        } else if (!strcmp(a, "--sweep")) {
            opt->sweep = 1;
        } else if (!strcmp(a, "--exact")) {
            opt->exact = 1;
        } else if (!strcmp(a, "--verbose")) {
            opt->verbose = 1;
        } else {
            fprintf(stderr, "ERROR: unknown option: %s\n", a);
            exit(2);
        }
    }

    if (opt->width <= 0 || opt->height <= 0 || opt->max_iter <= 0 ||
        opt->contexts <= 0 || opt->adders <= 0 || opt->multipliers <= 0 ||
        opt->workers <= 0 || opt->add_lat <= 0 || opt->mul_lat <= 0 ||
        opt->clock_hz <= 0.0) {
        fprintf(stderr, "ERROR: dimensions, units, latencies, contexts, workers, and clock must be positive\n");
        exit(2);
    }
    if (opt->max_iter > 65535) {
        fprintf(stderr, "ERROR: max_iter must be <= 65535\n");
        exit(2);
    }
}

static int mandelbrot_iter(double c_re, double c_im, int max_iter) {
    double z_re = 0.0;
    double z_im = 0.0;
    int it = 0;
    while (it < max_iter) {
        double z_re_sq = z_re * z_re;
        double z_im_sq = z_im * z_im;
        if (z_re_sq + z_im_sq > 4.0) break;
        z_im = 2.0 * z_re * z_im + c_im;
        z_re = z_re_sq - z_im_sq + c_re;
        it++;
    }
    return it;
}

static int *generate_frame_iters(const options_t *opt, uint64_t *iter_sum_out) {
    uint64_t pixels = (uint64_t)opt->width * (uint64_t)opt->height;
    if (pixels > (uint64_t)SIZE_MAX / sizeof(int)) {
        fprintf(stderr, "ERROR: image too large\n");
        exit(2);
    }
    int *iters = (int *)malloc((size_t)pixels * sizeof(int));
    if (!iters) {
        fprintf(stderr, "ERROR: out of memory\n");
        exit(2);
    }

    int half_w = (opt->width - 1) >> 1;
    int half_h = (opt->height - 1) >> 1;
    double re_start = opt->center_re - (double)half_w * opt->step;
    double im_start = opt->center_im + (double)half_h * opt->step;
    uint64_t iter_sum = 0;
    for (int y = 0; y < opt->height; y++) {
        double c_im = im_start - (double)y * opt->step;
        double c_re = re_start;
        for (int x = 0; x < opt->width; x++) {
            int it = mandelbrot_iter(c_re, c_im, opt->max_iter);
            iters[(uint64_t)y * (uint64_t)opt->width + (uint64_t)x] = it;
            iter_sum += (uint64_t)it;
            c_re += opt->step;
        }
    }
    *iter_sum_out = iter_sum;
    return iters;
}

static int run_self_test(void) {
    struct {
        double re;
        double im;
        int max_iter;
        int expected;
    } tests[] = {
        {2.5, 0.0, 256, 1},
        {2.6, 0.0, 256, 1},
        {3.0, 0.0, 256, 1},
        {4.1, 0.0, 256, 1},
        {0.0, 0.0, 256, 256},
        {-1.0, 0.0, 256, 256},
    };
    int ok = 1;
    for (size_t i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
        int got = mandelbrot_iter(tests[i].re, tests[i].im, tests[i].max_iter);
        if (got != tests[i].expected) {
            fprintf(stderr, "SELF-TEST FAIL c=(%.17g,%.17g) got=%d expected=%d\n",
                    tests[i].re, tests[i].im, got, tests[i].expected);
            ok = 0;
        }
    }
    if (ok) printf("SELF-TEST PASS: iteration-count checks matched expected values\n");
    return ok ? 0 : 1;
}

static void load_context(context_t *ctx, int seq, int iter_count, int max_iter, uint64_t cycle) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->active = 1;
    ctx->seq = seq;
    ctx->iter_count = iter_count;
    ctx->mode = (iter_count == 0 && iter_count < max_iter) ? CTX_ESCAPE : CTX_FULL;
    ctx->phase = 0;
    ctx->ready_cycle = cycle;
    ctx->last_issue_cycle = UINT64_MAX;
}

static void normalize_context(context_t *ctx, int max_iter) {
    if (!ctx->active || ctx->result_valid) return;

    for (;;) {
        if (ctx->mode == CTX_FULL && ctx->phase >= 7) {
            ctx->full_done++;
            if (ctx->full_done >= ctx->iter_count) {
                if (ctx->iter_count >= max_iter) {
                    ctx->result_valid = 1;
                    return;
                }
                ctx->mode = CTX_ESCAPE;
                ctx->phase = 0;
                return;
            }
            ctx->phase = 0;
            return;
        }
        if (ctx->mode == CTX_ESCAPE && ctx->phase >= 3) {
            ctx->result_valid = 1;
            return;
        }
        return;
    }
}

static void stage_needs(const context_t *ctx, int *need_m, int *need_a) {
    *need_m = 0;
    *need_a = 0;
    if (ctx->mode == CTX_FULL) {
        switch (ctx->phase) {
        case 0: *need_m = 1; break;
        case 1: *need_m = 1; break;
        case 2: *need_m = 1; *need_a = 1; break;
        case 3: *need_a = 1; break;
        case 4: *need_a = 1; break;
        case 5: *need_a = 1; break;
        case 6: *need_a = 1; break;
        default: break;
        }
    } else {
        switch (ctx->phase) {
        case 0: *need_m = 1; break;
        case 1: *need_m = 1; break;
        case 2: *need_m = 1; *need_a = 1; break;
        default: break;
        }
    }
}

static uint64_t simulate_worker_row(const options_t *opt, const int *iters, int pixels) {
    context_t *ctx = (context_t *)calloc((size_t)opt->contexts, sizeof(context_t));
    int *issued_this_cycle = (int *)calloc((size_t)opt->contexts, sizeof(int));
    if (!ctx || !issued_this_cycle) {
        fprintf(stderr, "ERROR: out of memory\n");
        exit(2);
    }

    int next_assign = 0;
    int next_commit = 0;
    int committed = 0;
    uint64_t cycle = 0;

    while (committed < pixels) {
        int committed_this_cycle = 0;
        int issued_count = 0;

        for (int i = 0; i < opt->contexts; i++) {
            if (ctx[i].active && !ctx[i].result_valid && ctx[i].ready_cycle <= cycle) {
                normalize_context(&ctx[i], opt->max_iter);
            }
        }

        for (int i = 0; i < opt->contexts; i++) {
            if (ctx[i].active && ctx[i].result_valid && ctx[i].seq == next_commit) {
                memset(&ctx[i], 0, sizeof(ctx[i]));
                next_commit++;
                committed++;
                committed_this_cycle = 1;
                break;
            }
        }

        for (int i = 0; i < opt->contexts && next_assign < pixels; i++) {
            if (!ctx[i].active) {
                load_context(&ctx[i], next_assign, iters[next_assign], opt->max_iter, cycle);
                next_assign++;
            }
        }

        memset(issued_this_cycle, 0, (size_t)opt->contexts * sizeof(int));
        int mul_left = opt->multipliers;
        int add_left = opt->adders;
        int progress = 1;
        while (progress) {
            progress = 0;
            int rr_start = (int)(cycle % (uint64_t)opt->contexts);
            for (int s = 0; s < opt->contexts; s++) {
                int i = (rr_start + s) % opt->contexts;
                int need_m = 0;
                int need_a = 0;
                if (issued_this_cycle[i]) continue;
                if (!ctx[i].active || ctx[i].result_valid || ctx[i].ready_cycle > cycle) continue;
                normalize_context(&ctx[i], opt->max_iter);
                if (ctx[i].result_valid) continue;
                stage_needs(&ctx[i], &need_m, &need_a);
                if (!need_m && !need_a) continue;
                if ((need_m && mul_left <= 0) || (need_a && add_left <= 0)) continue;

                if (need_m) mul_left--;
                if (need_a) add_left--;
                issued_this_cycle[i] = 1;
                issued_count++;
                ctx[i].phase++;
                ctx[i].last_issue_cycle = cycle;
                int lat = 0;
                if (need_m && opt->mul_lat > lat) lat = opt->mul_lat;
                if (need_a && opt->add_lat > lat) lat = opt->add_lat;
                ctx[i].ready_cycle = cycle + (uint64_t)lat;
                progress = 1;
                break;
            }
        }

        if (!committed_this_cycle && issued_count == 0) {
            uint64_t min_ready = UINT64_MAX;
            for (int i = 0; i < opt->contexts; i++) {
                if (ctx[i].active && !ctx[i].result_valid && ctx[i].ready_cycle > cycle && ctx[i].ready_cycle < min_ready) {
                    min_ready = ctx[i].ready_cycle;
                }
            }
            if (min_ready != UINT64_MAX) {
                cycle = min_ready;
                continue;
            }
        }
        cycle++;
    }

    free(ctx);
    free(issued_this_cycle);
    return cycle;
}

static int earliest_worker(const uint64_t *worker_cycles, int workers) {
    int best = 0;
    for (int i = 1; i < workers; i++) {
        if (worker_cycles[i] < worker_cycles[best]) best = i;
    }
    return best;
}

static uint64_t max_worker_cycle(const uint64_t *worker_cycles, int workers) {
    uint64_t maxv = 0;
    for (int i = 0; i < workers; i++) {
        if (worker_cycles[i] > maxv) maxv = worker_cycles[i];
    }
    return maxv;
}

static uint64_t simulate_frame_from_iters(const options_t *opt, const int *frame_iters) {
    uint64_t *worker_cycles = (uint64_t *)calloc((size_t)opt->workers, sizeof(uint64_t));
    if (!worker_cycles) {
        fprintf(stderr, "ERROR: out of memory\n");
        exit(2);
    }

    for (int y = 0; y < opt->height; y++) {
        const int *row_iters = frame_iters + (uint64_t)y * (uint64_t)opt->width;
        uint64_t row_cycles = simulate_worker_row(opt, row_iters, opt->width);
        int w = (opt->scheduler == SCHED_DYNAMIC) ? earliest_worker(worker_cycles, opt->workers) : (y % opt->workers);
        worker_cycles[w] += row_cycles;
    }

    if (opt->verbose) {
        for (int i = 0; i < opt->workers; i++) {
            printf("worker[%d]_cycles=%" PRIu64 "\n", i, worker_cycles[i]);
        }
    }

    uint64_t cycles = max_worker_cycle(worker_cycles, opt->workers);

    free(worker_cycles);
    return cycles;
}

static uint64_t estimate_row_cycles_fast(const options_t *opt, const int *iters, int pixels) {
    uint64_t full_iters = 0;
    uint64_t escape_pixels = 0;
    for (int i = 0; i < pixels; i++) {
        full_iters += (uint64_t)iters[i];
        if (iters[i] < opt->max_iter) escape_pixels++;
    }

    uint64_t mul_issues = full_iters * 3u + escape_pixels * 3u;
    uint64_t add_issues = full_iters * 5u + escape_pixels;
    uint64_t latency_sum = full_iters * (uint64_t)(3 * opt->mul_lat + 4 * opt->add_lat) +
                           escape_pixels * (uint64_t)(opt->mul_lat * 3 > opt->add_lat ? opt->mul_lat * 3 : opt->add_lat);

    double by_context = (double)latency_sum / (double)opt->contexts;
    double by_mul = (double)mul_issues / (double)opt->multipliers;
    double by_add = (double)add_issues / (double)opt->adders;
    double cycles = by_context;
    if (by_mul > cycles) cycles = by_mul;
    if (by_add > cycles) cycles = by_add;

    // Fill/drain and ordered-commit effects are small for full rows but visible
    // at high context counts. This keeps the fast model from claiming ideal zero
    // overhead at row boundaries.
    cycles += (double)(opt->mul_lat + opt->add_lat + opt->contexts);
    return (uint64_t)ceil(cycles);
}

static uint64_t simulate_frame_fast(const options_t *opt, const int *frame_iters) {
    uint64_t *worker_cycles = (uint64_t *)calloc((size_t)opt->workers, sizeof(uint64_t));
    if (!worker_cycles) {
        fprintf(stderr, "ERROR: out of memory\n");
        exit(2);
    }

    for (int y = 0; y < opt->height; y++) {
        const int *row_iters = frame_iters + (uint64_t)y * (uint64_t)opt->width;
        uint64_t row_cycles = estimate_row_cycles_fast(opt, row_iters, opt->width);
        int w = (opt->scheduler == SCHED_DYNAMIC) ? earliest_worker(worker_cycles, opt->workers) : (y % opt->workers);
        worker_cycles[w] += row_cycles;
    }

    if (opt->verbose) {
        for (int i = 0; i < opt->workers; i++) {
            printf("worker[%d]_cycles=%" PRIu64 "\n", i, worker_cycles[i]);
        }
    }

    uint64_t cycles = max_worker_cycle(worker_cycles, opt->workers);
    free(worker_cycles);
    return cycles;
}

static uint64_t simulate_selected(const options_t *opt, const int *frame_iters) {
    return opt->exact ? simulate_frame_from_iters(opt, frame_iters) : simulate_frame_fast(opt, frame_iters);
}

static void print_result(const options_t *opt, uint64_t cycles, uint64_t iter_sum) {
    uint64_t pixels = (uint64_t)opt->width * (uint64_t)opt->height;
    double avg_iter = pixels ? (double)iter_sum / (double)pixels : 0.0;
    double seconds = (double)cycles / opt->clock_hz;
    double pps = seconds > 0.0 ? (double)pixels / seconds : 0.0;
    double iter_per_cycle = cycles ? (double)iter_sum / (double)cycles : 0.0;

    printf("Mandelbrot compute pipeline simulation\n");
    printf("image=%dx%d pixels=%" PRIu64 " center=(%.17g,%.17g) step=%.17g max_iter=%d\n",
           opt->width, opt->height, pixels, opt->center_re, opt->center_im, opt->step, opt->max_iter);
    printf("workers=%d contexts=%d adders=%d multipliers=%d add_lat=%d mul_lat=%d scheduler=%s\n",
           opt->workers, opt->contexts, opt->adders, opt->multipliers, opt->add_lat, opt->mul_lat,
           opt->scheduler == SCHED_DYNAMIC ? "dynamic" : "static");
    printf("avg_iter=%.6f iter_sum=%" PRIu64 "\n", avg_iter, iter_sum);
    printf("compute_cycles=%" PRIu64 " compute_seconds=%.9f clock_hz=%.3f\n",
           cycles, seconds, opt->clock_hz);
    printf("compute_pps=%.3f\n", pps);
    printf("iterations_per_cycle=%.9f\n", iter_per_cycle);
    printf("model=%s\n", opt->exact ? "exact_stage_scheduler" : "fast_aggregate_row_model");
    printf("note=compute_only_uart_ceiling_ignored\n");
}

typedef struct {
    int contexts;
    int adders;
    int multipliers;
    const char *name;
} sweep_case_t;

static void run_sweep(const options_t *base, const int *frame_iters, uint64_t iter_sum) {
    static const sweep_case_t cases[] = {
        {1, 1, 1, "1ctx 1M+1A"},
        {2, 1, 1, "2ctx 1M+1A"},
        {4, 1, 1, "4ctx 1M+1A"},
        {8, 1, 1, "8ctx 1M+1A"},
        {16, 1, 1, "16ctx 1M+1A"},
        {16, 2, 1, "16ctx 1M+2A"},
        {24, 2, 2, "24ctx 2M+2A"},
        {32, 3, 2, "32ctx 2M+3A"},
        {48, 5, 3, "48ctx 3M+5A"},
    };
    uint64_t pixels = (uint64_t)base->width * (uint64_t)base->height;
    double avg_iter = pixels ? (double)iter_sum / (double)pixels : 0.0;
    uint64_t baseline_cycles = 0;

    printf("Mandelbrot compute pipeline sweep\n");
    printf("image=%dx%d pixels=%" PRIu64 " center=(%.17g,%.17g) step=%.17g max_iter=%d avg_iter=%.6f\n",
           base->width, base->height, pixels, base->center_re, base->center_im,
           base->step, base->max_iter, avg_iter);
    printf("workers=%d add_lat=%d mul_lat=%d clock_hz=%.3f scheduler=%s note=compute_only_uart_ceiling_ignored\n",
           base->workers, base->add_lat, base->mul_lat, base->clock_hz,
           base->scheduler == SCHED_DYNAMIC ? "dynamic" : "static");
    printf("model=%s\n", base->exact ? "exact_stage_scheduler" : "fast_aggregate_row_model");
    printf("case,contexts,multipliers,adders,cycles,compute_pps,speedup_vs_1ctx\n");

    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        options_t opt = *base;
        opt.contexts = cases[i].contexts;
        opt.adders = cases[i].adders;
        opt.multipliers = cases[i].multipliers;
        uint64_t cycles = simulate_selected(&opt, frame_iters);
        if (i == 0) baseline_cycles = cycles;
        double seconds = (double)cycles / opt.clock_hz;
        double pps = seconds > 0.0 ? (double)pixels / seconds : 0.0;
        double speedup = cycles ? (double)baseline_cycles / (double)cycles : 0.0;
        printf("%s,%d,%d,%d,%" PRIu64 ",%.3f,%.3f\n",
               cases[i].name, opt.contexts, opt.multipliers, opt.adders,
               cycles, pps, speedup);
    }
}

int main(int argc, char **argv) {
    options_t opt;
    parse_args(argc, argv, &opt);
    if (opt.self_test) return run_self_test();

    uint64_t iter_sum = 0;
    int *frame_iters = generate_frame_iters(&opt, &iter_sum);
    if (opt.sweep) {
        run_sweep(&opt, frame_iters, iter_sum);
    } else {
        uint64_t cycles = simulate_selected(&opt, frame_iters);
        print_result(&opt, cycles, iter_sum);
    }
    free(frame_iters);
    return 0;
}
