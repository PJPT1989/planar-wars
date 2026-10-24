class_name Hud
extends CanvasLayer
## The in-match interface: the top bar (gold, aether, supply, age, clock), the bottom panel
## (minimap, what is selected, the command card with its hotkeys), health bars and the
## selection box over the map, short notices, the pause menu and the results.

const KEYS := [KEY_Q, KEY_W, KEY_E, KEY_R, KEY_A, KEY_S, KEY_D, KEY_F, KEY_Z, KEY_X, KEY_C, KEY_V]
const KEY_NAMES := ["Q", "W", "E", "R", "A", "S", "D", "F", "Z", "X", "C", "V"]
const PANEL_H := 178.0
const ORDER_NAMES := ["Idle", "Moving", "Attack-moving", "Attacking", "Gathering", "Returning", "Building", "Following"]

var m: Match
var submenu := ""
var root: Control
var top: PanelContainer
var bottom: PanelContainer
var minimap: Minimap
var info: InfoPanel
var card: GridContainer
var overlay: Overlay
var tip: PanelContainer
var tip_label: RichTextLabel
var notices: VBoxContainer
var menu: PanelContainer
var result_panel: PanelContainer
var _gold: Label
var _aether: Label
var _supply: Label
var _age: Label
var _clock: Label
var _buttons: Array[CardButton] = []
var _refresh_t := 0.0


func setup(match_node: Match) -> void:
	m = match_node
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = Ui.theme()
	add_child(root)
	overlay = Overlay.new()
	overlay.hud = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	_build_top()
	_build_bottom()
	notices = VBoxContainer.new()
	notices.set_anchors_preset(Control.PRESET_CENTER_TOP)
	notices.position = Vector2(-300, 54)
	notices.custom_minimum_size = Vector2(600, 0)
	notices.alignment = BoxContainer.ALIGNMENT_BEGIN
	notices.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notices)
	tip = PanelContainer.new()
	tip.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.04, 0.04, 0.05, 0.96), Ui.EDGE, 6, 10))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip.visible = false
	tip_label = RichTextLabel.new()
	tip_label.bbcode_enabled = true
	tip_label.fit_content = true
	tip_label.custom_minimum_size = Vector2(320, 0)
	tip_label.scroll_active = false
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_label.add_theme_font_size_override("normal_font_size", 16)
	tip_label.add_theme_font_override("bold_font", Game.font_bold)
	tip.add_child(tip_label)
	root.add_child(tip)
	refresh()


func _build_top() -> void:
	top = PanelContainer.new()
	top.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.05, 0.05, 0.06, 0.88), Ui.EDGE, 0, 6))
	top.position = Vector2(8, 6)
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	top.add_child(row)
	for pair in [["gold", "_gold"], ["aether", "_aether"], ["supply", "_supply"]]:
		row.add_child(Ui.icon(pair[0], 24))
		var l := Ui.label("0", 20, Game.PALE, Game.font_bold)
		l.custom_minimum_size.x = 64
		set(pair[1], l)
		row.add_child(l)
	_age = Ui.label("", 18, Game.GOLD, Game.font_title_bold)
	row.add_child(_age)
	_clock = Ui.label("0:00", 18, Color(0.8, 0.78, 0.72))
	_clock.custom_minimum_size.x = 56
	row.add_child(_clock)
	var mb := Ui.button("Menu", toggle_menu, 14)
	mb.focus_mode = Control.FOCUS_NONE
	row.add_child(mb)


func _build_bottom() -> void:
	bottom = PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", Ui.panel_style(Color(0.05, 0.05, 0.065, 0.94), Ui.EDGE, 0, 6))
	bottom.anchor_left = 0.0
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_top = -PANEL_H
	bottom.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(bottom)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	bottom.add_child(row)
	minimap = Minimap.new()
	minimap.hud = self
	minimap.custom_minimum_size = Vector2(PANEL_H - 12, PANEL_H - 12)
	row.add_child(minimap)
	info = InfoPanel.new()
	info.hud = self
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	card = GridContainer.new()
	card.columns = 4
	card.add_theme_constant_override("h_separation", 4)
	card.add_theme_constant_override("v_separation", 4)
	row.add_child(card)
	for i in 12:
		var b := CardButton.new()
		b.hud = self
		b.slot = i
		b.custom_minimum_size = Vector2(62, 52)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _press(i))
		b.mouse_entered.connect(func(): _show_tip(i))
		b.mouse_exited.connect(func(): tip.visible = false)
		card.add_child(b)
		_buttons.append(b)


