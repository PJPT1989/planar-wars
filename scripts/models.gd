class_name Models
extends RefCounted
## Every unit, building, deposit and prop, built from MeshKit primitives with vertex colours.
## Units face +Z. Parts painted in the team marker colour `T` (magenta) take the owner's colour
## in shaders/unit.gdshader, so one mesh serves every player. Each race has its own look for the
## same template role: porcelain and sinew (Phyrexia), steel and blue tabards (Dominaria),
## gothic coats and bronze (Ravnica), brass, filigree and aether (Avishkar).
## Units and buildings are rigged (MeshKit.rig): legs, arms, wings, wheels, heads, banners and
## gears are tagged with one of the P_* parts and their pivot, and shaders/rig.gdshaderinc moves
## them from the instance data that View writes (walk cycle, attack swing).

const T := Color(1, 0, 1)
const TD := Color(0.6, 0, 0.6)
const SKIN := Color(0.85, 0.66, 0.52)
const LEATHER := Color(0.36, 0.24, 0.15)
const WOOD := Color(0.45, 0.31, 0.18)
const STEEL := Color(0.7, 0.72, 0.76)
const DARK := Color(0.12, 0.11, 0.12)

# rigged parts; the numbers are used in shaders/rig.gdshaderinc
const P_BODY := 0
const P_LEG := 1                       # steps with the walk, the two sides in turn
const P_ARM := 2                       # weapon arm: chops on a blow
const P_GUARD := 3                     # shield arm: braces on a blow
const P_THRUST := 4                    # spear arm: thrusts
const P_AIM := 5                       # bows, guns, nozzles: kick back on a shot
const P_CAST := 6                      # raised high on a blow
const P_WING := 7                      # beats about the root
const P_GAIT := 8                      # four legs, diagonal pairs together
const P_WHEEL := 9                     # rolls with the distance driven
const P_RECOIL := 10                   # barrels: slide back on a shot
const P_HEAD := 11                     # nods with the gait, lunges on a bite
const P_TAIL := 12                     # sways
const P_FLAG := 13                     # banners on buildings
const P_GEAR := 14                     # turns about the axis facing +Z
const P_SPIN := 15                     # turns about the up axis

static var _cache := {}


static func _mats() -> Array:
	return [Game.mat_unit, Game.mat_unit_glow, Game.mat_unit_gloss]


static func _pal(race: String) -> Dictionary:
	return Data.RACES[race].colors


static func unit(race: String, role: String) -> ArrayMesh:
	var key := "u:%s:%s" % [race, role]
	if _cache.has(key):
		return _cache[key]
	var k := MeshKit.new()
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


# --- shapes ------------------------------------------------------------------------------------

## A horizontal ellipse of n points at height c.y (for lofting upright bodies).
static func _hring(c: Vector3, rx: float, rz: float, n := 8) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector3(cos(a) * rx, 0, sin(a) * rz))
	return out


## Part of a horizontal ellipse, from angle a0 to a1 (0 is +X, PI/2 is the front, +Z).
static func _harc(c: Vector3, rx: float, rz: float, a0: float, a1: float, n := 5) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var a := lerpf(a0, a1, float(i) / (n - 1))
		out.append(c + Vector3(cos(a) * rx, 0, sin(a) * rz))
	return out


## A vertical ellipse of n points at depth c.z (for lofting bodies that run along Z).
static func _ring_pts(c: Vector3, rx: float, ry: float, n := 8) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector3(cos(a) * rx, sin(a) * ry, 0))
	return out


## Points what is added next along `dir` from `at`: local +Y becomes `dir`, local +X stays as
## level as it can. Returns the previous transform; put it back in k.xf afterwards.
static func _along(k: MeshKit, at: Vector3, dir: Vector3) -> Transform3D:
	var old := k.xf
	var y := dir.normalized()
	var x := Vector3.RIGHT - y * y.dot(Vector3.RIGHT)
	if x.length() < 0.1:
		x = Vector3.FORWARD.cross(y)
	x = x.normalized()
	k.xf = old * Transform3D(Basis(x, y, x.cross(y)), at)
	return old


## A flat plate: a convex outline in the XY plane, `thick` deep, its front facing +Z at `at`.
static func _slab(k: MeshKit, at: Vector3, outline: PackedVector2Array, thick: float, col: Color, side_col := Color(-1, 0, 0)) -> void:
	var sc := col.darkened(0.25) if side_col.r < 0.0 else side_col
	var n := outline.size()
	var mid := Vector2.ZERO
	for p in outline:
		mid += p
	mid /= n
	var f := at + Vector3(mid.x, mid.y, thick * 0.5)
	var b := at + Vector3(mid.x, mid.y, -thick * 0.5)
	for i in n:
		var p0 := outline[i]
		var p1 := outline[(i + 1) % n]
		var a0 := at + Vector3(p0.x, p0.y, thick * 0.5)
		var a1 := at + Vector3(p1.x, p1.y, thick * 0.5)
		var c0 := at + Vector3(p0.x, p0.y, -thick * 0.5)
		var c1 := at + Vector3(p1.x, p1.y, -thick * 0.5)
		k.tri(f, a0, a1, col)
		k.tri(f, a1, a0, col)
		k.tri(b, c1, c0, sc)
		k.quad(a0, c0, c1, a1, sc)
		k.quad(a1, c1, c0, a0, sc)


# --- body parts ----------------------------------------------------------------------------

## A standing figure, about 1.9 m tall at s = 1. o: s, skin, body, legs, arms, head ("helm",
## "plume", "hood", "mask", "cap", "hat", "turban", "bare"), head_col, hair, tabard, cape,
## cape_col, belt, r_hand / l_hand (hand positions; weapons are added by the caller inside
## `_hold`), r_style / l_style (how each arm moves, P_ARM by default for the right and P_GUARD
## for the left), pauldrons, spikes, robe, mounted (legs astride and still).
static func _man(k: MeshKit, o: Dictionary) -> void:
	var s: float = o.get("s", 1.0)
	var body: Color = o.get("body", LEATHER)
	var legs: Color = o.get("legs", body.darkened(0.25))
	var arms: Color = o.get("arms", body)
	var skin: Color = o.get("skin", SKIN)
	var boot: Color = o.get("boot", DARK)
	var armoured: bool = o.get("pauldrons", null) != null
	var mounted: bool = o.get("mounted", false)
	var tab: Variant = o.get("tabard", null)
	if o.get("robe", false):
		k.loft([_hring(Vector3(0, 0.02, 0) * s, 0.31 * s, 0.27 * s, 10), _hring(Vector3(0, 0.45, 0) * s, 0.25 * s, 0.2 * s, 10),
			_hring(Vector3(0, 0.88, 0) * s, 0.2 * s, 0.135 * s, 10)], func(_t: float, a: float, _c: Vector3, _n: Vector3) -> Color:
				return legs.darkened(0.1 * (int(a * 10.0) % 2)))
		k.ring(Vector3(0, 0.05, 0) * s, Vector3.UP, 0.29 * s, 0.025 * s, legs.darkened(0.35), 12, 3)
		if tab != null:
			k.loft([_harc(Vector3(0, 0.03, 0) * s, 0.32 * s, 0.28 * s, PI * 0.5 - 0.3, PI * 0.5 + 0.3, 3),
				_harc(Vector3(0, 0.45, 0) * s, 0.26 * s, 0.21 * s, PI * 0.5 - 0.3, PI * 0.5 + 0.3, 3),
				_harc(Vector3(0, 0.88, 0) * s, 0.21 * s, 0.145 * s, PI * 0.5 - 0.35, PI * 0.5 + 0.35, 3)], tab, false, false, false)
	elif mounted:
		for side in [-1.0, 1.0]:
			var hip := Vector3(side * 0.12, 0.9, 0)
			var knee := Vector3(side * 0.38, 0.74, 0.28)
			var ankle := Vector3(side * 0.4, 0.34, 0.2)
			k.cyl(hip * s, knee * s, 0.095 * s, 0.078 * s, legs, 7)
			k.sphere(knee * s, Vector3.ONE * 0.075 * s, legs.lightened(0.12) if armoured else legs, 6, 4)
			k.cyl(knee * s, ankle * s, 0.075 * s, 0.06 * s, legs.darkened(0.08), 7)
			k.taper((ankle + Vector3(0, -0.12, 0.0)) * s, Vector2(0.13, 0.17) * s, Vector2(0.12, 0.13) * s, 0.2 * s, boot)
			k.box((ankle + Vector3(0, -0.08, 0.11)) * s, Vector3(0.12, 0.08, 0.12) * s, boot)
		k.taper(Vector3(0, 0.78, 0) * s, Vector2(0.36, 0.24) * s, Vector2(0.4, 0.26) * s, 0.16 * s, legs)
	else:
		for side in [-1.0, 1.0]:
			var hip := Vector3(side * 0.11, 0.92, 0)
			var knee := Vector3(side * 0.12, 0.5, 0.03)
			var ankle := Vector3(side * 0.12, 0.13, 0)
			k.rig(P_LEG, hip * s)
			k.cyl(hip * s, knee * s, 0.095 * s, 0.075 * s, legs, 7)
			k.sphere(knee * s, Vector3.ONE * 0.07 * s, legs.lightened(0.12) if armoured else legs, 6, 4)
			k.cyl(knee * s, ankle * s, 0.075 * s, 0.06 * s, legs.darkened(0.08), 7)
			k.taper((ankle + Vector3(0, -0.13, 0.0)) * s, Vector2(0.13, 0.17) * s, Vector2(0.12, 0.13) * s, 0.22 * s, boot)
			k.box((ankle + Vector3(0, -0.09, 0.11)) * s, Vector3(0.12, 0.08, 0.12) * s, boot)
		k.rig()
		k.taper(Vector3(0, 0.78, 0) * s, Vector2(0.36, 0.24) * s, Vector2(0.4, 0.26) * s, 0.16 * s, legs)
	# torso
	k.loft([_hring(Vector3(0, 0.84, 0) * s, 0.19 * s, 0.125 * s, 10), _hring(Vector3(0, 1.02, 0) * s, 0.2 * s, 0.135 * s, 10),
		_hring(Vector3(0, 1.22, 0.01) * s, 0.235 * s, 0.155 * s, 10), _hring(Vector3(0, 1.37, 0) * s, 0.245 * s, 0.14 * s, 10),
		_hring(Vector3(0, 1.46, 0) * s, 0.12 * s, 0.09 * s, 10)], body)
	if tab != null and not o.get("robe", false):
		# a tabard over the chest and down to the knees, with a darker hem
		var rows := []
		var ys := [0.5, 0.86, 1.02, 1.22, 1.38]
		var rx := [0.23, 0.205, 0.21, 0.245, 0.255]
		var rz := [0.17, 0.14, 0.145, 0.168, 0.15]
		for i in ys.size():
			rows.append(_harc(Vector3(0, ys[i], 0.0 if i > 1 else 0.01) * s, rx[i] * s, rz[i] * s, PI * 0.5 - 0.62, PI * 0.5 + 0.62, 4))
		k.loft(rows, func(t: float, _a: float, _c: Vector3, _n: Vector3) -> Color:
			return (TD if tab == T else (tab as Color).darkened(0.3)) if t < 0.12 else tab, false, false, false)
	if o.has("belt"):
		var bc: Color = o.belt
		k.loft([_hring(Vector3(0, 0.86, 0) * s, 0.21 * s, 0.15 * s, 10), _hring(Vector3(0, 0.95, 0) * s, 0.212 * s, 0.152 * s, 10)], bc, false, true, false)
		k.box(Vector3(0, 0.905, 0.152) * s, Vector3(0.07, 0.07, 0.02) * s, Game.GOLD)
		k.box(Vector3(0.17, 0.83, 0.07) * s, Vector3(0.07, 0.1, 0.07) * s, LEATHER.darkened(0.1))
	if o.get("cape", false):
		var cc: Color = o.get("cape_col", TD)
		k.loft([_harc(Vector3(0, 1.42, -0.01) * s, 0.24 * s, 0.15 * s, -PI * 0.5 - 1.2, -PI * 0.5 + 1.2, 6),
			_harc(Vector3(0, 1.05, -0.02) * s, 0.27 * s, 0.2 * s, -PI * 0.5 - 1.1, -PI * 0.5 + 1.1, 6),
			_harc(Vector3(0, 0.55, -0.06) * s, 0.3 * s, 0.24 * s, -PI * 0.5 - 1.0, -PI * 0.5 + 1.0, 6),
			_harc(Vector3(0, 0.3, -0.1) * s, 0.31 * s, 0.25 * s, -PI * 0.5 - 1.0, -PI * 0.5 + 1.0, 6)],
			func(_t: float, a: float, _c: Vector3, _n: Vector3) -> Color:
				return cc.darkened(0.14 * (int(a * 5.0) % 2)), false, false, false)
	var pd: Variant = o.get("pauldrons", null)
	if pd != null:
		for side in [-1.0, 1.0]:
			k.sphere(Vector3(side * 0.29, 1.39, 0) * s, Vector3(0.14, 0.1, 0.15) * s, pd, 8, 4)
			k.sphere(Vector3(side * 0.32, 1.3, 0) * s, Vector3(0.12, 0.07, 0.135) * s, (pd as Color).darkened(0.12), 8, 3)
	# arms
	var rh: Vector3 = o.get("r_hand", Vector3(-0.27, 0.98, 0.22))
	var lh: Vector3 = o.get("l_hand", Vector3(0.27, 0.98, 0.18))
	for pair in [[-1.0, rh, o.get("r_style", P_ARM)], [1.0, lh, o.get("l_style", P_GUARD)]]:
		var side: float = pair[0]
		var hand: Vector3 = pair[1]
		var sh := Vector3(side * 0.27, 1.36, 0)
		var el := Vector3(side * 0.31, 1.1, -0.02)
		k.rig(pair[2], sh * s)
		k.cyl(sh * s, el * s, 0.075 * s, 0.065 * s, arms, 7)
		k.sphere(el * s, Vector3.ONE * 0.062 * s, arms.darkened(0.1), 6, 4)
		k.cyl(el * s, hand * s, 0.065 * s, 0.05 * s, arms, 7)
		if armoured:
			k.cyl(el.lerp(hand, 0.4) * s, el.lerp(hand, 0.85) * s, 0.072 * s, 0.062 * s, (o.get("glove", arms) as Color).darkened(0.1), 7)
		k.sphere(hand * s, Vector3(0.06, 0.065, 0.06) * s, o.get("glove", skin), 6, 4)
	k.rig()
	# neck and head
	k.cyl(Vector3(0, 1.42, 0) * s, Vector3(0, 1.53, 0) * s, 0.065 * s, 0.065 * s, skin, 6)
	var hc: Color = o.get("head_col", STEEL)
	var head := str(o.get("head", "bare"))
	if head != "mask":
		k.sphere(Vector3(0, 1.62, 0) * s, Vector3(0.13, 0.15, 0.135) * s, skin, 8, 5)
		k.box(Vector3(0, 1.6, 0.135) * s, Vector3(0.03, 0.05, 0.04) * s, skin.darkened(0.12))
		for side in [-1.0, 1.0]:
			k.box(Vector3(side * 0.045, 1.645, 0.122) * s, Vector3(0.026, 0.016, 0.01) * s, DARK)
	match head:
		"helm", "plume":
			k.sphere(Vector3(0, 1.68, -0.005) * s, Vector3(0.155, 0.12, 0.16) * s, hc, 9, 5)
			k.ring(Vector3(0, 1.63, -0.005) * s, Vector3.UP, 0.152 * s, 0.018 * s, hc.darkened(0.18), 12, 3)
			k.box(Vector3(0, 1.6, 0.15) * s, Vector3(0.03, 0.1, 0.025) * s, hc.darkened(0.2))
			if head == "plume":
				k.taper(Vector3(0, 1.76, -0.02) * s, Vector2(0.05, 0.26) * s, Vector2(0.03, 0.14) * s, 0.2 * s, T)
				k.taper(Vector3(0, 1.94, -0.06) * s, Vector2(0.03, 0.14) * s, Vector2(0.01, 0.04) * s, 0.08 * s, T, false, 0.0, Vector3(0, 0, -0.06) * s)
			else:
				k.box(Vector3(0, 1.79, 0) * s, Vector3(0.03, 0.04, 0.26) * s, hc.lightened(0.12))
		"hood":
			k.taper(Vector3(0, 1.45, -0.03) * s, Vector2(0.36, 0.34) * s, Vector2(0.08, 0.08) * s, 0.48 * s, hc, false, 0.0, Vector3(0, 0, -0.1) * s)
			k.ring(Vector3(0, 1.62, 0.04) * s, Vector3(0, 0.3, 1).normalized(), 0.15 * s, 0.03 * s, hc.darkened(0.2), 10, 3)
		"mask":
			# a faceless porcelain mask, long and tapering backwards, ridged over the crown
			k.taper(Vector3(0, 1.48, 0) * s, Vector2(0.24, 0.26) * s, Vector2(0.08, 0.12) * s, 0.4 * s, hc, false, 0.0, Vector3(0, 0.02, -0.12) * s)
			k.box(Vector3(0, 1.63, 0.12) * s, Vector3(0.16, 0.025, 0.03) * s, o.get("eye", Color(0.3, 1.0, 0.5)), true)
			k.box(Vector3(0, 1.58, 0.125) * s, Vector3(0.08, 0.015, 0.02) * s, DARK)
			for side in [-1.0, 1.0]:
				k.cyl(Vector3(side * 0.06, 1.75, -0.02) * s, Vector3(side * 0.05, 1.86, -0.16) * s, 0.025 * s, 0.0, hc.darkened(0.1), 4)
		"cap":
			k.cyl(Vector3(0, 1.7, 0) * s, Vector3(0, 1.8, 0) * s, 0.155 * s, 0.14 * s, hc, 10)
			k.box(Vector3(0, 1.71, 0.14) * s, Vector3(0.22, 0.02, 0.1) * s, hc.darkened(0.3))
			k.box(Vector3(0, 1.75, 0.15) * s, Vector3(0.05, 0.04, 0.01) * s, Game.GOLD)
		"hat":
			k.cyl(Vector3(0, 1.72, 0) * s, Vector3(0, 1.745, 0) * s, 0.3 * s, 0.3 * s, hc, 12)
			k.cyl(Vector3(0, 1.745, 0) * s, Vector3(0, 1.92, 0) * s, 0.14 * s, 0.06 * s, hc, 10)
			k.ring(Vector3(0, 1.77, 0) * s, Vector3.UP, 0.125 * s, 0.022 * s, hc.darkened(0.35), 10, 3)
		"turban":
			k.sphere(Vector3(0, 1.75, -0.01) * s, Vector3(0.18, 0.1, 0.18) * s, hc, 10, 4)
			k.ring(Vector3(0, 1.72, -0.01) * s, Vector3.UP, 0.165 * s, 0.03 * s, hc.darkened(0.1), 12, 3)
			k.sphere(Vector3(0, 1.77, 0.17) * s, Vector3(0.045, 0.045, 0.03) * s, o.get("eye", Color(0.3, 0.95, 1.0)), 6, 3, true)
		_:
			k.sphere(Vector3(0, 1.68, -0.015) * s, Vector3(0.14, 0.1, 0.145) * s, o.get("hair", Color(0.4, 0.28, 0.16)), 8, 4)
	if o.get("spikes", false):
		for side in [-1.0, 1.0]:
			k.cyl(Vector3(side * 0.22, 1.36, -0.05) * s, Vector3(side * 0.42, 1.62, -0.18) * s, 0.05 * s, 0.0, DARK, 5)
		k.cyl(Vector3(0, 1.2, -0.15) * s, Vector3(0, 1.45, -0.42) * s, 0.06 * s, 0.0, DARK, 5)


