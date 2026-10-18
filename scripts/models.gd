class_name Models
extends RefCounted
## Every unit, building, deposit and prop, built from MeshKit primitives with vertex colours.
## Units face +Z. Parts painted in the team marker colour `T` (magenta) take the owner's colour
## in shaders/unit.gdshader, so one mesh serves every player. Each race has its own look for the
## same template role: porcelain and sinew (Phyrexia), steel and blue tabards (Dominaria),
## gothic coats and bronze (Ravnica), brass, filigree and aether (Avishkar).

const T := Color(1, 0, 1)
const TD := Color(0.6, 0, 0.6)
const SKIN := Color(0.85, 0.66, 0.52)
const LEATHER := Color(0.36, 0.24, 0.15)
const WOOD := Color(0.45, 0.31, 0.18)
const STEEL := Color(0.7, 0.72, 0.76)
const DARK := Color(0.12, 0.11, 0.12)

static var _cache := {}


static func _mats() -> Array:
	return [Game.mat_unit, Game.mat_glow, Game.mat_unit_gloss]


static func _pal(race: String) -> Dictionary:
	return Data.RACES[race].colors


static func unit(race: String, role: String) -> ArrayMesh:
	var key := "u:%s:%s" % [race, role]
	if _cache.has(key):
		return _cache[key]
	var k := MeshKit.new()
	var fn := "_%s_%s" % [race.substr(0, 3), role]
	if role == "worker":
		_worker(k, race)
	elif role == "caster":
		_caster(k, race)
	elif role == "champion":
		_champion(k, race)
	elif role == "cavalry":
		_cavalry(k, race)
	elif role == "flyer":
		_flyer(k, race)
	elif role == "siege":
		_siege(k, race)
	else:
		_soldier(k, race, role)
	var m := k.commit(null, _mats())
	_cache[key] = m
	return m


# --- body parts ----------------------------------------------------------------------------

## A standing figure, about 1.9 m tall at s = 1. o: s, skin, body, legs, arms, head ("helm",
## "plume", "hood", "mask", "cap", "hat", "turban", "bare"), head_col, tabard, cape, belt,
## r_hand / l_hand (hand positions; weapons are added by the caller), pauldrons, spikes, robe.
static func _man(k: MeshKit, o: Dictionary) -> void:
	var s: float = o.get("s", 1.0)
	var body: Color = o.get("body", LEATHER)
	var legs: Color = o.get("legs", body.darkened(0.25))
	var arms: Color = o.get("arms", body)
	var skin: Color = o.get("skin", SKIN)
	var boot: Color = o.get("boot", DARK)
	if o.get("robe", false):
		k.taper(Vector3(0, 0, 0) * s, Vector2(0.62, 0.5) * s, Vector2(0.38, 0.26) * s, 1.0 * s, legs)
		k.box(Vector3(0, 0.55, 0.2) * s, Vector3(0.18, 0.9, 0.04) * s, o.get("tabard", T))
	else:
		for side in [-1.0, 1.0]:
			k.taper(Vector3(side * 0.11, 0.1, 0) * s, Vector2(0.13, 0.14) * s, Vector2(0.17, 0.18) * s, 0.78 * s, legs)
			k.box(Vector3(side * 0.11, 0.07, 0.03) * s, Vector3(0.15, 0.14, 0.26) * s, boot)
	k.taper(Vector3(0, 0.82, 0) * s, Vector2(0.4, 0.26) * s, Vector2(0.5, 0.3) * s, 0.6 * s, body)
	if o.has("belt"):
		k.box(Vector3(0, 0.88, 0) * s, Vector3(0.44, 0.08, 0.3) * s, o.belt)
	if o.get("tabard", null) != null and not o.get("robe", false):
		k.taper(Vector3(0, 0.55, 0.14) * s, Vector2(0.28, 0.03) * s, Vector2(0.3, 0.03) * s, 0.8 * s, o.tabard)
	if o.get("cape", false):
		k.taper(Vector3(0, 0.35, -0.17) * s, Vector2(0.56, 0.04) * s, Vector2(0.46, 0.04) * s, 1.05 * s, o.get("cape_col", TD))
	var pd: Variant = o.get("pauldrons", null)
	if pd != null:
		for side in [-1.0, 1.0]:
			k.sphere(Vector3(side * 0.29, 1.38, 0) * s, Vector3(0.14, 0.1, 0.15) * s, pd)
	# arms
	var rh: Vector3 = o.get("r_hand", Vector3(-0.27, 0.98, 0.22))
	var lh: Vector3 = o.get("l_hand", Vector3(0.27, 0.98, 0.18))
	for pair in [[-1.0, rh], [1.0, lh]]:
		var side: float = pair[0]
		var hand: Vector3 = pair[1]
		var sh := Vector3(side * 0.27, 1.36, 0)
		var el := Vector3(side * 0.31, 1.1, -0.02)
		k.cyl(sh * s, el * s, 0.075 * s, 0.065 * s, arms, 6)
		k.cyl(el * s, hand * s, 0.065 * s, 0.055 * s, arms, 6)
		k.sphere(hand * s, Vector3(0.06, 0.06, 0.06) * s, o.get("glove", skin), 6, 4)
	# neck and head
	k.cyl(Vector3(0, 1.42, 0) * s, Vector3(0, 1.52, 0) * s, 0.07 * s, 0.07 * s, skin, 6)
	var hc: Color = o.get("head_col", STEEL)
	match str(o.get("head", "bare")):
		"helm":
			k.sphere(Vector3(0, 1.64, 0) * s, Vector3(0.16, 0.17, 0.17) * s, hc, 8, 5)
			k.box(Vector3(0, 1.6, 0.15) * s, Vector3(0.04, 0.14, 0.04) * s, hc.darkened(0.2))
		"plume":
			k.sphere(Vector3(0, 1.64, 0) * s, Vector3(0.16, 0.18, 0.17) * s, hc, 8, 5)
			k.box(Vector3(0, 1.62, 0.13) * s, Vector3(0.22, 0.04, 0.05) * s, DARK)
			k.taper(Vector3(0, 1.78, -0.02) * s, Vector2(0.05, 0.22) * s, Vector2(0.03, 0.1) * s, 0.16 * s, T)
		"hood":
			k.sphere(Vector3(0, 1.63, 0) * s, Vector3(0.15, 0.16, 0.15) * s, skin, 7, 4)
			k.taper(Vector3(0, 1.48, -0.03) * s, Vector2(0.36, 0.34) * s, Vector2(0.06, 0.06) * s, 0.42 * s, hc, false, 0.0, Vector3(0, 0, -0.08) * s)
		"mask":
			# a faceless porcelain mask, long and tapering backwards
			k.taper(Vector3(0, 1.48, 0) * s, Vector2(0.24, 0.26) * s, Vector2(0.08, 0.12) * s, 0.4 * s, hc, false, 0.0, Vector3(0, 0.02, -0.12) * s)
			k.box(Vector3(0, 1.63, 0.12) * s, Vector3(0.16, 0.025, 0.03) * s, o.get("eye", Color(0.3, 1.0, 0.5)), true)
		"cap":
			k.sphere(Vector3(0, 1.63, 0) * s, Vector3(0.15, 0.16, 0.15) * s, skin, 7, 4)
			k.cyl(Vector3(0, 1.7, 0) * s, Vector3(0, 1.8, 0) * s, 0.16 * s, 0.14 * s, hc, 8)
			k.box(Vector3(0, 1.71, 0.14) * s, Vector3(0.22, 0.02, 0.1) * s, hc.darkened(0.3))
		"hat":
			k.sphere(Vector3(0, 1.63, 0) * s, Vector3(0.15, 0.16, 0.15) * s, skin, 7, 4)
			k.cyl(Vector3(0, 1.72, 0) * s, Vector3(0, 1.74, 0) * s, 0.3 * s, 0.3 * s, hc, 10)
			k.cyl(Vector3(0, 1.74, 0) * s, Vector3(0, 1.9, 0) * s, 0.13 * s, 0.05 * s, hc, 8)
		"turban":
			k.sphere(Vector3(0, 1.63, 0) * s, Vector3(0.15, 0.16, 0.15) * s, skin, 7, 4)
			k.sphere(Vector3(0, 1.75, -0.01) * s, Vector3(0.18, 0.1, 0.18) * s, hc, 8, 4)
			k.sphere(Vector3(0, 1.77, 0.15) * s, Vector3(0.04, 0.04, 0.03) * s, o.get("eye", Color(0.3, 0.95, 1.0)), 6, 3, true)
		_:
			k.sphere(Vector3(0, 1.63, 0) * s, Vector3(0.15, 0.17, 0.15) * s, skin, 7, 4)
	if o.get("spikes", false):
		for side in [-1.0, 1.0]:
			k.cyl(Vector3(side * 0.22, 1.36, -0.05) * s, Vector3(side * 0.42, 1.62, -0.18) * s, 0.05 * s, 0.0, DARK, 5)
		k.cyl(Vector3(0, 1.2, -0.15) * s, Vector3(0, 1.45, -0.42) * s, 0.06 * s, 0.0, DARK, 5)


static func _sword(k: MeshKit, hand: Vector3, s: float, blade: Color, len := 0.85, wide := 0.07) -> void:
	k.box((hand + Vector3(0, 0.03, 0.02)) * s, Vector3(0.22, 0.04, 0.05) * s, Color(0.55, 0.45, 0.2))
	k.box((hand + Vector3(0, 0.05 + len * 0.5, 0.03)) * s, Vector3(wide, len, 0.025) * s, blade)


static func _spear(k: MeshKit, hand: Vector3, s: float, shaft: Color, tip: Color, len := 2.4, glow := false) -> void:
	var a := hand + Vector3(0, -0.7, -0.15)
	var b := hand + Vector3(0, len - 0.7, 0.35)
	k.cyl(a * s, b * s, 0.03 * s, 0.03 * s, shaft, 5)
	var d := (b - a).normalized()
	k.cyl(b * s, (b + d * 0.32) * s, 0.06 * s, 0.0, tip, 5, glow)


static func _shield(k: MeshKit, at: Vector3, s: float, face: Color, rim: Color, r := 0.3, kite := false) -> void:
	if kite:
		k.taper((at + Vector3(0, -0.35, 0.05)) * s, Vector2(0.1, 0.05) * s, Vector2(0.5, 0.06) * s, 0.75 * s, face)
		k.box((at + Vector3(0, 0.05, 0.085)) * s, Vector3(0.08, 0.5, 0.02) * s, rim)
	else:
		k.cyl((at + Vector3(0, 0, 0.03)) * s, (at + Vector3(0, 0, 0.1)) * s, r * s, r * s, face, 10)
		k.ring((at + Vector3(0, 0, 0.1)) * s, Vector3(0, 0, 1), r * s, 0.03 * s, rim, 10, 4)


static func _bow(k: MeshKit, hand: Vector3, s: float, col: Color) -> void:
	var top := hand + Vector3(0.05, 0.62, 0.0)
	var bot := hand + Vector3(0.05, -0.62, 0.0)
	var mid := hand + Vector3(0.0, 0.0, 0.12)
	k.cyl(bot * s, mid * s, 0.025 * s, 0.03 * s, col, 5)
	k.cyl(mid * s, top * s, 0.03 * s, 0.025 * s, col, 5)
	k.cyl(bot * s, top * s, 0.006 * s, 0.006 * s, Color(0.9, 0.88, 0.8), 3)