func is_over_ui(p: Vector2) -> bool:
	if p.y >= root.size.y - PANEL_H:
		return true
	if top.get_global_rect().has_point(p):
		return true
	if menu and menu.visible and menu.get_global_rect().has_point(p):
		return true
	if result_panel and result_panel.visible and result_panel.get_global_rect().has_point(p):
		return true
	return false


func _process(delta: float) -> void:
	if m == null or m.sim == null:
		return
	var p: Dictionary = m.sim.players[m.me] if m.me >= 0 else {}
	if not p.is_empty():
		_gold.text = str(int(p.gold))
		_aether.text = str(int(p.aether))
		_supply.text = "%d/%d" % [p.supply, p.cap]
		_supply.add_theme_color_override("font_color", Game.BAD if p.supply >= p.cap and p.cap < Data.MAX_SUPPLY else Game.PALE)
		_age.text = Data.age_name(p.race, p.tier)
	var t := int(m.sim.time)
	_clock.text = "%d:%02d" % [t / 60, t % 60]
	_refresh_t -= delta
	if _refresh_t <= 0.0:
		_refresh_t = 0.25
		refresh()
	overlay.queue_redraw()
	info.queue_redraw()
	minimap.queue_redraw()


# --- command card --------------------------------------------------------------------------

## What the command card shows for the current selection: a list of 12 slots, each null or
## {"kind", "id", "title", "tip", "ok", "cb", "glyph" or "tex"}.
func _entries() -> Array:
	var out := []
	out.resize(12)
	if m.me < 0:
		return out
	var mine := m.selected_ents().filter(func(e): return e.owner == m.me)
	if mine.is_empty():
		return out
	var race: String = m.sim.players[m.me].race
	var units := mine.filter(func(e): return e.is_unit())
	if not units.is_empty():
		var workers := units.filter(func(e): return e.role == "worker")
		if submenu == "build" and not workers.is_empty():
			var i := 0
			for role in Data.BUILD_MENU:
				if not Data.has_building(race, role):
					continue
				var why := m.sim.why_not(m.me, "building", role)
				var r: String = role
				out[i] = {"kind": "building", "id": role, "tex": Portraits.get_tex(race, role), "title": Data.building_name(race, role),
					"tip": _tip(Data.building_name(race, role), Data.BUILDINGS[role].role, m.sim.cost_of(m.me, "building", role), Data.BUILDINGS[role].desc, why),
					"ok": why == "", "cb": func(): m.begin_build(r)}
				i += 1
			out[11] = {"kind": "cmd", "glyph": "back", "title": "Back", "tip": "[b]Back[/b]", "ok": true, "cb": func():
				submenu = ""
				refresh()}
			return out
		if not workers.is_empty():
			out[0] = {"kind": "cmd", "glyph": "build", "title": "Build", "tip": "[b]Build[/b]\nChoose a building, then click where it should stand. Shift keeps placing.", "ok": true, "cb": func():
				submenu = "build"
				refresh()}
		out[4] = {"kind": "cmd", "glyph": "attack", "title": "Attack", "tip": "[b]Attack-move[/b]\nClick a place: troops walk there and fight whatever they meet.", "ok": true, "cb": func(): m.mode = "amove"}
		out[5] = {"kind": "cmd", "glyph": "stop", "title": "Stop", "tip": "[b]Stop[/b]", "ok": true, "cb": func():
			m.issue({"t": "stop", "ids": units.map(func(e): return e.id)})}
		return out
	var b: Ent = mine[0]
	var same := mine.filter(func(e): return e.role == b.role and e.complete)
	if not b.complete:
		out[11] = {"kind": "cmd", "glyph": "cancel", "title": "Cancel", "tip": "[b]Cancel construction[/b]\nGet 75% of the cost back.", "ok": true, "cb": func():
			m.issue({"t": "cancel", "id": b.id})}
		return out
	var i := 0
	for role in Data.BUILDINGS[b.role].get("trains", []):
		if not Data.has_unit(race, role):
			continue
		var why := m.sim.why_not(m.me, "unit", role)
		var r: String = role
		var st := m.sim.stats(m.me, role)
		var extra := "Life %d · Attack %d · Armour %d/%d" % [st.hp, st.atk, st.arm, st.parm]
		out[i] = {"kind": "unit", "id": role, "tex": Portraits.get_tex(race, role), "title": Data.unit_name(race, role),
			"tip": _tip(Data.unit_name(race, role) + (" (elite)" if st.elite else ""), Data.UNITS[role].role, m.sim.cost_of(m.me, "unit", role), Data.UNITS[role].desc + "\n" + extra, why),
			"ok": why == "", "cb": func():
				var best: Ent = same[0]
				for o in same:
					if o.queue.size() < best.queue.size():
						best = o
				m.issue({"t": "train", "id": best.id, "u": r, "n": 5 if Input.is_key_pressed(KEY_SHIFT) else 1})}
		i += 1
	# technologies start on the second row when the building also trains troops
	if i > 0 and b.role != "hall":
		i = maxi(i, 4)
	var p: Dictionary = m.sim.players[m.me]
	for tech in Data.TECH_ORDER:
		var td: Dictionary = Data.TECHS[tech]
		if td.at != b.role or not Data.has_tech(race, tech) or p.techs.has(tech):
			continue
		if td.has("need") and not p.techs.has(td.need):
			continue
		if tech == "tier3" and not p.techs.has("tier2"):
			continue
		if i >= 11:
			break
		var why := m.sim.why_not(m.me, "tech", tech)
		var k: String = tech
		var desc: String = td.desc if tech != "unique" else Data.RACES[race].unique_text
		out[i] = {"kind": "tech", "id": tech, "glyph": Ui.tech_glyph(tech), "title": Data.tech_name(race, tech),
			"tip": _tip(Data.tech_name(race, tech), "Technology", m.sim.cost_of(m.me, "tech", tech), desc, why),
			"ok": why == "", "cb": func():
				var best: Ent = same[0]
				for o in same:
					if o.queue.size() < best.queue.size():
						best = o
				m.issue({"t": "research", "id": best.id, "k": k})}
		i += 1
	if not b.queue.is_empty():
		out[11] = {"kind": "cmd", "glyph": "cancel", "title": "Cancel", "tip": "[b]Cancel[/b] the last order in the queue (full refund).", "ok": true, "cb": func():
			m.issue({"t": "cancel", "id": b.id, "i": b.queue.size() - 1})}
	return out


