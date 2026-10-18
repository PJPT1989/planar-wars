class_name MapData
extends RefCounted
## One match's map, laid out from a template (Data.MAPS) and a seed. Every player builds the
## same map from the same seed, so only the seed travels over the network. The map is a grid
## of Data.MAP_CELLS cells, 2 m each: what is on a cell (ground, water, cliff, thicket, bridge,
## ramp, paving), its height, the four start spots and where gold and aether lie.

enum { GROUND, WATER, CLIFF, THICKET, BRIDGE, RAMP, PAVING }

var template: Dictionary
var index := 0
var seed_v := 0
var n := Data.MAP_CELLS
var cells := PackedByteArray()
var heights := PackedFloat32Array()      # per cell
var vheights := PackedFloat32Array()     # per grid corner, (n+1)^2, for drawing and sampling
var starts: Array[Vector2i] = []         # cell of each start town hall's top-left corner
var resources: Array = []                # {"type": "gold"/"aether", "cell": Vector2i}
var props: Array = []                    # {"kind": String, "pos": Vector2 (metres), "scale": float, "rot": float}
var rng := RandomNumberGenerator.new()


static func generate(map_index: int, seed_value: int) -> MapData:
	var m := MapData.new()
	m.index = map_index
	m.template = Data.MAPS[map_index]
	m.seed_v = seed_value
	m.rng.seed = seed_value
	m._build()
	return m


func idx(c: Vector2i) -> int:
	return c.y * n + c.x


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < n and c.y < n


func get_cell(c: Vector2i) -> int:
	return cells[idx(c)] if inside(c) else CLIFF


func walkable(c: Vector2i) -> bool:
	if not inside(c):
		return false
	var t := cells[idx(c)]
	return t == GROUND or t == BRIDGE or t == RAMP or t == PAVING


func size_m() -> float:
	return n * Data.CELL


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / Data.CELL), floori(p.y / Data.CELL))


static func cell_centre(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * Data.CELL


## Ground height at a point in metres (bilinear over the grid corners).
func height_at(p: Vector2) -> float:
	var f := p / Data.CELL
	var x0 := clampi(floori(f.x), 0, n - 1)
	var z0 := clampi(floori(f.y), 0, n - 1)
	var tx := clampf(f.x - x0, 0.0, 1.0)
	var tz := clampf(f.y - z0, 0.0, 1.0)
	var w := n + 1
	var a := vheights[z0 * w + x0]
	var b := vheights[z0 * w + x0 + 1]
	var c := vheights[(z0 + 1) * w + x0]
	var d := vheights[(z0 + 1) * w + x0 + 1]
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), tz)


# --- layout --------------------------------------------------------------------------------

func _build() -> void:
	cells.resize(n * n)
	cells.fill(GROUND)
	heights.resize(n * n)
	heights.fill(0.0)
	var inset := 10
	starts = [Vector2i(inset, inset), Vector2i(n - inset - 4, n - inset - 4), Vector2i(n - inset - 4, inset), Vector2i(inset, n - inset - 4)]
	match str(template.shape):
		"open":
			_open()
		"river":
			_river()
		"canyon":
			_canyon()
		"ring":
			_ring()
	for i in starts.size():
		_clear_base(i)
	_base_resources()
	_expansions()
	_connect()
	_finish_heights()
	_scatter_props()


func _start_centre(i: int) -> Vector2:
	return Vector2(starts[i]) + Vector2(2, 2)


func _toward_centre(i: int) -> Vector2:
	return (Vector2(n, n) * 0.5 - _start_centre(i)).normalized()


func _blob(centre: Vector2, radius: float, kind: int, rough := 0.35) -> void:
	var r := int(ceil(radius * (1.0 + rough))) + 1
	var phase := rng.randf() * TAU
	var wob := rng.randf_range(2.0, 4.0)
	for y in range(int(centre.y) - r, int(centre.y) + r + 1):
		for x in range(int(centre.x) - r, int(centre.x) + r + 1):
			var c := Vector2i(x, y)
			if not inside(c):
				continue
			var d := Vector2(x + 0.5, y + 0.5) - centre
			var a := atan2(d.y, d.x)
			var lim := radius * (1.0 + rough * sin(a * wob + phase) * 0.6 + rough * 0.4 * sin(a * 2.0 * wob + phase * 1.7))
			if d.length() <= lim:
				cells[idx(c)] = kind


func _far_from_starts(p: Vector2, dist: float) -> bool:
	for i in starts.size():
		if p.distance_to(_start_centre(i)) < dist:
			return false
	return true


