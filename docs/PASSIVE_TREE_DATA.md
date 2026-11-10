# Passive tree: data, tools and save rules (Phase 1, Phase 2, 3a, 3b and 4a content)

Plan: "Path of Dan: A Phased Plan to Expand and Deepen the Passive Tree" (project doc).
Phase 0 audit: `docs/passive_tree_audit_phase0.{csv,json}`.

## Files

| File | Role | Edit? |
|---|---|---|
| `data/tree_src/hand_nodes.json` | hand-made nodes (class sectors, roads, heart) | yes |
| `data/tree_src/clusters_spec.json` | six outer clusters + Wanderer's Road | yes |
| `tools/gen_clusters.py` | writes `data/passive_tree.json` from the two sources (`--check` = byte-for-byte test) | code only |
| `data/passive_tree.json` | **generated**, read by the game | never by hand |
| `data/passive_flags.json` | flag registry, tag vocabulary, statuses, point budget (`budget_l60`), `pending_rework` list | yes |
| `data/passive_migrations.json` | `tree_version` and id history | yes, when the tree changes |
| `scripts/core/tree_rules.gd` | validator + allocation rules (pure functions) | code |
| `tests/test_passive_tree.gd` | validator, generator, save migration and behavioural flag tests | code |

## Node schema

Required: `id` (stable, never reused), `name`, `type` (start / minor / greater / notable /
keystone; mastery and socket are reserved), `mods` (`flat` / `inc`; `more` only on keystones),
`x`, `y`, `cost` (0 only on starts), `links` (symmetric), `cluster`, `tags` (vocabulary in
`passive_flags.json`).

Optional: `desc`, `flags` (each must be registered), `class` (starts), `gen` (generated),
`drawback` (**required on keystones**; red tooltip comes in Phase 5), `exclusive_with`
(mutual; `can_allocate` refuses, routes avoid, illegal saves are refunded), `rev`, `art_id`
(reserved for Codex V5). Unknown keys fail validation, so additions are deliberate.

## Validator (`TreeRules.validate`)

Errors: bad/duplicate ids, missing or unknown keys, unknown type, bad cost, missing or unknown
tags, unregistered flags, `more` outside keystones, keystone without drawback (unless listed
in `pending_rework`: warning), drawback on a non-keystone, broken / one-way / duplicate /
self links, one-sided or dangling `exclusive_with`, nodes unreachable from every class start,
a keystone a class cannot reach or that costs more than `budget_l60`, and migration history
problems (removed id still present, target missing, version out of range).

Report (not errors yet): cheapest keystone cost per class, node type counts, and status
coverage (how many nodes are tagged with each of the 11 statuses). Run it with
`godot --headless --fixed-fps 60 --path . res://tests/tree_only.tscn`; WARN and INFO lines go
to `tests/tree_only_results.txt`.

## Flags and behavioural tests

Every flag in `passive_flags.json` needs `func flag_<id>(nid)` in `tests/test_passive_tree.gd`.
The test routes and allocates the real node on a level 60 character of the nearest class,
enters a dungeon, performs the trigger (hit, block, dodge, stand still, cast, apply a status)
and checks the outcome against the same character without the node. `kind: "marker"` flags
(automaton, one_mind, glass_cannon) are checked through their stat effects.

## Saves (SAVE_VERSION 4)

Saves now store `tree_version`. Version 3 saves count as tree version 1. **Policy (Dan,
2026-11-04): always a full refund.** On load the whole tree goes back to the class start
(every point returned, no gold) when:

- the save's `tree_version` is older than `data/passive_migrations.json`, or
- the allocation is illegal: a node no longer exists, is allocated twice, is not connected to
  the class start, more points are spent than the character has, another class start, or an
  exclusive pair.

The player sees "The passive web has changed: your N passive points have been refunded." once
when the next level loads. The original file is copied to `<slot file>.tree<old version>.bak`
the first time. A save without its start node just gets it back (old behaviour). A save from
a newer tree keeps a legal allocation (warning only).

## Changing the tree (from Phase 2 on)

1. Edit `data/tree_src/*`, run `python tools/gen_clusters.py`.
2. If ids, links, costs or effects changed: bump `tree_version` and add
   `history["<new version>"] = {"old_id": "new_id" | null}` for removed or renamed ids.
3. New flag: add it to `passive_flags.json` and write `flag_<id>` in the tests.
4. Run `tests/tree_only.tscn`, then the full suite.
5. Smartbot: compare with `tests/smartbot/baseline/tree_v4.csv` (earlier: tree_v1..v3); re-baseline only at the end
   of Phase 2 and of Phase 3 (see `tests/smartbot/baseline/BASELINES.md`).

## Phase 2 nodes (tree_version 2)

24 behaviour nodes as spurs off the class clusters (ids `p2_*`, `rev` 2). Numbers are placeholders for the Phase 6 balance pass.

