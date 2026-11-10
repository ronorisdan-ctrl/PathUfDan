# Summarises atlas_p1e CSVs: boss kills / deaths per class, clear median, damage taken median, mechanic notes.
#   python tests/smartbot/p1e_summary.py tests/smartbot/out/atlas_p1e_r3_p2_rot4.csv [...]
import csv, sys, statistics, re
for path in sys.argv[1:]:
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    print("==", path, len(rows), "runs")
    by = {}
    for r in rows:
        by.setdefault(r["class"], []).append(r)
    tot = 0
    for c, rs in sorted(by.items()):
        k = sum(1 for r in rs if r["outcome"] == "boss_killed")
        tot += k
        ct = [float(r["clear_time"]) for r in rs if r["outcome"] == "boss_killed" and r["clear_time"] not in ("", "-1")]
        dt = [float(r["damage_taken"]) for r in rs]
        deaths = [r.get("cause_of_death", "") for r in rs if r["outcome"] == "died"]
        print("  %-8s %d/%d  clear %s  dmg %s  deaths: %s" % (c, k, len(rs), int(statistics.median(ct)) if ct else "-", int(statistics.median(dt)) if dt else "-", "; ".join(deaths)))
    print("  total %d/%d" % (tot, len(rows)))
    fl = [int(m.group(1)) for r in rows for m in [re.search(r"flakes:(\d+)", r.get("notes", ""))] if m]
    du = [int(m.group(1)) for r in rows for m in [re.search(r"dust:(\d+)", r.get("notes", ""))] if m]
    if fl: print("  flakes/run %.1f" % (sum(fl) / len(fl)))
    if du: print("  dust/run %.1f" % (sum(du) / len(du)))
    pg = set(m.group(1) for r in rows for m in [re.search(r"pig:([^ ;,]+)", r.get("notes", ""))] if m)
    if pg: print("  pigments", pg)
