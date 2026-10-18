extends Node
## Autoload `Net`: online matches. One player hosts a room and runs the whole match (the
## simulation and the AI players); friends join with the room code and play their own side on
## their own computer. Rooms have four slots, each a person, an AI player, open or closed, so a
## match can be people against people, people against AI or any mix. Everything travels over
## Godot's high-level multiplayer:
##   in the browser  WebRTC, peer to peer. The browsers find each other through a signalling
##                   channel (tools/web/planar-net.js: on the shop page a Supabase Realtime
##                   channel per room, elsewhere a BroadcastChannel between tabs).
##   on a computer   ENet; the room code is the host's address (IP).
## Guests send their commands to the host; the host sends everyone a compressed snapshot of the
## match ten times a second (all units, buildings, deposits and the players' resources and
## techs) and passes on the messages each player should see.

signal lobby_changed
signal status_changed
signal match_start(cfg: Dictionary)
signal left(reason: String)

enum { OFF, HOST, CLIENT }
const PORT := 24690
const ICE := {"iceServers": [{"urls": ["stun:stun.l.google.com:19302", "stun:stun.cloudflare.com:3478"]}]}
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const SLOT_KINDS := ["open", "ai", "closed"]
const RES_KINDS := ["gold", "aether"]
const FORWARD := ["notice", "alert", "trained", "built", "researched", "defeated", "over"]

var role := OFF
var code := ""
var my_name := "Commander"
var status := ""
## Four slots: {"kind": "human"/"ai"/"open"/"closed", "peer", "name", "race" ("random" or a race), "team", "level"}
var slots: Array = []
var map := 0
var in_match := false
var game: Match
var test_args: PackedStringArray = []   # automated tests: host=CODE, join=CODE, bot, start=N

var _js: JavaScriptObject
var _peer: MultiplayerPeer
var _conns := {}
var _hello_t := 0.0
var _join_wait := 0.0
var _techs_seen := -1
var _sent_ms := 0
var _pending := PackedByteArray()      # guest: the newest snapshot, applied once per frame


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func(): _fail("Could not reach the host."))
	multiplayer.server_disconnected.connect(func(): _fail("The host left the room."))
	if OS.has_feature("web"):
		_js = JavaScriptBridge.get_interface("PlanarNet")
	var cfg := ConfigFile.new()
	if cfg.load(Game.SETTINGS_PATH) == OK:
		my_name = str(cfg.get_value("net", "name", my_name))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--net="):
			test_args = a.substr(6).split(",")
	if _js and test_args.is_empty():
		var t := str(_js.testArgs())
		if t != "":
			test_args = t.split(",")


func active() -> bool:
	return role != OFF


func is_host() -> bool:
	return role == HOST


func is_client() -> bool:
	return role == CLIENT


func my_id() -> int:
	return multiplayer.get_unique_id() if active() else 1


func invite_code() -> String:
	return str(_js.roomFromUrl()) if _js else ""


func copy_code() -> void:
	if _js:
		_js.copy(code)
	else:
		DisplayServer.clipboard_set(code)


func test_flag(name: String) -> String:
	for a in test_args:
		if a == name:
			return "1"
		if a.begins_with(name + "="):
			return a.get_slice("=", 1)
	return ""


func set_player_name(n: String) -> void:
	n = n.strip_edges().substr(0, 16)
	my_name = n if n != "" else "Commander"
	var cfg := ConfigFile.new()
	cfg.load(Game.SETTINGS_PATH)
	cfg.set_value("net", "name", my_name)
	cfg.save(Game.SETTINGS_PATH)


func _set_status(s: String) -> void:
	status = s
	status_changed.emit()


func my_slot() -> int:
	for i in slots.size():
		if slots[i].kind == "human" and int(slots[i].peer) == my_id():
			return i
	return -1


# --- rooms ------------------------------------------------------------------------------