static func _gun(k: MeshKit, hand: Vector3, s: float, body: Color, glow: Color, len := 0.9) -> void:
	k.box((hand + Vector3(0, 0.05, 0.25)) * s, Vector3(0.08, 0.1, len * 0.6) * s, body)
	k.cyl((hand + Vector3(0, 0.08, 0.3)) * s, (hand + Vector3(0, 0.08, 0.3 + len * 0.7)) * s, 0.03 * s, 0.03 * s, body.darkened(0.3), 6)
	k.box((hand + Vector3(0, 0.15, 0.2)) * s, Vector3(0.05, 0.05, 0.2) * s, glow, true)


static func _staff(k: MeshKit, hand: Vector3, s: float, wood: Color, orb: Color) -> void:
	k.cyl((hand + Vector3(0, -0.9, 0)) * s, (hand + Vector3(0, 0.75, 0)) * s, 0.03 * s, 0.03 * s, wood, 5)
	k.sphere((hand + Vector3(0, 0.86, 0)) * s, Vector3(0.09, 0.09, 0.09) * s, orb, 8, 5, true)


static func _wing(k: MeshKit, root: Vector3, side: float, span: float, col: Color, tip_col: Color, lift := 0.4, feathers := 4) -> void:
	for f in feathers:
		var t := float(f) / (feathers - 1)
		var a := root + Vector3(0, 0, -0.15 * t)
		var tip := root + Vector3(side * span * (1.0 - 0.25 * t), lift * (1.0 - t) + 0.1, -0.3 - 0.5 * t)
		var mid := root + Vector3(side * span * 0.5, lift * 0.7, -0.05 - 0.3 * t)
		var c := col.lerp(tip_col, t)
		k.tri(a, mid, tip, c)
		k.tri(a, tip, mid, c)
		k.tri(a + Vector3(0, -0.04, -0.2), mid, tip, c.darkened(0.1))
		k.tri(a + Vector3(0, -0.04, -0.2), tip, mid, c.darkened(0.1))


static func _horse(k: MeshKit, body: Color, mane: Color, cloth: Color, armour := false) -> void:
	k.sphere(Vector3(0, 1.15, 0), Vector3(0.36, 0.38, 0.85), body, 10, 6)
	for x in [-0.2, 0.2]:
		for z in [-0.58, 0.55]:
			k.cyl(Vector3(x, 1.0, z), Vector3(x, 0.45, z + 0.04), 0.09, 0.07, body, 6)
			k.cyl(Vector3(x, 0.45, z + 0.04), Vector3(x, 0.08, z), 0.065, 0.06, body.darkened(0.1), 6)
			k.box(Vector3(x, 0.05, z + 0.02), Vector3(0.12, 0.1, 0.14), DARK)
	k.cyl(Vector3(0, 1.3, 0.62), Vector3(0, 1.8, 0.95), 0.2, 0.14, body, 8)
	k.taper(Vector3(0, 1.7, 0.95), Vector2(0.2, 0.26), Vector2(0.14, 0.18), 0.22, body, false, 0.0, Vector3(0, -0.06, 0.18))
	k.box(Vector3(0, 1.78, 1.24), Vector3(0.15, 0.16, 0.28), body.darkened(0.1))
	k.box(Vector3(0, 1.72, 0.72), Vector3(0.06, 0.4, 0.3), mane)
	k.cyl(Vector3(0, 1.25, -0.82), Vector3(0, 0.7, -1.05), 0.08, 0.03, mane, 5)
	# saddle cloth in team colour
	k.box(Vector3(0, 1.3, -0.05), Vector3(0.82, 0.5 if armour else 0.18, 0.75), cloth)
	if armour:
		k.box(Vector3(0, 1.78, 1.08), Vector3(0.2, 0.2, 0.36), STEEL)


# --- units by role ---------------------------------------------------------------------------

