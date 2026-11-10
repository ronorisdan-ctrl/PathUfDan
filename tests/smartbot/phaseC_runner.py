#!/usr/bin/env python3
"""Phase C real-run matrix (docs/PHASE_C_MEASUREMENTS.md).

3 classes x 3 gear profiles (legacy / typical / geared) x 8 stages
(T3, T6, Atlas rings 1-3 plain, and the ring 1-3 Layer Wardens), Competent, balanced.
legacy uses --plan=none (the frozen-baseline bot); typical and geared use --plan=auto
(build_picks.json), unless --plan-<class> overrides it.

  python tests/smartbot/phaseC_runner.py --godot "W:\\AI game\\Godot_v4.0-stable_win64_console.exe" --runs 10
Resumes: a batch whose CSV already has --runs rows is skipped (use --force to replay).
"""
import argparse, csv, os, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out", "phaseC")
ATLAS = ["--rot=0", "--mechanic=none", "--wager=none"]
# stage -> (tier, level, seed, extra args)
STAGES = {
    "T3": (3, 20, 700, []),
    "T6": (6, 46, 700, []),
    "R1": (6, 40, 900, ["--dungeon=atlas:1,0"] + ATLAS),
    "R2": (6, 45, 900, ["--dungeon=atlas:2,-1"] + ATLAS),
    "R3": (6, 50, 900, ["--dungeon=atlas:3,0"] + ATLAS),
    "W1": (6, 40, 900, ["--dungeon=atlas:1,0"] + ATLAS + ["--warden=1"]),
    "W2": (6, 45, 900, ["--dungeon=atlas:2,-1"] + ATLAS + ["--warden=1"]),
    "W3": (6, 50, 900, ["--dungeon=atlas:3,0"] + ATLAS + ["--warden=1"]),
}


def path(gear, cls, stage, tag=""):
    return os.path.join(OUT, f"{gear}_{cls}_{stage}{('_' + tag) if tag else ''}.csv")


def rows(p):
    if not os.path.exists(p):
        return 0
    with open(p, newline="", encoding="utf-8") as f:
        return sum(1 for _ in csv.DictReader(f))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--classes", default="warrior,ranger,mage")
    ap.add_argument("--gears", default="legacy,typical,geared")
    ap.add_argument("--stages", default=",".join(STAGES))
    ap.add_argument("--plan-warrior", default="auto")
    ap.add_argument("--plan-ranger", default="auto")
    ap.add_argument("--plan-mage", default="auto")
    ap.add_argument("--tag", default="", help="suffix for side cells, e.g. a forced build")
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    todo = [(g, c, s) for s in a.stages.split(",") for g in a.gears.split(",") for c in a.classes.split(",")]
    t0 = time.time()
    for i, (g, c, s) in enumerate(todo):
        out = path(g, c, s, a.tag)
        if not a.force and rows(out) >= a.runs:
            print(f"[{i + 1}/{len(todo)}] skip {os.path.basename(out)}", flush=True)
            continue
        if a.force:
            base = out[:-4]
            for f in (out, base + "_perf.csv", base + "_kits.json", base + "_errors.txt"):
                if os.path.isfile(f):
                    os.remove(f)
            for d in (base + "_rows", base + "_ckpt"):
                if os.path.isdir(d):
                    shutil.rmtree(d)
        tier, lvl, seed, extra = STAGES[s]
        plan = "none" if g == "legacy" else getattr(a, "plan_" + c)
        args = [a.godot, "--headless", "--fixed-fps", "60", "--path", PROJ, "res://tests/smartbot/smartbot.tscn", "--",
                f"--class={c}", f"--tier={tier}", f"--level={lvl}", f"--runs={a.runs}", f"--seed={seed}"] + extra + [
                "--profile=Competent", "--build=balanced", f"--gear={g}", f"--plan={plan}", f"--jobs={a.runs}",
                "--out=res://tests/smartbot/out/phaseC/" + os.path.basename(out)]
        with open(out + ".log", "w") as lf:
            subprocess.run(args, stdout=lf, stderr=subprocess.STDOUT, timeout=7200)
        err = "SCRIPT ERROR" in open(out + ".log", errors="replace").read()
        print(f"[{i + 1}/{len(todo)}] {os.path.basename(out)} rows={rows(out)} {'SCRIPT ERROR' if err else ''} "
              f"({(time.time() - t0) / 60:.0f} min)", flush=True)
    print("ALL DONE", flush=True)


if __name__ == "__main__":
    main()
