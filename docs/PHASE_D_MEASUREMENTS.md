# Smartbot Phase D1: Rot, Wager and Wardens re-measured with typical bots

2026-11-07 · Claude (Cowork) for Dan · follows `docs/PHASE_C_MEASUREMENTS.md`

**Measure only.** Dan's choices: measure first and stop at a gate; scope = Rot 3-5 (+ Pigments), the Wager bets and odds, Wardens at Rot 3+, ranger keystones and Velis vs Embers; keep the old targets (about 50% Competent wins at Rot 4 + 2 Pigments, about 60% per bet) but hit them with **typical** bots, with geared as the upper-bound check.

All runs on Dan's PC (Godot 4.0 win64 console, headless, `--fixed-fps 60`): 126 batches, 990 runs, **0 script errors**. Only `tests/smartbot/` (2 new scripts) and `docs/` changed. No game file changed. Nothing is committed.

## 1. Summary

- **Rot no longer threatens a typical bot.** Rot 4 + 2 Pigments: typical **60/60 wins** over two seeds (target ~50%), geared 60/60. Rot 5 + 2 Pigments: typical 29/30. The only typical deaths in all Rot cells were 2 mages, both to the Heart's mortar. Legacy bots win 67-83% in the same cell today (47% in Phase 1E; caster itemisation and Blink have lifted them since).
- **The ranger barely gets hit.** A typical ranger takes about 800 damage in a whole Rot 4 + 2 Pigments run with 1,337 life and drinks 0.1 flasks. No sensible damage multiplier alone makes Rot dangerous for it; the warrior (6,600 taken, 5 flasks) and the mage are the classes a damage dial reaches.
- **6 of 9 bets are too easy, 1 is too hard.** Abstinence 100%, Iron Will 90%, Economy of Means 90%, Archaeology 81%, Colourist 80%, Against the Clock 77%, Frenzy 73%. Unscathed is on target (67%). **Flaking fell to 43%** and now loses gold: faster bots kill the boss before peeling 7 layers.
- **Wardens under Rot are still easy**, except the Gravemaw for the mage: W2 at Rot 5 typical mage **6/10** (4 deaths: spit, quake, burrow). Every other Warden cell is 29-30/30. **Rot never reaches ring 1** (`rot.min_ring = 2`), so the W1 "Rot" cells are Rot 0 and identical by design.
- **Velis vs Embers is worse under Rot.** At Rot 4 the Embers mage needs 32.9 s for Velis, against 22.8 s with no keystone (lightning), 24.4 s Glacial Heart, 14.5 s warrior, 4.3 s ranger.
- **Ranger keystones really are weak, not just badly measured.** On the long Velis fight at Rot 4 every keystone build is slower than no keystone: none 4.3 s, Glass Cannon 5.2, Perfect Aim 6.5, Perfect Aim at range 6.4, Wind Dancer 9.2. My earlier guess that clear time hid their value is only half right (section 5).
- **Bigger balance finding: the ranger kills Wardens 3-4x faster than the warrior** (W3 4-5 s vs 13-19 s; W2 7-10 s vs 23-29 s) and the mage is 1.3-2.3x slower than the warrior. Buffing the ranger keystones would widen that.

## 2. Method

- `tests/smartbot/phaseD_runner.py` (groups `rot`, `warden`, `side`, `wager`), `tests/smartbot/phaseD_summary.py` -> `out/phaseD/phaseD_summary.md / .json`.
- Competent, `--build=balanced`, tier-6 kit, atlas seed 1. Plans as Phase C: warrior `w_earthbreaker`, mage `m_embers`, ranger `none`; legacy = `--plan=none`.
- **Rot:** ring 3 hex 3,0 (Iron Penitent, Heart of Rot from Rot 3), L50, `--mechanic=none`. Rot 3, Rot 4, Rot 4 + Pigments `glazed,unfinished` (seeds 900 and 1900), Rot 5 + Pigments. 10 runs per class per cell.
- **Wardens:** ring 1/2/3 Warden summoned at Rot 3/4/5, 10 runs per class; geared at Rot 5.
- **Side:** Velis at Rot 4, typical, forced builds: ranger `r_glass`, `r_perfect_aim`, `r_far_aim`, `r_wind`; mage `none`, `m_glacial`.
- **Wager:** each of the 9 bets forced (`--wager=<id>`, stake 1x, Rot 0), rings 2 (L45) and 3 (L50), 5 runs per class per ring = 30 per bet; mechanics as `run_atlas_p2e.ps1`. Win rates with 30 runs carry about ±9 points of noise.

