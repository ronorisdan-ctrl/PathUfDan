"""Phase B build analyser (docs/BOT_GEAR_PROFILES.md section 4).

Plays every keystone build of sb_builds.gd (plus "none", the planner without a keystone)
in real smartbot dungeon / Atlas runs at each stage, then picks the best build per class
and stage and writes tests/smartbot/build_picks.json, which --plan=auto reads.

    python tests/smartbot/build_analyser.py --godot "W:\\AI game\\Godot_v4.0-stable_win64_console.exe" [--runs 4] [--gear typical] [--classes warrior,ranger,mage] [--stages T3,T6,R1,R3] [--jobs 4] [--summarize-only]

Ranking: a player commits to one build, so the pick is per class, the same at every stage:
the keystone build with the lowest mean "relative clear" over the stages, where relative
clear = clear time of the winning runs / the same for "none", plus 0.25 for every boss kill
fewer than "none" (per run). Stage-by-stage bests (noisier) are kept in the evidence. The
report flags each stage "gain" / "no clear gain" / "worse than none" (one boss kill or 8%).
"""
import argparse, csv, json, os, re, shutil, subprocess, sys, statistics as st
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "out", "builds")
# stage -> (tier, level, dungeon or "", seed)
STAGES = {
    "T3": (3, 20, "", 700), "T4": (4, 28, "", 700), "T5": (5, 37, "", 700), "T6": (6, 46, "", 700),
    "R1": (6, 40, "atlas:1,0", 900), "R2": (6, 45, "atlas:2,-1", 900), "R3": (6, 50, "atlas:3,0", 900),
}


def builds_by_class():
    src = open(os.path.join(HERE, "sb_builds.gd"), encoding="utf-8").read()
    out = {}
    for bid, cls in re.findall(r'"(\w+)": \{"class": "(\w+)"', src):
        out.setdefault(cls, []).append(bid)
    return out


def csv_path(gear, cls, stage, plan):
    return os.path.join(OUT, f"{gear}_{cls}_{stage}_{plan}.csv")


def run_one(a, cls, stage, plan):
    tier, lvl, dungeon, seed = STAGES[stage]
    out = csv_path(a.gear, cls, stage, plan)
    if os.path.exists(out) and not a.force:
        return out
    if a.force:
        # smartbot resumes from its CSV and its _rows/_ckpt caches, so a forced replay must clear them
        base = out[:-4]
        for f in (out, base + "_perf.csv", base + "_kits.json", base + "_errors.txt"):
            if os.path.isfile(f):
                os.remove(f)
        for d in (base + "_rows", base + "_ckpt"):
            if os.path.isdir(d):
                shutil.rmtree(d)
    res = "res://tests/smartbot/out/builds/" + os.path.basename(out)
    args = [a.godot, "--headless", "--fixed-fps", "60", "--path", PROJ, "res://tests/smartbot/smartbot.tscn", "--",
            f"--class={cls}", f"--tier={tier}", f"--level={lvl}", f"--runs={a.runs}", f"--seed={seed}",
            "--profile=Competent", "--build=balanced", f"--gear={a.gear}", f"--plan={plan}", f"--jobs={a.runs}", f"--out={res}"]
    if dungeon:
        args.insert(args.index("--profile=Competent"), f"--dungeon={dungeon}")
    with open(out + ".log", "w") as lf:
        subprocess.run(args, stdout=lf, stderr=subprocess.STDOUT, timeout=7200)
    return out


def stats(path):
    if not os.path.exists(path):
        return None
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    if not rows:
        return None
    wins = [r for r in rows if r["outcome"] == "boss_killed"]
    ct = [float(r["clear_time"]) for r in wins if float(r["clear_time"] or 0) > 0]
    return {
        "runs": len(rows), "wins": len(wins), "deaths": sum(1 for r in rows if r["outcome"] == "died"),
        "clear": st.mean(ct) if ct else 9999.0, "taken": st.mean(float(r["damage_taken"]) for r in rows),
        "dps_est": st.mean(float(r["dps_est"]) for r in rows), "ehp_est": st.mean(float(r["ehp_est"]) for r in rows),
        "keystones": sorted({k for r in rows for k in r["keystones"].split("|") if k}),
        "spec": rows[0]["spec"], "hotbar": rows[0]["hotbar"],
    }


