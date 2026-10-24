extends Node
## Global signal bus. Systems emit here so UI, progression and loot stay decoupled.

signal enemy_killed(enemy, killer)
signal player_damaged(amount)
signal player_died
signal player_leveled(level)
signal xp_changed
signal stats_changed
signal inventory_changed
signal currency_changed
signal skill_unlocked(skill_id)
signal loadout_changed
signal passive_changed
signal boss_spawned(boss)
signal boss_died(boss)
signal objective_changed(text)
signal message(text, color)
signal item_picked(item)
signal level_ready(level)
signal ui_panel_toggled(name, open)
