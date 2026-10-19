extends Node3D
## Model check (`-- --lineup [--dir=PATH]`): every race's troops in a row and then its buildings,
## close up, in four poses (standing, mid-stride, winding up, striking) and from a low angle.
## Saves PNGs (default /tmp/pw-lineup) and quits. With `--tris` it only prints each model's
## triangle count.

var dir := "/tmp/pw-lineup"
var _units: Array = []                 # [MultiMesh, is_flyer]
var _cam: Camera3D


func _ready() -> void:
	if "--tris" in OS.get_cmdline_user_args():
		_count()
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(dir)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.5, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.72, 0.8)
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_cam = Camera3D.new()
	_cam.environment = env
	_cam.fov = 40.0
	add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.36, 0.42, 0.26)
	ground.material_override = gm
	add_child(ground)
	_run()


func _place(mesh: Mesh, at: Vector3, slot: int, yaw: float) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D(Basis(Vector3.UP, yaw), at))
	mm.set_instance_color(0, Color(1, 1, 1, 0))
	mm.set_instance_custom_data(0, Color(slot, 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)
	return mm


func _clear() -> void:
	for c in get_children():
		if c is MultiMeshInstance3D:
			c.queue_free()
	_units.clear()


func _pose(ph: float, walk: float, sw: float) -> void:
	for u in _units:
		var mm: MultiMesh = u[0]
		var c := mm.get_instance_custom_data(0)
		mm.set_instance_custom_data(0, Color(c.r, 0, ph, sw))
		mm.set_instance_color(0, Color(1, 1, 1, 1.0 if u[1] else walk))


func _shot(name: String) -> void:
	for i in 3:
		await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("LINEUP ", name)


func _run() -> void:
	await get_tree().process_frame
	for ri in Data.RACE_ORDER.size():
		var race: String = Data.RACE_ORDER[ri]
		_clear()
		var x := 0.0
		for role in Data.UNIT_ORDER:
			if not Data.has_unit(race, role):
				continue
			var mesh := Models.unit(race, role)
			var w := maxf(mesh.get_aabb().size.x, 1.2)
			x += w * 0.5 + 0.5
			var y := 1.2 if role == "flyer" else 0.0
			_units.append([_place(mesh, Vector3(x, y, 0), ri, 0.5), role == "flyer"])
			x += w * 0.5 + 0.5
		_cam.position = Vector3(x * 0.5, 3.2, x * 0.62)
		_cam.look_at(Vector3(x * 0.5, 1.2, 0))
		_cam.fov = 45.0
		_pose(0.0, 0.0, 0.0)
		await _shot("%s_units_idle" % race)
		_pose(1.57, 1.0, 0.0)
		await _shot("%s_units_walk" % race)
		_pose(0.0, 0.0, 0.38)
		await _shot("%s_units_windup" % race)
		_pose(0.0, 0.0, 0.58)
		await _shot("%s_units_strike" % race)
		_cam.position = Vector3(x * 0.5, 1.3, x * 0.55)
		_cam.look_at(Vector3(x * 0.5, 1.4, 0))
		_pose(0.8, 1.0, 0.0)
		await _shot("%s_units_low" % race)
		# buildings
		_clear()
		x = 0.0
		for role in Data.BUILD_ORDER:
			if not Data.has_building(race, role):
				continue
			var mesh := Models.building(race, role)
			var w: float = Data.BUILDINGS[role].size * Data.CELL
			x += w * 0.5 + 1.0
			_units.append([_place(mesh, Vector3(x, 0, 0), ri, 0.6), false])
			x += w * 0.5 + 1.0
		_cam.position = Vector3(x * 0.5, 16.0, 26.0)
		_cam.look_at(Vector3(x * 0.5, 2.0, 0))
		_cam.fov = 55.0
		_pose(1.0, 0.0, 0.0)
		await _shot("%s_buildings" % race)
	print("LINEUP done")
	get_tree().quit()


func _count() -> void:
	var total := 0
	for race in Data.RACE_ORDER:
		var line: String = race
		for role in Data.UNIT_ORDER:
			if Data.has_unit(race, role):
				var n := _tris(Models.unit(race, role))
				total += n
				line += " %s=%d" % [role, n]
		for role in Data.BUILD_ORDER:
			if Data.has_building(race, role):
				line += " %s=%d" % [role, _tris(Models.building(race, role))]
		print("TRIS ", line)
	print("TRIS units total ", total)
	get_tree().quit()


func _tris(m: ArrayMesh) -> int:
	var n := 0
	for i in m.get_surface_count():
		n += m.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size() / 3
	return n
