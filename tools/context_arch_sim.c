// Compare old scoreboard K-context scheduling with a planned low-LUT
// ring/barrel context scheduler. This is an architecture-level compute model:
// it uses real Mandelbrot iteration counts, but it does not model UART,
// routing delay, placement, or exact RTL control hazards.

#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
    MODEL_SCOREBOARD = 0,
    MODEL_RING = 1,
} model_t;

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
    model_t model;
    int lookahead;
    int sweep;
    int self_test;
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
} context_t;

typedef struct {
    const char *name;
    int contexts;
    int adders;
    int multipliers;
} sweep_case_t;

static const sweep_case_t sweep_cases[] = {
    {"1ctx 1M+1A", 1, 1, 1},
    {"2ctx 1M+1A", 2, 1, 1},
    {"4ctx 1M+1A", 4, 1, 1},
    {"8ctx 1M+1A", 8, 1, 1},
    {"12ctx 1M+1A", 12, 1, 1},
    {"16ctx 1M+1A", 16, 1, 1},
    {"4ctx 1M+2A", 4, 2, 1},
    {"8ctx 1M+2A", 8, 2, 1},
    {"16ctx 1M+2A", 16, 2, 1},
    {"8ctx 2M+1A", 8, 1, 2},
    {"16ctx 2M+1A", 16, 1, 2},
    {"16ctx 2M+2A", 16, 2, 2},
    {"24ctx 2M+2A", 24, 2, 2},
};

static void usage(const char *prog) {
    printf("Usage: %s [options]\n", prog);
    printf("  --width W --height H --max-iter N --center RE IM --step S\n");
    printf("  --contexts K --adders A --multipliers M --workers N\n");
    printf("  --add-lat N --mul-lat N --clock-hz HZ\n");
    printf("  --scheduler dynamic|static\n");
    printf("  --model scoreboard|ring|both\n");
    printf("  --lookahead N          Ring ready-search window, default 1\n");
    printf("  --sweep\n");
    printf("  --self-test\n");
}

static int parse_int(const char *s, const char *name) {
    char *end = NULL;
    errno = 0;
    long v = strtol(s, &end, 10);
    if (errno || end == s || *end != '\0' || v <= 0 || v > 2147483647L) {
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
    opt->model = MODEL_SCOREBOARD;
    opt->lookahead = 1;
    opt->sweep = 0;
    opt->self_test = 0;
}

static int model_both_arg = 0;

static void parse_args(int argc, char **argv, options_t *opt) {
    default_options(opt);
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (!strcmp(a, "--help") || !strcmp(a, "-h")) {
            usage(argv[0]);
            exit(0);
        } else if (!strcmp(a, "--width")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --width needs value\n"); exit(2); }
            opt->width = parse_int(argv[i], "width");
        } else if (!strcmp(a, "--height")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --height needs value\n"); exit(2); }
            opt->height = parse_int(argv[i], "height");
        } else if (!strcmp(a, "--max-iter")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --max-iter needs value\n"); exit(2); }
            opt->max_iter = parse_int(argv[i], "max_iter");
        } else if (!strcmp(a, "--center")) {
            if (i + 2 >= argc) { fprintf(stderr, "ERROR: --center needs RE IM\n"); exit(2); }
            opt->center_re = parse_double(argv[++i], "center_re");
            opt->center_im = parse_double(argv[++i], "center_im");
        } else if (!strcmp(a, "--step")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --step needs value\n"); exit(2); }
            opt->step = parse_double(argv[i], "step");
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
            opt->add_lat = parse_int(argv[i], "add_lat");
        } else if (!strcmp(a, "--mul-lat")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --mul-lat needs value\n"); exit(2); }
            opt->mul_lat = parse_int(argv[i], "mul_lat");
        } else if (!strcmp(a, "--clock-hz")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --clock-hz needs value\n"); exit(2); }
            opt->clock_hz = parse_double(argv[i], "clock_hz");
        } else if (!strcmp(a, "--scheduler")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --scheduler needs value\n"); exit(2); }
            if (!strcmp(argv[i], "dynamic")) opt->scheduler = SCHED_DYNAMIC;
            else if (!strcmp(argv[i], "static")) opt->scheduler = SCHED_STATIC;
            else { fprintf(stderr, "ERROR: --scheduler must be dynamic or static\n"); exit(2); }
        } else if (!strcmp(a, "--model")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --model needs value\n"); exit(2); }
            if (!strcmp(argv[i], "scoreboard")) opt->model = MODEL_SCOREBOARD;
            else if (!strcmp(argv[i], "ring")) opt->model = MODEL_RING;
            else if (!strcmp(argv[i], "both")) model_both_arg = 1;
            else { fprintf(stderr, "ERROR: --model must be scoreboard, ring, or both\n"); exit(2); }
        } else if (!strcmp(a, "--lookahead")) {
            if (++i >= argc) { fprintf(stderr, "ERROR: --lookahead needs value\n"); exit(2); }
            opt->lookahead = parse_int(argv[i], "lookahead");
        } else if (!strcmp(a, "--sweep")) {
            opt->sweep = 1;
        } else if (!strcmp(a, "--self-test")) {
            opt->self_test = 1;
        } else {
            fprintf(stderr, "ERROR: unknown option: %s\n", a);
            exit(2);
        }
    }
}