static func _worker(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	match race:
		"phyrexia":
			# hunched vat drone: porcelain shell, sinew limbs, claws
			k.gloss = true
			k.sphere(Vector3(0, 0.95, -0.05), Vector3(0.32, 0.36, 0.42), p.main, 9, 6)
			k.gloss = false
			k.sphere(Vector3(0, 0.82, 0.18), Vector3(0.24, 0.2, 0.2), p.trim, 7, 4)
			k.taper(Vector3(0, 0.95, 0.25), Vector2(0.18, 0.2), Vector2(0.06, 0.08), 0.35, p.main, false, 0.0, Vector3(0, 0.1, 0.25))
			k.box(Vector3(0, 1.12, 0.42), Vector3(0.12, 0.02, 0.03), p.glow, true)
			for side in [-1.0, 1.0]:
				k.cyl(Vector3(side * 0.18, 0.75, 0.0), Vector3(side * 0.25, 0.0, 0.08), 0.05, 0.03, p.trim, 5)
				k.cyl(Vector3(side * 0.25, 0.9, 0.2), Vector3(side * 0.3, 0.55, 0.5), 0.05, 0.03, p.dark, 5)
				k.cyl(Vector3(side * 0.3, 0.55, 0.5), Vector3(side * 0.22, 0.35, 0.62), 0.03, 0.0, p.metal, 5)
			k.box(Vector3(0, 1.0, -0.42), Vector3(0.3, 0.2, 0.1), T)
		"dominaria":
			_man(k, {"body": Color(0.55, 0.42, 0.28), "legs": Color(0.38, 0.3, 0.22), "head": "hat", "head_col": Color(0.85, 0.75, 0.45),
				"tabard": T, "belt": LEATHER, "r_hand": Vector3(-0.25, 1.05, 0.25)})
			k.cyl(Vector3(-0.25, 0.75, 0.15), Vector3(-0.25, 1.55, 0.3), 0.025, 0.025, WOOD, 5)
			k.box(Vector3(-0.25, 1.55, 0.32), Vector3(0.05, 0.05, 0.42), STEEL)
			k.box(Vector3(0.0, 1.05, -0.24), Vector3(0.3, 0.38, 0.18), LEATHER)
		"ravnica":
			_man(k, {"body": Color(0.32, 0.3, 0.33), "legs": Color(0.22, 0.2, 0.24), "head": "cap", "head_col": Color(0.25, 0.22, 0.3),
				"tabard": T, "belt": LEATHER, "r_hand": Vector3(-0.27, 1.1, 0.25)})
			k.cyl(Vector3(-0.27, 0.9, 0.2), Vector3(-0.27, 1.55, 0.32), 0.025, 0.025, WOOD, 5)
			k.box(Vector3(-0.27, 1.58, 0.32), Vector3(0.22, 0.1, 0.1), p.metal)
		"avishkar":
			# a servo: a small brass walking machine with one glowing eye
			k.gloss = true
			k.sphere(Vector3(0, 0.95, 0), Vector3(0.3, 0.26, 0.3), p.main, 10, 6)
			k.gloss = false
			k.ring(Vector3(0, 0.95, 0), Vector3.UP, 0.3, 0.03, p.metal.darkened(0.3), 12, 4)
			k.sphere(Vector3(0, 1.02, 0.27), Vector3(0.08, 0.08, 0.05), p.glow, 8, 4, true)
			k.box(Vector3(0, 1.2, 0), Vector3(0.12, 0.12, 0.12), T)
			k.cyl(Vector3(0, 1.26, 0), Vector3(0, 1.5, -0.05), 0.015, 0.015, p.metal, 4)
			k.sphere(Vector3(0, 1.52, -0.05), Vector3(0.04, 0.04, 0.04), p.glow, 6, 3, true)
			for a in 4:
				var ang := TAU * (a + 0.5) / 4.0
				var d := Vector3(cos(ang), 0, sin(ang))
				k.cyl(Vector3(0, 0.85, 0) + d * 0.2, Vector3(0, 0.6, 0) + d * 0.42, 0.04, 0.035, p.metal, 5)
				k.cyl(Vector3(0, 0.6, 0) + d * 0.42, Vector3(0, 0.0, 0) + d * 0.45, 0.035, 0.02, p.metal.darkened(0.2), 5)
			k.cyl(Vector3(0.22, 0.95, 0.15), Vector3(0.38, 0.8, 0.42), 0.03, 0.03, p.metal, 4)
			k.box(Vector3(0.4, 0.78, 0.45), Vector3(0.06, 0.06, 0.14), p.trim)


static func _soldier(k: MeshKit, race: String, role: String) -> void:
	var p := _pal(race)
	var rh := Vector3(-0.27, 1.0, 0.26)
	var lh := Vector3(0.27, 1.0, 0.22)
	match race:
		"phyrexia":
			var o := {"body": p.main, "legs": p.trim, "arms": p.trim, "head": "mask", "head_col": p.main, "boot": p.dark, "skin": p.trim,
				"tabard": T, "spikes": role != "archer", "pauldrons": p.main, "eye": p.glow}
			if role == "archer":
				# oil spitter: bloated sac on its back, nozzle arm
				o.pauldrons = null
				o.r_hand = Vector3(-0.2, 1.25, 0.35)
				_man(k, o)
				k.gloss = true
				k.sphere(Vector3(0, 1.2, -0.28), Vector3(0.3, 0.32, 0.25), Color(0.06, 0.06, 0.07), 9, 6)
				k.gloss = false
				k.cyl(Vector3(-0.2, 1.25, 0.35), Vector3(-0.2, 1.3, 0.75), 0.06, 0.03, p.metal, 6)
				k.sphere(Vector3(-0.2, 1.3, 0.76), Vector3(0.04, 0.04, 0.04), p.glow, 6, 3, true)
				return
			o.r_hand = rh
			o.l_hand = lh
			k.gloss = true
			_man(k, o)
			k.gloss = false
			if role == "infantry":
				_sword(k, rh, 1.0, p.metal, 0.95, 0.1)
				k.cyl(Vector3(0.27, 1.0, 0.22), Vector3(0.32, 0.5, 0.45), 0.04, 0.0, p.metal, 5)
			else:
				_spear(k, rh, 1.0, p.dark, p.trim, 2.6)
		"dominaria":
			var o := {"body": STEEL, "legs": Color(0.45, 0.45, 0.5), "arms": STEEL.darkened(0.1), "head": "helm", "head_col": STEEL,
				"tabard": T, "belt": LEATHER, "pauldrons": STEEL, "glove": LEATHER}
			match role:
				"infantry":
					o.r_hand = rh
					o.l_hand = lh
					_man(k, o)
					_sword(k, rh, 1.0, Color(0.85, 0.86, 0.9))
					_shield(k, Vector3(0.36, 1.05, 0.22), 1.0, T, p.glow.darkened(0.2), 0.3, true)
				"spear":
					o.head = "helm"
					o.pauldrons = null
					o.r_hand = rh
					_man(k, o)
					_spear(k, rh, 1.0, WOOD, STEEL, 3.0)
				"archer":
					o.body = Color(0.3, 0.42, 0.25)
					o.legs = Color(0.35, 0.3, 0.22)
					o.arms = o.body
					o.pauldrons = null
					o.head = "hood"
					o.head_col = Color(0.25, 0.36, 0.2)
					o.l_hand = Vector3(0.24, 1.2, 0.35)
					o.r_hand = Vector3(-0.1, 1.25, 0.05)
					_man(k, o)
					_bow(k, Vector3(0.24, 1.2, 0.35), 1.0, WOOD)
					k.cyl(Vector3(0.12, 1.0, -0.2), Vector3(0.2, 1.6, -0.25), 0.07, 0.07, LEATHER, 6)
		"ravnica":
			var o := {"body": Color(0.28, 0.22, 0.32), "legs": Color(0.2, 0.18, 0.22), "arms": Color(0.3, 0.24, 0.34), "head": "helm",
				"head_col": p.metal, "tabard": T, "belt": p.metal.darkened(0.3), "pauldrons": p.metal, "glove": DARK, "cape": true}
			match role:
				"infantry":
					o.r_hand = rh
					o.l_hand = lh
					_man(k, o)
					# a heavy mace and a round bronze shield
					k.cyl(rh + Vector3(0, -0.1, 0), rh + Vector3(0, 0.6, 0.15), 0.03, 0.03, DARK, 5)
					k.sphere(rh + Vector3(0, 0.66, 0.17), Vector3(0.1, 0.1, 0.1), p.metal, 7, 4)
					_shield(k, Vector3(0.36, 1.05, 0.22), 1.0, p.metal, T, 0.32)
				"spear":
					o.r_hand = rh
					o.pauldrons = null
					_man(k, o)
					_spear(k, rh, 1.0, DARK, p.metal, 2.8)
					k.box(rh + Vector3(0, 1.55, 0.3), Vector3(0.3, 0.06, 0.04), p.metal)
				"archer":
					o.head = "hat"
					o.head_col = DARK
					o.pauldrons = null
					o.l_hand = Vector3(0.12, 1.25, 0.32)
					o.r_hand = Vector3(-0.12, 1.2, 0.3)
					_man(k, o)
					k.box(Vector3(0, 1.25, 0.45), Vector3(0.1, 0.1, 0.55), WOOD)
					k.box(Vector3(0, 1.28, 0.65), Vector3(0.6, 0.04, 0.05), p.metal)
		"avishkar":
			var o := {"body": Color(0.9, 0.86, 0.76), "legs": p.trim.darkened(0.3), "arms": Color(0.88, 0.84, 0.74), "head": "turban",
				"head_col": Color(0.95, 0.92, 0.85), "tabard": T, "belt": p.main, "pauldrons": p.main, "glove": p.main, "eye": p.glow}
			match role:
				"spear":
					o.r_hand = rh
					_man(k, o)
					_spear(k, rh, 1.0, p.main, p.glow, 2.6, true)
					k.ring(rh + Vector3(0, 0.9, 0.12), Vector3(0, 1, 0.3), 0.06, 0.015, p.main, 8, 3)
					_shield(k, Vector3(0.36, 1.05, 0.22), 1.0, p.main, p.glow, 0.26)
				"archer":
					o.pauldrons = null
					o.l_hand = Vector3(0.1, 1.2, 0.4)
					o.r_hand = Vector3(-0.1, 1.15, 0.2)
					_man(k, o)
					_gun(k, Vector3(0, 1.15, 0.2), 1.0, p.main, p.glow, 1.0)
					k.cyl(Vector3(0, 1.05, -0.2), Vector3(0, 1.5, -0.22), 0.09, 0.09, p.trim, 8)


static func _caster(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	var lh := Vector3(0.27, 1.05, 0.22)
	match race:
		"dominaria":
			_man(k, {"robe": true, "body": Color(0.22, 0.3, 0.6), "legs": Color(0.18, 0.25, 0.55), "head": "hood", "head_col": Color(0.2, 0.28, 0.58),
				"l_hand": lh, "belt": Color(0.85, 0.7, 0.3), "tabard": T})
			_staff(k, lh, 1.0, WOOD, Color(0.5, 0.75, 1.0))
		"ravnica":
			_man(k, {"robe": true, "body": Color(0.3, 0.15, 0.38), "legs": Color(0.22, 0.1, 0.3), "head": "hood", "head_col": DARK,
				"l_hand": lh, "r_hand": Vector3(-0.2, 1.2, 0.35), "belt": p.metal, "tabard": T})
			k.sphere(Vector3(-0.2, 1.35, 0.38), Vector3(0.1, 0.1, 0.1), p.glow, 8, 5, true)
			k.ring(Vector3(-0.2, 1.35, 0.38), Vector3(0.3, 1, 0), 0.16, 0.012, p.glow, 12, 3, true)
		"avishkar":
			_man(k, {"body": Color(0.92, 0.88, 0.8), "legs": p.trim.darkened(0.4), "head": "turban", "head_col": p.trim, "tabard": T,
				"belt": p.main, "eye": p.glow, "r_hand": Vector3(-0.27, 1.05, 0.3)})
			# backpack apparatus with an aether tank
			k.box(Vector3(0, 1.2, -0.26), Vector3(0.34, 0.45, 0.18), p.main)
			k.cyl(Vector3(0.12, 1.0, -0.34), Vector3(0.12, 1.5, -0.34), 0.07, 0.07, p.glow, 8, true)
			k.cyl(Vector3(-0.12, 1.0, -0.34), Vector3(-0.12, 1.5, -0.34), 0.07, 0.07, p.glow, 8, true)
			k.cyl(Vector3(-0.27, 1.05, 0.3), Vector3(-0.27, 1.1, 0.75), 0.04, 0.02, p.main, 6)
			k.sphere(Vector3(-0.27, 1.1, 0.78), Vector3(0.05, 0.05, 0.05), p.glow, 6, 3, true)
		_:
			_man(k, {"robe": true, "body": p.main, "head": "hood", "head_col": p.dark, "tabard": T})


static func _champion(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	var s := 1.6
	match race:
		"phyrexia":
			var rh := Vector3(-0.27, 1.0, 0.26)
			k.gloss = true
			_man(k, {"s": s, "body": p.main, "legs": p.trim, "arms": p.main, "head": "mask", "head_col": p.main, "boot": p.dark, "skin": p.trim,
				"tabard": T, "spikes": true, "pauldrons": p.main, "eye": p.glow, "cape": true, "cape_col": p.dark, "r_hand": rh})
			k.gloss = false
			_sword(k, rh, s, p.metal, 1.3, 0.16)
			for a in 5:
				var ang := -0.9 + a * 0.45
				k.cyl(Vector3(sin(ang) * 0.12, 1.78, -0.05) * s, Vector3(sin(ang) * 0.3, 2.15, -0.12) * s, 0.025 * s, 0.0, p.dark, 4)
		"dominaria":
			var rh := Vector3(-0.27, 1.05, 0.28)
			_man(k, {"s": 1.45, "body": Color(0.95, 0.9, 0.75), "legs": Color(0.9, 0.85, 0.7), "arms": Color(0.95, 0.9, 0.75), "head": "bare",
				"skin": Color(0.95, 0.85, 0.75), "tabard": T, "belt": p.glow, "pauldrons": p.glow, "r_hand": rh, "robe": true})
			_sword(k, rh, 1.45, Color(1.0, 0.95, 0.7), 1.1, 0.1)
			k.sphere(Vector3(0, 2.6, -0.02), Vector3(0.24, 0.05, 0.24), p.glow, 10, 3, true)
			for side in [-1.0, 1.0]:
				_wing(k, Vector3(side * 0.15, 1.95, -0.25), side, 1.7, Color(1, 1, 0.97), Color(0.9, 0.92, 1.0), 0.9, 5)
		"ravnica":
			# a stone guardian golem with glowing runes
			var stone := Color(0.5, 0.48, 0.5)
			k.box(Vector3(0, 0.55, 0), Vector3(0.7, 1.1, 0.5) * Vector3(1, 1, 1), stone.darkened(0.15))
			k.taper(Vector3(0, 1.0, 0), Vector2(0.9, 0.6), Vector2(1.3, 0.8), 1.2, stone)
			k.box(Vector3(0, 2.3, 0.05), Vector3(0.45, 0.4, 0.45), stone)
			k.box(Vector3(0, 2.32, 0.28), Vector3(0.3, 0.06, 0.03), p.glow, true)
			k.box(Vector3(0, 1.6, 0.42), Vector3(0.5, 0.5, 0.04), T)
			for side in [-1.0, 1.0]:
				k.box(Vector3(side * 0.85, 1.6, 0), Vector3(0.45, 0.45, 0.5), stone.darkened(0.05))
				k.box(Vector3(side * 0.9, 0.95, 0.12), Vector3(0.35, 0.9, 0.38), stone)
				k.box(Vector3(side * 0.92, 0.42, 0.18), Vector3(0.45, 0.35, 0.45), stone.darkened(0.2))
				k.box(Vector3(side * 0.25, 0.3, 0), Vector3(0.38, 0.6, 0.45), stone.darkened(0.2))
				k.box(Vector3(side * 0.92, 1.25, 0.32), Vector3(0.08, 0.3, 0.03), p.glow, true)
		"avishkar":
			# a brass walking colossus
			k.gloss = true
			k.sphere(Vector3(0, 2.0, 0), Vector3(0.75, 0.6, 0.6), p.main, 12, 7)
			k.gloss = false
			k.ring(Vector3(0, 2.0, 0), Vector3.UP, 0.74, 0.05, p.metal.darkened(0.3), 16, 4)
			k.sphere(Vector3(0, 2.15, 0.55), Vector3(0.15, 0.15, 0.1), p.glow, 8, 5, true)
			k.box(Vector3(0, 2.55, 0), Vector3(0.4, 0.2, 0.4), T)
			for side in [-1.0, 1.0]:
				k.cyl(Vector3(side * 0.35, 1.6, 0), Vector3(side * 0.5, 0.75, 0.1), 0.14, 0.11, p.metal, 8)
				k.cyl(Vector3(side * 0.5, 0.75, 0.1), Vector3(side * 0.55, 0.05, 0.0), 0.11, 0.16, p.metal.darkened(0.2), 8)
				k.cyl(Vector3(side * 0.7, 2.1, 0), Vector3(side * 1.05, 1.4, 0.2), 0.12, 0.1, p.metal, 8)
				k.box(Vector3(side * 1.1, 1.2, 0.3), Vector3(0.28, 0.4, 0.3), p.main)
				k.cyl(Vector3(side * 0.3, 2.4, -0.35), Vector3(side * 0.3, 3.0, -0.4), 0.08, 0.05, p.glow, 6, true)


static func _cavalry(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	match race:
		"dominaria":
			_horse(k, Color(0.9, 0.88, 0.84), Color(0.75, 0.72, 0.65), T, true)
			k.xf = Transform3D(Basis(), Vector3(0, 0.75, -0.05))
			_man(k, {"body": STEEL, "legs": STEEL.darkened(0.2), "head": "plume", "head_col": STEEL, "tabard": T, "pauldrons": STEEL,
				"r_hand": Vector3(-0.3, 1.1, 0.25), "l_hand": Vector3(0.3, 1.1, 0.25)})
			_spear(k, Vector3(-0.3, 1.1, 0.25), 1.0, Color(0.85, 0.8, 0.7), STEEL, 3.0)
			_shield(k, Vector3(0.4, 1.15, 0.15), 1.0, T, p.glow, 0.28, true)
			k.xf = Transform3D.IDENTITY
		"phyrexia":
			# a ravager hound: a big porcelain beast with exposed sinew and a spiked spine
			k.gloss = true
			k.sphere(Vector3(0, 1.0, 0), Vector3(0.42, 0.42, 0.9), p.main, 10, 6)
			k.sphere(Vector3(0, 1.1, 0.95), Vector3(0.26, 0.24, 0.4), p.main, 8, 5)
			k.gloss = false
			k.box(Vector3(0, 0.95, 1.3), Vector3(0.3, 0.06, 0.2), p.trim)
			k.box(Vector3(0, 1.15, 1.25), Vector3(0.2, 0.03, 0.05), p.glow, true)
			k.sphere(Vector3(0, 0.9, 0.1), Vector3(0.35, 0.3, 0.7), p.trim, 8, 5)
			for x in [-0.28, 0.28]:
				for z in [-0.6, 0.55]:
					k.cyl(Vector3(x, 0.95, z), Vector3(x * 1.3, 0.5, z + 0.15), 0.1, 0.07, p.trim, 6)
					k.cyl(Vector3(x * 1.3, 0.5, z + 0.15), Vector3(x * 1.2, 0.0, z + 0.05), 0.07, 0.03, p.main, 6)
			for i in 6:
				var z := 0.7 - i * 0.28
				k.cyl(Vector3(0, 1.35, z), Vector3(0, 1.75 - i * 0.03, z - 0.15), 0.06, 0.0, p.dark, 5)
			k.box(Vector3(0, 1.3, -0.2), Vector3(0.5, 0.1, 0.6), T)
			k.cyl(Vector3(0, 1.0, -0.85), Vector3(0, 1.2, -1.4), 0.07, 0.02, p.trim, 5)
		"avishkar":
			# an aethercycle with its rider
			k.ring(Vector3(0, 0.42, 0.75), Vector3.RIGHT, 0.36, 0.08, DARK, 14, 5)
			k.ring(Vector3(0, 0.42, -0.75), Vector3.RIGHT, 0.36, 0.08, DARK, 14, 5)
			k.ring(Vector3(0, 0.42, 0.75), Vector3.RIGHT, 0.26, 0.03, p.glow, 14, 3, true)
			k.ring(Vector3(0, 0.42, -0.75), Vector3.RIGHT, 0.26, 0.03, p.glow, 14, 3, true)
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 0.6, -0.95), 0.12, 0.1), _ring_pts(Vector3(0, 0.75, -0.3), 0.26, 0.2), _ring_pts(Vector3(0, 0.78, 0.35), 0.24, 0.18),
				_ring_pts(Vector3(0, 0.62, 1.0), 0.08, 0.07)], p.main)
			k.gloss = false
			k.box(Vector3(0, 0.9, -0.2), Vector3(0.36, 0.08, 0.5), T)
			k.cyl(Vector3(0.18, 0.6, -0.7), Vector3(0.22, 0.6, -1.1), 0.06, 0.08, p.metal, 6)
			k.cyl(Vector3(-0.18, 0.6, -0.7), Vector3(-0.22, 0.6, -1.1), 0.06, 0.08, p.metal, 6)
			k.sphere(Vector3(0.22, 0.6, -1.12), Vector3(0.05, 0.05, 0.03), p.glow, 6, 3, true)
			k.sphere(Vector3(-0.22, 0.6, -1.12), Vector3(0.05, 0.05, 0.03), p.glow, 6, 3, true)
			k.xf = Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.05, -0.15))
			_man(k, {"body": Color(0.9, 0.86, 0.76), "legs": p.trim.darkened(0.3), "head": "helm", "head_col": p.main, "tabard": T,
				"r_hand": Vector3(-0.25, 1.0, 0.55), "l_hand": Vector3(0.25, 1.0, 0.55)})
			k.xf = Transform3D.IDENTITY
			k.cyl(Vector3(-0.3, 1.1, 0.55), Vector3(0.3, 1.1, 0.55), 0.025, 0.025, p.metal, 5)
		_:
			_horse(k, LEATHER, DARK, T)


