class_name Sim
extends RefCounted
## The match itself, without any drawing: players, units, buildings and deposits, and the
## rules that move them (paths, gathering, building, training, research, combat, victory).
## Players change it only through `command(player, cmd)`, the same for the local player, the
## AI and guests over the network. It steps at a fixed 10 Hz (`STEP`); View interpolates.
## On a guest's computer a Sim holds the map and the host's snapshots but never steps.

signal event(e: Dictionary)

const STEP := 0.1
const BUCKET := 8.0
const QUEUE_MAX := 6

var map: MapData
var astar := AStarGrid2D.new()
var occ := PackedInt32Array()            # building or deposit id on each cell, 0 = free
var ents := {}                           # id -> Ent
var list: Array[Ent] = []
var next_id := 1
var players: Array[Dictionary] = []
var time := 0.0
var over := false
var winner_team := -1
var mirror := false                      # guest copy: no rules run
var _buckets := {}
var _stats := {}                         # player -> role -> stats
var _check_t := 0.0
var _alert_t := {}


## players: [{"name", "race", "team", "ai" (-1 human, else level), "peer"}]
func setup(map_index: int, seed_value: int, cfg_players: Array) -> void:
	map = MapData.generate(map_index, seed_value)
	var n := map.n
	occ.resize(n * n)
	occ.fill(0)
	astar.region = Rect2i(0, 0, n, n)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in n:
		for x in n:
			if not map.walkable(Vector2i(x, y)):
				astar.set_point_solid(Vector2i(x, y), true)
	players.clear()
	for i in cfg_players.size():
		var c: Dictionary = cfg_players[i]
		players.append({"index": i, "name": str(c.get("name", "Player")), "race": str(c.race), "team": int(c.get("team", i)),
			"color": int(c.get("color", i)), "ai": int(c.get("ai", -1)), "peer": int(c.get("peer", 0)), "start": int(c.get("start", i)),
			"gold": Data.START_GOLD, "aether": Data.START_AETHER, "supply": 0, "cap": 0, "tier": 1, "techs": {}, "researching": {},
			"alive": true, "stats": {"trained": 0, "killed": 0, "lost": 0, "gold": 0, "aether": 0, "built": 0, "razed": 0, "techs": 0}})
	for r in map.resources:
		var e := _new_ent(Ent.RESOURCE, str(r.type), -1)
		e.cell = r.cell
		e.size = 1
		e.pos = MapData.cell_centre(r.cell)
		e.radius = 0.8
		e.amount = int(Data.RESOURCES[r.type].amount)
		if map.template.shape == "ring" and Vector2(r.cell).distance_to(Vector2(map.n, map.n) * 0.5) < 14.0:
			e.amount = int(e.amount * 1.5)
		e.hp = e.amount
		e.max_hp = e.amount
		_occupy(e, true)
	if mirror:
		return
	for i in players.size():
		var p := players[i]
		var s: Vector2i = map.starts[p.start]
		var hall := place_building(i, "hall", s, true)
		hall.has_rally = false
		var centre := hall.rect().get_center()
		var to_mid := (Vector2(map.n, map.n) * Data.CELL * 0.5 - centre).normalized()
		for k in 5:
			var u := spawn_unit(i, "worker", centre + to_mid * 5.5 + Vector2(to_mid.y, -to_mid.x) * (k - 2) * 1.2)
			u.facing = atan2(to_mid.x, to_mid.y)
		var scout := "cavalry" if Data.has_unit(p.race, "cavalry") else "spear"
		spawn_unit(i, scout, centre + to_mid * 8.0)
	_recount()


func _new_ent(cat: int, role: String, owner: int) -> Ent:
	var e := Ent.new()
	e.id = next_id
	next_id += 1
	e.cat = cat
	e.role = role
	e.owner = owner
	ents[e.id] = e
	list.append(e)
	return e


func get_ent(id: int) -> Ent:
	return ents.get(id)


func team_of(player: int) -> int:
	return players[player].team if player >= 0 and player < players.size() else -1


func enemies(a: int, b: int) -> bool:
	return a >= 0 and b >= 0 and a != b and team_of(a) != team_of(b)


# --- stats ---------------------------------------------------------------------------------

## A unit's or building's numbers for a player, with race changes and researched techs.
func stats(player: int, role: String) -> Dictionary:
	var per: Dictionary = _stats.get(player, {})
	if per.has(role):
		return per[role]
	var p := players[player]
	var race: String = p.race
	var rd: Dictionary = Data.RACES[race]
	var is_b := Data.BUILDINGS.has(role)
	var base: Dictionary = Data.BUILDINGS[role] if is_b else Data.UNITS[role]
	var s := {"hp": float(base.hp), "atk": float(base.get("atk", 0)), "cd": float(base.get("cd", 1.0)), "range": float(base.get("range", 0.0)),
		"arm": float(base.get("arm", 0)), "parm": float(base.get("parm", 0)), "speed": float(base.get("speed", 0.0)), "sight": float(base.get("sight", 8.0)),
		"bonus": base.get("bonus", {}), "air": bool(base.get("air", false)), "splash": float(base.get("splash", 0.0)), "heal": float(base.get("heal", 0.0)),
		"minrange": float(base.get("minrange", 0.0)), "dmg": str(base.get("dmg", "pierce")), "cls": base.get("cls", ["building"]),
		"gather_g": 1.0, "gather_a": 1.0, "carry": float(Data.CARRY), "regen": 0.0, "train": 1.0, "elite": false}
	var mods: Dictionary = rd.mods.get(role, {})
	for k in mods:
		s[k] = s[k] + mods[k]
	var hp_pct := 0.0
	var speed_pct := 0.0
	var fx: Array = []
	var bonus: Dictionary = rd.bonus
	if bonus.has("regen") and not is_b:
		s.regen += bonus.regen
	if bonus.has("hp%"):
		hp_pct += bonus["hp%"].get(role, 0)
	if bonus.has("range"):
		s.range += bonus.range.get(role, 0.0)
	if bonus.has("gather_a%") and role == "worker":
		s.gather_a += bonus["gather_a%"] / 100.0
	for t in p.techs:
		var td: Dictionary = Data.TECHS[t]
		fx.append_array(td.get("fx", []))
		if td.has("elite") and td.elite == role:
			s.elite = true
			for e in Data.ELITE_FX:
				var e2: Dictionary = e.duplicate()
				e2.roles = [role]
				fx.append(e2)
		if t == "unique":
			fx.append_array(rd.unique_fx)
	for f in fx:
		var roles: Array = f.roles
		if not (role in roles or ("*" in roles and not is_b) or ("*b" in roles and is_b)):
			continue
		match str(f.stat):
			"hp%", "bhp%":
				hp_pct += f.add
			"speed%":
				speed_pct += f.add
			"gather_g%":
				s.gather_g += f.add / 100.0
			"gather_a%":
				s.gather_a += f.add / 100.0
			"train%":
				s.train += f.add / 100.0
			_:
				s[f.stat] = s[f.stat] + f.add
	s.hp = s.hp * (1.0 + hp_pct / 100.0)
	s.speed = s.speed * (1.0 + speed_pct / 100.0)
	per[role] = s
	_stats[player] = per
	return s


