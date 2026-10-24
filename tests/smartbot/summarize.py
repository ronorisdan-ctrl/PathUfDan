#!/usr/bin/env python3
"""Summarise smartbot CSVs (stdlib only).

    python tests/smartbot/summarize.py out/a.csv [out/b.csv ...] [--by=tier,level,class,profile]

Prints one line per group: runs, win% with a 95% Wilson interval, deaths, timeouts, mean
damage taken, mean clear time of wins, dodge attempts / avoided / failed, potions, and the
most common causes of death.
"""
import csv, sys, math, collections, statistics as st

def wilson(k, n, z=1.96):
    if n == 0:
        return (0.0, 0.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    r = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - r) / d, (c + r) / d)

def level_of(r):
    try:
        return int(r["run_id"].split("-L")[1].split("-")[0])
    except Exception:
        return int(r.get("start_level", 0))

def main():
    files = [a for a in sys.argv[1:] if not a.startswith("--")]
    by = ["tier", "level", "class", "profile"]
    for a in sys.argv[1:]:
        if a.startswith("--by="):
            by = a[5:].split(",")
    rows = []
    for f in files:
        rows += list(csv.DictReader(open(f, newline="")))
    g = collections.defaultdict(list)
    for r in rows:
        key = tuple(level_of(r) if k == "level" else r.get(k, "") for k in by)
        g[key].append(r)
    order = {"NoDodge": 0, "Competent": 1, "Expert": 2}
    print("  ".join(by) + "  |  n  win%  [95% CI]  died tout  dmg  clear  dodges avoided failed  pots  top causes")
    for k in sorted(g, key=lambda k: [str(order.get(x, x)).zfill(4) if isinstance(x, str) else str(x).zfill(4) for x in k]):
        rs = g[k]
        n = len(rs)
        w = sum(r["outcome"] == "boss_killed" for r in rs)
        d = sum(r["outcome"] == "died" for r in rs)
        lo, hi = wilson(w, n)
        mean = lambda c: st.mean(float(r[c]) for r in rs)
        ct = [float(r["clear_time"]) for r in rs if r["outcome"] == "boss_killed"]
        causes = collections.Counter(r["cause_of_death"] for r in rs if r["outcome"] == "died").most_common(3)
        print("%s  | %3d  %5.1f [%4.0f-%3.0f]  %3d %3d  %6.0f %5.0f  %6.1f %6.1f %5.1f  %4.1f  %s" % (
            "  ".join(str(x) for x in k), n, 100.0 * w / n, 100 * lo, 100 * hi, d, n - w - d,
            mean("damage_taken"), st.mean(ct) if ct else 0, mean("dodge_attempts"), mean("hits_avoided"),
            mean("evade_failed"), mean("potions_used"), "; ".join("%s x%d" % c for c in causes)))

if __name__ == "__main__":
    main()