## Everything added inside `fn` moves with one arm of a figure made by `_man` with the same `o`
## (side -1 is the right arm). Weapons go here.
static func _hold(k: MeshKit, o: Dictionary, side: float, fn: Callable) -> void:
	var s: float = o.get("s", 1.0)
	var style: int = o.get("r_style", P_ARM) if side < 0.0 else o.get("l_style", P_GUARD)
	k.rig(style, Vector3(side * 0.27, 1.36, 0) * s)
	fn.call()
	k.rig()


## A sword in the hand, held out forward and a little up (the way it swings from).
static func _sword(k: MeshKit, hand: Vector3, s: float, blade: Color, len := 0.85, wide := 0.07, dir := Vector3(0, 0.55, 1.0)) -> void:
	var old := _along(k, hand * s, dir)
	k.cyl(Vector3(0, -0.12, 0) * s, Vector3(0, 0.06, 0) * s, 0.022 * s, 0.022 * s, LEATHER, 5)
	k.sphere(Vector3(0, -0.14, 0) * s, Vector3.ONE * 0.035 * s, Color(0.75, 0.6, 0.3), 5, 3)
	k.box(Vector3(0, 0.07, 0) * s, Vector3(0.04, 0.035, 0.26) * s, Color(0.6, 0.48, 0.22))
	k.taper(Vector3(0, 0.085, 0) * s, Vector2(0.018, wide) * s, Vector2(0.012, wide * 0.85) * s, len * s, blade)
	k.taper(Vector3(0, 0.085 + len, 0) * s, Vector2(0.012, wide * 0.85) * s, Vector2(0.002, 0.004) * s, wide * 1.4 * s, blade.lightened(0.1))
	k.box(Vector3(0, 0.085 + len * 0.45, 0) * s, Vector3(0.02, len * 0.8, wide * 0.18) * s, blade.darkened(0.2))
	k.xf = old


## A spear or lance through the hand, its butt behind and below. `pennant`: a little flag.
static func _spear(k: MeshKit, hand: Vector3, s: float, shaft: Color, tip: Color, len := 2.4, glow := false, pennant: Variant = null) -> void:
	var old := _along(k, hand * s, Vector3(0, len, 0.5))
	var t0 := len - 0.72
	k.cyl(Vector3(0, -0.72, 0) * s, Vector3(0, t0, 0) * s, 0.028 * s, 0.025 * s, shaft, 6)
	k.cyl(Vector3(0, -0.8, 0) * s, Vector3(0, -0.7, 0) * s, 0.034 * s, 0.03 * s, STEEL.darkened(0.3), 5)
	k.cyl(Vector3(0, t0 - 0.06, 0) * s, Vector3(0, t0 + 0.02, 0) * s, 0.035 * s, 0.03 * s, tip.darkened(0.25), 6)
	k.taper(Vector3(0, t0, 0) * s, Vector2(0.02, 0.05) * s, Vector2(0.016, 0.1) * s, 0.12 * s, tip, glow)
	k.taper(Vector3(0, t0 + 0.12, 0) * s, Vector2(0.016, 0.1) * s, Vector2(0.002, 0.004) * s, 0.26 * s, tip, glow)
	if pennant != null:
		var a := Vector3(0, t0 - 0.08, 0) * s
		var b := Vector3(0, t0 - 0.4, 0) * s
		var c := Vector3(0, t0 - 0.2, -0.45) * s
		k.tri(a, b, c, pennant)
		k.tri(a, c, b, pennant)
	k.xf = old


static func _shield(k: MeshKit, at: Vector3, s: float, face: Color, rim: Color, r := 0.3, kite := false) -> void:
	if kite:
		var outline := PackedVector2Array([Vector2(-0.24, 0.32), Vector2(0.24, 0.32), Vector2(0.23, 0.0), Vector2(0.12, -0.28), Vector2(0, -0.44), Vector2(-0.12, -0.28), Vector2(-0.23, 0.0)])
		var big := PackedVector2Array()
		var bigger := PackedVector2Array()
		for p in outline:
			big.append(p * s)
			bigger.append((p * 1.1 + Vector2(0, 0.01)) * s)
		_slab(k, (at + Vector3(0, 0.0, 0.07)) * s, big, 0.03 * s, face)
		_slab(k, (at + Vector3(0, 0.0, 0.045)) * s, bigger, 0.03 * s, rim)
		k.box((at + Vector3(0, -0.02, 0.09)) * s, Vector3(0.06, 0.62, 0.012) * s, rim)
		k.box((at + Vector3(0, 0.12, 0.09)) * s, Vector3(0.4, 0.06, 0.012) * s, rim)
	else:
		k.cyl((at + Vector3(0, 0, 0.02)) * s, (at + Vector3(0, 0, 0.08)) * s, r * s, r * s, face, 14)
		k.ring((at + Vector3(0, 0, 0.08)) * s, Vector3(0, 0, 1), r * s, 0.028 * s, rim, 14, 4)
		k.ring((at + Vector3(0, 0, 0.085)) * s, Vector3(0, 0, 1), r * 0.55 * s, 0.015 * s, rim.darkened(0.15), 12, 3)
		k.sphere((at + Vector3(0, 0, 0.09)) * s, Vector3(r * 0.25, r * 0.25, r * 0.18) * s, rim, 7, 4)


static func _bow(k: MeshKit, hand: Vector3, s: float, col: Color) -> void:
	var pts := []
	for i in 7:
		var t := lerpf(-1.0, 1.0, i / 6.0)
		pts.append(hand + Vector3(0.04, t * 0.64, 0.13 * (1.0 - t * t) - 0.03 * absf(t * t * t)))
	for i in 6:
		var w := 0.032 - absf(i - 2.5) * 0.004
		k.cyl(pts[i] * s, pts[i + 1] * s, w * s, w * s, col if i != 2 and i != 3 else LEATHER, 5, false, true, false)
	var top: Vector3 = pts[6]
	var bot: Vector3 = pts[0]
	k.cyl(bot * s, (hand + Vector3(0.04, 0, -0.32)) * s, 0.006 * s, 0.006 * s, Color(0.9, 0.88, 0.8), 3)
	k.cyl((hand + Vector3(0.04, 0, -0.32)) * s, top * s, 0.006 * s, 0.006 * s, Color(0.9, 0.88, 0.8), 3)
	# the nocked arrow
	k.cyl((hand + Vector3(0.03, 0.0, -0.34)) * s, (hand + Vector3(0.03, 0.0, 0.32)) * s, 0.01 * s, 0.01 * s, WOOD.lightened(0.2), 3)
	k.cyl((hand + Vector3(0.03, 0.0, 0.32)) * s, (hand + Vector3(0.03, 0.0, 0.4)) * s, 0.022 * s, 0.0, STEEL, 4)


static func _gun(k: MeshKit, hand: Vector3, s: float, body: Color, glow: Color, len := 0.9) -> void:
	k.box((hand + Vector3(0, 0.02, -0.1)) * s, Vector3(0.07, 0.13, 0.3) * s, body.darkened(0.25))
	k.box((hand + Vector3(0, 0.06, 0.2)) * s, Vector3(0.09, 0.11, len * 0.5) * s, body)
	k.cyl((hand + Vector3(0, 0.08, 0.3)) * s, (hand + Vector3(0, 0.08, 0.3 + len * 0.7)) * s, 0.032 * s, 0.028 * s, body.darkened(0.3), 7)
	for i in 3:
		k.ring((hand + Vector3(0, 0.08, 0.45 + i * len * 0.17)) * s, Vector3(0, 0, 1), 0.035 * s, 0.012 * s, body.lightened(0.15), 8, 3)
	k.cyl((hand + Vector3(0, 0.16, 0.1)) * s, (hand + Vector3(0, 0.16, 0.36)) * s, 0.03 * s, 0.03 * s, glow, 7, true)
	k.sphere((hand + Vector3(0, 0.08, 0.3 + len * 0.7)) * s, Vector3.ONE * 0.025 * s, glow, 5, 3, true)


static func _staff(k: MeshKit, hand: Vector3, s: float, wood: Color, orb: Color) -> void:
	k.cyl((hand + Vector3(0, -0.9, 0)) * s, (hand + Vector3(0, 0.72, 0)) * s, 0.028 * s, 0.034 * s, wood, 6)
	k.cyl((hand + Vector3(0, -0.06, 0)) * s, (hand + Vector3(0, 0.1, 0)) * s, 0.04 * s, 0.04 * s, LEATHER, 6)
	for i in 3:
		var a := TAU * i / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		k.cyl((hand + Vector3(0, 0.7, 0) + d * 0.02) * s, (hand + Vector3(0, 0.98, 0) + d * 0.1) * s, 0.02 * s, 0.006 * s, Game.GOLD, 4)
	k.sphere((hand + Vector3(0, 0.88, 0)) * s, Vector3(0.085, 0.085, 0.085) * s, orb, 8, 5, true)


## A wing from `root` out to the side (+1 or -1): a layer of long flight feathers and a layer of
## shorter coverts over them, rigged to beat about the root.
static func _wing(k: MeshKit, root: Vector3, side: float, span: float, col: Color, tip_col: Color, lift := 0.4, feathers := 6) -> void:
	k.rig(P_WING, root)
	for layer in 2:
		var n := feathers if layer == 0 else maxi(3, feathers - 2)
		var sp := span * (1.0 if layer == 0 else 0.6)
		for f in n:
			var t := float(f) / (n - 1)
			var a := root + Vector3(0, 0.02 * layer, -0.15 * t)
			var tip := root + Vector3(side * sp * (1.0 - 0.3 * t), lift * (1.0 - t) * (1.0 if layer == 0 else 0.7) + 0.1, -0.3 - 0.55 * t * (1.0 if layer == 0 else 0.6))
			var mid := root + Vector3(side * sp * 0.5, lift * 0.7 + 0.03 * layer, -0.05 - 0.3 * t)
			var c := col.lerp(tip_col, t) if layer == 0 else col.lightened(0.06)
			k.tri(a, mid, tip, c)
			k.tri(a, tip, mid, c)
			k.tri(a + Vector3(0, -0.04, -0.2), mid, tip, c.darkened(0.1))
			k.tri(a + Vector3(0, -0.04, -0.2), tip, mid, c.darkened(0.1))
	k.cyl(root, root + Vector3(side * span * 0.5, lift * 0.7, -0.05), 0.05, 0.03, col.darkened(0.05), 5)
	k.rig()


## A horse facing +Z, about 2 m tall at the head. Legs gallop in diagonal pairs, the head nods
## and the tail sways. `tuck`: legs folded and still (a flying horse).
static func _horse(k: MeshKit, body: Color, mane: Color, cloth: Color, armour := false, tuck := false) -> void:
	# barrel of the body
	k.loft([_ring_pts(Vector3(0, 1.2, -0.92), 0.12, 0.14, 10), _ring_pts(Vector3(0, 1.18, -0.75), 0.3, 0.33, 10), _ring_pts(Vector3(0, 1.14, -0.35), 0.33, 0.37, 10),
		_ring_pts(Vector3(0, 1.13, 0.1), 0.32, 0.37, 10), _ring_pts(Vector3(0, 1.2, 0.48), 0.3, 0.36, 10), _ring_pts(Vector3(0, 1.3, 0.7), 0.2, 0.26, 10)], body)
	# legs
	for x in [-0.19, 0.19]:
		for z in [-0.6, 0.52]:
			var top := Vector3(x, 1.05, z)
			k.rig(P_BODY if tuck else P_GAIT, top)
			var knee := Vector3(x, 0.55, z + (0.04 if z > 0 else -0.06))
			var fet := Vector3(x, 0.16, z)
			if tuck:
				knee = Vector3(x, 0.78, z + (0.25 if z > 0 else -0.25))
				fet = Vector3(x, 0.62, z + (0.0 if z > 0 else -0.1))
			k.cyl(top, knee, 0.1, 0.07, body, 7)
			k.sphere(knee, Vector3.ONE * 0.07, body.darkened(0.05), 6, 3)
			k.cyl(knee, fet, 0.055, 0.05, body.darkened(0.08), 6)
			k.cyl(fet, fet + Vector3(0, -0.06, 0.02), 0.07, 0.075, mane.darkened(0.1), 6)
			k.taper(fet + Vector3(0, -0.16, 0.02), Vector2(0.13, 0.15), Vector2(0.1, 0.11), 0.1, DARK)
	# neck, head, mane and ears, nodding together
	k.rig(P_HEAD, Vector3(0, 1.35, 0.6))
	k.loft([_ring_pts(Vector3(0, 1.3, 0.55), 0.2, 0.28, 8), _ring_pts(Vector3(0, 1.58, 0.78), 0.15, 0.2, 8), _ring_pts(Vector3(0, 1.85, 0.95), 0.12, 0.14, 8)], body)
	k.loft([_ring_pts(Vector3(0, 1.9, 0.92), 0.11, 0.12, 8), _ring_pts(Vector3(0, 1.84, 1.08), 0.11, 0.13, 8), _ring_pts(Vector3(0, 1.72, 1.26), 0.09, 0.1, 8),
		_ring_pts(Vector3(0, 1.66, 1.36), 0.075, 0.08, 8)], body)
	k.sphere(Vector3(0, 1.66, 1.38), Vector3(0.08, 0.07, 0.05), body.darkened(0.25), 6, 3)
	for side in [-1.0, 1.0]:
		k.cyl(Vector3(side * 0.07, 2.0, 0.92), Vector3(side * 0.08, 2.14, 0.9), 0.035, 0.0, body, 4)
		k.box(Vector3(side * 0.1, 1.86, 1.1), Vector3(0.02, 0.03, 0.05), DARK)
		k.box(Vector3(side * 0.09, 1.76, 1.18), Vector3(0.015, 0.025, 0.3), LEATHER.darkened(0.3))
	for i in 6:
		var t := i / 5.0
		k.box(Vector3(0, 1.62 + t * 0.4, 0.62 + t * 0.3), Vector3(0.06, 0.18, 0.12), mane.darkened(0.08 * (i % 2)))
	if armour:
		k.taper(Vector3(0, 1.66, 1.02), Vector2(0.24, 0.2), Vector2(0.18, 0.14), 0.28, STEEL, false, 0.0, Vector3(0, -0.05, 0.12))
		k.loft([_ring_pts(Vector3(0, 1.32, 0.56), 0.22, 0.3, 8), _ring_pts(Vector3(0, 1.6, 0.79), 0.17, 0.22, 8)], STEEL.darkened(0.08), false, true, false)
	k.rig()
	# tail
	k.rig(P_TAIL, Vector3(0, 1.3, -0.9))
	k.cyl(Vector3(0, 1.3, -0.9), Vector3(0, 1.0, -1.08), 0.09, 0.07, mane, 6)
	k.cyl(Vector3(0, 1.0, -1.08), Vector3(0, 0.55, -1.05), 0.07, 0.03, mane, 6)
	k.rig()
	# saddle and a cloth in team colour
	k.box(Vector3(0, 1.53, -0.05), Vector3(0.36, 0.1, 0.5), LEATHER)
	k.box(Vector3(0, 1.6, -0.27), Vector3(0.32, 0.12, 0.08), LEATHER.darkened(0.2))
	if armour:
		k.loft([_harc(Vector3(0, 1.48, -0.05), 0.42, 0.52, 0.2, PI - 0.2, 7), _harc(Vector3(0, 0.95, -0.05), 0.44, 0.56, 0.15, PI - 0.15, 7)], cloth, false, false, false)
		k.loft([_harc(Vector3(0, 1.48, -0.05), 0.42, 0.52, PI + 0.2, TAU - 0.2, 7), _harc(Vector3(0, 0.95, -0.05), 0.44, 0.56, PI + 0.15, TAU - 0.15, 7)], cloth, false, false, false)
		for side in [-1.0, 1.0]:
			k.box(Vector3(side * 0.39, 1.5, -0.05), Vector3(0.04, 0.06, 0.95), Game.GOLD)
	else:
		for side in [-1.0, 1.0]:
			k.box(Vector3(side * 0.32, 1.32, -0.05), Vector3(0.04, 0.42, 0.62), cloth)
			k.box(Vector3(side * 0.33, 1.12, -0.05), Vector3(0.04, 0.05, 0.64), TD if cloth == T else cloth.darkened(0.3))


# --- units by role ---------------------------------------------------------------------------

