#!/usr/bin/env python3
"""Phase D re-measure (docs/PHASE_D_MEASUREMENTS.md): Rot 3-5, the Collector's Wager and the
Layer Wardens under Rot, with typical (and geared / legacy reference) bots. Measure only.

Groups (--groups):
  rot     ring 3 hex 3,0 L50: Rot 3, Rot 4, Rot 4 + 2 Pigments (seeds 900 and 1900), Rot 5 + 2 Pigments
  wager   the 9 bets forced, ring 2 (2,-1 L45) and ring 3 (3,0 L50), Rot 0, stake 1x
  warden  ring 1-3 Layer Wardens at Rot 3 / 4 / 5
  side    ring-3 Warden (Archon Velis) at Rot 4 with forced builds: ranger keystone builds, mage none / m_glacial
          (Warden fights are long enough for DPS keystones to show; plain-zone ranger boss fights last 1-3 s)
Cells: gear x class x cell. legacy uses --plan=none; typical / geared use --plan-<class>
(defaults: warrior w_earthbreaker, mage m_embers, ranger none = the Phase C picks).

  python tests/smartbot/phaseD_runner.py --godot "W:\\AI game\\Godot_v4.0-stable_win64_console.exe"
Resumes: a batch whose CSV already has the cell's run count is skipped (--force replays).
"""
import argparse, csv, os, shutil, subprocess, time

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out", "phaseD")
RINGS = {1: ("1,0", 40), 2: ("2,-1", 45), 3: ("3,0", 50)}
PIG = "--pigments=glazed,unfinished"
BETS = ["unscathed", "boss_rush", "few_skills", "frenzy", "abstinence", "iron_will", "flaking", "colourist", "archaeology"]
BET_MECH = {"flaking": "wager,glazed", "colourist": "wager,unfinished", "archaeology": "wager,vault"}


def cells(group):
    """-> list of (name, level, seed, runs, args, gears)"""
    out = []
    if group == "rot":
        hx, lv = RINGS[3]
        base = [f"--dungeon=atlas:{hx}", "--mechanic=none"]
        out.append(("rot3", lv, 900, 10, base + ["--rot=3"], ["typical"]))
        out.append(("rot4", lv, 900, 10, base + ["--rot=4"], ["typical"]))
        out.append(("rot4p", lv, 900, 10, base + ["--rot=4", PIG], ["legacy", "typical", "geared"]))
        out.append(("rot4p_s1900", lv, 1900, 10, base + ["--rot=4", PIG], ["legacy", "typical", "geared"]))
        out.append(("rot5p", lv, 900, 10, base + ["--rot=5", PIG], ["typical", "geared"]))
    elif group == "wager":
        for bet in BETS:
            for ring in (2, 3):
                hx, lv = RINGS[ring]
                a = [f"--dungeon=atlas:{hx}", "--rot=0", "--mechanic=" + BET_MECH.get(bet, "wager"), f"--wager={bet}", "--stake=1"]
                if bet == "archaeology":
                    a.append("--vaults=0")   # vault still sealed at the Collector, as in 2E
                out.append((f"wager_{bet}_r{ring}", lv, 900, 5, a, ["typical"]))
    elif group == "warden":
        for ring in (1, 2, 3):
            hx, lv = RINGS[ring]
            for rot in (3, 4, 5):
                a = [f"--dungeon=atlas:{hx}", f"--rot={rot}", "--mechanic=none", "--wager=none", "--warden=1"]
                out.append((f"W{ring}_rot{rot}", lv, 900, 10, a, ["typical"] + (["geared"] if rot == 5 else [])))
    elif group == "side":
        hx, lv = RINGS[3]
        a = [f"--dungeon=atlas:{hx}", "--rot=4", "--mechanic=none", "--wager=none", "--warden=1"]
        for b in ("r_glass", "r_perfect_aim", "r_far_aim", "r_wind"):
            out.append((f"W3_rot4_{b}", lv, 900, 10, a, ["typical"], {"ranger": b}))
        for b in ("none", "m_glacial"):
            out.append((f"W3_rot4_{b}", lv, 900, 10, a, ["typical"], {"mage": b}))
    elif group == "d2rot":     # Phase D2 dial: typical only, the four target cells
        hx, lv = RINGS[3]
        base = [f"--dungeon=atlas:{hx}", "--mechanic=none"]
        out.append(("rot3", lv, 900, 10, base + ["--rot=3"], ["typical"]))
        out.append(("rot4p", lv, 900, 10, base + ["--rot=4", PIG], ["typical"]))
        out.append(("rot4p_s1900", lv, 1900, 10, base + ["--rot=4", PIG], ["typical"]))
        out.append(("rot5p", lv, 900, 10, base + ["--rot=5", PIG], ["typical"]))
    elif group == "d2warden":  # Phase D2: ring 2 + 3 Wardens at Rot 5 (ring 1 never has Rot)
        for ring in (2, 3):
            hx, lv = RINGS[ring]
            a = [f"--dungeon=atlas:{hx}", "--rot=5", "--mechanic=none", "--wager=none", "--warden=1"]
            out.append((f"W{ring}_rot5", lv, 900, 10, a, ["typical"]))
    elif group == "dummy":     # Phase D2 (D5): ranger keystone builds on a Training Grounds dummy
        hx, lv = RINGS[3]
        for b in ("none", "r_glass", "r_perfect_aim", "r_far_aim", "r_wind", "r_wind_roll"):
            for dist in (60, 140, 220):
                a = [f"--dungeon=atlas:{hx}", f"--dummy={dist}:30"] + (["--dummy-roll=2.5"] if b == "r_wind_roll" else [])
                out.append((f"dummy_{b}_{dist}", lv, 900, 5, a, ["typical"], {"ranger": b}))
    return [c if len(c) == 7 else c + (None,) for c in out]


