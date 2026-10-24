extends Node
## Main: the screens around a match. Start-up renders the portraits, then the title shows an
## AI-only match behind the menu. From there: Skirmish (pick a map and up to three AI or closed
## seats, races and teams), Multiplayer (host or join a room; seats are people, AI or closed),
## the Codex (the shared unit and technology template and what each race gets from it) and How
## to play. A finished match goes back to the title, or to the room after an online match.

const RACE_CHOICES := ["random", "phyrexia", "dominaria", "ravnica", "avishkar"]

var match_node: Match
var demo: Match
var ui_layer: CanvasLayer
var screen: Control
var loading: Label
var skirmish := {"map": 0, "slots": [
	{"kind": "human", "race": "random", "team": 0, "level": 1},
	{"kind": "ai", "race": "random", "team": 1, "level": 1},
	{"kind": "closed", "race": "random", "team": 2, "level": 1},
	{"kind": "closed", "race": "random", "team": 3, "level": 1},
]}
var _codex_race := "phyrexia"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if "--simtest" in args:
		add_child(preload("res://scripts/simtest.gd").new())
		return
	if "--lineup" in args:
		add_child(preload("res://scripts/lineup.gd").new())
		return
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 5
	add_child(ui_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.035, 0.05)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.name = "Black"
	ui_layer.add_child(bg)
	loading = Ui.title(Game.TITLE, 64)
	loading.set_anchors_preset(Control.PRESET_CENTER)
	loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_layer.add_child(loading)
	await get_tree().process_frame
	if DisplayServer.get_name() != "headless":
		await Portraits.generate(self)
	bg.queue_free()
	loading.queue_free()
	Net.match_start.connect(_on_net_start)
	Net.lobby_changed.connect(func():
		if screen and screen.name == "Lobby":
			show_lobby())
	Net.left.connect(func(reason: String):
		if match_node == null:
			show_multiplayer())
	if "--autotest" in args:
		add_child(preload("res://scripts/autotest.gd").new())
		return
	if Net.test_flag("host") != "" or Net.test_flag("join") != "":
		add_child(preload("res://scripts/nettest.gd").new())
		return
	show_title()
	if Net.invite_code() != "":
		show_multiplayer()


# --- matches -----------------------------------------------------------------------------

func _start_demo() -> void:
	if demo:
		return
	var players := []
	var races := RACE_CHOICES.slice(1)
	races.shuffle()
	for i in 4:
		players.append({"name": "AI", "race": races[i], "team": i, "ai": 2, "start": i, "color": i})
	demo = Match.new()
	add_child(demo)
	demo.start({"map": randi() % Data.MAPS.size(), "seed": randi() % 100000, "players": players, "me": -1, "demo": true})
	demo.view.zoom = 36.0
	demo.view.look_at_point(Vector2(demo.sim.map.size_m() * 0.5, demo.sim.map.size_m() * 0.5))
	# skip the slow opening so there is something to watch
	for i in 900:
		for a in demo.ais:
			a.update(Sim.STEP)
		demo.sim.step()


func _stop_demo() -> void:
	if demo:
		demo.queue_free()
		demo = null


## cfg as Match.start takes it. Shared by skirmish, online matches and the tests.
func start_match(cfg: Dictionary) -> Match:
	_stop_demo()
	_clear_screen()
	match_node = Match.new()
	add_child(match_node)
	match_node.start(cfg)
	match_node.finished.connect(_on_match_finished)
	if cfg.get("online", false):
		Net.attach(match_node)
	return match_node


func start_skirmish() -> void:
	var players := []
	var starts := [0, 1, 2, 3]
	starts.shuffle()
	var me := -1
	for s in skirmish.slots:
		if s.kind == "closed":
			continue
		var race: String = s.race
		if race == "random":
			race = RACE_CHOICES[1 + randi() % 4]
		if s.kind == "human":
			me = players.size()
		players.append({"name": "You" if s.kind == "human" else "AI (%s)" % Data.AI_LEVELS[int(s.level)],
			"race": race, "team": int(s.team), "ai": -1 if s.kind == "human" else int(s.level),
			"start": starts[players.size()], "color": players.size()})
	start_match({"map": int(skirmish.map), "seed": randi() % 1000000, "players": players, "me": me})


func _on_net_start(cfg: Dictionary) -> void:
	if match_node:
		match_node.queue_free()
		match_node = null
	start_match(cfg)


func _on_match_finished(_result: Dictionary) -> void:
	var was_online := match_node != null and match_node.online
	Game.play_music(Game.MENU_MUSIC)
	if match_node:
		match_node.queue_free()
		match_node = null
	if was_online and Net.active():
		Net.back_to_room()
		_start_demo()
		show_lobby()
	else:
		Net.leave()
		show_title()