func _open() -> void:
	# ponds and copses, kept away from the bases
	for k in 7:
		for tries in 30:
			var p := Vector2(rng.randf_range(8, n - 8), rng.randf_range(8, n - 8))
			if _far_from_starts(p, 20.0):
				_blob(p, rng.randf_range(2.2, 4.2), WATER)
				break
	for k in 26:
		for tries in 30:
			var p := Vector2(rng.randf_range(2, n - 2), rng.randf_range(2, n - 2))
			if _far_from_starts(p, 15.0):
				_blob(p, rng.randf_range(1.2, 3.2), THICKET, 0.5)
				break
	# hedgerows along the map edge
	for k in n:
		for e in [0, n - 1]:
			if rng.randf() < 0.7:
				cells[idx(Vector2i(k, e))] = THICKET
				cells[idx(Vector2i(e, k))] = THICKET


func _river() -> void:
	var mid := n / 2
	# a paved city everywhere, split by two canals that cross in the middle
	cells.fill(PAVING)
	for k in n:
		var wob := int(round(sin(k * 0.21 + rng.randf() * 0.2) * 1.2))
		for w in range(-2, 2):
			cells[idx(Vector2i(k, mid + w + wob))] = WATER
			cells[idx(Vector2i(mid + w - wob, k))] = WATER
	_blob(Vector2(mid, mid), 4.5, WATER, 0.1)
	# bridges: two on each arm of the canals, between the crossing and the edge
	for along in [11, 26, n - 29, n - 14]:
		for arm in 2:
			for w in range(-4, 5):
				for b in 3:
					var c := Vector2i(along + b, mid + w) if arm == 0 else Vector2i(mid + w, along + b)
					if inside(c) and cells[idx(c)] == WATER:
						cells[idx(c)] = BRIDGE
	# ruined blocks in the districts
	for k in 30:
		for tries in 30:
			var p := Vector2(rng.randf_range(3, n - 3), rng.randf_range(3, n - 3))
			if _far_from_starts(p, 14.0) and absf(p.x - mid) > 6 and absf(p.y - mid) > 6:
				var s := Vector2i(rng.randi_range(1, 3), rng.randi_range(1, 3))
				for y in s.y:
					for x in s.x:
						var c := Vector2i(int(p.x) + x, int(p.y) + y)
						if inside(c):
							cells[idx(c)] = THICKET
				break
	# grass squares
	for k in 10:
		var p := Vector2(rng.randf_range(4, n - 4), rng.randf_range(4, n - 4))
		var r := rng.randf_range(2.0, 4.0)
		for y in range(int(p.y - r), int(p.y + r)):
			for x in range(int(p.x - r), int(p.x + r)):
				var c := Vector2i(x, y)
				if inside(c) and cells[idx(c)] == PAVING:
					cells[idx(c)] = GROUND


func _canyon() -> void:
	var plateau := 3.2
	var r := 21
	for i in starts.size():
		var sc := _start_centre(i)
		var corner := Vector2(0 if sc.x < n / 2 else n, 0 if sc.y < n / 2 else n)
		for y in n:
			for x in n:
				var p := Vector2(x + 0.5, y + 0.5)
				var d := maxf(absf(p.x - corner.x), absf(p.y - corner.y))
				var d2 := p.distance_to(corner)
				var edge := minf(float(r + 4) - d, float(r + 9) * 1.12 - d2)
				var c := Vector2i(x, y)
				if edge > 1.0:
					heights[idx(c)] = plateau
				elif edge > -1.0:
					cells[idx(c)] = CLIFF
					heights[idx(c)] = plateau * 0.5
		# two ramps, toward the neighbouring sides
		var dir_x := Vector2(1 if corner.x == 0 else -1, 0)
		var dir_z := Vector2(0, 1 if corner.y == 0 else -1)
		for dir in [dir_x, dir_z]:
			var along := Vector2(corner.x + (r * 0.55 if corner.x == 0 else -r * 0.55), corner.y + (r * 0.55 if corner.y == 0 else -r * 0.55))
			var side := Vector2(dir.y, dir.x).abs()
			var start: Vector2 = along + dir * (r * 0.0)
			# walk outward from the plateau along dir until clear of the cliff
			for step in range(0, 40):
				var p: Vector2 = start + dir * step
				for w in range(-2, 3):
					var c := Vector2i(int(p.x + side.x * w), int(p.y + side.y * w))
					if not inside(c):
						continue
					if cells[idx(c)] == CLIFF:
						cells[idx(c)] = RAMP
						heights[idx(c)] = plateau * 0.5
				if step > 4 and get_cell(Vector2i(int(p.x), int(p.y))) == GROUND and heights[idx(Vector2i(clampi(int(p.x), 0, n - 1), clampi(int(p.y), 0, n - 1)))] == 0.0:
					break
	# boulders and a pool on the canyon floor
	for k in 18:
		for tries in 30:
			var p := Vector2(rng.randf_range(4, n - 4), rng.randf_range(4, n - 4))
			var c := Vector2i(p)
			if heights[idx(c)] == 0.0 and cells[idx(c)] == GROUND and _far_from_starts(p, 26.0):
				_blob(p, rng.randf_range(1.0, 2.4), THICKET, 0.6)
				break
	_blob(Vector2(n / 2, n / 2) + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3)), 3.0, WATER, 0.3)


