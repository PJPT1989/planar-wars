class_name View
extends Node3D
## Draws a match: the terrain (one mesh, coloured per cell), water, bridges and props, then every
## unit, building and deposit through MultiMeshes (one per model, all players in one batch, team
## colour from the instance data), plus selection rings, projectiles, dust and fire. It reads
## the Sim (the host's real one or a guest's mirror) and interpolates between its 10 Hz steps.
## It also keeps the local player's fog of war and owns the camera.

const PITCH := deg_to_rad(56.0)
const FLY_HEIGHT := 4.5
const ZOOM_MIN := 18.0
const ZOOM_MAX := 75.0

var sim: Sim
var me := -1                           # local player (-1: spectator, no fog)
var cam: Camera3D
var cam_target := Vector2(40, 40)
var zoom := 44.0
var alpha := 1.0                       # 0..1 between the previous and the current sim step
var selected := {}                     # ids the local player has selected
var hover_id := 0
var ghost: MeshInstance3D
var fog_on := true

var _env: Environment
var _sun: DirectionalLight3D
var _ground_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _fog_img: Image
var _fog_tex: ImageTexture
var visible_grid := PackedByteArray()  # 2 = in sight, 1 = explored, 0 = never seen
var _fog_t := 0.0
var _discs := {}
var _batches := {}
var _fx_mat: ShaderMaterial
var _ring_mesh: ArrayMesh
var _projectiles: Array = []
var _puffs: Array = []
var _markers: Array = []
var _last := {}                        # id -> {"atk": int, "hp": float, "flash": float, "pos": Vector2, "role", "owner", "cat", "swing": float}
var _res_dirty := true
var _res_count := -1
var _time := 0.0


func setup(s: Sim, local_player: int) -> void:
	sim = s
	me = local_player
	fog_on = me >= 0
	var t: Dictionary = sim.map.template
	Game.set_sky(t)
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = load("res://shaders/fx.gdshader")
	_build_env(t)
	_build_terrain(t)
	_build_props()
	_build_fx_meshes()
	visible_grid.resize(sim.map.n * sim.map.n)
	visible_grid.fill(0)
	_fog_img = Image.create(sim.map.n, sim.map.n, false, Image.FORMAT_L8)
	_fog_img.fill(Color(0, 0, 0) if fog_on else Color(1, 1, 1))
	_fog_tex = ImageTexture.create_from_image(_fog_img)
	for m in [_ground_mat, _water_mat]:
		m.set_shader_parameter("fog_tex", _fog_tex)
		m.set_shader_parameter("map_size", sim.map.size_m())
		m.set_shader_parameter("fog_on", 1.0 if fog_on else 0.0)
	ghost = MeshInstance3D.new()
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	add_child(ghost)
	_update_fog()
	apply_quality()
	if me >= 0:
		for e in sim.list:
			if e.owner == me and e.role == "hall":
				cam_target = e.pos + Vector2(0, 6)
	_place_camera()


func _build_env(t: Dictionary) -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(t.fog).darkened(0.6)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(t.sky_horizon).lerp(Color(t.ground), 0.3)
	_env.ambient_light_energy = 0.55
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.0
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.05
	_env.glow_hdr_threshold = 1.1
	_env.fog_enabled = true
	_env.fog_light_color = t.fog
	_env.fog_density = 0.0035
	_env.fog_sky_affect = 0.0
	cam = Camera3D.new()
	cam.fov = 38.0
	cam.near = 1.0
	cam.far = 400.0
	cam.environment = _env
	add_child(cam)
	cam.current = true
	_sun = DirectionalLight3D.new()
	_sun.light_color = t.sun
	_sun.light_energy = 1.25
	_sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(-35), 0)
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 120.0
	_sun.shadow_bias = 0.06
	add_child(_sun)


func apply_quality() -> void:
	var q := Game.quality
	_sun.shadow_enabled = q >= Game.MEDIUM
	_env.glow_enabled = q >= Game.MEDIUM
	_ground_mat.set_shader_parameter("detail", 1.0 if q >= Game.MEDIUM else 0.5)
	for b in _batches.values():
		b.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if q >= Game.MEDIUM and b.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


# --- terrain -------------------------------------------------------------------------------

func _cell_colour(t: Dictionary, c: Vector2i, rng_v: float) -> Color:
	var m := sim.map
	var ground: Color = Color(t.ground).lerp(t.ground2, clampf(rng_v, 0.0, 1.0))
	match m.get_cell(c):
		MapData.WATER:
			return Color(t.dirt).darkened(0.35)
		MapData.CLIFF:
			return t.rock
		MapData.THICKET:
			return ground.darkened(0.25).lerp(t.dirt, 0.3)
		MapData.PAVING, MapData.BRIDGE:
			return Color(t.rock).lerp(t.ground2, 0.25).lightened(0.1)
		MapData.RAMP:
			return ground.lerp(t.dirt, 0.6)
	return ground


