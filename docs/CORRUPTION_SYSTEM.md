# Corruption system v1

Implemented against the 4 November 2026 design baseline. All 82 section-5 families are represented exactly: 62 ordinary P2 families, six P3 Signatures and 14 P4 exceptional families. P4 families have individual feature gates and are enabled after their gameplay acceptance tests. No numerical balance changes were made to the design tables.

The Blacksmith's **Corrupt Item** action costs one Abyssal Brand, defaults to zero gold and accepts owned, unequipped inventory equipment below 100% corruption. A single integer draw selects destruction / no modifier / single / double at 15 / 25 / 56 / 4. Every survivor is permanently sealed at 100%. Normal affixes, Legendary effects, sockets and gems survive unchanged. Destruction recovers gems once, following the existing sale/salvage policy. Selling, equipping and ordinary salvage remain available.

## Compatibility decisions

| Existing behavior | Resolution |
|---|---|
| Ordinary crafting gains corruption at 60% chance, +25 each hit | Preserved below 100%. Upgrade/removal/socketing still gain no corruption. The spec supersedes their historical exemption from the **100% seal**. |
| Bases use `shortbow`, `longbow`, `crossbow`, `pistol`, `rifle`, `focus`, `spellbook` | Data alias expansion supplies bow/firearm/caster-offhand tags. Pools come from runtime base metadata; focus/book/quiver/shield stay in Other Equipment. All 129 bases have both sides and compatible doubles at tested levels. |
| Increased damage versus elites is historically a separate multiplier | Historical sources remain unchanged. Corruption's elite bonus enters the additive increased bucket at hit resolution. |
| Player damage reduction resolves to 60%, with certain temporary effects reaching 75% | Preserved. Bastion's hit-only contribution stops at 60%; it cannot amplify the existing temporary exception. Block 75%, evasion 60%, armour 80% and base resistance 75% remain unchanged. Sovereign raises only derived elemental caps, with a separate absolute 78% safety cap. |
| Skill levels cap at 20 and existing charms/Legendary gear already grant levels | Preserved and stacked through the existing level resolver. Corruption raises matching usable active skills, never progression/passive levels. Existing damage scaling and rune-socket thresholds apply; no new level-based cooldown scaling was invented. |
| Damage-over-time effects snapshot their originating hit | Final Blow is evaluated at the hit, then follows the existing DoT snapshot policy. Deathless minion damage is rebuilt from the owner's current life on each minion attack. |
| Minion/deployable caps retire excess units on the next summon/deployment | Preserved. Trap capacity is per existing trap/mine type; no global capacity model was substituted. |
| Volley Fire changes behavior based on single versus multiple shots | It reads the actual supported shot count, including corruption. Existing rune and non-corruption projectile sources remain outside corruption's +2 cap. |
| F1 developer tools deliberately edit game state and taint the save | Existing developer cheats remain development-only; normal crafting, inventory and Jeweller paths honor the permanent seal. |

## Persistence and transactions

Optional item fields are `corrupted_prefix`, `corrupted_suffix` and `corruption_roll_version`. Each implicit stores a stable family ID, a genuine tier or fixed `null` tier, the actual shared rolled value and its expanded effects. Old items default to empty implicit slots/version zero and retain their corruption; no retroactive rolls. Unknown or malformed implicit records are retained in quarantine fields and disabled, while preserving the sealed item and its other contents. Personal and shared stash use the same normalization.

Actions resolve a stable inventory UID, validate all data and eligible pairs, plan without mutation, then charge and commit once. Confirmation receipts persist across reload. Ordinary saves use the existing atomic writer; a failed manual save restores item, materials, gold, gems and receipt, and never autosaves the aborted transaction. Successful manual commits also autosave. The existing `SAVE_VERSION` is retained; no destructive migration or reroll occurs. Dodge's eight-second cooldown persists as remaining game-time, following the normal pause/hit-stop clock and surviving equipment swaps/reload.

Corruption effects have item-specific source IDs. Exceptional effects use typed operations rather than unknown stats. Brand drops have their own seeded RNG stream and one eligible kill roll: T5 boss 10%, T6 boss 15%, Endless depth increments up to 20%, endgame elite 0.1%. Brands have zero ordinary material-pool weight, never enter merchant/salvage yield and are never refunded.

## Verification and reports

```powershell
python tools/validate_corruption_data.py
godot --headless --fixed-fps 60 --path . res://tests/corruption_system.tscn -- foundation
godot --headless --fixed-fps 60 --path . res://tests/corruption_system.tscn
godot --headless --fixed-fps 60 --path . res://tests/test_runner.tscn
python tools/simulate_corruption_economy.py
godot --rendering-method gl_compatibility --path . res://tests/screens_corruption.tscn
```

The standalone data validator compares every registry field with a frozen copy of the authoritative design tables. Godot tests cover every outcome boundary, costs/ownership/replay, failures before commit and during persistence, old/current save fixtures, gem recovery, all slots/levels, every ordinary band endpoint, compound rolls, fixed tiers, gates, incompatible doubles, stat sources, gameplay handlers and UI confirmation/cancellation/results. Stochastic checks use one million outcomes, 100,000 draws per tier-level scenario, 200,000 category draws, weighted family selection and 100,000 independent ordinary double plans.

Final Godot 4.0 run: **47,781 passed / 0 failed**, including **44,639 corruption checks**. The old all-skills summon assertion now checks actual creation at cast time, avoiding a false failure when successfully summoned minions die during the test's later combat window. The broad legacy suite still emits intentional malformed-save diagnostics and existing engine cleanup/leak warnings at exit.

- `corruption_training_matrix.json`: 20 matched ten-second Training Grounds samples across Warrior melee, Ranger projectile/turret and Mage spell/summon. Uses real combat, status and TrainingLog paths with scripted attack cadence, fixed initial deployed counts and maximum rolls within each tier. It records DPS, hits, use/fire time, cast speed, defence stats and CPU time. The target-clear column is an explicitly labeled DPS proxy, **not measured dungeon clear speed**. Small hit counts and critical-hit sampling limit balance conclusions. Sustained mana starvation, navigation and full dungeon performance remain playtest considerations.
- `corruption_economy.json`: 100,000 simulated hours per income scenario, assuming six bosses and 60 endgame elites per hour. Average Brands/hour: T5 about 0.66, T6 0.96, capped Endless 1.26. These are scenario assumptions, not player telemetry. Mean attempts including success: any double 25; eligible Forbidden Knowledge 625; double T1 conditional on both families being ordinary 2,500. No guarantee/pity or drop-rate retuning.
- Screenshot runner includes the irreversible warning, result and Legendary double tooltip, retaining distinct Legendary and corruption colors. Long corruption results stay inside the Blacksmith scroll area so controls remain accessible.

All mechanical families are implemented; none are placeholders. Real-run economy, dungeon-clear and long-session performance tuning require playtest telemetry rather than changing the specified numbers from a short benchmark.
