extends Node
## DEV TOOLS - TOGETHER: several people editing the same world at once over LAN or Hamachi.
## One HOSTs, the others JOIN with the host's address. Everyone sees the others' mouse (with their name) and
## every tile, wall, foe, person, door, treasure, zone and event box they change, as they change it. Events,
## shops, loot, sprites and your own maps go across each time someone saves them. Everyone SAVEs their own copy.
## (A star: the host passes everything on. Port 7778, one up from the game's.)

signal changed            # the people list or the state changed (for the window)

const PORT = 7778
const COLORS = [Color(1, 0.45, 0.35), Color(0.4, 0.8, 1), Color(0.5, 1, 0.45), Color(1, 0.85, 0.3),
	Color(0.95, 0.5, 1), Color(0.4, 1, 0.9), Color(1, 0.65, 0.2), Color(0.75, 0.75, 1)]
const WATCH = ["content", "content/sprites", "mods/maps/custom"]
const FILE_EXT = ["json", "png", "txt", "bin"]

var dev                    # the dev tools
var peer: ENetMultiplayerPeer
var hosting = false
var my_name = "MAKER"
var people = {}            # id -> {name, color index, key, x, y, tool, seen}
var my_id = 0
var applying = false       # while putting someone else's change in (so it isn't sent back)
var state = ""             # shown in the window
var _mt = {}               # watched file -> modified time
var _watch_t = 0.0
var _cur_t = 0.0
var _last_cur = Vector3(-1, -1, -1)
var _reload_t = -1.0
var cursors: Node2D

func _ready() -> void:
	cursors = Node2D.new()
	cursors.z_index = 210
	cursors.draw.connect(_draw_cursors)
	dev.add_child(cursors)

func _exit_tree() -> void:
	leave()
	if is_instance_valid(cursors):
		cursors.queue_free()

func active() -> bool:
	return peer != null and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED

# ------------------------------------------------------------------ connecting
func host(nm: String) -> bool:
	leave()
	my_name = _clean_name(nm)
	peer = ENetMultiplayerPeer.new()
	if peer.create_server(PORT, 16) != OK:
		peer = null
		state = "Could not open port %d (is another copy hosting?)" % PORT
		changed.emit()
		return false
	hosting = true
	my_id = 1
	people = {1: _person(my_name, 0)}
	peer.peer_connected.connect(func(_id): pass)
	peer.peer_disconnected.connect(_gone)
	_snap_files()
	state = "Hosting on port %d. Others JOIN with your address (Hamachi: your Hamachi IPv4)." % PORT
	changed.emit()
	return true

func join(ip: String, nm: String) -> bool:
	leave()
	my_name = _clean_name(nm)
	peer = ENetMultiplayerPeer.new()
	if peer.create_client(ip.strip_edges(), PORT) != OK:
		peer = null
		state = "Could not connect to %s" % ip
		changed.emit()
		return false
	hosting = false
	peer.peer_connected.connect(func(id):
		if id == 1:
			my_id = peer.get_unique_id()
			_send(1, {"t": "hi", "name": my_name})
			state = "Connected - getting the host's world..."
			changed.emit())
	peer.peer_disconnected.connect(func(id):
		if id == 1:
			_host_gone.call_deferred())      # (not inside the peer's own poll)
	state = "Connecting to %s..." % ip
	changed.emit()
	return true

func _host_gone() -> void:
	leave()
	state = "The host left. (Your copy stays - SAVE to keep it.)"
	dev._say(state)
	changed.emit()

func leave() -> void:
	if peer:
		peer.close()
	peer = null
	hosting = false
	people.clear()
	if is_instance_valid(cursors):
		cursors.queue_redraw()
	state = "Not connected."
	changed.emit()

func _gone(id: int) -> void:
	if people.has(id):
		dev._say("%s left." % str(people[id]["name"]))
	people.erase(id)
	_broadcast({"t": "who", "people": people}, 0)
	changed.emit()

func _person(nm: String, ci: int) -> Dictionary:
	return {"name": nm, "color": ci, "key": "", "x": 0.0, "y": 0.0, "tool": "", "seen": Time.get_ticks_msec()}

static func _clean_name(s: String) -> String:
	s = s.strip_edges().to_upper()
	if s == "":
		s = "MAKER"
	return s.substr(0, 16)

# ------------------------------------------------------------------ sending
func _send(to: int, msg: Dictionary) -> void:
	if peer == null:
		return
	peer.set_target_peer(to)
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_UNRELIABLE if msg["t"] == "cur" else MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.transfer_channel = 1 if msg["t"] == "cur" else 0
	peer.put_packet(var_to_bytes(msg))

## to everyone (from the host: all the others except 'skip'; from someone else: to the host, who passes it on)
func _broadcast(msg: Dictionary, skip: int) -> void:
	if peer == null:
		return
	if not hosting:
		_send(1, msg)
		return
	for id in people:
		if id != 1 and id != skip:
			_send(id, msg)

