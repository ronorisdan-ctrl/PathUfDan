#!/usr/bin/env python3
"""Phase D2 summary: python tests/smartbot/phaseD2_summary.py [--outdir phaseD2] [--md file]
Files: <gear>_<class>_<cell>[_<tag>].csv. Prints Rot / Warden win rates by cell+tag, the Wager
table (win %, net gold per stake, the odds that give +15% expected gold) and the dummy DPS table."""
import argparse, csv, glob, json, os, re, statistics as st, collections

HERE = os.path.dirname(os.path.abspath(__file__))
CLS = ["warrior", "ranger", "mage"]
NAME = re.compile(r"^(legacy|typical|geared)_(warrior|ranger|mage)_(.+)\.csv$")
WRE = re.compile(r"wager:([\w-]+)\|x(\d)\|(\w*)\|why=([^|]*)\|.*?gold=(-?\d+)")
DRE = re.compile(r"dummy:dist=(\d+)\|secs=(\d+)\|dps=([\d.]+)\|hits=(\d+)\|crit=([\d.]+)\|avg_hit=([\d.]+)\|rolls=(\d+)")
CELLS = ["rot3", "rot4", "rot4p", "rot4p_s1900", "rot5p", "W1_rot5", "W2_rot5", "W3_rot5"]


def split(rest):
    for c in sorted(CELLS, key=len, reverse=True):
        if rest == c:
            return c, ""
        if rest.startswith(c + "_"):
            return c, rest[len(c) + 1:]
    if rest.startswith("wager_"):
        m = re.match(r"(wager_\w+?_r\d)(?:_(.*))?$", rest)
        return m.group(1), m.group(2) or ""
    if rest.startswith("dummy_"):
        m = re.match(r"(dummy_.+?_\d+)(?:_(.*))?$", rest)
        return m.group(1), m.group(2) or ""
    return rest, ""


def load(outdir):
    D = collections.defaultdict(list)
    for fn in glob.glob(os.path.join(HERE, "out", outdir, "*.csv")):
        b = os.path.basename(fn)
        if b.endswith("_perf.csv") or "smoke" in b:
            continue
        m = NAME.match(b)
        if not m:
            continue
        g, c, rest = m.groups()
        cell, tag = split(rest)
        D[(cell, tag, g, c)] += list(csv.DictReader(open(fn, encoding="utf-8")))
    return D


def rot_table(D, L):
    keys = sorted({(k[0], k[1], k[2]) for k in D if not k[0].startswith(("wager_", "dummy_"))})
    L.append("| Cell | Tag | Gear | All | Warrior | Ranger | Mage | Fight s w/r/m | Taken w/r/m | Life w/r/m | no-tree rows |")
    L.append("|---|---|---|---|---|---|---|---|---|---|---|")
    J = {}
    for cell, tag, g in keys:
        S = {c: D[(cell, tag, g, c)] for c in CLS if (cell, tag, g, c) in D}
        n = sum(len(v) for v in S.values())
        w = sum(1 for v in S.values() for r in v if r["outcome"] == "boss_killed")
        def per(c, f):
            rs = S.get(c, [])
            return f(rs) if rs else "-"
        wins = {c: per(c, lambda rs: f"{sum(r['outcome'] == 'boss_killed' for r in rs)}/{len(rs)}") for c in CLS}
        fight = "/".join(per(c, lambda rs: "%.1f" % st.mean([float(r["clear_time"]) - float(r["time_to_boss"]) for r in rs if r["outcome"] == "boss_killed"] or [float("nan")])) for c in CLS)
        taken = "/".join(per(c, lambda rs: "%.0f" % st.mean(float(r["damage_taken"]) for r in rs)) for c in CLS)
        life = "/".join(per(c, lambda rs: "%.0f" % st.mean(float(r["max_life"]) for r in rs)) for c in CLS)
        nt = sum(1 for v in S.values() for r in v if r.get("passives") == "0")
        L.append(f"| {cell} | {tag} | {g} | {w}/{n} ({100.0 * w / max(1, n):.0f}%) | {wins['warrior']} | {wins['ranger']} | {wins['mage']} | {fight} | {taken} | {life} | {nt} |")
        J[f"{cell}|{tag}|{g}"] = {"wins": w, "n": n, "per": wins}
    return J


