# Smartbot baselines (passive tree plan)

Rule: keep the current baseline green for every change that is not a passive tree change.
Re-baseline exactly once at the end of Phase 2 and once at the end of Phase 3 (Phase 3 was split, so 3a and 3b each
re-baselined once); add a row here with the commit and the reason.

Check: `powershell -File tests\smartbot\run_baseline.ps1 -Out res://tests/smartbot/out/check.csv`
(about 12 minutes on Dan's PC), then
`python tests\smartbot\compare_baseline.py tests\smartbot\baseline\d2_v1.csv tests\smartbot\out\check.csv`
(exit 0 = identical).

| File | Date | Commit | Tree version | Set | Reason |
|---|---|---|---|---|---|
| `tree_v1.csv` | 2026-11-04 | uncommitted (on top of 18c3f71) | 1 | warrior/ranger/mage x T3, T6 x 10 runs, Competent, balanced, seed 1000, Godot 4.0 Windows | Frozen before passive tree Phase 2. Phase 1 code was shown gameplay-neutral: a T3 mini set (seed 900, 12 runs) was byte-identical before and after Phase 1. |
| `tree_v2.csv` | 2026-11-04 | uncommitted (on top of 18c3f71) | 2 | same set as tree_v1 | Re-baseline at the end of passive tree Phase 2 (24 behaviour nodes, tree 203 -> 227, Mind over Matter drawback). |
| `tree_v3.csv` | 2026-11-04 | uncommitted (on top of 18c3f71) | 3 | same set as tree_v1 | Re-baseline at the end of passive tree Phase 3a (bridges, 15 conversions, 14 cuts, Abyss points; tree 227 -> 232). |
| `tree_v4.csv` | 2026-11-04 | uncommitted (on top of 18c3f71) | 4 | same set as tree_v1 | Re-baseline at the end of passive tree Phase 3b (six archetype spurs, tree 232 -> 316). Phase 3 was split by Dan, so 3b gets its own re-baseline. |
| `tree_v4_bot2e.csv` | 2026-11-06 | uncommitted (on top of 18c3f71) | 4 | same set as tree_v1 | **Bot change, not a game change** (Endgame 2E): the mage now uses Blink as a dodge. Game data/code for these runs unchanged. |
| `caster_v1.csv` | 2026-11-06 | uncommitted (on top of 18c3f71) | 4 | same set as tree_v1 | **Game change** (caster itemisation, `docs/CASTER_ITEMISATION.md`): flat added spell damage, caster base implicits, +spell levels past the cap, glove spell damage / cast speed, spell penetration. The larger affix pool changes item rolls for every class. Approved by Dan. |
| `d2_v1.csv` | 2026-11-10 | Phase D2 commit | 6 | same set as tree_v1 | **Game change** (Phase D2, `docs/PHASE_D2_MEASUREMENTS.md`): Archon Velis fire resist 40 -> 30 (she is also the T3 boss), passive load fix, Perfect Aim 25% within 70. Approved by Dan 2026-11-10. |

tree_v1 summary: T3 100% wins for all classes; T6 warrior 100%, ranger 100%, mage 70%
(3 deaths to the Stormheart Colossus).

tree_v2 summary (v1 -> v2, means over 10 runs): T3 unchanged in wins (100% all); mage T3 byte-identical.
T6 warrior 10/10 (clear 156.8 -> 124.4 s, damage taken 4492 -> 2918), ranger 10 -> 9/10 (one death to the
Stormheart Colossus at 59% boss hp; clear 128.0 -> 119.2 s), mage 7 -> 8/10 (clear 226.5 -> 211.8 s).
The smartbot's balanced build takes no keystones (column empty in v1 and v2), so it exercises the new
notables only; keystone balance waits for Phase 6 benchmark builds.
tree_v3 summary (v2 -> v3, means over 10 runs): T3 still 100% for all classes. T6 warrior 10/10 (clear 124.4 -> 121.7 s,
damage taken 2918 -> 3438), ranger 9 -> 10/10 (clear 119.2 -> 100.9 s), mage 8/10 (clear 211.8 -> 189.4 s; same two
deaths: hazard lightning, Stormheart Colossus storm). Bots still take no keystones.
tree_v4 summary (v3 -> v4, means over 10 runs): T3 still 100% for all classes (mage damage taken 380 -> 147). T6 warrior
10/10 (clear 122 -> 113 s), ranger 10/10 (clear 101 -> 89 s), mage 8 -> 6/10 (clear 178 -> 164 s; all four deaths to the
Stormheart Colossus). The mage drop is seed noise: its build stats barely moved (life 751 -> 743, dps 1503 -> 1546), and a
20-run mage T6 check on seed 2000 gave 14/20 on both trees (v3 data files swapped in; the new code is flag-gated).
Files: `out/mage6_s2000_v3.csv`, `out/mage6_s2000_v4.csv`. Bots still take no keystones.
From now on compare against `tree_v4.csv`.
tree_v4_bot2e summary (v4 -> bot2e): 55/60 rows identical. The 5 changed rows are mage T6 runs where Blink fired 1-2 times
(c1, c3, c4, c7, c8); mage T6 wins 6/10 -> 6/10 (c3 now dies to the Stormheart spiral, c4 now wins). Warrior, ranger and all
T3 rows byte-identical. From now on compare against `tree_v4_bot2e.csv`.
caster_v1 summary (bot2e -> caster_v1, means over 10 runs): mage T6 6/10 -> 8/10 wins (clear 179 -> 114 s, damage taken 2224 -> 942,
dps_est 1353 -> 3358); mage T3 10/10 (clear 115 -> 104 s). Warrior and ranger 10/10 at T3 and T6 both, clear times within
+-6 s, dps_est within noise; their rows differ only because the new affixes change item rolls (10 of 60 rows identical).
Full suite on the PC 47965/0. From now on compare against `caster_v1.csv`.
d2_v1 summary (caster_v1 -> d2_v1): 52/60 rows identical. The 8 changed rows are T3 mage and ranger runs against Archon Velis (fire resist 40 -> 30); wins identical in all six class/tier cells, T3 mean clear mage 104.4 -> 103.8 s, ranger 132.7 -> 133.6 s; T6 and every warrior row byte-identical. Re-run after the Perfect Aim change: 60/60 identical (baseline bots take no keystones). From now on compare against `d2_v1.csv`.
