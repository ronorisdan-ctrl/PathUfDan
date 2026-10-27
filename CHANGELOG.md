# Changelog

## Training Grounds (branch `feature/training-grounds`, not merged)

Added
- **Drillmaster Rook** (hub NPC) and a Training panel with Setup, Result and History tabs.
- Single-target and three-dummy AoE DPS tests: 10 s or 30 s, All sources or Player only, defence profile (none, Tier 3 normal enemy, Tier 6 boss with poise), cluster spacing Tight or Spread.
- Result above the dummy's head (average DPS, peak second, settings, top three sources; in AoE a total line above dummy 1 and each dummy's own DPS and share), and a full Result tab with a per-skill breakdown, per-dummy table and average targets hit per cast.
- History of the last 5 tests per character (session only), with the change against the previous comparable test, a build snapshot (character, level, specialisation, main/off hand, hotbar, passives) and "what changed since last time". Clear history asks for confirmation.
- `data/training.json` (all tuning and wording), `scripts/core/training_rules.gd` (pure rules), `scripts/core/training_log.gd` (new autoload `TrainingLog`, listed last, after `Dev`), `scripts/entities/training_dummy.gd`, `scripts/ui/training_panel.gd`.
- Tests: `test_training()` and `test_training_world()` in `tests/test_runner.gd` (about 160 checks), `tests/train_only.tscn` for a quick run, `tests/screens_training.tscn` for screenshots.

Changed
- The old fixed hub dummy (an enemy entry in the hub) is replaced by the spawnable training dummy.
- Summon, deploy and buff skills are allowed in the hub, but only while training dummies exist (`player.gd`, one condition).
- Player damage packets carry a cast number (`Combat.cast_serial`); statuses record the skill that applied them (`src_skill`, `src_kind`); minions know which skill summoned them. These are bookkeeping only: smartbot results are byte-identical to the baseline (warrior/ranger/mage, tier 2 Competent and tier 3 Expert, seed 700).

Not changed
- Gameplay, balance, the save format (no `SAVE_VERSION` change) and the existing autoload order (`TrainingLog` is appended).
- The Training Grounds are off under `Game.testing` unless `Game.training_in_tests` is set.