func _build_terrain(t: Dictionary) -> void:
	var m := sim.map
	var n := m.n
	var noise := FastNoiseLite.new()
	noise.seed = m.seed_v
	noise.frequency = 0.06
	var cols := []
	var pave := PackedFloat32Array()
	var rocky := PackedFloat32Array()
	pave.resize(n * n)
	rocky.resize(n * n)
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			var v := noise.get_noise_2d(x, y) * 0.8 + 0.5
			var col := _cell_colour(t, c, v)
			# worn dirt around the start spots and deposits
			cols.append(col)
			var ct := m.get_cell(c)
			pave[m.idx(c)] = 1.0 if ct == MapData.PAVING or ct == MapData.BRIDGE else 0.0
			rocky[m.idx(c)] = 1.0 if ct == MapData.CLIFF else (0.5 if ct == MapData.RAMP else 0.0)
	for s in m.starts:
		var centre := Vector2(s) + Vector2(2, 2)
		for y in range(int(centre.y) - 7, int(centre.y) + 8):
			for x in range(int(centre.x) - 7, int(centre.x) + 8):
				var c := Vector2i(x, y)
				if m.inside(c) and m.get_cell(c) == MapData.GROUND:
					var d := Vector2(x + 0.5, y + 0.5).distance_to(centre)
					cols[m.idx(c)] = (cols[m.idx(c)] as Color).lerp(t.dirt, clampf(1.0 - d / 7.0, 0.0, 0.55))
	var sub := 2
	var vn := n * sub + 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts := PackedVector3Array()
	var vcols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(vn * vn)
	vcols.resize(vn * vn)
	uvs.resize(vn * vn)
	for j in vn:
		for i in vn:
			var p := Vector2(i, j) * (Data.CELL / sub)
			var h := m.height_at(p)
			# sample the four nearest cell centres for smooth colour
			var f := p / Data.CELL - Vector2(0.5, 0.5)
			var x0 := clampi(floori(f.x), 0, n - 1)
			var y0 := clampi(floori(f.y), 0, n - 1)
			var x1 := clampi(x0 + 1, 0, n - 1)
			var y1 := clampi(y0 + 1, 0, n - 1)
			var tx := clampf(f.x - floorf(f.x), 0.0, 1.0)
			var ty := clampf(f.y - floorf(f.y), 0.0, 1.0)
			var c00: Color = cols[y0 * n + x0]
			var c10: Color = cols[y0 * n + x1]
			var c01: Color = cols[y1 * n + x0]
			var c11: Color = cols[y1 * n + x1]
			var col := c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), ty)
			var pv := lerpf(lerpf(pave[y0 * n + x0], pave[y0 * n + x1], tx), lerpf(pave[y1 * n + x0], pave[y1 * n + x1], tx), ty)
			var rv := lerpf(lerpf(rocky[y0 * n + x0], rocky[y0 * n + x1], tx), lerpf(rocky[y1 * n + x0], rocky[y1 * n + x1], tx), ty)
			var k := j * vn + i
			verts[k] = Vector3(p.x, h, p.y)
			vcols[k] = col
			uvs[k] = Vector2(pv, rv)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var idx := PackedInt32Array()
	for j in vn - 1:
		for i in vn - 1:
			var a := j * vn + i
			var b := a + 1
			var c := a + vn
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_COLOR] = vcols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	st.create_from(mesh, 0)
	st.generate_normals()
	mesh = st.commit()
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://shaders/ground.gdshader")
	var gi := MeshInstance3D.new()
	gi.mesh = mesh
	gi.material_override = _ground_mat
	add_child(gi)
	# water plane and the dark world beyond the map edge
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://shaders/water.gdshader")
	_water_mat.set_shader_parameter("deep", t.water)
	_water_mat.set_shader_parameter("sky", t.sky_horizon)
	_water_mat.set_shader_parameter("oil", 1.0 if t.id == "mirrex" else 0.0)
	var wq := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2.ONE * m.size_m()
	wq.mesh = pm
	wq.position = Vector3(m.size_m() * 0.5, -0.35, m.size_m() * 0.5)
	wq.material_override = _water_mat
	wq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wq)
	var edge := MeshInstance3D.new()
	var em := PlaneMesh.new()
	em.size = Vector2.ONE * m.size_m() * 4.0
	edge.mesh = em
	edge.position = Vector3(m.size_m() * 0.5, -1.5, m.size_m() * 0.5)
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(t.fog).darkened(0.75)
	emat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	edge.material_override = emat
	add_child(edge)
	# bridges: planks over the water
	var k := MeshKit.new()
	for y in n:
		for x in n:
			var c := Vector2i(x, y)
			if m.get_cell(c) == MapData.BRIDGE:
				var p := MapData.cell_centre(c)
				k.box(Vector3(p.x, 0.0, p.y), Vector3(2.02, 0.25, 2.02), Color(0.42, 0.3, 0.2) if t.id != "canals" else Color(0.5, 0.47, 0.45))
				if m.get_cell(c + Vector2i(1, 0)) == MapData.WATER or m.get_cell(c + Vector2i(-1, 0)) == MapData.WATER:
					pass
	var bi := MeshInstance3D.new()
	bi.mesh = k.commit()
	add_child(bi)