func _tip(title: String, role: String, cost: Dictionary, desc: String, why: String) -> String:
	var s := "[b]%s[/b]  [color=#b8ad98]%s[/color]\n" % [title, role]
	s += "[color=#f2c86b]%s[/color]\n%s" % [Data.cost_text(cost), desc]
	if why != "":
		s += "\n[color=#ff7a6a]%s[/color]" % why
	return s


func refresh() -> void:
	if m == null:
		return
	var entries := _entries()
	for i in 12:
		_buttons[i].entry = entries[i]
		_buttons[i].disabled = entries[i] == null
		_buttons[i].queue_redraw()


func _press(i: int) -> void:
	var e = _buttons[i].entry
	if e == null:
		return
	if not e.ok:
		var why := str(e.tip).get_slice("[color=#ff7a6a]", 1).get_slice("[/color]", 0)
		notice(why if why != "" else "Not available")
		Game.play("error", -10.0)
		return
	Game.play("click", -8.0)
	e.cb.call()
	refresh()


func hotkey(code: int) -> bool:
	var i := KEYS.find(code)
	if i < 0:
		return false
	_press(i)
	return true


func _show_tip(i: int) -> void:
	var e = _buttons[i].entry
	if e == null:
		tip.visible = false
		return
	tip_label.text = str(e.tip)
	tip.visible = true
	tip.reset_size()
	await get_tree().process_frame
	var r := card.get_global_rect()
	tip.position = Vector2(clampf(r.end.x - tip.size.x, 0, root.size.x - tip.size.x), r.position.y - tip.size.y - 16)


# --- notices, alerts, menus ------------------------------------------------------------------

