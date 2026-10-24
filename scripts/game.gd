extends Node
## Autoload `Game`: settings (graphics quality, sound, music, voices, player name), fonts, the
## shared materials, the generated sound effects, the music player and the unit voices.

signal quality_changed

enum { LOW, MEDIUM, HIGH }
const QUALITY_NAMES := ["Low", "Medium", "High"]
const SETTINGS_PATH := "user://settings.cfg"

const TITLE := "Planar Wars"
const TAGLINE := "Four worlds. One war for the Multiverse."

const GOLD := Color(0.95, 0.78, 0.42)
const PALE := Color(0.95, 0.92, 0.84)
const AETHER := Color(0.45, 0.85, 1.0)
const BAD := Color(1.0, 0.42, 0.36)

var quality := MEDIUM
var quality_chosen := false
var muted := false
var music_on := true
var voices_on := true
var web := false
var testing := false
var font_title: FontVariation
var font_title_bold: FontVariation
var font_body: Font
var font_bold: Font
var mat_solid: StandardMaterial3D
var mat_glow: ShaderMaterial
var mat_gloss: ShaderMaterial
var mat_unit: ShaderMaterial          # units and buildings: vertex colour with the team colour from the instance
var mat_unit_gloss: ShaderMaterial
var mat_unit_glow: ShaderMaterial     # glowing parts of units and buildings, moved with their rig
var sounds := {}
var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _last_played := {}
var _music: AudioStreamPlayer
var _music_bus := 0
var _playlist: Array = []
var _playlist_at := 0
var _track_end := 0                     # Time.get_ticks_msec() when the current track ends
var _music_tween: Tween

var _voice: AudioStreamPlayer
var _voice_bus := 0
var _voice_cache := {}
var _voice_turn := {}                   # "race_role_event" -> the next of its lines
var _voice_at := 0

const MUSIC_DB := -10.0                  # the Music bus level (default_bus_layout.tres has the bus)
const MUSIC_FADE := 1.2


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	web = OS.has_feature("web") or "--web" in args
	testing = "--autotest" in args or "--simtest" in args or "--bench" in args or "--lineup" in args
	quality = MEDIUM if web else HIGH
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		if cfg.has_section_key("video", "quality"):
			quality = clampi(int(cfg.get_value("video", "quality")), LOW, HIGH)
			quality_chosen = true
		muted = bool(cfg.get_value("audio", "muted", false))
		music_on = bool(cfg.get_value("audio", "music", true))
		voices_on = bool(cfg.get_value("audio", "voices", true))
	for a in args:
		if a.begins_with("--quality="):
			quality = clampi(int(a.get_slice("=", 1)), LOW, HIGH)
			quality_chosen = true
	font_title = _font("res://fonts/Cinzel.ttf", 700)
	font_title_bold = _font("res://fonts/Cinzel.ttf", 900)
	font_body = load("res://fonts/AlegreyaSans-Regular.ttf")
	font_bold = load("res://fonts/AlegreyaSans-Bold.ttf")
	mat_solid = StandardMaterial3D.new()
	mat_solid.vertex_color_use_as_albedo = true
	mat_solid.roughness = 0.75
	mat_solid.metallic_specular = 0.4
	mat_glow = ShaderMaterial.new()
	mat_glow.shader = load("res://shaders/glow.gdshader")
	mat_gloss = ShaderMaterial.new()
	mat_gloss.shader = load("res://shaders/gloss.gdshader")
	mat_unit = ShaderMaterial.new()
	mat_unit.shader = load("res://shaders/unit.gdshader")
	mat_unit_gloss = ShaderMaterial.new()
	mat_unit_gloss.shader = mat_unit.shader
	mat_unit_gloss.set_shader_parameter("gloss", 1.0)
	mat_unit_glow = ShaderMaterial.new()
	mat_unit_glow.shader = load("res://shaders/unit_glow.gdshader")
	# colour slots for the marker parts: the players, the races' trims (portraits), white
	var slots := PackedVector3Array()
	for c in Data.TEAM_COLORS:
		slots.append(Vector3(c.r, c.g, c.b))
	for r in Data.RACE_ORDER:
		var c: Color = Data.RACES[r].colors.trim
		slots.append(Vector3(c.r, c.g, c.b))
	slots.append(Vector3.ONE)
	for m in [mat_unit, mat_unit_gloss, mat_unit_glow]:
		m.set_shader_parameter("slot_cols", slots)
	_setup_input()
	for i in 14:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_sounds()
	AudioServer.set_bus_mute(0, muted)
	# the browser plays streams as Web Audio samples: it follows bus volumes but not volume_db
	# changes or buses made in code, so fades go through the bus and the bus is in the layout file
	_music_bus = AudioServer.get_bus_index("Music")
	AudioServer.set_bus_mute(_music_bus, not music_on)
	AudioServer.set_bus_volume_db(_music_bus, MUSIC_DB)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_voice_bus = AudioServer.get_bus_index("Voice")
	AudioServer.set_bus_mute(_voice_bus, not voices_on)
	_voice = AudioStreamPlayer.new()
	_voice.bus = "Voice"
	add_child(_voice)


