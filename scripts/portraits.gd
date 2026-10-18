class_name Portraits
extends RefCounted
## Renders a portrait of every race's units and buildings once at start-up (one off-screen
## render of all the models in a grid, then cut into pieces) for the command card, the
## selection panel and the codex. Team-coloured parts show in the race's own trim colour.

const CELL := 128
const COLS := 12

static var tex := {}                   # "race:role" -> ImageTexture
static var done := false


static func get_tex(race: String, role: String) -> Texture2D:
	return tex.get(race + ":" + role)


static func generate(host: Node) -> void:
	if done:
		return
	var items := []
	for race in Data.RACE_ORDER:
		for role in Data.UNIT_ORDER:
			if Data.has_unit(race, role):
				items.append([race, role, Models.unit(race, role), false])
		for role in Data.BUILD_ORDER:
			if Data.has_building(race, role):
				items.append([race, role, Models.building(race, role), true])
	var rows := ceili(float(items.size()) / COLS)
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL * COLS, CELL * rows)
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	host.add_child(vp)
	var root := Node3D.new()
	vp.add_child(root)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.78)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 150, 0)
	key.light_energy = 1.4
	root.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, -30, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	root.add_child(rim)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.environment = env
	root.add_child(cam)
	var spacing := 4.0
	cam.size = spacing * rows
	var w := spacing * COLS
	var h := spacing * rows
	for i in items.size():
		var it: Array = items[i]
		var mesh: ArrayMesh = it[2]
		var aabb := mesh.get_aabb()
		var big := maxf(aabb.size.y, maxf(aabb.size.x, aabb.size.z) * (1.3 if it[3] else 0.95))
		var s := 3.2 / maxf(big, 0.5)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D())
		mm.set_instance_color(0, Color.WHITE)
		mm.set_instance_custom_data(0, Color(Data.RACES[it[0]].colors.trim, 0.0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var node := Node3D.new()
		node.add_child(mi)
		mi.position = -aabb.get_center() * Vector3(1, 0, 1) - Vector3(0, aabb.position.y, 0)
		mi.rotation.y = 0.0
		var col := i % COLS
		var row := i / COLS
		node.scale = Vector3(s, s, s)
		node.rotation = Vector3(deg_to_rad(-18), PI + (0.5 if it[3] else 0.6), 0)
		node.position = Vector3(w * 0.5 - spacing * (col + 0.5), h * 0.5 - spacing * (row + 0.5) - aabb.size.y * s * 0.5 + 0.05, 0)
		root.add_child(node)
	cam.position = Vector3(0, 0, -30)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	for i in items.size():
		var col := i % COLS
		var row := i / COLS
		var piece := img.get_region(Rect2i(col * CELL, row * CELL, CELL, CELL))
		tex[items[i][0] + ":" + items[i][1]] = ImageTexture.create_from_image(piece)
	vp.queue_free()
	done = true