func notice(text: String) -> void:
	for c in notices.get_children():
		if c is Label and c.text == text:
			c.set_meta("t", 3.0)
			return
	var l := Ui.label(text, 20, Game.PALE, Game.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.set_meta("t", 3.0)
	notices.add_child(l)
	while notices.get_child_count() > 4:
		notices.get_child(0).queue_free()
		notices.remove_child(notices.get_child(0))
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func alert(p: Vector2) -> void:
	notice("You are under attack! (Space to look)")
	minimap.pings.append({"p": p, "t": 0.0})


func toggle_menu() -> void:
	if menu and menu.visible:
		menu.visible = false
		if not m.online:
			m.paused = false
		return
	if menu == null:
		menu = PanelContainer.new()
		menu.set_anchors_preset(Control.PRESET_CENTER)
		root.add_child(menu)
	for c in menu.get_children():
		c.queue_free()
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	menu.add_child(col)
	col.add_child(Ui.title("Paused" if not m.online else "Menu", 34))
	col.add_child(Ui.button("Resume", toggle_menu))
	var qb := Ui.button("Graphics: " + Game.QUALITY_NAMES[Game.quality], func(): pass)
	qb.pressed.connect(func():
		Game.cycle_quality()
		qb.text = "Graphics: " + Game.QUALITY_NAMES[Game.quality])
	col.add_child(qb)
	var sb := Ui.button("Sound: " + ("off" if Game.muted else "on"), func(): pass)
	sb.pressed.connect(func():
		Game.toggle_mute()
		sb.text = "Sound: " + ("off" if Game.muted else "on"))
	col.add_child(sb)
	var mb := Ui.button("Music: " + ("on" if Game.music_on else "off"), func(): pass)
	mb.pressed.connect(func():
		Game.toggle_music()
		mb.text = "Music: " + ("on" if Game.music_on else "off"))
	col.add_child(mb)
	var vb := Ui.button("Voices: " + ("on" if Game.voices_on else "off"), func(): pass)
	vb.pressed.connect(func():
		Game.toggle_voices()
		vb.text = "Voices: " + ("on" if Game.voices_on else "off"))
	col.add_child(vb)
	if m.me >= 0 and m.sim.players[m.me].alive:
		col.add_child(Ui.button("Resign", func():
			m.issue({"t": "resign"})
			toggle_menu()))
	col.add_child(Ui.button("Quit to title", func(): m.leave()))
	col.add_child(Ui.wrap("Left click selects, drag to box-select. Right click moves, attacks, gathers, builds or sets a rally point. Command keys: Q W E R / A S D F / Z X C V. Ctrl+1-9 makes a group. H: town hall, period: idle worker, space: last attack. Arrows or the screen edge pan, the wheel zooms. L: graphics, M: sound, N: music." + ("" if m.online else " +/-: game speed."), 15, Color(0.8, 0.77, 0.7), 380))
	menu.visible = true
	menu.reset_size()
	menu.position = (root.size - menu.size) * 0.5
	if not m.online:
		m.paused = true


func show_result(res: Dictionary) -> void:
	if result_panel:
		result_panel.queue_free()
	result_panel = PanelContainer.new()
	root.add_child(result_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	result_panel.add_child(col)
	var t := Ui.title("Victory" if res.won else "Defeat", 52)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var mins := int(res.time) / 60
	col.add_child(Ui.label("The war lasted %d:%02d." % [mins, int(res.time) % 60], 18))
	var grid := GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 18)
	col.add_child(grid)
	for h in ["Player", "Race", "Trained", "Killed", "Lost", "Razed", "Gathered", "Techs"]:
		grid.add_child(Ui.label(h, 15, Game.GOLD, Game.font_bold))
	for p in res.players:
		var c: Color = Data.TEAM_COLORS[p.color % 4].lightened(0.25)
		grid.add_child(Ui.label(str(p.name) + ("" if p.alive else " ✝".replace("✝", "")), 16, c, Game.font_bold))
		grid.add_child(Ui.label(Data.RACES[p.race].name, 16))
		for k in ["trained", "killed", "lost", "razed"]:
			grid.add_child(Ui.label(str(p.stats[k]), 16))
		grid.add_child(Ui.label(str(p.stats.gold + p.stats.aether), 16))
		grid.add_child(Ui.label(str(p.stats.techs), 16))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(Ui.button("Back to title", func(): m.leave(), 18))
	result_panel.reset_size()
	result_panel.position = (root.size - result_panel.size) * 0.5 - Vector2(0, 40)


# --- drawn widgets -----------------------------------------------------------------------------

## A command card button: a portrait or glyph, the hotkey letter, greyed when unavailable.
class CardButton extends Button:
	var hud: Hud
	var slot := 0
	var entry = null

	func _draw() -> void:
		if entry == null:
			return
		var r := Rect2(Vector2(4, 3), size - Vector2(8, 6))
		var col := Color.WHITE if entry.ok else Color(0.45, 0.45, 0.45)
		if entry.has("tex") and entry.tex:
			draw_texture_rect(entry.tex, Rect2(r.position + Vector2((r.size.x - r.size.y) * 0.5, 0), Vector2(r.size.y, r.size.y)), false, col)
		elif entry.has("glyph"):
			var g := Rect2(r.position + Vector2(r.size.x * 0.5 - 16, 6), Vector2(32, 32))
			Ui.draw_glyph(self, entry.glyph, g, col)
			if not entry.ok:
				draw_rect(g.grow(2), Color(0, 0, 0, 0.45))
		var f := Game.font_bold
		draw_string_outline(f, Vector2(5, 15), Hud.KEY_NAMES[slot], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0, 0.9))
		draw_string(f, Vector2(5, 15), Hud.KEY_NAMES[slot], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Game.GOLD if entry.ok else Color(0.6, 0.55, 0.45))