func _setup_input() -> void:
	var keys := {
		"pause": [KEY_ESCAPE, KEY_F10], "quality": [KEY_L], "mute": [KEY_M],
		"pan_left": [KEY_LEFT], "pan_right": [KEY_RIGHT], "pan_up": [KEY_UP], "pan_down": [KEY_DOWN]}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)


func _font(path: String, weight: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = load(path)
	f.variation_opentype = {"wght": weight}
	return f


## Points the glossy reflections at a map's sky.
func set_sky(d: Dictionary) -> void:
	for m in [mat_gloss, mat_unit_gloss]:
		m.set_shader_parameter("sky_top", d.sky_top)
		m.set_shader_parameter("sky_horizon", d.sky_horizon)
		m.set_shader_parameter("sky_ground", d.ground)


func set_quality(q: int, save := true) -> void:
	quality = clampi(q, LOW, HIGH)
	if save:
		quality_chosen = true
		_save()
	quality_changed.emit()


func cycle_quality() -> void:
	set_quality((quality + 1) % 3)


func toggle_mute() -> void:
	muted = not muted
	AudioServer.set_bus_mute(0, muted)
	_save()


func toggle_music() -> void:
	music_on = not music_on
	AudioServer.set_bus_mute(_music_bus, not music_on)
	_save()


func toggle_voices() -> void:
	voices_on = not voices_on
	AudioServer.set_bus_mute(_voice_bus, not voices_on)
	_save()


func _save() -> void:
	if testing:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	if quality_chosen:
		cfg.set_value("video", "quality", quality)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "music", music_on)
	cfg.set_value("audio", "voices", voices_on)
	cfg.save(SETTINGS_PATH)


# --- sound ---------------------------------------------------------------------------

func play(name: String, vol_db := 0.0, pitch := 1.0) -> void:
	if not sounds.has(name):
		return
	# the same sound at most every 60 ms, so a volley does not stack into one loud click
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(name, -1000)) < 60:
		return
	_last_played[name] = now
	var p := _players[_next_player]
	_next_player = (_next_player + 1) % _players.size()
	p.stream = sounds[name]
	p.volume_db = vol_db
	p.pitch_scale = pitch * randf_range(0.94, 1.06)
	p.play()


# --- music -----------------------------------------------------------------------------
# Tracks are music/<name>.ogg, made by tools/gen_music.py: three menu themes ("title", "title2",
# "title3") and three per race ("<race>", "<race>2", "<race>3").