static func _flyer(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	match race:
		"dominaria":
			_horse(k, Color(0.97, 0.97, 0.95), Color(0.9, 0.9, 0.95), T)
			for side in [-1.0, 1.0]:
				_wing(k, Vector3(side * 0.3, 1.4, 0.2), side, 1.6, Color(1, 1, 1), Color(0.85, 0.88, 0.95), 0.7, 5)
			k.xf = Transform3D(Basis(), Vector3(0, 0.75, -0.05))
			_man(k, {"body": STEEL, "head": "helm", "head_col": STEEL, "tabard": T, "r_hand": Vector3(-0.3, 1.1, 0.25)})
			_spear(k, Vector3(-0.3, 1.1, 0.25), 1.0, WOOD, STEEL, 2.2)
			k.xf = Transform3D.IDENTITY
		"phyrexia":
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 1.0, -1.6), 0.04, 0.04), _ring_pts(Vector3(0, 1.1, -0.6), 0.25, 0.22), _ring_pts(Vector3(0, 1.15, 0.2), 0.32, 0.3),
				_ring_pts(Vector3(0, 1.3, 0.9), 0.18, 0.16), _ring_pts(Vector3(0, 1.35, 1.4), 0.12, 0.1)], p.main)
			k.gloss = false
			k.box(Vector3(0, 1.4, 1.42), Vector3(0.16, 0.025, 0.05), p.glow, true)
			k.sphere(Vector3(0, 1.0, 0.1), Vector3(0.25, 0.2, 0.5), p.trim, 8, 4)
			k.box(Vector3(0, 1.4, 0.1), Vector3(0.3, 0.08, 0.5), T)
			for side in [-1.0, 1.0]:
				_wing(k, Vector3(side * 0.25, 1.25, 0.3), side, 2.0, p.dark, p.trim, 0.6, 5)
		"ravnica":
			# a skyknight on a winged beast
			k.sphere(Vector3(0, 1.1, 0), Vector3(0.34, 0.34, 0.75), Color(0.55, 0.42, 0.28), 9, 6)
			k.sphere(Vector3(0, 1.4, 0.8), Vector3(0.2, 0.22, 0.25), Color(0.85, 0.82, 0.75), 8, 5)
			k.cyl(Vector3(0, 1.38, 1.0), Vector3(0, 1.3, 1.25), 0.07, 0.0, Color(0.9, 0.7, 0.2), 5)
			for x in [-0.18, 0.18]:
				for z in [-0.4, 0.45]:
					k.cyl(Vector3(x, 0.95, z), Vector3(x, 0.45, z + 0.1), 0.07, 0.05, Color(0.5, 0.38, 0.25), 5)
			for side in [-1.0, 1.0]:
				_wing(k, Vector3(side * 0.25, 1.35, 0.2), side, 1.7, Color(0.6, 0.5, 0.4), Color(0.85, 0.8, 0.7), 0.7, 5)
			k.box(Vector3(0, 1.3, -0.05), Vector3(0.75, 0.15, 0.6), T)
			k.xf = Transform3D(Basis(), Vector3(0, 0.6, -0.1))
			_man(k, {"body": Color(0.28, 0.22, 0.32), "head": "helm", "head_col": p.metal, "tabard": T, "cape": true, "r_hand": Vector3(-0.3, 1.1, 0.25)})
			_spear(k, Vector3(-0.3, 1.1, 0.25), 1.0, DARK, p.metal, 2.4)
			k.xf = Transform3D.IDENTITY
		"avishkar":
			# a thopter: brass body and filigree wings rimmed with aether
			k.gloss = true
			k.sphere(Vector3(0, 1.1, 0), Vector3(0.28, 0.24, 0.6), p.main, 10, 6)
			k.gloss = false
			k.sphere(Vector3(0, 1.15, 0.55), Vector3(0.1, 0.1, 0.06), p.glow, 7, 4, true)
			k.box(Vector3(0, 1.32, -0.1), Vector3(0.18, 0.1, 0.4), T)
			k.cyl(Vector3(0, 1.05, -0.5), Vector3(0, 1.1, -1.2), 0.05, 0.02, p.metal, 5)
			k.box(Vector3(0, 1.15, -1.2), Vector3(0.5, 0.03, 0.2), p.main)
			for side in [-1.0, 1.0]:
				for w in 2:
					var root := Vector3(side * 0.2, 1.2, 0.15 - w * 0.35)
					var tip := root + Vector3(side * 1.4, 0.25 - w * 0.15, -0.15)
					k.tri(root, tip, root + Vector3(side * 0.6, 0.05, -0.35), Color(0.85, 0.95, 1.0, 1.0).lerp(p.main, 0.4))
					k.tri(root, root + Vector3(side * 0.6, 0.05, -0.35), tip, Color(0.85, 0.95, 1.0).lerp(p.main, 0.4))
					k.cyl(root, tip, 0.02, 0.01, p.glow, 4, true)
			k.cyl(Vector3(0, 0.95, -0.15), Vector3(0, 0.75, 0.25), 0.02, 0.02, p.metal, 4)


static func _siege(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	match race:
		"phyrexia":
			# gorger engine: a crawling furnace with a toothed maw
			k.gloss = true
			k.box(Vector3(0, 1.0, 0), Vector3(1.3, 0.9, 1.9), p.main)
			k.gloss = false
			k.box(Vector3(0, 1.0, 1.0), Vector3(1.0, 0.6, 0.15), p.trim)
			for i in 6:
				k.cyl(Vector3(-0.4 + i * 0.16, 1.3, 1.02), Vector3(-0.4 + i * 0.16, 1.1, 1.1), 0.04, 0.0, p.main, 4)
			k.sphere(Vector3(0, 1.0, 1.05), Vector3(0.3, 0.2, 0.05), p.glow, 8, 3, true)
			k.box(Vector3(0, 1.5, -0.2), Vector3(0.9, 0.2, 1.1), T)
			for i in 3:
				var z := -0.6 + i * 0.6
				for side in [-1.0, 1.0]:
					k.cyl(Vector3(side * 0.6, 0.9, z), Vector3(side * 1.1, 0.6, z + 0.2), 0.08, 0.06, p.dark, 5)
					k.cyl(Vector3(side * 1.1, 0.6, z + 0.2), Vector3(side * 1.15, 0.0, z + 0.25), 0.06, 0.02, p.metal, 5)
			k.cyl(Vector3(0.35, 1.45, -0.6), Vector3(0.4, 2.2, -0.75), 0.12, 0.08, p.dark, 6)
			k.cyl(Vector3(-0.35, 1.45, -0.6), Vector3(-0.4, 2.0, -0.75), 0.1, 0.06, p.dark, 6)
		"ravnica":
			# spark cannon: a cart carrying a coil and a crackling orb
			for side in [-1.0, 1.0]:
				for z in [-0.55, 0.55]:
					k.ring(Vector3(side * 0.62, 0.38, z), Vector3.RIGHT, 0.33, 0.06, WOOD, 12, 4)
			k.box(Vector3(0, 0.6, 0), Vector3(1.1, 0.2, 1.6), WOOD.darkened(0.1))
			k.box(Vector3(0, 0.72, 0), Vector3(1.0, 0.05, 1.5), T)
			k.cyl(Vector3(0, 0.75, -0.2), Vector3(0, 1.7, 0.1), 0.25, 0.16, p.metal, 10)
			for i in 6:
				k.ring(Vector3(0, 0.9 + i * 0.13, -0.15 + i * 0.04), Vector3(0, 1, 0.3), 0.27 - i * 0.015, 0.025, Color(0.75, 0.45, 0.2), 12, 3)
			k.sphere(Vector3(0, 1.85, 0.15), Vector3(0.2, 0.2, 0.2), p.glow, 9, 6, true)
			k.cyl(Vector3(0, 1.0, 0.3), Vector3(0, 1.2, 1.1), 0.1, 0.07, p.metal.darkened(0.3), 8)
		"avishkar":
			# aether cannon: a brass barrel on a wheeled carriage with glowing tanks
			for side in [-1.0, 1.0]:
				k.ring(Vector3(side * 0.62, 0.48, -0.2), Vector3.RIGHT, 0.45, 0.07, p.metal, 14, 4)
				k.ring(Vector3(side * 0.62, 0.48, -0.2), Vector3.RIGHT, 0.2, 0.04, p.glow, 10, 3, true)
			k.box(Vector3(0, 0.6, -0.3), Vector3(0.9, 0.3, 1.3), p.dark)
			k.box(Vector3(0, 0.78, -0.4), Vector3(0.85, 0.06, 1.1), T)
			k.gloss = true
			k.cyl(Vector3(0, 0.95, -0.6), Vector3(0, 1.35, 1.2), 0.3, 0.2, p.main, 12)
			k.gloss = false
			k.ring(Vector3(0, 1.32, 1.12), Vector3(0, 0.22, 1).normalized(), 0.22, 0.05, p.metal.darkened(0.3), 12, 4)
			k.cyl(Vector3(0.3, 0.9, -0.9), Vector3(0.3, 1.4, -0.9), 0.12, 0.12, p.glow, 8, true)
			k.cyl(Vector3(-0.3, 0.9, -0.9), Vector3(-0.3, 1.4, -0.9), 0.12, 0.12, p.glow, 8, true)
		_:
			k.box(Vector3(0, 0.6, 0), Vector3(1, 0.4, 1.5), WOOD)


static func _ring_pts(c: Vector3, rx: float, ry: float, n := 8) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector3(cos(a) * rx, sin(a) * ry, 0))
	return out