## 3. Rot

| Cell | Gear | All | Warrior | Ranger | Mage | Fight s w/r/m | Damage taken w/r/m |
|---|---|---|---|---|---|---|---|
| Rot 3 | typical | 30/30 | 10/10 | 10/10 | 10/10 | 5.0 / 2.0 / 9.4 | 5,300 / 918 / 1,795 |
| Rot 4 | typical | 29/30 | 10/10 | 10/10 | 9/10 | 5.8 / 2.4 / 7.5 | 6,253 / 875 / 1,726 |
| Rot 4 + 2P (s900) | legacy | 25/30 | 6/10 | 10/10 | 9/10 | 9.3 / 10.0 / 10.8 | 14,859 / 2,344 / 2,754 |
| Rot 4 + 2P (s900) | typical | 30/30 | 10/10 | 10/10 | 10/10 | 5.3 / 1.7 / 9.4 | 6,280 / 759 / 1,717 |
| Rot 4 + 2P (s900) | geared | 30/30 | 10/10 | 10/10 | 10/10 | 4.1 / 1.2 / 8.1 | 4,892 / 633 / 1,508 |
| Rot 4 + 2P (s1900) | legacy | 20/30 | 4/10 | 9/10 | 7/10 | 7.6 / 7.5 / 9.1 | 17,212 / 2,049 / 3,223 |
| Rot 4 + 2P (s1900) | typical | 30/30 | 10/10 | 10/10 | 10/10 | 4.7 / 2.1 / 9.7 | 6,907 / 844 / 1,468 |
| Rot 4 + 2P (s1900) | geared | 30/30 | 10/10 | 10/10 | 10/10 | 3.4 / 0.9 / 6.0 | 6,782 / 1,105 / 1,130 |
| Rot 5 + 2P | typical | 29/30 | 10/10 | 10/10 | 9/10 | 7.8 / 2.5 / 11.5 | 7,664 / 944 / 2,703 |
| Rot 5 + 2P | geared | 30/30 | 10/10 | 10/10 | 10/10 | 3.9 / 0.8 / 7.7 | 5,922 / 822 / 2,042 |

Rot 4 + 2 Pigments, both seeds (means per run):

| Gear | Class | Life | Damage taken | Flasks | Hits taken | Clear s |
|---|---|---|---|---|---|---|
| legacy | warrior / ranger / mage | 1,614 / 991 / 1,010 | 16,035 / 2,197 / 2,989 | 22.1 / 2.8 / 4.3 | 275 / 31 / 38 | 189 / 210 / 305 |
| typical | warrior / ranger / mage | 1,993 / 1,337 / 1,376 | 6,594 / 801 / 1,576 | 5.0 / 0.1 / 0.5 | 149 / 16 / 22 | 160 / 147 / 216 |

Typical gear cuts damage taken by 60-70% and life rises 25-40%, so the same Rot hits 3-4x less hard relative to life. To bring typical back to ~50% the Rot 4 danger has to rise several-fold, which would flatten legacy-level (under-geared) players. That is why the target itself is a decision (section 7, D1).

## 4. Wardens under Rot

Rot 0 typical numbers from Phase C for comparison: fight s W1 15/16/19, W2 28/10/21, W3 15/6/23 (warrior/ranger/mage).

| Warden | Rot | Gear | All | Mage | Fight s w/r/m | Damage taken w/r/m |
|---|---|---|---|---|---|---|
| W1 Sir Morcant | 3-5 (= Rot 0, ring 1 has no Rot) | typical | 30/30 | 10/10 | 14.7 / 16.4 / 18.7 | 1,504 / 627 / 636 |
| W1 | 5 (= 0) | geared | 30/30 | 10/10 | 10.1 / 4.5 / 10.3 | 1,205 / 169 / 312 |
| W2 The Gravemaw | 3 | typical | 30/30 | 10/10 | 25.5 / 10.3 / 32.5 | 4,263 / 828 / 2,009 |
| W2 | 4 | typical | 29/30 | 9/10 | 22.6 / 7.2 / 32.2 | 4,955 / 626 / 2,209 |
| W2 | 5 | typical | 26/30 | **6/10** | 29.4 / 8.8 / 29.7 | 6,555 / 944 / 2,683 |
| W2 | 5 | geared | 30/30 | 10/10 | 13.7 / 5.1 / 26.0 | 3,074 / 589 / 2,332 |
| W3 Archon Velis | 3 | typical | 30/30 | 10/10 | 12.6 / 4.0 / 26.2 | 3,949 / 592 / 1,466 |
| W3 | 4 | typical | 30/30 | 10/10 | 14.5 / 4.3 / 32.9 | 4,454 / 414 / 2,080 |
| W3 | 5 | typical | 30/30 | 10/10 | 19.0 / 5.2 / 31.1 | 5,737 / 614 / 2,359 |
| W3 | 5 | geared | 30/30 | 10/10 | 10.6 / 2.9 / 22.1 | 3,710 / 791 / 2,006 |