static func _worker(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	match race:
		"phyrexia":
			# hunched vat drone: porcelain shell, sinew limbs, claws that dig
			for side in [-1.0, 1.0]:
				k.rig(P_LEG, Vector3(side * 0.16, 0.78, 0.0))
				k.cyl(Vector3(side * 0.16, 0.78, 0.0), Vector3(side * 0.24, 0.4, 0.1), 0.06, 0.045, p.trim, 6)
				k.sphere(Vector3(side * 0.24, 0.4, 0.1), Vector3.ONE * 0.05, p.main, 5, 3)
				k.cyl(Vector3(side * 0.24, 0.4, 0.1), Vector3(side * 0.25, 0.0, 0.0), 0.045, 0.02, p.main, 6)
				k.cyl(Vector3(side * 0.25, 0.03, 0.0), Vector3(side * 0.25, 0.0, 0.14), 0.025, 0.0, p.dark, 4)
			k.rig()
			k.gloss = true
			k.sphere(Vector3(0, 0.95, -0.05), Vector3(0.32, 0.36, 0.42), p.main, 10, 6)
			for i in 4:
				k.ring(Vector3(0, 1.0, -0.3 + i * 0.12), Vector3(0, 0.2, 1).normalized(), 0.3 - absf(i - 1.5) * 0.04, 0.025, p.main.darkened(0.12), 12, 3, false, PI)
			k.gloss = false
			k.sphere(Vector3(0, 0.82, 0.18), Vector3(0.24, 0.2, 0.2), p.trim, 8, 4)
			k.rig(P_HEAD, Vector3(0, 0.95, 0.25))
			k.taper(Vector3(0, 0.95, 0.25), Vector2(0.18, 0.2), Vector2(0.06, 0.08), 0.35, p.main, false, 0.0, Vector3(0, 0.1, 0.25))
			k.box(Vector3(0, 1.12, 0.42), Vector3(0.12, 0.02, 0.03), p.glow, true)
			k.rig()
			for side in [-1.0, 1.0]:
				k.rig(P_ARM if side < 0.0 else P_GUARD, Vector3(side * 0.25, 0.9, 0.2))
				k.cyl(Vector3(side * 0.25, 0.9, 0.2), Vector3(side * 0.3, 0.55, 0.5), 0.05, 0.03, p.dark, 6)
				k.cyl(Vector3(side * 0.3, 0.55, 0.5), Vector3(side * 0.22, 0.35, 0.62), 0.035, 0.0, p.metal, 5)
				k.cyl(Vector3(side * 0.3, 0.55, 0.5), Vector3(side * 0.36, 0.32, 0.6), 0.03, 0.0, p.metal, 5)
			k.rig()
			k.box(Vector3(0, 1.0, -0.42), Vector3(0.3, 0.2, 0.1), T)
			k.cyl(Vector3(0.1, 1.2, -0.3), Vector3(0.14, 1.5, -0.42), 0.04, 0.0, p.dark, 4)
			k.cyl(Vector3(-0.1, 1.2, -0.3), Vector3(-0.14, 1.45, -0.42), 0.04, 0.0, p.dark, 4)
		"dominaria":
			var o := {"body": Color(0.55, 0.42, 0.28), "legs": Color(0.38, 0.3, 0.22), "head": "hat", "head_col": Color(0.85, 0.75, 0.45),
				"tabard": T, "belt": LEATHER, "r_hand": Vector3(-0.25, 1.0, 0.25)}
			_man(k, o)
			_hold(k, o, -1.0, func():
				# a pick held out ahead, head up
				var old := _along(k, Vector3(-0.25, 1.0, 0.25), Vector3(0, 0.45, 1.0))
				k.cyl(Vector3(0, -0.2, 0), Vector3(0, 0.62, 0), 0.025, 0.025, WOOD, 5)
				k.box(Vector3(0, 0.62, 0), Vector3(0.045, 0.05, 0.42), STEEL)
				k.cyl(Vector3(0, 0.62, 0.2), Vector3(0, 0.6, 0.32), 0.025, 0.0, STEEL, 4)
				k.xf = old)
			# pack with a rolled blanket
			k.box(Vector3(0.0, 1.08, -0.24), Vector3(0.3, 0.38, 0.16), LEATHER)
			k.cyl(Vector3(-0.17, 1.32, -0.24), Vector3(0.17, 1.32, -0.24), 0.07, 0.07, Color(0.6, 0.25, 0.2), 7)
		"ravnica":
			var o := {"body": Color(0.32, 0.3, 0.33), "legs": Color(0.22, 0.2, 0.24), "head": "cap", "head_col": Color(0.25, 0.22, 0.3),
				"tabard": T, "belt": LEATHER, "r_hand": Vector3(-0.27, 1.05, 0.25)}
			_man(k, o)
			_hold(k, o, -1.0, func():
				# a mason's hammer
				var old := _along(k, Vector3(-0.27, 1.05, 0.25), Vector3(0, 0.5, 1.0))
				k.cyl(Vector3(0, -0.15, 0), Vector3(0, 0.5, 0), 0.025, 0.025, WOOD, 5)
				k.box(Vector3(0, 0.52, 0), Vector3(0.1, 0.1, 0.24), p.metal)
				k.xf = old)
			k.box(Vector3(0.0, 1.1, -0.22), Vector3(0.32, 0.4, 0.14), Color(0.4, 0.3, 0.22))
			k.box(Vector3(0.0, 0.9, -0.22), Vector3(0.36, 0.04, 0.16), p.metal)
		"avishkar":
			# a servo: a small brass walking machine with one glowing eye and a cutting arm
			k.gloss = true
			k.sphere(Vector3(0, 0.95, 0), Vector3(0.3, 0.26, 0.3), p.main, 12, 6)
			k.gloss = false
			k.ring(Vector3(0, 0.95, 0), Vector3.UP, 0.3, 0.03, p.metal.darkened(0.3), 14, 4)
			for i in 8:
				var a := TAU * i / 8.0
				k.box(Vector3(cos(a) * 0.3, 0.95, sin(a) * 0.3), Vector3(0.05, 0.05, 0.05), Game.GOLD)
			k.sphere(Vector3(0, 1.02, 0.27), Vector3(0.08, 0.08, 0.05), p.glow, 8, 4, true)
			k.ring(Vector3(0, 1.02, 0.28), Vector3(0, 0, 1), 0.085, 0.015, p.metal.darkened(0.3), 10, 3)
			k.box(Vector3(0, 1.2, 0), Vector3(0.14, 0.12, 0.14), T)
			k.rig(P_TAIL, Vector3(0, 1.26, 0))
			k.cyl(Vector3(0, 1.26, 0), Vector3(0, 1.5, -0.05), 0.015, 0.015, p.metal, 4)
			k.sphere(Vector3(0, 1.52, -0.05), Vector3(0.04, 0.04, 0.04), p.glow, 6, 3, true)
			k.rig()
			for a in 4:
				var ang := TAU * (a + 0.5) / 4.0
				var d := Vector3(cos(ang), 0, sin(ang))
				k.rig(P_GAIT, Vector3(0, 0.85, 0) + d * 0.2)
				k.cyl(Vector3(0, 0.85, 0) + d * 0.2, Vector3(0, 0.62, 0) + d * 0.42, 0.04, 0.035, p.metal, 6)
				k.sphere(Vector3(0, 0.62, 0) + d * 0.42, Vector3.ONE * 0.045, p.main, 5, 3)
				k.cyl(Vector3(0, 0.62, 0) + d * 0.42, Vector3(0, 0.0, 0) + d * 0.45, 0.035, 0.015, p.metal.darkened(0.2), 6)
			k.rig(P_ARM, Vector3(0.22, 0.95, 0.15))
			k.cyl(Vector3(0.22, 0.95, 0.15), Vector3(0.38, 0.8, 0.42), 0.03, 0.03, p.metal, 5)
			k.box(Vector3(0.4, 0.78, 0.45), Vector3(0.06, 0.06, 0.14), p.trim)
			k.cyl(Vector3(0.4, 0.78, 0.5), Vector3(0.4, 0.78, 0.6), 0.04, 0.0, p.glow, 5, true)
			k.rig()


static func _soldier(k: MeshKit, race: String, role: String) -> void:
	var p := _pal(race)
	var rh := Vector3(-0.27, 1.0, 0.26)
	var lh := Vector3(0.27, 1.0, 0.22)
	match race:
		"phyrexia":
			var o := {"body": p.main, "legs": p.trim, "arms": p.trim, "head": "mask", "head_col": p.main, "boot": p.dark, "skin": p.trim,
				"tabard": T, "spikes": role != "archer", "pauldrons": p.main, "eye": p.glow}
			if role == "archer":
				# oil spitter: bloated sac on its back, a nozzle for an arm
				o.pauldrons = null
				o.r_hand = Vector3(-0.2, 1.25, 0.35)
				o.r_style = P_AIM
				_man(k, o)
				k.gloss = true
				k.sphere(Vector3(0, 1.2, -0.28), Vector3(0.3, 0.32, 0.25), Color(0.06, 0.06, 0.07), 10, 6)
				k.gloss = false
				k.ring(Vector3(0, 1.2, -0.28), Vector3(0, 1, 0.4).normalized(), 0.28, 0.02, p.trim, 12, 3)
				k.cyl(Vector3(-0.1, 1.35, -0.1), Vector3(-0.2, 1.3, 0.3), 0.03, 0.03, p.trim, 5)
				_hold(k, o, -1.0, func():
					k.cyl(Vector3(-0.2, 1.25, 0.35), Vector3(-0.2, 1.3, 0.75), 0.06, 0.03, p.metal, 7)
					k.ring(Vector3(-0.2, 1.28, 0.55), Vector3(0, 0.1, 1).normalized(), 0.05, 0.012, p.dark, 8, 3)
					k.sphere(Vector3(-0.2, 1.3, 0.76), Vector3(0.04, 0.04, 0.04), p.glow, 6, 3, true))
				return
			o.r_hand = rh
			o.l_hand = lh
			o.r_style = P_ARM if role == "infantry" else P_THRUST
			k.gloss = true
			_man(k, o)
			k.gloss = false
			if role == "infantry":
				_hold(k, o, -1.0, func(): _sword(k, rh, 1.0, p.metal, 0.95, 0.1))
				_hold(k, o, 1.0, func():
					for i in 3:
						k.cyl(lh + Vector3(-0.03 + i * 0.03, 0, 0), lh + Vector3(0.02 + i * 0.05, -0.4, 0.25), 0.03, 0.0, p.metal, 4))
			else:
				_hold(k, o, -1.0, func(): _spear(k, rh, 1.0, p.dark, p.trim, 2.6))
				for i in 3:
					k.cyl(Vector3(-0.1 + i * 0.1, 1.3, -0.12), Vector3(-0.15 + i * 0.15, 1.6, -0.3), 0.03, 0.0, p.main, 4)
		"dominaria":
			var o := {"body": STEEL, "legs": Color(0.45, 0.45, 0.5), "arms": STEEL.darkened(0.1), "head": "helm", "head_col": STEEL,
				"tabard": T, "belt": LEATHER, "pauldrons": STEEL, "glove": LEATHER}
			match role:
				"infantry":
					o.r_hand = rh
					o.l_hand = lh
					_man(k, o)
					_hold(k, o, -1.0, func(): _sword(k, rh, 1.0, Color(0.85, 0.86, 0.9)))
					_hold(k, o, 1.0, func(): _shield(k, Vector3(0.36, 1.05, 0.22), 1.0, T, p.glow.darkened(0.2), 0.3, true))
				"spear":
					o.pauldrons = null
					o.r_hand = rh
					o.r_style = P_THRUST
					_man(k, o)
					_hold(k, o, -1.0, func(): _spear(k, rh, 1.0, WOOD, STEEL, 3.0, false, T))
				"archer":
					o.body = Color(0.3, 0.42, 0.25)
					o.legs = Color(0.35, 0.3, 0.22)
					o.arms = o.body
					o.pauldrons = null
					o.head = "hood"
					o.head_col = Color(0.25, 0.36, 0.2)
					o.l_hand = Vector3(0.24, 1.2, 0.35)
					o.r_hand = Vector3(-0.1, 1.25, 0.05)
					o.r_style = P_AIM
					o.l_style = P_AIM
					_man(k, o)
					_hold(k, o, 1.0, func(): _bow(k, Vector3(0.24, 1.2, 0.35), 1.0, WOOD))
					# quiver with fletchings
					k.cyl(Vector3(0.12, 1.0, -0.2), Vector3(0.2, 1.6, -0.25), 0.07, 0.07, LEATHER, 7)
					for i in 3:
						k.box(Vector3(0.18 + i * 0.02, 1.66, -0.22 - i * 0.02), Vector3(0.015, 0.1, 0.05), Color(0.9, 0.9, 0.85))
		"ravnica":
			var o := {"body": Color(0.28, 0.22, 0.32), "legs": Color(0.2, 0.18, 0.22), "arms": Color(0.3, 0.24, 0.34), "head": "helm",
				"head_col": p.metal, "tabard": T, "belt": p.metal.darkened(0.3), "pauldrons": p.metal, "glove": DARK, "cape": true}
			match role:
				"infantry":
					o.r_hand = rh
					o.l_hand = lh
					_man(k, o)
					_hold(k, o, -1.0, func():
						# a heavy flanged mace
						var old := _along(k, rh, Vector3(0, 0.6, 1.0))
						k.cyl(Vector3(0, -0.12, 0), Vector3(0, 0.55, 0), 0.03, 0.03, DARK, 5)
						k.sphere(Vector3(0, 0.62, 0), Vector3(0.09, 0.1, 0.09), p.metal, 7, 4)
						for i in 4:
							var a := TAU * i / 4.0
							k.box(Vector3(cos(a) * 0.08, 0.62, sin(a) * 0.08), Vector3(0.04 + absf(cos(a)) * 0.04, 0.14, 0.04 + absf(sin(a)) * 0.04), p.metal.darkened(0.2))
						k.xf = old)
					_hold(k, o, 1.0, func(): _shield(k, Vector3(0.36, 1.05, 0.22), 1.0, p.metal, T, 0.32))
				"spear":
					o.r_hand = rh
					o.pauldrons = null
					o.r_style = P_THRUST
					_man(k, o)
					_hold(k, o, -1.0, func():
						_spear(k, rh, 1.0, DARK, p.metal, 2.8)
						# the halberd's axe blade
						var old := _along(k, rh, Vector3(0, 2.8, 0.5))
						_slab(k, Vector3(0, 1.85, -0.12), PackedVector2Array([Vector2(0, 0.12), Vector2(0, -0.12), Vector2(-0.05, -0.2), Vector2(-0.2, 0.0), Vector2(-0.05, 0.2)]), 0.02, p.metal)
						k.xf = old)
				"archer":
					o.head = "hat"
					o.head_col = DARK
					o.pauldrons = null
					o.l_hand = Vector3(0.12, 1.25, 0.32)
					o.r_hand = Vector3(-0.12, 1.2, 0.3)
					o.r_style = P_AIM
					o.l_style = P_AIM
					_man(k, o)
					_hold(k, o, 1.0, func():
						# a heavy crossbow
						k.box(Vector3(0, 1.25, 0.45), Vector3(0.08, 0.09, 0.6), WOOD)
						k.box(Vector3(0, 1.25, 0.2), Vector3(0.07, 0.14, 0.12), WOOD.darkened(0.2))
						var bow := [Vector3(-0.32, 1.27, 0.6), Vector3(-0.15, 1.28, 0.7), Vector3(0, 1.28, 0.72), Vector3(0.15, 1.28, 0.7), Vector3(0.32, 1.27, 0.6)]
						for i in 4:
							k.cyl(bow[i], bow[i + 1], 0.022, 0.022, p.metal, 5, false, true, false)
						k.cyl(bow[0], Vector3(0, 1.28, 0.4), 0.005, 0.005, Color(0.9, 0.88, 0.8), 3)
						k.cyl(bow[4], Vector3(0, 1.28, 0.4), 0.005, 0.005, Color(0.9, 0.88, 0.8), 3)
						k.box(Vector3(0, 1.3, 0.58), Vector3(0.015, 0.015, 0.36), DARK))
		"avishkar":
			var o := {"body": Color(0.9, 0.86, 0.76), "legs": p.trim.darkened(0.3), "arms": Color(0.88, 0.84, 0.74), "head": "turban",
				"head_col": Color(0.95, 0.92, 0.85), "tabard": T, "belt": p.main, "pauldrons": p.main, "glove": p.main, "eye": p.glow}
			match role:
				"spear":
					o.r_hand = rh
					o.r_style = P_THRUST
					_man(k, o)
					_hold(k, o, -1.0, func():
						_spear(k, rh, 1.0, p.main, p.glow, 2.6, true)
						k.ring(rh + Vector3(0, 0.9, 0.12), Vector3(0, 1, 0.3), 0.06, 0.015, p.main, 8, 3))
					_hold(k, o, 1.0, func():
						_shield(k, Vector3(0.36, 1.05, 0.22), 1.0, p.main, p.glow, 0.26)
						for i in 6:
							var a := TAU * i / 6.0
							k.box(Vector3(0.36 + cos(a) * 0.16, 1.05 + sin(a) * 0.16, 0.32), Vector3(0.03, 0.03, 0.02), p.glow, true))
				"archer":
					o.pauldrons = null
					o.l_hand = Vector3(0.1, 1.2, 0.4)
					o.r_hand = Vector3(-0.1, 1.15, 0.2)
					o.r_style = P_AIM
					o.l_style = P_AIM
					_man(k, o)
					_hold(k, o, -1.0, func(): _gun(k, Vector3(0, 1.15, 0.2), 1.0, p.main, p.glow, 1.0))
					k.cyl(Vector3(0, 1.05, -0.2), Vector3(0, 1.5, -0.22), 0.09, 0.09, p.trim, 8)
					k.cyl(Vector3(0, 1.12, -0.29), Vector3(0, 1.42, -0.3), 0.03, 0.03, p.glow, 6, true)


static func _caster(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	var lh := Vector3(0.27, 1.05, 0.22)
	match race:
		"dominaria":
			var o := {"robe": true, "body": Color(0.22, 0.3, 0.6), "legs": Color(0.18, 0.25, 0.55), "head": "hood", "head_col": Color(0.2, 0.28, 0.58),
				"l_hand": lh, "l_style": P_CAST, "r_style": P_CAST, "r_hand": Vector3(-0.25, 1.1, 0.28), "belt": Color(0.85, 0.7, 0.3), "tabard": T}
			_man(k, o)
			_hold(k, o, 1.0, func(): _staff(k, lh, 1.0, WOOD, Color(0.5, 0.75, 1.0)))
			k.box(Vector3(-0.17, 0.82, 0.1), Vector3(0.1, 0.13, 0.04), Color(0.55, 0.3, 0.15))
		"ravnica":
			var o := {"robe": true, "body": Color(0.3, 0.15, 0.38), "legs": Color(0.22, 0.1, 0.3), "head": "hood", "head_col": DARK,
				"l_hand": lh, "r_hand": Vector3(-0.2, 1.2, 0.35), "r_style": P_CAST, "belt": p.metal, "tabard": T}
			_man(k, o)
			_hold(k, o, -1.0, func():
				k.sphere(Vector3(-0.2, 1.35, 0.38), Vector3(0.1, 0.1, 0.1), p.glow, 8, 5, true)
				k.ring(Vector3(-0.2, 1.35, 0.38), Vector3(0.3, 1, 0), 0.16, 0.012, p.glow, 12, 3, true))
			# a hanging tome
			k.box(Vector3(0.2, 0.8, 0.08), Vector3(0.06, 0.2, 0.15), Color(0.4, 0.12, 0.12))
		"avishkar":
			var o := {"body": Color(0.92, 0.88, 0.8), "legs": p.trim.darkened(0.4), "head": "turban", "head_col": p.trim, "tabard": T,
				"belt": p.main, "eye": p.glow, "r_hand": Vector3(-0.27, 1.05, 0.3), "r_style": P_AIM}
			_man(k, o)
			# backpack apparatus with two aether tanks
			k.box(Vector3(0, 1.2, -0.26), Vector3(0.34, 0.45, 0.18), p.main)
			for x in [-0.12, 0.12]:
				k.cyl(Vector3(x, 1.0, -0.34), Vector3(x, 1.5, -0.34), 0.07, 0.07, p.glow, 8, true)
				k.ring(Vector3(x, 1.02, -0.34), Vector3.UP, 0.075, 0.015, p.metal, 8, 3)
				k.ring(Vector3(x, 1.48, -0.34), Vector3.UP, 0.075, 0.015, p.metal, 8, 3)
			k.cyl(Vector3(-0.12, 1.5, -0.34), Vector3(-0.27, 1.2, 0.0), 0.02, 0.02, p.metal.darkened(0.3), 4)
			_hold(k, o, -1.0, func():
				k.cyl(Vector3(-0.27, 1.05, 0.3), Vector3(-0.27, 1.1, 0.75), 0.04, 0.02, p.main, 7)
				k.ring(Vector3(-0.27, 1.08, 0.55), Vector3(0, 0.1, 1).normalized(), 0.05, 0.012, p.metal.darkened(0.3), 8, 3)
				k.sphere(Vector3(-0.27, 1.1, 0.78), Vector3(0.05, 0.05, 0.05), p.glow, 6, 3, true))
		_:
			_man(k, {"robe": true, "body": p.main, "head": "hood", "head_col": p.dark, "tabard": T})


static func _champion(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	var s := 1.6
	match race:
		"phyrexia":
			var rh := Vector3(-0.27, 1.0, 0.26)
			var o := {"s": s, "body": p.main, "legs": p.trim, "arms": p.main, "head": "mask", "head_col": p.main, "boot": p.dark, "skin": p.trim,
				"tabard": T, "spikes": true, "pauldrons": p.main, "eye": p.glow, "cape": true, "cape_col": p.dark, "r_hand": rh}
			k.gloss = true
			_man(k, o)
			k.gloss = false
			_hold(k, o, -1.0, func(): _sword(k, rh, s, p.metal, 1.3, 0.16))
			for a in 5:
				var ang := -0.9 + a * 0.45
				k.cyl(Vector3(sin(ang) * 0.12, 1.78, -0.05) * s, Vector3(sin(ang) * 0.3, 2.15, -0.12) * s, 0.025 * s, 0.0, p.dark, 4)
			# exposed sinew down the chest
			for side in [-1.0, 1.0]:
				k.cyl(Vector3(side * 0.08, 0.95, 0.15) * s, Vector3(side * 0.12, 1.35, 0.13) * s, 0.025 * s, 0.025 * s, p.trim.darkened(0.2), 5)
		"dominaria":
			var rh := Vector3(-0.27, 1.05, 0.28)
			var o := {"s": 1.45, "body": Color(0.95, 0.9, 0.75), "legs": Color(0.9, 0.85, 0.7), "arms": Color(0.95, 0.9, 0.75), "head": "bare",
				"hair": Color(0.95, 0.82, 0.45), "skin": Color(0.95, 0.85, 0.75), "tabard": T, "belt": p.glow, "pauldrons": p.glow, "r_hand": rh, "robe": true}
			_man(k, o)
			_hold(k, o, -1.0, func(): _sword(k, rh, 1.45, Color(1.0, 0.95, 0.7), 1.1, 0.1))
			k.sphere(Vector3(0, 2.6, -0.02), Vector3(0.24, 0.05, 0.24), p.glow, 10, 3, true)
			for side in [-1.0, 1.0]:
				_wing(k, Vector3(side * 0.15, 1.95, -0.25), side, 1.7, Color(1, 1, 0.97), Color(0.9, 0.92, 1.0), 0.9, 7)
		"ravnica":
			# a stone guardian golem with glowing runes
			var stone := Color(0.5, 0.48, 0.5)
			for side in [-1.0, 1.0]:
				k.rig(P_LEG, Vector3(side * 0.25, 0.65, 0))
				k.box(Vector3(side * 0.25, 0.42, 0), Vector3(0.4, 0.5, 0.45), stone.darkened(0.2))
				k.box(Vector3(side * 0.25, 0.1, 0.05), Vector3(0.46, 0.2, 0.6), stone.darkened(0.28))
				k.box(Vector3(side * 0.25, 0.42, 0.23), Vector3(0.06, 0.25, 0.02), p.glow, true)
			k.rig()
			k.box(Vector3(0, 0.8, 0), Vector3(0.75, 0.4, 0.5), stone.darkened(0.15))
			k.taper(Vector3(0, 1.0, 0), Vector2(0.9, 0.6), Vector2(1.3, 0.8), 1.2, stone)
			for i in 3:
				k.box(Vector3(0, 1.25 + i * 0.3, 0.32 + i * 0.03), Vector3(0.9 + i * 0.12, 0.06, 0.04), stone.darkened(0.25))
			k.rig(P_HEAD, Vector3(0, 2.15, 0.05))
			k.box(Vector3(0, 2.3, 0.05), Vector3(0.45, 0.4, 0.45), stone)
			k.box(Vector3(0, 2.32, 0.28), Vector3(0.3, 0.06, 0.03), p.glow, true)
			k.box(Vector3(0, 2.52, 0.05), Vector3(0.5, 0.06, 0.5), stone.darkened(0.2))
			k.rig()
			k.box(Vector3(0, 1.6, 0.42), Vector3(0.5, 0.5, 0.04), T)
			for side in [-1.0, 1.0]:
				k.box(Vector3(side * 0.85, 1.6, 0), Vector3(0.45, 0.45, 0.5), stone.darkened(0.05))
				k.rig(P_ARM if side < 0.0 else P_GUARD, Vector3(side * 0.88, 1.6, 0))
				k.box(Vector3(side * 0.9, 1.15, 0.05), Vector3(0.35, 0.6, 0.38), stone)
				k.box(Vector3(side * 0.92, 0.8, 0.18), Vector3(0.38, 0.35, 0.4), stone.darkened(0.1))
				k.box(Vector3(side * 0.92, 0.48, 0.24), Vector3(0.48, 0.38, 0.48), stone.darkened(0.2))
				k.box(Vector3(side * 0.92, 1.15, 0.25), Vector3(0.08, 0.3, 0.03), p.glow, true)
				k.rig()
		"avishkar":
			# a brass walking colossus
			k.gloss = true
			k.sphere(Vector3(0, 2.0, 0), Vector3(0.75, 0.6, 0.6), p.main, 14, 7)
			k.gloss = false
			k.ring(Vector3(0, 2.0, 0), Vector3.UP, 0.74, 0.05, p.metal.darkened(0.3), 18, 4)
			for i in 10:
				var a := TAU * i / 10.0
				k.sphere(Vector3(cos(a) * 0.74, 2.0, sin(a) * 0.58), Vector3.ONE * 0.04, Game.GOLD, 5, 3)
			k.rig(P_HEAD, Vector3(0, 2.1, 0.4))
			k.sphere(Vector3(0, 2.15, 0.55), Vector3(0.15, 0.15, 0.1), p.glow, 8, 5, true)
			k.ring(Vector3(0, 2.15, 0.58), Vector3(0, 0, 1), 0.16, 0.03, p.metal.darkened(0.3), 12, 3)
			k.rig()
			k.box(Vector3(0, 2.55, 0), Vector3(0.4, 0.2, 0.4), T)
			for side in [-1.0, 1.0]:
				k.rig(P_LEG, Vector3(side * 0.35, 1.6, 0))
				k.cyl(Vector3(side * 0.35, 1.6, 0), Vector3(side * 0.5, 0.75, 0.1), 0.14, 0.11, p.metal, 8)
				k.sphere(Vector3(side * 0.5, 0.75, 0.1), Vector3.ONE * 0.13, p.main, 7, 4)
				k.cyl(Vector3(side * 0.5, 0.75, 0.1), Vector3(side * 0.55, 0.05, 0.0), 0.11, 0.16, p.metal.darkened(0.2), 8)
				k.box(Vector3(side * 0.55, 0.04, 0.1), Vector3(0.36, 0.08, 0.5), p.main.darkened(0.2))
				k.rig(P_ARM if side < 0.0 else P_GUARD, Vector3(side * 0.7, 2.1, 0))
				k.cyl(Vector3(side * 0.7, 2.1, 0), Vector3(side * 1.05, 1.4, 0.2), 0.12, 0.1, p.metal, 8)
				k.box(Vector3(side * 1.1, 1.2, 0.3), Vector3(0.28, 0.4, 0.3), p.main)
				for f in 3:
					k.cyl(Vector3(side * (1.0 + f * 0.08), 1.02, 0.38), Vector3(side * (1.0 + f * 0.08), 0.88, 0.45), 0.035, 0.02, p.metal.darkened(0.2), 4)
				k.rig()
				k.cyl(Vector3(side * 0.3, 2.4, -0.35), Vector3(side * 0.3, 3.0, -0.4), 0.08, 0.05, p.glow, 6, true)


static func _cavalry(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	match race:
		"dominaria":
			_horse(k, Color(0.9, 0.88, 0.84), Color(0.75, 0.72, 0.65), T, true)
			k.xf = Transform3D(Basis(), Vector3(0, 0.75, -0.05))
			var o := {"body": STEEL, "legs": STEEL.darkened(0.2), "head": "plume", "head_col": STEEL, "tabard": T, "pauldrons": STEEL, "mounted": true,
				"r_hand": Vector3(-0.3, 1.1, 0.25), "l_hand": Vector3(0.3, 1.1, 0.25), "r_style": P_THRUST}
			_man(k, o)
			_hold(k, o, -1.0, func(): _spear(k, Vector3(-0.3, 1.1, 0.25), 1.0, Color(0.85, 0.8, 0.7), STEEL, 3.0, false, T))
			_hold(k, o, 1.0, func(): _shield(k, Vector3(0.4, 1.15, 0.15), 1.0, T, p.glow, 0.28, true))
			k.xf = Transform3D.IDENTITY
		"phyrexia":
			# a ravager hound: a big porcelain beast with exposed sinew, a spiked spine and a jaw
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 1.0, -0.95), 0.15, 0.15, 10), _ring_pts(Vector3(0, 1.05, -0.6), 0.38, 0.38, 10), _ring_pts(Vector3(0, 1.0, 0.0), 0.36, 0.36, 10),
				_ring_pts(Vector3(0, 1.08, 0.5), 0.42, 0.44, 10), _ring_pts(Vector3(0, 1.12, 0.78), 0.26, 0.3, 10)], p.main)
			k.gloss = false
			k.sphere(Vector3(0, 0.88, 0.1), Vector3(0.3, 0.26, 0.6), p.trim, 9, 5)
			k.rig(P_HEAD, Vector3(0, 1.1, 0.75))
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 1.12, 0.75), 0.24, 0.26, 8), _ring_pts(Vector3(0, 1.15, 1.05), 0.24, 0.2, 8), _ring_pts(Vector3(0, 1.1, 1.38), 0.15, 0.12, 8)], p.main)
			k.gloss = false
			k.box(Vector3(0, 0.96, 1.2), Vector3(0.3, 0.07, 0.38), p.trim)
			for i in 5:
				k.cyl(Vector3(-0.12 + i * 0.06, 1.03, 1.32), Vector3(-0.12 + i * 0.06, 0.95, 1.36), 0.018, 0.0, Color(0.95, 0.93, 0.88), 4)
			k.box(Vector3(0, 1.2, 1.25), Vector3(0.2, 0.03, 0.05), p.glow, true)
			k.rig()
			for x in [-0.28, 0.28]:
				for z in [-0.6, 0.5]:
					k.rig(P_GAIT, Vector3(x, 1.0, z))
					k.cyl(Vector3(x, 1.0, z), Vector3(x * 1.3, 0.5, z + 0.15), 0.11, 0.07, p.trim, 7)
					k.sphere(Vector3(x * 1.3, 0.5, z + 0.15), Vector3.ONE * 0.075, p.main, 6, 3)
					k.cyl(Vector3(x * 1.3, 0.5, z + 0.15), Vector3(x * 1.2, 0.0, z + 0.05), 0.07, 0.03, p.main, 6)
					for c in 3:
						k.cyl(Vector3(x * 1.2, 0.04, z + 0.05), Vector3(x * 1.2 + (c - 1) * 0.06, 0.0, z + 0.2), 0.022, 0.0, p.dark, 4)
			k.rig()
			for i in 6:
				var z := 0.7 - i * 0.28
				k.cyl(Vector3(0, 1.35, z), Vector3(0, 1.75 - i * 0.03, z - 0.15), 0.06, 0.0, p.dark, 5)
			k.box(Vector3(0, 1.38, -0.2), Vector3(0.5, 0.1, 0.6), T)
			k.rig(P_TAIL, Vector3(0, 1.0, -0.9))
			k.cyl(Vector3(0, 1.0, -0.85), Vector3(0, 1.2, -1.4), 0.07, 0.02, p.trim, 5)
			k.rig()
		"avishkar":
			# an aethercycle with its rider
			for z in [0.75, -0.75]:
				k.rig(P_WHEEL, Vector3(0, 0.42, z))
				k.ring(Vector3(0, 0.42, z), Vector3.RIGHT, 0.36, 0.08, DARK, 16, 5)
				k.ring(Vector3(0, 0.42, z), Vector3.RIGHT, 0.26, 0.03, p.glow, 14, 3, true)
				for i in 3:
					var d := Vector3(0, sin(PI * i / 3.0), cos(PI * i / 3.0)) * 0.27
					k.cyl(Vector3(0, 0.42, z) - d, Vector3(0, 0.42, z) + d, 0.025, 0.025, p.metal, 4, false, true, false)
				k.cyl(Vector3(-0.09, 0.42, z), Vector3(0.09, 0.42, z), 0.06, 0.06, p.main, 8)
				k.rig()
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 0.6, -0.95), 0.12, 0.1, 10), _ring_pts(Vector3(0, 0.75, -0.3), 0.26, 0.2, 10), _ring_pts(Vector3(0, 0.78, 0.35), 0.24, 0.18, 10),
				_ring_pts(Vector3(0, 0.62, 1.0), 0.08, 0.07, 10)], p.main)
			k.gloss = false
			k.box(Vector3(0, 0.9, -0.2), Vector3(0.36, 0.08, 0.5), T)
			k.ring(Vector3(0, 0.76, 0.0), Vector3(0, 0, 1), 0.25, 0.025, p.glow, 12, 3, true)
			for side in [-1.0, 1.0]:
				k.cyl(Vector3(side * 0.18, 0.6, -0.7), Vector3(side * 0.22, 0.6, -1.1), 0.06, 0.08, p.metal, 7)
				k.sphere(Vector3(side * 0.22, 0.6, -1.12), Vector3(0.05, 0.05, 0.03), p.glow, 6, 3, true)
				k.cyl(Vector3(side * 0.08, 0.7, 0.85), Vector3(side * 0.06, 0.42, 0.75), 0.025, 0.025, p.metal, 4)
			k.xf = Transform3D(Basis(Vector3.RIGHT, 0.35), Vector3(0, 0.05, -0.15))
			var o := {"body": Color(0.9, 0.86, 0.76), "legs": p.trim.darkened(0.3), "head": "helm", "head_col": p.main, "tabard": T, "mounted": true,
				"r_hand": Vector3(-0.25, 1.0, 0.55), "l_hand": Vector3(0.25, 1.0, 0.55), "r_style": P_BODY, "l_style": P_BODY}
			_man(k, o)
			k.xf = Transform3D.IDENTITY
			k.cyl(Vector3(-0.3, 1.1, 0.55), Vector3(0.3, 1.1, 0.55), 0.025, 0.025, p.metal, 5)
		_:
			_horse(k, LEATHER, DARK, T)