func cost_of(player: int, kind: String, id: String) -> Dictionary:
	var race: String = players[player].race
	var c: Dictionary
	if kind == "unit":
		c = Data.UNITS[id].cost.duplicate()
		if id == "worker" and Data.RACES[race].bonus.has("worker_cost"):
			c.g = Data.RACES[race].bonus.worker_cost
	elif kind == "building":
		c = Data.BUILDINGS[id].cost.duplicate()
	else:
		c = Data.TECHS[id].cost.duplicate()
		var pct: float = Data.RACES[race].bonus.get("tech_cost%", 0)
		if pct != 0:
			for k in c:
				c[k] = int(round(c[k] * (1.0 + pct / 100.0)))
	return c


func can_afford(player: int, c: Dictionary) -> bool:
	var p := players[player]
	return p.gold >= c.get("g", 0) and p.aether >= c.get("a", 0)


func _pay(player: int, c: Dictionary, sign_v := 1) -> void:
	var p := players[player]
	p.gold -= c.get("g", 0) * sign_v
	p.aether -= c.get("a", 0) * sign_v


func _invalidate(player: int) -> void:
	_stats.erase(player)
	for e in list:
		if e.owner == player and e.alive and not e.is_resource():
			var s := stats(player, e.role)
			if e.is_building() and not e.complete:
				e.max_hp = s.hp
				continue
			var ratio := e.hp / maxf(e.max_hp, 1.0)
			e.max_hp = s.hp
			e.hp = s.hp * ratio
			e.elite = s.elite


# --- what a player may do (also used by the HUD) --------------------------------------------

## Why a player cannot train/research/build something right now ("" when they can).
func why_not(player: int, kind: String, id: String, at: Ent = null) -> String:
	var p := players[player]
	var race: String = p.race
	match kind:
		"unit":
			if not Data.has_unit(race, id):
				return "Not available to " + Data.RACES[race].name
			if p.tier < Data.UNITS[id].tier:
				return "Needs the " + Data.age_name(race, Data.UNITS[id].tier)
		"building":
			if not Data.has_building(race, id):
				return "Not available to " + Data.RACES[race].name
			if p.tier < Data.BUILDINGS[id].tier:
				return "Needs the " + Data.age_name(race, Data.BUILDINGS[id].tier)
		"tech":
			if not Data.has_tech(race, id):
				return "Not available to " + Data.RACES[race].name
			if p.techs.has(id):
				return "Already researched"
			if p.researching.has(id):
				return "Being researched"
			var td: Dictionary = Data.TECHS[id]
			if p.tier < td.tier:
				return "Needs the " + Data.age_name(race, td.tier)
			if td.has("need") and not p.techs.has(td.need):
				return "Needs " + Data.tech_name(race, td.need)
			if id == "tier2" and not _has_complete(player, "barracks"):
				return "Needs a " + Data.building_name(race, "barracks")
			if id == "tier3" and not (_has_complete(player, "sanctum") or _has_complete(player, "stable") or _has_complete(player, "workshop")):
				return "Needs a second-age building"
	var c := cost_of(player, kind, id)
	if not can_afford(player, c):
		return "Not enough " + ("gold" if p.gold < c.get("g", 0) else "aether")
	return ""


func _has_complete(player: int, role: String) -> bool:
	for e in list:
		if e.owner == player and e.alive and e.is_building() and e.complete and e.role == role:
			return true
	return false


func can_place(role: String, c: Vector2i, ignore_units := false) -> bool:
	var s: int = Data.BUILDINGS[role].size
	for y in s:
		for x in s:
			var q := c + Vector2i(x, y)
			if not map.walkable(q) or occ[map.idx(q)] != 0:
				return false
			if map.get_cell(q) == MapData.BRIDGE or map.get_cell(q) == MapData.RAMP:
				return false
	# all of it on one level
	var h0 := map.heights[map.idx(c)]
	for y in s:
		for x in s:
			if absf(map.heights[map.idx(c + Vector2i(x, y))] - h0) > 0.1:
				return false
	if not ignore_units:
		var r := Rect2(Vector2(c) * Data.CELL, Vector2(s, s) * Data.CELL).grow(-0.2)
		for e in (_near(r.get_center(), s * Data.CELL) if not _buckets.is_empty() else list):
			if e.is_unit() and e.alive and not e.flying and r.has_point(e.pos) and e.order != Ent.BUILD:
				return false
	return true


# --- commands ------------------------------------------------------------------------------