## Health bars over units, the selection box and the build hint.
class Overlay extends Control:
	var hud: Hud

	func _draw() -> void:
		var m := hud.m
		var v := m.view
		var vs := get_viewport_rect().size
		for e in m.sim.list:
			if not e.alive or e.is_resource():
				continue
			var sel := v.selected.has(e.id)
			if not sel and e.hp >= e.max_hp - 0.5 and e.complete:
				continue
			if not v.can_see(e) or not v.on_screen(e):
				continue
			var sp := v.screen_pos(e)
			if sp.x < -20 or sp.y < -20 or sp.x > vs.x + 20 or sp.y > vs.y - Hud.PANEL_H:
				continue
			var w := 26.0 if e.is_unit() else 20.0 + e.size * 10.0
			var y := sp.y - (26.0 if e.is_unit() else 20.0 + e.size * 9.0) - (18.0 if e.flying else 0.0)
			var f := clampf(e.hp / maxf(e.max_hp, 1.0), 0.0, 1.0)
			var col := Color(0.2, 0.9, 0.3) if f > 0.6 else (Color(0.95, 0.8, 0.2) if f > 0.3 else Color(0.95, 0.25, 0.2))
			if e.owner >= 0 and e.owner != m.me and m.me >= 0 and m.sim.enemies(m.me, e.owner):
				col = col.lerp(Color(1, 0.3, 0.3), 0.4)
			draw_rect(Rect2(sp.x - w * 0.5 - 1, y - 1, w + 2, 6), Color(0, 0, 0, 0.75))
			draw_rect(Rect2(sp.x - w * 0.5, y, w * f, 4), col)
			if e.is_building() and not e.complete:
				draw_rect(Rect2(sp.x - w * 0.5, y + 5, w * e.built, 3), Color(0.5, 0.8, 1.0))
		var dr := m.drag_rect()
		if dr.size != Vector2.ZERO:
			draw_rect(dr, Color(0.3, 1.0, 0.4, 0.12))
			draw_rect(dr, Color(0.3, 1.0, 0.4, 0.8), false, 1.5)
		if m.mode == "amove":
			draw_string(Game.font_bold, get_viewport().get_mouse_position() + Vector2(14, -6), "Attack", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.5, 0.4))
		elif m.mode == "build":
			draw_string(Game.font_bold, get_viewport().get_mouse_position() + Vector2(18, -10), Data.building_name(m.sim.players[m.me].race, m.build_role), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 1.0, 0.6))