static int mandelbrot_iter(double c_re, double c_im, int max_iter) {
    double z_re = 0.0;
    double z_im = 0.0;
    int it = 0;
    while (it < max_iter) {
        double zr2 = z_re * z_re;
        double zi2 = z_im * z_im;
        if (zr2 + zi2 > 4.0) break;
        z_im = 2.0 * z_re * z_im + c_im;
        z_re = zr2 - zi2 + c_re;
        it++;
    }
    return it;
}

static int *generate_iters(const options_t *opt, uint64_t *iter_sum_out) {
    uint64_t pixels = (uint64_t)opt->width * (uint64_t)opt->height;
    int *iters = (int *)malloc((size_t)pixels * sizeof(int));
    if (!iters) { fprintf(stderr, "ERROR: out of memory\n"); exit(2); }
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
    struct { double re, im; int max_iter, expected; } tests[] = {
        {2.5, 0.0, 256, 1},
        {2.6, 0.0, 256, 1},
        {4.1, 0.0, 256, 1},
        {0.0, 0.0, 256, 256},
        {-1.0, 0.0, 256, 256},
    };
    for (size_t i = 0; i < sizeof(tests) / sizeof(tests[0]); i++) {
        int got = mandelbrot_iter(tests[i].re, tests[i].im, tests[i].max_iter);
        if (got != tests[i].expected) {
            fprintf(stderr, "SELF-TEST FAIL got=%d expected=%d\n", got, tests[i].expected);
            return 1;
        }
    }
    printf("SELF-TEST PASS: iteration-count checks matched expected values\n");
    return 0;
}

static void load_context(context_t *ctx, int seq, int iter_count, int max_iter, uint64_t cycle) {
    memset(ctx, 0, sizeof(*ctx));
    ctx->active = 1;
    ctx->seq = seq;
    ctx->iter_count = iter_count;
    ctx->mode = (iter_count == 0 && iter_count < max_iter) ? CTX_ESCAPE : CTX_FULL;
    ctx->ready_cycle = cycle;
}

