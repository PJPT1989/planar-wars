extends Node
## Headless balance test (`godot --headless --path . -- --simtest [--map=N] [--players=N] [--level=N] [--minutes=N]`):
## AI-only matches on every map at full speed without drawing. Prints each match's winner,
## length and per-player stats. A good run has a winner on every map before the time limit.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var only := -1
	var n := 4
	var level := 1
	var minutes := 40.0
	var seed_v := 1234
	for a in args:
		if a.begins_with("--map="):
			only = int(a.get_slice("=", 1))
		elif a.begins_with("--players="):
			n = int(a.get_slice("=", 1))
		elif a.begins_with("--level="):
			level = int(a.get_slice("=", 1))
		elif a.begins_with("--minutes="):
			minutes = float(a.get_slice("=", 1))
		elif a.begins_with("--seed="):
			seed_v = int(a.get_slice("=", 1))
	for m in Data.MAPS.size():
		if only >= 0 and m != only:
			continue
		_run(m, n, level, minutes, seed_v + m)
	get_tree().quit()


func _run(map_i: int, n: int, level: int, minutes: float, seed_v: int) -> void:
	seed(seed_v)
	var cfg := []
	for i in n:
		cfg.append({"name": "AI %d" % (i + 1), "race": Data.RACE_ORDER[(i + map_i) % 4], "team": i, "ai": level})
	var sim := Sim.new()
	var t0 := Time.get_ticks_msec()
	sim.setup(map_i, seed_v, cfg)
	var ais := []
	for i in n:
		ais.append(AI.new(sim, i, level))
	var last_print := 0.0
	var worst := 0
	while not sim.over and sim.time < minutes * 60.0:
		var s0 := Time.get_ticks_usec()
		for a in ais:
			a.update(Sim.STEP)
		sim.step()
		worst = maxi(worst, Time.get_ticks_usec() - s0)
		if sim.time - last_print >= 120.0:
			last_print = sim.time
			var line := "  %5.0fs ents=%d" % [sim.time, sim.list.size()]
			for p in sim.players:
				line += " | %s %s t%d sup %d/%d g%d a%d" % [p.name, p.race.substr(0, 4), p.tier, p.supply, p.cap, p.gold, p.aether]
			print(line)
	var ms := Time.get_ticks_msec() - t0
	var w := "nobody"
	for p in sim.players:
		if p.alive and sim.over:
			w = "%s (%s)" % [p.name, p.race]
	print("SIMTEST map %d %s: winner %s after %.1f min (%.1f s real, worst step %.1f ms)" % [map_i, Data.MAPS[map_i].name, w, sim.time / 60.0, ms / 1000.0, worst / 1000.0])
	for p in sim.players:
		print("    %s %-9s alive=%s tier=%d trained=%d killed=%d lost=%d gold=%d aether=%d built=%d techs=%d" % [p.name, p.race, p.alive, p.tier,
			p.stats.trained, p.stats.killed, p.stats.lost, p.stats.gold, p.stats.aether, p.stats.built, p.stats.techs])
