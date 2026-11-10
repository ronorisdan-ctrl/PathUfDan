extends SceneTree
## Phase 2E: distribution check of Pentimento Vault type rolls (seeded like dungeon.gd).
func _init() -> void:
	var WV = load("res://scripts/core/wager_vault_rules.gd")
	var cnt := {}
	var rng := RandomNumberGenerator.new()
	for s in 2000:
		var run_seed: int = hash([900, s, 0]) & 0x7fffffff
		rng.seed = run_seed * 31 + 7
		for i in range(7, 0, -1):
			rng.randi_range(0, i)
		var t: String = WV.roll_type(rng)
		cnt[t] = int(cnt.get(t, 0)) + 1
	print("TYPES ", cnt)
	quit()
