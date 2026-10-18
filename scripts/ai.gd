class_name AI
extends RefCounted
## A computer player. It sees the whole map (no fog for the AI) and plays through the same
## Sim.command calls as a person: keeps its workers busy, builds houses before it runs out of
## supply, follows a build order for its race, trains a mixed army from what its race has,
## researches upgrades, defends its base and attacks in waves that grow over time.
## Easy thinks slowly, keeps fewer workers and attacks late; Hard is quick and aggressive.

var sim: Sim
var me := 0
var level := 1
var race := ""
var _t := 0.0
var _wave := 0
var _next_attack := 0.0
var _attacking := false
var _rally := Vector2.ZERO
var _home := Vector2.ZERO
var _plan: Array = []
var _rng := RandomNumberGenerator.new()
# rebuilt every think
var _my: Array = []
var _drops: Array = []
var _foes: Array = []

const THINK := [1.6, 1.0, 0.6]
const WORKERS := [11, 17, 22]
const FIRST_ATTACK := [600.0, 360.0, 240.0]
const WAVE_SIZE := [16, 14, 12]
var send: Callable                     # set when the commands go elsewhere (a guest's bot sends them to the host)

const MIX := {"infantry": 3.0, "spear": 2.0, "archer": 3.0, "cavalry": 3.0, "siege": 1.0, "flyer": 2.0, "caster": 1.0, "champion": 1.0}


func _init(s: Sim, player: int, lvl: int) -> void:
	sim = s
	me = player
	level = clampi(lvl, 0, 2)
	race = sim.players[me].race
	_rng.seed = hash(str(player) + race) + sim.map.seed_v
	_t = _rng.randf() * THINK[level]
	_next_attack = FIRST_ATTACK[level] + _rng.randf_range(-30.0, 30.0)
	var hall := _first("hall")
	if hall:
		_home = hall.pos
	_plan = ["barracks", "house", "forge" if level > 0 else "house", "barracks" if level > 0 else "", "tower" if level == 2 else "",
		"tier2", "sanctum", "stable", "workshop", "barracks" if level == 2 else "", "tier3", "sanctum" if level > 0 else ""]
	_plan = _plan.filter(func(x): return x != "" and (x.begins_with("tier") or Data.has_building(race, x)))


func update(dt: float) -> void:
	if not sim.players[me].alive or sim.over:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = THINK[level]
	_my.clear()
	_drops.clear()
	_foes.clear()
	for e in sim.list:
		if not e.alive:
			continue
		if e.owner == me:
			_my.append(e)
			if e.is_building() and e.complete and Data.BUILDINGS[e.role].get("drop", false):
				_drops.append(e)
		elif e.is_unit() and e.role != "worker" and sim.enemies(me, e.owner):
			_foes.append(e)
	_economy()
	_supply()
	_follow_plan()
	_train()
	_research()
	_war()


func _p() -> Dictionary:
	return sim.players[me]


func _mine(role := "") -> Array:
	if role == "":
		return _my
	var out := []
	for e in _my:
		if e.alive and e.role == role:
			out.append(e)
	return out


func _drop_dist(p: Vector2) -> float:
	var best := 999.0
	for d in _drops:
		best = minf(best, d.edge_dist(p))
	return best


func _first(role: String) -> Ent:
	for e in sim.list:
		if e.alive and e.owner == me and e.role == role:
			return e
	return null


func _cmd(c: Dictionary) -> void:
	if send.is_valid():
		send.call(c)
	else:
		sim.command(me, c)


# --- economy -------------------------------------------------------------------------------