func _ring() -> void:
	# a thicket ring around each base with two gaps, oil pools and a rich centre
	for i in starts.size():
		var sc := _start_centre(i)
		var to_c := _toward_centre(i)
		var gap_a := atan2(to_c.y, to_c.x) + rng.randf_range(-0.6, 0.6)
		var gaps := [gap_a + 0.9, gap_a - 0.9]
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5, y + 0.5) - sc
				var dist := d.length()
				if dist > 15.0 and dist < 18.5:
					var a := atan2(d.y, d.x)
					var open := false
					for g in gaps:
						if absf(wrapf(a - g, -PI, PI)) < 0.22:
							open = true
					if not open:
						cells[idx(Vector2i(x, y))] = THICKET
	for k in 8:
		for tries in 30:
			var p := Vector2(rng.randf_range(6, n - 6), rng.randf_range(6, n - 6))
			if _far_from_starts(p, 22.0) and p.distance_to(Vector2(n, n) * 0.5) > 8.0:
				_blob(p, rng.randf_range(1.6, 3.0), WATER)
				break
	for k in 14:
		for tries in 30:
			var p := Vector2(rng.randf_range(2, n - 2), rng.randf_range(2, n - 2))
			if _far_from_starts(p, 21.0) and p.distance_to(Vector2(n, n) * 0.5) > 9.0:
				_blob(p, rng.randf_range(1.0, 2.2), THICKET, 0.6)
				break


func _clear_base(i: int) -> void:
	var sc := _start_centre(i)
	var h := heights[idx(Vector2i(sc))]
	for y in range(int(sc.y) - 10, int(sc.y) + 11):
		for x in range(int(sc.x) - 10, int(sc.x) + 11):
			var c := Vector2i(x, y)
			if not inside(c):
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(sc) < 10.5:
				var t := cells[idx(c)]
				if t == WATER or t == THICKET:
					cells[idx(c)] = PAVING if str(template.shape) == "river" else GROUND
				if t == CLIFF and str(template.shape) != "canyon":
					cells[idx(c)] = GROUND
				if str(template.shape) != "canyon":
					heights[idx(c)] = h


## Gold and aether next to each base: a vein row on one side, crystals on the other.
func _base_resources() -> void:
	for i in starts.size():
		var sc := _start_centre(i)
		var to_c := _toward_centre(i)
		var side := Vector2(-to_c.y, to_c.x)
		var a0 := atan2(side.y, side.x) + rng.randf_range(-0.3, 0.3)
		_cluster("gold", sc + Vector2(cos(a0), sin(a0)) * 7.5, 8)
		var a1 := atan2(-side.y, -side.x) + rng.randf_range(-0.3, 0.3)
		_cluster("aether", sc + Vector2(cos(a1), sin(a1)) * 7.5, 7)


func _cluster(type: String, centre: Vector2, count: int) -> void:
	var placed := 0
	var ring := 0
	var order: Array[Vector2i] = []
	for y in range(-3, 4):
		for x in range(-3, 4):
			order.append(Vector2i(x, y))
	order.sort_custom(func(a: Vector2i, b: Vector2i): return Vector2(a).length() < Vector2(b).length())
	for o in order:
		if placed >= count:
			break
		var c: Vector2i = Vector2i(centre) + o
		if not inside(c) or not walkable(c) or _is_resource(c) or _in_start(c, 1):
			continue
		resources.append({"type": type, "cell": c})
		placed += 1


func _is_resource(c: Vector2i) -> bool:
	for r in resources:
		if r.cell == c:
			return true
	return false


func _in_start(c: Vector2i, pad: int) -> bool:
	for s in starts:
		if c.x >= s.x - pad and c.x < s.x + 4 + pad and c.y >= s.y - pad and c.y < s.y + 4 + pad:
			return true
	return false