func host() -> void:
	leave()
	role = HOST
	slots = [
		{"kind": "human", "peer": 1, "name": my_name, "race": "random", "team": 0, "level": 1},
		{"kind": "open", "peer": 0, "name": "", "race": "random", "team": 1, "level": 1},
		{"kind": "ai", "peer": 0, "name": "", "race": "random", "team": 2, "level": 1},
		{"kind": "closed", "peer": 0, "name": "", "race": "random", "team": 3, "level": 1},
	]
	if _js:
		code = ""
		for i in 5:
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		var fixed := test_flag("host")
		if fixed != "" and fixed != "1":
			code = fixed
		var p := WebRTCMultiplayerPeer.new()
		p.create_server()
		_peer = p
		_js.open(code)
	else:
		var p := ENetMultiplayerPeer.new()
		if p.create_server(PORT, Data.MAX_PLAYERS) != OK:
			role = OFF
			_set_status("Could not open a room on port %d." % PORT)
			return
		_peer = p
		code = _local_ip()
	multiplayer.multiplayer_peer = _peer
	_set_status("Room open. Share the code with your friends.")
	lobby_changed.emit()


func join(room: String) -> void:
	leave()
	room = room.strip_edges()
	if room == "":
		_set_status("Type the room code first.")
		return
	role = CLIENT
	slots = []
	if _js:
		code = room.to_upper()
		var p := WebRTCMultiplayerPeer.new()
		p.create_client(randi_range(2, 2147483646))
		_peer = p
		multiplayer.multiplayer_peer = _peer
		_js.open(code)
		_new_conn(1)
		_hello_t = 0.0
		_join_wait = 20.0
	else:
		code = room
		var p := ENetMultiplayerPeer.new()
		if p.create_client(room, PORT) != OK:
			role = OFF
			_set_status("That is not an address.")
			return
		_peer = p
		multiplayer.multiplayer_peer = _peer
		_join_wait = 12.0
	_set_status("Looking for room %s..." % code)


func leave() -> void:
	if _js:
		_js.close()
	for c in _conns.values():
		c.close()
	_conns.clear()
	if _peer:
		_peer.close()
	_peer = null
	multiplayer.multiplayer_peer = null
	role = OFF
	in_match = false
	game = null
	slots = []
	_join_wait = 0.0


func _fail(reason: String) -> void:
	if role == OFF:
		return
	var g := game
	leave()
	_set_status(reason)
	if g and is_instance_valid(g):
		g.local_event({"t": "notice", "p": -1, "text": reason})
	left.emit(reason)


func _local_ip() -> String:
	for a in IP.get_local_addresses():
		if a.begins_with("192.168.") or a.begins_with("10.") or a.begins_with("172."):
			return a
	return "127.0.0.1"


## Host: change what a slot holds ("open", "ai" with a level, "closed"). A person's slot can
## only be opened (which leaves them without a seat).
func set_slot(i: int, kind: String, level := 1) -> void:
	if not is_host() or i <= 0 or i >= slots.size():
		return
	var s: Dictionary = slots[i]
	if s.kind == "human":
		return
	s.kind = kind
	s.level = level
	s.peer = 0
	s.name = ""
	_push_lobby()


func set_map(m: int) -> void:
	map = posmod(m, Data.MAPS.size())
	_push_lobby()


## Pick a race or team for my own slot (host: or for an AI slot).
func pick(i: int, race: String, team: int) -> void:
	if is_host():
		_apply_pick(1, i, race, team)
	elif is_client():
		_req_pick.rpc_id(1, i, race, team)


func _apply_pick(peer: int, i: int, race: String, team: int) -> void:
	if i < 0 or i >= slots.size():
		return
	var s: Dictionary = slots[i]
	var own: bool = s.kind == "human" and int(s.peer) == peer
	if not own and not (peer == 1 and s.kind == "ai"):
		return
	if race == "random" or Data.RACES.has(race):
		s.race = race
	s.team = clampi(team, 0, 3)
	_push_lobby()


