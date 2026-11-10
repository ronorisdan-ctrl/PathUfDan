#!/usr/bin/env python3
"""Compare a smartbot CSV with the frozen baseline (stdlib only).

    python tests/smartbot/compare_baseline.py tests/smartbot/baseline/tree_v1.csv new.csv

Rows are matched by run_id. Every deterministic column is compared exactly (wall time lives
in *_perf.csv and is ignored). Exit 0 = identical, 1 = differences (listed), 2 = run ids
missing on either side. Passive-tree plan rule: the baseline stays green for every change
that is not a tree change; it is re-baselined exactly once at the end of Phase 2 and once at
the end of Phase 3 (record the commit and reason in tests/smartbot/baseline/BASELINES.md).
"""
import csv, sys

IGNORE = {"notes"}

def load(path):
    return {r["run_id"]: r for r in csv.DictReader(open(path, newline="", encoding="utf-8"))}

def main(argv):
    if len(argv) != 2:
        print(__doc__); return 2
    a, b = load(argv[0]), load(argv[1])
    missing = sorted(set(a) ^ set(b))
    diffs = []
    for rid in sorted(set(a) & set(b)):
        for col in a[rid]:
            if col in IGNORE:
                continue
            if a[rid].get(col) != b[rid].get(col):
                diffs.append((rid, col, a[rid].get(col), b[rid].get(col)))
    runs = len(set(a) & set(b))
    changed = len({d[0] for d in diffs})
    print(f"compared {runs} runs: {runs - changed} identical, {changed} differ, {len(missing)} only on one side")
    for rid in missing[:20]:
        print("  only in", "baseline" if rid in a else "new", rid)
    for rid, col, x, y in diffs[:60]:
        print(f"  {rid}  {col}: {x!r} -> {y!r}")
    return 2 if missing else (1 if diffs else 0)

if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