## Applies one player's command. Commands are small dictionaries (see the match below) so the
## same ones come from the mouse, the AI and the network.
func command(player: int, cmd: Dictionary) -> void:
	if over or player < 0 or player >= players.size() or not players[player].alive:
		return
	var t := str(cmd.get("t", ""))
	var ids: Array = cmd.get("ids", [])
	var mine: Array[Ent] = []
	for id in ids:
		var e: Ent = ents.get(int(id))
		if e and e.alive and e.owner == player:
			mine.append(e)
	match t:
		"move", "amove":
			var units := mine.filter(func(e): return e.is_unit())
			_group_move(units, Vector2(cmd.x, cmd.y), Ent.AMOVE if t == "amove" else Ent.MOVE)
		"target":
			var tgt: Ent = ents.get(int(cmd.get("id", 0)))
			if tgt == null or not tgt.alive:
				return
			for e in mine:
				if e.is_unit():
					_smart(e, tgt)
		"stop":
			for e in mine:
				if e.is_unit():
					_set_order(e, Ent.IDLE)
		"build":
			var role := str(cmd.b)
			var c := Vector2i(int(cmd.cx), int(cmd.cy))
			var workers := mine.filter(func(e): return e.is_unit() and e.role == "worker")
			if workers.is_empty() or why_not(player, "building", role) != "" or not can_place(role, c):
				_notice(player, "Cannot build there." if why_not(player, "building", role) == "" else why_not(player, "building", role))
				return
			_pay(player, cost_of(player, "building", role))
			var b := place_building(player, role, c, false)
			for w in workers:
				_set_order(w, Ent.BUILD, b.id)
		"train":
			var b: Ent = ents.get(int(cmd.id))
			if b == null or b.owner != player or not b.complete or not b.is_building():
				return
			var role := str(cmd.u)
			if role not in Data.BUILDINGS[b.role].get("trains", []):
				return
			for k in int(cmd.get("n", 1)):
				if b.queue.size() >= QUEUE_MAX:
					return
				var why := why_not(player, "unit", role)
				if why != "":
					_notice(player, why)
					return
				_pay(player, cost_of(player, "unit", role))
				b.queue.append({"kind": "unit", "id": role, "t": 0.0, "total": float(Data.UNITS[role].time), "reserved": false})
		"research":
			var b: Ent = ents.get(int(cmd.id))
			var tech := str(cmd.k)
			if b == null or b.owner != player or not b.complete or Data.TECHS[tech].at != b.role or b.queue.size() >= QUEUE_MAX:
				return
			var why := why_not(player, "tech", tech)
			if why != "":
				_notice(player, why)
				return
			_pay(player, cost_of(player, "tech", tech))
			players[player].researching[tech] = true
			b.queue.append({"kind": "tech", "id": tech, "t": 0.0, "total": float(Data.TECHS[tech].time), "reserved": false})
		"cancel":
			var b: Ent = ents.get(int(cmd.id))
			if b == null or b.owner != player:
				return
			if not b.complete:
				# cancelling a foundation refunds most of it
				var c := cost_of(player, "building", b.role)
				for k in c:
					c[k] = int(c[k] * 0.75)
				_pay(player, c, -1)
				_kill(b, -1)
				return
			var i := int(cmd.get("i", b.queue.size() - 1))
			if i < 0 or i >= b.queue.size():
				return
			var q: Dictionary = b.queue[i]
			_pay(player, cost_of(player, q.kind, q.id), -1)
			if q.kind == "tech":
				players[player].researching.erase(q.id)
			b.queue.remove_at(i)
		"rally":
			for e in mine:
				if e.is_building():
					e.rally = Vector2(cmd.x, cmd.y)
					e.has_rally = true
		"delete":
			for e in mine:
				_kill(e, -1)
		"resign":
			_defeat(player)


func _notice(player: int, text: String) -> void:
	event.emit({"t": "notice", "p": player, "text": text})


func _set_order(u: Ent, order: int, target_id := 0, goal := Vector2.ZERO) -> void:
	u.order = order
	u.target = target_id
	u.goal = goal
	u.engage = 0
	u.path = PackedVector2Array()
	u.path_i = 0
	u.path_goal = Vector2(-999, -999)
	u.repath_t = 0.0
	u.stuck_t = 0.0
	if order == Ent.GATHER and target_id != 0:
		u.res_target = target_id


## Right-click on something: attack an enemy, gather a deposit, build or repair, drop off,
## or follow a friend.
func _smart(u: Ent, t: Ent) -> void:
	if t.is_resource():
		if u.role == "worker":
			_set_order(u, Ent.GATHER, t.id)
		else:
			_set_order(u, Ent.MOVE, 0, t.pos)
		return
	if enemies(u.owner, t.owner):
		if can_hit(u, t):
			_set_order(u, Ent.ATTACK, t.id)
		else:
			_set_order(u, Ent.MOVE, 0, t.pos)
		return
	if t.is_building() and u.role == "worker" and t.owner == u.owner:
		if not t.complete or t.hp < t.max_hp:
			_set_order(u, Ent.BUILD, t.id)
			return
		if u.carry > 0 and Data.BUILDINGS[t.role].get("drop", false):
			_set_order(u, Ent.RETURN, t.id)
			return
	if t.is_unit() and t != u:
		_set_order(u, Ent.FOLLOW, t.id)
		return
	_set_order(u, Ent.MOVE, 0, t.pos if t.is_unit() else _approach(u, t))


func _group_move(units: Array, goal: Vector2, order: int) -> void:
	if units.is_empty():
		return
	var centre := Vector2.ZERO
	for u in units:
		centre += u.pos
	centre /= units.size()
	# keep the group's shape if it is tight, otherwise gather in a block around the goal
	var spread := 0.0
	for u in units:
		spread = maxf(spread, u.pos.distance_to(centre))
	var cols := int(ceil(sqrt(units.size())))
	var sorted := units.duplicate()
	var dir := (goal - centre).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2(0, 1)
	var side := Vector2(-dir.y, dir.x)
	sorted.sort_custom(func(a, b): return (a.pos - centre).dot(side) < (b.pos - centre).dot(side))
	for i in sorted.size():
		var u: Ent = sorted[i]
		var off: Vector2
		if spread < 6.0 and units.size() > 1:
			off = u.pos - centre
		else:
			var row := i / cols
			var col := i % cols
			off = side * (col - (cols - 1) * 0.5) * 1.6 - dir * row * 1.6
		var g := goal + off if units.size() > 1 else goal
		if not u.flying and not map.walkable(MapData.cell_of(g)):
			g = goal
		_set_order(u, order, 0, g)