static func _flyer(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	match race:
		"dominaria":
			_horse(k, Color(0.97, 0.97, 0.95), Color(0.9, 0.9, 0.95), T, false, true)
			for side in [-1.0, 1.0]:
				_wing(k, Vector3(side * 0.3, 1.45, 0.2), side, 1.6, Color(1, 1, 1), Color(0.85, 0.88, 0.95), 0.7, 7)
			k.xf = Transform3D(Basis(), Vector3(0, 0.75, -0.05))
			var o := {"body": STEEL, "head": "helm", "head_col": STEEL, "tabard": T, "mounted": true, "r_hand": Vector3(-0.3, 1.1, 0.25), "r_style": P_THRUST}
			_man(k, o)
			_hold(k, o, -1.0, func(): _spear(k, Vector3(-0.3, 1.1, 0.25), 1.0, WOOD, STEEL, 2.2, false, T))
			k.xf = Transform3D.IDENTITY
		"phyrexia":
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 1.1, -0.6), 0.25, 0.22, 10), _ring_pts(Vector3(0, 1.15, 0.2), 0.32, 0.3, 10), _ring_pts(Vector3(0, 1.3, 0.9), 0.18, 0.16, 10)], p.main)
			k.gloss = false
			k.rig(P_HEAD, Vector3(0, 1.3, 0.85))
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 1.3, 0.85), 0.18, 0.16, 8), _ring_pts(Vector3(0, 1.35, 1.4), 0.12, 0.1, 8), _ring_pts(Vector3(0, 1.3, 1.7), 0.04, 0.04, 8)], p.main)
			k.gloss = false
			k.box(Vector3(0, 1.4, 1.42), Vector3(0.16, 0.025, 0.05), p.glow, true)
			for side in [-1.0, 1.0]:
				k.cyl(Vector3(side * 0.06, 1.42, 1.2), Vector3(side * 0.12, 1.6, 0.95), 0.03, 0.0, p.dark, 4)
			k.rig()
			k.rig(P_TAIL, Vector3(0, 1.1, -0.6))
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 1.1, -0.6), 0.25, 0.22, 8), _ring_pts(Vector3(0, 1.05, -1.2), 0.12, 0.1, 8), _ring_pts(Vector3(0, 1.0, -1.8), 0.03, 0.03, 8)], p.main)
			k.gloss = false
			k.cyl(Vector3(0, 1.0, -1.75), Vector3(0, 1.15, -2.1), 0.08, 0.0, p.dark, 4)
			k.rig()
			k.sphere(Vector3(0, 1.0, 0.1), Vector3(0.25, 0.2, 0.5), p.trim, 8, 4)
			k.box(Vector3(0, 1.43, 0.1), Vector3(0.3, 0.08, 0.5), T)
			for i in 4:
				k.cyl(Vector3(0, 1.4, 0.5 - i * 0.3), Vector3(0, 1.62, 0.4 - i * 0.3), 0.04, 0.0, p.dark, 4)
			for side in [-1.0, 1.0]:
				_wing(k, Vector3(side * 0.25, 1.25, 0.3), side, 2.0, p.dark, p.trim, 0.6, 6)
		"ravnica":
			# a skyknight on a winged beast
			var hide := Color(0.55, 0.42, 0.28)
			k.loft([_ring_pts(Vector3(0, 1.12, -0.75), 0.15, 0.15, 10), _ring_pts(Vector3(0, 1.1, -0.35), 0.34, 0.34, 10), _ring_pts(Vector3(0, 1.12, 0.3), 0.33, 0.34, 10),
				_ring_pts(Vector3(0, 1.25, 0.7), 0.2, 0.22, 10)], hide)
			k.rig(P_HEAD, Vector3(0, 1.3, 0.7))
			k.sphere(Vector3(0, 1.4, 0.85), Vector3(0.2, 0.22, 0.25), Color(0.85, 0.82, 0.75), 8, 5)
			k.cyl(Vector3(0, 1.38, 1.0), Vector3(0, 1.3, 1.25), 0.07, 0.0, Color(0.9, 0.7, 0.2), 5)
			for side in [-1.0, 1.0]:
				k.box(Vector3(side * 0.12, 1.47, 1.0), Vector3(0.03, 0.03, 0.03), DARK)
				k.cyl(Vector3(side * 0.08, 1.55, 0.78), Vector3(side * 0.14, 1.72, 0.62), 0.04, 0.0, Color(0.85, 0.82, 0.75), 4)
			k.rig()
			for x in [-0.18, 0.18]:
				for z in [-0.4, 0.45]:
					k.cyl(Vector3(x, 0.95, z), Vector3(x, 0.62, z + 0.18), 0.07, 0.05, hide.darkened(0.1), 5)
					k.cyl(Vector3(x, 0.62, z + 0.18), Vector3(x, 0.58, z + 0.32), 0.04, 0.0, Color(0.9, 0.7, 0.2), 4)
			for side in [-1.0, 1.0]:
				_wing(k, Vector3(side * 0.25, 1.35, 0.2), side, 1.7, Color(0.6, 0.5, 0.4), Color(0.85, 0.8, 0.7), 0.7, 6)
			k.rig(P_TAIL, Vector3(0, 1.1, -0.75))
			k.cyl(Vector3(0, 1.1, -0.75), Vector3(0, 1.0, -1.3), 0.06, 0.02, hide, 5)
			k.box(Vector3(0, 1.0, -1.32), Vector3(0.16, 0.03, 0.14), Color(0.85, 0.8, 0.7))
			k.rig()
			k.box(Vector3(0, 1.32, -0.05), Vector3(0.75, 0.15, 0.6), T)
			k.xf = Transform3D(Basis(), Vector3(0, 0.6, -0.1))
			var o := {"body": Color(0.28, 0.22, 0.32), "head": "helm", "head_col": p.metal, "tabard": T, "cape": true, "mounted": true,
				"r_hand": Vector3(-0.3, 1.1, 0.25), "r_style": P_THRUST}
			_man(k, o)
			_hold(k, o, -1.0, func(): _spear(k, Vector3(-0.3, 1.1, 0.25), 1.0, DARK, p.metal, 2.4))
			k.xf = Transform3D.IDENTITY
		"avishkar":
			# a thopter: brass body and filigree wings rimmed with aether
			k.gloss = true
			k.loft([_ring_pts(Vector3(0, 1.05, -0.6), 0.1, 0.09, 10), _ring_pts(Vector3(0, 1.1, -0.2), 0.28, 0.24, 10), _ring_pts(Vector3(0, 1.12, 0.3), 0.26, 0.22, 10),
				_ring_pts(Vector3(0, 1.15, 0.62), 0.1, 0.1, 10)], p.main)
			k.gloss = false
			for i in 3:
				k.ring(Vector3(0, 1.1, -0.3 + i * 0.3), Vector3(0, 0, 1), 0.26, 0.02, p.metal.darkened(0.3), 12, 3)
			k.sphere(Vector3(0, 1.15, 0.6), Vector3(0.1, 0.1, 0.06), p.glow, 7, 4, true)
			k.box(Vector3(0, 1.34, -0.1), Vector3(0.18, 0.1, 0.4), T)
			k.rig(P_TAIL, Vector3(0, 1.05, -0.55))
			k.cyl(Vector3(0, 1.05, -0.5), Vector3(0, 1.1, -1.2), 0.05, 0.02, p.metal, 5)
			k.box(Vector3(0, 1.15, -1.2), Vector3(0.5, 0.03, 0.2), p.main)
			k.box(Vector3(0, 1.25, -1.2), Vector3(0.03, 0.2, 0.18), p.main)
			k.rig()
			for side in [-1.0, 1.0]:
				for w in 2:
					var root := Vector3(side * 0.2, 1.2, 0.15 - w * 0.35)
					var tip := root + Vector3(side * 1.4, 0.25 - w * 0.15, -0.15)
					var back := root + Vector3(side * 0.6, 0.05, -0.35)
					k.rig(P_WING, root)
					var film := Color(0.85, 0.95, 1.0).lerp(p.main, 0.4)
					k.tri(root, tip, back, film)
					k.tri(root, back, tip, film)
					k.cyl(root, tip, 0.02, 0.01, p.glow, 4, true)
					k.cyl(back, tip, 0.012, 0.008, p.metal, 4)
					k.cyl(root.lerp(tip, 0.3), back, 0.01, 0.01, p.metal, 3)
					k.rig()
			for side in [-1.0, 1.0]:
				k.cyl(Vector3(side * 0.1, 0.95, -0.15), Vector3(side * 0.15, 0.75, 0.15), 0.02, 0.02, p.metal, 4)
				k.cyl(Vector3(side * 0.15, 0.75, 0.15), Vector3(side * 0.15, 0.7, 0.3), 0.02, 0.0, p.metal, 4)


