#!/usr/bin/env python3
"""Run repeated host-tiled 1080p benchmarks and summarize stability."""

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

SCENES_1080P = [
    {
        "name": "fast escape @128",
        "width": 1920,
        "height": 1080,
        "max_iter": 128,
        "center": (1.0, 1.0),
        "step": "0.002",
        "timeout": 600,
        "baseline_100mhz_4ctx": 4.683,
        "baseline_pps": 443288.08,
    },
    {
        "name": "standard @64",
        "width": 1920,
        "height": 1080,
        "max_iter": 64,
        "center": (-0.5, 0.0),
        "step": "0.002",
        "timeout": 600,
        "baseline_100mhz_4ctx": 5.782,
        "baseline_pps": 493434.63,
    },
    {
        "name": "Seahorse zoom @512",
        "width": 1920,
        "height": 1080,
        "max_iter": 512,
        "center": (-0.743643887037151, 0.13182590420533),
        "step": "5e-6",
        "timeout": 900,
        "baseline_100mhz_4ctx": 9.836,
        "baseline_pps": 120003.12,
    },
    {
        "name": "deep tendrils @8192",
        "width": 1920,
        "height": 1080,
        "max_iter": 8192,
        "center": (-0.77568377, 0.13646737),
        "step": "1e-9",
        "timeout": 2400,
        "baseline_100mhz_4ctx": 17.677,
        "baseline_pps": 62096.41,
    },
    {
        "name": "deep mini-brot @8192",
        "width": 1920,
        "height": 1080,
        "max_iter": 8192,
        "center": (-1.25066, 0.02012),
        "step": "1e-9",
        "timeout": 3600,
        "baseline_100mhz_4ctx": 44.146,
        "baseline_pps": 24854.93,
    },
    {
        "name": "deep Seahorse @1024",
        "width": 1920,
        "height": 1080,
        "max_iter": 1024,
        "center": (-0.743643887037151, 0.13182590420533),
        "step": "1e-8",
        "timeout": 1200,
        "baseline_100mhz_4ctx": 19.965,
        "baseline_pps": 56842.30,
    },
]


def slug(text):
    return re.sub(r"[^a-zA-Z0-9]+", "_", text).strip("_").lower()


def parse_host_text(text, returncode, elapsed, scene, run_idx, log_path, output_path):
    fpga_time = None
    pps = None
    sw_time = None
    total_time = None
    match = None
    match_total = None
    match_pct = None

    m = re.search(r"FPGA elapsed: ([0-9.]+)s \(([0-9.]+) pixels/s\)", text)
    if m:
        fpga_time = float(m.group(1))
        pps = float(m.group(2))
    m = re.search(r"Software elapsed: ([0-9.]+)s", text)
    if m:
        sw_time = float(m.group(1))
    m = re.search(r"Total elapsed: ([0-9.]+)s", text)
    if m:
        total_time = float(m.group(1))
    m = re.search(r"HW vs SW: (\d+)/(\d+) match \(([0-9.]+)%\)", text)
    if m:
        match = int(m.group(1))
        match_total = int(m.group(2))
        match_pct = float(m.group(3))

    expected_pixels = scene["width"] * scene["height"]
    complete_frame = match_total == expected_pixels
    # Deep zoom scenes have known FP64/SW boundary differences. Treat the
    # run as a transport pass when the process exits successfully and the
    # full frame was received; report exact SW match separately.
    ok = returncode == 0 and complete_frame
    failed_attempts = len(re.findall(r"compute tile receive failed", text, re.IGNORECASE))
    recovered = [int(v) for v in re.findall(r"Recovered\s+(\d+)\s+failed compute tile attempts", text, re.IGNORECASE)]
    retry_events = max([failed_attempts] + recovered)

    return {
        "scene": scene["name"],
        "run": run_idx,
        "ok": ok,
        "returncode": returncode,
        "fpga_time": fpga_time,
        "pps": pps,
        "sw_time": sw_time,
        "total_time": total_time,
        "wall_time": elapsed,
        "match": match,
        "match_total": match_total,
        "match_pct": match_pct,
        "exact_match": match == match_total if match is not None else False,
        "retry_events": retry_events,
        "log": log_path,
        "output": output_path,
    }