func _economy() -> void:
	var p := _p()
	var workers := _mine("worker")
	var want: int = WORKERS[level] + (p.tier - 1) * 4
	for hall in _mine("hall"):
		if hall.complete and workers.size() + sim.queued(me, "worker") < want and hall.queue.size() < 2:
			_cmd({"t": "train", "id": hall.id, "u": "worker"})
	# idle workers go to work; keep gold and aether roughly balanced
	var on_gold := 0
	var on_aether := 0
	for w in workers:
		if w.order == Ent.GATHER or w.order == Ent.RETURN:
			if w.carry_type == "gold":
				on_gold += 1
			else:
				on_aether += 1
	for w in workers:
		if w.order != Ent.IDLE:
			continue
		var type := "gold" if on_gold <= on_aether * 1.5 else "aether"
		var r := _good_resource(type, w.pos)
		if r == null:
			r = _good_resource("aether" if type == "gold" else "gold", w.pos)
		if r:
			_cmd({"t": "target", "ids": [w.id], "id": r.id})
			if r.role == "gold":
				on_gold += 1
			else:
				on_aether += 1
	# a depot next to deposits far from any drop-off
	var near_gold := _good_resource("gold", _home, 999.0) != null
	var near_aether := _good_resource("aether", _home, 999.0) != null
	if sim.count(me, "depot") < 4 and (not near_gold or not near_aether or _rng.randf() < 0.1) and _mine("depot").filter(func(d): return not d.complete).is_empty():
		var r := _good_resource("" if near_gold == near_aether else ("aether" if near_gold else "gold"), _home, 90.0, true)
		if r:
			_build_near("depot", r.pos, 3, 6)


## A deposit close to a drop-off (or, with far_ok, the closest one to `from` anywhere).
func _good_resource(type: String, from: Vector2, radius := 60.0, far_ok := false) -> Ent:
	var best: Ent = null
	var best_d := INF
	for e in sim.list:
		if not e.alive or not e.is_resource() or (type != "" and e.role != type):
			continue
		var dd := _drop_dist(e.pos)
		if not far_ok and dd > 12.0:
			continue
		if _threatened(e.pos, 10.0):
			continue
		var d := e.pos.distance_to(from) + dd * 0.5
		if far_ok:
			d = e.pos.distance_to(from)
			if dd < 12.0:
				continue
		if d < best_d and d < radius:
			best_d = d
			best = e
	return best


func _threatened(p: Vector2, r: float) -> bool:
	for e in _foes:
		if e.alive and e.pos.distance_to(p) < r:
			return true
	return false


func _supply() -> void:
	var p := _p()
	if p.cap >= Data.MAX_SUPPLY:
		return
	var producers := 0
	for e in _mine():
		if e.is_building() and Data.BUILDINGS[e.role].has("trains"):
			producers += 1
	var pending := 0
	for h in _mine("house"):
		if not h.complete:
			pending += 8
	if p.cap + pending - p.supply < 3 + producers * 2 and p.gold >= 60:
		_build_near("house", _home, 6, 14)


func _follow_plan() -> void:
	if _plan.is_empty():
		return
	var step: String = _plan[0]
	var p := _p()
	if step.begins_with("tier"):
		if p.techs.has(step):
			_plan.pop_front()
			return
		if p.researching.has(step):
			return
		var hall := _first("hall")
		if hall and hall.complete and sim.why_not(me, "tech", step) == "":
			_cmd({"t": "research", "id": hall.id, "k": step})
			_plan.pop_front()
		return
	if sim.why_not(me, "building", step) == "":
		if _build_near(step, _home, 6, 16):
			_plan.pop_front()
	elif p.tier < Data.BUILDINGS[step].tier and not p.researching.has("tier%d" % Data.BUILDINGS[step].tier) and not p.techs.has("tier%d" % Data.BUILDINGS[step].tier):
		# the plan wants a later building first; insert the age-up
		_plan.push_front("tier%d" % Data.BUILDINGS[step].tier)