static func _siege(k: MeshKit, race: String) -> void:
	var p := _pal(race)
	match race:
		"phyrexia":
			# gorger engine: a crawling furnace with a toothed maw
			k.gloss = true
			k.taper(Vector3(0, 0.55, 0), Vector2(1.3, 1.9), Vector2(1.15, 1.7), 0.9, p.main)
			k.gloss = false
			for i in 4:
				k.box(Vector3(0, 1.0, -0.75 + i * 0.5), Vector3(1.34, 0.06, 0.08), p.main.darkened(0.2))
			k.rig(P_HEAD, Vector3(0, 1.3, 0.85))
			k.box(Vector3(0, 1.0, 1.0), Vector3(1.0, 0.6, 0.15), p.trim)
			for i in 6:
				k.cyl(Vector3(-0.4 + i * 0.16, 1.3, 1.02), Vector3(-0.4 + i * 0.16, 1.1, 1.1), 0.04, 0.0, p.main, 4)
				k.cyl(Vector3(-0.32 + i * 0.13, 0.72, 1.02), Vector3(-0.32 + i * 0.13, 0.9, 1.1), 0.035, 0.0, p.main, 4)
			k.sphere(Vector3(0, 1.0, 1.05), Vector3(0.3, 0.2, 0.05), p.glow, 8, 3, true)
			k.rig()
			k.box(Vector3(0, 1.5, -0.2), Vector3(0.9, 0.2, 1.1), T)
			for i in 3:
				var z := -0.6 + i * 0.6
				for side in [-1.0, 1.0]:
					k.rig(P_GAIT, Vector3(side * 0.6, 0.9, z))
					k.cyl(Vector3(side * 0.6, 0.9, z), Vector3(side * 1.1, 0.6, z + 0.2), 0.08, 0.06, p.dark, 6)
					k.sphere(Vector3(side * 1.1, 0.6, z + 0.2), Vector3.ONE * 0.07, p.main, 5, 3)
					k.cyl(Vector3(side * 1.1, 0.6, z + 0.2), Vector3(side * 1.15, 0.0, z + 0.25), 0.06, 0.02, p.metal, 6)
			k.rig()
			for x in [0.35, -0.35]:
				k.cyl(Vector3(x, 1.45, -0.6), Vector3(x * 1.15, 2.2 if x > 0.0 else 2.0, -0.75), 0.12, 0.08, p.dark, 7)
				k.cyl(Vector3(x * 1.15, 2.18 if x > 0.0 else 1.98, -0.75), Vector3(x * 1.15, 2.24 if x > 0.0 else 2.04, -0.76), 0.085, 0.085, Color(1.0, 0.4, 0.15), 7, true)
		"ravnica":
			# spark cannon: a cart carrying a coil and a crackling orb
			for side in [-1.0, 1.0]:
				for z in [-0.55, 0.55]:
					var c := Vector3(side * 0.62, 0.38, z)
					k.rig(P_WHEEL, c)
					k.ring(c, Vector3.RIGHT, 0.33, 0.05, WOOD, 14, 4)
					for i in 3:
						var d := Vector3(0, sin(PI * i / 3.0), cos(PI * i / 3.0)) * 0.3
						k.cyl(c - d, c + d, 0.025, 0.025, WOOD.darkened(0.15), 4, false, true, false)
					k.cyl(c - Vector3(0.06, 0, 0), c + Vector3(0.06, 0, 0), 0.07, 0.07, p.metal, 7)
					k.rig()
			k.box(Vector3(0, 0.6, 0), Vector3(1.1, 0.2, 1.6), WOOD.darkened(0.1))
			k.box(Vector3(0, 0.72, 0), Vector3(1.0, 0.05, 1.5), T)
			k.cyl(Vector3(0, 0.75, -0.2), Vector3(0, 1.7, 0.1), 0.25, 0.16, p.metal, 12)
			for i in 6:
				k.ring(Vector3(0, 0.9 + i * 0.13, -0.15 + i * 0.04), Vector3(0, 1, 0.3), 0.27 - i * 0.015, 0.025, Color(0.75, 0.45, 0.2), 12, 3)
			k.rig(P_SPIN, Vector3(0, 1.85, 0.15))
			k.sphere(Vector3(0, 1.85, 0.15), Vector3(0.2, 0.2, 0.2), p.glow, 9, 6, true)
			k.ring(Vector3(0, 1.85, 0.15), Vector3(0.4, 1, 0.2).normalized(), 0.32, 0.015, p.glow, 14, 3, true)
			k.rig()
			k.rig(P_RECOIL, Vector3(0, 1.1, 0.7))
			k.cyl(Vector3(0, 1.0, 0.3), Vector3(0, 1.2, 1.1), 0.1, 0.07, p.metal.darkened(0.3), 9)
			k.ring(Vector3(0, 1.2, 1.1), Vector3(0, 0.25, 1).normalized(), 0.08, 0.02, p.metal, 9, 3)
			k.rig()
		"avishkar":
			# aether cannon: a brass barrel on a wheeled carriage with glowing tanks
			for side in [-1.0, 1.0]:
				var c := Vector3(side * 0.62, 0.48, -0.2)
				k.rig(P_WHEEL, c)
				k.ring(c, Vector3.RIGHT, 0.45, 0.07, p.metal, 16, 4)
				k.ring(c, Vector3.RIGHT, 0.2, 0.04, p.glow, 10, 3, true)
				for i in 4:
					var d := Vector3(0, sin(PI * i / 4.0), cos(PI * i / 4.0)) * 0.41
					k.cyl(c - d, c + d, 0.03, 0.03, p.main, 4, false, true, false)
				k.rig()
			k.box(Vector3(0, 0.6, -0.3), Vector3(0.9, 0.3, 1.3), p.dark)
			k.box(Vector3(0, 0.78, -0.4), Vector3(0.85, 0.06, 1.1), T)
			k.cyl(Vector3(0.3, 0.9, -0.9), Vector3(0.3, 1.4, -0.9), 0.12, 0.12, p.glow, 8, true)
			k.cyl(Vector3(-0.3, 0.9, -0.9), Vector3(-0.3, 1.4, -0.9), 0.12, 0.12, p.glow, 8, true)
			for x in [-0.3, 0.3]:
				k.ring(Vector3(x, 0.92, -0.9), Vector3.UP, 0.13, 0.02, p.metal, 8, 3)
				k.ring(Vector3(x, 1.38, -0.9), Vector3.UP, 0.13, 0.02, p.metal, 8, 3)
			k.rig(P_RECOIL, Vector3(0, 1.1, 0.0))
			k.gloss = true
			k.cyl(Vector3(0, 0.95, -0.6), Vector3(0, 1.35, 1.2), 0.3, 0.2, p.main, 14)
			k.gloss = false
			k.ring(Vector3(0, 1.32, 1.12), Vector3(0, 0.22, 1).normalized(), 0.22, 0.05, p.metal.darkened(0.3), 12, 4)
			k.ring(Vector3(0, 1.1, 0.3), Vector3(0, 0.22, 1).normalized(), 0.28, 0.04, p.metal.darkened(0.3), 12, 4)
			k.cyl(Vector3(0, 1.33, 1.15), Vector3(0, 1.34, 1.2), 0.14, 0.14, p.glow, 10, true)
			k.rig()
		_:
			k.box(Vector3(0, 0.6, 0), Vector3(1, 0.4, 1.5), WOOD)


# --- buildings ------------------------------------------------------------------------------

static func building(race: String, role: String) -> ArrayMesh:
	var key := "b:%s:%s" % [race, role]
	if _cache.has(key):
		return _cache[key]
	var k := MeshKit.new()
	var w: float = Data.BUILDINGS[role].size * Data.CELL - 0.5
	_footing(k, race, w)
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


## The ground a building stands on: cobbles (Dominaria), dark flagstones (Ravnica), cream
## tiles edged in brass (Avishkar) or a riveted plate with oil seams (Phyrexia).
static func _footing(k: MeshKit, race: String, w: float) -> void:
	var hw := w * 0.5 + 0.2
	var rng := RandomNumberGenerator.new()
	rng.seed = int(w * 100.0) + race.length()
	match race:
		"phyrexia":
			k.cyl(Vector3(0, -0.1, 0), Vector3(0, 0.08, 0), hw * 1.02, hw * 0.98, Color(0.24, 0.24, 0.27), 12, false, false)
			for i in 6:
				var a := TAU * i / 6.0 + 0.26
				k.box(Vector3(cos(a), 0, sin(a)) * hw * 0.55 + Vector3(0, 0.08, 0), Vector3(0.12, 0.03, hw * 0.85), Color(0.05, 0.05, 0.06), -a + PI * 0.5)
			for i in 12:
				var a := TAU * i / 12.0
				k.sphere(Vector3(cos(a) * hw * 0.93, 0.09, sin(a) * hw * 0.93), Vector3.ONE * 0.06, Color(0.45, 0.45, 0.48), 4, 2)
		_:
			var edge: Color = {"dominaria": Color(0.5, 0.47, 0.42), "ravnica": Color(0.3, 0.28, 0.32), "avishkar": Game.GOLD.darkened(0.25)}[race]
			var tile: Color = {"dominaria": Color(0.56, 0.52, 0.45), "ravnica": Color(0.38, 0.36, 0.4), "avishkar": Color(0.88, 0.82, 0.7)}[race]
			k.taper(Vector3(0, -0.1, 0), Vector2(hw, hw) * 2.0 + Vector2(0.2, 0.2), Vector2(hw, hw) * 2.0, 0.18, edge)
			var n := maxi(3, int(w / 1.1))
			var step := hw * 2.0 / n
			for y in n:
				for x in n:
					var c := Vector3(-hw + (x + 0.5) * step, 0.085, -hw + (y + 0.5) * step)
					k.box(c, Vector3(step * 0.88, 0.02, step * 0.88), tile.darkened(rng.randf_range(0.0, 0.12)) if race != "avishkar" else (tile if (x + y) % 2 == 0 else Color(0.2, 0.55, 0.56)))


## A wall block standing on y = c.y: a plinth, the wall, a cornice and corner posts.
static func _block(k: MeshKit, c: Vector3, w: float, d: float, h: float, col: Color, trim: Color) -> void:
	k.box(c + Vector3(0, 0.2, 0), Vector3(w + 0.14, 0.4, d + 0.14), trim.darkened(0.1))
	k.box(c + Vector3(0, h * 0.5, 0), Vector3(w, h, d), col)
	k.box(c + Vector3(0, h - 0.07, 0), Vector3(w + 0.16, 0.14, d + 0.16), trim)
	for x in [-1.0, 1.0]:
		for z in [-1.0, 1.0]:
			k.box(c + Vector3(x * w * 0.5, h * 0.5, z * d * 0.5), Vector3(0.22, h, 0.22), trim)


## A square beam (four-sided) from a to b.
static func _beam(k: MeshKit, a: Vector3, b: Vector3, r: float, col: Color) -> void:
	k.cyl(a, b, r, r, col, 4, false, false, true)


## Half-timbering on the front and back faces of a wall (w wide, d deep, from y0 to y1).
static func _timber(k: MeshKit, c: Vector3, w: float, d: float, y0: float, y1: float, col: Color) -> void:
	for z in [-1.0, 1.0]:
		var f: float = c.z + z * (d * 0.5 + 0.03)
		var n := maxi(2, int(w / 1.3))
		for i in n + 1:
			var x := c.x - w * 0.5 + w * i / n
			_beam(k, Vector3(x, y0, f), Vector3(x, y1, f), 0.06, col)
		_beam(k, Vector3(c.x - w * 0.5, (y0 + y1) * 0.5, f), Vector3(c.x + w * 0.5, (y0 + y1) * 0.5, f), 0.05, col)
		_beam(k, Vector3(c.x - w * 0.5, y1 - 0.05, f), Vector3(c.x + w * 0.5, y1 - 0.05, f), 0.06, col)
		for i in n:
			var x0 := c.x - w * 0.5 + w * i / n
			var x1 := c.x - w * 0.5 + w * (i + 1) / n
			if i % 2 == 0:
				_beam(k, Vector3(x0, y0, f), Vector3(x1, (y0 + y1) * 0.5, f), 0.04, col)
			else:
				_beam(k, Vector3(x1, y0, f), Vector3(x0, (y0 + y1) * 0.5, f), 0.04, col)


## A door in the face at z = c.z (facing +Z), its bottom centre at c: frame, planks, a step.
static func _door(k: MeshKit, c: Vector3, w: float, h: float, col: Color, frame: Color, arch := false) -> void:
	k.box(c + Vector3(0, h * 0.5 + 0.04, 0.0), Vector3(w + 0.22, h + 0.1, 0.08), frame)
	k.box(c + Vector3(0, h * 0.5, 0.04), Vector3(w, h, 0.05), col)
	for i in 3:
		k.box(c + Vector3(-w * 0.33 + i * w * 0.33, h * 0.5, 0.07), Vector3(0.03, h * 0.94, 0.02), col.darkened(0.3))
	k.box(c + Vector3(0, h * 0.65, 0.075), Vector3(w * 0.9, 0.05, 0.02), DARK)
	if arch:
		k.ring(c + Vector3(0, h, 0.03), Vector3(0, 0, 1), w * 0.5 + 0.05, 0.07, frame, 10, 3, false, PI)
		k.cyl(c + Vector3(0, h, 0.02), c + Vector3(0, h, 0.07), w * 0.5, w * 0.5, col.darkened(0.15), 10, false, false, true)
	k.box(c + Vector3(0, 0.05, 0.2), Vector3(w + 0.4, 0.1, 0.35), frame.darkened(0.1))


## A window in a face (facing +Z at `c`, or -Z with `back`): frame, glowing pane, cross bars,
## sill; `peak` adds a pointed top (Ravnica).
static func _window(k: MeshKit, c: Vector3, w: float, h: float, col: Color, frame: Color, glow := true, back := false, peak := false) -> void:
	var s := -1.0 if back else 1.0
	k.box(c + Vector3(0, 0, 0.0), Vector3(w + 0.12, h + 0.12, 0.06), frame)
	k.box(c + Vector3(0, 0, 0.02 * s), Vector3(w, h, 0.06), col, glow)
	k.box(c + Vector3(0, 0, 0.05 * s), Vector3(0.035, h, 0.03), frame.darkened(0.2))
	k.box(c + Vector3(0, h * 0.1, 0.05 * s), Vector3(w, 0.035, 0.03), frame.darkened(0.2))
	k.box(c + Vector3(0, -h * 0.5 - 0.06, 0.06 * s), Vector3(w + 0.22, 0.06, 0.14), frame.lightened(0.1))
	if peak:
		k.taper(c + Vector3(0, h * 0.5, 0.0), Vector2(w + 0.12, 0.06), Vector2(0.02, 0.06), w * 0.7, frame)
		k.taper(c + Vector3(0, h * 0.5, 0.02 * s), Vector2(w, 0.06), Vector2(0.01, 0.06), w * 0.55, col, glow)


static func _windows(k: MeshKit, c: Vector3, w: float, d: float, y: float, n: int, col: Color, glow := true, tall := 0.4, frame := DARK, peak := false) -> void:
	for i in n:
		var x := -w * 0.5 + w * (i + 0.5) / n
		_window(k, c + Vector3(x, y, d * 0.5 + 0.02), 0.24, tall, col, frame, glow, false, peak)
		_window(k, c + Vector3(x, y, -d * 0.5 - 0.02), 0.24, tall, col, frame, glow, true, peak)


## A banner on a pole; the cloth (swallow-tailed, team coloured) flutters.
static func _banner(k: MeshKit, at: Vector3, h: float, pole := WOOD) -> void:
	k.cyl(at, at + Vector3(0, h, 0), 0.05, 0.04, pole, 6)
	k.sphere(at + Vector3(0, h + 0.05, 0), Vector3(0.07, 0.07, 0.07), Game.GOLD, 6, 3)
	k.box(at + Vector3(0.3, h - 0.06, 0), Vector3(0.62, 0.04, 0.04), pole)
	k.rig(P_FLAG, at)
	var top := at + Vector3(0.04, h - 0.1, 0)
	var pts := [top, top + Vector3(0.58, 0, 0), top + Vector3(0.58, -0.8, 0), top + Vector3(0.36, -0.6, 0), top + Vector3(0.0, -0.85, 0)]
	for i in [[0, 1, 3], [1, 2, 3], [0, 3, 4]]:
		k.tri(pts[i[0]], pts[i[1]], pts[i[2]], T)
		k.tri(pts[i[0]], pts[i[2]], pts[i[1]], T)
	k.box(top + Vector3(0.29, -0.3, 0), Vector3(0.18, 0.18, 0.012), Game.GOLD, false, PI * 0.25)
	k.rig()