# --- buildings and units -------------------------------------------------------------------

func place_building(player: int, role: String, c: Vector2i, done: bool) -> Ent:
	var b := _new_ent(Ent.BUILDING, role, player)
	b.cell = c
	b.size = Data.BUILDINGS[role].size
	b.pos = b.rect().get_center()
	b.radius = b.size * Data.CELL * 0.5
	var s := stats(player, role)
	b.max_hp = s.hp
	b.complete = done
	b.built = 1.0 if done else 0.0
	b.hp = s.hp if done else maxf(1.0, s.hp * 0.08)
	b.facing = 0.0
	_occupy(b, true)
	# push out anyone standing on the foundation
	var r := b.rect()
	for e in list:
		if e.is_unit() and e.alive and not e.flying and r.grow(e.radius).has_point(e.pos):
			e.pos = _free_spot_near(b, e.pos, 0.3)
			e.prev_pos = e.pos
	if done:
		_recount()
	return b


func spawn_unit(player: int, role: String, at: Vector2) -> Ent:
	var u := _new_ent(Ent.UNIT, role, player)
	var s := stats(player, role)
	u.pos = at
	u.prev_pos = at
	u.max_hp = s.hp
	u.hp = s.hp
	u.radius = Data.UNITS[role].radius
	u.flying = Data.UNITS[role].get("fly", false)
	u.elite = s.elite
	u.scan_t = randf() * 0.5
	return u


func _occupy(e: Ent, on: bool) -> void:
	for y in e.size:
		for x in e.size:
			var c := e.cell + Vector2i(x, y)
			if not map.inside(c):
				continue
			occ[map.idx(c)] = e.id if on else 0
			if not mirror:
				astar.set_point_solid(c, on or not map.walkable(c))


## Mirror (guest) only: keeps the occupancy grid in step with the host's buildings.
func mirror_occupy(e: Ent, on: bool) -> void:
	_occupy(e, on)


## Mirror only: an entity the host's snapshot has and this copy does not yet.
func mirror_add(id: int, cat: int, role: String, owner: int) -> Ent:
	var e := Ent.new()
	e.id = id
	e.cat = cat
	e.role = role
	e.owner = owner
	ents[id] = e
	list.append(e)
	next_id = maxi(next_id, id + 1)
	return e


## Mirror only: an entity the host no longer has (it died or ran out).
func mirror_remove(e: Ent) -> void:
	e.alive = false
	if not e.is_unit():
		_occupy(e, false)
	ents.erase(e.id)
	list.erase(e)


## Mirror only: techs changed, so cached unit numbers are stale.
func invalidate_stats() -> void:
	_stats.clear()


func _free_spot_near(b: Ent, from: Vector2, jitter := 0.0) -> Vector2:
	var best := from
	var best_d := INF
	var s := b.size
	for y in range(-1, s + 1):
		for x in range(-1, s + 1):
			if x >= 0 and x < s and y >= 0 and y < s:
				continue
			var c := b.cell + Vector2i(x, y)
			if not map.walkable(c) or occ[map.idx(c)] != 0:
				continue
			var p := MapData.cell_centre(c)
			var d := p.distance_to(from)
			if d < best_d:
				best_d = d
				best = p
	if best_d == INF:
		# ring is full: try further out
		for rr in range(2, 6):
			for y in range(-rr, s + rr):
				for x in range(-rr, s + rr):
					var c := b.cell + Vector2i(x, y)
					if map.walkable(c) and occ[map.idx(c)] == 0:
						var p := MapData.cell_centre(c)
						var d := p.distance_to(from)
						if d < best_d:
							best_d = d
							best = p
			if best_d < INF:
				break
	return best + Vector2(randf_range(-jitter, jitter), randf_range(-jitter, jitter))


## Where a unit should walk to reach a building or deposit: the closest free cell beside it.
func _approach(u: Ent, t: Ent) -> Vector2:
	if t.is_unit():
		return t.pos
	return _free_spot_near(t, u.pos)


func _recount() -> void:
	for p in players:
		p.supply = 0
		p.cap = 0
	for e in list:
		if not e.alive or e.owner < 0:
			continue
		var p := players[e.owner]
		if e.is_unit():
			p.supply += int(Data.UNITS[e.role].supply)
		elif e.complete:
			p.cap += int(Data.BUILDINGS[e.role].get("supply", 0))
			for q in e.queue:
				if q.reserved:
					p.supply += int(Data.UNITS[q.id].supply)
	for p in players:
		p.cap = mini(p.cap, Data.MAX_SUPPLY)


# --- stepping ------------------------------------------------------------------------------

func step() -> void:
	if mirror or over:
		return
	time += STEP
	_buckets.clear()
	for e in list:
		if e.alive and e.is_unit():
			var k := Vector2i(floori(e.pos.x / BUCKET), floori(e.pos.y / BUCKET))
			if not _buckets.has(k):
				_buckets[k] = []
			_buckets[k].append(e)
	var snapshot := list.duplicate()
	for e in snapshot:
		if not e.alive:
			continue
		if e.is_unit():
			_unit(e)
		elif e.is_building():
			_building(e)
	_separate()
	# drop the dead
	var i := 0
	while i < list.size():
		if not list[i].alive:
			ents.erase(list[i].id)
			list.remove_at(i)
		else:
			i += 1
	_check_t -= STEP
	if _check_t <= 0.0:
		_check_t = 1.0
		_recount()
		_check_victory()