## The minimap: terrain, fog of war, everything you can see, the camera frame and alert pings.
## Left click or drag moves the camera; right click orders the selection there.
class Minimap extends Control:
	var hud: Hud
	var pings: Array = []
	var _terrain: ImageTexture
	var _fog_img: Image
	var _fog_tex: ImageTexture
	var _fog_t := 0.0
	var _dragging := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _build() -> void:
		var sim := hud.m.sim
		var n := sim.map.n
		var t: Dictionary = sim.map.template
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var c := Vector2i(x, y)
				var col: Color = t.ground
				match sim.map.get_cell(c):
					MapData.WATER:
						col = Color(t.water).lightened(0.15)
					MapData.CLIFF:
						col = Color(t.rock).darkened(0.2)
					MapData.THICKET:
						col = Color(t.ground).darkened(0.45)
					MapData.PAVING, MapData.BRIDGE:
						col = Color(t.rock).lightened(0.1)
					MapData.RAMP:
						col = Color(t.dirt)
				if sim.map.heights[sim.map.idx(c)] > 1.0 and sim.map.get_cell(c) == MapData.GROUND:
					col = col.lightened(0.12)
				img.set_pixel(x, y, col)
		_terrain = ImageTexture.create_from_image(img)
		_fog_img = Image.create(n, n, false, Image.FORMAT_RGBA8)
		_fog_tex = ImageTexture.create_from_image(_fog_img)

	func _process(delta: float) -> void:
		for p in pings:
			p.t += delta
		pings = pings.filter(func(p): return p.t < 3.0)

	func _to_map(lp: Vector2) -> Vector2:
		return lp / size * hud.m.sim.map.size_m()

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
				if mb.pressed:
					hud.m.view.look_at_point(_to_map(mb.position))
			elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
				var p := _to_map(mb.position)
				var ids := hud.m.selected_ents().filter(func(e): return e.owner == hud.m.me and e.is_unit()).map(func(e): return e.id)
				if not ids.is_empty():
					hud.m.issue({"t": "move", "ids": ids, "x": p.x, "y": p.y})
					hud.m.view.mark(p)
			accept_event()
		elif ev is InputEventMouseMotion and _dragging:
			hud.m.view.look_at_point(_to_map((ev as InputEventMouseMotion).position))
			accept_event()

	func _draw() -> void:
		var m := hud.m
		if _terrain == null:
			_build()
		var sim := m.sim
		var n := sim.map.n
		var r := Rect2(Vector2.ZERO, size)
		draw_texture_rect(_terrain, r, false)
		var k := size.x / sim.map.size_m()
		for e in sim.list:
			if not e.alive or not m.view.can_see(e):
				continue
			var p: Vector2 = e.pos * k
			if e.is_resource():
				draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), Color(1.0, 0.85, 0.3) if e.role == "gold" else Color(0.5, 0.9, 1.0))
				continue
			var c: Color = Data.TEAM_COLORS[sim.players[e.owner].color % 4]
			if e.is_building():
				var s: float = e.size * Data.CELL * k
				draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), c.lightened(0.2))
				draw_rect(Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), Color(0, 0, 0, 0.6), false, 1.0)
			else:
				draw_rect(Rect2(p - Vector2(1.5, 1.5), Vector2(3, 3)), c.lightened(0.35))
		_fog_t -= get_process_delta_time()
		if m.view.fog_on and _fog_t <= 0.0:
			_fog_t = 0.3
			for y in n:
				for x in n:
					var v := m.view.visible_grid[y * n + x]
					_fog_img.set_pixel(x, y, Color(0, 0, 0, 0.0 if v == 2 else (0.45 if v == 1 else 0.92)))
			_fog_tex.update(_fog_img)
		if m.view.fog_on:
			draw_texture_rect(_fog_tex, r, false)
		# camera frame
		var vs := get_viewport_rect().size
		var corners := [Vector2(0, 0), Vector2(vs.x, 0), Vector2(vs.x, vs.y - Hud.PANEL_H), Vector2(0, vs.y - Hud.PANEL_H)]
		var pts := PackedVector2Array()
		for c in corners:
			pts.append((m.view.screen_to_ground(c) * k).clamp(Vector2.ZERO, size))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.85), 1.2)
		for p in pings:
			var pp: Vector2 = p.p * k
			draw_arc(pp, 4.0 + fmod(p.t, 1.0) * 14.0, 0, TAU, 20, Color(1, 0.2, 0.15, 1.0 - fmod(p.t, 1.0)), 2.0)
		draw_rect(r, Ui.EDGE, false, 1.0)