| Archetype | Id | Node | Type | Attached to | Flag | Effect | Drawback |
|---|---|---|---|---|---|---|---|
| W Bleed Berserker | `p2_bf_a` | Opened Veins | notable | `w_mel3` | `opened_veins` | Melee critical strikes always inflict Bleed. +5% chance to inflict Bleed. |  |
| W Bleed Berserker | `p2_bf_b` | Blood Scent | notable |  | `blood_scent` | Killing a bleeding enemy restores 4% of your maximum life. 8% increased physical damage. |  |
| W Bleed Berserker | `p2_ks_frenzy` | Blood Frenzy | keystone |  | `blood_frenzy` | Each bleeding enemy within 150 units grants 4% more attack speed (up to 5). You take 10% more physical damage. No life regeneration while above 50% life. | You take 10% more physical damage, and you do not regenerate life while above 50% life. |
| W Iron Riposte | `p2_ir_a` | Counterweight | notable | `w_blk1` | `counterweight` | Blocking grants 40% increased melee damage for 2 seconds. +2% block chance. |  |
| W Iron Riposte | `p2_ir_b` | Staggering Guard | notable |  | `staggering_guard` | Blocking a hit stuns the attacker if it is within 70 units. 10% increased armour. |  |
| W Iron Riposte | `p2_ks_riposte` | Iron Riposte | keystone |  | `iron_riposte` | Blocking triggers a free counterattack that hits all enemies within 55 units with your weapon (0.5s cooldown). +5% block chance. You cannot dodge roll; movement skills cost 50% more. | You cannot dodge roll, and movement skills cost 50% more. |
| W War Herald | `p2_wh_a` | Rallying Cry | notable | `c_w1` | `rallying_cry` | Killing a stunned enemy resets the skill with the shortest remaining cooldown. 5% increased cooldown recovery. |  |
| W War Herald | `p2_wh_b` | Herald's Voice | notable |  | `war_herald` | Buff skills last 50% longer and stun enemies within 70 units when used. 10% increased stun threshold. |  |
| R Clockwork | `p2_cw_a` | Volatile Mechanisms | notable | `r_trap2` | `volatile_mechanisms` | Turrets explode when they expire or are replaced; traps go off instead of fizzling. 8% increased trap damage. |  |
| R Clockwork | `p2_cw_b` | Overclock | notable |  | `overclock` | Turrets fire 25% faster while you are within 120 units of them. 8% increased turret damage. |  |
| R Clockwork | `p2_ks_clockwork` | Clockwork Mind | keystone |  | `clockwork_mind` | +2 maximum turrets. Turret and trap hits use your weapon's critical chance if it is higher. Your other hits deal 30% less damage. | Your own hits (not turrets, traps or minions) deal 30% less damage. |
| R Venom | `p2_vn_a` | Agonising Toxins | notable | `r_prj3` | `agonising_toxins` | Your hits have 10% chance to poison. Your poisons stack up to 3 times; an enemy with 3 stacks suffers Agony. 8% increased damage over time. |  |
| R Venom | `p2_vn_b` | Virulence | notable |  | `virulence` | When a poisoned enemy dies, its poison spreads to the nearest enemy within 90 units. 8% increased status duration. |  |
| R Venom | `p2_ks_venom` | Venom Pact | keystone |  | `venom_pact` | Your hits have 20% chance to poison. Poisons stack (up to 20) and last 40% longer. Your hits cannot be critical strikes. | Your hits cannot be critical strikes. |
| R Deadeye | `p2_de_a` | Marked for Death | notable | `c_r1` | `marked_for_death` | Projectile critical strikes Mark the enemy for 2 seconds. Critical strikes against Marked enemies also hit one enemy nearby. 10% increased critical chance. |  |
| R Deadeye | `p2_de_b` | Shadowstep | notable |  | `shadowstep` | Dodge rolling releases a frost nova that chills enemies within 60 units. 10% increased evasion. |  |
| M Embers | `p2_em_a` | Funeral Pyre | notable | `m_fire1` | `funeral_pyre` | Killing an ignited enemy grants 20% increased fire damage and 10% increased cast speed for 3 seconds. 8% increased fire damage. |  |
| M Embers | `p2_em_b` | Searing Insight | notable |  | `searing_insight` | Hits against ignited enemies have +25% critical strike chance. +5% chance to ignite. |  |
| M Embers | `p2_ks_embers` | Avatar of Embers | keystone |  | `avatar_of_embers` | Cold and lightning damage of your skills is converted to fire. +20% chance to ignite. You cannot chill, freeze or shock: those chances ignite instead. | You cannot chill, freeze or shock. |
| M Legion | `p2_lg_a` | Marrow Feast | notable | `m_min3` | `marrow_feast` | When one of your minions kills an enemy, it recovers 20% of its life. 10% increased minion life. |  |
| M Legion | `p2_lg_b` | Necrotic Orders | notable |  | `necrotic_orders` | Minion hits have 20% chance to inflict Frailty. 8% increased minion damage. |  |
| M Legion | `p2_ks_legion` | Legion of Bone | keystone |  | `legion_of_bone` | +2 maximum minions. Minions explode when they die, dealing 40% of their life as physical damage nearby. Minions have 30% less life; your own hits deal 20% less damage. | Minions have 30% less life, and your own hits deal 20% less damage. |
| M Hex | `p2_hx_a` | Frailty Bloom | notable | `c_m2` | `frailty_bloom` | When an enemy with Frailty dies, Frailty spreads to enemies within 80 units. 8% increased status duration. |  |
| M Hex | `p2_hx_b` | Hexblight | notable |  | `hexblight` | Hits against enemies with Frailty or Snare have 25% chance to inflict Agony. 8% increased damage over time. |  |