## A pitched roof along X over a w x d wall, ridge h above `c`: tile courses, a ridge beam,
## fascia boards and gable ends in `wall` colour.
static func _gable(k: MeshKit, c: Vector3, w: float, d: float, h: float, col: Color, wall := Color(-1, 0, 0)) -> void:
	var hw := w * 0.5 + 0.22
	var hd := d * 0.5 + 0.28
	var drop := 0.14
	var rows := maxi(3, int(hd / 0.32))
	for i in rows:
		var t0 := float(i) / rows
		var t1 := float(i + 1) / rows
		var y0 := c.y - drop + (h + drop) * t0
		var y1 := c.y - drop + (h + drop) * t1
		var shade := 0.07 * (i % 2)
		var cf := col.darkened(shade)
		var cb := col.darkened(0.12 + shade)
		k.quad(Vector3(c.x - hw, y0, c.z + hd * (1.0 - t0)), Vector3(c.x + hw, y0, c.z + hd * (1.0 - t0)), Vector3(c.x + hw, y1, c.z + hd * (1.0 - t1)), Vector3(c.x - hw, y1, c.z + hd * (1.0 - t1)), cf)
		k.quad(Vector3(c.x + hw, y0, c.z - hd * (1.0 - t0)), Vector3(c.x - hw, y0, c.z - hd * (1.0 - t0)), Vector3(c.x - hw, y1, c.z - hd * (1.0 - t1)), Vector3(c.x + hw, y1, c.z - hd * (1.0 - t1)), cb)
	# the roof's thickness along the eaves and the verges
	for z in [-1.0, 1.0]:
		k.box(Vector3(c.x, c.y - drop - 0.04, c.z + z * hd), Vector3(hw * 2.0, 0.1, 0.07), col.darkened(0.35))
	var ridge := Vector3(c.x, c.y + h, c.z)
	for x in [-1.0, 1.0]:
		_beam(k, Vector3(c.x + x * hw, c.y - drop, c.z - hd), ridge + Vector3(x * hw, 0, 0), 0.05, col.darkened(0.35))
		_beam(k, Vector3(c.x + x * hw, c.y - drop, c.z + hd), ridge + Vector3(x * hw, 0, 0), 0.05, col.darkened(0.35))
	k.box(ridge + Vector3(0, 0.03, 0), Vector3(hw * 2.0 + 0.08, 0.1, 0.14), col.darkened(0.3))
	var gc := col.darkened(0.25) if wall.r < 0.0 else wall
	var gh := h * (d * 0.5) / hd + drop * 0.0
	k.tri(Vector3(c.x - w * 0.5, c.y, c.z - d * 0.5), Vector3(c.x - w * 0.5, c.y, c.z + d * 0.5), Vector3(c.x - w * 0.5, c.y + gh, c.z), gc)
	k.tri(Vector3(c.x + w * 0.5, c.y, c.z + d * 0.5), Vector3(c.x + w * 0.5, c.y, c.z - d * 0.5), Vector3(c.x + w * 0.5, c.y + gh, c.z), gc)


static func _crenels(k: MeshKit, c: Vector3, w: float, d: float, col: Color) -> void:
	k.box(c + Vector3(0, -0.05, 0), Vector3(w + 0.2, 0.12, d + 0.2), col.darkened(0.12))
	var n := int(w / 0.7)
	for i in n:
		var x := -w * 0.5 + w * (i + 0.5) / n
		k.box(c + Vector3(x, 0.22, d * 0.5), Vector3(0.36, 0.44, 0.26), col)
		k.box(c + Vector3(x, 0.22, -d * 0.5), Vector3(0.36, 0.44, 0.26), col)
	n = int(d / 0.7)
	for i in n:
		var z := -d * 0.5 + d * (i + 0.5) / n
		k.box(c + Vector3(w * 0.5, 0.22, z), Vector3(0.26, 0.44, 0.36), col)
		k.box(c + Vector3(-w * 0.5, 0.22, z), Vector3(0.26, 0.44, 0.36), col)


## A finial: a gold ball and a spike on top of a roof.
static func _finial(k: MeshKit, top: Vector3, col := Game.GOLD, h := 0.5) -> void:
	k.sphere(top + Vector3(0, 0.08, 0), Vector3.ONE * 0.1, col, 6, 3)
	k.cyl(top + Vector3(0, 0.12, 0), top + Vector3(0, h, 0), 0.035, 0.0, col, 5)


static func _round_tower(k: MeshKit, c: Vector3, r: float, h: float, wall: Color, roof: Color, roof_h: float) -> void:
	k.cyl(c, c + Vector3(0, 0.4, 0), r * 1.12, r * 1.05, wall.darkened(0.12), 14)
	k.cyl(c, c + Vector3(0, h, 0), r, r * 0.92, wall, 14)
	k.ring(c + Vector3(0, h * 0.5, 0), Vector3.UP, r * 0.97, 0.05, wall.darkened(0.15), 14, 3)
	k.cyl(c + Vector3(0, h - 0.25, 0), c + Vector3(0, h, 0), r * 1.0, r * 1.08, wall.darkened(0.08), 14)
	for i in 3:
		var a := TAU * i / 3.0 + 0.5
		k.box(c + Vector3(cos(a) * r * 0.95, h * 0.62, sin(a) * r * 0.95), Vector3(0.1, 0.4, 0.1), DARK, false, -a)
	if roof_h > 0.0:
		k.cyl(c + Vector3(0, h, 0), c + Vector3(0, h + roof_h, 0), r * 1.2, 0.0, roof, 14)
		k.ring(c + Vector3(0, h + 0.02, 0), Vector3.UP, r * 1.18, 0.05, roof.darkened(0.3), 14, 3)
		_finial(k, c + Vector3(0, h + roof_h - 0.05, 0))


static func _dome(k: MeshKit, c: Vector3, r: float, col: Color, onion := false) -> void:
	k.ring(c + Vector3(0, 0.03, 0), Vector3.UP, r * 0.98, 0.06, col.darkened(0.3), 14, 3)
	if onion:
		k.sphere(c + Vector3(0, r * 0.7, 0), Vector3(r, r * 0.95, r), col, 14, 8)
		k.cyl(c + Vector3(0, r * 1.5, 0), c + Vector3(0, r * 2.3, 0), r * 0.3, 0.0, col, 10)
		for i in 8:
			var a := TAU * i / 8.0
			k.cyl(c + Vector3(cos(a) * r * 0.99, r * 0.7, sin(a) * r * 0.99), c + Vector3(cos(a) * r * 0.3, r * 1.52, sin(a) * r * 0.3), 0.02, 0.012, col.darkened(0.25), 3, false, false, false)
		_finial(k, c + Vector3(0, r * 2.25, 0), col.lightened(0.2), 0.35)
	else:
		k.sphere(c, Vector3(r, r * 0.8, r), col, 14, 7)
		_finial(k, c + Vector3(0, r * 0.78, 0), Game.GOLD, 0.4)


## A gear facing +Z (it turns, rigged as P_GEAR).
static func _gear(k: MeshKit, c: Vector3, r: float, col: Color, teeth := 10) -> void:
	k.rig(P_GEAR, c)
	k.cyl(c - Vector3(0, 0, 0.06), c + Vector3(0, 0, 0.06), r * 0.86, r * 0.86, col, teeth * 2)
	for i in teeth:
		var a := TAU * i / teeth
		k.box(c + Vector3(cos(a), sin(a), 0) * r * 0.92, Vector3(r * 0.2, r * 0.2, 0.1), col.darkened(0.1))
	k.cyl(c + Vector3(0, 0, 0.06), c + Vector3(0, 0, 0.1), r * 0.3, r * 0.3, col.darkened(0.3), 10)
	for i in 4:
		var a := TAU * i / 4.0 + 0.4
		k.box(c + Vector3(cos(a), sin(a), 0) * r * 0.58 + Vector3(0, 0, 0.07), Vector3(r * 0.22, r * 0.22, 0.03), col.darkened(0.45))
	k.rig()


## A chimney with a cap; `hot` makes the top glow (forges).
static func _chimney(k: MeshKit, c: Vector3, h: float, col: Color, hot := false) -> void:
	k.box(c + Vector3(0, h * 0.5, 0), Vector3(0.6, h, 0.6), col)
	k.box(c + Vector3(0, h + 0.06, 0), Vector3(0.78, 0.14, 0.78), col.darkened(0.2))
	if hot:
		k.box(c + Vector3(0, h + 0.14, 0), Vector3(0.44, 0.06, 0.44), Color(1.0, 0.5, 0.15), true)
	else:
		k.box(c + Vector3(0, h + 0.14, 0), Vector3(0.44, 0.06, 0.44), DARK)


static func _dom_building(k: MeshKit, role: String, w: float) -> void:
	var stone := Color(0.72, 0.7, 0.66)
	var trim := Color(0.6, 0.57, 0.52)
	var plaster := Color(0.9, 0.86, 0.76)
	var roof := Color(0.3, 0.36, 0.52)
	var thatch := Color(0.72, 0.6, 0.32)
	var win := Color(1.0, 0.85, 0.5)
	match role:
		"hall":
			_block(k, Vector3(0, 0, 0), w, w, 2.4, stone, trim)
			_crenels(k, Vector3(0, 2.4, 0), w, w, stone)
			_block(k, Vector3(0, 2.4, 0), w * 0.5, w * 0.5, 2.9, stone.lightened(0.05), trim)
			_crenels(k, Vector3(0, 5.3, 0), w * 0.5, w * 0.5, stone)
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					_round_tower(k, Vector3(x * w * 0.45, 0, z * w * 0.45), 0.75, 3.4, stone, roof, 1.6)
			_door(k, Vector3(0, 0, w * 0.5 + 0.02), 1.2, 1.6, WOOD.darkened(0.2), trim, true)
			_windows(k, Vector3(0, 0, 0), w * 0.5, w * 0.5, 4.2, 2, win, true, 0.5)
			_windows(k, Vector3(0, 0, 0), w * 0.6, w, 1.4, 2, win, true, 0.45)
			_banner(k, Vector3(0, 5.3, 0), 2.0)
			k.box(Vector3(0, 3.6, w * 0.25 + 0.04), Vector3(0.9, 1.1, 0.05), T)
			k.box(Vector3(0, 3.6, w * 0.25 + 0.07), Vector3(0.12, 0.8, 0.03), Game.GOLD)
			k.box(Vector3(0, 3.75, w * 0.25 + 0.07), Vector3(0.5, 0.1, 0.03), Game.GOLD)
		"house":
			k.box(Vector3(0, 0.25, 0), Vector3(w, 0.5, w * 0.85), stone)
			k.box(Vector3(0, 1.1, 0), Vector3(w * 0.95, 1.2, w * 0.8), plaster)
			_timber(k, Vector3(0, 0, 0), w * 0.95, w * 0.8, 0.5, 1.7, WOOD.darkened(0.2))
			_gable(k, Vector3(0, 1.7, 0), w * 0.95, w * 0.8, 1.2, thatch, plaster)
			_door(k, Vector3(w * 0.12, 0.5, w * 0.4 + 0.02), 0.5, 0.95, WOOD.darkened(0.25), WOOD.darkened(0.4))
			_chimney(k, Vector3(w * 0.25, 1.6, -0.25), 1.6, stone)
			_window(k, Vector3(-w * 0.25, 1.2, w * 0.4 + 0.05), 0.32, 0.34, win, WOOD.darkened(0.4))
			k.box(Vector3(-w * 0.25, 1.65, w * 0.4 + 0.06), Vector3(0.4, 0.12, 0.05), T)
			k.box(Vector3(-w * 0.32, 0.25, w * 0.47), Vector3(0.5, 0.22, 0.24), WOOD)
		"depot":
			k.box(Vector3(0, 0.9, 0), Vector3(w * 0.9, 1.8, w * 0.7), Color(0.55, 0.42, 0.28))
			_timber(k, Vector3(0, 0, 0), w * 0.9, w * 0.7, 0.0, 1.8, WOOD.darkened(0.35))
			_gable(k, Vector3(0, 1.8, 0), w * 0.9, w * 0.7, 0.9, roof, Color(0.55, 0.42, 0.28))
			_door(k, Vector3(0, 0, w * 0.35 + 0.02), 1.0, 1.3, WOOD.darkened(0.2), WOOD.darkened(0.4))
			for i in 3:
				k.box(Vector3(-w * 0.32 + i * 0.55, 0.25, w * 0.5), Vector3(0.45, 0.45, 0.45), WOOD.lightened(0.05 * i))
				k.box(Vector3(-w * 0.32 + i * 0.55, 0.25, w * 0.5), Vector3(0.47, 0.06, 0.47), WOOD.darkened(0.35))
			k.cyl(Vector3(w * 0.36, 0, w * 0.5), Vector3(w * 0.36, 0.5, w * 0.5), 0.2, 0.22, WOOD, 8)
			k.sphere(Vector3(w * 0.36, 0.5, w * 0.5), Vector3(0.22, 0.12, 0.22), Color(0.95, 0.8, 0.3), 7, 3)
			_banner(k, Vector3(-w * 0.45, 0, -w * 0.35), 2.6)
		"barracks":
			k.box(Vector3(0, 0.4, 0), Vector3(w, 0.8, w * 0.75), stone)
			k.box(Vector3(0, 1.5, 0), Vector3(w * 0.96, 1.4, w * 0.7), plaster)
			_timber(k, Vector3(0, 0, 0), w * 0.96, w * 0.7, 0.8, 2.2, WOOD.darkened(0.25))
			_gable(k, Vector3(0, 2.2, 0), w * 0.96, w * 0.7, 1.6, roof, plaster)
			_door(k, Vector3(0, 0.0, w * 0.375 + 0.02), 1.1, 1.6, WOOD.darkened(0.25), trim, true)
			_banner(k, Vector3(w * 0.4, 0, w * 0.45), 3.4)
			_banner(k, Vector3(-w * 0.4, 0, w * 0.45), 3.4)
			# a weapon rack and a straw target
			for i in 3:
				k.cyl(Vector3(-w * 0.45, 0, -w * 0.45 + i * 0.3), Vector3(-w * 0.45, 1.6, -w * 0.4 + i * 0.3), 0.03, 0.03, WOOD, 4)
			k.box(Vector3(-w * 0.45, 1.0, -w * 0.15), Vector3(0.08, 0.08, 0.9), WOOD.darkened(0.2))
			k.cyl(Vector3(w * 0.42, 0, -w * 0.42), Vector3(w * 0.42, 1.0, -w * 0.42), 0.05, 0.05, WOOD, 4)
			k.cyl(Vector3(w * 0.42, 1.2, -w * 0.47), Vector3(w * 0.42, 1.2, -w * 0.37), 0.35, 0.35, thatch, 10)
			k.cyl(Vector3(w * 0.42, 1.2, -w * 0.37), Vector3(w * 0.42, 1.2, -w * 0.36), 0.15, 0.15, Color(0.75, 0.15, 0.1), 10)
		"forge":
			_block(k, Vector3(0, 0, 0), w * 0.9, w * 0.75, 2.2, stone.darkened(0.1), trim.darkened(0.1))
			_gable(k, Vector3(0, 2.2, 0), w * 0.9, w * 0.75, 1.0, Color(0.5, 0.3, 0.22), stone.darkened(0.1))
			_chimney(k, Vector3(w * 0.3, 1.8, -w * 0.15), 2.6, stone.darkened(0.2), true)
			k.box(Vector3(0, 0.9, w * 0.375 + 0.02), Vector3(1.6, 1.4, 0.08), trim.darkened(0.2))
			k.box(Vector3(0, 0.85, w * 0.375 + 0.05), Vector3(1.4, 1.2, 0.05), Color(1.0, 0.45, 0.1), true)
			# anvil, quench barrel, a rack of blades
			k.box(Vector3(-w * 0.3, 0.35, w * 0.5), Vector3(0.6, 0.3, 0.3), DARK)
			k.box(Vector3(-w * 0.3, 0.12, w * 0.5), Vector3(0.3, 0.25, 0.2), DARK)
			k.cyl(Vector3(w * 0.25, 0, w * 0.52), Vector3(w * 0.25, 0.6, w * 0.52), 0.28, 0.3, WOOD, 8)
			k.cyl(Vector3(w * 0.25, 0.55, w * 0.52), Vector3(w * 0.25, 0.58, w * 0.52), 0.25, 0.25, Color(0.3, 0.4, 0.5), 8)
			for i in 3:
				k.box(Vector3(w * 0.47, 1.0, -0.4 + i * 0.4), Vector3(0.04, 1.0, 0.1), STEEL)
			_banner(k, Vector3(-w * 0.45, 0, -w * 0.4), 3.0)
		"tower":
			_round_tower(k, Vector3(0, 0, 0), w * 0.38, 5.5, stone, roof, 2.2)
			k.ring(Vector3(0, 5.3, 0), Vector3.UP, w * 0.42, 0.18, stone.darkened(0.1), 14, 4)
			for i in 8:
				var a := TAU * i / 8.0
				k.box(Vector3(cos(a) * w * 0.42, 5.55, sin(a) * w * 0.42), Vector3(0.3, 0.35, 0.3), stone, false, -a)
			_door(k, Vector3(0, 0, w * 0.38), 0.6, 1.1, WOOD.darkened(0.25), trim, true)
			_banner(k, Vector3(0, 7.6, 0), 1.2)
		"stable":
			k.box(Vector3(0, 1.1, -w * 0.12), Vector3(w * 0.9, 2.2, w * 0.55), WOOD)
			for i in 9:
				k.box(Vector3(-w * 0.45 + i * w * 0.1125, 1.1, w * 0.155), Vector3(0.04, 2.2, 0.03), WOOD.darkened(0.25))
			_gable(k, Vector3(0, 2.2, -w * 0.12), w * 0.9, w * 0.55, 1.3, thatch, WOOD)
			for i in 3:
				var x := -w * 0.3 + i * w * 0.3
				k.box(Vector3(x, 0.8, w * 0.16 + 0.01), Vector3(0.8, 1.4, 0.05), DARK)
				k.box(Vector3(x, 0.55, w * 0.16 + 0.04), Vector3(0.8, 0.9, 0.04), WOOD.lightened(0.08))
				_beam(k, Vector3(x - 0.38, 0.12, w * 0.16 + 0.07), Vector3(x + 0.38, 0.98, w * 0.16 + 0.07), 0.03, WOOD.darkened(0.3))
			for i in 6:
				var x := -w * 0.45 + i * w * 0.18
				k.box(Vector3(x, 0.5, w * 0.45), Vector3(0.1, 1.0, 0.1), WOOD.darkened(0.2))
			k.box(Vector3(0, 0.8, w * 0.45), Vector3(w * 0.9, 0.08, 0.06), WOOD)
			k.box(Vector3(0, 0.45, w * 0.45), Vector3(w * 0.9, 0.08, 0.06), WOOD)
			k.box(Vector3(w * 0.3, 0.35, w * 0.3), Vector3(0.9, 0.5, 0.6), thatch)
			k.box(Vector3(-w * 0.3, 0.25, w * 0.32), Vector3(0.8, 0.25, 0.3), WOOD.darkened(0.2))
			_banner(k, Vector3(w * 0.45, 0, -w * 0.4), 3.2)
		"sanctum":
			# Tolarian academy: a round tower with a blue dome and a glowing lens
			_block(k, Vector3(0, 0, 0), w * 0.9, w * 0.9, 1.8, stone, trim)
			_round_tower(k, Vector3(0, 1.8, 0), w * 0.3, 3.5, plaster, roof, 0.0)
			_dome(k, Vector3(0, 5.3, 0), w * 0.32, Color(0.3, 0.45, 0.8))
			k.sphere(Vector3(0, 6.3, 0), Vector3(0.35, 0.35, 0.35), Color(0.5, 0.8, 1.0), 10, 6, true)
			k.rig(P_SPIN, Vector3(0, 6.3, 0))
			k.ring(Vector3(0, 6.3, 0), Vector3(0.3, 1, 0.2), 0.7, 0.04, Game.GOLD, 16, 3)
			k.ring(Vector3(0, 6.3, 0), Vector3(-0.4, 1, 0.1), 0.85, 0.03, Game.GOLD, 16, 3)
			k.rig()
			_windows(k, Vector3(0, 0, 0), w * 0.9, w * 0.9, 1.0, 3, Color(0.6, 0.85, 1.0))
			_door(k, Vector3(0, 1.8, w * 0.3), 0.6, 1.0, Color(0.3, 0.4, 0.7), trim, true)
			_banner(k, Vector3(w * 0.42, 1.8, w * 0.42), 2.0)
		"workshop":
			_block(k, Vector3(0, 0, 0), w, w * 0.8, 2.4, WOOD, WOOD.darkened(0.3))
			_gable(k, Vector3(0, 2.4, 0), w, w * 0.8, 1.2, roof, WOOD)
			_door(k, Vector3(0, 0, w * 0.4 + 0.02), 1.6, 1.8, WOOD.darkened(0.2), WOOD.darkened(0.45))