func _unit(u: Ent) -> void:
	u.prev_pos = u.pos
	var s := stats(u.owner, u.role)
	if s.regen > 0.0 and u.hp < u.max_hp:
		u.hp = minf(u.max_hp, u.hp + s.regen * STEP)
	u.cd -= STEP
	u.anim = Ent.A_IDLE
	match u.order:
		Ent.IDLE:
			_idle(u, s)
		Ent.MOVE:
			if _walk(u, u.goal, s.speed, 0.4):
				_set_order(u, Ent.IDLE)
		Ent.FOLLOW:
			var t: Ent = ents.get(u.target)
			if t == null or not t.alive:
				_set_order(u, Ent.IDLE)
			elif u.pos.distance_to(t.pos) > 3.0:
				_walk(u, t.pos, s.speed, 2.5)
		Ent.AMOVE:
			if u.engage != 0:
				var t: Ent = ents.get(u.engage)
				if t == null or not t.alive or u.pos.distance_to(t.pos) > s.sight + 4.0:
					u.engage = 0
					u.path_goal = Vector2(-999, -999)
				else:
					_fight(u, t, s)
					return
			u.scan_t -= STEP
			if u.scan_t <= 0.0:
				u.scan_t = 0.5
				var t := _find_enemy(u, s.sight, s)
				if t:
					u.engage = t.id
					return
			if _walk(u, u.goal, s.speed, 0.6):
				_set_order(u, Ent.IDLE)
		Ent.ATTACK:
			var t: Ent = ents.get(u.target)
			if t == null or not t.alive:
				_set_order(u, Ent.IDLE)
				u.scan_t = 0.0
				return
			_fight(u, t, s)
		Ent.GATHER:
			_gather(u, s)
		Ent.RETURN:
			_return(u, s)
		Ent.BUILD:
			_build(u, s)


func _idle(u: Ent, s: Dictionary) -> void:
	if u.engage != 0:
		var t: Ent = ents.get(u.engage)
		if t and t.alive and u.pos.distance_to(t.pos) < s.sight + 3.0:
			_fight(u, t, s)
			return
		u.engage = 0
		# go back to where the fight started
		if u.goal != Vector2.ZERO and u.pos.distance_to(u.goal) > 2.0:
			_walk(u, u.goal, s.speed, 0.8)
			return
	if s.heal > 0.0 and _heal(u, s):
		return
	u.scan_t -= STEP
	if u.scan_t > 0.0:
		return
	u.scan_t = 0.6
	if u.role == "worker":
		return
	var t := _find_enemy(u, s.sight, s)
	if t:
		u.engage = t.id
		u.goal = u.pos


func _heal(u: Ent, s: Dictionary) -> bool:
	if u.cd > 0.0:
		return false
	var best: Ent = null
	var worst := 0.999
	for o in _near(u.pos, 6.0):
		if o != u and o.alive and o.owner == u.owner and o.hp / o.max_hp < worst and o.role != "siege":
			worst = o.hp / o.max_hp
			best = o
	if best == null:
		return false
	best.hp = minf(best.max_hp, best.hp + s.heal * 2.0)
	u.cd = 1.5
	u.anim = Ent.A_ATTACK
	u.atk_n = (u.atk_n + 1) % 256
	u.atk_target = best.id
	u.facing = _face(u.pos, best.pos)
	event.emit({"t": "heal", "from": u.id, "to": best.id})
	return true


func can_hit(a: Ent, t: Ent) -> bool:
	if not t.alive or t.is_resource():
		return false
	if t.flying:
		return stats(a.owner, a.role).air if a.owner >= 0 else false
	return true


## The closest enemy a unit or tower can attack within `radius`, preferring troops that fight
## back over workers, and anything over buildings.
func _find_enemy(u: Ent, radius: float, s: Dictionary) -> Ent:
	var best: Ent = null
	var best_score := INF
	var siege := u.role == "siege"
	for o in _near(u.pos, radius):
		if not o.alive or not enemies(u.owner, o.owner) or not can_hit(u, o):
			continue
		var d := u.pos.distance_to(o.pos)
		if d > radius:
			continue
		var score := d
		if o.role == "worker":
			score += 4.0
		if siege:
			score += 6.0
		if score < best_score:
			best_score = score
			best = o
	if best and not siege:
		return best
	# buildings
	for b in list:
		if not b.alive or not b.is_building() or not enemies(u.owner, b.owner):
			continue
		var d := b.edge_dist(u.pos)
		if d > radius * 0.7:
			continue
		var score := d + (0.0 if siege else 6.0)
		if score < best_score:
			best_score = score
			best = b
	return best


func _near(p: Vector2, r: float) -> Array:
	var out := []
	var k0 := Vector2i(floori((p.x - r) / BUCKET), floori((p.y - r) / BUCKET))
	var k1 := Vector2i(floori((p.x + r) / BUCKET), floori((p.y + r) / BUCKET))
	for y in range(k0.y, k1.y + 1):
		for x in range(k0.x, k1.x + 1):
			var b = _buckets.get(Vector2i(x, y))
			if b:
				out.append_array(b)
	return out


func _in_range(a: Ent, t: Ent, s: Dictionary) -> bool:
	var reach: float = s.range + a.radius
	if t.is_unit():
		reach += t.radius
	return t.edge_dist(a.pos) <= reach + (0.0 if t.is_unit() else 0.25) and (s.minrange <= 0.0 or a.pos.distance_to(t.pos) >= s.minrange)


func _fight(u: Ent, t: Ent, s: Dictionary) -> void:
	if not can_hit(u, t):
		_set_order(u, Ent.IDLE)
		return
	if _in_range(u, t, s):
		u.facing = _face(u.pos, t.pos)
		u.path = PackedVector2Array()
		u.path_goal = Vector2(-999, -999)
		if u.cd <= 0.0:
			_attack(u, t, s)
		u.anim = Ent.A_ATTACK if u.cd > float(s.cd) - 0.45 else Ent.A_IDLE
	else:
		var aim := t.pos
		if not t.is_unit():
			aim = u.path_goal if u.path_goal.x > -900 and t.edge_dist(u.path_goal) < 2.5 else _approach(u, t)
		_walk(u, aim, s.speed, 0.1)