- Rot 3+ Wardens drop Master Pigments in the Phase 3 design, but no win-rate target was ever set for them.
- The Gravemaw at Rot 5 is the only Warden that kills a typical bot, and only the mage: its fight is 30 s and it takes ~2,700 damage with ~1,370 life.

## 5. Ranger keystones and Velis vs Embers

### Velis at Rot 4 (typical, 10 runs each, all 10/10)

| Build | Fight s | Damage taken |
|---|---|---|
| ranger, no keystone | 4.3 | 414 |
| ranger, Glass Cannon | 5.2 | 516 |
| ranger, Perfect Aim at range | 6.4 | 582 |
| ranger, Perfect Aim | 6.5 | 657 |
| ranger, Wind Dancer | 9.2 | 682 |
| mage, Embers | 32.9 | 2,080 |
| mage, no keystone (lightning lead) | 22.8 | 1,285 |
| mage, Glacial Heart | 24.4 | 1,713 |
| warrior, Earthbreaker | 14.5 | 4,454 |

**Ranger keystones.**
- Cost is not the problem: Perfect Aim and Automaton are 8 points from the ranger start, the same as Embers is for the mage; Glass Cannon is 6 (from any start).
- Phase C judged them by clear time, and plain-zone ranger boss fights last 1-3 s, so clear time is ~97% walking. Measured by boss-fight time on the plain R3 boss, Glass Cannon is faster (1.8 s vs 3.1 s). But on Velis, a fight long enough to show DPS, **every keystone is slower than none**, by 20% (Glass) to 115% (Wind Dancer).
- Likely causes, in the keystones' own text: Perfect Aim's 30% less damage inside 100 units (Velis teleports on a 3.5 s cooldown, so she is often close); Wind Dancer's 10% less without the buff; Glass Cannon's 40% less life making the bot play more defensively (damage taken still rises). The keystone path also skips the ~8 points of plain projectile damage the no-keystone tree takes.
- Static DPS can't settle bot play vs keystone maths. A Training Grounds dummy pass per build would (not built yet).
- **The ranger is already the fastest boss killer by 3-4x.** Retune the keystones as sidegrades (remove the drawbacks that trigger in normal play), not as raw power.

**Velis vs Embers.**
- Velis has 40 fire / 30 lightning / 30 void base resistance, plus ring 3's +30: **70 fire, 60 lightning, 30 cold**.
- Embers deals 0.30 of its damage, lightning 0.40, cold 0.70. At Rot 4 Embers is 1.44x slower than a lightning mage and 2.3x the warrior.
- If Velis's base fire is lowered 40 -> 25 (55% in ring 3), Embers deals 0.45: estimated fight about 22 s at Rot 4, level with the lightning mage, still 1.5x the warrior.
- The pinnacle design already lets the player skip one Warden ("any 4 of 6"), so leaving it as a respec / skip moment is a valid choice.

## 6. Collector's Wager (typical, rings 2 + 3, Rot 0, stake 1x)

| Bet | Rule now | Odds | 2E win (legacy) | **D1 win (typical)** | W / R / M | Net gold per stake | Main loss reason | Proposal (to re-measure in D2) |
|---|---|---|---|---|---|---|---|---|
| Unscathed | next elite, max 5 hits | 0.95 | 59% | **67%** | 40 / 80 / 80 | +0.28 | boss fell first x6, 6 hits x4 | keep |
| Against the Clock | 12 s + 8 s/chamber | 0.7 | 67% | **77%** | 70 / 90 / 70 | +0.33 | out of time x7 | per chamber 8 -> 6.5 s |
| Economy of Means | 1 skill | 0.25 | 93% | **90%** | 100 / 100 / 70 | +0.12 | 3 mage deaths | keep (no number) |
| Frenzy | 25 kills / 38 s | 1.0 | 57% | **73%** | 70 / 80 / 70 | +0.44 | boss fell first x6 | 25 -> 30 kills |
| Abstinence | no flask | 0.3 | 87% | **100%** | 100 / 100 / 100 | +0.30 | - | odds 0.3 -> 0.15 (no number to tune) |
| Iron Will | never below 70% | 0.9 | 60% | **90%** | 80 / 90 / 100 | +0.67 | life below 70% x3 | 70% -> 85% |
| Flaking | 7 layers | 0.6 | 72% | **43%** | 30 / 40 / 60 | -0.31 | boss fell first x17 | 7 -> 5 layers |
| Colourist | 10 sketches / 75 s | 0.65 | 70% | **80%** | 80 / 80 / 80 | +0.29 | boss fell first x6 | 10 -> 12 sketches |
| Archaeology | 1 vault / 40 s | 0.9 | 61% | **81% (16 bets)** | 75 / 83 / 83 | +0.52 | out of time x3 | 40 -> 30 s |