## What is selected: one thing in detail (portrait, life, numbers, queue), or a grid of many.
class InfoPanel extends Control:
	var hud: Hud
	var _slots: Array = []           # [Rect2, id or queue index, kind]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			for s in _slots:
				if s[0].has_point(ev.position):
					if s[2] == "unit":
						if ev.shift_pressed:
							var ids: Array = hud.m.selection.duplicate()
							ids.erase(s[1])
							hud.m._set_selection(ids)
						else:
							hud.m._set_selection([s[1]])
					elif s[2] == "queue":
						var b: Ent = hud.m.selected_ents()[0]
						hud.m.issue({"t": "cancel", "id": b.id, "i": s[1]})
					accept_event()
					return

	func _draw() -> void:
		_slots.clear()
		var m := hud.m
		var ents := m.selected_ents()
		var f := Game.font_body
		var fb := Game.font_bold
		if ents.is_empty():
			if m.me >= 0:
				var p: Dictionary = m.sim.players[m.me]
				var rd: Dictionary = Data.RACES[p.race]
				draw_string(Game.font_title_bold, Vector2(8, 30), rd.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Game.GOLD)
				draw_string(f, Vector2(8, 56), rd.motto, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 17, Color(0.8, 0.77, 0.7))
				draw_string(f, Vector2(8, 84), "Race bonus: " + rd.bonus_text, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 16, Color(0.75, 0.72, 0.66))
				var idle := 0
				for e in m.sim.list:
					if e.alive and e.owner == m.me and e.role == "worker" and e.order == Ent.IDLE:
						idle += 1
				if idle > 0:
					draw_string(fb, Vector2(8, 112), "%d idle worker%s (press period)" % [idle, "s" if idle > 1 else ""], HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(1, 0.8, 0.4))
			return
		if ents.size() == 1:
			_one(ents[0])
			return
		var cell := 44.0
		var cols := maxi(1, int(size.x / (cell + 4)))
		for i in mini(ents.size(), cols * 3):
			var e: Ent = ents[i]
			var r := Rect2(Vector2(4 + (i % cols) * (cell + 4), 6 + (i / cols) * (cell + 8)), Vector2(cell, cell))
			draw_rect(r, Color(0.1, 0.1, 0.12))
			var race: String = m.sim.players[e.owner].race if e.owner >= 0 else ""
			var tex := Portraits.get_tex(race, e.role)
			if tex:
				draw_texture_rect(tex, r, false)
			draw_rect(r, Data.TEAM_COLORS[m.sim.players[e.owner].color % 4] if e.owner >= 0 else Ui.EDGE, false, 1.0)
			var hf := clampf(e.hp / maxf(e.max_hp, 1.0), 0, 1)
			draw_rect(Rect2(r.position + Vector2(0, cell + 1), Vector2(cell * hf, 4)), Color(0.2, 0.9, 0.3) if hf > 0.5 else Color(0.95, 0.4, 0.2))
			_slots.append([r, e.id, "unit"])
		if ents.size() > cols * 3:
			draw_string(fb, Vector2(4, size.y - 6), "+%d more" % (ents.size() - cols * 3), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Game.PALE)

	func _one(e: Ent) -> void:
		var m := hud.m
		var f := Game.font_body
		var fb := Game.font_bold
		var race: String = m.sim.players[e.owner].race if e.owner >= 0 else ""
		var pr := Rect2(Vector2(4, 6), Vector2(96, 96))
		draw_rect(pr, Color(0.1, 0.1, 0.12))
		var tex := Portraits.get_tex(race, e.role) if e.owner >= 0 else null
		if tex:
			draw_texture_rect(tex, pr, false)
		elif e.is_resource():
			Ui.draw_glyph(self, e.role, pr.grow(-20))
		draw_rect(pr, Data.TEAM_COLORS[m.sim.players[e.owner].color % 4] if e.owner >= 0 else Ui.EDGE, false, 2.0)
		var x := 112.0
		var name := ""
		var sub := ""
		if e.is_resource():
			name = Data.RESOURCES[e.role].name
			sub = "%d left" % e.amount
		elif e.is_unit():
			name = Data.unit_name(race, e.role) + (" (elite)" if e.elite else "")
			sub = "%s · %s · %s" % [Data.UNITS[e.role].role, Data.RACES[race].name, m.sim.players[e.owner].name]
		else:
			name = Data.building_name(race, e.role)
			sub = "%s · %s · %s" % [Data.BUILDINGS[e.role].role, Data.RACES[race].name, m.sim.players[e.owner].name]
		draw_string(Game.font_title_bold, Vector2(x, 26), name, HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 20, Game.GOLD)
		draw_string(f, Vector2(x, 48), sub, HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 15, Color(0.78, 0.75, 0.68))
		if e.is_resource():
			return
		var hf := clampf(e.hp / maxf(e.max_hp, 1.0), 0, 1)
		var bw := minf(220.0, size.x - x - 8)
		draw_rect(Rect2(x, 56, bw, 12), Color(0, 0, 0, 0.7))
		draw_rect(Rect2(x, 56, bw * hf, 12), Color(0.2, 0.85, 0.3) if hf > 0.5 else Color(0.95, 0.5, 0.2))
		draw_string(fb, Vector2(x + bw + 8, 67), "%d / %d" % [ceili(e.hp), int(e.max_hp)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Game.PALE)
		var st := m.sim.stats(e.owner, e.role)
		var y := 90.0
		if e.is_unit():
			var line := "Attack %d %s · Armour %d/%d · Speed %.1f" % [st.atk, st.dmg, st.arm, st.parm, st.speed]
			if st.range > 1.0:
				line += " · Range %d" % int(st.range)
			draw_string(f, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 15, Game.PALE)
			y += 20
			var bonus: Dictionary = st.bonus
			if not bonus.is_empty():
				var parts := []
				for k in bonus:
					parts.append("+%d vs %s" % [bonus[k], k])
				draw_string(f, Vector2(x, y), "Bonus: " + ", ".join(parts), HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 15, Color(0.85, 0.8, 0.6))
				y += 20
			if e.owner == m.me or m.me < 0:
				var status: String = Hud.ORDER_NAMES[e.order]
				if e.carry > 0:
					status += " · carrying %d %s" % [e.carry, e.carry_type]
				draw_string(f, Vector2(x, y), status, HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 15, Color(0.7, 0.9, 1.0))
			return
		if not e.complete:
			draw_string(fb, Vector2(x, y), "Under construction: %d%%" % int(e.built * 100), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.85, 1.0))
			return
		if st.atk > 0:
			draw_string(f, Vector2(x, y), "Attack %d · Range %d" % [st.atk, int(st.range)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Game.PALE)
			y += 20
		if e.owner != m.me:
			return
		if e.queue.is_empty():
			var hint := ""
			if Data.BUILDINGS[e.role].get("supply", 0) > 0:
				hint = "Supports %d supply." % Data.BUILDINGS[e.role].supply
			if Data.BUILDINGS[e.role].get("drop", false):
				hint += (" " if hint != "" else "") + "Workers drop resources here."
			draw_string(f, Vector2(x, y), hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 15, Color(0.78, 0.75, 0.68))
			return
		for i in e.queue.size():
			var q: Dictionary = e.queue[i]
			var r := Rect2(Vector2(x + i * 50, y - 14), Vector2(44, 44))
			draw_rect(r, Color(0.1, 0.1, 0.12))
			if q.kind == "unit":
				var tx := Portraits.get_tex(race, q.id)
				if tx:
					draw_texture_rect(tx, r, false)
			else:
				Ui.draw_glyph(self, Ui.tech_glyph(q.id), r.grow(-8))
			draw_rect(r, Ui.EDGE, false, 1.0)
			if i == 0:
				draw_rect(Rect2(r.position + Vector2(0, 46), Vector2(44 * clampf(q.t / q.total, 0, 1), 4)), Color(0.5, 0.85, 1.0))
			_slots.append([r, i, "queue"])
		var q0: Dictionary = e.queue[0]
		var nm := Data.unit_name(race, q0.id) if q0.kind == "unit" else Data.tech_name(race, q0.id)
		var p: Dictionary = m.sim.players[m.me]
		var waiting: bool = q0.kind == "unit" and not q0.reserved and p.supply + int(Data.UNITS[q0.id].supply) > p.cap
		draw_string(f, Vector2(x, y + 50), ("Waiting for supply: " if waiting else "") + nm + " (click to cancel)", HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 14, Game.BAD if waiting else Color(0.78, 0.75, 0.68))
