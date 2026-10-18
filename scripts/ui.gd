class_name Ui
extends RefCounted
## Shared look for menus and the HUD: the theme (dark slate panels with gold edges), label and
## button helpers, and small vector icons (gold, aether, supply, swords, arrows, shields...)
## drawn in code because the web fonts have no symbols.

const INK := Color(0.06, 0.06, 0.08, 0.92)
const EDGE := Color(0.95, 0.78, 0.42, 0.55)

static var _theme: Theme


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = Game.font_body
	t.default_font_size = 18
	var normal := _box(Color(0.1, 0.09, 0.11, 0.94), EDGE, 2, 6)
	normal.content_margin_left = 14
	normal.content_margin_right = 14
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	var hover := normal.duplicate()
	hover.bg_color = Color(0.2, 0.16, 0.12, 0.96)
	hover.border_color = Game.GOLD
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.3, 0.12, 0.08, 0.96)
	pressed.border_color = Color(1.0, 0.6, 0.4)
	var disabled := normal.duplicate()
	disabled.bg_color = Color(0.07, 0.07, 0.08, 0.8)
	disabled.border_color = Color(0.4, 0.36, 0.3, 0.4)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("focus", "Button", hover)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_font("font", "Button", Game.font_title_bold)
	t.set_font_size("font_size", "Button", 16)
	t.set_color("font_color", "Button", Color(0.96, 0.92, 0.82))
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.45))
	var panel := _box(INK, Color(EDGE, 0.4), 1, 8)
	panel.set_content_margin_all(16)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_color("font_color", "Label", Game.PALE)
	var le := _box(Color(0.03, 0.03, 0.04, 0.95), EDGE, 1, 4)
	le.set_content_margin_all(8)
	t.set_stylebox("normal", "LineEdit", le)
	t.set_stylebox("focus", "LineEdit", le)
	t.set_font_size("font_size", "LineEdit", 18)
	var ob := normal.duplicate()
	t.set_stylebox("normal", "OptionButton", ob)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_stylebox("focus", "OptionButton", hover)
	t.set_font("font", "OptionButton", Game.font_body)
	t.set_font_size("font_size", "OptionButton", 17)
	var pop := _box(Color(0.08, 0.07, 0.09, 0.98), EDGE, 1, 4)
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_font("font", "PopupMenu", Game.font_body)
	t.set_font_size("font_size", "PopupMenu", 17)
	var tip := _box(Color(0.05, 0.05, 0.06, 0.96), EDGE, 1, 4)
	tip.set_content_margin_all(8)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_font_size("font_size", "TooltipLabel", 16)
	_theme = t
	return t


static func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	return s


