class_name Match
extends Node
## One running match: owns the Sim, the View, the HUD and the AI players, steps the simulation
## (on the host or in a local game) and turns the mouse and keyboard into commands. On a guest's
## computer the Sim is a mirror filled by Net from the host's snapshots, and commands go to the
## host instead.
##
## Controls: left click / drag selects, right click orders (move, attack, gather, build,
## rally), the command card keys (Q W E R / A S D F / Z X C V), Ctrl+number groups, H the town
## hall, period an idle worker, space the last alert, arrows / screen edge / middle drag pan,
## wheel zooms.

signal finished(result: Dictionary)

var sim: Sim
var view: View
var hud: Hud
var ais: Array = []
var me := -1
var cfg := {}
var guest := false
var online := false
var paused := false
var speed := 1.0
var acc := 0.0
var snap_t := 0.0                     # guest: time since the last snapshot
var selection: Array = []
var groups := {}
var mode := ""                        # "", "build", "amove"
var build_role := ""
var last_alert := Vector2(-1, -1)
var result := {}
var demo := false                     # title screen backdrop: AI only, no HUD
var _drag := false
var _drag_from := Vector2.ZERO
var _pan_drag := false
var _last_click := 0
var _last_group := {"n": -1, "t": 0}
var _over_t := -1.0
var _centred := false
var net_speed := 1.0                   # online tests run the host faster


## cfg: {"map": int, "seed": int, "players": [...], "me": int, "guest": bool, "online": bool, "demo": bool}
func start(c: Dictionary) -> void:
	cfg = c
	me = int(c.get("me", 0))
	guest = bool(c.get("guest", false))
	online = bool(c.get("online", false))
	demo = bool(c.get("demo", false))
	sim = Sim.new()
	sim.mirror = guest
	sim.setup(int(c.map), int(c.seed), c.players)
	view = View.new()
	add_child(view)
	view.setup(sim, me)
	if not guest:
		for i in sim.players.size():
			if sim.players[i].ai >= 0:
				ais.append(AI.new(sim, i, sim.players[i].ai))
		sim.event.connect(_on_event)
	if not demo:
		hud = Hud.new()
		add_child(hud)
		hud.setup(self)
	Game.quality_changed.connect(view.apply_quality)


func issue(cmd: Dictionary) -> void:
	if me < 0:
		return
	if guest:
		Net.send_command(cmd)
	else:
		sim.command(me, cmd)


## The host turns a player who left into an AI so the match goes on.
func peer_left(peer: int) -> void:
	for i in sim.players.size():
		var p := sim.players[i]
		if p.peer == peer and p.ai < 0 and p.alive:
			p.ai = 1
			p.name += " (AI)"
			ais.append(AI.new(sim, i, 1))
			_on_event({"t": "notice", "p": -1, "text": "%s left; the AI takes over." % p.name})


func _process(delta: float) -> void:
	if sim == null:
		return
	if not guest:
		if not paused or online:
			acc += delta * (speed if not online else net_speed)
			var steps := 0
			while acc >= Sim.STEP and steps < 5:
				for a in ais:
					a.update(Sim.STEP)
				sim.step()
				if online:
					Net.host_tick(self)
				acc -= Sim.STEP
				steps += 1
			if steps >= 5:
				acc = 0.0
		view.alpha = clampf(acc / Sim.STEP, 0.0, 1.0)
	else:
		snap_t += delta
		view.alpha = clampf(snap_t / Sim.STEP, 0.0, 1.0)
		if not _centred and me >= 0:
			for e in sim.list:
				if e.owner == me and e.role == "hall":
					view.look_at_point(e.pos)
					_centred = true
	if demo:
		view.cam_target += Vector2(cos(Time.get_ticks_msec() * 0.00005), sin(Time.get_ticks_msec() * 0.00007)) * delta * 2.0
		return
	# drop the dead from the selection
	var keep := []
	for id in selection:
		var e: Ent = sim.ents.get(id)
		if e and e.alive and (e.owner == me or view.can_see(e)):
			keep.append(id)
	if keep.size() != selection.size():
		_set_selection(keep)
	_camera_keys(delta)
	var mp := get_viewport().get_mouse_position()
	var over_ui := hud.is_over_ui(mp)
	if mode == "build" and not over_ui:
		var c := _build_cell(mp)
		view.show_ghost(sim.players[me].race, build_role, c, sim.can_place(build_role, c))
	else:
		view.hide_ghost()
	var h := view.ent_at(mp) if not over_ui and not _drag else null
	view.hover_id = h.id if h else 0
	if sim.over and _over_t < 0.0:
		_over_t = 0.0
	if _over_t >= 0.0:
		_over_t += delta
		if _over_t > 1.5 and result.is_empty():
			_finish()


