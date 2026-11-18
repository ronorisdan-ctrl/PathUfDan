"""Endgame Phase 3D: summary of the Overpainter runs (run_atlas_p3d.ps1).

usage: python tests/smartbot/p3d_summary.py [--tag v1] [--dir tests/smartbot/out/p3d]

Per class and Ground Pigment set: runs, wins, win rate, fight time (wins / all), the phase that
kills the bot, sections painted / restored, poise breaks, painted-floor hits, and the try use a
win rate implies (each run is one fight: P(win within 3 tries) = 1 - (1 - p)^3, expected tries
per set = 1 + (1 - p) + (1 - p)^2).
"""
import argparse, csv, glob, os, re
from collections import defaultdict

def notes_of(row):
    out = {}
    m = re.search(r"pin:([^ ]*)", row.get("notes", ""))
    if not m:
        return out
    for kv in m.group(1).split("|"):
        if "=" in kv:
            k, v = kv.split("=", 1)
            out[k] = v
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="v1")
    ap.add_argument("--dir", default=os.path.join(os.path.dirname(__file__), "out", "p3d"))
    a = ap.parse_args()
    groups = defaultdict(list)
    for f in sorted(glob.glob(os.path.join(a.dir, "typical_*_%s.csv" % a.tag))):
        base = os.path.basename(f)[len("typical_"):-len("_%s.csv" % a.tag)]
        cls, sname = base.split("_", 1)
        with open(f, newline="") as fh:
            for row in csv.DictReader(fh):
                groups[(cls, sname)].append(row)
    if not groups:
        print("no rows for tag", a.tag)
        return
    tot = defaultdict(lambda: [0, 0])
    print("class    set        runs wins  win%   t_win  t_all  died_in(p1/p2/p3)  timeouts  painted restored breaks paint_hits  in3%  tries/set")
    for (cls, sname), rows in sorted(groups.items()):
        n = len(rows)
        wins = [r for r in rows if r["outcome"] == "boss_killed"]
        died = [r for r in rows if r["outcome"] == "died"]
        to = n - len(wins) - len(died)
        p = len(wins) / n if n else 0.0
        tw = sum(float(r["clear_time"]) for r in wins) / max(1, len(wins))
        ta = sum(float(r["clear_time"]) for r in rows) / max(1, n)
        ph = defaultdict(int)
        for r in died:
            ph[notes_of(r).get("phase", "?")] += 1
        nts = [notes_of(r) for r in rows]
        def avg(k):
            v = [float(x.get(k, 0)) for x in nts if k in x]
            return sum(v) / max(1, len(v))
        in3 = 1 - (1 - p) ** 3
        tries = 1 + (1 - p) + (1 - p) ** 2
        print("%-8s %-10s %4d %4d  %4.0f%%  %5.1f  %5.1f  %d/%d/%d              %3d     %5.1f   %5.1f  %5.1f  %6.1f    %4.0f%%  %4.2f" % (
            cls, sname, n, len(wins), 100 * p, tw, ta, ph.get("1", 0), ph.get("2", 0), ph.get("3", 0), to,
            avg("painted"), avg("restored"), avg("breaks"), avg("paint_hits"), 100 * in3, tries))
        tot[cls][0] += len(wins)
        tot[cls][1] += n
        tot["all"][0] += len(wins)
        tot["all"][1] += n
    print()
    for k in ["warrior", "ranger", "mage", "all"]:
        if tot[k][1]:
            print("%-8s %d/%d wins (%.0f%%)" % (k, tot[k][0], tot[k][1], 100 * tot[k][0] / tot[k][1]))

if __name__ == "__main__":
    main()