# --- screens -----------------------------------------------------------------------------

func _clear_screen() -> void:
	if screen:
		screen.queue_free()
		screen = null


func _new_screen(nm: String, dim := 0.55) -> Control:
	_clear_screen()
	screen = Control.new()
	screen.name = nm
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.theme = Ui.theme()
	ui_layer.add_child(screen)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, dim)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(shade)
	return screen


## A centred panel with a title, filling most of the screen.
func _panel(title: String, width := 900.0) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(width, 0)
	center.add_child(pc)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	pc.add_child(col)
	var t := Ui.title(title, 38)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	return col


func _row(sep := 12) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", sep)
	return r


func _option(items: Array, selected: int, cb: Callable, width := 170.0) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(str(it))
	o.select(selected)
	o.custom_minimum_size = Vector2(width, 34)
	o.item_selected.connect(cb)
	return o


func _race_label(r: String) -> String:
	return "Random" if r == "random" else Data.RACES[r].name


func show_title() -> void:
	_start_demo()
	Game.play_music(Game.MENU_MUSIC)
	_new_screen("Title", 0.0)
	var side := ColorRect.new()
	side.color = Color(0.03, 0.025, 0.04, 0.72)
	side.anchor_bottom = 1.0
	side.custom_minimum_size = Vector2(400, 0)
	side.size = Vector2(400, 0)
	screen.add_child(side)
	var col := VBoxContainer.new()
	col.position = Vector2(48, 70)
	col.custom_minimum_size = Vector2(310, 0)
	col.add_theme_constant_override("separation", 12)
	screen.add_child(col)
	col.add_child(Ui.title(Game.TITLE, 58))
	col.add_child(Ui.wrap(Game.TAGLINE, 19, Game.GOLD, 310))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 22)
	col.add_child(gap)
	col.add_child(Ui.button("Skirmish", show_skirmish, 20))
	col.add_child(Ui.button("Multiplayer", show_multiplayer, 20))
	col.add_child(Ui.button("Codex", show_codex, 20))
	col.add_child(Ui.button("How to play", show_help, 20))
	var qb := Ui.button("Graphics: " + Game.QUALITY_NAMES[Game.quality], func(): pass, 16)
	qb.pressed.connect(func():
		Game.cycle_quality()
		qb.text = "Graphics: " + Game.QUALITY_NAMES[Game.quality])
	col.add_child(qb)
	var sb := Ui.button("Sound: " + ("off" if Game.muted else "on"), func(): pass, 16)
	sb.pressed.connect(func():
		Game.toggle_mute()
		sb.text = "Sound: " + ("off" if Game.muted else "on"))
	col.add_child(sb)
	var mb := Ui.button("Music: " + ("on" if Game.music_on else "off"), func(): pass, 16)
	mb.pressed.connect(func():
		Game.toggle_music()
		mb.text = "Music: " + ("on" if Game.music_on else "off"))
	col.add_child(mb)
	var vb := Ui.button("Voices: " + ("on" if Game.voices_on else "off"), func(): pass, 16)
	vb.pressed.connect(func():
		Game.toggle_voices()
		vb.text = "Voices: " + ("on" if Game.voices_on else "off"))
	col.add_child(vb)
	var foot := Ui.wrap("Phyrexia, Dominaria, Ravnica and Avishkar fight over four planes. Build a base, gather gold and aether, raise an army and raze your rivals.", 15, Color(0.75, 0.72, 0.66), 310)
	col.add_child(foot)