## the dev tools call these after each change
func sent_cells(key: String, stroke: Dictionary) -> void:
	if not active() or applying:
		return
	var ch = {}
	for i in stroke:
		ch[int(i)] = stroke[i][1]
	_broadcast({"t": "cells", "key": key, "ch": ch, "from": my_id}, 0)

func sent_objects(key: String) -> void:
	if not active() or applying:
		return
	var p = Mods.patch(key)
	var o = {}
	for k in Mods.PATCH_KEYS:
		if k != "cells":
			o[k] = p[k]
	_broadcast({"t": "obj", "key": key, "o": o, "from": my_id}, 0)

# ------------------------------------------------------------------ every frame
func _process(dt: float) -> void:
	if peer == null:
		return
	peer.poll()
	if peer == null:
		return
	while peer and peer.get_available_packet_count() > 0:
		var from = peer.get_packet_peer()
		var raw = peer.get_packet()
		var m = bytes_to_var(raw)       # (no objects can come across this way)
		if m is Dictionary and m.has("t"):
			_got(from, m)
	if not active():
		return
	# my mouse, ten times a second when it moves
	_cur_t += dt
	if _cur_t > 0.1 and dev.tab == "MAP":
		_cur_t = 0.0
		var w = dev._world_of(dev.get_viewport().get_mouse_position())
		var c = Vector3(round(w.x), round(w.y), hash(dev.key))
		if c != _last_cur:
			_last_cur = c
			var me = {"t": "cur", "key": dev.key, "x": w.x, "y": w.y, "tool": dev.tool, "from": my_id}
			if hosting:
				_got_cur(1, me)
			_broadcast(me, 0)
	# saved files
	_watch_t += dt
	if _watch_t > 2.0:
		_watch_t = 0.0
		_check_files()
	if _reload_t >= 0.0:
		_reload_t -= dt
		if _reload_t < 0.0:
			_reload_content()
	cursors.visible = dev.tab == "MAP"
	cursors.queue_redraw()

func _got(from: int, m: Dictionary) -> void:
	var t = str(m["t"])
	if hosting:
		if t == "hi":
			var used = []
			for id in people:
				used.append(int(people[id]["color"]))
			var ci = 0
			while ci in used and ci < COLORS.size() - 1:
				ci += 1
			people[from] = _person(_clean_name(str(m.get("name", ""))), ci)
			_send(from, _everything(from))
			_broadcast({"t": "who", "people": people}, 0)
			dev._say("%s joined." % str(people[from]["name"]))
			changed.emit()
			return
		if not people.has(from):
			return
		m["from"] = from          # (nobody can speak for someone else)
		_broadcast(m, from)
	match t:
		"who":
			people = {}
			var src: Dictionary = m.get("people", {})
			for id in src:
				people[int(id)] = src[id]
			state = "Editing together with %d other(s)." % maxi(0, people.size() - 1)
			changed.emit()
		"all":
			_take_everything(m)
		"cur":
			_got_cur(int(m.get("from", from)), m)
		"cells":
			_got_cells(str(m.get("key", "")), m.get("ch", {}))
		"obj":
			_got_objects(str(m.get("key", "")), m.get("o", {}))
		"file":
			_got_file(str(m.get("path", "")), m.get("data", PackedByteArray()))

func _got_cur(id: int, m: Dictionary) -> void:
	if not people.has(id):
		return
	var p: Dictionary = people[id]
	p["key"] = str(m.get("key", "")); p["x"] = float(m.get("x", 0)); p["y"] = float(m.get("y", 0))
	p["tool"] = str(m.get("tool", "")); p["seen"] = Time.get_ticks_msec()

func _got_cells(key: String, ch) -> void:
	if not ch is Dictionary or key == "":
		return
	applying = true
	if key == dev.key and not dev.area.is_empty():
		var n = int(dev.area["tw"]) * int(dev.area["th"])
		var changes = {}
		for i in ch:
			var v = ch[i]
			if int(i) >= 0 and int(i) < n and v is Array and v.size() == 6:
				changes[int(i)] = [v, v]
		dev._write(changes, 1)
		dev._changes = []
		dev.dirty = true
	else:
		var p = Mods.patch(key)
		var a = Assets.area(key)
		var tw = int(a.get("tw", 0))
		if tw > 0:
			for i in ch:
				p["cells"]["%d,%d" % [int(i) % tw, int(i) / tw]] = ch[i]
			Assets._areas.erase(key)
	applying = false

func _got_objects(key: String, o) -> void:
	if not o is Dictionary or key == "":
		return
	applying = true
	var p = Mods.patch(key)
	for k in o:
		if k in Mods.PATCH_KEYS and k != "cells" and o[k] is Array:
			p[k] = o[k]
	if key == dev.key:
		dev._rebuild_world()
		dev.selected = {}
	else:
		Game.planet.build_land(0, 1)
	applying = false