func _attack(u: Ent, t: Ent, s: Dictionary) -> void:
	u.cd = s.cd
	u.atk_n = (u.atk_n + 1) % 256
	u.atk_target = t.id
	if s.splash > 0.0:
		var centre := t.pos
		for o in _near(centre, s.splash + 1.5):
			if o.alive and enemies(u.owner, o.owner) and o.pos.distance_to(centre) <= s.splash + o.radius and can_hit(u, o) and o != t:
				_damage(u, o, s, 0.6)
	_damage(u, t, s, 1.0)
	event.emit({"t": "attack", "from": u.id, "to": t.id, "role": u.role, "owner": u.owner})


func _damage(a: Ent, t: Ent, s: Dictionary, mult: float) -> void:
	var ts: Dictionary = stats(t.owner, t.role) if t.owner >= 0 else {}
	var armour := 0.0
	match str(s.dmg):
		"melee", "siege":
			armour = ts.get("arm", 0.0)
		"pierce":
			armour = ts.get("parm", 0.0)
	var dmg := maxf(1.0, s.atk - armour)
	var bonus: Dictionary = s.bonus
	var cls: Array = ts.get("cls", ["building"]) if t.is_unit() else ["building"]
	for c in cls:
		dmg += bonus.get(c, 0.0)
	if t.is_building() and s.dmg == "pierce":
		dmg *= 0.5
	dmg *= mult
	t.hp -= dmg
	t.last_hit_t = time
	if t.owner >= 0 and (not _alert_t.has(t.owner) or time - _alert_t[t.owner] > 12.0):
		_alert_t[t.owner] = time
		event.emit({"t": "alert", "p": t.owner, "x": t.pos.x, "y": t.pos.y})
	if t.hp <= 0.0:
		players[a.owner].stats.killed += 1
		if t.is_building():
			players[a.owner].stats.razed += 1
		_kill(t, a.owner)
		return
	# troops strike back; idle towers notice
	if t.is_unit() and t.role != "worker" and (t.order == Ent.IDLE or t.order == Ent.FOLLOW) and t.engage == 0 and can_hit(t, a):
		t.engage = a.id
		if t.goal == Vector2.ZERO:
			t.goal = t.pos


func _kill(e: Ent, by: int) -> void:
	if not e.alive:
		return
	e.alive = false
	if e.is_building() or e.is_resource():
		_occupy(e, false)
		if e.is_building():
			for q in e.queue:
				if q.kind == "tech":
					players[e.owner].researching.erase(q.id)
	if e.owner >= 0 and e.is_unit():
		players[e.owner].stats.lost += 1
	event.emit({"t": "death", "id": e.id, "role": e.role, "owner": e.owner, "cat": e.cat, "x": e.pos.x, "y": e.pos.y})
	_recount()


static func _face(from: Vector2, to: Vector2) -> float:
	var d := to - from
	return atan2(d.x, d.y) if d.length_squared() > 0.0001 else 0.0


# --- walking -------------------------------------------------------------------------------

## Moves a unit toward `goal` along a grid path. Returns true once within `arrive` metres.
func _walk(u: Ent, goal: Vector2, speed: float, arrive: float) -> bool:
	if u.pos.distance_to(goal) <= arrive:
		return true
	u.repath_t -= STEP
	if u.flying:
		_step_toward(u, goal, speed)
		return u.pos.distance_to(goal) <= arrive
	if u.path.is_empty() or u.stuck_t > 1.2 or (u.path_goal.distance_to(goal) > 1.0 and u.repath_t <= 0.0):
		_make_path(u, goal)
	if u.path_i >= u.path.size():
		if u.path.size() > 0 and u.path[u.path.size() - 1].distance_to(goal) > arrive + 1.0:
			# the path ended short (goal unreachable): stop there
			return true
		_step_toward(u, goal, speed)
		return u.pos.distance_to(goal) <= arrive
	var wp := u.path[u.path_i]
	var before := u.pos
	_step_toward(u, wp, speed)
	if u.pos.distance_to(wp) < 0.5 or (u.path_i < u.path.size() - 1 and _los(u.pos, u.path[u.path_i + 1])):
		u.path_i += 1
	if u.pos.distance_to(before) < speed * STEP * 0.25:
		u.stuck_t += STEP
	else:
		u.stuck_t = maxf(0.0, u.stuck_t - STEP)
	return false


func _step_toward(u: Ent, wp: Vector2, speed: float) -> void:
	var d := wp - u.pos
	var dist := d.length()
	if dist < 0.001:
		return
	var stepv := d / dist * minf(dist, speed * STEP)
	u.facing = lerp_angle(u.facing, atan2(d.x, d.y), 0.5)
	u.anim = Ent.A_WALK
	if u.flying:
		u.pos += stepv
		u.pos = u.pos.clamp(Vector2(1, 1), Vector2.ONE * (map.size_m() - 1.0))
		return
	var np := u.pos + stepv
	if _free(np):
		u.pos = np
	elif _free(Vector2(np.x, u.pos.y)):
		u.pos.x = np.x
	elif _free(Vector2(u.pos.x, np.y)):
		u.pos.y = np.y


func _free(p: Vector2) -> bool:
	var c := MapData.cell_of(p)
	return map.walkable(c) and occ[map.idx(c)] == 0


