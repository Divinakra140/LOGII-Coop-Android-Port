extends PanelContainer
## DEV TOOLS - HELP - FIRST MAP: a guide that walks you through making your first map, step by step.
## Each step ticks itself off when you have done it (or press NEXT to skip it).

var dev
var step = 0
var my_map = ""            # the map made in step 1
var title: Label
var body: Label
var done_lab: Label
var _t = 0.0
var _wait = -1.0           # a moment on the tick before the next step

const STEPS = [
	["MAKE A MAP OF YOUR OWN", "Press NEW MAP on the bar at the top. Give it a name (like myhouse) and a size and press OK. It starts filled with the tile you picked last."],
	["PAINT THE GROUND", "Choose TILE on the second bar. Pick a tile in the palette on the right (the wheel scrolls it), then click and drag on your map. Ctrl+Z undoes. SMART paints and fits the edges for you."],
	["WALLS", "Choose WALL and drag over the places nobody may walk on - they turn red (WALLS on the top bar shows them). GROUND makes a place walkable again. Every edge of the map is a wall by itself."],
	["SOMEONE TO TALK TO", "Choose PERSON. On the right type a name and what they say (one line each), then click on your map to put them there. EVENTS can make them do much more later."],
	["A WAY IN", "Go to EARTH in the map list (top left). Choose DOOR and drag a small box where the door should be (a house's door, a cave...). Then choose your map in the list and click where you arrive. Make a door back the same way!"],
	["SAVE", "Press SAVE (or Ctrl+S). Everything goes into the mods folder next to the game - it stays when the game is imported again. Every save is also kept in CHECK > HISTORY."],
	["TRY IT", "Press PLAY HERE on Earth near your door and walk in. F10 in the game brings you back here. That's it - you made a map!\nNext: CHECK finds mistakes, SHARE turns your work into a mod for others, TOGETHER lets friends build with you."],
]

func _ready() -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.2, 0.95); sb.border_color = Color(1, 0.8, 0.3); sb.set_border_width_all(2)
	sb.set_content_margin_all(8); sb.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", sb)
	custom_minimum_size = Vector2(330, 0)
	var v = VBoxContainer.new(); add_child(v)
	title = Label.new(); title.add_theme_font_size_override("font_size", 12); title.add_theme_color_override("font_color", Color(1, 0.85, 0.35)); v.add_child(title)
	body = Label.new(); body.autowrap_mode = TextServer.AUTOWRAP_WORD; body.custom_minimum_size = Vector2(310, 0); body.add_theme_font_size_override("font_size", 10); v.add_child(body)
	done_lab = Label.new(); done_lab.add_theme_font_size_override("font_size", 11); done_lab.add_theme_color_override("font_color", Color(0.5, 1, 0.5)); v.add_child(done_lab)
	var h = HBoxContainer.new(); v.add_child(h)
	var bb = Button.new(); bb.text = "BACK"; bb.pressed.connect(func(): _goto(step - 1)); h.add_child(bb)
	var nb = Button.new(); nb.text = "NEXT"; nb.pressed.connect(func(): _goto(step + 1)); h.add_child(nb)
	var cb = Button.new(); cb.text = "CLOSE"; cb.pressed.connect(queue_free); h.add_child(cb)
	_goto(0)

func _goto(i: int) -> void:
	if i >= STEPS.size():
		dev._say("The first-map guide is done. HELP > FIRST MAP starts it again.")
		queue_free()
		return
	step = clampi(i, 0, STEPS.size() - 1)
	title.text = "FIRST MAP  %d/%d: %s" % [step + 1, STEPS.size(), STEPS[step][0]]
	body.text = STEPS[step][1]
	done_lab.text = ""
	_wait = -1.0
	if step == 0 and dev.key.begins_with("custom/"):
		my_map = dev.key
	if step >= 1 and dev.tab != "MAP":
		dev._show_tab("MAP")

## has this step been done?
func passed() -> bool:
	match step:
		0:
			if dev.key.begins_with("custom/") and not Mods.custom_maps().is_empty():
				my_map = dev.key
				return true
		1:
			return dev.key == my_map and dev.undo.any(func(u): return u.has("cells"))
		2:
			if my_map == "":
				return false
			for c in Mods.patch(my_map)["cells"].values():
				if c is Array and c.size() == 6 and int(c[5]) & 1 == 0:
					return true
		3:
			return my_map != "" and not Mods.patch(my_map)["people_add"].is_empty()
		4:
			if my_map == "":
				return false
			for d in Mods.patch("land/0/0")["doors_add"]:
				if str(d.get("to", "")) == my_map:
					return true
			for d in Mods.patch(my_map)["doors_add"]:
				if str(d.get("to", "")) == "land/0/0":
					return true
		5:
			return my_map != "" and not dev.dirty and FileAccess.file_exists(Mods.maps_dir().path_join(Mods.file_key(my_map) + ".json"))
	return false

func _process(dt: float) -> void:
	if _wait >= 0.0:
		_wait -= dt
		if _wait < 0.0:
			_goto(step + 1)
		return
	_t += dt
	if _t < 0.4:
		return
	_t = 0.0
	if step < STEPS.size() - 1 and passed():
		done_lab.text = "DONE!"
		_wait = 1.2