func show_skirmish() -> void:
	_new_screen("Skirmish")
	var col := _panel("Skirmish", 860)
	col.add_child(Ui.label("Map", 18, Game.GOLD, Game.font_bold))
	var maps := _row(8)
	col.add_child(maps)
	var desc := Ui.wrap("", 16, Color(0.82, 0.79, 0.72), 820)
	for i in Data.MAPS.size():
		var b := Ui.button(Data.MAPS[i].name, func():
			skirmish.map = i
			show_skirmish(), 15)
		b.toggle_mode = true
		b.button_pressed = i == skirmish.map
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		maps.add_child(b)
	var mp: Dictionary = Data.MAPS[skirmish.map]
	desc.text = "%s, %s. %s" % [mp.name, mp.plane, mp.desc]
	col.add_child(desc)
	col.add_child(Ui.label("Players", 18, Game.GOLD, Game.font_bold))
	var kinds := ["AI Easy", "AI Normal", "AI Hard", "Closed"]
	for i in 4:
		var s: Dictionary = skirmish.slots[i]
		var r := _row()
		col.add_child(r)
		var sw := ColorRect.new()
		sw.color = Data.TEAM_COLORS[i]
		sw.custom_minimum_size = Vector2(10, 34)
		r.add_child(sw)
		if s.kind == "human":
			var l := Ui.label("You", 18, Game.PALE, Game.font_bold)
			l.custom_minimum_size = Vector2(170, 34)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			r.add_child(l)
		else:
			var cur := 3 if s.kind == "closed" else int(s.level)
			r.add_child(_option(kinds, cur, func(k: int):
				s.kind = "closed" if k == 3 else "ai"
				s.level = mini(k, 2)
				show_skirmish()))
		if s.kind != "closed":
			r.add_child(_option(RACE_CHOICES.map(_race_label), RACE_CHOICES.find(s.race), func(k: int):
				s.race = RACE_CHOICES[k]
				show_skirmish()))
			r.add_child(_option(["Team 1", "Team 2", "Team 3", "Team 4"], int(s.team), func(k: int):
				s.team = k
				show_skirmish(), 120))
			if s.race != "random":
				r.add_child(Ui.wrap(Data.RACES[s.race].bonus_text, 14, Color(0.78, 0.75, 0.68), 300))
	var teams := {}
	for s in skirmish.slots:
		if s.kind != "closed":
			teams[int(s.team)] = true
	var ok := teams.size() >= 2
	col.add_child(Ui.wrap("Players on the same team are allies. Last team standing wins." if ok else "Put at least two players on different teams.", 15, Color(0.78, 0.75, 0.68) if ok else Game.BAD, 820))
	var btns := _row()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btns)
	btns.add_child(Ui.button("Back", show_title, 18))
	var go := Ui.button("Start", start_skirmish, 18)
	go.disabled = not ok
	go.name = "Start"
	btns.add_child(go)


func show_multiplayer() -> void:
	_start_demo()
	if Net.active() and not Net.slots.is_empty():
		show_lobby()
		return
	_new_screen("Multiplayer")
	var col := _panel("Multiplayer", 620)
	col.add_child(Ui.wrap("Play with friends. One of you opens a room and shares its code; the others join with it. Empty seats can be AI players, so you can fight together against the AI, against each other, or both.", 16, Color(0.82, 0.79, 0.72), 580))
	var r := _row()
	col.add_child(r)
	r.add_child(Ui.label("Your name", 17))
	var name_edit := LineEdit.new()
	name_edit.text = Net.my_name
	name_edit.max_length = 16
	name_edit.custom_minimum_size = Vector2(240, 36)
	name_edit.text_changed.connect(func(t: String): Net.set_player_name(t))
	r.add_child(name_edit)
	col.add_child(Ui.button("Open a room", func(): Net.host(); show_lobby(), 18))
	var r2 := _row()
	col.add_child(r2)
	var code_edit := LineEdit.new()
	code_edit.placeholder_text = "Room code" if OS.has_feature("web") else "Host's address"
	code_edit.text = Net.invite_code()
	code_edit.custom_minimum_size = Vector2(240, 36)
	r2.add_child(code_edit)
	r2.add_child(Ui.button("Join", func(): Net.join(code_edit.text); show_lobby(), 18))
	var st := Ui.wrap(Net.status, 15, Game.GOLD, 580)
	col.add_child(st)
	Net.status_changed.connect(func(): if is_instance_valid(st): st.text = Net.status)
	col.add_child(Ui.button("Back", func(): Net.leave(); show_title(), 16))