Exclusive pair: Blood Frenzy and Iron Riposte. Mind over Matter (`xa_ks`) gained its drawback: 30% less mana regeneration.

New hooks: poison stacking (`actor.add_status` with `max_stacks`; `poison_stacks()`; ordinary poison does not stack), Avatar of Embers conversion (`Combat.player_packet`, `Combat.apply_status`), `Combat._on_hit_passives`, `player._kill_passives` (`on_kill(e, killer)`), `player._on_block(source)`, `turret.retire()` / `mine.retire()` / `turret.overclocked()`, minion death burst in `minion.die`, Herald's Voice in the `buff` behaviour.

Status coverage after Phase 2 (nodes tagged): ignite 4, chill 1, freeze 0, shock 0, bleed 8, poison 3, stun 3, frailty 3, marked 1, snare 1, agony 2. Freeze and shock still need nodes (Phase 3).

## Phase 3a nodes (tree_version 3)

Phase 3a (Dan, 2026-11-04): bridge clusters on the three class roads, the Phase 0 conversions, the Phase 0 cuts and Abyss bonus points. Growth towards ~320 nodes is Phase 3b. New ids `p3_*`; converted and cut-adjacent nodes carry `rev` 3. Numbers are placeholders for Phase 6.

| Group | Id | Node | Type | Flag | Effect | Drawback |
|---|---|---|---|---|---|---|
| Bridge W-R (Hunter-Knight) | `h_wr3` | Hunter-Knight | notable | `hunter_knight` | Melee hits have a 20% chance to Mark enemies that are not Marked, for 2 seconds. Projectile hits against Marked enemies have +15% critical strike chance. 5% increased attack speed, 6% increased attack damage. |  |
| Bridge W-R (Hunter-Knight) | `p3_hk_a` | Pinning Shot | notable | `pinning_shot` | Projectile hits against Marked enemies Snare them for 1.5 seconds. 8% increased projectile damage. |  |
| Bridge W-R (Hunter-Knight) | `p3_hk_b` | Run Them Down | notable | `run_them_down` | Melee hits against Snared or Chilled enemies have +20% critical strike chance. 8% increased melee damage. |  |
| Bridge W-R (Hunter-Knight) | `p3_hk_ks` | Twin Disciplines | keystone | `twin_disciplines` | Using a melee skill after a projectile skill, or a projectile skill after a melee skill, makes it deal 25% more damage. Using the same kind twice in a row makes it deal 10% less. 10% increased attack damage. | Repeating a melee or projectile skill deals 10% less damage. |
| Bridge R-M (Hexshot) | `h_rm3` | Hexshot | notable | `hexshot` | The first projectile hit of each skill use applies the last curse you cast to the enemy hit. 6% increased elemental and projectile damage. |  |
| Bridge R-M (Hexshot) | `p3_hs_a` | Charged Quiver | notable | `charged_quiver` | Projectile hits have a 15% chance to Shock. 10% increased lightning damage. |  |
| Bridge R-M (Hexshot) | `p3_hs_b` | Overload | notable | `overload` | Killing a Shocked enemy Shocks every enemy within 80 units and deals 10% of its maximum life to them as lightning damage. 8% increased lightning damage. |  |
| Bridge R-M (Hexshot) | `p3_hs_ks` | Spell Archer | keystone | `spell_archer` | Increases to spell damage also apply to your projectile attacks. 15% less attack speed. | 15% less attack speed. |
| Bridge M-W (Spellblade) | `h_mw3` | Spellblade | notable | `spellblade` | Melee hits release a burst (50 units) of your last spell's element for 30% of the hit's damage: fire ignites, cold chills, lightning shocks. 0.6 second cooldown. 6% increased spell and melee damage. |  |
| Bridge M-W (Spellblade) | `p3_sb_a` | Rime Edge | notable | `rime_edge` | Melee hits against Chilled enemies have a 25% chance to Freeze them. 10% increased cold damage. |  |
| Bridge M-W (Spellblade) | `p3_sb_b` | Shatter | notable | `shatter` | Killing a Frozen enemy shatters it: enemies within 60 units are Chilled and take 10% of its maximum life as cold damage. 8% increased cold damage. |  |
| Bridge M-W (Spellblade) | `p3_sb_ks` | Battlemage's Covenant | keystone | `battlemage` | Increases to spell damage also apply to your melee attacks, and increases to melee damage also apply to your spells. 15% less maximum life. | 15% less maximum life. |
| Conversion | `w_brutal` | Brutal Force | notable | `brutal_force` | Melee hits against Stunned or Frozen enemies are always critical strikes. 12% increased melee damage, 5% increased attack speed. |  |
| Conversion | `w_life3` | Second Wind | notable | `second_wind` | When a hit leaves you below 35% life, recover 20% of your maximum life over 4 seconds (20 second cooldown). 8% increased maximum life, +1.5 life regeneration. |  |
| Conversion | `r_deadeye` | Deadeye Mastery | notable | `deadeye_mastery` | Projectile hits against enemies more than 160 units away Snare them for 1.5 seconds. +1 pierce, 8% increased projectile damage. |  |
| Conversion | `r_engineer` | Engineer's Doctrine | notable | `engineers_doctrine` | Turret and trap hits have a 15% chance to Shock. +1 turret limit, 10% increased turret damage. |  |
| Conversion | `r_crit2` | Killer Instinct | notable | `killer_instinct` | Critical strikes against Chilled enemies Freeze them. +20% critical strike multiplier, 10% increased critical strike chance. |  |
| Conversion | `m_flame` | Pyroclasm | notable | `pyroclasm` | Ignited enemies explode when they die, dealing 10% of their maximum life as fire damage to enemies within 60 units. 12% increased fire damage, +10% chance to ignite. |  |
| Conversion | `m_command` | Commander Mastery | notable | `commanders_edge` | Your minions use your critical strike chance increases and critical strike multiplier. +1 minion limit, 8% increased minion speed. |  |
| Conversion | `m_flow` | Rift Step | notable | `rift_step` | Blink Snares enemies within 60 units of where you leave and where you arrive, for 2 seconds. 15% increased mana regeneration, 8% reduced mana cost. |  |
| Conversion | `c_dot2` | Festering Wounds | notable | `festering_wounds` | Bleed, ignite and poison you inflict on Snared or Marked enemies last 50% longer. 15% increased damage over time, +6% status chance, 15% increased ailment duration. |  |
| Conversion | `xp_r0` | Elemental Warding | notable | `elemental_warding` | Ignite, Chill, Freeze and Shock on you last 50% shorter. +8% fire, cold and lightning resistance. |  |
| Conversion | `xp_ks` | Prismatic Soul | keystone | `prismatic_soul` | You cannot be Ignited, Chilled, Frozen or Shocked. +25% fire, cold and lightning resistance and 15% more elemental damage. You cannot inflict Ignite, Chill, Freeze or Shock, and you have 40% less armour and evasion. | You cannot inflict Ignite, Chill, Freeze or Shock. 40% less armour and evasion. |
| Conversion | `xw_r0` | Tailwind | notable | `tailwind` | Using a movement skill (dash, leap or blink) resets your dodge roll cooldown. 8% increased movement speed and cooldown recovery. |  |
| Conversion | `xe_r0` | Deathblow | notable | `deathblow` | Killing an enemy with a critical strike grants 20% increased critical strike chance and 10% increased attack and cast speed for 3 seconds. +20% critical strike multiplier, +4 life on kill. |  |
| Conversion | `xa_r0` | Arcane Shell | notable | `arcane_shell` | Taking a hit of at least 15% of your maximum life grants Arcane Shell: +20% damage reduction for 3 seconds (8 second cooldown). 10% increased maximum mana, +3% damage reduction. |  |
| Conversion | `xv_r0` | Abyssal Gaze | notable | `abyssal_gaze` | Void and arcane hits have a 15% chance to inflict Frailty for 4 seconds. 12% increased void and arcane damage. |  |