- Target for every bet: ~60% wins at odds that give about +15% expected gold. At 60% that is odds 0.92; the bets with no number to tune (Economy of Means, Abstinence) take lower odds instead.
- Economy of Means: all 3 losses were mage deaths at Rot 0 (Iron Penitent mortar and cannon, Malgrath's rift) while held to one skill.
- **Archaeology measurement fault:** 14 of 30 runs had no bet, because the vault was already open when the bot reached the Collector, so the bet was refused (`--vaults=0` does not stop it here). The 16 real bets are reported. Fix the bot before D2.
- Bets that count something before the boss dies (Flaking, Colourist, Frenzy, Unscathed) get harder as bots get faster; timed and condition bets get easier. Gear pushes them apart.

## 7. Decisions for Dan (gate before D2)

| # | Decision | Options | Recommendation |
|---|---|---|---|
| D1 | Rot target with typical bots | (a) ~50% at Rot 4 + 2P for typical, as asked: Rot 4-5 needs several times today's danger, and legacy-level players would mostly die; (b) a dial: typical ~85% Rot 3, ~65% Rot 4 + 2P, ~45% Rot 5 + 2P; (c) put the extra danger in the opt-in layers (Pigments / Varnish / Rot 5 only) | **(b)**, tuned by a D2 sweep of Rot 4-5 `damage_mult`, `heal` and `attack_speed`, plus one ranger-reaching lever (e.g. more projectile packs or faster monster projectiles at Rot 4+), because damage alone does not reach the ranger |
| D2 | Wardens at Rot 3+ (Master Pigments) | set a target (e.g. ~70% typical at Rot 5) or leave them as they are | Decide with D1; today only the mage vs Gravemaw at Rot 5 is below 90% |
| D3 | Wager numbers | apply the section 6 proposals and re-measure | Yes, plus odds back to ~0.9 where a bet lands at 60%. Fix the Archaeology bot first |
| D4 | Velis vs Embers | (a) leave it (skip / respec moment, "any 4 of 6"); (b) Velis base fire 40 -> 25 | (b) is cheap and keeps Embers viable; (a) is fine if Wardens are meant to counter builds |
| D5 | Ranger keystones | (a) leave; (b) sidegrade retune (e.g. Perfect Aim drop the close-range penalty to 15% or 60 units; Wind Dancer drop the 10% less); (c) first build a Training Grounds dummy pass to separate keystone maths from bot play | (c) then (b). Don't add raw ranger power |
| D6 | Class balance on Wardens | ranger 3-4x faster than warrior, mage 1.3-2.3x slower | Flag only; worth its own pass after Rot is retuned |

## 8. Files and commands

New: `tests/smartbot/phaseD_runner.py`, `tests/smartbot/phaseD_summary.py`, `docs/PHASE_D_MEASUREMENTS.md`, `tests/smartbot/out/phaseD/` (CSVs, logs, `phaseD_summary.md/.json`; the `*_smoke*` files are the 2-run smoke test). No other file changed.

```
python tests/smartbot/phaseD_runner.py --godot "W:\AI game\Godot_v4.0-stable_win64_console.exe" --groups rot,warden,side
python tests/smartbot/phaseD_runner.py --godot "W:\AI game\Godot_v4.0-stable_win64_console.exe" --groups wager
python tests/smartbot/phaseD_summary.py
```

Verification: 129 batch logs (126 + 3 smoke), 0 `SCRIPT ERROR`; every cell has its full run count (10, or 5 for Wager cells); Warden rows carry `warden:N`, Rot rows `rot:N` (W1 rows correctly have none).
