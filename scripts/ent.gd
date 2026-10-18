class_name Ent
extends RefCounted
## Anything on the map that has an id: a unit, a building or a resource deposit. Plain data;
## Sim moves it, View draws it. On a guest's computer the fields come from the host's
## snapshots instead (Net.apply_snapshot).

enum { UNIT, BUILDING, RESOURCE }
enum { IDLE, MOVE, AMOVE, ATTACK, GATHER, RETURN, BUILD, FOLLOW }
enum { A_IDLE, A_WALK, A_ATTACK, A_WORK }

var id := 0
var cat := UNIT
var role := ""
var owner := -1
var pos := Vector2.ZERO
var prev_pos := Vector2.ZERO
var facing := 0.0
var hp := 1.0
var max_hp := 1.0
var radius := 0.5
var alive := true
var flying := false
var elite := false

# orders (units)
var order := IDLE
var target := 0                   # ent id the order is about
var goal := Vector2.ZERO
var engage := 0                   # attack-move / idle: the enemy currently fought
var path := PackedVector2Array()
var path_i := 0
var path_goal := Vector2(-999, -999)
var repath_t := 0.0
var stuck_t := 0.0
var cd := 0.0
var scan_t := 0.0
var anim := A_IDLE
var atk_n := 0                    # counts attacks, so viewers can show each shot
var atk_target := 0               # who the last attack went to
var carry := 0
var carry_type := ""
var gather_t := 0.0
var res_target := 0
var last_hit_t := -99.0

# buildings
var cell := Vector2i.ZERO
var size := 1
var built := 1.0                  # construction progress 0..1
var complete := true
var queue: Array = []             # {"kind": "unit"/"tech", "id": String, "t": float, "total": float, "reserved": bool}
var rally := Vector2.ZERO
var has_rally := false

# resources
var amount := 0


func is_unit() -> bool:
	return cat == UNIT


func is_building() -> bool:
	return cat == BUILDING


func is_resource() -> bool:
	return cat == RESOURCE


## The building's or deposit's footprint in metres.
func rect() -> Rect2:
	if cat == UNIT:
		return Rect2(pos - Vector2(radius, radius), Vector2(radius, radius) * 2.0)
	return Rect2(Vector2(cell) * Data.CELL, Vector2(size, size) * Data.CELL)


## Distance from a point to this entity's edge.
func edge_dist(p: Vector2) -> float:
	if cat == UNIT:
		return maxf(0.0, p.distance_to(pos) - radius)
	var r := rect()
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dy).length()