# --- buildings ------------------------------------------------------------------------------

static func building(race: String, role: String) -> ArrayMesh:
	var key := "b:%s:%s" % [race, role]
	if _cache.has(key):
		return _cache[key]
	var k := MeshKit.new()
	var w: float = Data.BUILDINGS[role].size * Data.CELL - 0.5
	match race:
		"dominaria":
			_dom_building(k, role, w)
		"ravnica":
			_rav_building(k, role, w)
		"avishkar":
			_avi_building(k, role, w)
		"phyrexia":
			_phy_building(k, role, w)
	var m := k.commit(null, _mats())
	_cache[key] = m
	return m


static func _banner(k: MeshKit, at: Vector3, h: float, pole := WOOD) -> void:
	k.cyl(at, at + Vector3(0, h, 0), 0.05, 0.04, pole, 5)
	k.box(at + Vector3(0.3, h - 0.35, 0), Vector3(0.55, 0.6, 0.03), T)
	k.sphere(at + Vector3(0, h + 0.05, 0), Vector3(0.07, 0.07, 0.07), Game.GOLD, 6, 3)


static func _gable(k: MeshKit, c: Vector3, w: float, d: float, h: float, col: Color) -> void:
	var hw := w * 0.5 + 0.15
	var hd := d * 0.5 + 0.15
	var a := c + Vector3(-hw, 0, -hd)
	var b := c + Vector3(hw, 0, -hd)
	var cc := c + Vector3(hw, 0, hd)
	var dd := c + Vector3(-hw, 0, hd)
	var r0 := c + Vector3(-hw, h, 0)
	var r1 := c + Vector3(hw, h, 0)
	k.quad(dd, cc, r1, r0, col)
	k.quad(b, a, r0, r1, col.darkened(0.12))
	k.tri(a, dd, r0, col.darkened(0.25))
	k.tri(cc, b, r1, col.darkened(0.25))


static func _windows(k: MeshKit, c: Vector3, w: float, d: float, y: float, n: int, col: Color, glow := true, tall := 0.4) -> void:
	for i in n:
		var x := -w * 0.5 + w * (i + 0.5) / n
		k.box(c + Vector3(x, y, d * 0.5 + 0.02), Vector3(0.22, tall, 0.04), col, glow)
		k.box(c + Vector3(x, y, -d * 0.5 - 0.02), Vector3(0.22, tall, 0.04), col, glow)


static func _crenels(k: MeshKit, c: Vector3, w: float, d: float, col: Color) -> void:
	var n := int(w / 0.7)
	for i in n:
		var x := -w * 0.5 + w * (i + 0.5) / n
		k.box(c + Vector3(x, 0.2, d * 0.5), Vector3(0.35, 0.4, 0.25), col)
		k.box(c + Vector3(x, 0.2, -d * 0.5), Vector3(0.35, 0.4, 0.25), col)
	n = int(d / 0.7)
	for i in n:
		var z := -d * 0.5 + d * (i + 0.5) / n
		k.box(c + Vector3(w * 0.5, 0.2, z), Vector3(0.25, 0.4, 0.35), col)
		k.box(c + Vector3(-w * 0.5, 0.2, z), Vector3(0.25, 0.4, 0.35), col)


static func _round_tower(k: MeshKit, c: Vector3, r: float, h: float, wall: Color, roof: Color, roof_h: float) -> void:
	k.cyl(c, c + Vector3(0, h, 0), r, r * 0.92, wall, 12)
	k.cyl(c + Vector3(0, h, 0), c + Vector3(0, h + roof_h, 0), r * 1.15, 0.0, roof, 12)


static func _dome(k: MeshKit, c: Vector3, r: float, col: Color, onion := false) -> void:
	if onion:
		k.sphere(c + Vector3(0, r * 0.7, 0), Vector3(r, r * 0.95, r), col, 12, 7)
		k.cyl(c + Vector3(0, r * 1.5, 0), c + Vector3(0, r * 2.3, 0), r * 0.3, 0.0, col, 8)
	else:
		k.sphere(c, Vector3(r, r * 0.8, r), col, 12, 6)


static func _dom_building(k: MeshKit, role: String, w: float) -> void:
	var stone := Color(0.72, 0.7, 0.66)
	var plaster := Color(0.9, 0.86, 0.76)
	var roof := Color(0.3, 0.36, 0.52)
	var thatch := Color(0.72, 0.6, 0.32)
	var win := Color(1.0, 0.85, 0.5)
	match role:
		"hall":
			k.box(Vector3(0, 1.2, 0), Vector3(w, 2.4, w), stone)
			_crenels(k, Vector3(0, 2.4, 0), w, w, stone)
			k.box(Vector3(0, 3.3, 0), Vector3(w * 0.5, 4.0, w * 0.5), stone.lightened(0.05))
			_crenels(k, Vector3(0, 5.3, 0), w * 0.5, w * 0.5, stone)
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					_round_tower(k, Vector3(x * w * 0.45, 0, z * w * 0.45), 0.75, 3.4, stone, roof, 1.4)
			k.box(Vector3(0, 0.8, w * 0.5 + 0.02), Vector3(1.2, 1.6, 0.1), WOOD.darkened(0.3))
			_windows(k, Vector3(0, 0, 0), w * 0.5, w * 0.5, 4.2, 2, win)
			_banner(k, Vector3(0, 5.3, 0), 2.0)
		"house":
			k.box(Vector3(0, 0.25, 0), Vector3(w, 0.5, w * 0.85), stone)
			k.box(Vector3(0, 1.1, 0), Vector3(w * 0.95, 1.2, w * 0.8), plaster)
			for x in [-0.5, 0.5]:
				k.box(Vector3(x * w * 0.9, 1.1, w * 0.4 + 0.01), Vector3(0.12, 1.2, 0.04), WOOD)
			_gable(k, Vector3(0, 1.7, 0), w * 0.95, w * 0.8, 1.2, thatch)
			k.box(Vector3(0, 0.75, w * 0.4 + 0.02), Vector3(0.5, 0.9, 0.05), WOOD.darkened(0.3))
			k.box(Vector3(w * 0.25, 2.2, -0.2), Vector3(0.3, 1.0, 0.3), stone)
			k.box(Vector3(-w * 0.25, 1.15, w * 0.4 + 0.02), Vector3(0.3, 0.3, 0.04), T)
		"depot":
			k.box(Vector3(0, 0.9, 0), Vector3(w * 0.9, 1.8, w * 0.7), Color(0.55, 0.42, 0.28))
			_gable(k, Vector3(0, 1.8, 0), w * 0.9, w * 0.7, 0.9, roof)
			for i in 3:
				k.box(Vector3(-w * 0.3 + i * 0.6, 0.3, w * 0.42), Vector3(0.5, 0.5, 0.5), WOOD)
			k.box(Vector3(w * 0.3, 0.25, w * 0.42), Vector3(0.4, 0.4, 0.4), Color(0.95, 0.8, 0.3))
			_banner(k, Vector3(-w * 0.45, 0, -w * 0.35), 2.6)
		"barracks":
			k.box(Vector3(0, 0.4, 0), Vector3(w, 0.8, w * 0.75), stone)
			k.box(Vector3(0, 1.5, 0), Vector3(w * 0.96, 1.4, w * 0.7), plaster)
			_gable(k, Vector3(0, 2.2, 0), w * 0.96, w * 0.7, 1.6, roof)
			for i in 4:
				k.box(Vector3(-w * 0.45 + i * w * 0.3, 1.5, w * 0.35 + 0.01), Vector3(0.14, 1.4, 0.04), WOOD)
			k.box(Vector3(0, 1.0, w * 0.35 + 0.02), Vector3(1.1, 1.6, 0.06), WOOD.darkened(0.3))
			_banner(k, Vector3(w * 0.4, 0, w * 0.45), 3.4)
			_banner(k, Vector3(-w * 0.4, 0, w * 0.45), 3.4)
			for i in 3:
				k.cyl(Vector3(-w * 0.45, 0, -w * 0.45 + i * 0.3), Vector3(-w * 0.45, 1.6, -w * 0.4 + i * 0.3), 0.03, 0.03, WOOD, 4)
		"forge":
			k.box(Vector3(0, 1.1, 0), Vector3(w * 0.9, 2.2, w * 0.75), stone.darkened(0.1))
			_gable(k, Vector3(0, 2.2, 0), w * 0.9, w * 0.75, 1.0, Color(0.5, 0.3, 0.22))
			k.box(Vector3(w * 0.3, 3.0, -w * 0.15), Vector3(0.7, 2.6, 0.7), stone.darkened(0.2))
			k.box(Vector3(w * 0.3, 4.35, -w * 0.15), Vector3(0.5, 0.15, 0.5), Color(1.0, 0.5, 0.15), true)
			k.box(Vector3(0, 0.9, w * 0.375 + 0.02), Vector3(1.4, 1.2, 0.05), Color(1.0, 0.45, 0.1), true)
			k.box(Vector3(-w * 0.3, 0.35, w * 0.5), Vector3(0.6, 0.3, 0.3), DARK)
			k.box(Vector3(-w * 0.3, 0.12, w * 0.5), Vector3(0.3, 0.25, 0.2), DARK)
			_banner(k, Vector3(-w * 0.45, 0, -w * 0.4), 3.0)
		"tower":
			_round_tower(k, Vector3(0, 0, 0), w * 0.38, 5.5, stone, roof, 2.2)
			k.ring(Vector3(0, 5.3, 0), Vector3.UP, w * 0.42, 0.18, stone.darkened(0.1), 12, 4)
			for i in 3:
				k.box(Vector3(0, 2.0 + i * 1.3, w * 0.38), Vector3(0.12, 0.45, 0.06), DARK)
			_banner(k, Vector3(0, 7.6, 0), 1.2)
		"stable":
			k.box(Vector3(0, 1.1, -w * 0.12), Vector3(w * 0.9, 2.2, w * 0.55), WOOD)
			_gable(k, Vector3(0, 2.2, -w * 0.12), w * 0.9, w * 0.55, 1.3, thatch)
			for i in 3:
				k.box(Vector3(-w * 0.3 + i * w * 0.3, 0.8, w * 0.16 + 0.01), Vector3(0.8, 1.4, 0.05), DARK)
			for i in 6:
				var x := -w * 0.45 + i * w * 0.18
				k.box(Vector3(x, 0.5, w * 0.45), Vector3(0.1, 1.0, 0.1), WOOD.darkened(0.2))
			k.box(Vector3(0, 0.8, w * 0.45), Vector3(w * 0.9, 0.08, 0.06), WOOD)
			k.box(Vector3(0, 0.45, w * 0.45), Vector3(w * 0.9, 0.08, 0.06), WOOD)
			_banner(k, Vector3(w * 0.45, 0, -w * 0.4), 3.2)
		"sanctum":
			# Tolarian academy: a round tower with a blue dome and a glowing lens
			k.box(Vector3(0, 0.9, 0), Vector3(w * 0.9, 1.8, w * 0.9), stone)
			_round_tower(k, Vector3(0, 1.8, 0), w * 0.3, 3.5, plaster, roof, 0.0)
			_dome(k, Vector3(0, 5.3, 0), w * 0.32, Color(0.3, 0.45, 0.8))
			k.sphere(Vector3(0, 6.3, 0), Vector3(0.35, 0.35, 0.35), Color(0.5, 0.8, 1.0), 10, 6, true)
			k.ring(Vector3(0, 6.3, 0), Vector3(0.3, 1, 0.2), 0.7, 0.04, Game.GOLD, 16, 3)
			_windows(k, Vector3(0, 0, 0), w * 0.9, w * 0.9, 1.0, 3, Color(0.6, 0.85, 1.0))
			_banner(k, Vector3(w * 0.42, 1.8, w * 0.42), 2.0)
		"workshop":
			k.box(Vector3(0, 1.2, 0), Vector3(w, 2.4, w * 0.8), WOOD)
			_gable(k, Vector3(0, 2.4, 0), w, w * 0.8, 1.2, roof)