func _camera_keys(delta: float) -> void:
	var v := Vector2.ZERO
	if Input.is_action_pressed("pan_left"):
		v.x -= 1
	if Input.is_action_pressed("pan_right"):
		v.x += 1
	if Input.is_action_pressed("pan_up"):
		v.y -= 1
	if Input.is_action_pressed("pan_down"):
		v.y += 1
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport().get_visible_rect().size
	if DisplayServer.window_is_focused() and not Game.testing and not _pan_drag and Rect2(Vector2.ZERO, vs).has_point(mp):
		var m := 3.0
		if mp.x <= m:
			v.x -= 1
		elif mp.x >= vs.x - m:
			v.x += 1
		if mp.y <= m:
			v.y -= 1
		elif mp.y >= vs.y - m:
			v.y += 1
	if v != Vector2.ZERO:
		view.pan(v.normalized() * delta * 60.0)


func _build_cell(mp: Vector2) -> Vector2i:
	var g := view.screen_to_ground(mp)
	var s: int = Data.BUILDINGS[build_role].size
	return MapData.cell_of(g - Vector2(s, s) * 0.5 * Data.CELL + Vector2.ONE * Data.CELL * 0.5)


func _unhandled_input(ev: InputEvent) -> void:
	if sim == null or demo:
		return
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			view.zoom_by(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			view.zoom_by(1.1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if mode == "build":
					_place_building(mb.position, mb.shift_pressed)
					return
				if mode == "amove":
					_order_at(mb.position, true)
					if not mb.shift_pressed:
						mode = ""
					return
				_drag = true
				_drag_from = mb.position
			elif _drag:
				_drag = false
				if mb.position.distance_to(_drag_from) > 8.0:
					_box_select(Rect2(_drag_from, mb.position - _drag_from).abs(), mb.shift_pressed)
				else:
					_click_select(mb.position, mb.shift_pressed, mb.double_click or Time.get_ticks_msec() - _last_click < 300)
					_last_click = Time.get_ticks_msec()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			if mode != "":
				mode = ""
				return
			_order_at(mb.position, false)
	elif ev is InputEventMouseMotion and _pan_drag:
		view.pan(-(ev as InputEventMouseMotion).relative * 0.05)
	elif ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev as InputEventKey)


func _key(k: InputEventKey) -> void:
	var code := k.physical_keycode
	if code == KEY_ESCAPE:
		if mode != "":
			mode = ""
		elif hud.submenu != "":
			hud.submenu = ""
			hud.refresh()
		else:
			hud.toggle_menu()
		return
	if code == KEY_F10:
		hud.toggle_menu()
		return
	if code == KEY_L:
		Game.cycle_quality()
		hud.notice("Graphics: " + Game.QUALITY_NAMES[Game.quality])
		return
	if code == KEY_M and not k.ctrl_pressed:
		Game.toggle_mute()
		hud.notice("Sound off" if Game.muted else "Sound on")
		return
	if code >= KEY_0 and code <= KEY_9:
		var n := code - KEY_0
		if k.ctrl_pressed:
			groups[n] = selection.duplicate()
			hud.notice("Group %d set" % n)
		elif groups.has(n):
			var ids: Array = groups[n].filter(func(id): return sim.ents.has(id) and sim.ents[id].alive)
			_set_selection(ids)
			if _last_group.n == n and Time.get_ticks_msec() - _last_group.t < 400 and not ids.is_empty():
				view.look_at_point(sim.ents[ids[0]].pos)
			_last_group = {"n": n, "t": Time.get_ticks_msec()}
		return
	if code == KEY_H:
		var halls := []
		for e in sim.list:
			if e.alive and e.owner == me and e.role == "hall":
				halls.append(e.id)
		if not halls.is_empty():
			_set_selection([halls[0]])
			view.look_at_point(sim.ents[halls[0]].pos)
		return
	if code == KEY_PERIOD or code == KEY_HOME:
		select_idle_worker()
		return
	if code == KEY_SPACE:
		if last_alert.x >= 0:
			view.look_at_point(last_alert)
		return
	if (code == KEY_EQUAL or code == KEY_KP_ADD) and not online:
		speed = minf(speed * 1.5, 3.0)
		hud.notice("Speed x%.1f" % speed)
		return
	if (code == KEY_MINUS or code == KEY_KP_SUBTRACT) and not online:
		speed = maxf(speed / 1.5, 0.5)
		hud.notice("Speed x%.1f" % speed)
		return
	hud.hotkey(code)


func select_idle_worker() -> void:
	var idle := []
	for e in sim.list:
		if e.alive and e.owner == me and e.role == "worker" and e.order == Ent.IDLE:
			idle.append(e)
	if idle.is_empty():
		hud.notice("No idle workers")
		return
	# cycle through them
	var pick: Ent = idle[0]
	if selection.size() == 1:
		for i in idle.size():
			if idle[i].id == selection[0]:
				pick = idle[(i + 1) % idle.size()]
	_set_selection([pick.id])
	view.look_at_point(pick.pos)


# --- selection -----------------------------------------------------------------------------

func _set_selection(ids: Array) -> void:
	selection = ids
	view.selected.clear()
	for id in ids:
		view.selected[id] = true
	if mode == "build" and not _has_worker():
		mode = ""
	hud.submenu = ""
	hud.refresh()


func _has_worker() -> bool:
	for id in selection:
		var e: Ent = sim.ents.get(id)
		if e and e.owner == me and e.role == "worker":
			return true
	return false


func _click_select(sp: Vector2, add: bool, double: bool) -> void:
	var e := view.ent_at(sp)
	if e == null:
		if not add:
			_set_selection([])
		return
	if double and e.owner == me:
		var ids := []
		for o in view.ents_in_rect(get_viewport().get_visible_rect()):
			if o.owner == me and o.role == e.role:
				ids.append(o.id)
		_set_selection(ids)
		return
	if add and e.owner == me:
		var ids := selection.duplicate()
		if e.id in ids:
			ids.erase(e.id)
		elif _all_mine(ids):
			ids.append(e.id)
		_set_selection(ids)
		return
	_set_selection([e.id])
	Game.play("click", -10.0)


func _all_mine(ids: Array) -> bool:
	for id in ids:
		var e: Ent = sim.ents.get(id)
		if e == null or e.owner != me:
			return false
	return true


func _box_select(r: Rect2, add: bool) -> void:
	var units := []
	var blds := []
	for e in view.ents_in_rect(r):
		if e.owner != me:
			continue
		if e.is_unit():
			units.append(e.id)
		elif e.is_building():
			blds.append(e.id)
	var ids := units if not units.is_empty() else blds
	if add:
		var merged := selection.duplicate()
		for id in ids:
			if id not in merged:
				merged.append(id)
		ids = merged
	if not ids.is_empty() or not add:
		_set_selection(ids)
	if not units.is_empty():
		Game.play("ack", -10.0)


func selected_ents() -> Array:
	var out := []
	for id in selection:
		var e: Ent = sim.ents.get(id)
		if e and e.alive:
			out.append(e)
	return out


func drag_rect() -> Rect2:
	if not _drag:
		return Rect2()
	return Rect2(_drag_from, get_viewport().get_mouse_position() - _drag_from).abs()


# --- orders --------------------------------------------------------------------------------

func _order_at(sp: Vector2, attack: bool) -> void:
	var mine := selected_ents().filter(func(e): return e.owner == me)
	if mine.is_empty():
		return
	var units := mine.filter(func(e): return e.is_unit())
	var blds := mine.filter(func(e): return e.is_building())
	var tgt := view.ent_at(sp)
	var g := view.screen_to_ground(sp)
	if units.is_empty():
		var ids := blds.map(func(e): return e.id)
		var at := tgt.pos if tgt and tgt.is_resource() else g
		issue({"t": "rally", "ids": ids, "x": at.x, "y": at.y})
		view.mark(at)
		return
	var ids := units.map(func(e): return e.id)
	if tgt and tgt.alive and not (attack and tgt.owner == me):
		if attack and not sim.enemies(me, tgt.owner):
			issue({"t": "amove", "ids": ids, "x": tgt.pos.x, "y": tgt.pos.y})
		else:
			issue({"t": "target", "ids": ids, "id": tgt.id})
		view.mark(tgt.pos, sim.enemies(me, tgt.owner))
		Game.play("ack", -8.0)
		return
	issue({"t": "amove" if attack else "move", "ids": ids, "x": g.x, "y": g.y})
	view.mark(g, attack)
	Game.play("ack", -8.0)


func _place_building(sp: Vector2, keep: bool) -> void:
	var c := _build_cell(sp)
	if not sim.can_place(build_role, c):
		hud.notice("Cannot build there.")
		Game.play("error", -8.0)
		return
	var why := sim.why_not(me, "building", build_role)
	if why != "":
		hud.notice(why)
		Game.play("error", -8.0)
		mode = ""
		return
	var workers := selected_ents().filter(func(e): return e.owner == me and e.role == "worker").map(func(e): return e.id)
	issue({"t": "build", "ids": workers, "b": build_role, "cx": c.x, "cy": c.y})
	Game.play("build", -10.0)
	if not keep:
		mode = ""


func begin_build(role: String) -> void:
	var why := sim.why_not(me, "building", role)
	if why != "":
		hud.notice(why)
		Game.play("error", -8.0)
		return
	build_role = role
	mode = "build"


# --- events --------------------------------------------------------------------------------

## Sim events on the host (also sent on to the guest they concern).
func _on_event(e: Dictionary) -> void:
	if online:
		Net.forward_event(self, e)
	local_event(e)


## An event for the local player (from the local Sim, or from the host over the network).
func local_event(e: Dictionary) -> void:
	if hud == null:
		return
	var p := int(e.get("p", -2))
	match str(e.t):
		"notice":
			if p == me or p == -1:
				hud.notice(str(e.text))
				if p == me:
					Game.play("error", -12.0)
		"alert":
			if p == me:
				last_alert = Vector2(e.x, e.y)
				hud.alert(last_alert)
				Game.play("horn", -8.0)
		"trained":
			if p == me:
				Game.play("ready", -12.0)
		"built":
			if p == me:
				hud.notice("%s finished." % Data.building_name(sim.players[me].race, str(e.role)))
				Game.play("chime", -8.0)
		"researched":
			if p == me:
				var k := str(e.k)
				hud.notice("%s researched." % Data.tech_name(sim.players[me].race, k))
				Game.play("upgrade", -6.0)
				hud.refresh()
		"defeated":
			if p == me:
				hud.notice("You have been defeated.")
				Game.play("lose", -4.0)
			elif p >= 0:
				hud.notice("%s has been defeated." % sim.players[p].name)
		"over":
			_over_t = 0.0


func _finish() -> void:
	var won: bool = me >= 0 and sim.players[me].alive and sim.over
	result = {"won": won, "time": sim.time, "players": sim.players.duplicate(true), "team": sim.winner_team}
	Game.play("win" if won else "lose", -4.0)
	if hud:
		hud.show_result(result)


func leave() -> void:
	finished.emit(result)
