#!/usr/bin/env python3
"""Run fractional-UART full-protocol benchmarks and write Markdown results."""

import argparse
import pathlib
import re
import subprocess
import sys
import time

from uart_ft232h_sweep import ROOT, HOST, set_baud, build_and_program_full


CANDIDATE_BAUDS = [576000, 1000000, 2000000, 4000000, 6000000, 8000000, 12000000]

SMALL_CASE = {
    "name": "160x120 standard",
    "width": 160,
    "height": 120,
    "max_iter": 64,
    "center": (-0.5, 0.0),
    "step": "0.005",
    "timeout": 180,
}

SCENES_1080P = [
    {
        "name": "fast escape @128",
        "width": 1920,
        "height": 1080,
        "max_iter": 128,
        "center": (1.0, 1.0),
        "step": "0.002",
        "timeout": 600,
    },
    {
        "name": "standard @64",
        "width": 1920,
        "height": 1080,
        "max_iter": 64,
        "center": (-0.5, 0.0),
        "step": "0.002",
        "timeout": 600,
    },
    {
        "name": "Seahorse zoom @512",
        "width": 1920,
        "height": 1080,
        "max_iter": 512,
        "center": (-0.743643887037151, 0.13182590420533),
        "step": "5e-6",
        "timeout": 900,
    },
    {
        "name": "deep tendrils @8192",
        "width": 1920,
        "height": 1080,
        "max_iter": 8192,
        "center": (-0.77568377, 0.13646737),
        "step": "1e-9",
        "timeout": 2400,
    },
    {
        "name": "deep mini-brot @8192",
        "width": 1920,
        "height": 1080,
        "max_iter": 8192,
        "center": (-1.25066, 0.02012),
        "step": "1e-9",
        "timeout": 3600,
    },
    {
        "name": "deep Seahorse @1024",
        "width": 1920,
        "height": 1080,
        "max_iter": 1024,
        "center": (-0.743643887037151, 0.13182590420533),
        "step": "1e-8",
        "timeout": 1200,
    },
]


def slug(text):
    return re.sub(r"[^a-zA-Z0-9]+", "_", text).strip("_").lower()


def parse_host_text(text, returncode, elapsed, baud, case, output):
    fpga_time = None
    pps = None
    sw_time = None
    total_time = None
    match = None
    match_total = None
    match_pct = None
    fpga_match = re.search(r"FPGA elapsed: ([0-9.]+)s \(([0-9.]+) pixels/s\)", text)
    if fpga_match:
        fpga_time = float(fpga_match.group(1))
        pps = float(fpga_match.group(2))
    sw_match = re.search(r"Software elapsed: ([0-9.]+)s", text)
    if sw_match:
        sw_time = float(sw_match.group(1))
    total_match = re.search(r"Total elapsed: ([0-9.]+)s", text)
    if total_match:
        total_time = float(total_match.group(1))
    verify_match = re.search(r"HW vs SW: (\d+)/(\d+) match \(([0-9.]+)%\)", text)
    if verify_match:
        match = int(verify_match.group(1))
        match_total = int(verify_match.group(2))
        match_pct = float(verify_match.group(3))

    ok = returncode == 0 and match is not None and match == match_total
    return {
        "name": case["name"],
        "baud": baud,
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
        "output": output,
        "stdout": text,
    }


def run_host(port, baud, case, out_dir, prefix):
    output = out_dir / f"{prefix}_{baud}_{slug(case['name'])}.png"
    cmd = [
        sys.executable,
        str(HOST),
        "--port",
        port,
        "--width",
        str(case["width"]),
        "--height",
        str(case["height"]),
        "--max-iter",
        str(case["max_iter"]),
        "--center",
        str(case["center"][0]),
        str(case["center"][1]),
        "--step",
        str(case["step"]),
        "--verify",
        "--output",
        str(output),
        "--timeout",
        str(case["timeout"]),
    ]
    started = time.perf_counter()
    try:
        proc = subprocess.run(cmd, cwd=str(ROOT), text=True, capture_output=True, timeout=case["timeout"] + 7200)
        stdout = proc.stdout
        stderr = proc.stderr
        returncode = proc.returncode
    except subprocess.TimeoutExpired as exc:
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        returncode = 124
    elapsed = time.perf_counter() - started

    text = stdout + ("\nSTDERR:\n" + stderr if stderr else "")
    return parse_host_text(text, returncode, elapsed, baud, case, output)


def load_log(path, baud, case, out_dir, prefix):
    output = out_dir / f"{prefix}_{baud}_{slug(case['name'])}.png"
    text = path.read_text(encoding="utf-8", errors="replace")
    return parse_host_text(text, 0, 0.0, baud, case, output)