func _build_props() -> void:
	var groups := {}
	for pr in sim.map.props:
		var variant := int(abs(pr.pos.x * 7.3 + pr.pos.y * 3.1)) % 2
		var key := "%s:%d" % [pr.kind, variant]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(pr)
	for key in groups:
		var parts: PackedStringArray = key.split(":")
		var mesh := Models.prop(parts[0], int(parts[1]))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		var arr: Array = groups[key]
		mm.instance_count = arr.size()
		for i in arr.size():
			var pr: Dictionary = arr[i]
			var xf := Transform3D(Basis(Vector3.UP, pr.rot).scaled(Vector3.ONE * pr.scale), Vector3(pr.pos.x, sim.map.height_at(pr.pos) - 0.05, pr.pos.y))
			mm.set_instance_transform(i, xf)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		add_child(mi)


func _build_fx_meshes() -> void:
	var k := MeshKit.new()
	k.ring(Vector3.ZERO, Vector3.UP, 1.0, 0.07, Color.WHITE, 28, 3)
	_ring_mesh = k.commit(null, [_fx_mat, _fx_mat, _fx_mat])


# --- batches -------------------------------------------------------------------------------

## One MultiMesh drawing every instance of a mesh. Instances are collected during a frame and
## written to the GPU in one buffer at the end.
class Batch:
	const STRIDE := 20                 # transform 12, colour 4 (white), custom 4
	var mm := MultiMesh.new()
	var node := MultiMeshInstance3D.new()
	var buf := PackedFloat32Array()
	var n := 0
	var cap := 0
	var shadow := true

	func _init(parent: Node3D, mesh: Mesh, cast := true) -> void:
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true            # Compatibility: without instance colours, COLOR comes out black
		mm.mesh = mesh
		node.multimesh = mm
		shadow = cast
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(node)

	func begin() -> void:
		n = 0

	func add(xf: Transform3D, c: Color) -> void:
		var o := n * STRIDE
		if buf.size() < o + STRIDE:
			buf.resize(maxi(64 * STRIDE, buf.size() * 2))
		var b := xf.basis
		buf[o] = b.x.x
		buf[o + 1] = b.y.x
		buf[o + 2] = b.z.x
		buf[o + 3] = xf.origin.x
		buf[o + 4] = b.x.y
		buf[o + 5] = b.y.y
		buf[o + 6] = b.z.y
		buf[o + 7] = xf.origin.y
		buf[o + 8] = b.x.z
		buf[o + 9] = b.y.z
		buf[o + 10] = b.z.z
		buf[o + 11] = xf.origin.z
		buf[o + 12] = 1.0
		buf[o + 13] = 1.0
		buf[o + 14] = 1.0
		buf[o + 15] = 1.0
		buf[o + 16] = c.r
		buf[o + 17] = c.g
		buf[o + 18] = c.b
		buf[o + 19] = c.a
		n += 1

	func finish() -> void:
		if n > cap or cap > 64 and n < cap / 4:
			cap = maxi(16, int(n * 1.5))
			mm.instance_count = cap
		if cap == 0:
			mm.visible_instance_count = 0
			return
		var need := cap * STRIDE
		if buf.size() != need:
			buf.resize(need)
		mm.buffer = buf
		mm.visible_instance_count = n


func _batch(key: String, mesh_fn: Callable, cast := true) -> Batch:
	if _batches.has(key):
		return _batches[key]
	var b := Batch.new(self, mesh_fn.call(), cast)
	_batches[key] = b
	return b


