#!/usr/bin/env python3
"""Benchmark the 1080p standard scene for response retry row-split variants."""

import argparse
import math
import pathlib
import re
import subprocess
import sys
import time


ROOT = pathlib.Path(__file__).resolve().parents[1]
HOST = ROOT / "python" / "mandelbrot_host.py"
OUT_DIR = ROOT / "python" / "host_tile_stability_bench"

STANDARD_SCENE = {
    "name": "standard @64",
    "width": 1920,
    "height": 1080,
    "max_iter": 64,
    "center": (-0.5, 0.0),
    "step": "0.002",
    "timeout": 600,
}


def split_description(tile_height, row_splits):
    row_splits = max(row_splits, 1)
    base_rows = max(tile_height // row_splits, 1)
    full_tiles = tile_height // base_rows
    remainder = tile_height % base_rows
    if remainder:
        return f"{full_tiles}x{base_rows}+{remainder}"
    return f"{full_tiles}x{base_rows}"


def parse_host_text(text, returncode, elapsed):
    m = re.search(r"FPGA elapsed: ([0-9.]+)s \(([0-9.]+) pixels/s\)", text)
    fpga_time = float(m.group(1)) if m else None
    pps = float(m.group(2)) if m else None
    m = re.search(r"HW vs SW: (\d+)/(\d+) match \(([0-9.]+)%\)", text)
    match = int(m.group(1)) if m else None
    match_total = int(m.group(2)) if m else None
    retry_events = len(re.findall(r"compute tile receive failed", text, re.IGNORECASE))
    recovered = [int(v) for v in re.findall(r"Recovered\s+(\d+)\s+failed compute tile attempts", text, re.IGNORECASE)]
    deferred = [int(v) for v in re.findall(r"Recovered\s+(\d+)\s+deferred checksum retry tile", text, re.IGNORECASE)]
    retry_events = max([retry_events] + recovered) + sum(deferred)
    expected_pixels = STANDARD_SCENE["width"] * STANDARD_SCENE["height"]
    ok = returncode == 0 and match_total == expected_pixels
    return {
        "ok": ok,
        "returncode": returncode,
        "fpga_time": fpga_time,
        "pps": pps,
        "match": match,
        "match_total": match_total,
        "retry_events": retry_events,
        "wall_time": elapsed,
    }


def mean(values):
    return sum(values) / len(values) if values else None


def stdev(values):
    if len(values) < 2:
        return 0.0 if values else None
    avg = mean(values)
    return math.sqrt(sum((v - avg) ** 2 for v in values) / (len(values) - 1))


def fmt(value, digits=3):
    if value is None:
        return "Fail"
    return f"{value:.{digits}f}"


def run_one(args, row_splits, run_idx):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tag = f"{args.run_tag}_rtr{row_splits}" if args.run_tag else f"rtr{row_splits}"
    log_path = OUT_DIR / f"{tag}_standard_run{run_idx}.log"
    output_path = OUT_DIR / f"{tag}_standard_run{run_idx}.png"
    cmd = [
        sys.executable,
        str(HOST),
        "--mode", "fx64",
        "--port", args.port,
        "--width", str(STANDARD_SCENE["width"]),
        "--height", str(STANDARD_SCENE["height"]),
        "--max-iter", str(STANDARD_SCENE["max_iter"]),
        "--center", str(STANDARD_SCENE["center"][0]), str(STANDARD_SCENE["center"][1]),
        "--step", str(STANDARD_SCENE["step"]),
        "--timeout", str(STANDARD_SCENE["timeout"]),
        "--verify",
        "--tile-width", str(args.tile_width),
        "--tile-height", str(args.tile_height),
        "--tile-retries", str(args.tile_retries),
        "--quiet",
        "--output", str(output_path),
    ]
    started = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            text=True,
            capture_output=True,
            timeout=STANDARD_SCENE["timeout"] + args.extra_timeout,
        )
        text = proc.stdout + ("\nSTDERR:\n" + proc.stderr if proc.stderr else "")
        returncode = proc.returncode
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        if isinstance(stdout, bytes):
            stdout = stdout.decode(errors="replace")
        if isinstance(stderr, bytes):
            stderr = stderr.decode(errors="replace")
        text = stdout + ("\nSTDERR:\n" + stderr if stderr else "")
        returncode = 124
    elapsed = time.perf_counter() - started
    log_path.write_text(text, encoding="utf-8", errors="replace")
    result = parse_host_text(text, returncode, elapsed)
    result["log"] = log_path
    result["row_splits"] = row_splits
    result["run"] = run_idx
    status = "PASS" if result["ok"] else f"FAIL rc={returncode}"
    print(f"rtr={row_splits} run={run_idx}/{args.runs} {status}: fpga={result['fpga_time']}s pps={result['pps']} retries={result['retry_events']}", flush=True)
    return result


