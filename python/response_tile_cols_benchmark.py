#!/usr/bin/env python3
"""Benchmark the 1080p standard scene for different response tile widths."""

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


def parse_host_text(text, returncode, elapsed):
    m = re.search(r"FPGA elapsed: ([0-9.]+)s \(([0-9.]+) pixels/s\)", text)
    fpga_time = float(m.group(1)) if m else None
    pps = float(m.group(2)) if m else None
    m = re.search(r"HW vs SW: (\d+)/(\d+) match \(([0-9.]+)%\)", text)
    match = int(m.group(1)) if m else None
    match_total = int(m.group(2)) if m else None
    retry_events = len(re.findall(r"compute tile receive failed", text, re.IGNORECASE))
    recovered = [int(v) for v in re.findall(r"Recovered\s+(\d+)\s+failed compute tile attempts", text, re.IGNORECASE)]
    retry_events = max([retry_events] + recovered)
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


def run_one(args, response_tile_cols, run_idx):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tag = f"{args.run_tag}_rt{response_tile_cols}" if args.run_tag else f"rt{response_tile_cols}"
    log_path = OUT_DIR / f"{tag}_standard_run{run_idx}.log"
    output_path = OUT_DIR / f"{tag}_standard_run{run_idx}.png"
    cmd = [
        sys.executable,
        str(HOST),
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
    result["response_tile_cols"] = response_tile_cols
    result["run"] = run_idx
    status = "PASS" if result["ok"] else f"FAIL rc={returncode}"
    print(f"rt={response_tile_cols} run={run_idx}/{args.runs} {status}: fpga={result['fpga_time']}s pps={result['pps']} retries={result['retry_events']}", flush=True)
    return result


def write_summary(args, results):
    lines = []
    lines.append("# Response Tile Width Standard Scene Benchmark")
    lines.append("")
    lines.append(f"- Scene: `{STANDARD_SCENE['name']}`")
    lines.append(f"- Runs per width: `{args.runs}`")
    lines.append(f"- Host tile: `{args.tile_width}x{args.tile_height}`")
    lines.append(f"- Tile retries: `{args.tile_retries}`")
    lines.append("")
    lines.append("| Response tile cols | Pass | Retry events | Mean FPGA s | Min s | Max s | CV | Mean pps |")
    lines.append("|---:|---:|---:|---:|---:|---:|---:|---:|")
    for cols in args.response_tile_cols:
        group = [r for r in results if r["response_tile_cols"] == cols]
        passed = [r for r in group if r["ok"] and r["fpga_time"] is not None]
        times = [r["fpga_time"] for r in passed]
        pps_values = [r["pps"] for r in passed if r["pps"] is not None]
        avg = mean(times)
        sd = stdev(times)
        cv = (sd / avg * 100.0) if avg else None
        retries = sum(r["retry_events"] for r in group)
        lines.append(f"| `{cols}` | {len(passed)}/{len(group)} | {retries} | `{fmt(avg)}` | `{fmt(min(times) if times else None)}` | `{fmt(max(times) if times else None)}` | `{fmt(cv, 2)}%` | `{fmt(mean(pps_values), 2)}` |")
    lines.append("")
    lines.append("## Runs")
    lines.append("")
    lines.append("| Response tile cols | Run | Status | Retry events | FPGA s | pps | Log |")
    lines.append("|---:|---:|---|---:|---:|---:|---|")
    for r in results:
        status = "PASS" if r["ok"] else f"FAIL rc={r['returncode']}"
        log_rel = r["log"].relative_to(ROOT).as_posix()
        lines.append(f"| `{r['response_tile_cols']}` | {r['run']} | {status} | {r['retry_events']} | `{fmt(r['fpga_time'])}` | `{fmt(r['pps'], 2)}` | `{log_rel}` |")
    out = OUT_DIR / args.summary_name
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def main():
    parser = argparse.ArgumentParser(description="Benchmark standard scene for response tile width variants")
    parser.add_argument("--port", default="COM6")
    parser.add_argument("--runs", type=int, default=10)
    parser.add_argument("--response-tile-cols", type=int, nargs="+", default=[1920, 240, 120, 64, 32])
    parser.add_argument("--tile-width", type=int, default=1920)
    parser.add_argument("--tile-height", type=int, default=120)
    parser.add_argument("--tile-retries", type=int, default=3)
    parser.add_argument("--extra-timeout", type=int, default=7200)
    parser.add_argument("--run-tag", default="response_tile_cols")
    parser.add_argument("--summary-name", default="response_tile_cols_standard.md")
    args = parser.parse_args()

    results = []
    for cols in args.response_tile_cols:
        print(f"=== Response tile cols {cols} ===", flush=True)
        for run_idx in range(1, args.runs + 1):
            results.append(run_one(args, cols, run_idx))
            write_summary(args, results)
    summary = write_summary(args, results)
    print(f"Summary: {summary}")


if __name__ == "__main__":
    main()