# --- per frame -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	if sim == null:
		return
	_time += delta
	_fog_t -= delta
	if _fog_t <= 0.0:
		_fog_t = 0.25
		_update_fog()
	_place_camera()
	for b in _batches.values():
		b.begin()
	var team_cols := []
	for p in sim.players:
		team_cols.append(Data.TEAM_COLORS[p.color % Data.TEAM_COLORS.size()])
	var seen := {}
	var res_n := 0
	for e in sim.list:
		if not e.alive:
			continue
		seen[e.id] = true
		var st: Dictionary = _last.get(e.id, {})
		if st.is_empty():
			st = {"atk": e.atk_n, "hp": e.hp, "flash": 0.0, "swing": 99.0, "pos": e.pos, "role": e.role, "owner": e.owner, "cat": e.cat, "flying": e.flying, "size": e.size}
			_last[e.id] = st
		if e.atk_n != st.atk:
			st.atk = e.atk_n
			st.swing = 0.0
			_on_attack(e)
		if e.hp < st.hp - 0.5 and not e.is_resource():
			st.flash = 0.15
		st.hp = e.hp
		st.flash = maxf(0.0, st.flash - delta)
		st.swing += delta
		var p: Vector2 = e.prev_pos.lerp(e.pos, alpha) if e.is_unit() else e.pos
		st.pos = p
		if e.is_resource():
			res_n += 1
			if not _visible_cell(MapData.cell_of(e.pos), true):
				continue
			var sc := 0.55 + 0.45 * clampf(float(e.amount) / maxf(e.max_hp, 1.0), 0.0, 1.0)
			var xf := Transform3D(Basis(Vector3.UP, float(e.id) * 1.7).scaled(Vector3.ONE * sc), Vector3(p.x, sim.map.height_at(p), p.y))
			_batch("res:" + e.role, func(): return Models.resource(e.role)).add(xf, Color(1, 1, 1, 0))
			continue
		var race: String = sim.players[e.owner].race if e.owner >= 0 else "dominaria"
		var tc: Color = team_cols[e.owner] if e.owner >= 0 else Color.WHITE
		if e.is_building():
			if e.owner != me and fog_on and not _visible_cell(MapData.cell_of(e.pos), true):
				continue
			var h := sim.map.height_at(e.pos)
			var built := e.built if not e.complete else 1.0
			var sy := 0.12 + 0.88 * built
			var xf := Transform3D(Basis().scaled(Vector3(1, sy, 1)), Vector3(e.pos.x, h, e.pos.y))
			var c := Color(tc.r, tc.g, tc.b, st.flash * 2.0 if e.complete else -0.4)
			var role := e.role
			_batch("b:%s:%s" % [race, role], func(): return Models.building(race, role)).add(xf, c)
			if not e.complete:
				var sz := e.size
				_batch("scaffold:%d" % sz, func(): return Models.scaffold(sz)).add(Transform3D(Basis(), Vector3(e.pos.x, h, e.pos.y)), Color(1, 1, 1, 0))
			elif e.hp < e.max_hp * 0.55:
				_fire(e, h)
			continue
		# units
		if e.owner != me and fog_on and not _visible_cell(MapData.cell_of(p), false):
			continue
		var y := sim.map.height_at(p)
		var yaw := e.facing
		var lean := 0.0
		var off := 0.0
		match e.anim:
			Ent.A_WALK:
				off = absf(sin(_time * 9.0 + e.id)) * 0.09
				lean = 0.06
			Ent.A_WORK:
				off = absf(sin(_time * 6.0 + e.id)) * 0.12
				lean = 0.12 + sin(_time * 6.0 + e.id) * 0.1
		var fwd := 0.0
		if st.swing < 0.35:
			var sw: float = sin(st.swing / 0.35 * PI)
			fwd = sw * (0.35 if not e.flying else 0.2)
			lean += sw * 0.15
		if e.flying:
			y = maxf(y, 0.0) + FLY_HEIGHT + sin(_time * 2.0 + e.id) * 0.25
		var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean)
		if e.elite:
			basis = basis.scaled(Vector3.ONE * 1.08)
		var origin := Vector3(p.x, y + off, p.y) + Basis(Vector3.UP, yaw) * Vector3(0, 0, fwd)
		var role := e.role
		_batch("u:%s:%s" % [race, role], func(): return Models.unit(race, role)).add(Transform3D(basis, origin), Color(tc.r, tc.g, tc.b, st.flash * 2.5))
		if e.flying:
			_batch("shadow", func(): return _shadow_mesh(), false).add(Transform3D(Basis().scaled(Vector3(e.radius * 1.1, 1, e.radius * 1.1)), Vector3(p.x, sim.map.height_at(p) + 0.08, p.y)), Color(0, 0, 0, 0.35))
	# the dead
	for id in _last.keys():
		if not seen.has(id):
			var st: Dictionary = _last[id]
			if st.cat != Ent.RESOURCE and (st.owner == me or not fog_on or _visible_cell(MapData.cell_of(st.pos), st.cat == Ent.BUILDING)):
				_on_death(st)
			_last.erase(id)
	_draw_rings()
	_draw_fx(delta)
	for b in _batches.values():
		b.finish()


