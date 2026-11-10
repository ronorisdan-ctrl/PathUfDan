#!/usr/bin/env python3
"""Summarise the Phase C matrix (tests/smartbot/out/phaseC/*.csv) into markdown + JSON.
  python tests/smartbot/phaseC_summary.py [out_dir]
"""
import csv, glob, json, os, re, statistics as st, sys

HERE = os.path.dirname(os.path.abspath(__file__))
D = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "out", "phaseC")
STAGES = ["T3", "T6", "R1", "R2", "R3", "W1", "W2", "W3"]
GEARS = ["legacy", "typical", "geared"]
CLASSES = ["warrior", "ranger", "mage"]


def m(xs):
    return st.mean(xs) if xs else float("nan")


def cell(p):
    rs = list(csv.DictReader(open(p, newline="", encoding="utf-8")))
    if not rs:
        return None
    win = [r for r in rs if r["outcome"] == "boss_killed"]
    f = lambda k, R: [float(r[k]) for r in R if r.get(k, "") not in ("", None)]
    fight = [float(r["clear_time"]) - float(r["time_to_boss"]) for r in win if r["time_to_boss"] and r["clear_time"]]
    wn = [r for r in rs if "warden:" in r.get("notes", "")]
    ks = sorted({r["keystones"] for r in rs if r["keystones"]})
    return {"runs": len(rs), "wins": len(win), "deaths": int(sum(f("deaths_total", rs))),
            "timeouts": sum(1 for r in rs if r["outcome"] == "timeout"),
            "clear": m(f("clear_time", win)), "to_boss": m(f("time_to_boss", win)), "fight": m(fight),
            "fight_med": st.median(fight) if fight else float("nan"),
            "taken": m(f("damage_taken", rs)), "life": m(f("max_life", rs)), "ehp": m(f("ehp_est", rs)),
            "boss_hp": m(f("boss_hp_pct", [r for r in rs if r["outcome"] != "boss_killed"])),
            "warden_runs": len(wn), "keystones": ",".join(ks), "spec": rs[0].get("spec", ""),
            "causes": sorted({r["cause_of_death"] for r in rs if r["cause_of_death"]})[:3],
            "top": rs[0].get("top_damage", "")[:80]}


def main():
    res = {}
    for p in sorted(glob.glob(os.path.join(D, "*.csv"))):
        b = os.path.basename(p)[:-4]
        if b.endswith("_perf"):
            continue
        parts = b.split("_")
        if len(parts) < 3:
            continue
        c = cell(p)
        if c:
            res[b] = c
    L = ["| Stage | Class | Gear | Boss kills | Deaths | Clear s | To boss s | Boss fight s (median) | Damage taken | Life | Keystone |",
         "|---|---|---|---|---|---|---|---|---|---|---|"]
    for s in STAGES:
        for c in CLASSES:
            for g in GEARS:
                r = res.get(f"{g}_{c}_{s}")
                if not r:
                    continue
                L.append(f"| {s} | {c} | {g} | {r['wins']}/{r['runs']} | {r['deaths']} | {r['clear']:.0f} | {r['to_boss']:.0f} | "
                         f"{r['fight']:.0f} ({r['fight_med']:.0f}) | {r['taken']:.0f} | {r['life']:.0f} | {r['keystones'] or '-'} |")
    L += ["", "Ratios (mean boss-fight time, wins only): class / warrior, same gear", "",
          "| Stage | Gear | ranger / warrior | mage / warrior | mage clear / warrior clear |", "|---|---|---|---|---|"]
    for s in STAGES:
        for g in GEARS:
            w, r, mg = (res.get(f"{g}_{c}_{s}") for c in CLASSES)
            if w and r and mg:
                L.append(f"| {s} | {g} | {r['fight'] / w['fight']:.2f} | {mg['fight'] / w['fight']:.2f} | {mg['clear'] / w['clear']:.2f} |")
    L += ["", "Side cells", "", "| Cell | Boss kills | Deaths | Clear s | Boss fight s | Damage taken | Keystone |", "|---|---|---|---|---|---|---|"]
    for b, r in res.items():
        if len(b.split("_")) > 3:
            L.append(f"| {b} | {r['wins']}/{r['runs']} | {r['deaths']} | {r['clear']:.0f} | {r['fight']:.0f} | {r['taken']:.0f} | {r['keystones'] or '-'} |")
    open(os.path.join(D, "phaseC_summary.md"), "w").write("\n".join(L) + "\n")
    json.dump(res, open(os.path.join(D, "phaseC_summary.json"), "w"), indent=1)
    print("\n".join(L))


if __name__ == "__main__":
    main()
