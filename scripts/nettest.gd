extends Node
## Automated online test (`tools/net_test.sh`, or the web build with `?pwnet=...`). Flags in
## `--net=` (comma separated):
##   host[=CODE]  open a room;  join=CODE  join one (on a computer CODE is the host's address)
##   start=N      host: start once N people are in the room (the other seats are AI)
##   bot          let an AI play my side (a guest's bot sends its commands to the host)
##   minutes=M    game minutes to play (default 4);  fast=X  host speed (default 4)
## At the end each side prints `NETTEST t=... | per player: alive supply buildings` from its
## own copy of the match; the host's and the guests' lines must match. Then `NETTEST done`.

var main: Node
var minutes := 4.0
var m: Match
var bot: AI
var printed := false
var _start_wait := 0.0
var _report := 0.0


func _ready() -> void:
	main = get_parent()
	Game.testing = true
	if Net.test_flag("minutes") != "":
		minutes = float(Net.test_flag("minutes"))
	Net.match_start.connect(_on_start, CONNECT_DEFERRED)
	Net.left.connect(func(r: String):
		print("NETTEST left: ", r)
		_quit())
	if Net.test_flag("host") != "":
		Net.host()
		print("NETTEST hosting ", Net.code)
	else:
		Net.join(Net.test_flag("join"))
		print("NETTEST joining ", Net.test_flag("join"))
	main.show_lobby()


func _on_start(_cfg: Dictionary) -> void:
	m = main.match_node
	if Net.is_host() and Net.test_flag("fast") != "1":
		m.net_speed = float(Net.test_flag("fast")) if Net.test_flag("fast") != "" else 4.0
	print("NETTEST started as player ", m.me, " guest=", m.guest)


func _humans() -> int:
	var n := 0
	for s in Net.slots:
		if s.kind == "human":
			n += 1
	return n


func _process(delta: float) -> void:
	if m == null:
		if Net.is_host() and not Net.in_match and _humans() >= maxi(1, int(Net.test_flag("start"))):
			_start_wait += delta
			if _start_wait > 1.0:
				Net.set_slot(2, "ai", 0)
				Net.start_match()
		return
	if not is_instance_valid(m):
		return
	if Net.test_flag("bot") != "" and bot == null and m.me >= 0:
		for e in m.sim.list:
			if e.owner == m.me and e.role == "hall":
				bot = AI.new(m.sim, m.me, 1)
				if m.guest:
					bot.send = Net.send_command
				else:
					m.ais.append(bot)
	if bot and m.guest:
		bot.update(delta)
	if m.sim.time >= _report:
		_report += 15.0
		print("NETTEST progress t=%.0f fps=%d" % [m.sim.time, Engine.get_frames_per_second()])
	if not printed and (m.sim.time >= minutes * 60.0 - 0.05 or m.sim.over):
		printed = true
		if Net.is_host():
			m.net_speed = 0.0
			Net.host_tick(m, true)
		print(_summary())
		if Net.is_host():
			get_tree().create_timer(3.0).timeout.connect(_quit)
		else:
			_quit.call_deferred()


func _summary() -> String:
	var line := "NETTEST t=%.1f ents=%d" % [m.sim.time, m.sim.list.size()]
	for i in m.sim.players.size():
		var p: Dictionary = m.sim.players[i]
		var b := 0
		var u := 0
		for e in m.sim.list:
			if e.owner == i:
				if e.is_building():
					b += 1
				else:
					u += 1
		line += " | %s %s alive=%s units=%d buildings=%d techs=%d" % [p.name, p.race, p.alive, u, b, p.techs.size()]
	return line


func _quit() -> void:
	print("NETTEST done")
	get_tree().quit()