func _shadow_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3.ZERO, Vector3(0, 0.01, 0), 1.0, 1.0, Color(1, 1, 1, 1), 14)
	return k.commit(null, [_fx_mat, _fx_mat, _fx_mat])


func _draw_rings() -> void:
	var b := _batch("ring", func(): return _ring_mesh, false)
	for id in selected:
		var e: Ent = sim.ents.get(id)
		if e == null or not e.alive:
			continue
		var st: Dictionary = _last.get(id, {})
		var p: Vector2 = st.get("pos", e.pos)
		var r := e.radius * 1.25 if e.is_unit() else e.size * Data.CELL * 0.62
		var y := sim.map.height_at(p) + 0.12
		if e.flying:
			y += FLY_HEIGHT * 0.0
		var col := Color(0.3, 1.0, 0.4, 0.9) if e.owner == me else (Color(1.0, 0.85, 0.3, 0.9) if e.owner < 0 else (Color(1.0, 0.3, 0.25, 0.9) if me >= 0 and sim.enemies(me, e.owner) else Color(0.9, 0.9, 0.9, 0.9)))
		b.add(Transform3D(Basis().scaled(Vector3(r, 1, r)), Vector3(p.x, y, p.y)), col)
		if e.is_building() and e.has_rally and e.owner == me:
			var rp := e.rally
			b.add(Transform3D(Basis().scaled(Vector3(0.6, 1, 0.6)), Vector3(rp.x, sim.map.height_at(rp) + 0.12, rp.y)), Color(0.4, 0.9, 1.0, 0.9))
	if hover_id != 0 and not selected.has(hover_id):
		var e: Ent = sim.ents.get(hover_id)
		if e and e.alive:
			var st: Dictionary = _last.get(hover_id, {})
			var p: Vector2 = st.get("pos", e.pos)
			var r := e.radius * 1.25 if e.is_unit() else e.size * Data.CELL * 0.62
			b.add(Transform3D(Basis().scaled(Vector3(r, 1, r)), Vector3(p.x, sim.map.height_at(p) + 0.12, p.y)), Color(1, 1, 1, 0.35))
	for m in _markers:
		var r: float = 0.4 + m.t * 1.2
		b.add(Transform3D(Basis().scaled(Vector3(r, 1, r)), Vector3(m.p.x, sim.map.height_at(m.p) + 0.15, m.p.y)), Color(m.col.r, m.col.g, m.col.b, 1.0 - m.t / 0.6))


## Shows where an order went: green for a move, red for an attack.
func mark(p: Vector2, attack := false) -> void:
	_markers.append({"p": p, "t": 0.0, "col": Color(1.0, 0.3, 0.2) if attack else Color(0.3, 1.0, 0.4)})


# --- fog of war ----------------------------------------------------------------------------

func _disc(r: int) -> Array:
	if _discs.has(r):
		return _discs[r]
	var out := []
	for y in range(-r, r + 1):
		for x in range(-r, r + 1):
			if x * x + y * y <= r * r + r:
				out.append(Vector2i(x, y))
	_discs[r] = out
	return out


func _update_fog() -> void:
	if not fog_on:
		return
	var n := sim.map.n
	for i in visible_grid.size():
		if visible_grid[i] == 2:
			visible_grid[i] = 1
	var my_team := sim.team_of(me)
	for e in sim.list:
		if not e.alive or e.owner < 0 or sim.team_of(e.owner) != my_team:
			continue
		var sight: float = 0.0
		if e.is_unit():
			sight = Data.UNITS[e.role].sight
		else:
			sight = Data.BUILDINGS[e.role].get("sight", 6.0) * (1.0 if e.complete else 0.5)
		var c := MapData.cell_of(e.pos)
		var r := int(ceil(sight / Data.CELL))
		for o in _disc(r):
			var q: Vector2i = c + o
			if q.x >= 0 and q.y >= 0 and q.x < n and q.y < n:
				visible_grid[q.y * n + q.x] = 2
	for y in n:
		for x in n:
			var v := visible_grid[y * n + x]
			_fog_img.set_pixel(x, y, Color(0.0 if v == 0 else (0.5 if v == 1 else 1.0), 0, 0))
	_fog_tex.update(_fog_img)


## Whether the local player can see a cell now (or, with `explored`, has ever seen it).
func _visible_cell(c: Vector2i, explored: bool) -> bool:
	if not fog_on:
		return true
	if not sim.map.inside(c):
		return false
	var v := visible_grid[sim.map.idx(c)]
	return v == 2 or (explored and v >= 1)