## Places a building on a free spot between rmin and rmax cells from `near` and sends the
## closest worker. Returns false if nothing fits or nobody can build.
func _build_near(role: String, near: Vector2, rmin: int, rmax: int) -> bool:
	if sim.why_not(me, "building", role) != "":
		return false
	var size: int = Data.BUILDINGS[role].size
	var c0 := MapData.cell_of(near)
	var spots: Array[Vector2i] = []
	for y in range(-rmax, rmax + 1):
		for x in range(-rmax, rmax + 1):
			var d := Vector2(x, y).length()
			if d >= rmin and d <= rmax:
				spots.append(c0 + Vector2i(x, y) - Vector2i(size / 2, size / 2))
	spots.sort_custom(func(a, b): return Vector2(a).distance_to(Vector2(c0)) < Vector2(b).distance_to(Vector2(c0)))
	if role == "tower":
		var mid := Vector2(sim.map.n, sim.map.n) * 0.5
		spots.sort_custom(func(a, b): return Vector2(a).distance_to(mid) < Vector2(b).distance_to(mid))
	var start := _rng.randi_range(0, mini(10, spots.size() - 1))
	for k in spots.size():
		var c: Vector2i = spots[(k + start) % spots.size()] if k < 12 else spots[k]
		if not _roomy(c, size):
			continue
		var builder := _builder(MapData.cell_centre(c))
		if builder == null:
			return false
		_cmd({"t": "build", "ids": [builder.id], "b": role, "cx": c.x, "cy": c.y})
		return true
	return false


## Leaves a lane around buildings and keeps them off the deposits.
func _roomy(c: Vector2i, size: int) -> bool:
	for y in range(-1, size + 1):
		for x in range(-1, size + 1):
			var q := c + Vector2i(x, y)
			if not sim.map.inside(q) or sim.occ[sim.map.idx(q)] != 0:
				return false
	for y in range(-2, size + 2):
		for x in range(-2, size + 2):
			var q := c + Vector2i(x, y)
			if sim.map.inside(q):
				var e: Ent = sim.ents.get(sim.occ[sim.map.idx(q)])
				if e and e.is_resource():
					return false
	return sim.can_place(_role_for_size(size), c)


func _role_for_size(size: int) -> String:
	return "hall" if size == 4 else ("barracks" if size == 3 else "house")


func _builder(near: Vector2) -> Ent:
	var best: Ent = null
	var best_d := INF
	for w in _mine("worker"):
		if w.order == Ent.BUILD:
			continue
		var d: float = w.pos.distance_to(near) + (8.0 if w.carry > 5 else 0.0)
		if d < best_d:
			best_d = d
			best = w
	return best


# --- army ----------------------------------------------------------------------------------

func _train() -> void:
	var p := _p()
	var reserve := 0
	if not _plan.is_empty() and str(_plan[0]).begins_with("tier"):
		reserve = 300
	for b in _mine():
		if not b.is_building() or not b.complete or b.role == "hall" or not Data.BUILDINGS[b.role].has("trains"):
			continue
		if b.queue.size() >= (2 if level > 0 else 1):
			continue
		if p.gold < reserve + 60:
			continue
		var options := []
		var weights := []
		for u in Data.BUILDINGS[b.role].trains:
			if sim.why_not(me, "unit", u) != "":
				continue
			var w: float = MIX.get(u, 1.0)
			if u == "siege" and sim.count(me, "siege") >= 3:
				w = 0.0
			if u == "champion" and sim.count(me, "champion") >= 4:
				w = 0.2
			if u == "caster" and sim.count(me, "caster") >= 4:
				w = 0.2
			if w > 0.0:
				options.append(u)
				weights.append(w)
		if options.is_empty():
			continue
		var total := 0.0
		for w in weights:
			total += w
		var roll := _rng.randf() * total
		var pick: String = options[0]
		for i in options.size():
			roll -= weights[i]
			if roll <= 0.0:
				pick = options[i]
				break
		_cmd({"t": "train", "id": b.id, "u": pick})
		if not b.has_rally:
			_cmd({"t": "rally", "ids": [b.id], "x": _rally_point().x, "y": _rally_point().y})