Bridge spurs: road centre (now a notable) -> 2 minors -> two notables side by side -> 1 minor -> bridge keystone (`p3_hk_ks` also links down to `xs_r4` through `p3_hk_4`, so mages can reach it). Every class reaches all 23 keystones; dearest 36 (W), 36 (R), 33 (M) points.

Cuts (history[3] -> null): Wanderer's Road `xo0..5_2` and `_4` (each arc 6 nodes of +4 -> 4 nodes of +6, surviving ids pinned with an explicit "id" in the spec), `xp_p13`, `xp_p14` (Prismatic approach path 4 -> 2). Prismatic Soul `xp_ks` is exclusive with Avatar of Embers `p2_ks_embers`.

Generator: path/arc slots may carry an explicit `"id"`; hand-node links into generated nodes are mirrored automatically.

Abyss bonus points: `passive_flags.json` `abyss_point_depths` [10..70]; `CharacterData.abyss_passive_points()` counts depths <= `progress.abyss_best` and is added to `total_passive_points()` (retroactive, never stored). 59 + 6 boss + 7 Abyss = 72 = `budget_l60`. `dungeon.gd` shows a message when a milestone is crossed.

New hooks: `Combat._on_hit_phase3`, `Combat.death_burst` (Overload, Shatter, Pyroclasm, Spellblade), conditional crit in `Combat.deal`, Spell Archer/Battlemage stat routing in `player_packet`, `player._before_skill` (last spell type, Twin Disciplines), `player._hit_passives` (Second Wind, Arcane Shell), `player.add_status` (Prismatic Soul, Elemental Warding), `skill_exec.rift_snare`, `player.last_curse` set in `_curse`.