func _push_lobby() -> void:
	if not is_host():
		return
	lobby_changed.emit()
	if not multiplayer.get_peers().is_empty():
		_lobby.rpc(slots, map, code)


## True when the room can start: at least two sides.
func can_start() -> bool:
	var teams := {}
	for s in slots:
		if s.kind == "human" or s.kind == "ai":
			teams[int(s.team)] = true
	return teams.size() >= 2


@rpc("any_peer", "call_remote", "reliable")
func _hello(name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if in_match:
		_kick.rpc_id(id, "A match is already running in that room. Try again after it.")
		return
	for s in slots:
		if s.kind == "human" and int(s.peer) == id:
			s.name = name.substr(0, 16)
			_push_lobby()
			return
	for s in slots:
		if s.kind == "open":
			s.kind = "human"
			s.peer = id
			s.name = name.substr(0, 16)
			_push_lobby()
			return
	_kick.rpc_id(id, "That room is full.")


@rpc("authority", "call_remote", "reliable")
func _kick(reason: String) -> void:
	_fail(reason)


@rpc("authority", "call_remote", "reliable")
func _lobby(s: Array, m: int, c: String) -> void:
	slots = s
	map = m
	code = c
	_set_status("In room %s." % c)
	lobby_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _req_pick(i: int, race: String, team: int) -> void:
	_apply_pick(multiplayer.get_remote_sender_id(), i, race, team)


func _on_peer_connected(id: int) -> void:
	if is_client() and id == 1:
		_on_connected()


func _on_connected() -> void:
	if not is_client():
		return
	_join_wait = 0.0
	_set_status("Connected, joining the room...")
	_hello.rpc_id(1, my_name)


func _on_peer_disconnected(id: int) -> void:
	if is_client():
		if id == 1:
			_fail("The host left the room.")
		return
	if not is_host():
		return
	_conns.erase(id)
	for s in slots:
		if s.kind == "human" and int(s.peer) == id:
			s.kind = "open"
			s.peer = 0
	if game and is_instance_valid(game):
		game.peer_left(id)
	_push_lobby()


# --- the match ---------------------------------------------------------------------------

## Host: turns the slots into players (random races rolled, start corners shuffled) and starts
## the match on every computer in the room.
func start_match() -> void:
	if not is_host() or not can_start():
		return
	var players := []
	for s in slots:
		if s.kind != "human" and s.kind != "ai":
			continue
		var race: String = s.race
		if race == "random":
			race = Data.RACE_ORDER[randi() % 4]
		var nm: String = s.name if s.kind == "human" else "AI (%s)" % Data.AI_LEVELS[int(s.level)]
		players.append({"name": nm, "race": race, "team": int(s.team), "ai": -1 if s.kind == "human" else int(s.level),
			"peer": int(s.peer), "color": players.size()})
	var starts := [0, 1, 2, 3]
	starts.shuffle()
	for i in players.size():
		players[i].start = starts[i]
	var cfg := {"map": map, "seed": randi() % 1000000, "players": players, "online": true}
	_start.rpc(cfg)
	_start(cfg)


@rpc("authority", "call_remote", "reliable")
func _start(cfg: Dictionary) -> void:
	in_match = true
	_techs_seen = -1
	var c := cfg.duplicate(true)
	c.me = -1
	for i in c.players.size():
		if int(c.players[i].peer) == my_id() and int(c.players[i].ai) < 0:
			c.me = i
	c.guest = is_client()
	match_start.emit(c)


## Main hands over the match it built for this room.
func attach(m: Match) -> void:
	game = m


## Guest: a command for the host's simulation.
func send_command(cmd: Dictionary) -> void:
	if is_client():
		_cmd.rpc_id(1, cmd)


@rpc("any_peer", "call_remote", "reliable")
func _cmd(cmd: Dictionary) -> void:
	if not is_host() or game == null or not is_instance_valid(game):
		return
	var id := multiplayer.get_remote_sender_id()
	for i in game.sim.players.size():
		var p: Dictionary = game.sim.players[i]
		if int(p.peer) == id and int(p.ai) < 0:
			game.sim.command(i, cmd)
			return


## Host, after every simulation step: a snapshot to everyone.
func host_tick(m: Match, force := false) -> void:
	if not is_host() or multiplayer.get_peers().is_empty():
		return
	# at most ten a second, also when a test runs the host faster
	var now := Time.get_ticks_msec()
	if now - _sent_ms < 90 and not m.sim.over and not force:
		return
	_sent_ms = now
	var raw := pack(m.sim)
	var z := raw.compress(FileAccess.COMPRESSION_DEFLATE)
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, raw.size())
	out.append_array(z)
	_snapshot.rpc(out)