## Plays the tracks one after another, round and round (one track loops on its own).
## Fades out whatever is playing first; does nothing if this playlist already plays.
func play_music(tracks: Array) -> void:
	if tracks == _playlist or "--simtest" in OS.get_cmdline_user_args():
		return
	_playlist = tracks
	_playlist_at = 0
	if _music.playing:
		_fade(-50.0, MUSIC_FADE * 0.6).tween_callback(_start_track)
	else:
		_start_track()


const MENU_MUSIC := ["title", "title2", "title3"]


## A match's music: the player's race's three themes first, then the other races' and the menu themes.
func match_playlist(race: String) -> Array:
	var list := []
	var order: Array = Data.RACE_ORDER.duplicate()
	if race in order:
		order.erase(race)
		order.push_front(race)
	for r in order:
		for n in ["", "2", "3"]:
			list.append(r + n)
	return list + MENU_MUSIC


## The track playing now ("" if none).
func music_now() -> String:
	return str(_playlist[_playlist_at]) if not _playlist.is_empty() and _music.playing else ""


func _start_track() -> void:
	var stream: AudioStreamOggVorbis = load("res://music/%s.ogg" % _playlist[_playlist_at])
	stream.loop = _playlist.size() == 1
	_track_end = Time.get_ticks_msec() + int(stream.get_length() * 1000.0)
	AudioServer.set_bus_volume_db(_music_bus, -50.0)
	_music.stream = stream
	_music.play()
	_fade(MUSIC_DB, MUSIC_FADE)


func _fade(db: float, time: float) -> Tween:
	if _music_tween:
		_music_tween.kill()
	_music_tween = create_tween()
	_music_tween.tween_method(func(v: float): AudioServer.set_bus_volume_db(_music_bus, v),
			AudioServer.get_bus_volume_db(_music_bus), db, time)
	return _music_tween


# the next track by the clock: the browser's sample playback does not always report the end
func _process(_delta: float) -> void:
	if _playlist.size() > 1 and Time.get_ticks_msec() > _track_end:
		_playlist_at = (_playlist_at + 1) % _playlist.size()
		_start_track()


# --- voices ----------------------------------------------------------------------------
# Clips are voices/<race>_<role>_<event><n>.ogg, made by tools/gen_voices.py.

## A troop answers: event is "select", "move", "attack" (three lines each, taken in turn) or
## "ready". A new order cuts in once the last line has had a moment; "ready" waits for quiet.
func say(race: String, role: String, event: String) -> void:
	if not voices_on:
		return
	var now := Time.get_ticks_msec()
	if _voice.playing and (event == "ready" or now - _voice_at < 400):
		return
	var key := "%s_%s_%s" % [race, role, event]
	var count := 1 if event == "ready" else 3
	var i: int = _voice_turn.get(key, randi() % count)
	_voice_turn[key] = (i + 1) % count
	var path := "res://voices/%s%d.ogg" % [key, i]
	if not _voice_cache.has(path):
		if not ResourceLoader.exists(path):
			return
		_voice_cache[path] = load(path)
	_voice.stream = _voice_cache[path]
	_voice.play()
	_voice_at = now


## The clip playing now ("" if none), for the tests.
func voice_now() -> String:
	return _voice.stream.resource_path.get_file() if _voice.playing and _voice.stream else ""


## The voice that answers for a group: the troop kind most of them are.
func lead_role(ents: Array) -> String:
	var count := {}
	var best := ""
	for e in ents:
		if e.is_unit():
			count[e.role] = int(count.get(e.role, 0)) + 1
			if best == "" or count[e.role] > count[best]:
				best = e.role
	return best


func make_wav(dur: float, gen: Callable, rate := 22050) -> AudioStreamWAV:
	var n := int(dur * rate)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var p := float(i) / n
		var env := pow(1.0 - p, 1.6) * minf(1.0, i / 60.0)
		var v: float = gen.call(float(i) / rate, p) * env
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	return s


func _noise(cut: float) -> Callable:
	var st := [0.0]
	return func(_t: float, _p: float) -> float:
		st[0] += (randf() * 2.0 - 1.0 - st[0]) * cut
		return st[0] / sqrt(cut) * 0.5