def write_summary(args, results):
    lines = []
    lines.append("# Response Tile Row-Split Standard Scene Benchmark")
    lines.append("")
    lines.append(f"- Scene: `{STANDARD_SCENE['name']}`")
    lines.append(f"- Runs per split count: `{args.runs}`")
    lines.append(f"- Host/compute tile: `{args.tile_width}x{args.tile_height}`")
    lines.append(f"- Tile retries: `{args.tile_retries}`")
    lines.append("")
    lines.append("| Row splits M | Height split | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |")
    lines.append("|---:|---|---:|---:|---:|---:|---:|---:|---:|")
    for row_splits in args.row_splits:
        group = [r for r in results if r["row_splits"] == row_splits]
        passed = [r for r in group if r["ok"] and r["fpga_time"] is not None]
        times = [r["fpga_time"] for r in passed]
        pps_values = [r["pps"] for r in passed if r["pps"] is not None]
        avg = mean(times)
        sd = stdev(times)
        cv = (sd / avg * 100.0) if avg else None
        retries = sum(r["retry_events"] for r in group)
        split_desc = split_description(args.tile_height, row_splits)
        lines.append(f"| `{row_splits}` | `{split_desc}` | {len(passed)}/{len(group)} | {retries} | `{fmt(avg)}` | `{fmt(min(times) if times else None)}` | `{fmt(max(times) if times else None)}` | `{fmt(cv, 2)}%` | `{fmt(mean(pps_values), 2)}` |")
    lines.append("")
    lines.append("## Runs")
    lines.append("")
    lines.append("| Row splits M | Run | Status | Retry events | FPGA s | pps | Log |")
    lines.append("|---:|---:|---|---:|---:|---:|---|")
    for r in results:
        status = "PASS" if r["ok"] else f"FAIL rc={r['returncode']}"
        log_rel = r["log"].relative_to(ROOT).as_posix()
        lines.append(f"| `{r['row_splits']}` | {r['run']} | {status} | {r['retry_events']} | `{fmt(r['fpga_time'])}` | `{fmt(r['pps'], 2)}` | `{log_rel}` |")
    out = OUT_DIR / args.summary_name
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def main():
    parser = argparse.ArgumentParser(description="Benchmark standard scene for response retry row-split variants")
    parser.add_argument("--port", default="COM6")
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--row-splits", type=int, nargs="+", default=[1, 2, 4, 8, 15, 30])
    parser.add_argument("--tile-width", type=int, default=1920)
    parser.add_argument("--tile-height", type=int, default=120)
    parser.add_argument("--tile-retries", type=int, default=3)
    parser.add_argument("--extra-timeout", type=int, default=7200)
    parser.add_argument("--run-tag", default="response_tile_rows")
    parser.add_argument("--summary-name", default="response_tile_rows_standard.md")
    args = parser.parse_args()

    results = []
    for row_splits in args.row_splits:
        print(f"=== Response tile row splits {row_splits} ===", flush=True)
        for run_idx in range(1, args.runs + 1):
            results.append(run_one(args, row_splits, run_idx))
            write_summary(args, results)
    summary = write_summary(args, results)
    print(f"Summary: {summary}")


if __name__ == "__main__":
    main()