def run_one(args, scene, run_idx):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    scene_slug = slug(scene["name"])
    log_path = OUT_DIR / f"{scene_slug}_run{run_idx}.log"
    output_path = OUT_DIR / f"{scene_slug}_run{run_idx}.png"
    cmd = [
        sys.executable,
        str(HOST),
        "--port", args.port,
        "--width", str(scene["width"]),
        "--height", str(scene["height"]),
        "--max-iter", str(scene["max_iter"]),
        "--center", str(scene["center"][0]), str(scene["center"][1]),
        "--step", str(scene["step"]),
        "--timeout", str(scene["timeout"]),
        "--verify",
        "--tile-width", str(args.tile_width),
        "--tile-height", str(args.tile_height),
        "--tile-retries", str(args.tile_retries),
        "--quiet",
        "--output", str(output_path),
    ]
    print(f"=== {scene['name']} run {run_idx}/{args.runs} ===", flush=True)
    started = time.perf_counter()
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(ROOT),
            text=True,
            capture_output=True,
            timeout=scene["timeout"] + args.extra_timeout,
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
    result = parse_host_text(text, returncode, elapsed, scene, run_idx, log_path, output_path)
    status = "PASS" if result["ok"] else "FAIL"
    print(f"{status}: fpga={result['fpga_time']}s pps={result['pps']} wall={elapsed:.3f}s", flush=True)
    return result


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


def summarize(results, args):
    lines = []
    lines.append("# Host-Tiled 12 Mbaud Stability Benchmark")
    lines.append("")
    lines.append(f"- Runs per scene: `{args.runs}`")
    lines.append(f"- Host tile: `{args.tile_width}x{args.tile_height}`")
    lines.append(f"- Tile retries: `{args.tile_retries}`")
    lines.append(f"- UART baud: `12000000`")
    lines.append("")
    lines.append("## Summary")
    lines.append("")
    lines.append("| Scene | Transport pass | Exact SW match | Retry events | Mean FPGA s | Min s | Max s | Stddev s | CV | Mean pps | vs 100MHz 4ctx |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")

    for scene in SCENES_1080P:
        scene_results = [r for r in results if r["scene"] == scene["name"]]
        passed = [r for r in scene_results if r["ok"] and r["fpga_time"] is not None]
        times = [r["fpga_time"] for r in passed]
        pps_values = [r["pps"] for r in passed if r["pps"] is not None]
        avg = mean(times)
        sd = stdev(times)
        cv = (sd / avg * 100.0) if avg else None
        ratio = (scene["baseline_100mhz_4ctx"] / avg) if avg else None
        exact = [r for r in passed if r["exact_match"]]
        retries = sum(r["retry_events"] for r in scene_results)
        lines.append(
            f"| {scene['name']} | {len(passed)}/{len(scene_results)} | {len(exact)}/{len(passed)} | {retries} | `{fmt(avg)}` | `{fmt(min(times) if times else None)}` | "
            f"`{fmt(max(times) if times else None)}` | `{fmt(sd)}` | `{fmt(cv, 2)}%` | `{fmt(mean(pps_values), 2)}` | `{fmt(ratio, 3)}x` |"
        )

    lines.append("")
    lines.append("## Runs")
    lines.append("")
    lines.append("| Scene | Run | Status | Retry events | FPGA s | pps | Match | Log |")
    lines.append("|---|---:|---|---:|---:|---:|---|---|")
    for r in results:
        status = "PASS" if r["ok"] else f"FAIL rc={r['returncode']}"
        match = f"{r['match']}/{r['match_total']}" if r["match"] is not None else "n/a"
        log_rel = r["log"].relative_to(ROOT).as_posix()
        lines.append(f"| {r['scene']} | {r['run']} | {status} | {r['retry_events']} | `{fmt(r['fpga_time'])}` | `{fmt(r['pps'], 2)}` | {match} | `{log_rel}` |")

    out = OUT_DIR / "host_tile_stability_results.md"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def main():
    parser = argparse.ArgumentParser(description="Repeated host-tiled 1080p stability benchmark")
    parser.add_argument("--port", default="COM9")
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--tile-width", type=int, default=1920)
    parser.add_argument("--tile-height", type=int, default=120)
    parser.add_argument("--tile-retries", type=int, default=3)
    parser.add_argument("--extra-timeout", type=int, default=7200)
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    results = []
    for scene in SCENES_1080P:
        scene_slug = slug(scene["name"])
        for run_idx in range(1, args.runs + 1):
            log_path = OUT_DIR / f"{scene_slug}_run{run_idx}.log"
            output_path = OUT_DIR / f"{scene_slug}_run{run_idx}.png"
            if args.resume and log_path.exists():
                text = log_path.read_text(encoding="utf-8", errors="replace")
                returncode = 1 if "Traceback (most recent call last)" in text else 0
                result = parse_host_text(text, returncode, 0.0, scene, run_idx, log_path, output_path)
                if result["ok"]:
                    print(f"=== {scene['name']} run {run_idx}/{args.runs}: resume PASS ===", flush=True)
                else:
                    print(f"=== {scene['name']} run {run_idx}/{args.runs}: resume stale FAIL, rerun ===", flush=True)
                    result = run_one(args, scene, run_idx)
            else:
                result = run_one(args, scene, run_idx)
            results.append(result)
            summarize(results, args)

    summary = summarize(results, args)
    print(f"Summary: {summary}")


if __name__ == "__main__":
    main()