## Extra deposits away from the bases, richer in the middle, so armies have something to
## fight over.
func _expansions() -> void:
	var mid := Vector2(n, n) * 0.5
	var spots: Array[Vector2] = [mid + Vector2(0, -24), mid + Vector2(0, 24), mid + Vector2(-24, 0), mid + Vector2(24, 0)]
	for k in spots.size():
		var p := spots[k] + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
		_clear_disc(p, 4.0)
		_cluster("gold" if k % 2 == 0 else "aether", p, 5)
	var centre_gold := 8 if str(template.shape) == "ring" else 5
	var cp := mid + Vector2(rng.randf_range(-2, 2), rng.randf_range(-2, 2)) + Vector2(6, 6)
	if str(template.shape) == "river":
		cp = mid + Vector2(10, 10)
	_clear_disc(cp, 3.5)
	_cluster("gold", cp, centre_gold)
	var ap := mid - Vector2(6, 6) if str(template.shape) != "river" else mid - Vector2(10, 10)
	_clear_disc(ap, 3.5)
	_cluster("aether", ap, centre_gold)


func _clear_disc(p: Vector2, r: float) -> void:
	for y in range(int(p.y - r) - 1, int(p.y + r) + 2):
		for x in range(int(p.x - r) - 1, int(p.x + r) + 2):
			var c := Vector2i(x, y)
			if inside(c) and Vector2(x + 0.5, y + 0.5).distance_to(p) <= r:
				var t := cells[idx(c)]
				if t == THICKET or t == WATER:
					cells[idx(c)] = PAVING if str(template.shape) == "river" else GROUND


## Makes sure every base can walk to the middle: if a flood fill from a base cannot reach it,
## a path is cut straight through.
func _connect() -> void:
	var mid := Vector2i(n / 2 + 6, n / 2 + 6)
	if not walkable(mid):
		mid = Vector2i(n / 2 + 8, n / 2 + 2)
	for i in starts.size():
		var reach := _flood(starts[i] + Vector2i(5, 2))
		if reach.has(idx(mid)):
			continue
		var a := Vector2(starts[i]) + Vector2(2, 2)
		var b := Vector2(mid)
		var steps := int(a.distance_to(b))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / steps)
			for w in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				var c: Vector2i = Vector2i(p) + w
				if not inside(c):
					continue
				var t := cells[idx(c)]
				if t == WATER:
					cells[idx(c)] = BRIDGE
				elif t == CLIFF:
					cells[idx(c)] = RAMP
				elif t == THICKET:
					cells[idx(c)] = GROUND


func _flood(from: Vector2i) -> Dictionary:
	var seen := {}
	var stack: Array[Vector2i] = [from]
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		if not walkable(c) or seen.has(idx(c)):
			continue
		seen[idx(c)] = true
		stack.append(c + Vector2i(1, 0))
		stack.append(c + Vector2i(-1, 0))
		stack.append(c + Vector2i(0, 1))
		stack.append(c + Vector2i(0, -1))
	return seen


func _finish_heights() -> void:
	for i in n * n:
		if cells[i] == WATER:
			heights[i] = minf(heights[i], 0.0) - 0.9
	var w := n + 1
	vheights.resize(w * w)
	for y in w:
		for x in w:
			var sum := 0.0
			var cnt := 0
			for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var c: Vector2i = Vector2i(x, y) + o
				if inside(c):
					sum += heights[idx(c)]
					cnt += 1
			vheights[y * w + x] = sum / maxi(cnt, 1)


## Trees, ruins, pipes or metal spires on the thicket cells, plus loose decoration.
func _scatter_props() -> void:
	var kind := str(template.tree)
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			var t := cells[idx(c)]
			if t == THICKET:
				var count := 1 if kind == "ruin" else 2
				for k in count:
					var p := (Vector2(c) + Vector2(rng.randf_range(0.15, 0.85), rng.randf_range(0.15, 0.85))) * Data.CELL
					props.append({"kind": kind, "pos": p, "scale": rng.randf_range(0.8, 1.25), "rot": rng.randf() * TAU})
			elif t == CLIFF:
				if rng.randf() < 0.6:
					var p := (Vector2(c) + Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.2, 0.8))) * Data.CELL
					props.append({"kind": "boulder", "pos": p, "scale": rng.randf_range(0.9, 1.6), "rot": rng.randf() * TAU})
			elif (t == GROUND or t == PAVING) and rng.randf() < 0.025 and not _in_start(c, 1) and not _is_resource(c):
				var p := (Vector2(c) + Vector2(rng.randf(), rng.randf())) * Data.CELL
				props.append({"kind": "pebble" if rng.randf() < 0.5 else "shrub", "pos": p, "scale": rng.randf_range(0.6, 1.2), "rot": rng.randf() * TAU})