func _rally_point() -> Vector2:
	if _rally == Vector2.ZERO:
		var mid := Vector2.ONE * sim.map.size_m() * 0.5
		_rally = _home + (mid - _home).normalized() * 14.0
	return _rally


func _research() -> void:
	var p := _p()
	if level == 0 and _rng.randf() < 0.5:
		return
	if p.gold < 250 or (not _plan.is_empty() and str(_plan[0]).begins_with("tier") and p.gold < 600):
		return
	var order := ["gold1", "aether1", "melee1", "ranged1", "armor1", "worker_armor", "elite_spear", "elite_archer", "elite_infantry",
		"gold2", "aether2", "carry", "melee2", "ranged2", "armor2", "tower_range", "unique", "elite_cavalry", "elite_flyer", "elite_siege",
		"elite_caster", "melee3", "ranged3", "armor3", "tower_fortify"]
	for t in order:
		if sim.why_not(me, "tech", t) != "":
			continue
		var at: String = Data.TECHS[t].at
		for b in _mine(at):
			if b.complete and b.queue.size() < 1:
				_cmd({"t": "research", "id": b.id, "k": t})
				return


func _army() -> Array:
	var out := []
	for e in _mine():
		if e.is_unit() and e.role != "worker":
			out.append(e)
	return out


func _war() -> void:
	var army := _army()
	# defend: any enemy troops near our buildings
	var threat := Vector2.ZERO
	var threat_n := 0
	var blds := _my.filter(func(b): return b.is_building())
	for e in _foes:
		for b in blds:
			if b.edge_dist(e.pos) < 14.0:
				threat += e.pos
				threat_n += 1
				break
	if threat_n > 0:
		threat /= threat_n
		var ids := []
		for u in army:
			if u.order == Ent.IDLE or u.order == Ent.MOVE or (not _attacking and u.order == Ent.AMOVE) or u.pos.distance_to(_home) < 40.0:
				if u.order != Ent.ATTACK and u.engage == 0:
					ids.append(u.id)
		if not ids.is_empty():
			_cmd({"t": "amove", "ids": ids, "x": threat.x, "y": threat.y})
		return
	var supply := 0
	for u in army:
		supply += int(Data.UNITS[u.role].supply)
	if not _attacking:
		var broke: bool = _p().gold < 80 and supply >= 6 and sim.time > _next_attack
		if sim.time >= _next_attack and (supply >= WAVE_SIZE[level] + mini(_wave * 3, 18) or broke or _p().supply >= _p().cap - 2 and _p().cap >= Data.MAX_SUPPLY - 10):
			_attacking = true
			_wave += 1
		else:
			# gather idle troops at the rally point
			var ids := []
			for u in army:
				if u.order == Ent.IDLE and u.engage == 0 and u.pos.distance_to(_rally_point()) > 8.0:
					ids.append(u.id)
			if not ids.is_empty():
				_cmd({"t": "move", "ids": ids, "x": _rally_point().x, "y": _rally_point().y})
			return
	# attacking: send everyone at the nearest enemy building
	var tgt := _enemy_target()
	if tgt == null:
		_attacking = false
		return
	var ids := []
	for u in army:
		if u.order == Ent.IDLE or (u.order == Ent.AMOVE and u.goal.distance_to(tgt.pos) > 6.0) or u.order == Ent.MOVE:
			ids.append(u.id)
	if not ids.is_empty():
		_cmd({"t": "amove", "ids": ids, "x": tgt.pos.x, "y": tgt.pos.y})
	if supply < 5:
		_attacking = false
		_next_attack = sim.time + [150.0, 90.0, 60.0][level]


func _enemy_target() -> Ent:
	var best: Ent = null
	var best_d := INF
	var from := _home
	for e in sim.list:
		if e.alive and e.is_building() and sim.enemies(me, e.owner):
			var d := e.pos.distance_to(from) + (20.0 if e.role == "tower" else 0.0)
			if d < best_d:
				best_d = d
				best = e
	return best
