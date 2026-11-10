#!/usr/bin/env python3
"""Path of Dan - passive tree generator (rebuilt 2026-11-04, Phase 0).

The original gen_clusters.py lived only in an old cloud workspace and was lost.
This version was reverse-engineered from data/passive_tree.json and rebuilds it
byte-for-byte (see --check).

Sources (edit these, never the generated output):
  data/tree_src/hand_nodes.json     hand-authored nodes (classes, roads, heart).
                                    Links INTO generated nodes are not stored
                                    here; the generator appends them.
  data/tree_src/clusters_spec.json  the six outer clusters + Wanderer's Road.

Phase 1 schema (validated by scripts/core/tree_rules.gd): every node has "tags"
(vocabulary in data/passive_flags.json); keystones have "drawback"; optional
"exclusive_with", "rev", "art_id". Spec slots carry these keys and the
generator copies them through.

Geometry (all deterministic, no RNG):
  ring centre  = center_r  * (cos a, sin a), a = cluster angle
  keystone     = ks_r      * (cos a, sin a)
  ring slot i  = centre + ring_r * (cos(a + i*step), sin(a + i*step))
  path node j of m between anchor A and ring slot B = A + (B - A) * (j+1)/(m+1)
  Wanderer's Road arc nodes are pinned (x, y) in the spec: the old arc formula
  could not be recovered exactly.
  Phase 3: a path or arc slot may carry an explicit "id" (used after cuts, so the
  surviving nodes keep their ids; ids are never reused or renumbered).
Python round() (banker's rounding) is used, as in the original.

Usage:
  python tools/gen_clusters.py            rebuild data/passive_tree.json
  python tools/gen_clusters.py --check    exit 1 if a rebuild would differ
  python tools/gen_clusters.py --out F    write to F instead
  python tools/gen_clusters.py --extract  (one-off) split the current tree
                                          into data/tree_src/  (overwrites!)
"""
import json, math, os, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TREE = os.path.join(ROOT, "data", "passive_tree.json")
SRC = os.path.join(ROOT, "data", "tree_src")
HAND = os.path.join(SRC, "hand_nodes.json")
SPEC = os.path.join(SRC, "clusters_spec.json")


def dump(obj):
    return json.dumps(obj, indent=1, ensure_ascii=False)


# Phase 1 schema keys, copied from a spec slot when present, appended in this order.
OPTIONAL = ("tags", "drawback", "exclusive_with", "rev", "art_id")


def node(nid, name, ntype, mods, x, y, cost, links, cluster, desc=None, flags=None, src=None):
    # Key order matches the Phase 0 output, with the Phase 1 keys appended.
    n = {"id": nid, "name": name, "type": ntype, "mods": mods}
    if desc is not None:
        n["desc"] = desc
    if flags and ntype != "keystone":
        n["flags"] = flags
    n.update({"x": x, "y": y, "cost": cost, "links": links, "cluster": cluster, "gen": True})
    if flags and ntype == "keystone":
        n["flags"] = flags
    for k in OPTIONAL:
        if src is not None and k in src:
            n[k] = src[k]
    return n


def build(hand, spec):
    g = spec["geometry"]
    step = g["ring_step_deg"]
    out, extra = [], {}          # extra: node id -> links added from generated nodes

    def link_in(target, src):
        extra.setdefault(target, []).append(src)

    pos = {n["id"]: (n["x"], n["y"]) for n in hand}
    for c in spec["clusters"]:
        p, a, cname = c["prefix"], c["angle"], c["name"]
        ar = math.radians(a)
        cx, cy = g["center_r"] * math.cos(ar), g["center_r"] * math.sin(ar)
        ring = []
        for i, s in enumerate(c["ring"]):
            b = math.radians(a + step * i)
            ring.append((round(cx + g["ring_r"] * math.cos(b)), round(cy + g["ring_r"] * math.sin(b))))
        for i in range(8):
            pos[f"{p}_r{i}"] = ring[i]
        nodes = []
        for i, s in enumerate(c["ring"]):
            links = [f"{p}_r1", f"{p}_r7", f"{p}_ks"] if i == 0 else [f"{p}_r{i-1}", f"{p}_r{(i+1) % 8}"]
            nodes.append(node(f"{p}_r{i}", s["name"], s["type"], s["mods"], ring[i][0], ring[i][1],
                              s.get("cost", 1), links, cname, s.get("desc"), s.get("flags"), s))
        k = c["keystone"]
        kx, ky = round(g["ks_r"] * math.cos(ar)), round(g["ks_r"] * math.sin(ar))
        nodes.append(node(f"{p}_ks", k["name"], "keystone", k["mods"], kx, ky, k.get("cost", 1),
                          [f"{p}_r0"], cname, k.get("desc"), k.get("flags"), k))
        ring_nodes = {n["id"]: n for n in nodes}
        for path in c["paths"]:
            A = pos[path["from"]]
            to = f"{p}_r{path['to_ring']}"
            B = pos[to]
            m = len(path["nodes"])
            ids = [s.get("id", f"{p}_p{path['group']}{j+1}") for j, s in enumerate(path["nodes"])]
            for j, s in enumerate(path["nodes"]):
                x = round(A[0] + (B[0] - A[0]) * (j + 1) / (m + 1))
                y = round(A[1] + (B[1] - A[1]) * (j + 1) / (m + 1))
                links = [path["from"] if j == 0 else ids[j-1], to if j == m - 1 else ids[j+1]]
                nodes.append(node(ids[j], s["name"], s.get("type", "minor"), s["mods"], x, y,
                                  s.get("cost", 1), links, cname, s.get("desc"), s.get("flags"), s))
            link_in(path["from"], ids[0])
            ring_nodes[to]["links"].append(ids[-1])
        out += nodes

    road = spec["road"]
    for k, arc in enumerate(road["arcs"]):
        m = len(arc["nodes"])
        ids = [s.get("id", f"xo{k}_{j+1}") for j, s in enumerate(arc["nodes"])]   # Phase 3: explicit "id" keeps ids stable after cuts
        for j, s in enumerate(arc["nodes"]):
            links = [arc["from"] if j == 0 else ids[j-1], arc["to"] if j == m - 1 else ids[j+1]]
            out.append(node(ids[j], s.get("name", road["cluster"]), s.get("type", "minor"), s["mods"],
                            s["x"], s["y"], s.get("cost", 1), links, road["cluster"], s.get("desc"), s.get("flags"), s))
        link_in(arc["from"], ids[0])
        link_in(arc["to"], ids[-1])

    by_id = {n["id"]: n for n in out}
    hand_out = []
    for h in hand:
        h = json.loads(json.dumps(h))
        h["links"] = h["links"] + extra.pop(h["id"], [])
        hand_out.append(h)
    for target, srcs in extra.items():   # arcs ending on generated ring nodes
        by_id[target]["links"] += srcs
    for h in hand_out:   # Phase 3: a hand node may link into a generated node; mirror the link
        for l in h["links"]:
            if l in by_id and h["id"] not in by_id[l]["links"]:
                by_id[l]["links"].append(h["id"])
    return hand_out + out