def fmt(value, suffix=""):
    if value is None:
        return "Fail"
    if isinstance(value, float):
        return f"{value:.3f}{suffix}"
    return f"{value}{suffix}"


def write_log(path, result):
    path.write_text(result["stdout"], encoding="utf-8")


def write_report(path, small_results, scene_results, passed_bauds):
    lines = []
    lines.append("# Fractional UART Full-Protocol Benchmark Results")
    lines.append("")
    lines.append("## Small-Frame Gate")
    lines.append("")
    lines.append("| Baud | Result | FPGA Time | Throughput | Verify |")
    lines.append("|---:|---|---:|---:|---:|")
    for result in small_results:
        verify = "Fail" if result["match"] is None else f"{result['match']}/{result['match_total']}"
        lines.append(
            f"| {result['baud']} | {'Pass' if result['ok'] else 'Fail'} | {fmt(result['fpga_time'], 's')} | {fmt(result['pps'], ' pps')} | {verify} |"
        )
    lines.append("")
    lines.append(f"Small-frame pass baudrates: {', '.join(str(x) for x in passed_bauds) if passed_bauds else 'none'}")
    lines.append("")
    lines.append("## 1080p Verified Benchmarks")
    lines.append("")
    lines.append("| Baud | Scene | FPGA Time | Throughput | Software Time | Total Time | Verify |")
    lines.append("|---:|---|---:|---:|---:|---:|---:|")
    for result in scene_results:
        verify = "Fail" if result["match"] is None else f"{result['match']}/{result['match_total']}"
        lines.append(
            f"| {result['baud']} | {result['name']} | {fmt(result['fpga_time'], 's')} | {fmt(result['pps'], ' pps')} | {fmt(result['sw_time'], 's')} | {fmt(result['total_time'], 's')} | {verify} |"
        )
    lines.append("")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", default="COM6")
    parser.add_argument("--bauds", nargs="*", type=int, default=CANDIDATE_BAUDS)
    parser.add_argument("--out-dir", default=str(ROOT / "python" / "uart_fractional_bench"))
    parser.add_argument("--small-only", action="store_true")
    parser.add_argument("--scenes-only", action="store_true")
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--no-build", action="store_true")
    args = parser.parse_args()

    out_dir = pathlib.Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    small_results = []
    scene_results = []
    passed_bauds = []

    for baud in args.bauds:
        small_log = out_dir / f"small_{baud}.log"
        if small_log.exists():
            small = load_log(small_log, baud, SMALL_CASE, out_dir, "small")
            small_results.append(small)
            if small["ok"]:
                passed_bauds.append(baud)
        for scene in SCENES_1080P:
            scene_log = out_dir / f"1080p_{baud}_{slug(scene['name'])}.log"
            if scene_log.exists():
                scene_results.append(load_log(scene_log, baud, scene, out_dir, "1080p"))

    for baud in args.bauds:
        if args.scenes_only and baud not in passed_bauds:
            print(f"=== baud {baud}: skipped, no passing small log ===", flush=True)
            continue

        print(f"=== baud {baud}: build/program full design ===", flush=True)
        set_baud(baud)
        if not args.no_build and not build_and_program_full():
            if not args.scenes_only:
                small_results.append({"baud": baud, "ok": False, "match": None, "match_total": None, "fpga_time": None, "pps": None})
            continue

        if not args.scenes_only:
            small_log = out_dir / f"small_{baud}.log"
            if args.resume and small_log.exists():
                small = load_log(small_log, baud, SMALL_CASE, out_dir, "small")
            else:
                print(f"=== baud {baud}: small verify ===", flush=True)
                small = run_host(args.port, baud, SMALL_CASE, out_dir, "small")
                write_log(small_log, small)
                small_results = [x for x in small_results if x.get("baud") != baud]
                small_results.append(small)
            if not small["ok"]:
                write_report(out_dir / "uart_fractional_benchmark_results.md", small_results, scene_results, passed_bauds)
                continue
            if baud not in passed_bauds:
                passed_bauds.append(baud)

        if args.small_only:
            write_report(out_dir / "uart_fractional_benchmark_results.md", small_results, scene_results, passed_bauds)
            continue

        for scene in SCENES_1080P:
            scene_log = out_dir / f"1080p_{baud}_{slug(scene['name'])}.log"
            if args.resume and scene_log.exists():
                continue
            print(f"=== baud {baud}: 1080p {scene['name']} ===", flush=True)
            result = run_host(args.port, baud, scene, out_dir, "1080p")
            write_log(scene_log, result)
            scene_results.append(result)
            write_report(out_dir / "uart_fractional_benchmark_results.md", small_results, scene_results, passed_bauds)

    set_baud(576000)
    write_report(out_dir / "uart_fractional_benchmark_results.md", small_results, scene_results, passed_bauds)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