func can_see(e: Ent) -> bool:
	if e.owner == me or not fog_on:
		return true
	return _visible_cell(MapData.cell_of(e.pos), not e.is_unit())


# --- effects -------------------------------------------------------------------------------

const SHOT := {
	"arrow": {"speed": 26.0, "arc": 0.18, "col": Color(0.85, 0.75, 0.55), "size": Vector3(0.05, 0.05, 0.7)},
	"bolt": {"speed": 30.0, "arc": 0.1, "col": Color(0.6, 0.5, 0.4), "size": Vector3(0.07, 0.07, 0.5)},
	"oil": {"speed": 16.0, "arc": 0.25, "col": Color(0.08, 0.1, 0.08), "size": Vector3(0.22, 0.22, 0.3)},
	"bullet": {"speed": 45.0, "arc": 0.0, "col": Color(0.5, 1.6, 1.8), "size": Vector3(0.06, 0.06, 0.9)},
	"magic": {"speed": 20.0, "arc": 0.05, "col": Color(0.6, 0.9, 2.0), "size": Vector3(0.25, 0.25, 0.25)},
	"spark": {"speed": 22.0, "arc": 0.05, "col": Color(0.7, 0.85, 2.0), "size": Vector3(0.35, 0.35, 0.35)},
	"stone": {"speed": 16.0, "arc": 0.35, "col": Color(0.45, 0.4, 0.38), "size": Vector3(0.45, 0.45, 0.45)},
	"aether": {"speed": 24.0, "arc": 0.12, "col": Color(0.4, 1.6, 2.0), "size": Vector3(0.4, 0.4, 0.4)},
	"heal": {"speed": 14.0, "arc": 0.05, "col": Color(0.6, 2.0, 0.8), "size": Vector3(0.2, 0.2, 0.2)},
}


func _shot_kind(e: Ent) -> String:
	var race: String = sim.players[e.owner].race if e.owner >= 0 else ""
	match e.role:
		"archer":
			return {"phyrexia": "oil", "dominaria": "arrow", "ravnica": "bolt", "avishkar": "bullet"}[race]
		"flyer":
			return {"phyrexia": "oil", "dominaria": "arrow", "ravnica": "bolt", "avishkar": "bullet"}[race]
		"caster":
			return "magic"
		"siege":
			return {"phyrexia": "oil", "ravnica": "spark", "avishkar": "aether"}.get(race, "stone")
		"tower", "hall":
			return {"phyrexia": "oil", "avishkar": "bullet", "ravnica": "bolt"}.get(race, "arrow")
	return ""


func _on_attack(e: Ent) -> void:
	var t: Ent = sim.ents.get(e.atk_target)
	var kind := _shot_kind(e)
	if t and t.owner == e.owner:
		kind = "heal"
	var near := _near_camera(e.pos)
	if kind == "":
		# melee: a spark and a clang at the target
		if t:
			_puffs.append({"p": Vector3(t.pos.x, sim.map.height_at(t.pos) + 1.0 + (FLY_HEIGHT if t.flying else 0.0), t.pos.y), "t": 0.0, "life": 0.25, "size": 0.35, "col": Color(1.6, 1.4, 0.9), "rise": 0.0})
		if near:
			Game.play("chop" if e.role == "worker" else "sword", -12.0)
		return
	if t == null:
		return
	var from := Vector3(e.pos.x, sim.map.height_at(e.pos) + (FLY_HEIGHT + 0.8 if e.flying else (4.5 if e.is_building() else 1.3)), e.pos.y)
	var to := Vector3(t.pos.x, sim.map.height_at(t.pos) + (FLY_HEIGHT + 1.0 if t.flying else 1.0), t.pos.y)
	if t.is_building():
		to.y = sim.map.height_at(t.pos) + 1.5
	var d := from.distance_to(to)
	_projectiles.append({"from": from, "to": to, "t": 0.0, "dur": maxf(0.08, d / SHOT[kind].speed), "kind": kind, "splash": e.role == "siege"})
	if near:
		match kind:
			"arrow", "bolt":
				Game.play("bow", -14.0)
			"magic", "spark", "aether", "bullet", "heal":
				Game.play("zap", -16.0)
			"oil":
				Game.play("bow", -16.0, 0.6)
			"stone":
				Game.play("boom", -14.0, 1.4)


func _near_camera(p: Vector2) -> bool:
	return p.distance_to(cam_target) < zoom * 0.9