def rows(p):
    if not os.path.exists(p):
        return 0
    with open(p, newline="", encoding="utf-8") as f:
        return sum(1 for _ in csv.DictReader(f))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--groups", default="rot,warden,side,wager")
    ap.add_argument("--classes", default="warrior,ranger,mage")
    ap.add_argument("--gears", default="legacy,typical,geared", help="filter on the cells' gear lists")
    ap.add_argument("--only", default="", help="comma list of cell names")
    ap.add_argument("--runs", type=int, default=0, help="override the cell run count")
    ap.add_argument("--plan-warrior", default="w_earthbreaker")
    ap.add_argument("--plan-ranger", default="none")
    ap.add_argument("--plan-mage", default="m_embers")
    ap.add_argument("--tag", default="")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--tune", default="", help="Phase D2: passed to smartbot as --tune=...")
    ap.add_argument("--outdir", default="phaseD")
    a = ap.parse_args()
    global OUT
    OUT = os.path.join(HERE, "out", a.outdir)
    os.makedirs(OUT, exist_ok=True)
    gears = a.gears.split(",")
    todo = []
    for g in a.groups.split(","):
        for (name, lv, seed, runs, extra, cg, plans) in cells(g):
            if a.only and name not in a.only.split(","):
                continue
            for gear in cg:
                if gear in gears:
                    for c in a.classes.split(","):
                        if plans and c not in plans:
                            continue
                        todo.append((name, lv, seed, a.runs or runs, extra, gear, c, (plans or {}).get(c)))
    t0 = time.time()
    for i, (name, lv, seed, runs, extra, gear, c, forced) in enumerate(todo):
        out = os.path.join(OUT, f"{gear}_{c}_{name}{('_' + a.tag) if a.tag else ''}.csv")
        if not a.force and rows(out) >= runs:
            print(f"[{i + 1}/{len(todo)}] skip {os.path.basename(out)}", flush=True)
            continue
        base = out[:-4]
        for f in (out, base + "_perf.csv", base + "_kits.json", base + "_errors.txt"):
            if os.path.isfile(f):
                os.remove(f)
        for d in (base + "_rows", base + "_ckpt"):
            if os.path.isdir(d):
                shutil.rmtree(d)
        plan = forced or ("none" if gear == "legacy" else getattr(a, "plan_" + c))
        args = [a.godot, "--headless", "--fixed-fps", "60", "--path", PROJ, "res://tests/smartbot/smartbot.tscn", "--",
                f"--class={c}", "--tier=6", f"--level={lv}", f"--runs={runs}", f"--seed={seed}"] + extra + [
                "--profile=Competent", "--build=balanced", f"--gear={gear}", f"--plan={plan}", f"--jobs={runs}",
                "--out=res://tests/smartbot/out/" + a.outdir + "/" + os.path.basename(out)] + (
                [f"--tune={a.tune}"] if a.tune else [])
        with open(out + ".log", "w") as lf:
            try:
                subprocess.run(args, stdout=lf, stderr=subprocess.STDOUT, timeout=7200)
            except subprocess.TimeoutExpired:
                lf.write("\nRUNNER TIMEOUT\n")
        err = "SCRIPT ERROR" in open(out + ".log", errors="replace").read()
        print(f"[{i + 1}/{len(todo)}] {os.path.basename(out)} rows={rows(out)} {'SCRIPT ERROR' if err else ''} "
              f"({(time.time() - t0) / 60:.0f} min)", flush=True)
    print("ALL DONE", flush=True)


if __name__ == "__main__":
    main()