## Host: a simulation event goes on to the guests it concerns.
func forward_event(m: Match, e: Dictionary) -> void:
	if not is_host() or multiplayer.get_peers().is_empty() or str(e.get("t", "")) not in FORWARD:
		return
	var p := int(e.get("p", -1))
	if p >= 0 and p < m.sim.players.size():
		var peer := int(m.sim.players[p].peer)
		if peer > 1 and peer in multiplayer.get_peers() and int(m.sim.players[p].ai) < 0:
			_event.rpc_id(peer, e)
		if str(e.t) != "defeated":
			return
	_event.rpc(e)


@rpc("authority", "call_remote", "reliable")
func _event(e: Dictionary) -> void:
	if game and is_instance_valid(game):
		game.local_event(e)


@rpc("authority", "call_remote", "unreliable_ordered")
func _snapshot(data: PackedByteArray) -> void:
	_pending = data


## Host: the match is over and everyone has seen the results; the room opens again.
func back_to_room() -> void:
	in_match = false
	game = null
	if is_host():
		_push_lobby()


# --- snapshots ---------------------------------------------------------------------------

## The whole match in a few kilobytes: time, players, then every entity.
func pack(sim: Sim) -> PackedByteArray:
	var b := StreamPeerBuffer.new()
	b.put_float(sim.time)
	b.put_u8(1 if sim.over else 0)
	b.put_8(sim.winner_team)
	var pl := []
	for p in sim.players:
		pl.append([p.gold, p.aether, p.supply, p.cap, p.tier, p.techs, p.researching, p.alive, p.stats, p.ai, p.name])
	var pb := var_to_bytes(pl)
	b.put_u32(pb.size())
	b.put_data(pb)
	b.put_u32(sim.list.size())
	for e in sim.list:
		b.put_u32(e.id)
		b.put_u8(e.cat)
		if e.cat == Ent.RESOURCE:
			b.put_u16(e.amount)
			continue
		var order: Array = Data.UNIT_ORDER if e.cat == Ent.UNIT else Data.BUILD_ORDER
		b.put_u8(order.find(e.role))
		b.put_8(e.owner)
		b.put_float(e.pos.x)
		b.put_float(e.pos.y)
		b.put_u16(int(clampf(e.hp, 0, 65535)))
		b.put_u16(int(clampf(e.max_hp, 1, 65535)))
		if e.cat == Ent.UNIT:
			b.put_u8(int(posmod(e.facing, TAU) / TAU * 255.0))
			var f := (1 if e.flying else 0) | (2 if e.elite else 0) | (4 if e.carry > 0 else 0) | (8 if e.carry_type == "aether" else 0) | (e.anim << 4)
			b.put_u8(f)
			b.put_u8(e.atk_n % 256)
			b.put_u32(e.atk_target)
			b.put_u8(e.order)
		else:
			b.put_u8(e.cell.x)
			b.put_u8(e.cell.y)
			b.put_u8(int(e.built * 255.0))
			b.put_u8((1 if e.complete else 0) | (2 if e.has_rally else 0))
			b.put_u8(e.atk_n % 256)
			b.put_u32(e.atk_target)
			b.put_float(e.rally.x)
			b.put_float(e.rally.y)
			b.put_u8(e.queue.size())
			for q in e.queue:
				var tech: bool = q.kind == "tech"
				b.put_u8(1 if tech else 0)
				b.put_u8(Data.TECH_ORDER.find(q.id) if tech else Data.UNIT_ORDER.find(q.id))
				b.put_u8(int(clampf(q.t / maxf(q.total, 0.01), 0, 1) * 255.0))
				b.put_float(q.total)
				b.put_u8(1 if q.reserved else 0)
	return b.data_array