def extract():
    t = json.load(open(TREE, encoding="utf-8"))
    N = {n["id"]: n for n in t}
    gen = {n["id"] for n in t if n.get("gen")}
    hand = []
    for n in t:
        if n.get("gen"):
            continue
        h = dict(n)
        h["links"] = [l for l in n["links"] if l not in gen]
        hand.append(h)

    def slot(n):
        s = {"name": n["name"], "type": n["type"], "mods": n["mods"]}
        for key in ("desc", "flags") + OPTIONAL:
            if key in n:
                s[key] = n[key]
        if n["cost"] != 1:
            s["cost"] = n["cost"]
        return s

    clusters = []
    for p in [n["id"][:2] for n in t if n["id"].endswith("_ks") and n.get("gen")]:
        ks = N[p + "_ks"]
        a = round(math.degrees(math.atan2(ks["y"], ks["x"])))
        paths = {}
        for n in t:
            if n["id"].startswith(p + "_p"):
                paths.setdefault(n["id"][len(p) + 2], []).append(n)
        plist = []
        for grp, ns in paths.items():
            plist.append({"group": grp,
                          "from": [l for l in ns[0]["links"] if not l.startswith(p + "_p")][0],
                          "to_ring": int([l for l in ns[-1]["links"] if not l.startswith(p + "_p")][0][-1]),
                          "nodes": [dict(slot(n), **({} if n["type"] != "minor" else {})) for n in ns]})
        for pl in plist:
            for s in pl["nodes"]:
                if s["type"] == "minor":
                    del s["type"]
        kslot = slot(ks); del kslot["type"]
        clusters.append({"prefix": p, "name": ks["cluster"], "angle": a,
                         "ring": [slot(N[f"{p}_r{i}"]) for i in range(8)],
                         "keystone": kslot, "paths": plist})
    arcs = []
    k = 0
    while f"xo{k}_1" in N:
        ns = []
        j = 1
        while f"xo{k}_{j}" in N:
            ns.append(N[f"xo{k}_{j}"]); j += 1
        arcs.append({"from": ns[0]["links"][0], "to": ns[-1]["links"][-1],
                     "nodes": [dict({"mods": n["mods"], "x": n["x"], "y": n["y"]}, **{k: n[k] for k in OPTIONAL if k in n}) for n in ns]})
        k += 1
    spec = {"_about": "Source for the generated part of data/passive_tree.json. Edit this, then run tools/gen_clusters.py. Ids are stable: never reuse or renumber them.",
            "geometry": {"center_r": 1130, "ks_r": 1380, "ring_r": 120, "ring_step_deg": -45},
            "clusters": clusters,
            "road": {"cluster": "Wanderer's Road", "arcs": arcs}}
    os.makedirs(SRC, exist_ok=True)
    open(HAND, "w", encoding="utf-8").write(dump(hand))
    open(SPEC, "w", encoding="utf-8").write(dump(spec))
    print(f"extracted {len(hand)} hand nodes, {len(clusters)} clusters, {len(arcs)} arcs")


def main(argv):
    if "--extract" in argv:
        extract(); return 0
    hand = json.load(open(HAND, encoding="utf-8"))
    spec = json.load(open(SPEC, encoding="utf-8"))
    text = dump(build(hand, spec))
    if "--check" in argv:
        cur = open(TREE, encoding="utf-8").read()
        if cur == text:
            print("OK: generator reproduces data/passive_tree.json byte-for-byte"); return 0
        a, b = json.loads(cur), json.loads(text)
        ia, ib = {n["id"]: n for n in a}, {n["id"]: n for n in b}
        for nid in sorted(set(ia) | set(ib)):
            if ia.get(nid) != ib.get(nid):
                print("DIFF", nid, "\n  current:", ia.get(nid), "\n  rebuilt:", ib.get(nid))
        if [n["id"] for n in a] != [n["id"] for n in b]:
            print("DIFF node order")
        return 1
    out = argv[argv.index("--out") + 1] if "--out" in argv else TREE
    open(out, "w", encoding="utf-8").write(text)
    print(f"wrote {out} ({len(json.loads(text))} nodes)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
