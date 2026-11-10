"""Endgame 2E summary: wager win rates per bet / class, vault results.
   python tests/smartbot/p2e_summary.py [tag] [glob]"""
import csv, glob, os, re, sys, collections, statistics
WRE = re.compile(r"wager:([\w-]+)\|x(\d)\|(\w*)\|why=([^|]*)\|offers=([^|]*)\|t=(-?\d+)\|gold=(-?\d+)")
VRE = re.compile(r"vaults:([^|]*)\|t=(\d+)\|sigils=(\d+)\|shards=(\d+)")
tag = sys.argv[1] if len(sys.argv) > 1 else "v1"
pat = sys.argv[2] if len(sys.argv) > 2 else "atlas_p2e_*_%s_rot*.csv" % tag
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
W = collections.defaultdict(lambda: collections.defaultdict(list))
V = collections.defaultdict(list)
for fn in sorted(glob.glob(os.path.join(out, pat))):
    if fn.endswith("_perf.csv"):
        continue
    for r in csv.DictReader(open(fn, encoding="utf-8")):
        fields = {}
        m = WRE.search(r["notes"])
        if m:
            fields["wager"] = {"bet": m.group(1), "state": m.group(3), "why": m.group(4), "t": m.group(6), "gold": m.group(7)}
        m = VRE.search(r["notes"])
        if m:
            fields["vaults"] = {"types": m.group(1), "t": m.group(2), "sigils": m.group(3), "shards": m.group(4)}
        if "wager" in fields:
            w = fields["wager"]
            W[w["bet"]][r["class"]].append((w["state"], int(w.get("gold", 0)), w.get("why", ""), r["outcome"], float(r["clear_time"])))
        if "vaults" in fields:
            V[r["class"]].append((fields["vaults"], r["outcome"], float(r["clear_time"]), r["cause_of_death"]))
if W:
    print("bet          class    n  won  lost  died  win%   gold/bet  top loss reasons")
    for bet in sorted(W):
        allr = []
        for cl in ["warrior", "ranger", "mage"]:
            rs = W[bet].get(cl, [])
            allr += rs
            if not rs: continue
            won = sum(1 for x in rs if x[0] == "won"); died = sum(1 for x in rs if x[3] == "died")
            why = collections.Counter(x[2] for x in rs if x[0] != "won").most_common(2)
            print("%-12s %-7s %3d %4d %5d %5d %5.0f%% %9.0f  %s" % (bet, cl, len(rs), won, len(rs) - won, died, 100.0 * won / len(rs), statistics.mean(x[1] for x in rs), why))
        won = sum(1 for x in allr if x[0] == "won")
        print("%-12s %-7s %3d %4d %5d %5s %5.0f%% %9.0f" % (bet, "ALL", len(allr), won, len(allr) - won, "", 100.0 * won / max(1, len(allr)), statistics.mean(x[1] for x in allr) if allr else 0))
if V:
    print("\nvaults  class    runs  died  vaults(open/done/total)  by type done/seen   clear med")
    for cl in ["warrior", "ranger", "mage"]:
        rs = V.get(cl, [])
        if not rs: continue
        tot = opn = dn = 0; bt = collections.defaultdict(lambda: [0, 0])
        for d, o, ct, cause in rs:
            for tv in d["types"].split("+"):
                t, s = tv.split(":"); tot += 1; bt[t][1] += 1
                if s != "sealed": opn += 1
                if s == "done": dn += 1; bt[t][0] += 1
        died = sum(1 for x in rs if x[1] == "died")
        print("%-7s %-7s %4d %5d   %d/%d/%d   %s   %.0f s" % ("", cl, len(rs), died, opn, dn, tot, " ".join("%s %d/%d" % (k, v[0], v[1]) for k, v in sorted(bt.items())), statistics.median(x[2] for x in rs)))