## Guest: makes the mirror Sim match a snapshot (entities that are missing have died).
func apply(sim: Sim, data: PackedByteArray) -> void:
	var b := StreamPeerBuffer.new()
	b.data_array = data
	sim.time = b.get_float()
	sim.over = b.get_u8() == 1
	sim.winner_team = b.get_8()
	var pl = bytes_to_var(b.get_data(b.get_u32())[1])
	var techs := 0
	if pl is Array:
		for i in mini(pl.size(), sim.players.size()):
			var p: Dictionary = sim.players[i]
			var s: Array = pl[i]
			p.gold = s[0]; p.aether = s[1]; p.supply = s[2]; p.cap = s[3]; p.tier = s[4]
			p.techs = s[5]; p.researching = s[6]; p.alive = s[7]; p.stats = s[8]; p.ai = s[9]; p.name = s[10]
			techs += p.techs.size() + p.tier * 100
	if techs != _techs_seen:
		_techs_seen = techs
		sim.invalidate_stats()
	var seen := {}
	var n := b.get_u32()
	for k in n:
		var id := b.get_u32()
		var cat := b.get_u8()
		seen[id] = true
		var e: Ent = sim.ents.get(id)
		if cat == Ent.RESOURCE:
			var amount := b.get_u16()
			if e:
				e.amount = amount
				e.hp = amount
			continue
		var ri := b.get_u8()
		var owner := b.get_8()
		var role: String = (Data.UNIT_ORDER if cat == Ent.UNIT else Data.BUILD_ORDER)[ri]
		var fresh := e == null
		if fresh:
			e = sim.mirror_add(id, cat, role, owner)
		var x := b.get_float()
		var y := b.get_float()
		e.prev_pos = e.pos if not fresh else Vector2(x, y)
		e.pos = Vector2(x, y)
		e.hp = b.get_u16()
		e.max_hp = b.get_u16()
		if cat == Ent.UNIT:
			e.facing = b.get_u8() / 255.0 * TAU
			var f := b.get_u8()
			e.flying = f & 1 != 0
			e.elite = f & 2 != 0
			e.carry = Data.CARRY if f & 4 != 0 else 0
			e.carry_type = "aether" if f & 8 != 0 else "gold"
			e.anim = (f >> 4) & 3
			e.atk_n = b.get_u8()
			e.atk_target = b.get_u32()
			e.order = b.get_u8()
			e.radius = Data.UNITS[role].radius
		else:
			var c := Vector2i(b.get_u8(), b.get_u8())
			e.built = b.get_u8() / 255.0
			var f := b.get_u8()
			e.complete = f & 1 != 0
			e.has_rally = f & 2 != 0
			e.atk_n = b.get_u8()
			e.atk_target = b.get_u32()
			e.rally = Vector2(b.get_float(), b.get_float())
			if fresh:
				e.cell = c
				e.size = int(Data.BUILDINGS[role].size)
				e.pos = e.rect().get_center()
				e.radius = e.size * Data.CELL * 0.5
				e.prev_pos = e.pos
				sim.mirror_occupy(e, true)
			var qn := b.get_u8()
			e.queue = []
			for qi in qn:
				var tech := b.get_u8() == 1
				var qid: String = Data.TECH_ORDER[b.get_u8()] if tech else Data.UNIT_ORDER[b.get_u8()]
				var frac := b.get_u8() / 255.0
				var total := b.get_float()
				e.queue.append({"kind": "tech" if tech else "unit", "id": qid, "t": frac * total, "total": total, "reserved": b.get_u8() == 1})
	for e in sim.list.duplicate():
		if not seen.has(e.id):
			sim.mirror_remove(e)