func _on_death(st: Dictionary) -> void:
	var p: Vector2 = st.pos
	var y := sim.map.height_at(p)
	if st.cat == Ent.BUILDING:
		var s: float = st.size * Data.CELL
		for i in 10:
			var o := Vector3(randf_range(-0.5, 0.5) * s, 0, randf_range(-0.5, 0.5) * s)
			_puffs.append({"p": Vector3(p.x, y + 0.5, p.y) + o, "t": 0.0, "life": randf_range(1.0, 2.0), "size": randf_range(1.2, 2.4), "col": Color(0.45, 0.4, 0.36), "rise": 1.5})
		if _near_camera(p):
			Game.play("collapse", -6.0)
	else:
		var fy := FLY_HEIGHT if st.flying else 0.0
		_puffs.append({"p": Vector3(p.x, y + 0.6 + fy, p.y), "t": 0.0, "life": 0.7, "size": 0.9, "col": Color(0.55, 0.12, 0.1) if st.role != "worker" else Color(0.5, 0.45, 0.4), "rise": 0.6})
		_puffs.append({"p": Vector3(p.x, y + 0.3 + fy, p.y), "t": 0.0, "life": 0.9, "size": 1.1, "col": Color(0.5, 0.46, 0.4), "rise": 0.8})
		if _near_camera(p):
			Game.play("death", -12.0)


func _fire(e: Ent, h: float) -> void:
	var s := e.size * Data.CELL
	var n := 1 if e.hp > e.max_hp * 0.3 else 3
	for i in n:
		var o := Vector3(sin(e.id * 3.1 + i * 2.0) * s * 0.3, 0, cos(e.id * 1.7 + i * 2.3) * s * 0.3)
		var fl := 0.8 + sin(_time * 13.0 + i * 1.3 + e.id) * 0.2
		_batch("flame", func(): return _flame_mesh(), false).add(Transform3D(Basis().scaled(Vector3(fl, fl * 1.3, fl)), Vector3(e.pos.x, h + 1.4 + s * 0.15, e.pos.y) + o), Color(1.8, 0.8, 0.2, 0.85))


func _flame_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	k.cyl(Vector3.ZERO, Vector3(0, 1.4, 0), 0.5, 0.0, Color(1, 0.7, 0.3), 7)
	k.cyl(Vector3(0, 0, 0), Vector3(0, 0.9, 0), 0.32, 0.0, Color(1, 1, 0.6), 6)
	return k.commit(null, [_fx_mat, _fx_mat, _fx_mat])


func _ball_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	k.sphere(Vector3.ZERO, Vector3.ONE * 0.5, Color.WHITE, 8, 5)
	return k.commit(null, [_fx_mat, _fx_mat, _fx_mat])


func _stick_mesh() -> ArrayMesh:
	var k := MeshKit.new()
	k.box(Vector3.ZERO, Vector3.ONE, Color.WHITE)
	return k.commit(null, [_fx_mat, _fx_mat, _fx_mat])


func _draw_fx(delta: float) -> void:
	var balls := _batch("fx_ball", func(): return _ball_mesh(), false)
	var sticks := _batch("fx_stick", func(): return _stick_mesh(), false)
	var keep := []
	for pr in _projectiles:
		pr.t += delta
		var f: float = pr.t / pr.dur
		if f >= 1.0:
			if pr.splash:
				_puffs.append({"p": pr.to, "t": 0.0, "life": 0.6, "size": 1.8, "col": SHOT[pr.kind].col * 0.8, "rise": 0.5})
				if _near_camera(Vector2(pr.to.x, pr.to.z)):
					Game.play("boom", -10.0)
			elif pr.kind == "magic" or pr.kind == "heal":
				_puffs.append({"p": pr.to, "t": 0.0, "life": 0.3, "size": 0.6, "col": SHOT[pr.kind].col, "rise": 0.0})
			continue
		keep.append(pr)
		var sh: Dictionary = SHOT[pr.kind]
		var pos: Vector3 = pr.from.lerp(pr.to, f)
		var d: float = pr.from.distance_to(pr.to)
		pos.y += sin(f * PI) * d * sh.arc
		var dir: Vector3 = (pr.to - pr.from).normalized()
		dir.y += cos(f * PI) * sh.arc * 2.0
		var basis := Basis.looking_at(dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD, Vector3.UP).scaled(sh.size)
		var c: Color = sh.col
		if sh.size.z > sh.size.x * 1.5:
			sticks.add(Transform3D(basis, pos), Color(c.r, c.g, c.b, 1.0))
		else:
			balls.add(Transform3D(basis, pos), Color(c.r, c.g, c.b, 1.0))
	_projectiles = keep
	var keep2 := []
	for pf in _puffs:
		pf.t += delta
		if pf.t >= pf.life:
			continue
		keep2.append(pf)
		var f: float = pf.t / pf.life
		var s: float = pf.size * (0.4 + f * 0.9)
		var pos: Vector3 = pf.p + Vector3(0, pf.rise * f, 0)
		balls.add(Transform3D(Basis().scaled(Vector3.ONE * s), pos), Color(pf.col.r, pf.col.g, pf.col.b, (1.0 - f) * 0.8))
	_puffs = keep2
	var keep3 := []
	for m in _markers:
		m.t += delta
		if m.t < 0.6:
			keep3.append(m)
	_markers = keep3