def wager_table(D, L):
    B = collections.defaultdict(lambda: {"n": 0, "w": 0, "gold": 0, "stake": 0, "cls": collections.Counter(), "clsn": collections.Counter(), "why": collections.Counter(), "nobet": 0})
    for (cell, tag, g, c), rs in D.items():
        if not cell.startswith("wager_"):
            continue
        bet = cell[6:].rsplit("_r", 1)[0]
        b = B[(bet, tag)]
        for r in rs:
            m = WRE.search(r["notes"])
            if not m or m.group(1) == "-":
                b["nobet"] += 1
                continue
            st_ = m.group(3)
            if st_ not in ("won", "lost"):
                b["nobet"] += 1
                continue
            b["n"] += 1
            b["clsn"][c] += 1
            if st_ == "won":
                b["w"] += 1
                b["cls"][c] += 1
            else:
                b["why"][m.group(4)] += 1
    L.append("| Bet | Tag | Bets | Win % | W / R / M % | no bet | Odds for +15% EV | Main loss reasons |")
    L.append("|---|---|---|---|---|---|---|---|")
    J = {}
    for (bet, tag), b in sorted(B.items()):
        p = b["w"] / max(1, b["n"])
        odds = (1.15 - p) / p if p > 0 else float("nan")
        wrm = " / ".join(f"{100.0 * b['cls'][c] / max(1, b['clsn'][c]):.0f}" for c in CLS)
        L.append(f"| {bet} | {tag} | {b['n']} | {100 * p:.0f}% | {wrm} | {b['nobet']} | {odds:.2f} | " + ", ".join(f"{k} x{v}" for k, v in b["why"].most_common(3)) + " |")
        J[f"{bet}|{tag}"] = {"n": b["n"], "p": p, "odds_15": odds}
    return J


def dummy_table(D, L):
    R = {}
    for (cell, tag, g, c), rs in D.items():
        if not cell.startswith("dummy_"):
            continue
        build, dist = cell[6:].rsplit("_", 1)
        vals = {}
        for r in rs:
            m = DRE.search(r["notes"])
            if m:
                vals[r["chain"]] = (float(m.group(3)), float(m.group(5)), int(m.group(7)), float(r["max_life"]), r["keystones"])
        R[(build, int(dist))] = vals
    builds = sorted({k[0] for k in R}, key=lambda b: (b != "none", b))
    dists = sorted({k[1] for k in R})
    L.append("| Build | Keystone | Life | " + " | ".join(f"DPS @{d} (x none)" for d in dists) + " |")
    L.append("|---|---|---|" + "---|" * len(dists))
    J = {}
    for b in builds:
        cells = []
        life = ks = "-"
        for d in dists:
            v = R.get((b, d), {})
            base = R.get(("none", d), {})
            if not v:
                cells.append("-")
                continue
            dps = st.mean(x[0] for x in v.values())
            ratios = [v[k][0] / base[k][0] for k in v if k in base and base[k][0] > 0]
            rr = st.mean(ratios) if ratios else float("nan")
            life = "%.0f" % st.mean(x[3] for x in v.values())
            ks = next(iter(v.values()))[4] or "-"
            cells.append(f"{dps:,.0f} (x{rr:.2f})")
            J[f"{b}|{d}"] = {"dps": dps, "ratio": rr, "n": len(v)}
        L.append(f"| {b} | {ks} | {life} | " + " | ".join(cells) + " |")
    return J


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default="phaseD2")
    ap.add_argument("--md", default="")
    a = ap.parse_args()
    D = load(a.outdir)
    L = ["# Phase D2 summary (phaseD2_summary.py)", "", "## Rot / Wardens", ""]
    J = {"rot": rot_table(D, L)}
    L += ["", "## Wager", ""]
    J["wager"] = wager_table(D, L)
    L += ["", "## Dummy", ""]
    J["dummy"] = dummy_table(D, L)
    txt = "\n".join(L)
    print(txt)
    if a.md:
        open(a.md, "w", encoding="utf-8").write(txt + "\n")
        json.dump(J, open(a.md[:-3] + ".json", "w"), indent=1)


if __name__ == "__main__":
    main()