func show_lobby() -> void:
	if not Net.active():
		show_multiplayer()
		return
	_new_screen("Lobby")
	var col := _panel("Room " + Net.code if Net.code != "" else "Room", 900)
	var top := _row()
	col.add_child(top)
	var st := Ui.wrap(Net.status, 15, Game.GOLD, 600)
	top.add_child(st)
	Net.status_changed.connect(func(): if is_instance_valid(st): st.text = Net.status)
	if Net.code != "":
		top.add_child(Ui.button("Copy code", Net.copy_code, 15))
	if Net.slots.is_empty():
		col.add_child(Ui.label("Joining...", 18))
		col.add_child(Ui.button("Leave", func(): Net.leave(); show_multiplayer(), 16))
		return
	var host := Net.is_host()
	var mr := _row()
	col.add_child(mr)
	mr.add_child(Ui.label("Map", 18, Game.GOLD, Game.font_bold))
	if host:
		mr.add_child(_option(Data.MAPS.map(func(m): return m.name), Net.map, func(k: int): Net.set_map(k), 260))
	else:
		mr.add_child(Ui.label(Data.MAPS[Net.map].name, 18))
	col.add_child(Ui.wrap(Data.MAPS[Net.map].desc, 15, Color(0.82, 0.79, 0.72), 860))
	var kinds := ["Open", "AI Easy", "AI Normal", "AI Hard", "Closed"]
	for i in Net.slots.size():
		var s: Dictionary = Net.slots[i]
		var r := _row()
		col.add_child(r)
		var sw := ColorRect.new()
		sw.color = Data.TEAM_COLORS[i]
		sw.custom_minimum_size = Vector2(10, 34)
		r.add_child(sw)
		var mine: bool = s.kind == "human" and int(s.peer) == Net.my_id()
		if s.kind == "human":
			var l := Ui.label(str(s.name) + (" (you)" if mine else ""), 18, Game.PALE, Game.font_bold)
			l.custom_minimum_size = Vector2(190, 34)
			l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			r.add_child(l)
		elif host:
			var cur := 0 if s.kind == "open" else (4 if s.kind == "closed" else 1 + int(s.level))
			r.add_child(_option(kinds, cur, func(k: int):
				if k == 0:
					Net.set_slot(i, "open")
				elif k == 4:
					Net.set_slot(i, "closed")
				else:
					Net.set_slot(i, "ai", k - 1), 190))
		else:
			var txt: String = {"open": "Open", "closed": "Closed"}.get(s.kind, "AI " + Data.AI_LEVELS[int(s.level)])
			var l := Ui.label(txt, 18, Color(0.8, 0.77, 0.7))
			l.custom_minimum_size = Vector2(190, 34)
			r.add_child(l)
		if s.kind == "human" or s.kind == "ai":
			var can: bool = mine or (host and s.kind == "ai")
			if can:
				r.add_child(_option(RACE_CHOICES.map(_race_label), RACE_CHOICES.find(s.race), func(k: int): Net.pick(i, RACE_CHOICES[k], int(s.team))))
				r.add_child(_option(["Team 1", "Team 2", "Team 3", "Team 4"], int(s.team), func(k: int): Net.pick(i, str(s.race), k), 120))
			else:
				var l := Ui.label("%s, team %d" % [_race_label(s.race), int(s.team) + 1], 17)
				r.add_child(l)
	var btns := _row()
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btns)
	btns.add_child(Ui.button("Leave", func(): Net.leave(); show_multiplayer(), 18))
	if host:
		var go := Ui.button("Start", Net.start_match, 18)
		go.disabled = not Net.can_start()
		btns.add_child(go)
		if not Net.can_start():
			col.add_child(Ui.wrap("Put at least two players on different teams.", 15, Game.BAD, 860))
	else:
		col.add_child(Ui.wrap("The host picks the map and starts the match.", 15, Color(0.78, 0.75, 0.68), 860))


func show_help() -> void:
	_new_screen("Help")
	var col := _panel("How to play", 820)
	var txt := """[b]Goal.[/b] Destroy every building and worker of the other teams. Allies share victory.
[b]Economy.[/b] Workers gather [color=#f2c76b]gold[/color] from veins and [color=#73d9ff]aether[/color] from crystals and carry it to your hall or a depot. Houses raise your supply limit (at most 120).
[b]Building.[/b] Select workers, press Build (Q) and pick a building, then click the ground. More workers build faster. Right click a damaged building with a worker to repair it.
[b]Army.[/b] Barracks, stables, workshops and the sanctum train troops. Every race uses the same template of roles, but names, looks, numbers and what is available differ. Infantry beats spearmen, spearmen stop cavalry and champions, archers shoot infantry and flyers, cavalry runs down archers and siege engines, and siege engines raze buildings.
[b]Ages and research.[/b] Advance your hall to the second and third age to unlock new buildings, troops and upgrades. Each race lacks a few upgrades and has one unique technology. See the Codex.
[b]Mouse.[/b] Left click selects, drag selects many, double click selects all of one kind on screen. Right click moves, attacks, gathers or sets a rally point.
[b]Keys.[/b] Command card: Q W E R / A S D F / Z X C V. A then click: attack-move. Ctrl+1-9 sets a group, 1-9 selects it. H: town hall. Period: idle worker. Space: last attack. Arrows or the screen edge pan, the wheel zooms. Esc: menu. L: graphics. M: sound. N: music."""
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(780, 0)
	rt.add_theme_font_size_override("normal_font_size", 17)
	rt.add_theme_font_size_override("bold_font_size", 17)
	rt.add_theme_font_override("bold_font", Game.font_bold)
	rt.text = txt
	col.add_child(rt)
	col.add_child(Ui.button("Back", show_title, 18))