# --- camera and picking ---------------------------------------------------------------------

func _place_camera() -> void:
	var size := sim.map.size_m()
	cam_target = cam_target.clamp(Vector2(4, 8), Vector2(size - 4, size + 4))
	var ground := maxf(sim.map.height_at(cam_target.clamp(Vector2.ZERO, Vector2.ONE * (size - 0.1))), 0.0)
	var target := Vector3(cam_target.x, ground, cam_target.y)
	cam.position = target + Vector3(0, sin(PITCH), cos(PITCH)) * zoom
	cam.look_at(target, Vector3.UP)
	_sun.directional_shadow_max_distance = zoom * 2.2 + 20.0


func pan(v: Vector2) -> void:
	cam_target += v * zoom * 0.02


func zoom_by(f: float) -> void:
	zoom = clampf(zoom * f, ZOOM_MIN, ZOOM_MAX)


func look_at_point(p: Vector2) -> void:
	cam_target = p + Vector2(0, 2.0)


## The ground point under a screen position (metres on the map plane).
func screen_to_ground(sp: Vector2) -> Vector2:
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	var y := 0.0
	var hit := Vector3.ZERO
	for i in 3:
		if absf(d.y) < 0.001:
			break
		var t := (y - o.y) / d.y
		hit = o + d * t
		y = maxf(sim.map.height_at(Vector2(hit.x, hit.z).clamp(Vector2.ZERO, Vector2.ONE * (sim.map.size_m() - 0.1))), -0.35)
	return Vector2(hit.x, hit.z)


func screen_pos(e: Ent) -> Vector2:
	var st: Dictionary = _last.get(e.id, {})
	var p: Vector2 = st.get("pos", e.pos)
	var y := sim.map.height_at(p) + (FLY_HEIGHT if e.flying else 0.0)
	return cam.unproject_position(Vector3(p.x, y + (1.0 if e.is_unit() else 1.5), p.y))


func on_screen(e: Ent) -> bool:
	var st: Dictionary = _last.get(e.id, {})
	var p: Vector2 = st.get("pos", e.pos)
	return not cam.is_position_behind(Vector3(p.x, 0, p.y))


## The entity under a screen position, if any (units first, then buildings, then deposits).
func ent_at(sp: Vector2) -> Ent:
	var best: Ent = null
	var best_d := INF
	var px_per_m := get_viewport().get_visible_rect().size.y / (2.0 * zoom * tan(deg_to_rad(cam.fov * 0.5)))
	for e in sim.list:
		if not e.alive or not can_see(e):
			continue
		var s := screen_pos(e)
		var r := (e.radius * 1.4 + 0.4) * px_per_m if e.is_unit() else e.size * Data.CELL * 0.55 * px_per_m
		var d := s.distance_to(sp)
		if e.is_unit():
			d -= 6.0
		if d < r and d < best_d:
			best_d = d
			best = e
	return best


func ents_in_rect(r: Rect2) -> Array:
	var out := []
	for e in sim.list:
		if e.alive and can_see(e) and r.has_point(screen_pos(e)):
			out.append(e)
	return out


## The building placement preview: the building's own model, tinted green or red.
func show_ghost(race: String, role: String, cell: Vector2i, ok: bool) -> void:
	ghost.visible = true
	ghost.mesh = Models.building(race, role)
	var s: int = Data.BUILDINGS[role].size
	var centre := (Vector2(cell) + Vector2(s, s) * 0.5) * Data.CELL
	ghost.position = Vector3(centre.x, sim.map.height_at(centre) + 0.02, centre.y)
	ghost.material_override = _ghost_material(ok)


var _ghost_ok: StandardMaterial3D
var _ghost_bad: StandardMaterial3D


func _ghost_material(ok: bool) -> StandardMaterial3D:
	if _ghost_ok == null:
		for i in 2:
			var m := StandardMaterial3D.new()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.3, 1.0, 0.4, 0.45) if i == 0 else Color(1.0, 0.25, 0.2, 0.45)
			if i == 0:
				_ghost_ok = m
			else:
				_ghost_bad = m
	return _ghost_ok if ok else _ghost_bad


func hide_ghost() -> void:
	ghost.visible = false