static void normalize_context(context_t *ctx, int max_iter) {
    if (!ctx->active || ctx->result_valid) return;
    if (ctx->mode == CTX_FULL && ctx->phase >= 7) {
        ctx->full_done++;
        if (ctx->full_done >= ctx->iter_count) {
            if (ctx->iter_count >= max_iter) ctx->result_valid = 1;
            else { ctx->mode = CTX_ESCAPE; ctx->phase = 0; }
        } else {
            ctx->phase = 0;
        }
    } else if (ctx->mode == CTX_ESCAPE && ctx->phase >= 3) {
        ctx->result_valid = 1;
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

static int commit_one(context_t *ctx, int contexts, int *next_commit) {
    for (int i = 0; i < contexts; i++) {
        if (ctx[i].active && ctx[i].result_valid && ctx[i].seq == *next_commit) {
            memset(&ctx[i], 0, sizeof(ctx[i]));
            (*next_commit)++;
            return 1;
        }
    }
    return 0;
}

static void refill(context_t *ctx, int contexts, const int *iters, int pixels, int max_iter, int *next_assign, uint64_t cycle) {
    for (int i = 0; i < contexts && *next_assign < pixels; i++) {
        if (!ctx[i].active) {
            load_context(&ctx[i], *next_assign, iters[*next_assign], max_iter, cycle);
            (*next_assign)++;
        }
    }
}

static uint64_t simulate_row_scoreboard(const options_t *opt, const int *iters, int pixels) {
    context_t *ctx = (context_t *)calloc((size_t)opt->contexts, sizeof(context_t));
    int *issued = (int *)calloc((size_t)opt->contexts, sizeof(int));
    if (!ctx || !issued) { fprintf(stderr, "ERROR: out of memory\n"); exit(2); }
    int next_assign = 0, next_commit = 0, committed = 0;
    uint64_t cycle = 0;
    while (committed < pixels) {
        int did_commit = 0, issued_count = 0;
        for (int i = 0; i < opt->contexts; i++) {
            if (ctx[i].active && ctx[i].ready_cycle <= cycle) normalize_context(&ctx[i], opt->max_iter);
        }
        if (commit_one(ctx, opt->contexts, &next_commit)) { committed++; did_commit = 1; }
        refill(ctx, opt->contexts, iters, pixels, opt->max_iter, &next_assign, cycle);
        memset(issued, 0, (size_t)opt->contexts * sizeof(int));
        int mul_left = opt->multipliers;
        int add_left = opt->adders;
        int progress = 1;
        while (progress) {
            progress = 0;
            int rr = (int)(cycle % (uint64_t)opt->contexts);
            for (int s = 0; s < opt->contexts; s++) {
                int i = (rr + s) % opt->contexts;
                int need_m, need_a;
                if (issued[i] || !ctx[i].active || ctx[i].result_valid || ctx[i].ready_cycle > cycle) continue;
                normalize_context(&ctx[i], opt->max_iter);
                if (ctx[i].result_valid) continue;
                stage_needs(&ctx[i], &need_m, &need_a);
                if (!need_m && !need_a) continue;
                if ((need_m && mul_left <= 0) || (need_a && add_left <= 0)) continue;
                if (need_m) mul_left--;
                if (need_a) add_left--;
                ctx[i].phase++;
                int lat = 0;
                if (need_m && opt->mul_lat > lat) lat = opt->mul_lat;
                if (need_a && opt->add_lat > lat) lat = opt->add_lat;
                ctx[i].ready_cycle = cycle + (uint64_t)lat;
                issued[i] = 1;
                issued_count++;
                progress = 1;
                break;
            }
        }
        if (!did_commit && !issued_count) {
            uint64_t min_ready = UINT64_MAX;
            for (int i = 0; i < opt->contexts; i++) {
                if (ctx[i].active && !ctx[i].result_valid && ctx[i].ready_cycle > cycle && ctx[i].ready_cycle < min_ready)
                    min_ready = ctx[i].ready_cycle;
            }
            if (min_ready != UINT64_MAX) { cycle = min_ready; continue; }
        }
        cycle++;
    }
    free(ctx);
    free(issued);
    return cycle;
}

static uint64_t simulate_row_ring(const options_t *opt, const int *iters, int pixels) {
    context_t *ctx = (context_t *)calloc((size_t)opt->contexts, sizeof(context_t));
    int *issued = (int *)calloc((size_t)opt->contexts, sizeof(int));
    if (!ctx || !issued) { fprintf(stderr, "ERROR: out of memory\n"); exit(2); }
    int next_assign = 0, next_commit = 0, committed = 0;
    int issue_ptr = 0;
    uint64_t cycle = 0;
    while (committed < pixels) {
        int did_commit = 0, issued_count = 0;
        for (int i = 0; i < opt->contexts; i++) {
            if (ctx[i].active && ctx[i].ready_cycle <= cycle) normalize_context(&ctx[i], opt->max_iter);
        }
        if (commit_one(ctx, opt->contexts, &next_commit)) { committed++; did_commit = 1; }
        refill(ctx, opt->contexts, iters, pixels, opt->max_iter, &next_assign, cycle);

        int mul_left = opt->multipliers;
        int add_left = opt->adders;
        int lanes = opt->multipliers > opt->adders ? opt->multipliers : opt->adders;
        if (lanes < 1) lanes = 1;
        if (lanes > opt->contexts) lanes = opt->contexts;
        int lookahead = opt->lookahead;
        if (lookahead < 1) lookahead = 1;
        if (lookahead > opt->contexts) lookahead = opt->contexts;
        memset(issued, 0, (size_t)opt->contexts * sizeof(int));

        for (int lane = 0; lane < lanes; lane++) {
            int chosen = -1;
            int chosen_need_m = 0;
            int chosen_need_a = 0;
            for (int off = 0; off < lookahead; off++) {
                int i = (issue_ptr + lane + off) % opt->contexts;
                int need_m, need_a;
                if (issued[i] || !ctx[i].active || ctx[i].result_valid || ctx[i].ready_cycle > cycle) continue;
                normalize_context(&ctx[i], opt->max_iter);
                if (ctx[i].result_valid) continue;
                stage_needs(&ctx[i], &need_m, &need_a);
                if (!need_m && !need_a) continue;
                if ((need_m && mul_left <= 0) || (need_a && add_left <= 0)) continue;
                chosen = i;
                chosen_need_m = need_m;
                chosen_need_a = need_a;
                break;
            }
            if (chosen < 0) continue;
            if (chosen_need_m) mul_left--;
            if (chosen_need_a) add_left--;
            ctx[chosen].phase++;
            int lat = 0;
            if (chosen_need_m && opt->mul_lat > lat) lat = opt->mul_lat;
            if (chosen_need_a && opt->add_lat > lat) lat = opt->add_lat;
            ctx[chosen].ready_cycle = cycle + (uint64_t)lat;
            issued[chosen] = 1;
            issued_count++;
        }
        issue_ptr = (issue_ptr + lanes) % opt->contexts;

        if (!did_commit && !issued_count) {
            uint64_t min_ready = UINT64_MAX;
            for (int i = 0; i < opt->contexts; i++) {
                if (ctx[i].active && !ctx[i].result_valid && ctx[i].ready_cycle > cycle && ctx[i].ready_cycle < min_ready)
                    min_ready = ctx[i].ready_cycle;
            }
            if (min_ready != UINT64_MAX) { cycle = min_ready; continue; }
        }
        cycle++;
    }
    free(ctx);
    free(issued);
    return cycle;
}

static int earliest_worker(const uint64_t *cycles, int workers) {
    int best = 0;
    for (int i = 1; i < workers; i++) if (cycles[i] < cycles[best]) best = i;
    return best;
}

static uint64_t max_worker_cycle(const uint64_t *cycles, int workers) {
    uint64_t m = 0;
    for (int i = 0; i < workers; i++) if (cycles[i] > m) m = cycles[i];
    return m;
}

static uint64_t simulate_frame(const options_t *opt, const int *frame_iters) {
    uint64_t *worker_cycles = (uint64_t *)calloc((size_t)opt->workers, sizeof(uint64_t));
    if (!worker_cycles) { fprintf(stderr, "ERROR: out of memory\n"); exit(2); }
    for (int y = 0; y < opt->height; y++) {
        const int *row = frame_iters + (uint64_t)y * (uint64_t)opt->width;
        uint64_t row_cycles = (opt->model == MODEL_RING) ?
            simulate_row_ring(opt, row, opt->width) : simulate_row_scoreboard(opt, row, opt->width);
        int w = (opt->scheduler == SCHED_DYNAMIC) ? earliest_worker(worker_cycles, opt->workers) : (y % opt->workers);
        worker_cycles[w] += row_cycles;
    }
    uint64_t cycles = max_worker_cycle(worker_cycles, opt->workers);
    free(worker_cycles);
    return cycles;
}

static void print_one(const options_t *opt, uint64_t cycles, uint64_t iter_sum) {
    uint64_t pixels = (uint64_t)opt->width * (uint64_t)opt->height;
    double sec = (double)cycles / opt->clock_hz;
    double pps = sec > 0.0 ? (double)pixels / sec : 0.0;
    printf("model=%s contexts=%d multipliers=%d adders=%d lookahead=%d cycles=%" PRIu64 " compute_pps=%.3f avg_iter=%.6f\n",
           opt->model == MODEL_RING ? "ring" : "scoreboard", opt->contexts,
           opt->multipliers, opt->adders, opt->lookahead, cycles, pps,
           pixels ? (double)iter_sum / (double)pixels : 0.0);
}

static const int ring_lookaheads[] = {1, 2, 4};

static void run_sweep(const options_t *base, const int *iters, uint64_t iter_sum) {
    uint64_t pixels = (uint64_t)base->width * (uint64_t)base->height;
    uint64_t baseline_score = 0;
    uint64_t baseline_ring[sizeof(ring_lookaheads) / sizeof(ring_lookaheads[0])] = {0};
    printf("context architecture sweep\n");
    printf("image=%dx%d pixels=%" PRIu64 " center=(%.17g,%.17g) step=%.17g max_iter=%d avg_iter=%.6f\n",
           base->width, base->height, pixels, base->center_re, base->center_im,
           base->step, base->max_iter, pixels ? (double)iter_sum / (double)pixels : 0.0);
    printf("workers=%d add_lat=%d mul_lat=%d scheduler=%s clock_hz=%.3f\n",
           base->workers, base->add_lat, base->mul_lat,
           base->scheduler == SCHED_DYNAMIC ? "dynamic" : "static", base->clock_hz);
    printf("case,model,contexts,multipliers,adders,lookahead,cycles,compute_pps,speedup_vs_1ctx_same_model,vs_scoreboard\n");
    for (size_t i = 0; i < sizeof(sweep_cases) / sizeof(sweep_cases[0]); i++) {
        options_t opt = *base;
        opt.contexts = sweep_cases[i].contexts;
        opt.adders = sweep_cases[i].adders;
        opt.multipliers = sweep_cases[i].multipliers;
        opt.model = MODEL_SCOREBOARD;
        opt.lookahead = 0;
        uint64_t score_cycles = simulate_frame(&opt, iters);
        if (i == 0) baseline_score = score_cycles;
        double sec = (double)score_cycles / opt.clock_hz;
        double pps = sec > 0.0 ? (double)pixels / sec : 0.0;
        double speed = score_cycles ? (double)baseline_score / (double)score_cycles : 0.0;
        printf("%s,scoreboard,%d,%d,%d,0,%" PRIu64 ",%.3f,%.3f,1.000\n",
               sweep_cases[i].name, opt.contexts, opt.multipliers, opt.adders,
               score_cycles, pps, speed);

        for (size_t la = 0; la < sizeof(ring_lookaheads) / sizeof(ring_lookaheads[0]); la++) {
            opt.model = MODEL_RING;
            opt.lookahead = ring_lookaheads[la];
            uint64_t cycles = simulate_frame(&opt, iters);
            if (i == 0) baseline_ring[la] = cycles;
            sec = (double)cycles / opt.clock_hz;
            pps = sec > 0.0 ? (double)pixels / sec : 0.0;
            speed = cycles ? (double)baseline_ring[la] / (double)cycles : 0.0;
            double vs_score = cycles ? (double)score_cycles / (double)cycles : 0.0;
            printf("%s,ring_la%d,%d,%d,%d,%d,%" PRIu64 ",%.3f,%.3f,%.3f\n",
                   sweep_cases[i].name, opt.lookahead, opt.contexts, opt.multipliers,
                   opt.adders, opt.lookahead, cycles, pps, speed, vs_score);
        }
    }
}

int main(int argc, char **argv) {
    options_t opt;
    parse_args(argc, argv, &opt);
    if (opt.self_test) return run_self_test();
    uint64_t iter_sum = 0;
    int *iters = generate_iters(&opt, &iter_sum);
    if (opt.sweep) {
        run_sweep(&opt, iters, iter_sum);
    } else if (model_both_arg) {
        options_t a = opt;
        a.model = MODEL_SCOREBOARD;
        print_one(&a, simulate_frame(&a, iters), iter_sum);
        a.model = MODEL_RING;
        print_one(&a, simulate_frame(&a, iters), iter_sum);
    } else {
        print_one(&opt, simulate_frame(&opt, iters), iter_sum);
    }
    free(iters);
    return 0;
}