func _build_sounds() -> void:
	if "--simtest" in OS.get_cmdline_user_args():
		return
	var n1 := _noise(0.5)
	sounds["sword"] = make_wav(0.18, func(t, p): return n1.call(t, p) * 0.5 + sin(TAU * (2600.0 - 1200.0 * p) * t) * 0.18)
	var n2 := _noise(0.7)
	sounds["bow"] = make_wav(0.16, func(t, p): return n2.call(t, p) * 0.25 + sin(TAU * (380.0 - 200.0 * p) * t) * 0.3)
	var n3 := _noise(0.9)
	sounds["zap"] = make_wav(0.3, func(t, p): return (n3.call(t, p) * 0.4 + signf(sin(TAU * 140.0 * t)) * 0.1) * (0.6 + 0.4 * sin(TAU * 31.0 * t)))
	var n4 := _noise(0.04)
	sounds["boom"] = make_wav(0.6, func(t, p): return n4.call(t, p) * 1.6 + sin(TAU * (80.0 - 40.0 * p) * t) * 0.5)
	var n5 := _noise(0.25)
	sounds["chop"] = make_wav(0.12, func(t, p): return n5.call(t, p) * 0.6 * (1.0 if fposmod(t * 50.0, 1.0) < 0.5 else 0.3))
	sounds["chime"] = make_wav(0.6, func(t, _p): return (sin(TAU * 880.0 * t) + sin(TAU * 1318.5 * t) * 0.6 + sin(TAU * 1760.0 * t) * 0.3) * 0.16)
	sounds["ready"] = make_wav(0.35, func(t, p): return sin(TAU * (523.3 if p < 0.5 else 784.0) * t) * 0.22)
	sounds["upgrade"] = make_wav(0.7, func(t, p): return sin(TAU * (523.3 if p < 0.33 else (659.3 if p < 0.66 else 784.0)) * t) * 0.25)
	sounds["click"] = make_wav(0.05, func(t, _p): return sin(TAU * 1200.0 * t) * 0.25)
	sounds["ack"] = make_wav(0.09, func(t, p): return sin(TAU * (700.0 + 300.0 * p) * t) * 0.18)
	var n6 := _noise(0.5)
	sounds["build"] = make_wav(0.4, func(t, p): return n6.call(t, p) * (1.0 if fposmod(t * 9.0, 1.0) < 0.25 else 0.1) * 0.8 + sin(TAU * 300.0 * t) * 0.1)
	var n7 := _noise(0.08)
	sounds["death"] = make_wav(0.35, func(t, p): return n7.call(t, p) * 0.9 + sin(TAU * (160.0 - 80.0 * p) * t) * 0.3)
	var n8 := _noise(0.02)
	sounds["collapse"] = make_wav(1.4, func(t, p): return n8.call(t, p) * 1.8 + sin(TAU * (50.0 + 90.0 * (1.0 - p)) * t) * 0.35)
	sounds["horn"] = make_wav(1.4, func(t, p): return (sin(TAU * 110.0 * t) * 0.5 + sin(TAU * 165.0 * t) * 0.3 + sin(TAU * 220.0 * t) * 0.15) * minf(1.0, p * 6.0) * 0.8)
	sounds["error"] = make_wav(0.25, func(t, p): return signf(sin(TAU * (220.0 if p < 0.5 else 165.0) * t)) * 0.12)
	sounds["win"] = make_wav(1.8, func(t, p): return (sin(TAU * [392.0, 523.3, 659.3, 784.0][mini(int(p * 5.0), 3)] * t) * 0.3 + sin(TAU * 196.0 * t) * 0.1))
	sounds["lose"] = make_wav(1.8, func(t, p): return (sin(TAU * [220.0, 207.7, 196.0, 146.8][mini(int(p * 4.0), 3)] * t) * 0.3))
