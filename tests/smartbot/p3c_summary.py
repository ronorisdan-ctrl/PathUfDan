#!/usr/bin/env python3
"""Endgame Phase 3C summary of tests/smartbot/out/p3c (run_atlas_p3c.ps1): win rate, clear time, Ash per run,
time ahead of the fire front, cisterns, burn deaths; Pigment Wells fills, chest kinds and value.
  python tests/smartbot/p3c_summary.py [--tag v1] [--md out.md]"""
import argparse, csv, glob, os, re, statistics as S

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out", "p3c")


def seg(notes, prefix):
    """key=value pairs of the note that starts with prefix (e.g. 'burn:')."""
    i = notes.find(prefix)
    if i < 0:
        return None
    out = {}
    first = True
    for tok in notes[i + len(prefix):].split("|"):
        if first:
            first = False
            if prefix == "wells:":   # crimson=0.62+ochre=0.30
                out["fills"] = {k: float(v) for k, v in (p.split("=") for p in tok.split("+") if "=" in p)}
                continue
        if "=" not in tok:
            break
        k, v = tok.split("=", 1)
        if k in out:
            break
        out[k] = v
    return out


def mean(xs):
    return round(S.mean(xs), 1) if xs else "-"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="v1")
    ap.add_argument("--md", default="")
    a = ap.parse_args()
    lines = ["| cell | Rot | class | runs | wins | deaths (fire) | clear s (wins) | kills | Ash/run | ahead % | caught | cisterns | burn dmg | front reached arena s |",
             "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    wl = ["| cell | Rot | class | runs | wins | fills (mean per colour) | full wells/run | chests | draws/run | value/run | legendaries |",
          "|---|---|---|---|---|---|---|---|---|---|---|"]
    agg = {}
    for f in sorted(glob.glob(os.path.join(OUT, f"typical_*_{a.tag}.csv"))):
        m = re.match(r"typical_(\w+?)_(\w+)_rot(\d+)_" + re.escape(a.tag) + r"\.csv", os.path.basename(f))
        if not m:
            continue
        cls, cell, rot = m.group(1), m.group(2), int(m.group(3))
        rows = [r for r in csv.DictReader(open(f, newline="", encoding="utf-8")) if r.get("outcome")]
        if not rows:
            continue
        wins = [r for r in rows if r["outcome"] == "boss_killed"]
        deaths = [r for r in rows if r["outcome"] == "died"]
        fire_deaths = [r for r in deaths if r["cause_of_death"] == "burning_canvas"]
        b = [seg(r["notes"], "burn:") for r in rows]
        b = [x for x in b if x]
        key = (cell, rot)
        g = agg.setdefault(key, {"runs": 0, "wins": 0, "clear": [], "ash": [], "ahead": []})
        g["runs"] += len(rows)
        g["wins"] += len(wins)
        g["clear"] += [float(r["clear_time"]) for r in wins]
        if b:
            g["ash"] += [int(x["ash"]) for x in b]
            g["ahead"] += [int(x["ahead_pct"]) for x in b]
        if cell != "wells":
            lines.append("| %s | %d | %s | %d | %d | %d (%d) | %s | %s | %s | %s | %s | %s | %s | %s |" % (
                cell, rot, cls, len(rows), len(wins), len(deaths), len(fire_deaths), mean([float(r["clear_time"]) for r in wins]),
                mean([int(r["kills"]) for r in rows]),
                mean([int(x["ash"]) for x in b]) if b else "-", mean([int(x["ahead_pct"]) for x in b]) if b else "-",
                "%d/%d" % (sum(1 for x in b if int(x["caught"]) > 0), len(b)) if b else "-",
                mean([int(x["cist"].split("/")[0]) for x in b]) if b else "-", mean([int(x["dmg"]) for x in b]) if b else "-",
                mean([float(x["reach_arena"]) for x in b if float(x["reach_arena"]) >= 0]) if b else "-"))
        else:
            w = [seg(r["notes"], "wells:") for r in rows]
            w = [x for x in w if x]
            cols = {}
            for x in w:
                for k, v in x["fills"].items():
                    cols.setdefault(k, []).append(v)
            kinds = {}
            for x in w:
                kinds[x["kind"]] = kinds.get(x["kind"], 0) + 1
            wl.append("| %s | %d | %s | %d | %d | %s | %s | %s | %s | %s | %d |" % (
                cell, rot, cls, len(rows), len(wins), ", ".join("%s %.2f" % (k, S.mean(v)) for k, v in sorted(cols.items())),
                mean([int(x["full"]) for x in w]), ", ".join("%s %d" % kv for kv in sorted(kinds.items())),
                mean([int(x["draws"]) for x in w]), mean([int(x["value"]) for x in w]), sum(int(x["leg"]) for x in w)))
    tot = ["", "| cell | Rot | runs | win % | clear s | Ash/run | ahead % |", "|---|---|---|---|---|---|---|"]
    for (cell, rot), g in sorted(agg.items()):
        tot.append("| %s | %d | %d | %d%% | %s | %s | %s |" % (cell, rot, g["runs"], round(100 * g["wins"] / max(1, g["runs"])), mean(g["clear"]), mean(g["ash"]), mean(g["ahead"])))
    text = "\n".join(lines + [""] + wl + tot)
    print(text)
    if a.md:
        open(a.md, "w", encoding="utf-8").write(text + "\n")


if __name__ == "__main__":
    main()