def rank_key(s):
    return (-s["wins"], s["clear"], s["taken"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--godot", default=os.environ.get("GODOT", "godot"))
    ap.add_argument("--runs", type=int, default=4)
    ap.add_argument("--gear", default="typical")
    ap.add_argument("--classes", default="warrior,ranger,mage")
    ap.add_argument("--stages", default="T3,T6,R1,R3")
    ap.add_argument("--jobs", type=int, default=1, help="smartbot batches at once (each uses --runs child processes)")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--summarize-only", action="store_true")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    bc = builds_by_class()
    todo = []
    for cls in a.classes.split(","):
        for stage in a.stages.split(","):
            for plan in ["none"] + bc.get(cls, []):
                todo.append((cls, stage, plan))
    if not a.summarize_only:
        with ThreadPoolExecutor(max_workers=a.jobs) as ex:
            for i, p in enumerate(ex.map(lambda t: run_one(a, *t), todo)):
                print(f"[{i + 1}/{len(todo)}] {os.path.basename(p)}", flush=True)
    picks_path = os.path.join(HERE, "build_picks.json")
    picks = json.load(open(picks_path)) if os.path.exists(picks_path) else {"picks": {}, "evidence": {}}
    rel_by = {}
    lines = ["| Class | Stage | Build | Boss kills | Deaths | Clear s (wins) | Damage taken | Keystones | Spec |", "|---|---|---|---|---|---|---|---|---|"]
    for cls in a.classes.split(","):
        for stage in a.stages.split(","):
            res = {}
            for plan in ["none"] + bc.get(cls, []):
                s = stats(csv_path(a.gear, cls, stage, plan))
                if s:
                    res[plan] = s
            if not res:
                continue
            ks_builds = sorted([p for p in res if p != "none"], key=lambda p: rank_key(res[p]))
            best = ks_builds[0] if ks_builds else "none"
            note = ""
            if "none" in res and best != "none":
                n, b = res["none"], res[best]
                bw, nw = b["wins"] / max(1, b["runs"]), n["wins"] / max(1, n["runs"])
                gain = bw > nw or (bw == nw and b["clear"] < n["clear"] * 0.92)
                worse = bw < nw or (bw == nw and b["clear"] > n["clear"] * 1.08)
                note = "gain" if gain else ("worse than none" if worse else "no clear gain")
            if "none" in res:
                n = res["none"]
                for p in ks_builds:
                    b = res[p]
                    # boss-kill penalty on win rates (0.25 per kill fewer in 4 runs), so unequal run counts compare fairly
                    rel = b["clear"] / max(1.0, n["clear"]) + max(0.0, n["wins"] / max(1, n["runs"]) - b["wins"] / max(1, b["runs"]))
                    rel_by.setdefault(cls, {}).setdefault(p, []).append(rel)
            picks["evidence"].setdefault(cls, {})[stage] = {"pick": best, "vs_none": note, "gear": a.gear, "runs": a.runs,
                                                         "stage_best": best, "results": {p: {k: (round(v, 1) if isinstance(v, float) else v) for k, v in s.items()} for p, s in res.items()}}
            for p in ["none"] + ks_builds:
                s = res[p]
                mark = " (stage best)" if p == best else ""
                lines.append(f"| {cls} | {stage} | {p}{mark} | {s['wins']}/{s['runs']} | {s['deaths']} | {s['clear']:.0f} | {s['taken']:.0f} | {','.join(s['keystones']) or '-'} | {s['spec']} |")
            lines.append(f"| {cls} | {stage} | vs none: {note or '-'} | | | | | | |")
    lines.append("")
    lines.append("| Class | Build | Mean relative clear (1.00 = no keystone) | Per stage |")
    lines.append("|---|---|---|---|")
    for cls, d in rel_by.items():
        order = sorted(d, key=lambda p: st.mean(d[p]))
        for stage in a.stages.split(","):
            picks["picks"].setdefault(cls, {})[stage] = order[0]
        picks.setdefault("class_pick", {})[cls] = {"build": order[0], "mean_relative_clear": round(st.mean(d[order[0]]), 3)}
        for p in order:
            mark = " **pick**" if p == order[0] else ""
            lines.append(f"| {cls} | {p}{mark} | {st.mean(d[p]):.2f} | {' / '.join('%.2f' % x for x in d[p])} |")
    json.dump(picks, open(picks_path, "w"), indent=1)
    rep = os.path.join(OUT, f"analyser_{a.gear}.md")
    open(rep, "w").write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print("wrote", picks_path, "and", rep)


if __name__ == "__main__":
    main()