Status coverage after Phase 3a: ignite 7, chill 8, freeze 6, shock 6, bleed 8, poison 3, stun 4, frailty 5, marked 5, snare 6, agony 3. Behaviour nodes 66 of 232 (28%).

## Phase 3b nodes (tree_version 4)

Phase 3b (Dan, 2026-11-04): six archetype spurs, two per class, one keystone per class (Dan chose Barrage over Gunslinger). Tree 232 -> 316 nodes (+84), keystones 23 -> 26, behaviour nodes 66 -> 84 (27%). Ids `p3b_<spur>_<slot>`, `rev` 4. Numbers are placeholders for Phase 6.

Each spur is a "wheel" of 14 nodes: 2 travel minors (`_t1`, `_t2`) -> a ring of 10 (`_r0`..`_r9`; behaviour notables at `_r3` and `_r7`, a greater at the far side `_r5`) -> the capstone in the ring centre (`_cap`, linked from `_r5`) and a greater tip outside the ring (`_tip`). Both sides of the ring cost the same, so the player picks which notable to pass.

| Spur | Anchor | Where |
|---|---|---|
| Earthbreaker (`eb`) | `w_brutal` | outside Wanderer's Road below Weapon Master; `_t2` and `_r0` join the road at `xo0_3` |
| Duelist (`du`) | `w_bulwark` | left of Iron Bastion |
| Trapper (`tr`) | `r_engineer` | right of Engineer (mirror of Duelist) |
| Barrage (`ba`) | `r_deadeye` | outside the road below Marksman; joins the road at `xo1_5` |
| Tempest (`ts`) | `m_storm` | above Elementalist |
| Frostweaver (`fw`) | `m_command` | above Necromancy |

| Archetype | Id | Node | Type | Flag | Effect | Drawback |
|---|---|---|---|---|---|---|
| W Earthbreaker | `p3b_eb_r3` | Tremor Lines | notable | `tremor_lines` | Slam hits Snare enemies for 1.5 seconds. Stuns you inflict on Snared enemies last 50% longer. 8% increased area. |  |
| W Earthbreaker | `p3b_eb_r7` | Shockwave | notable | `shockwave` | Killing a Stunned enemy releases a shockwave: enemies within 70 units take 10% of its maximum life as physical damage and are Stunned. 8% increased melee damage. |  |
| W Earthbreaker | `p3b_eb_cap` | Earthbreaker | keystone | `earthbreaker` | Slam skills deal 35% more damage and always Stun the enemies they hit. 20% less attack speed. | 20% less attack speed. |
| W Duelist | `p3b_du_r3` | Feint | notable | `feint` | After a dodge roll, your next melee hit within 2 seconds is a critical strike. 10% increased critical strike chance. |  |
| W Duelist | `p3b_du_r7` | Single Combat | notable | `single_combat` | Melee hits against an enemy with no other enemy within 110 units Mark it for 3 seconds. 10% increased damage against elites and bosses. |  |
| W Duelist | `p3b_du_cap` | Blade Dance | notable | `blade_dance` | Melee critical strikes grant a stack of Blade Dance for 3 seconds: 5% increased attack speed and movement speed per stack (up to 4). 6% increased attack speed. |  |
| R Barrage | `p3b_ba_r3` | Volley Fire | notable | `volley_fire` | Attacks that fire more than one projectile fire 2 more. Attacks that fire a single projectile pierce 1 more enemy. 8% increased projectile damage. |  |
| R Barrage | `p3b_ba_r7` | Arrowstorm | notable | `arrowstorm` | Every 10th projectile attack hit calls down 3 volleys of arrows on the target (radius 40), each dealing 40% of that hit's damage. 6% increased attack speed. |  |
| R Barrage | `p3b_ba_cap` | Endless Quiver | notable | `endless_quiver` | Projectile attacks have a 15% chance to fire a second time. 5% increased attack speed. |  |
| R Trapper | `p3b_tr_r3` | Barbed Snares | notable | `barbed_snares` | Trap hits Snare enemies for 2 seconds and have a 30% chance to inflict Bleed. 10% increased trap damage. |  |
| R Trapper | `p3b_tr_r7` | Noxious Payload | notable | `noxious_payload` | Trap hits poison Snared enemies. Your poisons on Snared enemies stack up to 5 times; an enemy with 5 stacks suffers Agony. 8% increased damage over time. |  |
| R Trapper | `p3b_tr_cap` | Master Trapper | keystone | `master_trapper` | +1 to the maximum number of each trap. Your traps arm instantly and deal 30% more damage. You cannot deploy turrets. | You cannot deploy turrets. |
| M Tempest | `p3b_ts_r3` | Conductive Web | notable | `conductive_web` | When you Shock an enemy, the nearest unshocked enemy within 90 units is also Shocked. 10% increased lightning damage. |  |
| M Tempest | `p3b_ts_r7` | Thunderhead | notable | `thunderhead` | Every 4th lightning spell you cast also strikes the enemy nearest your target with a bolt for 150% of the spell's damage, Shocking it. 6% increased cast speed. |  |
| M Tempest | `p3b_ts_cap` | Static Cascade | notable | `static_cascade` | Lightning hits against Shocked enemies arc to another enemy within 100 units for 50% of the hit's damage. 10% increased lightning damage. |  |
| M Frostweaver | `p3b_fw_r3` | Cold Snap | notable | `cold_snap` | When you Freeze an enemy, enemies within 70 units are Chilled. 10% increased cold damage. |  |
| M Frostweaver | `p3b_fw_r7` | Brittle | notable | `brittle` | Hits against Frozen enemies have +30% critical strike chance. Freezes you inflict last 30% longer. 10% increased critical strike chance. |  |
| M Frostweaver | `p3b_fw_cap` | Glacial Heart | keystone | `glacial_heart` | Cold hits always Chill. Hits against Frozen enemies deal 40% more damage. Hits against enemies that are neither Chilled nor Frozen deal 20% less damage. | Hits against enemies that are neither Chilled nor Frozen deal 20% less damage. |

