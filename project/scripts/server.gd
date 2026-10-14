extends Node
## The dedicated server: runs the world (every enemy, every area someone is in) with no player of its own.

var t = 0
var status: Label
var log_lines = []

func _ready() -> void:
	Game.toast.connect(func(text, _c): _log(text))
	get_tree().set_auto_accept_quit(false)

func _log(s: String) -> void:
	var line = "%s  %s" % [Time.get_time_string_from_system(), s]
	print("[server] ", line)
	log_lines.append(line)
	if log_lines.size() > 10:
		log_lines.pop_front()

func _physics_process(_dt: float) -> void:
	Game.host_step([])
	t += 1
	if t % 30 == 0 and status:
		var lines = ["WORLD: %s (%s)   PORT %d" % [Game.planet.title, Game.world_id(), Game.PORT],
			"Players JOIN with this PC's Hamachi IP. Close this window to stop. (Each player keeps their own fighter.)", "", "PLAYING NOW: %d" % Game.remote_states.size()]
		for pid in Game.remote_states:
			var st: Dictionary = Game.remote_states[pid]
			lines.append("  %s  LV %d  - %s" % [st.get("name", "?"), int(st.get("lvl", 1)), Game.planet.nodes[clampi(int(st.get("node", 0)), 0, Game.planet.nodes.size() - 1)]["name"]])
		lines.append("")
		lines.append_array(log_lines)
		status.text = "\n".join(PackedStringArray(lines))
	if t % 3600 == 0:
		_log("%d min up, %d playing" % [t / 3600, Game.remote_states.size()])

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