static func _rav_building(k: MeshKit, role: String, w: float) -> void:
	var stone := Color(0.42, 0.38, 0.42)
	var stone2 := Color(0.55, 0.5, 0.52)
	var roof := Color(0.22, 0.18, 0.28)
	var bronze := Color(0.75, 0.55, 0.3)
	var win := Color(1.0, 0.78, 0.45)
	match role:
		"hall":
			# guildhall: a cathedral block with a tall central spire and flying buttresses
			k.box(Vector3(0, 2.0, 0), Vector3(w * 0.8, 4.0, w * 0.9), stone)
			_gable(k, Vector3(0, 4.0, 0), w * 0.8, w * 0.9, 2.0, roof)
			k.box(Vector3(0, 4.0, w * 0.2), Vector3(1.6, 8.0, 1.6), stone2)
			k.cyl(Vector3(0, 8.0, w * 0.2), Vector3(0, 11.5, w * 0.2), 1.25, 0.0, roof, 8)
			k.sphere(Vector3(0, 11.6, w * 0.2), Vector3(0.18, 0.18, 0.18), bronze, 6, 3)
			for x in [-1.0, 1.0]:
				for z in [-0.3, 0.1, 0.4]:
					k.box(Vector3(x * w * 0.47, 1.6, z * w), Vector3(0.4, 3.2, 0.5), stone2)
					k.cyl(Vector3(x * w * 0.47, 3.2, z * w), Vector3(x * w * 0.47, 4.2, z * w), 0.3, 0.0, roof, 6)
			_windows(k, Vector3(0, 0, 0), w * 0.8, w * 0.9, 2.4, 3, win, true, 1.2)
			k.box(Vector3(0, 6.0, w * 0.2 + 0.82), Vector3(0.8, 0.8, 0.05), win, true)
			k.box(Vector3(0, 1.2, w * 0.45 + 0.02), Vector3(1.0, 2.2, 0.08), DARK)
			_banner(k, Vector3(w * 0.42, 0, w * 0.5), 3.6, DARK)
			_banner(k, Vector3(-w * 0.42, 0, w * 0.5), 3.6, DARK)
		"house":
			k.box(Vector3(0, 1.8, 0), Vector3(w * 0.7, 3.6, w * 0.7), stone2)
			_gable(k, Vector3(0, 3.6, 0), w * 0.7, w * 0.7, 1.3, roof)
			_windows(k, Vector3(0, 0, 0), w * 0.7, w * 0.7, 1.4, 2, win)
			_windows(k, Vector3(0, 0, 0), w * 0.7, w * 0.7, 2.6, 2, win)
			k.box(Vector3(0, 3.0, w * 0.35 + 0.05), Vector3(w * 0.5, 0.25, 0.08), T)
		"depot":
			k.box(Vector3(0, 1.0, 0), Vector3(w * 0.85, 2.0, w * 0.85), stone2)
			_dome(k, Vector3(0, 2.0, 0), w * 0.36, bronze)
			k.box(Vector3(0, 0.7, w * 0.42 + 0.02), Vector3(0.7, 1.2, 0.06), DARK)
			k.box(Vector3(0, 1.75, w * 0.42 + 0.03), Vector3(w * 0.6, 0.2, 0.05), T)
		"barracks":
			k.box(Vector3(0, 1.4, 0), Vector3(w, 2.8, w * 0.8), stone)
			_crenels(k, Vector3(0, 2.8, 0), w, w * 0.8, stone)
			for x in [-1.0, 1.0]:
				k.box(Vector3(x * w * 0.4, 2.2, w * 0.4), Vector3(0.9, 4.4, 0.9), stone2)
				k.cyl(Vector3(x * w * 0.4, 4.4, w * 0.4), Vector3(x * w * 0.4, 6.0, w * 0.4), 0.65, 0.0, roof, 6)
			k.box(Vector3(0, 1.0, w * 0.4 + 0.03), Vector3(1.3, 2.0, 0.08), DARK)
			k.box(Vector3(0, 2.2, w * 0.4 + 0.05), Vector3(1.6, 0.4, 0.06), T)
			_banner(k, Vector3(0, 2.8, 0), 2.4, DARK)
		"forge":
			k.box(Vector3(0, 1.3, 0), Vector3(w * 0.9, 2.6, w * 0.8), stone)
			_gable(k, Vector3(0, 2.6, 0), w * 0.9, w * 0.8, 1.2, roof)
			for x in [-0.25, 0.25]:
				k.cyl(Vector3(x * w, 2.5, -w * 0.2), Vector3(x * w, 5.0, -w * 0.2), 0.3, 0.25, DARK, 8)
				k.cyl(Vector3(x * w, 5.0, -w * 0.2), Vector3(x * w, 5.1, -w * 0.2), 0.27, 0.27, Color(1.0, 0.5, 0.15), 8, true)
			k.box(Vector3(0, 0.9, w * 0.4 + 0.02), Vector3(1.6, 1.4, 0.05), Color(1.0, 0.45, 0.1), true)
			k.box(Vector3(0, 1.85, w * 0.4 + 0.03), Vector3(1.8, 0.25, 0.05), T)
		"tower":
			k.box(Vector3(0, 3.0, 0), Vector3(w * 0.7, 6.0, w * 0.7), stone2)
			k.box(Vector3(0, 6.3, 0), Vector3(w * 0.8, 0.6, w * 0.8), stone)
			k.cyl(Vector3(0, 6.6, 0), Vector3(0, 9.0, 0), w * 0.5, 0.0, roof, 4)
			k.sphere(Vector3(0, 5.6, w * 0.36), Vector3(0.3, 0.3, 0.06), bronze, 8, 4)
			k.box(Vector3(0, 4.6, w * 0.36), Vector3(0.6, 0.3, 0.06), T)
		"workshop":
			# spark foundry: a squat block with a crackling coil tower
			k.box(Vector3(0, 1.3, 0), Vector3(w, 2.6, w * 0.85), stone)
			_gable(k, Vector3(0, 2.6, 0), w, w * 0.85, 1.0, roof)
			k.cyl(Vector3(w * 0.25, 2.6, -w * 0.15), Vector3(w * 0.25, 5.6, -w * 0.15), 0.5, 0.3, bronze, 10)
			for i in 5:
				k.ring(Vector3(w * 0.25, 3.0 + i * 0.5, -w * 0.15), Vector3.UP, 0.5 - i * 0.04, 0.05, Color(0.8, 0.5, 0.2), 12, 3)
			k.sphere(Vector3(w * 0.25, 6.0, -w * 0.15), Vector3(0.45, 0.45, 0.45), Color(0.55, 0.75, 1.0), 10, 6, true)
			k.box(Vector3(0, 1.0, w * 0.43), Vector3(1.4, 2.0, 0.06), DARK)
			k.box(Vector3(-w * 0.3, 2.0, w * 0.43 + 0.02), Vector3(0.8, 0.3, 0.05), T)
		"sanctum":
			# guild spire: a very tall needle with glowing windows
			k.box(Vector3(0, 1.0, 0), Vector3(w * 0.9, 2.0, w * 0.9), stone)
			k.taper(Vector3(0, 2.0, 0), Vector2(w * 0.55, w * 0.55), Vector2(w * 0.3, w * 0.3), 6.5, stone2)
			k.cyl(Vector3(0, 8.5, 0), Vector3(0, 12.0, 0), w * 0.24, 0.0, roof, 6)
			for i in 4:
				k.box(Vector3(0, 3.0 + i * 1.4, w * 0.2 + 0.1), Vector3(0.3, 0.8, 0.05), Color(0.6, 0.8, 1.0), true)
			k.sphere(Vector3(0, 9.0, 0), Vector3(0.5, 0.5, 0.5), Color(0.6, 0.8, 1.0), 10, 6, true)
			_banner(k, Vector3(w * 0.42, 2.0, w * 0.42), 2.4, DARK)
			k.box(Vector3(0, 1.6, w * 0.45 + 0.02), Vector3(1.2, 0.3, 0.05), T)
		"stable":
			k.box(Vector3(0, 1.2, 0), Vector3(w, 2.4, w * 0.8), stone)
			_gable(k, Vector3(0, 2.4, 0), w, w * 0.8, 1.2, roof)


