extends Node
## Automated visual test (`tools/smoke_test.sh`): walks the menus, the codex, a skirmish on every
## map (selecting, building, training, a fast-forwarded battle), the pause menu and the results,
## saving a screenshot of each step. Prints `AUTOTEST ...` lines and ends with `AUTOTEST done`.

var dir := "/tmp/pw-shots"
var main: Node


func _ready() -> void:
	main = get_parent()
	Game.testing = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(dir)
	_run()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name + ".png"))
	print("AUTOTEST shot ", name)


## Runs the match's simulation (and its AI players) forward without drawing.
func _advance(m: Match, seconds: float) -> void:
	for i in int(seconds / Sim.STEP):
		for a in m.ais:
			a.update(Sim.STEP)
		m.sim.step()
		if m.sim.over:
			break


func _run() -> void:
	main.show_title()
	await _wait(30)
	await _shot("01_title")
	print("AUTOTEST music ", Game.music_now())
	main.show_skirmish()
	await _wait(5)
	await _shot("02_skirmish")
	for t in ["units", "buildings", "techs", "races"]:
		main.show_codex(t)
		await _wait(5)
		await _shot("03_codex_" + t)
	main.show_help()
	await _wait(5)
	await _shot("04_help")
	main.show_multiplayer()
	await _wait(5)
	await _shot("05_multiplayer")

	for map_i in Data.MAPS.size():
		var race: String = Data.RACE_ORDER[map_i]
		var players := [
			{"name": "You", "race": race, "team": 0, "ai": -1, "start": 0, "color": 0},
			{"name": "AI (Easy)", "race": Data.RACE_ORDER[(map_i + 1) % 4], "team": 1, "ai": 0, "start": 3, "color": 1},
		]
		var m: Match = main.start_match({"map": map_i, "seed": 100 + map_i, "players": players, "me": 0})
		await _wait(10)
		print("AUTOTEST map ", map_i, " ", Data.MAPS[map_i].name, " as ", race, ", music ", Game.music_now())
		# select the workers and open the build menu
		var workers := []
		var hall: Ent
		for e in m.sim.list:
			if e.owner == 0 and e.role == "worker":
				workers.append(e.id)
			if e.owner == 0 and e.role == "hall":
				hall = e
		m._set_selection(workers)
		m._say_selected("select")
		print("AUTOTEST voice ", Game.voice_now())
		m.hud.submenu = "build"
		m.hud.refresh()
		await _wait(5)
		await _shot("1%d_map_start" % map_i)
		# a house and a barracks, two workers in training
		m.hud.submenu = ""
		var spot := _spot(m, "house", hall)
		m.issue({"t": "build", "ids": workers.slice(0, 2), "b": "house", "cx": spot.x, "cy": spot.y})
		spot = _spot(m, "barracks", hall)
		m.issue({"t": "build", "ids": workers.slice(2, 4), "b": "barracks", "cx": spot.x, "cy": spot.y})
		m.issue({"t": "train", "id": hall.id, "u": "worker", "n": 2})
		for id in workers.slice(4):
			m.issue({"t": "target", "ids": [id], "id": _nearest_res(m, hall.pos)})
		_advance(m, 20.0)
		m._set_selection([hall.id])
		await _wait(5)
		await _shot("1%d_map_building" % map_i)
		# let the AI play my side too and jump ahead to the fighting
		m.ais.append(AI.new(m.sim, 0, 2))
		_advance(m, 60.0 * (9 + map_i))
		var fight := _find_fight(m)
		m.view.look_at_point(fight)
		var army := []
		for e in m.sim.list:
			if e.owner == 0 and e.is_unit() and e.role != "worker" and e.pos.distance_to(fight) < 25.0:
				army.append(e.id)
		m._set_selection(army)
		await _wait(20)
		await _shot("1%d_map_battle" % map_i)
		print("AUTOTEST battle at %.0f min, %d units of mine selected" % [m.sim.time / 60.0, army.size()])
		var t0 := Time.get_ticks_usec()
		await _wait(30)
		print("AUTOTEST frame %.1f ms over the battle, %d units on the map" % [(Time.get_ticks_usec() - t0) / 30000.0, m.sim.list.size()])
		# close up on the fighting: walking, striking and falling troops
		m.view.look_at_point(_find_fight(m))
		m.view.zoom_by(0.42)
		await _wait(8)
		await _shot("1%d_battle_close" % map_i)
		m.view.zoom_by(1.0 / 0.42)
		if map_i == 0:
			m.view.zoom_by(0.5)
			await _wait(10)
			await _shot("1%d_map_close" % map_i)
			m.hud.toggle_menu()
			await _wait(5)
			await _shot("06_pause")
			m.hud.toggle_menu()
		if map_i == Data.MAPS.size() - 1:
			_advance(m, 60.0 * 30)
			await _wait(80)
			await _shot("07_result")
			print("AUTOTEST result over=", m.sim.over, " time=%.1f min" % (m.sim.time / 60.0))
		m.leave()
		await _wait(5)
	print("AUTOTEST done")
	get_tree().quit()


func _spot(m: Match, role: String, hall: Ent) -> Vector2i:
	var best := Vector2i.ZERO
	var best_d := INF
	for y in range(-12, 13):
		for x in range(-12, 13):
			var c := hall.cell + Vector2i(x, y)
			if m.sim.can_place(role, c):
				var d := Vector2(x - 6, y - 2).length()
				if d < best_d:
					best_d = d
					best = c
	return best


func _nearest_res(m: Match, p: Vector2) -> int:
	var best := 0
	var bd := INF
	for e in m.sim.list:
		if e.is_resource() and e.role == "gold" and e.pos.distance_to(p) < bd:
			bd = e.pos.distance_to(p)
			best = e.id
	return best


## Where most of the fighting is (units that attacked recently), else my hall.
func _find_fight(m: Match) -> Vector2:
	var sum := Vector2.ZERO
	var n := 0
	for e in m.sim.list:
		if e.is_unit() and e.anim == Ent.A_ATTACK and e.role != "worker":
			sum += e.pos
			n += 1
	if n > 0:
		return sum / n
	for e in m.sim.list:
		if e.owner == 0 and e.role == "hall":
			return e.pos
	return Vector2(80, 80)