Exclusive pairs: Master Trapper ⟂ Clockwork Mind; Glacial Heart ⟂ Avatar of Embers and ⟂ Prismatic Soul.

New hooks: Earthbreaker / Master Trapper `extra_more` and Phase 3b status enablers in `Combat.player_packet`; Feint, Brittle crit and pre-hit shock (`_was_shocked`) in `Combat.deal`; Glacial Heart in `_conditional`; `Combat._freeze` (Brittle duration, Cold Snap), Conductive Web, Noxious Payload stacks and Tremor Lines stun in `apply_status`; `Combat._on_hit_phase3b` (Blade Dance, Arrowstorm, Static Cascade, Single Combat, Noxious Payload); `Combat.arrow_rain`; `player.feint_t` / `arrowstorm_n` / `thunder_n`, `player.blade_dance_stack()`, `player._thunderhead()`, Endless Quiver and Thunderhead in `_on_skill_used`, Shockwave in `_kill_passives`, turret block in `use_block_reason`; `SkillExec.proj_count()` / `proj_pierce()` (Volley Fire) and +1 trap limit in `_deploy`; instant arming in `Mine.setup`.

Status coverage after Phase 3b: ignite 7, chill 12, freeze 9, shock 10, bleed 9, poison 5, stun 7, frailty 5, marked 6, snare 9, agony 4. Dearest keystone: 36 (W), 36 (R), 29 (M) points.

One-off build script and layout: `../_claude_xfer/phase3b/` (`build_p3b.py`, `spurs_geom.json`, `content.py`); backups of the touched files: `../_claude_xfer/phase3b_backup/`.

## Phase 4a masteries (tree_version 5)

Choice layer, PoE 3.16 style (Dan, 2026-11-04: masteries first; sockets are Phase 4b).
Tree 316 -> 328 nodes. One-off build script: `../_claude_xfer/phase4/build_p4a.py`
(layout `mastery_geom.json`); backups `../_claude_xfer/phase4_backup/`.

Rules:
- A node of type `mastery` costs 1, has no mods/flags of its own and names its group in
  `mastery`. Groups and options live in `data/passive_flags.json` → `masteries`
  (`{group: {name, tags, options: [{id, name, mods, flags?}]}}`); option mods are `flat`/`inc` only.
- Each mastery hangs off exactly one notable/greater (a leaf), so it unlocks after that
  notable. Routes never pass through a mastery (`TreeRules.cheapest_costs`, `CharacterData.path_to`).
- Allocating needs an option: `allocate(id, option)` / `allocate_path(id, option)`; without
  one it fails. An option id can be chosen **at most once across the tree**; 3 groups are
  placed twice (bleed, projectile, elemental), so one character can take two different
  options of those.
- `change_mastery(id, option)` swaps the effect for `refund_cost()` gold (the price of one
  node). Refunding the node clears its choice.
- Save: `mastery_choices` (`{node_id: option_id}`, written only when non-empty).
  `TreeRules.allocation_problem(..., choices, masteries)` treats a missing, wrong-group or
  duplicated choice as an illegal allocation → full free refund (same policy as before).