static func _rav_building(k: MeshKit, role: String, w: float) -> void:
	var stone := Color(0.42, 0.38, 0.42)
	var stone2 := Color(0.55, 0.5, 0.52)
	var roof := Color(0.22, 0.18, 0.28)
	var bronze := Color(0.75, 0.55, 0.3)
	var win := Color(1.0, 0.78, 0.45)
	match role:
		"hall":
			# guildhall: a cathedral block with a tall central spire and flying buttresses
			_block(k, Vector3(0, 0, 0), w * 0.8, w * 0.9, 4.0, stone, stone2)
			_gable(k, Vector3(0, 4.0, 0), w * 0.8, w * 0.9, 2.0, roof, stone)
			_block(k, Vector3(0, 0, w * 0.2), 1.6, 1.6, 8.0, stone2, stone)
			k.cyl(Vector3(0, 8.0, w * 0.2), Vector3(0, 11.5, w * 0.2), 1.25, 0.0, roof, 8)
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					k.cyl(Vector3(x * 0.8, 8.0, w * 0.2 + z * 0.8), Vector3(x * 0.8, 9.2, w * 0.2 + z * 0.8), 0.18, 0.0, roof, 6)
			_finial(k, Vector3(0, 11.4, w * 0.2), bronze, 0.6)
			for x in [-1.0, 1.0]:
				for z in [-0.3, 0.1, 0.4]:
					k.box(Vector3(x * w * 0.47, 1.6, z * w), Vector3(0.4, 3.2, 0.5), stone2)
					k.cyl(Vector3(x * w * 0.47, 3.2, z * w), Vector3(x * w * 0.47, 4.4, z * w), 0.3, 0.0, roof, 6)
					_beam(k, Vector3(x * w * 0.47, 3.0, z * w), Vector3(x * w * 0.4, 3.9, z * w), 0.1, stone2)
			_windows(k, Vector3(0, 0, 0), w * 0.8, w * 0.9, 2.4, 3, win, true, 1.2, stone2.darkened(0.3), true)
			k.ring(Vector3(0, 6.0, w * 0.2 + 0.82), Vector3(0, 0, 1), 0.45, 0.06, stone2.darkened(0.2), 14, 3)
			k.cyl(Vector3(0, 6.0, w * 0.2 + 0.8), Vector3(0, 6.0, w * 0.2 + 0.84), 0.42, 0.42, win, 12, true)
			k.box(Vector3(0, 6.0, w * 0.2 + 0.86), Vector3(0.04, 0.84, 0.02), stone2.darkened(0.3))
			k.box(Vector3(0, 6.0, w * 0.2 + 0.86), Vector3(0.84, 0.04, 0.02), stone2.darkened(0.3))
			_door(k, Vector3(0, 0, w * 0.45 + 0.02), 1.0, 2.0, DARK.lightened(0.1), stone2, true)
			_banner(k, Vector3(w * 0.42, 0, w * 0.5), 3.6, DARK)
			_banner(k, Vector3(-w * 0.42, 0, w * 0.5), 3.6, DARK)
		"house":
			_block(k, Vector3(0, 0, 0), w * 0.7, w * 0.7, 3.6, stone2, stone)
			_gable(k, Vector3(0, 3.6, 0), w * 0.7, w * 0.7, 1.3, roof, stone2)
			_windows(k, Vector3(0, 0, 0), w * 0.7, w * 0.7, 1.5, 2, win, true, 0.45, stone, true)
			_windows(k, Vector3(0, 0, 0), w * 0.7, w * 0.7, 2.7, 2, win, true, 0.45, stone, true)
			k.box(Vector3(0, 3.1, w * 0.35 + 0.08), Vector3(w * 0.5, 0.25, 0.08), T)
			_chimney(k, Vector3(-w * 0.2, 3.6, -w * 0.15), 1.3, stone)
		"depot":
			_block(k, Vector3(0, 0, 0), w * 0.85, w * 0.85, 2.0, stone2, stone)
			_dome(k, Vector3(0, 2.0, 0), w * 0.36, bronze)
			_door(k, Vector3(0, 0, w * 0.425 + 0.02), 0.7, 1.2, DARK, stone, true)
			k.box(Vector3(0, 1.75, w * 0.425 + 0.1), Vector3(w * 0.6, 0.2, 0.05), T)
			for i in 2:
				k.cyl(Vector3(-w * 0.3 + i * 0.5, 0, w * 0.55), Vector3(-w * 0.3 + i * 0.5, 0.5, w * 0.55), 0.2, 0.2, bronze.darkened(0.3), 8)
		"barracks":
			_block(k, Vector3(0, 0, 0), w, w * 0.8, 2.8, stone, stone2)
			_crenels(k, Vector3(0, 2.8, 0), w, w * 0.8, stone)
			for x in [-1.0, 1.0]:
				_block(k, Vector3(x * w * 0.4, 0, w * 0.4), 0.9, 0.9, 4.4, stone2, stone)
				k.cyl(Vector3(x * w * 0.4, 4.4, w * 0.4), Vector3(x * w * 0.4, 6.2, w * 0.4), 0.7, 0.0, roof, 6)
				_finial(k, Vector3(x * w * 0.4, 6.1, w * 0.4), bronze, 0.3)
				_window(k, Vector3(x * w * 0.4, 3.4, w * 0.4 + 0.47), 0.2, 0.5, win, stone, true, false, true)
			_door(k, Vector3(0, 0, w * 0.4 + 0.02), 1.3, 2.0, DARK, stone2, true)
			k.box(Vector3(0, 2.45, w * 0.4 + 0.12), Vector3(1.6, 0.4, 0.06), T)
			_banner(k, Vector3(0, 2.8, 0), 2.4, DARK)
		"forge":
			_block(k, Vector3(0, 0, 0), w * 0.9, w * 0.8, 2.6, stone, stone2)
			_gable(k, Vector3(0, 2.6, 0), w * 0.9, w * 0.8, 1.2, roof, stone)
			for x in [-0.25, 0.25]:
				k.cyl(Vector3(x * w, 2.5, -w * 0.2), Vector3(x * w, 5.0, -w * 0.2), 0.3, 0.25, DARK, 10)
				k.ring(Vector3(x * w, 4.0, -w * 0.2), Vector3.UP, 0.28, 0.04, bronze, 10, 3)
				k.cyl(Vector3(x * w, 5.0, -w * 0.2), Vector3(x * w, 5.1, -w * 0.2), 0.27, 0.27, Color(1.0, 0.5, 0.15), 10, true)
			k.box(Vector3(0, 0.9, w * 0.4 + 0.04), Vector3(1.8, 1.6, 0.06), stone2)
			k.box(Vector3(0, 0.9, w * 0.4 + 0.06), Vector3(1.6, 1.4, 0.05), Color(1.0, 0.45, 0.1), true)
			k.box(Vector3(0, 1.95, w * 0.4 + 0.1), Vector3(1.8, 0.25, 0.05), T)
		"tower":
			_block(k, Vector3(0, 0, 0), w * 0.7, w * 0.7, 6.0, stone2, stone)
			k.box(Vector3(0, 6.3, 0), Vector3(w * 0.8, 0.6, w * 0.8), stone)
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					k.box(Vector3(x * w * 0.4, 6.0, z * w * 0.4), Vector3(0.2, 0.5, 0.2), stone.darkened(0.2))
			k.cyl(Vector3(0, 6.6, 0), Vector3(0, 9.0, 0), w * 0.55, 0.0, roof, 4)
			_finial(k, Vector3(0, 8.9, 0), bronze, 0.5)
			k.sphere(Vector3(0, 5.6, w * 0.36), Vector3(0.3, 0.3, 0.06), bronze, 10, 4)
			k.box(Vector3(0, 5.6, w * 0.36 + 0.05), Vector3(0.04, 0.22, 0.02), DARK)
			k.box(Vector3(0.06, 5.62, w * 0.36 + 0.05), Vector3(0.14, 0.03, 0.02), DARK)
			k.box(Vector3(0, 4.6, w * 0.36 + 0.02), Vector3(0.6, 0.3, 0.06), T)
			_window(k, Vector3(0, 2.6, w * 0.35 + 0.03), 0.2, 0.6, win, stone, true, false, true)
			_door(k, Vector3(0, 0, w * 0.35 + 0.02), 0.6, 1.2, DARK, stone, true)
		"workshop":
			# spark foundry: a squat block with a crackling coil tower
			_block(k, Vector3(0, 0, 0), w, w * 0.85, 2.6, stone, stone2)
			_gable(k, Vector3(0, 2.6, 0), w, w * 0.85, 1.0, roof, stone)
			k.cyl(Vector3(w * 0.25, 2.6, -w * 0.15), Vector3(w * 0.25, 5.6, -w * 0.15), 0.5, 0.3, bronze, 12)
			for i in 5:
				k.ring(Vector3(w * 0.25, 3.0 + i * 0.5, -w * 0.15), Vector3.UP, 0.5 - i * 0.04, 0.05, Color(0.8, 0.5, 0.2), 12, 3)
			k.sphere(Vector3(w * 0.25, 6.0, -w * 0.15), Vector3(0.45, 0.45, 0.45), Color(0.55, 0.75, 1.0), 10, 6, true)
			k.rig(P_SPIN, Vector3(w * 0.25, 6.0, -w * 0.15))
			k.ring(Vector3(w * 0.25, 6.0, -w * 0.15), Vector3(0.3, 1, 0.1).normalized(), 0.7, 0.025, Color(0.55, 0.75, 1.0), 16, 3, true)
			k.rig()
			_door(k, Vector3(0, 0, w * 0.425 + 0.02), 1.4, 2.0, DARK, stone2, true)
			k.box(Vector3(-w * 0.3, 2.0, w * 0.425 + 0.1), Vector3(0.8, 0.3, 0.05), T)
		"sanctum":
			# guild spire: a very tall needle with glowing windows
			_block(k, Vector3(0, 0, 0), w * 0.9, w * 0.9, 2.0, stone, stone2)
			k.taper(Vector3(0, 2.0, 0), Vector2(w * 0.55, w * 0.55), Vector2(w * 0.3, w * 0.3), 6.5, stone2)
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					k.taper(Vector3(x * w * 0.26, 2.0, z * w * 0.26), Vector2(0.3, 0.3), Vector2(0.12, 0.12), 6.6, stone, false, 0.0, Vector3(-x * w * 0.12, 0, -z * w * 0.12))
			k.cyl(Vector3(0, 8.5, 0), Vector3(0, 12.0, 0), w * 0.24, 0.0, roof, 6)
			_finial(k, Vector3(0, 11.9, 0), bronze, 0.6)
			for i in 4:
				_window(k, Vector3(0, 3.0 + i * 1.4, w * 0.2 + 0.12 - i * 0.03), 0.3, 0.7, Color(0.6, 0.8, 1.0), stone, true, false, true)
			k.sphere(Vector3(0, 9.0, 0), Vector3(0.5, 0.5, 0.5), Color(0.6, 0.8, 1.0), 10, 6, true)
			_banner(k, Vector3(w * 0.42, 2.0, w * 0.42), 2.4, DARK)
			k.box(Vector3(0, 1.6, w * 0.45 + 0.1), Vector3(1.2, 0.3, 0.05), T)
			_door(k, Vector3(0, 0, w * 0.45 + 0.02), 0.9, 1.3, DARK, stone2, true)
		"stable":
			_block(k, Vector3(0, 0, 0), w, w * 0.8, 2.4, stone, stone2)
			_gable(k, Vector3(0, 2.4, 0), w, w * 0.8, 1.2, roof, stone)