## The shared template: one row per role or technology, one column per race.
func show_codex(tab := "units") -> void:
	_new_screen("Codex", 0.7)
	var col := _panel("Codex", 1180)
	var tabs := _row(8)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(tabs)
	for t in [["units", "Troops"], ["buildings", "Buildings"], ["techs", "Technologies"], ["races", "Races"]]:
		var b := Ui.button(t[1], func(): show_codex(t[0]), 16)
		b.toggle_mode = true
		b.button_pressed = tab == t[0]
		tabs.add_child(b)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(1140, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	if tab == "races":
		grid.columns = 2
		for r in Data.RACE_ORDER:
			var rd: Dictionary = Data.RACES[r]
			var box := VBoxContainer.new()
			box.custom_minimum_size = Vector2(555, 0)
			box.add_child(Ui.label(rd.name, 24, rd.colors.trim.lightened(0.45), Game.font_bold))
			box.add_child(Ui.label(rd.motto, 16, Game.GOLD))
			box.add_child(Ui.wrap(rd.blurb, 15, Game.PALE, 540))
			box.add_child(Ui.wrap("Bonus: " + rd.bonus_text, 15, Color(0.7, 0.9, 0.7), 540))
			box.add_child(Ui.wrap("Unique technology: %s. %s" % [rd.techs.get("unique", "Unique"), rd.unique_text], 15, Color(0.6, 0.85, 1.0), 540))
			var miss := []
			for k in rd.missing:
				if Data.UNITS.has(k):
					miss.append(Data.UNITS[k].role)
				elif Data.TECHS.has(k):
					miss.append(Data.TECH_TEMPLATE[k])
			box.add_child(Ui.wrap("Lacks: " + ", ".join(miss) + ".", 15, Color(0.95, 0.6, 0.55), 540))
			box.add_child(Ui.wrap("Ages: " + ", ".join(rd.ages) + ".", 14, Color(0.75, 0.72, 0.66), 540))
			var faces := HBoxContainer.new()
			for k in Data.UNIT_ORDER:
				if Data.has_unit(r, k) and Portraits.get_tex(r, k):
					var tr := TextureRect.new()
					tr.texture = Portraits.get_tex(r, k)
					tr.custom_minimum_size = Vector2(58, 58)
					tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					tr.tooltip_text = Data.unit_name(r, k)
					faces.add_child(tr)
			box.add_child(faces)
			grid.add_child(box)
	else:
		grid.add_child(Ui.label("Template", 17, Game.GOLD, Game.font_bold))
		for r in Data.RACE_ORDER:
			grid.add_child(Ui.label(Data.RACES[r].name, 17, Data.RACES[r].colors.trim.lightened(0.45), Game.font_bold))
		var keys: Array = Data.UNIT_ORDER if tab == "units" else (Data.BUILD_ORDER if tab == "buildings" else Data.TECH_ORDER)
		for k in keys:
			var base: Dictionary = Data.UNITS[k] if tab == "units" else (Data.BUILDINGS[k] if tab == "buildings" else Data.TECHS[k])
			var head := VBoxContainer.new()
			head.custom_minimum_size = Vector2(250, 0)
			head.add_child(Ui.label(Data.TECH_TEMPLATE[k] if tab == "techs" else str(base.role), 16, Game.PALE, Game.font_bold))
			head.add_child(Ui.wrap(str(base.get("desc", "")), 13, Color(0.72, 0.7, 0.64), 245))
			grid.add_child(head)
			for r in Data.RACE_ORDER:
				var cell := HBoxContainer.new()
				cell.custom_minimum_size = Vector2(210, 0)
				var has: bool = Data.has_unit(r, k) if tab == "units" else (Data.has_building(r, k) if tab == "buildings" else Data.has_tech(r, k))
				if tab != "techs" and has:
					var tr := TextureRect.new()
					tr.texture = Portraits.get_tex(r, k)
					tr.custom_minimum_size = Vector2(52, 52)
					tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
					tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
					cell.add_child(tr)
				var nm := ""
				if has:
					nm = Data.unit_name(r, k) if tab == "units" else (Data.building_name(r, k) if tab == "buildings" else Data.tech_name(r, k))
				var l := Ui.wrap(nm if has else "not available", 14, Game.PALE if has else Color(0.85, 0.4, 0.36), 150)
				l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				cell.add_child(l)
				grid.add_child(cell)
	col.add_child(Ui.button("Back", show_title, 18))