# ------------------------------------------------------------------ joining: the host's whole world
func _everything(to: int) -> Dictionary:
	var md = Mods.maps_dir()
	var d = DirAccess.open(md)
	if d:
		for f in d.get_files():
			if f.ends_with(".json"):
				var k = _key_of(f.get_basename())
				if k != "":
					Mods.patch(k)
	var files = {}
	for rel in _watched_files():
		var b = FileAccess.get_file_as_bytes(Assets.exe_dir().path_join(rel))
		if b.size() <= 4 * 1024 * 1024:
			files[rel] = b
	return {"t": "all", "patches": Mods._patches, "files": files, "people": people, "you": to}

static func _key_of(fk: String) -> String:
	if fk.begins_with("custom_"):
		return "custom/" + fk.substr(7)
	if fk.begins_with("land_"):
		return fk.replace("_", "/")
	return ""

func _take_everything(m: Dictionary) -> void:
	Mods.backup(true)          # (what you had is kept in HISTORY)
	applying = true
	var files: Dictionary = m.get("files", {})
	for rel in files:
		_write_file(str(rel), files[rel])
	Mods.reload()
	var pt: Dictionary = m.get("patches", {})
	for k in pt:
		if pt[k] is Dictionary:
			var p: Dictionary = pt[k]
			Mods._fill_patch(p)
			Mods._patches[str(k)] = p
	Assets._areas.clear()
	Assets.reload_sets()
	dev._packs_changed()
	applying = false
	var src: Dictionary = m.get("people", {})
	people = {}
	for id in src:
		people[int(id)] = src[id]
	_snap_files()
	state = "Editing together with %d other(s). (Your own edits from before are in CHECK > HISTORY.)" % maxi(0, people.size() - 1)
	dev._say("Joined - you have the host's world now.")
	changed.emit()

# ------------------------------------------------------------------ saved files (events, shops, sprites, own maps...)
func _watched_files() -> Array:
	var out = []
	for w in WATCH:
		var d = DirAccess.open(Assets.exe_dir().path_join(w))
		if d == null:
			continue
		for f in d.get_files():
			if f.get_extension().to_lower() in FILE_EXT:
				out.append(w.path_join(f))
	return out

func _snap_files() -> void:
	_mt.clear()
	for rel in _watched_files():
		_mt[rel] = FileAccess.get_modified_time(Assets.exe_dir().path_join(rel))

func _check_files() -> void:
	for rel in _watched_files():
		var t = FileAccess.get_modified_time(Assets.exe_dir().path_join(rel))
		if _mt.get(rel, -1) != t:
			_mt[rel] = t
			var b = FileAccess.get_file_as_bytes(Assets.exe_dir().path_join(rel))
			if b.size() <= 4 * 1024 * 1024:
				_broadcast({"t": "file", "path": rel, "data": b, "from": my_id}, 0)

static func safe_path(rel: String) -> bool:
	if ".." in rel or rel.begins_with("/") or "\\" in rel or ":" in rel:
		return false
	if not rel.get_extension().to_lower() in FILE_EXT:
		return false
	return rel.get_base_dir() in WATCH

func _write_file(rel: String, data) -> bool:
	if not safe_path(rel) or not data is PackedByteArray:
		return false
	var dest = Assets.exe_dir().path_join(rel)
	DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
	var fa = FileAccess.open(dest, FileAccess.WRITE)
	if fa == null:
		return false
	fa.store_buffer(data)
	fa.close()
	_mt[rel] = FileAccess.get_modified_time(dest)
	return true

func _got_file(rel: String, data) -> void:
	if _write_file(rel, data):
		_reload_t = 0.5           # (several files often come together)
		dev._say("Got %s from the others." % rel.get_file())

func _reload_content() -> void:
	applying = true
	var keep = Mods._patches.duplicate()
	Mods.reload()
	for k in keep:
		Mods._patches[k] = keep[k]
	Assets._areas.clear()
	Assets.reload_sets()
	dev._packs_changed()
	applying = false

# ------------------------------------------------------------------ the others' mice
func _draw_cursors() -> void:
	var now = Time.get_ticks_msec()
	var z = dev.cam.zoom.x
	var font = ThemeDB.fallback_font
	for id in people:
		if int(id) == my_id:
			continue
		var p: Dictionary = people[id]
		if str(p.get("key", "")) != dev.key or now - int(p.get("seen", 0)) > 30000:
			continue
		var c: Color = COLORS[int(p.get("color", 0)) % COLORS.size()]
		var at = Vector2(float(p["x"]), float(p["y"]))
		var s = 1.0 / z
		var pts = PackedVector2Array([at, at + Vector2(0, 14) * s, at + Vector2(4, 10) * s, at + Vector2(9, 9) * s])
		cursors.draw_colored_polygon(pts, c)
		cursors.draw_polyline(pts + PackedVector2Array([at]), Color(0, 0, 0, 0.8), s)
		cursors.draw_rect(Rect2(int(at.x / 8) * 8, int(at.y / 8) * 8, 8, 8), Color(c, 0.8), false, s)
		var label = "%s (%s)" % [str(p["name"]), str(p.get("tool", "")).to_lower()]
		cursors.draw_string(font, at + Vector2(10, 14) * s, label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(maxf(6.0, 11.0 * s)), c)