static func _avi_building(k: MeshKit, role: String, w: float) -> void:
	var cream := Color(0.93, 0.88, 0.78)
	var brass := Color(0.85, 0.64, 0.32)
	var teal := Color(0.12, 0.6, 0.62)
	var glow := Color(0.35, 0.95, 1.0)
	match role:
		"hall":
			# consulate: a white palace with a great brass dome and four minarets
			_block(k, Vector3(0, 0, 0), w, w, 2.8, cream, brass)
			k.cyl(Vector3(0, 2.8, 0), Vector3(0, 4.0, 0), w * 0.32, w * 0.32, cream, 16)
			for i in 12:
				var a := TAU * i / 12.0
				k.box(Vector3(cos(a) * w * 0.32, 3.4, sin(a) * w * 0.32), Vector3(0.12, 0.7, 0.12), brass.darkened(0.15), false, -a)
			k.gloss = true
			_dome(k, Vector3(0, 4.0, 0), w * 0.33, brass, true)
			k.gloss = false
			for x in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					var c := Vector3(x * w * 0.44, 0, z * w * 0.44)
					k.cyl(c, c + Vector3(0, 5.0, 0), 0.38, 0.32, cream, 12)
					k.ring(c + Vector3(0, 2.0, 0), Vector3.UP, 0.37, 0.04, brass, 12, 3)
					k.cyl(c + Vector3(0, 4.0, 0), c + Vector3(0, 4.12, 0), 0.5, 0.5, brass, 12)
					_window(k, c + Vector3(0, 3.2, 0.36), 0.14, 0.35, glow, brass)
					_dome(k, c + Vector3(0, 5.0, 0), 0.36, brass, true)
			for i in 3:
				var x := -w * 0.3 + i * w * 0.3
				k.box(Vector3(x, 1.2, w * 0.5 + 0.02), Vector3(0.8, 1.8, 0.06), teal)
				k.ring(Vector3(x, 2.1, w * 0.5 + 0.05), Vector3(0, 0, 1), 0.4, 0.05, brass, 12, 3, false, PI)
				k.cyl(Vector3(x, 2.1, w * 0.5 + 0.02), Vector3(x, 2.1, w * 0.5 + 0.06), 0.4, 0.4, teal.darkened(0.2), 12, false, false, true)
			k.ring(Vector3(0, 4.3, 0), Vector3.UP, w * 0.34, 0.06, glow, 20, 3, true)
			k.box(Vector3(0, 2.55, w * 0.5 + 0.1), Vector3(w * 0.7, 0.25, 0.05), T)
			_gear(k, Vector3(0, 3.4, w * 0.32 + 0.05), 0.5, brass)
		"house":
			_block(k, Vector3(0, 0, 0), w * 0.8, w * 0.8, 1.8, cream, brass)
			k.gloss = true
			_dome(k, Vector3(0, 1.8, 0), w * 0.33, brass, true)
			k.gloss = false
			k.box(Vector3(0, 0.6, w * 0.4 + 0.02), Vector3(0.5, 1.0, 0.05), teal)
			k.ring(Vector3(0, 1.1, w * 0.4 + 0.04), Vector3(0, 0, 1), 0.25, 0.04, brass, 10, 3, false, PI)
			k.box(Vector3(0, 1.5, w * 0.4 + 0.1), Vector3(w * 0.6, 0.15, 0.04), T)
			for x in [-1.0, 1.0]:
				_window(k, Vector3(x * w * 0.25, 0.95, w * 0.4 + 0.03), 0.2, 0.32, glow, brass)
		"depot":
			k.box(Vector3(0, 0.5, 0), Vector3(w * 0.9, 1.0, w * 0.9), brass.darkened(0.3))
			k.box(Vector3(0, 1.02, 0), Vector3(w * 0.94, 0.08, w * 0.94), brass)
			for x in [-0.22, 0.22]:
				k.cyl(Vector3(x * w, 1.0, 0), Vector3(x * w, 2.6, 0), 0.42, 0.42, cream, 12)
				k.cyl(Vector3(x * w, 1.2, 0), Vector3(x * w, 2.4, 0), 0.44, 0.44, glow, 12, true, true, false)
				for i in 3:
					k.ring(Vector3(x * w, 1.25 + i * 0.55, 0), Vector3.UP, 0.45, 0.03, brass, 12, 3)
				k.sphere(Vector3(x * w, 2.6, 0), Vector3(0.42, 0.25, 0.42), brass, 12, 4)
			_beam(k, Vector3(-0.22 * w, 2.2, 0), Vector3(0.22 * w, 2.2, 0), 0.06, brass.darkened(0.2))
			k.box(Vector3(0, 0.75, w * 0.45 + 0.02), Vector3(w * 0.6, 0.2, 0.05), T)
		"barracks":
			_block(k, Vector3(0, 0, 0), w, w * 0.8, 2.4, cream, brass)
			for i in 4:
				var x := -w * 0.36 + i * w * 0.24
				k.ring(Vector3(x, 1.4, w * 0.4 + 0.04), Vector3(0, 0, 1), 0.45, 0.06, brass, 12, 3, false, PI)
				k.box(Vector3(x, 0.7, w * 0.4 + 0.02), Vector3(0.7, 1.4, 0.05), teal.darkened(0.3))
				k.cyl(Vector3(x, 1.4, w * 0.4 + 0.02), Vector3(x, 1.4, w * 0.4 + 0.05), 0.35, 0.35, teal.darkened(0.4), 10, false, false, true)
			k.gloss = true
			_dome(k, Vector3(0, 2.6, 0), w * 0.22, brass, true)
			k.gloss = false
			_banner(k, Vector3(w * 0.45, 2.4, w * 0.35), 2.2, brass)
			_banner(k, Vector3(-w * 0.45, 2.4, w * 0.35), 2.2, brass)
		"forge":
			# gearworks: big turning gears on the walls and an aether chimney
			_block(k, Vector3(0, 0, 0), w * 0.9, w * 0.8, 2.4, cream.darkened(0.08), brass)
			for x in [-0.25, 0.25]:
				_gear(k, Vector3(x * w, 1.4, w * 0.4 + 0.12), 0.65, brass, 12)
			_gear(k, Vector3(0, 2.0, w * 0.4 + 0.1), 0.35, brass.darkened(0.1), 8)
			k.cyl(Vector3(w * 0.25, 2.4, -w * 0.2), Vector3(w * 0.25, 4.6, -w * 0.2), 0.35, 0.28, brass, 12)
			for i in 3:
				k.ring(Vector3(w * 0.25, 2.8 + i * 0.6, -w * 0.2), Vector3.UP, 0.33 - i * 0.02, 0.04, brass.darkened(0.3), 12, 3)
			k.cyl(Vector3(w * 0.25, 4.6, -w * 0.2), Vector3(w * 0.25, 4.75, -w * 0.2), 0.3, 0.3, glow, 12, true)
			k.box(Vector3(-w * 0.25, 2.3, w * 0.4 + 0.1), Vector3(0.9, 0.25, 0.05), T)
		"tower":
			k.cyl(Vector3(0, 0, 0), Vector3(0, 0.5, 0), w * 0.38, w * 0.34, brass.darkened(0.2), 12)
			k.cyl(Vector3(0, 0, 0), Vector3(0, 5.0, 0), w * 0.32, w * 0.22, cream, 12)
			for i in 3:
				k.ring(Vector3(0, 1.4 + i * 1.4, 0), Vector3.UP, w * 0.31 - i * 0.07, 0.06, brass, 12, 3)
			k.cyl(Vector3(0, 5.0, 0), Vector3(0, 5.6, 0), w * 0.25, w * 0.3, brass, 12)
			k.sphere(Vector3(0, 6.3, 0), Vector3(0.55, 0.55, 0.55), glow, 10, 6, true)
			k.rig(P_SPIN, Vector3(0, 6.3, 0))
			k.ring(Vector3(0, 6.3, 0), Vector3(1, 1, 0).normalized(), 0.85, 0.05, brass, 16, 3)
			k.ring(Vector3(0, 6.3, 0), Vector3(-1, 1, 0).normalized(), 0.85, 0.05, brass, 16, 3)
			k.rig()
			k.box(Vector3(0, 2.2, w * 0.3), Vector3(0.5, 0.3, 0.05), T)
			_window(k, Vector3(0, 3.4, w * 0.27), 0.14, 0.4, glow, brass)
		"stable":
			# racing garage: a low curved hall with a striped start ramp
			k.box(Vector3(0, 1.0, -w * 0.1), Vector3(w * 0.95, 2.0, w * 0.6), cream)
			k.cyl(Vector3(-w * 0.47, 2.0, -w * 0.1), Vector3(w * 0.47, 2.0, -w * 0.1), w * 0.3, w * 0.3, brass, 14)
			for i in 5:
				k.ring(Vector3(-w * 0.4 + i * w * 0.2, 2.0, -w * 0.1), Vector3.RIGHT, w * 0.305, 0.04, brass.darkened(0.25), 14, 3, false, PI)
			for i in 3:
				var x := -w * 0.3 + i * w * 0.3
				k.box(Vector3(x, 0.8, w * 0.2 + 0.02), Vector3(0.9, 1.4, 0.05), DARK)
				for j in 4:
					k.box(Vector3(x, 0.3 + j * 0.3, w * 0.2 + 0.05), Vector3(0.88, 0.04, 0.03), brass.darkened(0.3))
			for i in 5:
				k.box(Vector3(-w * 0.4 + i * w * 0.2, 0.05, w * 0.4), Vector3(w * 0.18, 0.1, 0.6), T if i % 2 == 0 else cream)
			k.cyl(Vector3(w * 0.42, 0, w * 0.42), Vector3(w * 0.42, 3.0, w * 0.42), 0.06, 0.06, brass, 6)
			k.box(Vector3(w * 0.42, 2.8, w * 0.42), Vector3(0.6, 0.4, 0.04), glow, true)
		"workshop":
			_block(k, Vector3(0, 0, 0), w, w * 0.8, 2.6, cream.darkened(0.05), brass)
			k.cyl(Vector3(-w * 0.5, 2.6, 0), Vector3(w * 0.5, 2.6, 0), w * 0.25, w * 0.25, brass, 12)
			k.cyl(Vector3(-w * 0.2, 2.2, w * 0.2), Vector3(-w * 0.2, 3.5, w * 0.75), 0.25, 0.2, brass.darkened(0.2), 10)
			for x in [0.15, 0.35]:
				k.cyl(Vector3(x * w, 2.4, -w * 0.25), Vector3(x * w, 4.4, -w * 0.25), 0.3, 0.3, glow, 10, true)
				k.ring(Vector3(x * w, 2.6, -w * 0.25), Vector3.UP, 0.31, 0.04, brass, 10, 3)
				k.ring(Vector3(x * w, 4.3, -w * 0.25), Vector3.UP, 0.31, 0.04, brass, 10, 3)
			k.box(Vector3(0, 1.0, w * 0.4 + 0.02), Vector3(1.6, 2.0, 0.05), teal.darkened(0.3))
			k.box(Vector3(0, 2.25, w * 0.4 + 0.1), Vector3(1.8, 0.25, 0.05), T)
			_gear(k, Vector3(w * 0.32, 1.5, w * 0.4 + 0.1), 0.45, brass, 10)
		"sanctum":
			# inventors' fair: a striped pavilion around a glowing aether engine
			for i in 8:
				var a := TAU * i / 8.0
				var c := Vector3(cos(a), 0, sin(a)) * w * 0.42
				k.cyl(c, c + Vector3(0, 2.4, 0), 0.08, 0.08, brass, 6)
			k.cyl(Vector3(0, 2.4, 0), Vector3(0, 4.6, 0), w * 0.5, 0.15, cream, 16)
			for i in 8:
				var a := TAU * i / 8.0 + 0.2
				k.cyl(Vector3(0, 2.42, 0) + Vector3(cos(a), 0, sin(a)) * w * 0.3, Vector3(0, 4.4, 0), 0.22, 0.02, T if i % 2 == 0 else teal, 4)
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.6, 0), 0.9, 0.7, brass.darkened(0.2), 12)
			k.sphere(Vector3(0, 2.0, 0), Vector3(0.6, 0.6, 0.6), glow, 10, 6, true)
			k.rig(P_SPIN, Vector3(0, 2.0, 0))
			k.ring(Vector3(0, 2.0, 0), Vector3(0.4, 1, 0).normalized(), 1.0, 0.05, brass, 16, 3)
			k.rig()
			k.cyl(Vector3(0, 4.6, 0), Vector3(0, 5.6, 0), 0.04, 0.04, brass, 4)
			k.rig(P_FLAG, Vector3(0, 5.3, 0))
			k.box(Vector3(0.3, 5.3, 0), Vector3(0.5, 0.35, 0.03), T)
			k.rig()


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
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.0, 0), w * 0.5, w * 0.45, metal, 14)
			for i in 14:
				var a := TAU * i / 14.0
				k.box(Vector3(cos(a) * w * 0.48, 0.5, sin(a) * w * 0.48), Vector3(0.08, 0.9, 0.2), metal.darkened(0.3), false, -a)
			k.sphere(Vector3(0, 2.6, 0), Vector3(1.5, 1.8, 1.5), glow, 12, 7, true)
			k.gloss = true
			for i in 10:
				var a := TAU * i / 10.0
				var d := Vector3(cos(a), 0, sin(a))
				var pts := [d * w * 0.45 + Vector3(0, 1.0, 0), d * w * 0.48 + Vector3(0, 3.0, 0), d * w * 0.3 + Vector3(0, 5.2, 0), d * 0.3 + Vector3(0, 6.6, 0)]
				for j in 3:
					k.cyl(pts[j], pts[j + 1], 0.22 - j * 0.04, 0.18 - j * 0.04, porcelain, 7)
					k.sphere(pts[j + 1], Vector3.ONE * (0.2 - j * 0.04), porcelain.darkened(0.06), 6, 3)
			k.cyl(Vector3(0, 6.4, 0), Vector3(0, 9.0, 0), 0.4, 0.0, porcelain, 10)
			k.gloss = false
			k.ring(Vector3(0, 1.0, 0), Vector3.UP, w * 0.46, 0.15, sinew, 22, 4)
			k.ring(Vector3(0, 4.0, 0), Vector3.UP, w * 0.42, 0.12, T, 22, 4)
			for i in 4:
				var a := TAU * i / 4.0 + 0.4
				k.cyl(Vector3(cos(a) * w * 0.5, 0, sin(a) * w * 0.5), Vector3(cos(a) * w * 0.62, 3.0, sin(a) * w * 0.62), 0.2, 0.0, oil, 6)
				k.cyl(Vector3(cos(a) * w * 0.3, 1.0, sin(a) * w * 0.3), Vector3(cos(a) * w * 0.1, 2.2, sin(a) * w * 0.1), 0.1, 0.08, sinew.darkened(0.2), 6)
		"house":
			# incubation vat: a glass tank of glowing oil on a porcelain stand
			k.cyl(Vector3(0, 0, 0), Vector3(0, 0.5, 0), w * 0.42, w * 0.4, metal, 12)
			k.cyl(Vector3(0, 0.5, 0), Vector3(0, 2.6, 0), w * 0.32, w * 0.32, glow.darkened(0.3), 12, true)
			k.sphere(Vector3(0.1, 1.5, 0.05), Vector3(0.35, 0.5, 0.3), oil, 7, 5)
			k.gloss = true
			for i in 4:
				var a := TAU * i / 4.0 + 0.78
				k.cyl(Vector3(cos(a), 0, sin(a)) * w * 0.38 + Vector3(0, 0.4, 0), Vector3(cos(a), 0, sin(a)) * w * 0.3 + Vector3(0, 3.2, 0), 0.12, 0.08, porcelain, 7)
			k.cyl(Vector3(0, 2.6, 0), Vector3(0, 3.0, 0), w * 0.36, w * 0.2, porcelain, 12)
			k.gloss = false
			k.ring(Vector3(0, 1.6, 0), Vector3.UP, w * 0.33, 0.07, T, 16, 3)
			k.cyl(Vector3(0, 3.0, 0), Vector3(0.3, 3.6, -0.2), 0.08, 0.06, sinew, 5)
		"depot":
			k.cyl(Vector3(0, 0, 0), Vector3(0, 0.4, 0), w * 0.48, w * 0.45, metal, 12)
			k.gloss = true
			k.cyl(Vector3(0, 0.4, 0), Vector3(0, 0.45, 0), w * 0.4, w * 0.4, oil, 14)
			for i in 6:
				var a := TAU * i / 6.0
				k.cyl(Vector3(cos(a), 0, sin(a)) * w * 0.44, Vector3(cos(a), 0, sin(a)) * w * 0.2 + Vector3(0, 2.2, 0), 0.12, 0.04, porcelain, 6)
			k.gloss = false
			k.ring(Vector3(0, 0.5, 0), Vector3.UP, w * 0.44, 0.08, T, 16, 3)
			k.sphere(Vector3(0, 0.5, 0), Vector3(0.4, 0.15, 0.4), glow.darkened(0.2), 8, 3, true)
		"barracks":
			# compleation pit: a sunken ring wall with spikes and hanging hooks
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.6, 0), w * 0.5, w * 0.46, metal, 16)
			for i in 8:
				var a := TAU * i / 8.0
				k.box(Vector3(cos(a) * w * 0.49, 0.8, sin(a) * w * 0.49), Vector3(0.1, 1.5, 0.3), metal.darkened(0.3), false, -a)
			k.cyl(Vector3(0, 1.6, 0), Vector3(0, 1.65, 0), w * 0.42, w * 0.42, glow.darkened(0.4), 16, true)
			k.gloss = true
			for i in 12:
				var a := TAU * i / 12.0
				k.cyl(Vector3(cos(a), 0, sin(a)) * w * 0.48 + Vector3(0, 1.5, 0), Vector3(cos(a), 0, sin(a)) * w * 0.55 + Vector3(0, 3.0 + (i % 3) * 0.5, 0), 0.18, 0.0, porcelain, 6)
			k.gloss = false
			k.ring(Vector3(0, 1.2, 0), Vector3.UP, w * 0.5, 0.12, T, 22, 4)
			k.cyl(Vector3(0, 1.6, 0), Vector3(0, 4.0, 0), 0.25, 0.15, sinew, 7)
			for i in 3:
				var a := TAU * i / 3.0
				k.cyl(Vector3(0, 4.0, 0), Vector3(cos(a) * 1.2, 3.6, sin(a) * 1.2), 0.04, 0.04, metal, 4)
				k.cyl(Vector3(cos(a) * 1.2, 3.6, sin(a) * 1.2), Vector3(cos(a) * 1.2, 2.6, sin(a) * 1.2), 0.025, 0.025, metal, 4)
				k.cyl(Vector3(cos(a) * 1.2, 2.6, sin(a) * 1.2), Vector3(cos(a) * 1.35, 2.4, sin(a) * 1.35), 0.03, 0.0, metal.lightened(0.2), 4)
		"forge":
			_block(k, Vector3(0, 0, 0), w * 0.85, w * 0.85, 2.0, metal, metal.darkened(0.3))
			k.gloss = true
			k.taper(Vector3(0, 2.0, 0), Vector2(w * 0.85, w * 0.85), Vector2(w * 0.4, w * 0.4), 1.2, porcelain)
			for x in [-0.25, 0.25]:
				k.cyl(Vector3(x * w, 3.0, 0), Vector3(x * w * 1.2, 5.5, -0.3), 0.35, 0.05, porcelain, 7)
			k.gloss = false
			k.box(Vector3(0, 0.8, w * 0.43), Vector3(1.4, 1.2, 0.05), Color(1.0, 0.35, 0.15), true)
			for i in 5:
				k.cyl(Vector3(-0.56 + i * 0.28, 1.45, w * 0.44), Vector3(-0.56 + i * 0.28, 1.2, w * 0.47), 0.05, 0.0, porcelain, 4)
			k.box(Vector3(0, 1.75, w * 0.43 + 0.04), Vector3(w * 0.7, 0.2, 0.04), T)
			k.ring(Vector3(0, 2.0, 0), Vector3.UP, w * 0.5, 0.1, sinew, 4, 3)
		"tower":
			# spine tower: stacked vertebrae with a spiked crown and a glowing eye
			k.gloss = true
			for i in 7:
				k.cyl(Vector3(0, i * 0.85, 0), Vector3(0, i * 0.85 + 0.6, 0), w * 0.32 - i * 0.025, w * 0.3 - i * 0.025, porcelain, 10)
				for side in [-1.0, 1.0]:
					k.cyl(Vector3(side * w * 0.25, i * 0.85 + 0.3, 0), Vector3(side * w * 0.5, i * 0.85 + 0.55, 0), 0.08, 0.0, porcelain, 4)
			k.gloss = false
			k.cyl(Vector3(0, 0, 0), Vector3(0, 6.0, 0), w * 0.18, w * 0.15, sinew, 8)
			k.sphere(Vector3(0, 6.3, 0), Vector3(0.45, 0.45, 0.45), glow, 8, 5, true)
			k.sphere(Vector3(0, 6.3, 0.38), Vector3(0.12, 0.2, 0.08), oil, 6, 4)
			for i in 5:
				var a := TAU * i / 5.0
				k.cyl(Vector3(cos(a) * 0.4, 6.0, sin(a) * 0.4), Vector3(cos(a) * 0.9, 7.6, sin(a) * 0.9), 0.1, 0.0, oil, 5)
			k.ring(Vector3(0, 2.0, 0), Vector3.UP, w * 0.31, 0.07, T, 14, 3)
		"stable":
			# hound kennels: low porcelain hutches with an oil trough
			k.gloss = true
			for x in [-0.28, 0.28]:
				k.sphere(Vector3(x * w, 0.6, -w * 0.1), Vector3(w * 0.24, 1.5, w * 0.36), porcelain, 12, 6)
				for i in 3:
					k.ring(Vector3(x * w, 0.7 + i * 0.4, -w * 0.1), Vector3.UP, w * 0.24 * (1.0 - i * 0.15), 0.04, porcelain.darkened(0.15), 12, 3)
			k.gloss = false
			k.box(Vector3(0, 0.2, w * 0.35), Vector3(w * 0.8, 0.4, 0.5), metal)
			k.box(Vector3(0, 0.42, w * 0.35), Vector3(w * 0.75, 0.04, 0.4), glow.darkened(0.3), true)
			for x in [-0.28, 0.28]:
				k.box(Vector3(x * w, 0.6, w * 0.25), Vector3(0.7, 0.9, 0.05), oil)
			k.ring(Vector3(0, 0.15, -w * 0.1), Vector3.UP, w * 0.5, 0.1, T, 18, 3)
			for i in 5:
				k.cyl(Vector3(-w * 0.4 + i * w * 0.2, 0, -w * 0.48), Vector3(-w * 0.4 + i * w * 0.2, 2.2, -w * 0.55), 0.12, 0.0, porcelain, 5)
		"workshop":
			# engine foundry: a furnace hall with a crane arm
			_block(k, Vector3(0, 0, 0), w * 0.95, w * 0.8, 2.4, metal, metal.darkened(0.3))
			k.gloss = true
			k.taper(Vector3(0, 2.4, 0), Vector2(w * 0.95, w * 0.8), Vector2(w * 0.2, w * 0.8), 1.3, porcelain)
			k.gloss = false
			k.cyl(Vector3(w * 0.35, 2.4, -w * 0.3), Vector3(w * 0.35, 5.0, -w * 0.3), 0.2, 0.15, sinew, 7)
			k.rig(P_SPIN, Vector3(w * 0.35, 5.0, -w * 0.3))
			k.cyl(Vector3(w * 0.35, 5.0, -w * 0.3), Vector3(-w * 0.2, 5.4, w * 0.2), 0.12, 0.08, metal, 6)
			k.cyl(Vector3(-w * 0.2, 5.4, w * 0.2), Vector3(-w * 0.2, 4.2, w * 0.2), 0.02, 0.02, DARK, 3)
			k.cyl(Vector3(-w * 0.2, 4.2, w * 0.2), Vector3(-w * 0.12, 4.0, w * 0.2), 0.05, 0.0, metal.lightened(0.2), 4)
			k.rig()
			k.box(Vector3(0, 1.0, w * 0.4 + 0.02), Vector3(1.8, 2.0, 0.05), Color(1.0, 0.35, 0.15), true)
			k.box(Vector3(0, 2.2, w * 0.4 + 0.1), Vector3(w * 0.8, 0.2, 0.04), T)
		"sanctum":
			# oil cathedral: a tall spiked spire weeping oil
			k.cyl(Vector3(0, 0, 0), Vector3(0, 1.5, 0), w * 0.48, w * 0.42, metal, 12)
			k.gloss = true
			k.cyl(Vector3(0, 1.5, 0), Vector3(0, 9.5, 0), w * 0.36, 0.0, porcelain, 12)
			for i in 6:
				var a := TAU * i / 6.0
				var c := Vector3(cos(a), 0, sin(a)) * w * 0.42
				k.cyl(c + Vector3(0, 1.0, 0), c * 1.15 + Vector3(0, 5.5, 0), 0.2, 0.0, porcelain, 6)
			k.cyl(Vector3(0, 1.5, w * 0.22), Vector3(0, 6.0, w * 0.06), 0.18, 0.04, oil, 7)
			k.gloss = false
			k.sphere(Vector3(0, 4.5, 0), Vector3(0.5, 0.5, 0.5), glow, 8, 5, true)
			k.ring(Vector3(0, 1.4, 0), Vector3.UP, w * 0.46, 0.12, T, 18, 4)


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