func _make_path(u: Ent, goal: Vector2) -> void:
	u.path_goal = goal
	u.repath_t = 0.6
	u.stuck_t = 0.0
	u.path = PackedVector2Array()
	u.path_i = 0
	var from := MapData.cell_of(u.pos)
	if not map.inside(from) or astar.is_point_solid(from):
		from = _nearest_open(from)
		u.pos = MapData.cell_centre(from)
	var to := MapData.cell_of(goal)
	if not map.inside(to) or astar.is_point_solid(to):
		to = _nearest_open(to, from)
	if from == to:
		u.path = PackedVector2Array([goal])
		return
	var ids := astar.get_id_path(from, to, true)
	if ids.is_empty():
		u.path = PackedVector2Array([goal])
		return
	var pts := PackedVector2Array()
	for k in range(1, ids.size()):
		pts.append(MapData.cell_centre(ids[k]))
	if ids[ids.size() - 1] == MapData.cell_of(goal):
		pts[pts.size() - 1] = goal
	u.path = pts


func _nearest_open(c: Vector2i, toward := Vector2i(-1, -1)) -> Vector2i:
	for r in range(1, 12):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				if absi(x) != r and absi(y) != r:
					continue
				var q := c + Vector2i(x, y)
				if map.inside(q) and not astar.is_point_solid(q):
					var d := Vector2(q).distance_to(Vector2(toward if toward.x >= 0 else c))
					if d < best_d:
						best_d = d
						best = q
		if best.x >= 0:
			return best
	return c