static func panel_style(bg := INK, border := EDGE, radius := 8, pad := 14) -> StyleBoxFlat:
	var s := _box(bg, border, 1, radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	return s


static func label(text: String, size := 18, col := Game.PALE, font: Font = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	if font:
		l.add_theme_font_override("font", font)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


static func wrap(text: String, size := 17, col := Game.PALE, width := 360.0) -> Label:
	var l := label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


static func title(text: String, size := 40) -> Label:
	var l := label(text, size, Game.GOLD, Game.font_title_bold)
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.05, 0.02, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	return l


static func button(text: String, cb: Callable, size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(func():
		Game.play("click", -6.0)
		cb.call())
	return b


static func icon(kind: String, size := 22.0, col := Color.WHITE) -> Glyph:
	var g := Glyph.new()
	g.kind = kind
	g.col = col
	g.custom_minimum_size = Vector2(size, size)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


## The glyph that stands for a technology on the command card.
static func tech_glyph(tech: String) -> String:
	if tech.begins_with("tier"):
		return "age"
	if tech.begins_with("gold"):
		return "gold"
	if tech.begins_with("aether"):
		return "aether"
	if tech == "carry" or tech == "worker_armor":
		return "pick"
	if tech.begins_with("melee"):
		return "sword"
	if tech.begins_with("ranged"):
		return "arrow"
	if tech.begins_with("armor"):
		return "shield"
	if tech.begins_with("elite"):
		return "elite"
	if tech.begins_with("tower"):
		return "tower"
	return "star"


## Draws a small icon with polygons into a rectangle of `canvas`.
static func draw_glyph(cv: CanvasItem, kind: String, rect: Rect2, col := Color.WHITE) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	match kind:
		"gold":
			for i in 3:
				var o := c + Vector2((i - 1) * r * 0.45, (0.25 if i != 1 else -0.15) * r)
				var pts := PackedVector2Array([o + Vector2(-r * 0.35, 0), o + Vector2(0, -r * 0.3), o + Vector2(r * 0.35, 0), o + Vector2(0, r * 0.3)])
				cv.draw_colored_polygon(pts, Color(1.0, 0.8, 0.25))
				cv.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.6, 0.4, 0.1), 1.0, true)
		"aether":
			var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.55, -r * 0.1), c + Vector2(0, r), c + Vector2(-r * 0.55, -r * 0.1)])
			cv.draw_colored_polygon(pts, Color(0.35, 0.8, 1.0))
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.55, -r * 0.1), c + Vector2(0, 0)]), Color(0.8, 0.97, 1.0))
			cv.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.85, 0.97, 1.0), 1.0, true)
		"supply":
			var pts := PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.05), c + Vector2(0, -r * 0.8), c + Vector2(r * 0.75, -r * 0.05)])
			cv.draw_colored_polygon(pts, Color(0.85, 0.45, 0.3))
			cv.draw_rect(Rect2(c + Vector2(-r * 0.55, -r * 0.05), Vector2(r * 1.1, r * 0.8)), Color(0.9, 0.85, 0.7))
			cv.draw_rect(Rect2(c + Vector2(-r * 0.15, r * 0.3), Vector2(r * 0.3, r * 0.45)), Color(0.35, 0.25, 0.15))
		"sword":
			cv.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.6, -r * 0.6), col, maxf(2.0, r * 0.22), true)
			cv.draw_line(c + Vector2(-r * 0.6, r * 0.2), c + Vector2(-r * 0.2, r * 0.6), Color(0.8, 0.6, 0.3), maxf(2.0, r * 0.18), true)
		"arrow":
			cv.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.5, -r * 0.5), col, maxf(1.5, r * 0.12), true)
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.75, -r * 0.75), c + Vector2(r * 0.25, -r * 0.55), c + Vector2(r * 0.55, -r * 0.25)]), col)
			cv.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(-r * 0.75, r * 0.35), Color(0.9, 0.3, 0.2), maxf(1.5, r * 0.12), true)
			cv.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(-r * 0.35, r * 0.75), Color(0.9, 0.3, 0.2), maxf(1.5, r * 0.12), true)
		"shield":
			var pts := PackedVector2Array([c + Vector2(-r * 0.65, -r * 0.7), c + Vector2(r * 0.65, -r * 0.7), c + Vector2(r * 0.6, r * 0.1), c + Vector2(0, r * 0.85), c + Vector2(-r * 0.6, r * 0.1)])
			cv.draw_colored_polygon(pts, col.darkened(0.3))
			cv.draw_polyline(pts + PackedVector2Array([pts[0]]), col, maxf(1.5, r * 0.12), true)
		"age":
			var pts := PackedVector2Array([c + Vector2(-r * 0.8, r * 0.5), c + Vector2(-r * 0.8, -r * 0.4), c + Vector2(-r * 0.4, 0), c + Vector2(0, -r * 0.7),
				c + Vector2(r * 0.4, 0), c + Vector2(r * 0.8, -r * 0.4), c + Vector2(r * 0.8, r * 0.5)])
			cv.draw_colored_polygon(pts, Game.GOLD)
			cv.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 0.95, 0.7), 1.2, true)
		"pick":
			cv.draw_line(c + Vector2(-r * 0.5, r * 0.7), c + Vector2(r * 0.3, -r * 0.4), Color(0.7, 0.5, 0.3), maxf(2.0, r * 0.15), true)
			cv.draw_arc(c + Vector2(r * 0.15, -r * 0.1), r * 0.6, -PI * 0.95, -PI * 0.2, 12, col, maxf(2.0, r * 0.16), true)
		"elite":
			for i in 3:
				var y := r * (0.45 - i * 0.45)
				cv.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.7, y + r * 0.2), c + Vector2(0, y - r * 0.25), c + Vector2(r * 0.7, y + r * 0.2)]), Game.GOLD, maxf(2.0, r * 0.18), true)
		"tower":
			cv.draw_rect(Rect2(c + Vector2(-r * 0.3, -r * 0.4), Vector2(r * 0.6, r * 1.2)), col.darkened(0.2))
			for i in 3:
				cv.draw_rect(Rect2(c + Vector2(-r * 0.45 + i * r * 0.33, -r * 0.75), Vector2(r * 0.22, r * 0.35)), col)
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + TAU * i / 10.0
				pts.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
			cv.draw_colored_polygon(pts, Game.GOLD)
		"build":
			cv.draw_rect(Rect2(c + Vector2(-r * 0.7, -r * 0.1), Vector2(r * 1.4, r * 0.8)), Color(0.8, 0.7, 0.5))
			cv.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.85, -r * 0.1), c + Vector2(0, -r * 0.8), c + Vector2(r * 0.85, -r * 0.1)]), Color(0.7, 0.3, 0.2))
		"stop":
			cv.draw_rect(Rect2(c - Vector2(r, r) * 0.6, Vector2(r, r) * 1.2), Color(0.85, 0.2, 0.15))
		"attack":
			cv.draw_line(c + Vector2(-r * 0.7, r * 0.7), c + Vector2(r * 0.7, -r * 0.7), col, maxf(2.0, r * 0.18), true)
			cv.draw_line(c + Vector2(r * 0.7, r * 0.7), c + Vector2(-r * 0.7, -r * 0.7), col, maxf(2.0, r * 0.18), true)
		"back":
			cv.draw_polyline(PackedVector2Array([c + Vector2(r * 0.3, -r * 0.6), c + Vector2(-r * 0.4, 0), c + Vector2(r * 0.3, r * 0.6)]), col, maxf(2.0, r * 0.2), true)
		"cancel":
			cv.draw_line(c + Vector2(-r * 0.55, -r * 0.55), c + Vector2(r * 0.55, r * 0.55), Color(1, 0.35, 0.3), maxf(2.0, r * 0.2), true)
			cv.draw_line(c + Vector2(r * 0.55, -r * 0.55), c + Vector2(-r * 0.55, r * 0.55), Color(1, 0.35, 0.3), maxf(2.0, r * 0.2), true)


## Draws small icons with polygons.
class Glyph extends Control:
	var kind := "gold"
	var col := Color.WHITE

	func _draw() -> void:
		Ui.draw_glyph(self, kind, Rect2(Vector2.ZERO, size), col)
