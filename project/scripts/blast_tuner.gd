extends Node
## DEV TOOLS - THE BLAST TUNER (F9 in the game): your hero fires one of its own drawn attacks again and
## again; move the glow or the beam with the arrow keys until it sits exactly right, for each direction.
##   F9 on / off    [ ]  the part (the glow at the hands, the beam's tail, head, body...)    , .  the attack
##   1 2 3 4  face down / up / left / right    arrows: move 1 pixel (Shift: 4)    Ctrl+S: save
## Saved into content/rom_specials.json next to the game (the game reads it at the next start).

var world
var on = false
var label: Label
var parts = []
var part_i = 0
var specials = []
var sp_i = 0
var t = 0
var saved_level = 0
var msg = ""

func _ready() -> void:
	var cl = CanvasLayer.new(); cl.layer = 30; add_child(cl)
	label = Label.new()
	label.position = Vector2(4, 60)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Color(1, 1, 0.6))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 3)
	label.visible = false
	cl.add_child(label)
	if str(Game.cfg.get("blast_tune", "")) != "" or Game.cfg.has("blast_tune"):
		call_deferred("toggle")

func _fighter():
	if world == null or world.locals.is_empty():
		return null
	return world.locals[0].fighter

func toggle() -> void:
	var f = _fighter()
	if f == null:
		return
	on = not on
	label.visible = on
	if on:
		saved_level = f.level
		f.level = maxi(f.level, 99)
		specials = []
		for sk in f.unlocked_skills():
			if sk.has("rom") and Content.rom_specials.has(str(sk["rom"])):
				specials.append(sk)
		sp_i = 0
		var want = str(Game.cfg.get("blast_tune", ""))
		for i in specials.size():
			if str(specials[i]["rom"]) == want:
				sp_i = i
		_pick_special()
	else:
		f.level = saved_level
		world.test_keys = []
	Game.cfg.erase("blast_tune")

func _pick_special() -> void:
	var f = _fighter()
	if specials.is_empty():
		msg = "This hero has none of the game's drawn attacks."
		return
	var u = f.unlocked_skills()
	f.skill_i = maxi(0, u.find(specials[sp_i]))
	var R: Dictionary = Content.rom_specials[str(specials[sp_i]["rom"])]
	parts = []
	if R.has("charge"):
		for k in ["small", "big"]:
			if R["charge"].has(k):
				parts.append("charge." + k)
	for k in R:
		var v = R[k]
		if v is Array and v.size() == 4 and v[0] is Array and v[0].size() == 2:
			parts.append(k)
	for k in ["pose_charge", "pose_fire"]:
		if R.has(k):
			parts.append(k)
	part_i = clampi(part_i, 0, maxi(0, parts.size() - 1))

func _arr(R: Dictionary, part: String) -> Array:
	if part.begins_with("charge."):
		return R["charge"][part.substr(7)]
	return R[part]

func _unhandled_input(ev: InputEvent) -> void:
	if not (ev is InputEventKey) or not ev.pressed:
		return
	var k: InputEventKey = ev
	if k.keycode == KEY_F9 and not k.echo:
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not on or specials.is_empty():
		return
	var f = _fighter()
	var R: Dictionary = Content.rom_specials[str(specials[sp_i]["rom"])]
	var part = parts[part_i] if parts.size() > 0 else ""
	var step = 4 if k.shift_pressed else 1
	var handled = true
	match k.keycode:
		KEY_BRACKETLEFT: part_i = (part_i - 1 + parts.size()) % parts.size()
		KEY_BRACKETRIGHT: part_i = (part_i + 1) % parts.size()
		KEY_COMMA: sp_i = (sp_i - 1 + specials.size()) % specials.size(); _pick_special()
		KEY_PERIOD: sp_i = (sp_i + 1) % specials.size(); _pick_special()
		KEY_1: f.dir = 0
		KEY_2: f.dir = 1
		KEY_3: f.dir = 2
		KEY_4: f.dir = 3
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			if part != "":
				var a: Array = _arr(R, part)
				var e: Array = a[f.dir]
				if part.begins_with("pose"):
					# [animation, frame, pixels to the right]: left/right move it, up/down change the frame
					if k.keycode == KEY_LEFT: e[2] = int(e[2]) - step
					elif k.keycode == KEY_RIGHT: e[2] = int(e[2]) + step
					elif k.keycode == KEY_UP: e[1] = int(e[1]) + 1
					else: e[1] = maxi(0, int(e[1]) - 1)
				else:
					if k.keycode == KEY_LEFT: e[0] = int(e[0]) - step
					elif k.keycode == KEY_RIGHT: e[0] = int(e[0]) + step
					elif k.keycode == KEY_UP: e[1] = int(e[1]) - step
					else: e[1] = int(e[1]) + step
		KEY_S:
			if k.ctrl_pressed:
				_save()
			else:
				handled = false
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _save() -> void:
	var p = Assets.exe_dir().path_join("content")
	DirAccess.make_dir_recursive_absolute(p)
	var fa = FileAccess.open(p.path_join("rom_specials.json"), FileAccess.WRITE)
	if fa:
		fa.store_string(JSON.stringify(Content.rom_specials, " "))
		fa.close()
		msg = "SAVED to content/rom_specials.json"
	else:
		msg = "could not save"

func _physics_process(_dt: float) -> void:
	if not on or world == null or specials.is_empty():
		return
	t += 1
	# fire, hold, let go, again (facing where you chose)
	var ph = t % 170
	world.test_keys = [{"sp": true, "tune": true}] if ph < 110 else [{"tune": true}]
	var f = _fighter()
	var R: Dictionary = Content.rom_specials[str(specials[sp_i]["rom"])]
	var part = parts[part_i] if parts.size() > 0 else ""
	var cur = _arr(R, part)[f.dir] if part != "" else []
	label.text = "BLAST TUNER (F9 off)   %s  [%s]\npart: %s   facing: %s   value: %s\n[ ] part   , . attack   1-4 facing   arrows move (Shift x4)   Ctrl+S save   %s" % [
		str(specials[sp_i].get("name", "")), str(specials[sp_i]["rom"]), part, ["DOWN", "UP", "LEFT", "RIGHT"][f.dir], str(cur), msg]
