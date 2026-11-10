"""Phase B: compare entry kits of the gear profiles (docs/BOT_GEAR_PROFILES.md).

    python tests/smartbot/gear_compare.py OUT_ROOT [legacy typical geared] > table.md

OUT_ROOT holds one folder per profile (k_legacy, k_typical, k_geared), each with the
`<class>_<stage>_kits.json` dumps written by smartbot.tscn --kit_only=1.
"""
import json, os, sys, statistics as st

root = sys.argv[1]
profiles = sys.argv[2:] or ["legacy", "typical", "geared"]
stages = ["T3", "T6", "R1", "R2", "R3"]
classes = ["warrior", "ranger", "mage"]


def load(p, c, s):
    f = os.path.join(root, "k_" + p, f"{c}_{s}_kits.json")
    if not os.path.exists(f):
        return None
    return [k["kit_summary"] for k in json.load(open(f))]


def m(xs):
    return st.mean(xs) if xs else 0


print("| Stage | Class | Profile | Life | Lowest res F/C/L | DPS raw | DPS vs stage | EHP | Rare+ slots | Points | Keystone | Runs (total / window) | Drops | Crafts (add/reroll/rarity/swap, sealed) |")
print("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
for s in stages:
    for c in classes:
        base = None
        for p in profiles:
            ks = load(p, c, s)
            if not ks:
                continue
            life = m([k["life"] for k in ks])
            dr = m([k["dps_raw"] for k in ks])
            ds = m([k["dps_stage"] for k in ks])
            eh = m([k["ehp_raw"] for k in ks])
            lowres = m([min(k["res"][:3]) for k in ks])
            rare = m([sum(v for r, v in k["rarities"].items() if r in ("rare", "epic", "legendary")) for k in ks])
            pts = m([k["points"] for k in ks])
            kst = ",".join(sorted({x for k in ks for x in k["keystones"]})) or "-"
            g = [k.get("gear_model") for k in ks if k.get("gear_model")]
            runs = f'{m([x["runs_total"] for x in g]):.0f} / {m([x["runs_window"] for x in g]):.1f}' if g else "-"
            drops = f'{m([x["drops"] for x in g]):.0f}' if g else "-"
            cr = "-"
            if g:
                cr = "%.1f/%.1f/%.1f/%.1f, %.1f" % tuple(m([x["craft"][o] for x in g]) for o in ["add", "reroll", "rarity", "swap", "sealed"])
            if base is None:
                base = (dr, ds, eh)
                rel = ""
            else:
                rel = " (x%.2f / x%.2f / x%.2f)" % (dr / max(1, base[0]), ds / max(1, base[1]), eh / max(1, base[2]))
            print(f"| {s} | {c} | {p}{rel} | {life:.0f} | {lowres:.0f} | {dr:.0f} | {ds:.0f} | {eh:.0f} | {rare:.1f} | {pts:.0f} | {kst} | {runs} | {drops} | {cr} |")