# --- WebRTC signalling ---------------------------------------------------------------------

func _new_conn(id: int) -> WebRTCPeerConnection:
	var c := WebRTCPeerConnection.new()
	c.initialize(ICE)
	c.session_description_created.connect(func(type: String, sdp: String):
		c.set_local_description(type, sdp)
		_sig({"t": "sdp", "o": id, "type": type, "sdp": sdp}))
	c.ice_candidate_created.connect(func(mid: String, index: int, cand: String):
		_sig({"t": "ice", "o": id, "mid": mid, "i": index, "c": cand}))
	(_peer as WebRTCMultiplayerPeer).add_peer(c, id)
	_conns[id] = c
	return c


func _sig(m: Dictionary) -> void:
	if _js == null:
		return
	m["f"] = multiplayer.get_unique_id()
	_js.send(JSON.stringify(m))


func _room_full() -> bool:
	for s in slots:
		if s.kind == "open":
			return false
	return true


func _on_signal(m: Dictionary) -> void:
	var from := int(m.get("f", 0))
	var to := int(m.get("o", 0))
	if from == 0 or from == multiplayer.get_unique_id():
		return
	if to != 0 and to != multiplayer.get_unique_id():
		return
	match str(m.get("t", "")):
		"hello":
			if not is_host():
				return
			# a repeated hello from someone already connecting or seated
			if _conns.has(from):
				var old: WebRTCPeerConnection = _conns[from]
				if old.get_connection_state() != WebRTCPeerConnection.STATE_FAILED:
					return
				(_peer as WebRTCMultiplayerPeer).remove_peer(from)
				_conns.erase(from)
			if in_match or _room_full():
				_sig({"t": "busy", "o": from, "full": not in_match})
				return
			var c := _new_conn(from)
			c.create_offer()
		"sdp":
			if _conns.has(from):
				_conns[from].set_remote_description(str(m.type), str(m.sdp))
		"ice":
			if _conns.has(from):
				_conns[from].add_ice_candidate(str(m.mid), int(m.i), str(m.c))
		"busy":
			if is_client() and _join_wait > 0.0:
				_fail("That room is full." if m.get("full", false) else "A match is already running in that room. Try again after it.")


func _process(dt: float) -> void:
	if not _pending.is_empty():
		if game and is_instance_valid(game) and _pending.size() > 4:
			var raw := _pending.slice(4).decompress(mini(_pending.decode_u32(0), 1 << 22), FileAccess.COMPRESSION_DEFLATE)
			apply(game.sim, raw)
			game.snap_t = 0.0
		_pending = PackedByteArray()
	if _js and active():
		var raw := str(_js.poll())
		if raw != "[]" and raw != "":
			var arr = JSON.parse_string(raw)
			if arr is Array:
				for s in arr:
					var m = JSON.parse_string(str(s))
					if m is Dictionary:
						_on_signal(m)
	if is_client() and _join_wait > 0.0:
		_join_wait -= dt
		if _js:
			_hello_t -= dt
			if _hello_t <= 0.0 and bool(_js.ready()):
				_hello_t = 1.0
				_sig({"t": "hello", "o": 1})
		if _join_wait <= 0.0:
			var c: WebRTCPeerConnection = _conns.get(1)
			if c and c.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTING:
				_fail("Found the room, but could not connect to the host. One of your networks blocks direct connections.")
			else:
				_fail("No room %s found. Check the code, and that the host is still in the room." % code)