- `build_stats` / `preview_final` / `preview_skill_avg` take an optional `choices` map for previews.
- Bots (smartbot planner, tests/bot.gd) skip masteries, like keystones.
- UI: hexagon node, label shows the chosen effect; tooltip lists all effects (current in
  green, taken elsewhere greyed); LMB opens the effect menu (allocate or change for gold),
  RMB refunds. Screenshots: `tests/screens_tree_p4.tscn -- <outdir>`.

| Node | Name | Cluster |
|---|---|---|
| `p4_m_melee` | Melee Mastery | Weapon Master (off `w_2h`) |
| `p4_m_bulwark` | Bulwark Mastery | Iron Bastion (off `w_blk1`) |
| `p4_m_bleed_w` | Bloodletting Mastery | Bloodrage (off `p2_bf_a`) |
| `p4_m_bleed_x` | Bloodletting Mastery | Sanguine Rites (off `xs_r6`) |
| `p4_m_proj_r` | Projectile Mastery | Marksman (off `r_pspd`) |
| `p4_m_proj_b` | Projectile Mastery | Barrage (off `p3b_ba_tip`) |
| `p4_m_deploy` | Deployable Mastery | Engineer (off `r_trap2`) |
| `p4_m_afflict` | Affliction Mastery | Venom (off `p2_vn_a`) |
| `p4_m_elem_m` | Elemental Mastery | Elementalist (off `m_ele`) |
| `p4_m_elem_t` | Elemental Mastery | Tempest (off `p3b_ts_tip`) |
| `p4_m_minion` | Minion Mastery | Necromancy (off `m_minl`) |
| `p4_m_mind` | Mind Mastery | Mind Fortress (off `xa_r2`) |

| Group | Options (placeholder numbers, Phase 6 tunes them) |
|---|---|
| Melee Mastery (`melee`) | `melee_fury` Fury: 20% increased melee damage<br>`melee_tempo` Tempo: 8% increased attack speed, 4% increased move speed<br>`melee_leech` Bloodthirst: +2 life on hit<br>`melee_heavy` Heavy Blows: +20 crit multi, 6% reduced attack speed |
| Bulwark Mastery (`bulwark`) | `bw_block` Shield Wall: +5 block chance<br>`bw_plate` Plated: 30% increased armour, 10% increased stun threshold<br>`bw_stand` Stand Firm: +4 damage reduction, 8% reduced move speed<br>`bw_regen` Second Wind: +2 life regen |
| Bloodletting Mastery (`bleed`) | `bl_chance` Serrated: +15 bleed chance<br>`bl_rend` Rend: 20% increased dot damage, 8% increased physical damage<br>`bl_long` Lingering Wounds: 25% increased status duration<br>`bl_feast` Blood Feast: +5 life on kill, 10% increased physical damage |
| Projectile Mastery (`projectile`) | `pj_split` Split Shot: +1 projectile count, 15% reduced projectile damage<br>`pj_pierce` Piercing: +1 pierce<br>`pj_chain` Ricochet: +1 chain, 10% reduced projectile damage<br>`pj_velocity` Velocity: 20% increased projectile speed, 12% increased projectile damage |
| Deployable Mastery (`deployable`) | `dp_turret` Battery: +1 turret limit, 10% reduced turret damage<br>`dp_trap` Hair Trigger: 25% increased trap damage<br>`dp_cd` Quick Assembly: 12% increased cooldown recovery<br>`dp_blast` Wide Charges: 15% increased area, 8% increased trap damage |
| Affliction Mastery (`affliction`) | `af_dot` Corrosion: 25% increased dot damage<br>`af_chance` Contagion: +8 status chance<br>`af_dur` Slow Rot: 25% increased status duration<br>`af_elite` Bane: 20% increased damage vs elite |
| Elemental Mastery (`elemental`) | `el_dmg` Attunement: 20% increased elemental damage<br>`el_ward` Elemental Ward: +12 res fire, +12 res cold, +12 res lightning<br>`el_ail` Overload: +8 status chance, 10% increased status duration<br>`el_flow` Flowing Casts: 10% increased cast speed, 10% reduced mana cost |
| Minion Mastery (`minion`) | `mn_horde` Horde: +1 minion limit, 15% reduced minion damage<br>`mn_power` Dark Pact: 25% increased minion damage<br>`mn_tough` Bone Armour: 30% increased minion life<br>`mn_swift` Hasted Dead: 15% increased minion speed, 10% increased minion damage |
| Mind Mastery (`mind`) | `md_well` Deep Well: 15% increased max mana, 20% increased mana regen<br>`md_thrift` Thrift: 15% reduced mana cost<br>`md_arcane` Esoterica: 15% increased arcane damage, 15% increased void damage<br>`md_haste` Quickened Mind: 12% increased cooldown recovery |

## Phase 4b tree sockets (tree_version 6)

Choice layer, Diablo 4 glyph style (Dan, 2026-11-04: 9 sockets, 2 per class + 1 per bridge;
gem gives a tree stat table by grade plus a radius boost to allocated nodes sharing its tags).
Tree 328 -> 337 nodes. One-off build script: `../_claude_xfer/phase4b/build_p4b.py`
(layout `socket_geom.json`, placement search `place.py`); backups `../_claude_xfer/phase4b_backup/`.