static func _avi_building(k: MeshKit, role: String, w: float) -> void:
	var cream := Color(0.93, 0.88, 0.78)
	var brass := Color(0.85, 0.64, 0.32)
	var teal := Color(0.12, 0.6, 0.62)
	var glow := Color(0.35, 0.95, 1.0)
	match role:
		"hall":
			# consulate: a white palace with a great brass dome and four minarets
			k.box(Vector3(0, 1.4, 0), Vector3(w, 2.8, w), cream)
			k.box(Vector3(0, 2.9, 0), Vector3(w * 1.02, 0.2, w * 1.02), brass)
			k.cyl(Vector3(0, 2.8, 0), Vector3(0, 4.0, 0), w * 0.32, w * 0.32, cream, 14)
			k.gloss = true
			_dome(k, Vector3(0, 4.0, 0), w * 0.33, brass, true)
			k.gloss = false
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					var c := Vector3(x * w * 0.44, 0, z * w * 0.44)
					k.cyl(c, c + Vector3(0, 5.0, 0), 0.38, 0.32, cream, 10)
					k.ring(c + Vector3(0, 4.0, 0), Vector3.UP, 0.4, 0.06, brass, 10, 3)
					_dome(k, c + Vector3(0, 5.0, 0), 0.36, brass, true)
			for i in 3:
				var x := -w * 0.3 + i * w * 0.3
				k.box(Vector3(x, 1.2, w * 0.5 + 0.02), Vector3(0.8, 1.8, 0.06), teal)
				k.ring(Vector3(x, 2.1, w * 0.5 + 0.05), Vector3(0, 0, 1), 0.4, 0.05, brass, 12, 3, false, PI)
			k.ring(Vector3(0, 4.3, 0), Vector3.UP, w * 0.34, 0.06, glow, 20, 3, true)
			k.box(Vector3(0, 2.55, w * 0.5 + 0.05), Vector3(w * 0.7, 0.25, 0.05), T)
		"house":
			k.box(Vector3(0, 0.9, 0), Vector3(w * 0.8, 1.8, w * 0.8), cream)
			k.gloss = true
			_dome(k, Vector3(0, 1.8, 0), w * 0.33, brass, true)
			k.gloss = false
			k.box(Vector3(0, 0.6, w * 0.4 + 0.02), Vector3(0.5, 1.0, 0.05), teal)
			k.box(Vector3(0, 1.5, w * 0.4 + 0.03), Vector3(w * 0.6, 0.15, 0.04), T)
		"depot":
			k.box(Vector3(0, 0.5, 0), Vector3(w * 0.9, 1.0, w * 0.9), brass.darkened(0.3))
			for x in [-0.22, 0.22]:
				k.cyl(Vector3(x * w, 1.0, 0), Vector3(x * w, 2.6, 0), 0.42, 0.42, cream, 10)
				k.cyl(Vector3(x * w, 1.2, 0), Vector3(x * w, 2.4, 0), 0.44, 0.44, glow, 10, true, true, false)
				k.sphere(Vector3(x * w, 2.6, 0), Vector3(0.42, 0.25, 0.42), brass, 10, 4)
			k.box(Vector3(0, 0.75, w * 0.45 + 0.02), Vector3(w * 0.6, 0.2, 0.05), T)
		"barracks":
			k.box(Vector3(0, 1.2, 0), Vector3(w, 2.4, w * 0.8), cream)
			k.box(Vector3(0, 2.5, 0), Vector3(w * 1.02, 0.2, w * 0.82), brass)
			for i in 4:
				var x := -w * 0.36 + i * w * 0.24
				k.ring(Vector3(x, 1.4, w * 0.4 + 0.04), Vector3(0, 0, 1), 0.45, 0.06, brass, 12, 3, false, PI)
				k.box(Vector3(x, 0.7, w * 0.4 + 0.02), Vector3(0.7, 1.4, 0.05), teal.darkened(0.3))
			k.gloss = true
			_dome(k, Vector3(0, 2.6, 0), w * 0.22, brass, true)
			k.gloss = false
			_banner(k, Vector3(w * 0.45, 2.6, w * 0.35), 2.2, brass)
			_banner(k, Vector3(-w * 0.45, 2.6, w * 0.35), 2.2, brass)
		"forge":
			# gearworks: big turning gears on the walls and an aether chimney
			k.box(Vector3(0, 1.2, 0), Vector3(w * 0.9, 2.4, w * 0.8), cream.darkened(0.08))
			k.box(Vector3(0, 2.5, 0), Vector3(w * 0.92, 0.2, w * 0.82), brass)
			for x in [-0.25, 0.25]:
				k.ring(Vector3(x * w, 1.4, w * 0.4 + 0.1), Vector3(0, 0, 1), 0.6, 0.12, brass, 14, 4)
				k.cyl(Vector3(x * w, 1.4, w * 0.4 + 0.02), Vector3(x * w, 1.4, w * 0.4 + 0.2), 0.15, 0.15, brass.darkened(0.3), 8)
			k.cyl(Vector3(w * 0.25, 2.4, -w * 0.2), Vector3(w * 0.25, 4.6, -w * 0.2), 0.35, 0.28, brass, 10)
			k.cyl(Vector3(w * 0.25, 4.6, -w * 0.2), Vector3(w * 0.25, 4.75, -w * 0.2), 0.3, 0.3, glow, 10, true)
			k.box(Vector3(-w * 0.25, 2.3, w * 0.4 + 0.03), Vector3(0.9, 0.25, 0.05), T)
		"tower":
			k.cyl(Vector3(0, 0, 0), Vector3(0, 5.0, 0), w * 0.32, w * 0.22, cream, 10)
			for i in 3:
				k.ring(Vector3(0, 1.4 + i * 1.4, 0), Vector3.UP, w * 0.31 - i * 0.07, 0.06, brass, 10, 3)
			k.cyl(Vector3(0, 5.0, 0), Vector3(0, 5.6, 0), w * 0.25, w * 0.3, brass, 10)
			k.sphere(Vector3(0, 6.3, 0), Vector3(0.55, 0.55, 0.55), glow, 10, 6, true)
			k.ring(Vector3(0, 6.3, 0), Vector3(1, 1, 0).normalized(), 0.85, 0.05, brass, 16, 3)
			k.ring(Vector3(0, 6.3, 0), Vector3(-1, 1, 0).normalized(), 0.85, 0.05, brass, 16, 3)
			k.box(Vector3(0, 2.2, w * 0.3), Vector3(0.5, 0.3, 0.05), T)
		"stable":
			# racing garage: a low curved hall with a striped start ramp
			k.box(Vector3(0, 1.0, -w * 0.1), Vector3(w * 0.95, 2.0, w * 0.6), cream)
			k.cyl(Vector3(-w * 0.47, 2.0, -w * 0.1), Vector3(w * 0.47, 2.0, -w * 0.1), w * 0.3, w * 0.3, brass, 10)
			for i in 3:
				k.box(Vector3(-w * 0.3 + i * w * 0.3, 0.8, w * 0.2 + 0.02), Vector3(0.9, 1.4, 0.05), DARK)
			for i in 5:
				k.box(Vector3(-w * 0.4 + i * w * 0.2, 0.05, w * 0.4), Vector3(w * 0.18, 0.1, 0.6), T if i % 2 == 0 else cream)
			k.cyl(Vector3(w * 0.42, 0, w * 0.42), Vector3(w * 0.42, 3.0, w * 0.42), 0.06, 0.06, brass, 5)
			k.box(Vector3(w * 0.42, 2.8, w * 0.42), Vector3(0.6, 0.4, 0.04), glow, true)
		"workshop":
			k.box(Vector3(0, 1.3, 0), Vector3(w, 2.6, w * 0.8), cream.darkened(0.05))
			k.cyl(Vector3(-w * 0.5, 2.6, 0), Vector3(w * 0.5, 2.6, 0), w * 0.25, w * 0.25, brass, 10)
			k.cyl(Vector3(-w * 0.2, 2.2, w * 0.2), Vector3(-w * 0.2, 3.5, w * 0.75), 0.25, 0.2, brass.darkened(0.2), 10)
			for x in [0.15, 0.35]:
				k.cyl(Vector3(x * w, 2.4, -w * 0.25), Vector3(x * w, 4.4, -w * 0.25), 0.3, 0.3, glow, 8, true)
			k.box(Vector3(0, 1.0, w * 0.4 + 0.02), Vector3(1.6, 2.0, 0.05), teal.darkened(0.3))
			k.box(Vector3(0, 2.25, w * 0.4 + 0.03), Vector3(1.8, 0.25, 0.05), T)
		"sanctum":
			# inventors' fair: a striped pavilion around a glowing aether engine
			for i in 8:
				var a := TAU * i / 8.0
				var c := Vector3(cos(a), 0, sin(a)) * w * 0.42
				k.cyl(c, c + Vector3(0, 2.4, 0), 0.08, 0.08, brass, 5)
			k.cyl(Vector3(0, 2.4, 0), Vector3(0, 4.6, 0), w * 0.5, 0.15, cream, 8)
			for i in 4:
				var a := TAU * i / 4.0 + 0.2
				k.cyl(Vector3(0, 2.42, 0) + Vector3(cos(a), 0, sin(a)) * w * 0.25, Vector3(0, 4.4, 0), 0.25, 0.02, T, 4)
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.6, 0), 0.9, 0.7, brass.darkened(0.2), 10)
			k.sphere(Vector3(0, 2.0, 0), Vector3(0.6, 0.6, 0.6), glow, 10, 6, true)
			k.ring(Vector3(0, 2.0, 0), Vector3(0.4, 1, 0).normalized(), 1.0, 0.05, brass, 16, 3)
			k.cyl(Vector3(0, 4.6, 0), Vector3(0, 5.6, 0), 0.04, 0.04, brass, 4)
			k.box(Vector3(0.3, 5.3, 0), Vector3(0.5, 0.35, 0.03), T)