## Whether a straight walk between two points crosses only open cells.
func _los(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := int(d.length() / (Data.CELL * 0.4)) + 1
	for k in range(1, steps + 1):
		var p := a + d * (float(k) / steps)
		if not _free(p):
			return false
	return true


## Pushes overlapping ground units apart; units standing still give way to moving ones.
func _separate() -> void:
	for k in _buckets:
		var arr: Array = _buckets[k]
		var others := []
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var b = _buckets.get(k + Vector2i(ox, oy))
				if b:
					others.append_array(b)
		for a in arr:
			if not a.alive:
				continue
			for o in others:
				if o == a or not o.alive or o.flying != a.flying or o.id < a.id and arr.has(o):
					continue
				var d: Vector2 = a.pos - o.pos
				var min_d: float = (a.radius + o.radius) * (0.6 if a.flying else 0.9)
				var dist := d.length()
				if dist >= min_d:
					continue
				if dist < 0.001:
					d = Vector2(randf_range(-1, 1), randf_range(-1, 1))
					dist = d.length()
				var push := d / dist * (min_d - dist)
				var wa := 0.5
				var a_moving: bool = a.anim == Ent.A_WALK
				var o_moving: bool = o.anim == Ent.A_WALK
				if a_moving and not o_moving:
					wa = 0.2
				elif o_moving and not a_moving:
					wa = 0.8
				_nudge(a, push * wa * 0.5)
				_nudge(o, -push * (1.0 - wa) * 0.5)


func _nudge(u: Ent, v: Vector2) -> void:
	if u.flying:
		u.pos += v
		return
	var np: Vector2 = u.pos + v
	if _free(np):
		u.pos = np


# --- economy -------------------------------------------------------------------------------

func _gather(u: Ent, s: Dictionary) -> void:
	var r: Ent = ents.get(u.target)
	if r == null or not r.alive:
		r = _nearest_resource(u.carry_type, u.pos, 14.0)
		if r == null:
			if u.carry > 0:
				_set_order(u, Ent.RETURN)
			else:
				_set_order(u, Ent.IDLE)
			return
		u.target = r.id
		u.res_target = r.id
		u.path_goal = Vector2(-999, -999)
	if u.carry_type != r.role:
		u.carry = 0
		u.carry_type = r.role
	if not _touching(u, r):
		var aim := u.path_goal if u.path_goal.x > -900 and u.path_goal.distance_to(r.pos) < 2.5 else _approach(u, r)
		_walk(u, aim, s.speed, 0.2)
		return
	u.facing = _face(u.pos, r.pos)
	u.anim = Ent.A_WORK
	var rate: float = Data.RESOURCES[r.role].rate * (s.gather_g if r.role == "gold" else s.gather_a)
	u.gather_t += STEP * rate
	while u.gather_t >= 1.0 and r.alive:
		u.gather_t -= 1.0
		u.carry += 1
		r.amount -= 1
		r.hp = r.amount
		if r.amount <= 0:
			_kill(r, -1)
	if u.carry >= int(s.carry):
		_set_order(u, Ent.RETURN)
		u.res_target = r.id


## Close enough to work on a building or deposit (standing on a neighbouring cell counts).
func _touching(u: Ent, t: Ent) -> bool:
	return t.edge_dist(u.pos) <= u.radius + 1.15


func _nearest_resource(type: String, p: Vector2, radius: float) -> Ent:
	var best: Ent = null
	var best_d := radius
	for e in list:
		if e.alive and e.is_resource() and (type == "" or e.role == type):
			var d := e.pos.distance_to(p)
			if d < best_d:
				best_d = d
				best = e
	return best


func nearest_drop(player: int, p: Vector2) -> Ent:
	var best: Ent = null
	var best_d := INF
	for e in list:
		if e.alive and e.owner == player and e.is_building() and e.complete and Data.BUILDINGS[e.role].get("drop", false):
			var d := e.edge_dist(p)
			if d < best_d:
				best_d = d
				best = e
	return best


func _return(u: Ent, s: Dictionary) -> void:
	var b: Ent = ents.get(u.target)
	if b == null or not b.alive or not b.complete or b.owner != u.owner:
		b = nearest_drop(u.owner, u.pos)
		if b == null:
			_set_order(u, Ent.IDLE)
			return
		u.target = b.id
		u.path_goal = Vector2(-999, -999)
	if not _touching(u, b):
		var aim := u.path_goal if u.path_goal.x > -900 and b.edge_dist(u.path_goal) < 2.5 else _approach(u, b)
		_walk(u, aim, s.speed, 0.2)
		return
	var p := players[u.owner]
	if u.carry_type == "gold":
		p.gold += u.carry
		p.stats.gold += u.carry
	elif u.carry_type == "aether":
		p.aether += u.carry
		p.stats.aether += u.carry
	u.carry = 0
	var back := u.res_target
	var r: Ent = ents.get(back)
	if r == null or not r.alive:
		r = _nearest_resource(u.carry_type, u.pos, 20.0)
	if r:
		_set_order(u, Ent.GATHER, r.id)
	else:
		_set_order(u, Ent.IDLE)


func _build(u: Ent, s: Dictionary) -> void:
	var b: Ent = ents.get(u.target)
	if b == null or not b.alive or (b.complete and b.hp >= b.max_hp):
		var was_drop: bool = b != null and b.alive and Data.BUILDINGS[b.role].get("drop", false)
		_set_order(u, Ent.IDLE)
		if was_drop:
			var r := _nearest_resource("", u.pos, 12.0)
			if r:
				_set_order(u, Ent.GATHER, r.id)
		else:
			# help with the next unfinished building nearby
			for o in list:
				if o.alive and o.is_building() and o.owner == u.owner and not o.complete and o.pos.distance_to(u.pos) < 16.0:
					_set_order(u, Ent.BUILD, o.id)
					break
		return
	if not _touching(u, b):
		var aim := u.path_goal if u.path_goal.x > -900 and b.edge_dist(u.path_goal) < 2.5 else _approach(u, b)
		_walk(u, aim, s.speed, 0.2)
		return
	u.facing = _face(u.pos, b.pos)
	u.anim = Ent.A_WORK
	var total: float = Data.BUILDINGS[b.role].time
	if not b.complete:
		var add := STEP / total
		b.built = minf(1.0, b.built + add)
		b.hp = minf(b.max_hp, b.hp + b.max_hp * add * 0.92)
		if b.built >= 1.0:
			b.complete = true
			b.hp = maxf(b.hp, b.max_hp * 0.98)
			players[b.owner].stats.built += 1
			_recount()
			event.emit({"t": "built", "id": b.id, "p": b.owner, "role": b.role})
	else:
		b.hp = minf(b.max_hp, b.hp + b.max_hp / total * 0.5 * STEP)


func _building(b: Ent) -> void:
	if not b.complete:
		return
	var s := stats(b.owner, b.role)
	if s.atk > 0.0:
		b.cd -= STEP
		if b.cd <= 0.0:
			var t: Ent = ents.get(b.engage)
			if t == null or not t.alive or b.edge_dist(t.pos) > s.range + t.radius:
				b.engage = 0
				t = null
				for o in _near(b.pos, s.range + b.radius + 2.0):
					if o.alive and enemies(b.owner, o.owner) and can_hit(b, o) and b.edge_dist(o.pos) <= s.range + o.radius:
						t = o
						break
			if t:
				b.engage = t.id
				_attack(b, t, s)
	if b.queue.is_empty():
		return
	var q: Dictionary = b.queue[0]
	var p := players[b.owner]
	if q.kind == "unit" and not q.reserved:
		var need: int = Data.UNITS[q.id].supply
		if p.supply + need > p.cap:
			if int(time * 10.0) % 150 == 0:
				_notice(b.owner, "Need more supply: build a " + Data.building_name(p.race, "house") + ".")
			return
		q.reserved = true
		p.supply += need
	q.t += STEP * float(s.train) if q.kind == "unit" else STEP
	if q.t < q.total:
		return
	b.queue.pop_front()
	if q.kind == "unit":
		var at := _free_spot_near(b, b.rally if b.has_rally else b.pos + Vector2(0, b.radius + 2.0), 0.4)
		var u := spawn_unit(b.owner, q.id, at)
		p.stats.trained += 1
		event.emit({"t": "trained", "id": u.id, "p": b.owner, "role": q.id})
		if b.has_rally:
			var r := _resource_at(b.rally)
			if r and u.role == "worker":
				_set_order(u, Ent.GATHER, r.id)
			else:
				_set_order(u, Ent.MOVE, 0, b.rally + Vector2(randf_range(-1, 1), randf_range(-1, 1)))
		_recount()
	else:
		p.researching.erase(q.id)
		p.techs[q.id] = true
		p.stats.techs += 1
		if Data.TECHS[q.id].has("age"):
			p.tier = Data.TECHS[q.id].age
		_invalidate(b.owner)
		event.emit({"t": "researched", "p": b.owner, "k": q.id})


func _resource_at(p: Vector2) -> Ent:
	var c := MapData.cell_of(p)
	if not map.inside(c):
		return null
	var id := occ[map.idx(c)]
	var e: Ent = ents.get(id)
	return e if e and e.is_resource() else null


# --- victory -------------------------------------------------------------------------------

func _check_victory() -> void:
	for i in players.size():
		var p := players[i]
		if not p.alive:
			continue
		var has_b := false
		var has_w := false
		for e in list:
			if e.alive and e.owner == i:
				if e.is_building():
					has_b = true
					break
				if e.role == "worker":
					has_w = true
		if not has_b and not has_w:
			_defeat(i)
	var teams := {}
	for p in players:
		if p.alive:
			teams[p.team] = true
	if teams.size() <= 1 and not over:
		over = true
		winner_team = teams.keys()[0] if teams.size() == 1 else -1
		event.emit({"t": "over", "team": winner_team})


func _defeat(i: int) -> void:
	var p := players[i]
	if not p.alive:
		return
	p.alive = false
	for e in list.duplicate():
		if e.alive and e.owner == i:
			_kill(e, -1)
	event.emit({"t": "defeated", "p": i})
	_check_t = 0.0


## How many of a player's things are alive (AI and HUD helpers).
func count(player: int, role: String, include_unfinished := true) -> int:
	var n := 0
	for e in list:
		if e.alive and e.owner == player and e.role == role and (include_unfinished or e.complete):
			n += 1
	return n


func queued(player: int, id: String) -> int:
	var n := 0
	for e in list:
		if e.alive and e.owner == player and e.is_building():
			for q in e.queue:
				if q.id == id:
					n += 1
	return n
