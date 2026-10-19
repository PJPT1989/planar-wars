class_name MeshKit
extends RefCounted
## Builds meshes out of boxes, cylinders, cones, spheres, rings and lofted shells with vertex
## colours. A mesh has up to three surfaces: "solid" (lit), "glow" (emissive aether and magic)
## and "gloss" (porcelain, oil, polished metal). Every unit, building and prop is made with this.
## Units and buildings are rigged: `rig(part, pivot)` tags what follows as a moving part (a leg,
## an arm, a wing, a wheel; see Models.P_*) turning about `pivot`, which shaders/rig.gdshaderinc
## animates from the instance data.

var _st: Array[SurfaceTool] = [SurfaceTool.new(), SurfaceTool.new(), SurfaceTool.new()]
var _used := [false, false, false]
## Transform applied to everything added (set it to place a part).
var xf := Transform3D.IDENTITY
## While true, everything that does not glow goes on the glossy surface.
var gloss := false
## The rigged part (0: fixed) and its pivot for everything added (see `rig`).
var part := 0
var pivot := Vector3.ZERO


func _init() -> void:
	for s in _st:
		s.begin(Mesh.PRIMITIVE_TRIANGLES)


## One triangle, corners counter-clockwise seen from the front (Godot wants clockwise, so the
## order is swapped here).
func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, glow := false, na := Vector3.ZERO, nb := Vector3.ZERO, nc := Vector3.ZERO) -> void:
	a = xf * a
	b = xf * b
	c = xf * c
	var flat := (b - a).cross(c - a).normalized()
	if na == Vector3.ZERO:
		na = flat
		nb = flat
		nc = flat
	else:
		na = (xf.basis * na).normalized()
		nb = (xf.basis * nb).normalized()
		nc = (xf.basis * nc).normalized()
	var i := 1 if glow else (2 if gloss else 0)
	_used[i] = true
	var s := _st[i]
	s.set_uv(Vector2(part, pivot.x))
	s.set_uv2(Vector2(pivot.y, pivot.z))
	s.set_color(col)
	s.set_normal(na)
	s.add_vertex(a)
	s.set_normal(nc)
	s.add_vertex(c)
	s.set_normal(nb)
	s.add_vertex(b)


## Tags everything added from now on as part `p` turning about `at` (in the same space as the
## points; `xf` as it is now applies to it). rig() alone goes back to the fixed body.
func rig(p := 0, at := Vector3.ZERO) -> void:
	part = p
	pivot = xf * at


func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, glow := false) -> void:
	tri(a, b, c, col, glow)
	tri(a, c, d, col, glow)


