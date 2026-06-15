#!/usr/bin/env python3
"""Benchmark several host tile sizes across the standard 1080p scenes."""

import argparse
import pathlib
import re
import subprocess
import sys
import time

from host_tile_stability_benchmark import SCENES_1080P, ROOT, HOST, slug


OUT_DIR = ROOT / "python" / "host_tile_size_matrix"
TILE_SIZES = [(80, 60), (320, 120), (960, 120), (1920, 120), (1920, 240)]


def parse_host_text(text, returncode, elapsed, scene, tile_w, tile_h, log_path, output_path):
    fpga_time = None
    pps = None
    total_time = None
    retry_events = len(re.findall(r"Tile receive failed", text))
    m = re.search(r"FPGA elapsed: ([0-9.]+)s \(([0-9.]+) pixels/s\)", text)
    if m:
        fpga_time = float(m.group(1))
        pps = float(m.group(2))
    m = re.search(r"Total elapsed: ([0-9.]+)s", text)
    if m:
        total_time = float(m.group(1))
    ok = returncode == 0 and fpga_time is not None
    return {
        "scene": scene["name"],
        "tile_w": tile_w,
        "tile_h": tile_h,
        "ok": ok,
        "returncode": returncode,
        "fpga_time": fpga_time,
        "pps": pps,
        "total_time": total_time,
        "wall_time": elapsed,
        "retry_events": retry_events,
        "log": log_path,
        "output": output_path,
    }


def run_one(args, scene, tile_w, tile_h):
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    tile_name = f"{tile_w}x{tile_h}"
    scene_slug = slug(scene["name"])
    log_path = OUT_DIR / f"{tile_name}_{scene_slug}.log"
    output_path = OUT_DIR / f"{tile_name}_{scene_slug}.png"
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
        "--tile-width", str(tile_w),
        "--tile-height", str(tile_h),
        "--tile-retries", str(args.tile_retries),
        "--quiet",
        "--output", str(output_path),
    ]
    if args.verify:
        cmd.append("--verify")
    print(f"=== tile {tile_name}: {scene['name']} ===", flush=True)
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
    result = parse_host_text(text, returncode, elapsed, scene, tile_w, tile_h, log_path, output_path)
    status = "PASS" if result["ok"] else f"FAIL rc={returncode}"
    print(f"{status}: fpga={result['fpga_time']}s pps={result['pps']} retries={result['retry_events']} wall={elapsed:.3f}s", flush=True)
    return result


def load_one(scene, tile_w, tile_h):
    tile_name = f"{tile_w}x{tile_h}"
    scene_slug = slug(scene["name"])
    log_path = OUT_DIR / f"{tile_name}_{scene_slug}.log"
    output_path = OUT_DIR / f"{tile_name}_{scene_slug}.png"
    text = log_path.read_text(encoding="utf-8", errors="replace")
    returncode = 1 if "Traceback (most recent call last)" in text else 0
    return parse_host_text(text, returncode, 0.0, scene, tile_w, tile_h, log_path, output_path)


def fmt(value, digits=3):
    if value is None:
        return "Fail"
    return f"{value:.{digits}f}"


def summarize(results):
    lines = []
    lines.append("# Host Tile Size Matrix")
    lines.append("")
    lines.append("- Resolution: `1920x1080`")
    lines.append("- UART baud: `12000000`")
    lines.append("- Runs: one run per scene and tile size")
    lines.append("- Verification: disabled by default; this matrix measures FPGA/transport elapsed time")
    lines.append("")
    lines.append("## By Scene")
    lines.append("")
    lines.append("| Scene | Tile | Host tiles/frame | Status | Retry events | FPGA s | pps |")
    lines.append("|---|---:|---:|---|---:|---:|---:|")
    for scene in SCENES_1080P:
        for tile_w, tile_h in TILE_SIZES:
            result = next((r for r in results if r["scene"] == scene["name"] and r["tile_w"] == tile_w and r["tile_h"] == tile_h), None)
            host_tiles = ((scene["width"] + tile_w - 1) // tile_w) * ((scene["height"] + tile_h - 1) // tile_h)
            if result is None:
                lines.append(f"| {scene['name']} | `{tile_w}x{tile_h}` | {host_tiles} | Missing | 0 | `Fail` | `Fail` |")
                continue
            status = "PASS" if result["ok"] else f"FAIL rc={result['returncode']}"
            lines.append(f"| {scene['name']} | `{tile_w}x{tile_h}` | {host_tiles} | {status} | {result['retry_events']} | `{fmt(result['fpga_time'])}` | `{fmt(result['pps'], 2)}` |")

    lines.append("")
    lines.append("## By Tile Size")
    lines.append("")
    lines.append("| Tile | Host tiles/frame | Passed scenes | Total FPGA s | Mean pps | Retry events |")
    lines.append("|---:|---:|---:|---:|---:|---:|")
    for tile_w, tile_h in TILE_SIZES:
        tile_results = [r for r in results if r["tile_w"] == tile_w and r["tile_h"] == tile_h and r["ok"]]
        host_tiles = ((1920 + tile_w - 1) // tile_w) * ((1080 + tile_h - 1) // tile_h)
        total_time = sum(r["fpga_time"] for r in tile_results if r["fpga_time"] is not None)
        pps_values = [r["pps"] for r in tile_results if r["pps"] is not None]
        mean_pps = sum(pps_values) / len(pps_values) if pps_values else None
        retries = sum(r["retry_events"] for r in results if r["tile_w"] == tile_w and r["tile_h"] == tile_h)
        lines.append(f"| `{tile_w}x{tile_h}` | {host_tiles} | {len(tile_results)}/6 | `{fmt(total_time)}` | `{fmt(mean_pps, 2)}` | {retries} |")

    out = OUT_DIR / "host_tile_size_matrix_results.md"
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def main():
    parser = argparse.ArgumentParser(description="Host tile size matrix benchmark")
    parser.add_argument("--port", default="COM9")
    parser.add_argument("--tile-retries", type=int, default=3)
    parser.add_argument("--extra-timeout", type=int, default=7200)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    results = []
    for tile_w, tile_h in TILE_SIZES:
        for scene in SCENES_1080P:
            log_path = OUT_DIR / f"{tile_w}x{tile_h}_{slug(scene['name'])}.log"
            if args.resume and log_path.exists():
                result = load_one(scene, tile_w, tile_h)
                if result["ok"]:
                    print(f"=== tile {tile_w}x{tile_h}: {scene['name']}: resume PASS ===", flush=True)
                else:
                    print(f"=== tile {tile_w}x{tile_h}: {scene['name']}: resume stale FAIL, rerun ===", flush=True)
                    result = run_one(args, scene, tile_w, tile_h)
            else:
                result = run_one(args, scene, tile_w, tile_h)
            results.append(result)
            summarize(results)
    summary = summarize(results)
    print(f"Summary: {summary}")


if __name__ == "__main__":
    main()
