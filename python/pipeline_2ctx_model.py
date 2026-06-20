#!/usr/bin/env python3
"""Cycle model for tagged multi-context Mandelbrot worker scheduling.

This is a scheduling model, not a replacement RTL implementation. It uses real
or synthetic iteration-count traces and models the current FP issue sequence with
separate MUL/ADD tag latencies, tagged context completion, and ordered commit by
pixel_seq.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from typing import List, Sequence, Tuple


MUL_LAT = 6
ADD_LAT = 9


# Stages per non-escaping iteration. Stage 2 issues mul and add together.
FULL_ITER_STAGES = ("M", "M", "MA", "A", "A", "A", "A")
ESCAPE_CHECK_STAGES = ("M", "M", "MA")


@dataclass
class Context:
    seq: int = -1
    stages: Tuple[str, ...] = ()
    stage_idx: int = 0
    ready_cycle: int = 0
    active: bool = False
    done: bool = False
    done_cycle: int = 0


def stages_for_pixel(iter_count: int, max_iter: int) -> Tuple[str, ...]:
    if iter_count >= max_iter:
        return FULL_ITER_STAGES * max_iter
    return FULL_ITER_STAGES * iter_count + ESCAPE_CHECK_STAGES


def stage_latency(stage: str, mul_lat: int, add_lat: int) -> int:
    if stage == "MA":
        return max(mul_lat, add_lat)
    if stage == "M":
        return mul_lat
    if stage == "A":
        return add_lat
    raise ValueError(f"unknown stage {stage!r}")


def mandelbrot_trace(width: int, height: int, max_iter: int, center_re: float,
                     center_im: float, step: float) -> List[int]:
    half_w = (width - 1) >> 1
    half_h = (height - 1) >> 1
    re_start = center_re - half_w * step
    im_start = center_im + half_h * step
    trace: List[int] = []
    for y in range(height):
        cim = im_start - y * step
        for x in range(width):
            cre = re_start + x * step
            zre = 0.0
            zim = 0.0
            count = 0
            while count < max_iter:
                zre_sq = zre * zre
                zim_sq = zim * zim
                if zre_sq + zim_sq > 4.0:
                    break
                zim = 2.0 * zre * zim + cim
                zre = zre_sq - zim_sq + cre
                count += 1
            trace.append(count)
    return trace


def synthetic_trace(kind: str, pixels: int, max_iter: int) -> List[int]:
    if kind == "uniform-long":
        return [max_iter] * pixels
    if kind == "uniform-short":
        return [1] * pixels
    if kind == "alternating-long-short":
        return [max_iter if i % 2 == 0 else 1 for i in range(pixels)]
    if kind == "long-head-short-tail":
        return [max_iter] + [1] * (pixels - 1)
    if kind == "bands":
        out = []
        for i in range(pixels):
            band = (i // 64) % 4
            out.append(max_iter if band == 0 else (max_iter // 8 if band == 1 else 2))
        return out
    raise ValueError(f"unknown synthetic trace kind: {kind}")


def load_context(ctx: Context, seq: int, iter_count: int, max_iter: int, cycle: int) -> None:
    ctx.seq = seq
    ctx.stages = stages_for_pixel(iter_count, max_iter)
    ctx.stage_idx = 0
    ctx.ready_cycle = cycle
    ctx.active = True
    ctx.done = False
    ctx.done_cycle = 0


def simulate(trace: List[int], max_iter: int, contexts_count: int,
             mul_units: int = 1, add_units: int = 1,
             mul_lat: int = MUL_LAT, add_lat: int = ADD_LAT) -> Tuple[int, int, int, int, int]:
    contexts = [Context() for _ in range(contexts_count)]
    next_assign = 0
    next_commit = 0
    committed = 0
    cycle = 0
    done_table = {}
    max_reorder_occupancy = 0
    commit_stall_cycles = 0
    mul_issues = 0
    add_issues = 0

    def assign_ready_contexts(now: int) -> None:
        nonlocal next_assign
        for ctx in contexts:
            if not ctx.active and not ctx.done and next_assign < len(trace):
                load_context(ctx, next_assign, trace[next_assign], max_iter, now)
                next_assign += 1

    assign_ready_contexts(cycle)

    while committed < len(trace):
        mul_used = 0
        add_used = 0

        # Commit in order before issuing more work, matching an output FIFO write slot.
        if next_commit in done_table and done_table[next_commit] <= cycle:
            del done_table[next_commit]
            next_commit += 1
            committed += 1
            for ctx in contexts:
                if ctx.done and ctx.seq == next_commit - 1:
                    ctx.done = False
                    ctx.active = False
                    break
            assign_ready_contexts(cycle)
        elif done_table:
            commit_stall_cycles += 1

        # Issue as many independent context stages as the FP units can accept.
        for ctx in contexts:
            if not ctx.active or ctx.done or ctx.ready_cycle > cycle:
                continue
            if ctx.stage_idx >= len(ctx.stages):
                continue
            stage = ctx.stages[ctx.stage_idx]
            need_m = "M" in stage
            need_a = "A" in stage
            if (need_m and mul_used >= mul_units) or (need_a and add_used >= add_units):
                continue
            if need_m:
                mul_used += 1
                mul_issues += 1
            if need_a:
                add_used += 1
                add_issues += 1
            ctx.stage_idx += 1
            ctx.ready_cycle = cycle + stage_latency(stage, mul_lat, add_lat)
            if ctx.stage_idx >= len(ctx.stages):
                ctx.done = True
                ctx.done_cycle = ctx.ready_cycle
                done_table[ctx.seq] = ctx.done_cycle

        if len(done_table) > max_reorder_occupancy:
            max_reorder_occupancy = len(done_table)
        cycle += 1

    return cycle, max_reorder_occupancy, commit_stall_cycles, mul_issues, add_issues


def parse_csv_ints(text: str) -> List[int]:
    return [int(part) for part in text.split(",") if part.strip()]


def summarize(name: str, trace: List[int], max_iter: int,
              contexts_list: Sequence[int], configs: Sequence[Tuple[int, int]]) -> None:
    avg_iter = sum(trace) / len(trace)
    baseline = simulate(trace, max_iter, 4, 1, 1)[0]
    print(f"\n{name}  pixels={len(trace)} avg_iter={avg_iter:.2f} baseline=4ctx/1M1A {baseline} cycles")
    print("config contexts      cycles  speedup_vs_4ctx  reorder  commit_wait  mul_util  add_util")
    for mul_units, add_units in configs:
        for contexts_count in contexts_list:
            cycles, reorder, stalls, mul_issues, add_issues = simulate(
                trace, max_iter, contexts_count, mul_units, add_units
            )
            speedup = baseline / cycles if cycles else 0.0
            mul_util = mul_issues / (cycles * mul_units) if cycles else 0.0
            add_util = add_issues / (cycles * add_units) if cycles else 0.0
            print(f"{mul_units}M{add_units}A {contexts_count:8d} {cycles:11d} {speedup:14.2f}x "
                  f"{reorder:8d} {stalls:12d} {mul_util:8.1%} {add_util:8.1%}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Model tagged multi-context Mandelbrot worker scheduling")
    parser.add_argument("--width", type=int, default=160)
    parser.add_argument("--height", type=int, default=120)
    parser.add_argument("--max-iter", type=int, default=256)
    parser.add_argument("--center", nargs=2, type=float, default=(-0.5, 0.0))
    parser.add_argument("--step", type=float, default=0.005)
    parser.add_argument("--pixels", type=int, default=4096)
    parser.add_argument("--contexts", default="1,2,4,8,12,16,24,32",
                        help="comma-separated context counts to model")
    parser.add_argument("--configs", default="1x1,1x2,2x1,2x2",
                        help="comma-separated FP unit configs such as 1x1,1x2,2x2")
    args = parser.parse_args()

    contexts_list = parse_csv_ints(args.contexts)
    configs = []
    for item in args.configs.split(","):
        left, right = item.lower().split("x")
        configs.append((int(left), int(right)))

    print("Tagged Mandelbrot worker cycle model")
    print(f"MUL_LAT={MUL_LAT}, ADD_LAT={ADD_LAT}")
    print(f"contexts={contexts_list}")
    print(f"configs={['%dM%dA' % cfg for cfg in configs]}")

    real_trace = mandelbrot_trace(args.width, args.height, args.max_iter,
                                  args.center[0], args.center[1], args.step)
    summarize("real-small-frame", real_trace, args.max_iter, contexts_list, configs)

    for kind in [
        "uniform-short",
        "uniform-long",
        "alternating-long-short",
        "long-head-short-tail",
        "bands",
    ]:
        summarize(kind, synthetic_trace(kind, args.pixels, args.max_iter),
                  args.max_iter, contexts_list, configs)


if __name__ == "__main__":
    main()