Rules:
- A node of type `socket` costs 1, has no mods/flags of its own, hangs off one or two
  notables/greaters (the bridge sockets sit in the middle of each bridge diamond, linked to
  both notables) and is never routed through (`TreeRules.NO_ROUTE`).
- Socketing is free: `CharacterData.socket_tree_gem(node, gid)` takes the gem from the pouch
  (`gems`), a gem already there goes back; `unsocket_tree_gem(node)` returns it. Gem level
  requirements apply. Refunding the socket returns its gem; `clear_tree_gems()` (used by the
  dev respec) returns all.
- Effect 1: the gem's `tree` table in `data/gems.json`, scaled by the tier `mult` like the
  item tables (`Loot.gem_mods(gid, "tree")`). Shown in the Jeweller tooltip ("Passive tree: ...").
- Effect 2: every allocated minor/greater/notable within `radius` (240 tree units) of the
  socket that shares a tag with the gem's `tree_tags` has its mod values raised by
  `boost_pct[tier]` (15/25/35/50%). Keystones, masteries, starts and sockets are never boosted;
  `more` mods are never boosted. A node in two matching rings takes the larger boost (no
  stacking). Config: `data/passive_flags.json` -> `tree_sockets`. Pure rule:
  `TreeRules.socket_boosts`; applied in `CharacterData.build_stats`.
- Save: `tree_gems` (`{socket_id: gem_id}`, written only when non-empty). On load, a gem whose
  socket is not allocated (for example after a full tree refund) goes back to the pouch;
  unknown gem ids are dropped. A bad socket entry never causes a tree refund.
- Bots (smartbot planner, tests/bot.gd) skip sockets.
- UI: socket node with a gem-coloured diamond when filled; hovering a socket draws its ring,
  filled sockets keep a faint ring; boosted nodes get a purple outline; LMB on an allocated
  socket opens the gem menu (remove / socket each pouch gem), RMB refunds (gem returns).
  Screenshots: `tests/screens_tree_p4b.tscn` (writes `tests/screens_out_tree_p4b/`).

| Node | Links | Cluster |
|---|---|---|
| `p4_s_w_in` Warrior Gem Socket | `w_1h` | Weapon Master |
| `p4_s_w_out` Duelist Gem Socket | `p3b_du_r7` | Duelist |
| `p4_s_r_in` Ranger Gem Socket | `r_gun` | Marksman |
| `p4_s_r_out` Trapper Gem Socket | `p3b_tr_r7` | Trapper |
| `p4_s_m_in` Mage Gem Socket | `m_ele` | Elementalist |
| `p4_s_m_out` Frostweaver Gem Socket | `p3b_fw_r3` | Frostweaver |
| `p4_s_wr` Hunter-Knight Gem Socket | `p3_hk_a`, `p3_hk_b` | Warrior-Ranger Road |
| `p4_s_rm` Hexshot Gem Socket | `p3_hs_a`, `p3_hs_b` | Ranger-Mage Road |
| `p4_s_mw` Spellblade Gem Socket | `p3_sb_a`, `p3_sb_b` | Mage-Warrior Road |

Reach: each class reaches its own 2 sockets and its 2 bridge sockets within budget (max 34
points). The far bridge socket sits behind that bridge's keystone, so the mage cannot reach
`p4_s_wr` (same as the Hunter-Knight notables).

| Gem | Tree table (Chipped; x tier mult) | tree_tags (radius boost) |
|---|---|---|
| Ruby | 4% fire_damage, 4 res_fire (flat) | fire, ignite |
| Sapphire | 4% cold_damage, 4 res_cold (flat) | cold, chill, freeze |
| Topaz | 4% lightning_damage, 4% trap_damage | lightning, shock, trap, deployable |
| Onyx | 4% physical_damage, 5% armour | physical, melee, armour, stun, block |
| Emerald | 2% attack_speed, 4% projectile_speed | speed, projectile, evasion, mobility, dodge |
| Amethyst | 4% spell_damage, 4% minion_damage | spell, arcane, void, minion, mana |
| Diamond | 5% crit_chance, 3 crit_multi (flat) | crit, execute, marked, resist |
| Bloodstone | 6 max_life (flat), 4% dot_damage | life, sustain, bleed, poison, dot, ailment |

## Phase 5a tree UI (no data change)
Navigation and readability only; see `docs/TREE_UI_CONTRACT.md` for the node-state contract
with Codex V5, the zoom levels and the filters. New code: `TreeRules.stat_theme`,
`theme_order`, `is_behaviour_node`, `sum_mod`; `CharacterData.tree_summary()`;
`tree_refund.ids` (runtime only, not saved). Tests: `test_tree_ui_5a` in
`tests/test_passive_tree.gd`.