## Box centred at `c` with full size `s`, optionally rotated about Y by `yaw`.
func box(c: Vector3, s: Vector3, col: Color, glow := false, yaw := 0.0) -> void:
	var h := s * 0.5
	var bs := Basis(Vector3.UP, yaw)
	var p: Array[Vector3] = []
	for k in 8:
		p.append(c + bs * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	quad(p[0], p[2], p[3], p[1], col, glow)   # -z
	quad(p[4], p[5], p[7], p[6], col, glow)   # +z
	quad(p[0], p[4], p[6], p[2], col, glow)   # -x
	quad(p[5], p[1], p[3], p[7], col, glow)   # +x
	quad(p[2], p[6], p[7], p[3], col, glow)   # +y
	quad(p[0], p[1], p[5], p[4], col, glow)   # -y


## Tapered box: bottom size `b` (x,z), top size `t` (x,z), height h, base centre at `c`.
func taper(c: Vector3, b: Vector2, t: Vector2, h: float, col: Color, glow := false, yaw := 0.0, top_off := Vector3.ZERO) -> void:
	var bs := Basis(Vector3.UP, yaw)
	var lo: Array[Vector3] = []
	var hi: Array[Vector3] = []
	for k in 4:
		var sx := -1.0 if k == 0 or k == 3 else 1.0
		var sz := -1.0 if k < 2 else 1.0
		lo.append(c + bs * Vector3(sx * b.x * 0.5, 0, sz * b.y * 0.5))
		hi.append(c + bs * (Vector3(sx * t.x * 0.5, h, sz * t.y * 0.5) + top_off))
	for k in 4:
		var n := (k + 1) % 4
		quad(lo[n], lo[k], hi[k], hi[n], col, glow)
	quad(hi[0], hi[3], hi[2], hi[1], col, glow)
	quad(lo[0], lo[1], lo[2], lo[3], col, glow)


## Cylinder or cone along an axis from `a` to `b`, radii ra at a and rb at b.
func cyl(a: Vector3, b: Vector3, ra: float, rb: float, col: Color, segs := 8, glow := false, smooth := true, caps := true) -> void:
	var ax := b - a
	var up := ax.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
	var fwd := side.cross(up)
	var slope := (ra - rb) / maxf(ax.length(), 0.001)
	for k in segs:
		var a0 := TAU * k / segs
		var a1 := TAU * (k + 1) / segs
		var d0 := side * cos(a0) + fwd * sin(a0)
		var d1 := side * cos(a1) + fwd * sin(a1)
		var p0 := a + d0 * ra
		var p1 := a + d1 * ra
		var q0 := b + d0 * rb
		var q1 := b + d1 * rb
		if smooth:
			var n0 := (d0 + up * slope).normalized()
			var n1 := (d1 + up * slope).normalized()
			tri(p0, q0, q1, col, glow, n0, n0, n1)
			tri(p0, q1, p1, col, glow, n0, n1, n1)
		else:
			quad(p0, q0, q1, p1, col, glow)
		if caps:
			if rb > 0.0:
				tri(b, q1, q0, col, glow)
			if ra > 0.0:
				tri(a, p0, p1, col, glow)


## Low-poly ellipsoid centred at c with radii r.
func sphere(c: Vector3, r: Vector3, col: Color, segs := 8, rings := 5, glow := false) -> void:
	for j in rings:
		var t0 := PI * j / rings - PI * 0.5
		var t1 := PI * (j + 1) / rings - PI * 0.5
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var u: Array[Vector3] = [
				Vector3(cos(t0) * cos(a0), sin(t0), cos(t0) * sin(a0)),
				Vector3(cos(t0) * cos(a1), sin(t0), cos(t0) * sin(a1)),
				Vector3(cos(t1) * cos(a1), sin(t1), cos(t1) * sin(a1)),
				Vector3(cos(t1) * cos(a0), sin(t1), cos(t1) * sin(a0))]
			var p: Array[Vector3] = []
			for v in u:
				p.append(c + v * r)
			tri(p[0], p[3], p[2], col, glow, u[0], u[3], u[2])
			tri(p[0], p[2], p[1], col, glow, u[0], u[2], u[1])


## Ring (torus) around axis `axis` through centre c: major radius R, tube radius r.
func ring(c: Vector3, axis: Vector3, big: float, r: float, col: Color, segs := 16, tube := 5, glow := false, arc := TAU) -> void:
	var up := axis.normalized()
	var side := up.cross(Vector3.FORWARD if absf(up.y) > 0.9 else Vector3.UP).normalized()
	var fwd := side.cross(up)
	for k in segs:
		var a0 := arc * k / segs
		var a1 := arc * (k + 1) / segs
		var d0 := side * cos(a0) + fwd * sin(a0)
		var d1 := side * cos(a1) + fwd * sin(a1)
		for j in tube:
			var b0 := TAU * j / tube
			var b1 := TAU * (j + 1) / tube
			var n00 := d0 * cos(b0) + up * sin(b0)
			var n01 := d0 * cos(b1) + up * sin(b1)
			var n10 := d1 * cos(b0) + up * sin(b0)
			var n11 := d1 * cos(b1) + up * sin(b1)
			var p00 := c + d0 * big + n00 * r
			var p01 := c + d0 * big + n01 * r
			var p10 := c + d1 * big + n10 * r
			var p11 := c + d1 * big + n11 * r
			tri(p00, p11, p10, col, glow, n00, n11, n10)
			tri(p00, p01, p11, col, glow, n00, n01, n11)


## Irregular rock: a jittered sphere, deterministic from `seed`.
func rock(c: Vector3, r: Vector3, col: Color, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var segs := 7
	var rings := 4
	var pts := {}
	for j in rings + 1:
		for k in segs:
			var t := PI * j / rings - PI * 0.5
			var a := TAU * k / segs
			var jit := 1.0 if j == 0 or j == rings else rng.randf_range(0.75, 1.2)
			pts[Vector2i(j, k)] = c + Vector3(cos(t) * cos(a), sin(t), cos(t) * sin(a)) * r * jit
	for j in rings:
		for k in segs:
			var k1 := (k + 1) % segs
			var shade := col.darkened(rng.randf_range(0.0, 0.18))
			quad(pts[Vector2i(j, k)], pts[Vector2i(j + 1, k)], pts[Vector2i(j + 1, k1)], pts[Vector2i(j, k1)], shade)


## Smooth shell through rows of points: rows[i] is one cross-section, its points going round
## the same way in every row. `col` is a Color or a Callable(t, a, centre, normal) -> Color
## called per quad, with t along the rows and a around them (both 0..1). The ends are capped
## when `caps` is set. Normals are averaged, so the shell shades smoothly.
func loft(rows: Array, col: Variant, glow := false, closed := true, caps := true) -> void:
	var nr := rows.size()
	var nc: int = rows[0].size()
	var ncol := nc if closed else nc - 1
	var nrm: Array = []
	for i in nr:
		var row: PackedVector3Array = rows[i]
		var mid := Vector3.ZERO
		for p in row:
			mid += p
		mid /= nc
		var ns := PackedVector3Array()
		for j in nc:
			var along: Vector3 = rows[mini(i + 1, nr - 1)][j] - rows[maxi(i - 1, 0)][j]
			var jn := (j + 1) % nc if closed else mini(j + 1, nc - 1)
			var jp := (j - 1 + nc) % nc if closed else maxi(j - 1, 0)
			var around := row[jn] - row[jp]
			var n := along.cross(around)
			if n.length_squared() < 1e-10:
				n = row[j] - mid
			n = n.normalized()
			if n.dot(row[j] - mid) < 0.0:
				n = -n
			ns.append(n)
		nrm.append(ns)
	for i in nr - 1:
		for j in ncol:
			var j1 := (j + 1) % nc
			var p00: Vector3 = rows[i][j]
			var p01: Vector3 = rows[i][j1]
			var p10: Vector3 = rows[i + 1][j]
			var p11: Vector3 = rows[i + 1][j1]
			var n00: Vector3 = nrm[i][j]
			var n01: Vector3 = nrm[i][j1]
			var n10: Vector3 = nrm[i + 1][j]
			var n11: Vector3 = nrm[i + 1][j1]
			var navg := (n00 + n01 + n10 + n11).normalized()
			var c: Color = col.call((i + 0.5) / (nr - 1), (j + 0.5) / ncol, (p00 + p01 + p10 + p11) * 0.25, navg) if col is Callable else col
			if (p10 - p00).cross(p11 - p00).dot(navg) >= 0.0:
				tri(p00, p10, p11, c, glow, n00, n10, n11)
				tri(p00, p11, p01, c, glow, n00, n11, n01)
			else:
				tri(p00, p11, p10, c, glow, n00, n11, n10)
				tri(p00, p01, p11, c, glow, n00, n01, n11)
	if caps:
		for e in [0, nr - 1]:
			var row: PackedVector3Array = rows[e]
			var mid := _centre(row)
			var out: Vector3 = mid - _centre(rows[1] if e == 0 else rows[nr - 2])
			var c: Color = col.call(0.0 if e == 0 else 1.0, 0.5, mid, out.normalized()) if col is Callable else col
			for j in ncol:
				var a := row[j]
				var b := row[(j + 1) % nc]
				if (a - mid).cross(b - mid).dot(out) >= 0.0:
					tri(mid, a, b, c, glow)
				else:
					tri(mid, b, a, c, glow)


static func _centre(row: PackedVector3Array) -> Vector3:
	var m := Vector3.ZERO
	for p in row:
		m += p
	return m / maxi(row.size(), 1)


## Turns what was added into a mesh. `mats` replaces the three materials (solid, glow, gloss).
func commit(mesh: ArrayMesh = null, mats: Array = []) -> ArrayMesh:
	if mesh == null:
		mesh = ArrayMesh.new()
	if mats.is_empty():
		mats = [Game.mat_solid, Game.mat_glow, Game.mat_gloss]
	for i in 3:
		if _used[i]:
			_st[i].commit(mesh)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[i])
	return mesh
