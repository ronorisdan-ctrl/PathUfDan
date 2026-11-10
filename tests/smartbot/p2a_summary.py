# Summarises atlas_p2a CSVs: wins per class, clear median, Warden fight median (clear - time to boss), deaths.
#   python tests/smartbot/p2a_summary.py tests/smartbot/out/atlas_p2a_r1_v1_rot0.csv [...]
import csv, sys, statistics as st
for path in sys.argv[1:]:
    rows = list(csv.DictReader(open(path, encoding="utf-8")))
    print("==", path, len(rows), "runs")
    by = {}
    for r in rows:
        by.setdefault(r["class"], []).append(r)
    tot = 0
    allf = []
    for c, rs in sorted(by.items()):
        won = [r for r in rs if r["outcome"] == "boss_killed"]
        tot += len(won)
        fights = [float(r["clear_time"]) - float(r["time_to_boss"]) for r in won if float(r["time_to_boss"]) >= 0]
        allf += fights
        deaths = [r.get("cause_of_death", "") for r in rs if r["outcome"] != "boss_killed"]
        print("  %-8s %d/%d  clear %s  warden fight %s s  deaths: %s" % (c, len(won), len(rs),
            int(st.median([float(r["clear_time"]) for r in won])) if won else "-",
            round(st.median(fights), 1) if fights else "-", "; ".join(d or r_out for d, r_out in zip(deaths, [r["outcome"] for r in rs if r["outcome"] != "boss_killed"]))))
    print("  total %d/%d  warden fight median %s s" % (tot, len(rows), round(st.median(allf), 1) if allf else "-"))