static func _phy_building(k: MeshKit, role: String, w: float) -> void:
	var p := _pal("phyrexia")
	var porcelain: Color = p.main
	var oil := Color(0.06, 0.06, 0.07)
	var sinew: Color = p.trim
	var metal := Color(0.3, 0.3, 0.33)
	var glow := Color(0.3, 0.95, 0.55)
	match role:
		"hall":
			# furnace core: a cage of porcelain ribs around a glowing furnace
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.0, 0), w * 0.5, w * 0.45, metal, 12)
			k.sphere(Vector3(0, 2.6, 0), Vector3(1.5, 1.8, 1.5), glow, 12, 7, true)
			k.gloss = true
			for i in 10:
				var a := TAU * i / 10.0
				var d := Vector3(cos(a), 0, sin(a))
				var pts := [d * w * 0.45 + Vector3(0, 1.0, 0), d * w * 0.48 + Vector3(0, 3.0, 0), d * w * 0.3 + Vector3(0, 5.2, 0), d * 0.3 + Vector3(0, 6.6, 0)]
				for j in 3:
					k.cyl(pts[j], pts[j + 1], 0.22 - j * 0.04, 0.18 - j * 0.04, porcelain, 6)
			k.cyl(Vector3(0, 6.4, 0), Vector3(0, 9.0, 0), 0.4, 0.0, porcelain, 8)
			k.gloss = false
			k.ring(Vector3(0, 1.0, 0), Vector3.UP, w * 0.46, 0.15, sinew, 20, 4)
			k.ring(Vector3(0, 4.0, 0), Vector3.UP, w * 0.42, 0.12, T, 20, 4)
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				k.cyl(Vector3(cos(a) * w * 0.5, 0, sin(a) * w * 0.5), Vector3(cos(a) * w * 0.62, 3.0, sin(a) * w * 0.62), 0.2, 0.0, oil, 5)
		"house":
			# incubation vat: a glass tank of glowing oil on a porcelain stand
			k.cyl(Vector3(0, 0, 0), Vector3(0, 0.5, 0), w * 0.42, w * 0.4, metal, 10)
			k.cyl(Vector3(0, 0.5, 0), Vector3(0, 2.6, 0), w * 0.32, w * 0.32, glow.darkened(0.3), 10, true)
			k.gloss = true
			for i in 4:
				var a := TAU * i / 4.0 + 0.78
				k.cyl(Vector3(cos(a), 0, sin(a)) * w * 0.38 + Vector3(0, 0.4, 0), Vector3(cos(a), 0, sin(a)) * w * 0.3 + Vector3(0, 3.2, 0), 0.12, 0.08, porcelain, 6)
			k.cyl(Vector3(0, 2.6, 0), Vector3(0, 3.0, 0), w * 0.36, w * 0.2, porcelain, 10)
			k.gloss = false
			k.ring(Vector3(0, 1.6, 0), Vector3.UP, w * 0.33, 0.07, T, 14, 3)
		"depot":
			k.cyl(Vector3(0, 0, 0), Vector3(0, 0.4, 0), w * 0.48, w * 0.45, metal, 10)
			k.gloss = true
			k.cyl(Vector3(0, 0.4, 0), Vector3(0, 0.45, 0), w * 0.4, w * 0.4, oil, 12)
			for i in 6:
				var a := TAU * i / 6.0
				k.cyl(Vector3(cos(a), 0, sin(a)) * w * 0.44, Vector3(cos(a), 0, sin(a)) * w * 0.2 + Vector3(0, 2.2, 0), 0.12, 0.04, porcelain, 5)
			k.gloss = false
			k.ring(Vector3(0, 0.5, 0), Vector3.UP, w * 0.44, 0.08, T, 14, 3)
		"barracks":
			# compleation pit: a sunken ring wall with spikes and hanging hooks
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.6, 0), w * 0.5, w * 0.46, metal, 14)
			k.cyl(Vector3(0, 1.6, 0), Vector3(0, 1.65, 0), w * 0.42, w * 0.42, glow.darkened(0.4), 14, true)
			k.gloss = true
			for i in 12:
				var a := TAU * i / 12.0
				k.cyl(Vector3(cos(a), 0, sin(a)) * w * 0.48 + Vector3(0, 1.5, 0), Vector3(cos(a), 0, sin(a)) * w * 0.55 + Vector3(0, 3.0 + (i % 3) * 0.5, 0), 0.18, 0.0, porcelain, 5)
			k.gloss = false
			k.ring(Vector3(0, 1.2, 0), Vector3.UP, w * 0.5, 0.12, T, 20, 4)
			k.cyl(Vector3(0, 1.6, 0), Vector3(0, 4.0, 0), 0.25, 0.15, sinew, 6)
		"forge":
			k.box(Vector3(0, 1.0, 0), Vector3(w * 0.85, 2.0, w * 0.85), metal)
			k.gloss = true
			k.taper(Vector3(0, 2.0, 0), Vector2(w * 0.85, w * 0.85), Vector2(w * 0.4, w * 0.4), 1.2, porcelain)
			for x in [-0.25, 0.25]:
				k.cyl(Vector3(x * w, 3.0, 0), Vector3(x * w * 1.2, 5.5, -0.3), 0.35, 0.05, porcelain, 6)
			k.gloss = false
			k.box(Vector3(0, 0.8, w * 0.43), Vector3(1.4, 1.2, 0.05), Color(1.0, 0.35, 0.15), true)
			k.box(Vector3(0, 1.75, w * 0.43 + 0.02), Vector3(w * 0.7, 0.2, 0.04), T)
			k.ring(Vector3(0, 2.0, 0), Vector3.UP, w * 0.5, 0.1, sinew, 4, 3)
		"tower":
			# spine tower: stacked vertebrae with a spiked crown and a glowing eye
			k.gloss = true
			for i in 7:
				k.cyl(Vector3(0, i * 0.85, 0), Vector3(0, i * 0.85 + 0.6, 0), w * 0.32 - i * 0.025, w * 0.3 - i * 0.025, porcelain, 8)
				for side in [-1.0, 1.0]:
					k.cyl(Vector3(side * w * 0.25, i * 0.85 + 0.3, 0), Vector3(side * w * 0.5, i * 0.85 + 0.55, 0), 0.08, 0.0, porcelain, 4)
			k.gloss = false
			k.cyl(Vector3(0, 0, 0), Vector3(0, 6.0, 0), w * 0.18, w * 0.15, sinew, 8)
			k.sphere(Vector3(0, 6.3, 0), Vector3(0.45, 0.45, 0.45), glow, 8, 5, true)
			for i in 5:
				var a := TAU * i / 5.0
				k.cyl(Vector3(cos(a) * 0.4, 6.0, sin(a) * 0.4), Vector3(cos(a) * 0.9, 7.6, sin(a) * 0.9), 0.1, 0.0, oil, 4)
			k.ring(Vector3(0, 2.0, 0), Vector3.UP, w * 0.31, 0.07, T, 12, 3)
		"stable":
			# hound kennels: low porcelain hutches with an oil trough
			k.gloss = true
			for x in [-0.28, 0.28]:
				k.sphere(Vector3(x * w, 0.6, -w * 0.1), Vector3(w * 0.24, 1.5, w * 0.36), porcelain, 10, 6)
			k.gloss = false
			k.box(Vector3(0, 0.2, w * 0.35), Vector3(w * 0.8, 0.4, 0.5), metal)
			k.box(Vector3(0, 0.42, w * 0.35), Vector3(w * 0.75, 0.04, 0.4), glow.darkened(0.3), true)
			for x in [-0.28, 0.28]:
				k.box(Vector3(x * w, 0.6, w * 0.25), Vector3(0.7, 0.9, 0.05), oil)
			k.ring(Vector3(0, 0.15, -w * 0.1), Vector3.UP, w * 0.5, 0.1, T, 16, 3)
			for i in 5:
				k.cyl(Vector3(-w * 0.4 + i * w * 0.2, 0, -w * 0.48), Vector3(-w * 0.4 + i * w * 0.2, 2.2, -w * 0.55), 0.12, 0.0, porcelain, 4)
		"workshop":
			# engine foundry: a furnace hall with a crane arm
			k.box(Vector3(0, 1.2, 0), Vector3(w * 0.95, 2.4, w * 0.8), metal)
			k.gloss = true
			k.taper(Vector3(0, 2.4, 0), Vector2(w * 0.95, w * 0.8), Vector2(w * 0.2, w * 0.8), 1.3, porcelain)
			k.gloss = false
			k.cyl(Vector3(w * 0.35, 2.4, -w * 0.3), Vector3(w * 0.35, 5.0, -w * 0.3), 0.2, 0.15, sinew, 6)
			k.cyl(Vector3(w * 0.35, 5.0, -w * 0.3), Vector3(-w * 0.2, 5.4, w * 0.2), 0.12, 0.08, metal, 6)
			k.box(Vector3(0, 1.0, w * 0.4 + 0.02), Vector3(1.8, 2.0, 0.05), Color(1.0, 0.35, 0.15), true)
			k.box(Vector3(0, 2.2, w * 0.4 + 0.03), Vector3(w * 0.8, 0.2, 0.04), T)
		"sanctum":
			# oil cathedral: a tall spiked spire weeping oil
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.5, 0), w * 0.48, w * 0.42, metal, 10)
			k.gloss = true
			k.cyl(Vector3(0, 1.5, 0), Vector3(0, 9.5, 0), w * 0.36, 0.0, porcelain, 10)
			for i in 6:
				var a := TAU * i / 6.0
				var c := Vector3(cos(a), 0, sin(a)) * w * 0.42
				k.cyl(c + Vector3(0, 1.0, 0), c * 1.15 + Vector3(0, 5.5, 0), 0.2, 0.0, porcelain, 5)
			k.cyl(Vector3(0, 1.5, w * 0.22), Vector3(0, 6.0, w * 0.06), 0.18, 0.04, oil, 6)
			k.gloss = false
			k.sphere(Vector3(0, 4.5, 0), Vector3(0.5, 0.5, 0.5), glow, 8, 5, true)
			k.ring(Vector3(0, 1.4, 0), Vector3.UP, w * 0.46, 0.12, T, 16, 4)


static func scaffold(size: int) -> ArrayMesh:
	var key := "scaffold:%d" % size
	if _cache.has(key):
		return _cache[key]
	var k := MeshKit.new()
	var w := size * Data.CELL - 0.4
	var h := 1.5 + size * 0.5
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			k.box(Vector3(x * w * 0.5, h * 0.5, z * w * 0.5), Vector3(0.12, h, 0.12), WOOD)
	for y in [0.4, h * 0.6, h]:
		k.box(Vector3(0, y, w * 0.5), Vector3(w, 0.08, 0.08), WOOD.lightened(0.1))
		k.box(Vector3(0, y, -w * 0.5), Vector3(w, 0.08, 0.08), WOOD.lightened(0.1))
		k.box(Vector3(w * 0.5, y, 0), Vector3(0.08, 0.08, w), WOOD.lightened(0.1))
		k.box(Vector3(-w * 0.5, y, 0), Vector3(0.08, 0.08, w), WOOD.lightened(0.1))
	k.box(Vector3(0, 0.05, 0), Vector3(w, 0.1, w), Color(0.5, 0.45, 0.38))
	var m := k.commit(null, _mats())
	_cache[key] = m
	return m


# --- deposits and props ------------------------------------------------------------------------

static func resource(kind: String) -> ArrayMesh:
	var key := "r:" + kind
	if _cache.has(key):
		return _cache[key]
	var k := MeshKit.new()
	if kind == "gold":
		k.rock(Vector3(0, 0.3, 0), Vector3(0.85, 0.65, 0.8), Color(0.42, 0.38, 0.34), 7)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		for i in 9:
			var a := rng.randf() * TAU
			var r := rng.randf_range(0.35, 0.75)
			k.gloss = true
			k.rock(Vector3(cos(a) * r, rng.randf_range(0.3, 0.75), sin(a) * r), Vector3(0.16, 0.13, 0.16) * rng.randf_range(0.7, 1.3), Color(1.0, 0.8, 0.25), i)
			k.gloss = false
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = 23
		k.rock(Vector3(0, 0.1, 0), Vector3(0.7, 0.25, 0.7), Color(0.3, 0.32, 0.38), 3)
		for i in 6:
			var a := TAU * i / 6.0 + rng.randf() * 0.5
			var tilt := Vector3(cos(a) * 0.35, 1.0, sin(a) * 0.35).normalized()
			var base := Vector3(cos(a) * 0.3, 0.1, sin(a) * 0.3)
			var h := rng.randf_range(0.8, 1.5)
			k.cyl(base, base + tilt * h, 0.16, 0.0, Color(0.4, 0.85, 1.0), 6, true, false)
		k.cyl(Vector3(0, 0.1, 0), Vector3(0, 1.9, 0), 0.22, 0.0, Color(0.6, 0.95, 1.0), 6, true, false)
	var m := k.commit()
	_cache[key] = m
	return m


static func prop(kind: String, variant := 0) -> ArrayMesh:
	var key := "p:%s:%d" % [kind, variant]
	if _cache.has(key):
		return _cache[key]
	var k := MeshKit.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	match kind:
		"oak":
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.6, 0), 0.22, 0.16, Color(0.36, 0.26, 0.17), 6)
			var g := Color(0.22, 0.42, 0.16).lerp(Color(0.38, 0.5, 0.2), variant * 0.5)
			for i in 4:
				k.sphere(Vector3(rng.randf_range(-0.5, 0.5), 2.1 + rng.randf_range(0, 0.9), rng.randf_range(-0.5, 0.5)), Vector3.ONE * rng.randf_range(0.7, 1.05), g.darkened(rng.randf() * 0.15), 7, 5)
		"ruin":
			var stone := Color(0.4, 0.37, 0.4)
			k.box(Vector3(0, 0.7, 0), Vector3(1.7, 1.4, 1.7), stone)
			k.box(Vector3(-0.5, 1.9, -0.5), Vector3(0.7, 1.2 + variant * 0.6, 0.7), stone.lightened(0.08))
			k.box(Vector3(0.45, 1.6, 0.4), Vector3(0.6, 0.6, 0.6), stone.darkened(0.1))
			k.box(Vector3(0, 1.45, 0.86), Vector3(0.5, 0.6, 0.04), Color(0.9, 0.7, 0.4), true)
		"pipe":
			var brass := Color(0.75, 0.55, 0.3)
			if variant == 0:
				k.cyl(Vector3(0, 0, 0), Vector3(0, 2.6, 0), 0.4, 0.35, brass, 10)
				k.ring(Vector3(0, 1.3, 0), Vector3.UP, 0.42, 0.06, brass.darkened(0.3), 10, 3)
				k.sphere(Vector3(0, 2.8, 0), Vector3(0.3, 0.3, 0.3), Color(0.35, 0.95, 1.0), 8, 4, true)
			else:
				k.rock(Vector3(0, 0.6, 0), Vector3(1.0, 0.8, 0.9), Color(0.6, 0.4, 0.28), variant)
		"spire":
			var metal := Color(0.32, 0.32, 0.36)
			k.gloss = true
			k.cyl(Vector3(0, 0, 0), Vector3(rng.randf_range(-0.3, 0.3), 3.4 + variant, rng.randf_range(-0.3, 0.3)), 0.35, 0.0, metal, 6)
			k.cyl(Vector3(0.3, 0, 0.2), Vector3(0.6, 2.0, 0.4), 0.18, 0.0, Color(0.85, 0.82, 0.8), 5)
			k.gloss = false
			k.cyl(Vector3(-0.2, 0, -0.2), Vector3(-0.5, 1.6, -0.4), 0.12, 0.0, Color(0.55, 0.08, 0.1), 5)
		"boulder":
			k.rock(Vector3(0, 0.7, 0), Vector3(1.2, 1.0, 1.1), Color(0.5, 0.47, 0.44), variant + 3)
		"pebble":
			k.rock(Vector3(0, 0.1, 0), Vector3(0.3, 0.2, 0.25), Color(0.5, 0.48, 0.45), variant + 9)
		"shrub":
			for i in 3:
				k.sphere(Vector3(rng.randf_range(-0.3, 0.3), 0.3, rng.randf_range(-0.3, 0.3)), Vector3(0.4, 0.32, 0.4), Color(0.25, 0.4, 0.18), 6, 4)
	var m := k.commit()
	_cache[key] = m
	return m
