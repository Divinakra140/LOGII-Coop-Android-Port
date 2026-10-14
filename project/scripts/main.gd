extends Node
## Start: import the game once, pick a fighter and a planet, play solo / host / join (LAN or Hamachi).

var ui: Control
var world: Node
var status: Label
var ip_edit: LineEdit
var name_edit: LineEdit
var seed_edit: LineEdit
var char_pick: OptionButton
var adv_pick: OptionButton
var diff_pick: OptionButton
var locals_pick: OptionButton
var char2_pick: OptionButton
var name2_edit: LineEdit
var p2_row: HBoxContainer
var lobby_label: Label
var start_btn: Button
var file_dialog: FileDialog
var music_label: Label
var fetch_ip: LineEdit
var test = {}
## the game's own lands, joined edge to edge (needs the building kit from the import)
const LANDS = [[0, "EARTH - THE WHOLE PLANET"], [4, "WEST CITY & TRICERATOPS JUNGLE"], [8, "NORTHERN MOUNTAINS"], [2, "EAST DISTRICT 439"], [7, "SOUTHERN CONTINENT"],
	[10, "GINGERTOWN"], [3, "NORTHERN WASTELANDS"], [12, "TROPICAL ISLANDS"], [13, "SNOWY HIGHLANDS"], [6, "CAPSULE CORP & NEW NAMEK"]]
var test_t = 0

func _ready() -> void:
	print("[main] ready, import found: ", Assets.base_dir)
	get_window().size_changed.connect(_fit_view)
	_fit_view()
	for a in OS.get_cmdline_user_args():
		var kv = a.trim_prefix("--").split("=")
		test[kv[0]] = kv[1] if kv.size() > 1 else "1"
	Game.started.connect(_on_started)
	if OS.has_feature("android"):
		# your own songs in Music/LoG2Coop: Android asks once for "music and audio"
		get_tree().on_request_permissions_result.connect(_on_permission)
		if Assets.audio_allowed():
			_make_music_dirs()
		else:
			OS.request_permissions()
	Game.lobby_changed.connect(_refresh_lobby)
	if test.has("server"):
		_start_server()
		return
	if not Assets.ready_to_play():
		_import_screen()
	else:
		Assets.load_data()
		Assets.start_sharing()   # a phone on the same network can get the game files from this PC
		if test.has("devtools"):
			_dev_tools()
		elif test.has("autotest"):
			_start_test()
		else:
			_menu()
			if test.has("lmp"):
				_local_multiplayer()
			elif test.has("gmp"):
				_global_multiplayer()
			elif test.has("find"):
				_find_games()
			if test.has("find"):
				_find_games()

func _on_permission(permission: String, granted: bool) -> void:
	if permission == Assets.ANDROID_AUDIO and granted:
		_make_music_dirs()
		Music._files.clear()       # songs looked for before are looked for again
		var playing = Music.current
		Music.current = ""
		Music.play(playing)        # (your title song at once)
		Sfx.reload()
		if is_instance_valid(music_label):
			music_label.text = _music_text()

func _make_music_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(Assets.sounds_dir())

func _music_text() -> String:
	if OS.has_feature("android"):
		return "MUSIC: put your own songs in  %s  (Internal storage > Music > LoG2Coop). Name them title.ogg, field.ogg, cave.ogg, lair.ogg, boss.ogg and victory.ogg (or .mp3) to replace those songs in the game. Optional: a file named after an area (the name that pops up when you walk in, like \"west city.ogg\") plays only in that area and takes priority over the base soundtrack. Sound effects go in  %s" % [Assets.music_dir(), Assets.sounds_dir()] + ("" if Assets.audio_allowed() else "  (Allow MUSIC AND AUDIO when Android asks, or in the app's settings.)")
	return "MUSIC: put your own songs in the music folder (title, field, cave, lair, boss, victory .ogg / .mp3, or a place's name like \"west city.ogg\")."

func _clear() -> void:
	if ui:
		ui.queue_free()
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui)
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(bg)

func _box() -> VBoxContainer:
	var v = VBoxContainer.new()
	v.position = Vector2(12, 8)
	v.size = Vector2(456, 254)
	v.add_theme_constant_override("separation", 2)
	ui.add_child(v)
	return v

func _label(parent: Node, t: String, size = 8, col = Color(1, 1, 1)) -> Label:
	var l = Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size = Vector2(450, 0)
	parent.add_child(l)
	return l

func _button(parent: Node, t: String, f: Callable) -> Button:
	var b = Button.new()
	b.text = t
	b.add_theme_font_size_override("font_size", 8)
	b.pressed.connect(f)
	parent.add_child(b)
	return b

# ------------------------------------------------------------------ first start: your game
func _import_screen() -> void:
	_clear()
	var v = _box()
	_label(v, "LEGACY OF GOKU II - CO-OP (GODOT)", 12, Color(1, 0.85, 0.3))
	if Assets.base_dir != "" and Assets.import_version() < Assets.IMPORT_VERSION:
		_label(v, "NEW: each land is ONE world you walk through (roads join its parts), and the heroes' special moves use the game's own effects. Your game is read once more (a minute or two). Your fighters and the recorded music are kept.", 8, Color(0.6, 1, 0.8))
	_label(v, "First start: choose your own Legacy of Goku II (USA) .gba file. Its pictures, maps and enemies are read from it once (about a minute) - nothing of the game comes with this download.", 8)
	_button(v, "CHOOSE MY GAME...", _pick_rom)
	status = _label(v, "", 8, Color(0.7, 1, 0.7))
	# a phone / tablet: the files can also come from your PC (where the game was read and the music recorded)
	_label(v, "OR FROM A PC: open the game on your PC (it must have read your game), connect both to the same Wi-Fi, type the PC's address (shown in the PC's menu) and press GET:", 7, Color(0.75, 0.85, 1))
	var hf = HBoxContainer.new()
	v.add_child(hf)
	fetch_ip = LineEdit.new()
	fetch_ip.placeholder_text = "PC address, e.g. 192.168.1.20"
	fetch_ip.text = str(Game.cfg.get("ip", ""))
	fetch_ip.custom_minimum_size = Vector2(170, 0)
	fetch_ip.add_theme_font_size_override("font_size", 8)
	hf.add_child(fetch_ip)
	_button(hf, "GET THE GAME FILES FROM MY PC", func(): if fetch_ip.text.strip_edges() != "": Assets.start_fetch(fetch_ip.text.strip_edges()))
	if test.has("fetch"):
		Assets.start_fetch(test["fetch"])
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.gba ; GBA game"])
	file_dialog.size = Vector2i(360, 200)
	if OS.has_feature("android"):
		# Android's own file picker (it knows no ".gba" type: every file is shown, the game is checked after)
		file_dialog.use_native_dialog = true
		file_dialog.filters = PackedStringArray()
	file_dialog.file_selected.connect(_rom_chosen)
	ui.add_child(file_dialog)
	# a game file (.gba) next to the program is found by itself
	var d = DirAccess.open(Assets.exe_dir())
	if d:
		for f in d.get_files():
			if f.to_lower().ends_with(".gba"):
				_rom_chosen(Assets.exe_dir().path_join(f))
				return

func _pick_rom() -> void:
	print("[main] CHOOSE MY GAME")
	file_dialog.popup_centered()

func _rom_chosen(path: String) -> void:
	print("[main] game chosen: ", path)
	if OS.has_feature("android"):
		# the picker hands a file the importer cannot open itself: a copy goes into the game's own folder
		var gba = FileAccess.get_file_as_bytes(path)
		print("[main] read ", gba.size(), " bytes (", FileAccess.get_open_error(), ")")
		if gba.size() < 0x100000 or gba.slice(0xA0, 0xAC).get_string_from_ascii().strip_edges() == "":
			status.text = "That file could not be read as a GBA game - choose your Legacy of Goku II (USA) .gba (not a .zip)."
			return
		var copy = Assets.exe_dir().path_join("game.gba")
		if path != copy:
			var fa = FileAccess.open(copy, FileAccess.WRITE)
			if fa == null:
				status.text = "Could not copy the game file into the app's folder."
				return
			fa.store_buffer(gba)
			fa.close()
		path = copy
	status.text = "Reading your game... (about a minute)"
	Assets.start_import(path)
	set_process(true)

func _process(_dt: float) -> void:
	if Assets.fetch_thread != null and is_instance_valid(status):
		status.text = Assets.fetch_status
	if Assets.fetch_result >= 0:
		var r = Assets.fetch_result
		Assets.fetch_result = -1
		if r == 0 and Assets.ready_to_play():
			print("[test] fetched the game files: ", Assets.base_dir)
			if test.has("fetch"):
				get_tree().quit()
				return
			Assets.load_data()
			Sfx.reload()
			_menu()
			return
		elif is_instance_valid(status):
			status.text = Assets.fetch_status
	if Assets.import_thread != null and Assets.import_result >= 0:
		if Assets.import_result == 0:
			Assets.import_thread = null
			Assets.load_data()
			Sfx.reload()
			Assets.start_sharing()
			_menu()
		else:
			status.text = "That did not work: is it the USA Legacy of Goku II game?\n" + Assets.import_log.right(300)
			Assets.import_thread = null

# ------------------------------------------------------------------ the menu
func _menu() -> void:
	_global_back = Callable()
	_clear()
	Music.play("title")
	Music.prepare(["field", "cave", "lair", "boss", "victory"])
	var v = _box()
	var head = HBoxContainer.new(); head.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(head)
	var logo = TextureRect.new(); logo.texture = preload("res://art/puni_logo.png")
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(34, 34); head.add_child(logo)
	var tv = VBoxContainer.new(); head.add_child(tv)
	var tl = _label(tv, "LEGACY OF GOKU II - CO-OP", 12, Color(1, 0.85, 0.3)); tl.custom_minimum_size = Vector2(0, 0); tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	var by = HBoxContainer.new(); tv.add_child(by)
	var bl = _label(by, "by Puni Puni", 8, Color(0.85, 0.75, 1)); bl.custom_minimum_size = Vector2(0, 0); bl.autowrap_mode = TextServer.AUTOWRAP_OFF
	var yt = Button.new(); yt.text = "YOUTUBE: @PuniPuni2026"; yt.add_theme_font_size_override("font_size", 7)
	yt.add_theme_color_override("font_color", Color(1, 0.45, 0.45)); yt.tooltip_text = "youtube.com/@PuniPuni2026"
	yt.pressed.connect(func(): OS.shell_open("https://www.youtube.com/@PuniPuni2026"))
	by.add_child(yt)
	Game.cfg.erase("story")
	Game.cfg.erase("start_at")
	if not Content.story.is_empty():
		_story_row(v)
	var h = HBoxContainer.new()
	v.add_child(h)
	char_pick = OptionButton.new()
	for i in Assets.CHARACTERS.size():
		char_pick.add_item(Assets.CHARACTERS[i], i)
	char_pick.select(int(Game.cfg["character"]))
	char_pick.add_theme_font_size_override("font_size", 8)
	h.add_child(char_pick)
	adv_pick = OptionButton.new()
	adv_pick.add_item("PLANET GATORRA (adventure)", 0)
	adv_pick.add_item("PLANET DUNARA (adventure)", 1)
	adv_pick.add_item("RANDOM PLANET (seed)", 2)
	if Assets.has_kit():
		var i = 3
		for l in LANDS:
			adv_pick.add_item(("THE ORIGINAL: " if l[0] > 0 else "") + l[1], i)
			i += 1
		adv_pick.select(3)      # EARTH first
	adv_pick.add_theme_font_size_override("font_size", 8)
	adv_pick.fit_to_longest_item = false      # (the longest planet name made the whole menu wider than the screen)
	adv_pick.clip_text = true
	adv_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(adv_pick)
	diff_pick = OptionButton.new()
	for t in ["EASY", "NORMAL", "HARD"]:
		diff_pick.add_item(t)
	diff_pick.select(1)
	diff_pick.custom_minimum_size.x = DIFF_W
	diff_pick.add_theme_font_size_override("font_size", 8)
	h.add_child(diff_pick)
	var mid = HBoxContainer.new()       # (name + seed, players) | PLAY
	v.add_child(mid)
	var left = VBoxContainer.new()
	left.add_theme_constant_override("separation", 2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_child(left)
	var h2 = HBoxContainer.new()
	left.add_child(h2)
	name_edit = LineEdit.new()
	name_edit.text = str(Game.cfg["name"])
	name_edit.placeholder_text = "your name"
	name_edit.custom_minimum_size = Vector2(90, 0)
	name_edit.add_theme_font_size_override("font_size", 8)
	h2.add_child(name_edit)
	seed_edit = LineEdit.new()
	seed_edit.text = str(randi() % 1000000)
	seed_edit.custom_minimum_size = Vector2(70, 0)
	seed_edit.add_theme_font_size_override("font_size", 8)
	h2.add_child(seed_edit)
	seed_edit.placeholder_text = "planet seed"
	seed_edit.tooltip_text = "RANDOM PLANET: the same number always makes the same planet"
	# split screen: a second player on this PC (works online too: 2 here + your friend's PC)
	var h4 = HBoxContainer.new()
	left.add_child(h4)
	var play_place = CenterContainer.new()      # (PLAY in the middle of the room under NORMAL)
	mid.add_child(play_place)
	play_place.add_child(_play_button())
	play_place.custom_minimum_size.x = DIFF_W        # (the NORMAL box's width: PLAY is centred under it)
	locals_pick = OptionButton.new()
	var here = "" if OS.has_feature("mobile") else " ON THIS PC"      # (a handheld: no "PC")
	locals_pick.add_item("1 PLAYER" + here, 0)
	locals_pick.add_item("2 PLAYERS" + here + " (SPLIT SCREEN)", 1)
	locals_pick.select(clampi(int(Game.cfg.get("local_players", 1)) - 1, 0, 1))
	locals_pick.fit_to_longest_item = false      # (only as wide as what it shows)
	locals_pick.add_theme_font_size_override("font_size", 8)
	h4.add_child(locals_pick)
	p2_row = HBoxContainer.new()
	h4.add_child(p2_row)
	char2_pick = OptionButton.new()
	for i in Assets.CHARACTERS.size():
		char2_pick.add_item("P2: " + Assets.CHARACTERS[i], i)
	char2_pick.select(int(Game.cfg.get("character2", 0)))
	char2_pick.add_theme_font_size_override("font_size", 8)
	p2_row.add_child(char2_pick)
	name2_edit = LineEdit.new()
	name2_edit.text = str(Game.cfg.get("name2", "PLAYER 2"))
	name2_edit.custom_minimum_size = Vector2(80, 0)
	name2_edit.add_theme_font_size_override("font_size", 8)
	p2_row.add_child(name2_edit)
	p2_row.visible = locals_pick.selected == 1
	locals_pick.item_selected.connect(func(i): p2_row.visible = i == 1)
	var h3 = HBoxContainer.new()
	left.add_child(h3)
	_button(h3, "LOCAL MULTIPLAYER", _local_multiplayer)
	_button(h3, "GLOBAL MULTIPLAYER", _global_multiplayer)
	_button(h3, "DEV TOOLS", _dev_tools)
	_button(h3, "MODS (%d ON)" % Mods.enabled_names().size(), _mods_screen)
	lobby_label = _label(v, "", 8, Color(0.7, 0.9, 1))
	start_btn = _button(v, "START THE ADVENTURE", func(): _read(); Game.begin())
	start_btn.visible = false
	music_label = _label(v, _music_text(), 7, Color(1, 0.9, 0.55))
	if Assets.share_server != null:
		var ips = []
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
				ips.append(a)
		if not ips.is_empty():
			_label(v, "PHONE / TABLET: this PC's address is %s - type it on the phone (to get the game files, and to JOIN)." % ", ".join(PackedStringArray(ips)), 7, Color(0.7, 0.85, 1))
	if OS.has_feature("mobile"):
		_label(v, "CONTROLS: d-pad / stick move.  A punch (hold: rushing strike).  B ki blast (hold: your beam).  X special.  Y transform.  L1 item.  R1 next special.  R2 or L3 run.  START menu.  SELECT map.  MENUS: d-pad + A, or tap.\nLOCAL MULTIPLAYER: play with people on the same Wi-Fi.  GLOBAL MULTIPLAYER: play with anyone over the internet - public games, or private ones with a password.", 7, Color(0.75, 0.75, 0.8))
	else:
		_label(v, "ONE PLAYER: arrows / WASD / pad.  A = Z or J (punch, hold: rushing strike).  B = X or K (ki blast, hold: your beam).  ESC / START: pause.\nTWO ON THIS PC: P1 = WASD + J / K, P2 = arrows + . / (or numpad 1 / 2). With pads: one pad - P1 keyboard, P2 pad; two pads - one each. F2 in the game: player 2 joins / leaves.\nLOCAL MULTIPLAYER: play together with people on the same network - host a game, join one, or host a server. Split screen and multiplayer mix: up to 2 on each PC.", 7, Color(0.75, 0.75, 0.8))

func _read() -> void:
	if char_pick == null or not is_instance_valid(char_pick):
		return      # (the menu is gone: what was read when you left it stays)
	Game.cfg["character"] = char_pick.get_selected_id()
	var aid = adv_pick.get_selected_id()
	Game.cfg["adventure"] = ["gatorra", "dunara", "random"][aid] if aid < 3 else "land:%d" % int(LANDS[aid - 3][0])
	Game.cfg["difficulty"] = diff_pick.selected
	Game.cfg["seed"] = int(seed_edit.text) if seed_edit.text.is_valid_int() else 12345
	Game.cfg["name"] = name_edit.text.strip_edges().to_upper().left(10) if name_edit.text.strip_edges() != "" else "PLAYER"
	Game.cfg["local_players"] = locals_pick.selected + 1
	Game.cfg["character2"] = char2_pick.get_selected_id()
	Game.cfg["name2"] = name2_edit.text.strip_edges().to_upper().left(10) if name2_edit.text.strip_edges() != "" else "PLAYER 2"

## MODS: the mod packages people share - switched on and off here
func _mods_screen() -> void:
	if char_pick and is_instance_valid(char_pick):
		_read()
	var cl = CanvasLayer.new(); cl.layer = 30; add_child(cl)
	var m = load("res://scripts/dev_mods.gd").new()
	m.share = false
	m.font_size = 8
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(m)
	m.closed.connect(func():
		cl.queue_free()
		Mods.reload()
		_menu())

## DEV TOOLS: the map, hero, enemy, move, form, blast and mission editors for your team
var dev: Node
func _dev_tools() -> void:
	if char_pick and is_instance_valid(char_pick):
		_read()
	if ui:
		ui.queue_free()
		ui = null
	Music.stop()
	Game.cfg["adventure"] = "land:0"
	dev = load("res://scripts/devtools.gd").new()
	add_child(dev)
	if test.has("devdemo") and not _dev_scripted:
		add_child(load("res://scripts/dev_demo.gd").new())
	if test.has("devscript") and not _dev_scripted:       # test aid: another script that drives the tools
		add_child(load(str(test["devscript"])).new())
	_dev_scripted = true
	dev.play_requested.connect(func(at: Dictionary):
		dev.queue_free()
		dev = null
		_fit_view()
		Game.cfg["dev_return"] = at
		Game.cfg["start_at"] = at
		Game.cfg["mode"] = "solo"
		Game.cfg["adventure"] = "land:0"
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fighters_playtest.json"))   # (a fresh hero each time: events run again)
		Game.begin())
	dev.closed.connect(func():
		dev.queue_free()
		dev = null
		_fit_view()
		_menu())
	dev.tune_requested.connect(func():
		dev.queue_free()
		dev = null
		_fit_view()
		Game.cfg["mode"] = "solo"
		Game.cfg["adventure"] = "land:0"
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fighters_playtest.json"))   # (a fresh hero each time: events run again)
		Game.begin())

var _dev_scripted = false

## F10 in a play-test: back to the DEV TOOLS where you were
func back_to_tools() -> void:
	if world and is_instance_valid(world):
		if world.has_method("save_all"):
			world.save_all()
		world.queue_free()
		world = null
	Game.leave()
	Game.cfg.erase("start_at")
	_dev_tools()

## a story made in DEV TOOLS - STORY (in your content folder or a mod): its own title, three save slots, PLAY
func _story_row(v: Control) -> void:
	var st: Dictionary = Content.story
	var box = PanelContainer.new()
	var sb = StyleBoxFlat.new(); sb.bg_color = Color(0.12, 0.08, 0.2, 0.9); sb.border_color = Color(1, 0.8, 0.3); sb.set_border_width_all(1); sb.set_content_margin_all(4)
	box.add_theme_stylebox_override("panel", sb)
	v.add_child(box)
	var vv = VBoxContainer.new(); box.add_child(vv)
	var tl = _label(vv, str(st.get("title", "MY STORY")).to_upper(), 11, Color(1, 0.85, 0.35)); tl.custom_minimum_size = Vector2(0, 0)
	if str(st.get("subtitle", "")) != "":
		var stl = _label(vv, str(st["subtitle"]), 7, Color(0.85, 0.85, 1)); stl.custom_minimum_size = Vector2(0, 0)
	var row = HBoxContainer.new(); vv.add_child(row)
	var slot = OptionButton.new(); slot.add_theme_font_size_override("font_size", 8)
	for i in 3:
		var path = "user://fighters_story_%s_%d.json" % [_story_id(), i + 1]
		var txt = "SLOT %d - NEW STORY" % (i + 1)
		if FileAccess.file_exists(path):
			var t = JSON.parse_string(FileAccess.get_file_as_string(path))
			if t is Dictionary and not t.is_empty():
				var d: Dictionary = t.values()[0]
				var ch = clampi(int(d.get("ch", 0)), 0, Assets.CHARACTERS.size() - 1)
				txt = "SLOT %d - %s LV %d" % [i + 1, Assets.CHARACTERS[ch], int(d.get("level", 1))]
		slot.add_item(txt, i)
	row.add_child(slot)
	_button(row, "PLAY THE STORY", func(): _play_story(slot.selected + 1))
	_button(row, "ERASE SLOT", func():
		var d = ConfirmationDialog.new(); d.dialog_text = "Erase slot %d of this story?" % (slot.selected + 1)
		d.confirmed.connect(func():
			DirAccess.remove_absolute(ProjectSettings.globalize_path("user://fighters_story_%s_%d.json" % [_story_id(), slot.selected + 1]))
			_menu())
		add_child(d); d.popup_centered())

func _story_id() -> String:
	var t = str(Content.story.get("title", "story")).to_lower()
	var out = ""
	for ch in t:
		out += ch if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") else "_"
	return out.left(24)

func _play_story(slot: int) -> void:
	var st: Dictionary = Content.story
	_read()
	Game.cfg["mode"] = "solo"
	Game.cfg["adventure"] = "land:0"
	Game.cfg["story"] = "%s_%d" % [_story_id(), slot]
	Game.cfg["local_players"] = 1
	var ci = Assets.CHARACTERS.find(str(st.get("hero", "GOKU")).to_upper())
	if ci >= 0:
		Game.cfg["character"] = ci
	Game.cfg["start_at"] = {"key": str(st.get("start_map", "land/0/0")), "x": float(st.get("x", 8088)), "y": float(st.get("y", 9632))}
	Game.begin()

func _solo() -> void:
	_read()
	Game.cfg["mode"] = "solo"
	Game.begin()

func _host() -> void:
	_read()
	Game.cfg["mode"] = "host"
	# the world opens at once; friends come in whenever they like (JOIN with your Hamachi IP)
	if Game.host_game():
		Game.begin()
	else:
		lobby_label.text = Game.net_error

## this PC only runs the world (no player): everyone JOINs it, the world stays up while you come and go
func _server_from_menu() -> void:
	_read()
	test["adv"] = Game.cfg["adventure"]
	test["seed"] = str(Game.cfg["seed"])
	test["difficulty"] = str(Game.cfg["difficulty"])
	_start_server()

func _join() -> void:
	_read()
	Game.cfg["mode"] = "join"
	if Game.join_game(str(Game.cfg["ip"])):
		lobby_label.text = "CONNECTING TO %s ..." % Game.cfg["ip"]
	else:
		lobby_label.text = Game.net_error

# ------------------------------------------------------------------ LOCAL MULTIPLAYER (Android port): host, join or serve
## on the same Wi-Fi; the addresses are found and used behind the scenes - nobody types one
var in_local_mp = false
func _local_multiplayer() -> void:
	_read()
	in_local_mp = true
	_clear()
	var v = _box()
	v.add_theme_constant_override("separation", 4)
	# top left: a small BACK, then the title
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	_button(top, "BACK", func(): in_local_mp = false; _menu())
	var t = _label(top, "LOCAL MULTIPLAYER", 12, Color(1, 0.85, 0.3))
	t.custom_minimum_size = Vector2(0, 0)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	# a server with no player of its own
	var gap_top = Control.new()
	gap_top.custom_minimum_size = Vector2(0, 6)
	v.add_child(gap_top)
	var srv = _button(v, "HOST SERVER WITHOUT PLAYING", func(): in_local_mp = false; _server_from_menu())
	srv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	srv.add_theme_font_size_override("font_size", 11)
	srv.custom_minimum_size = Vector2(0, 24)
	_green(srv)
	var sd = _label(v, "Allows a device on your local Wi-Fi network to become a server that other devices can join without that device having to run the game.", 8, Color(0.8, 0.85, 0.95))
	sd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# a lot of room, then HOST GAME and JOIN GAME down below: the screen is filled
	var gap = Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.size_flags_stretch_ratio = 2.0
	v.add_child(gap)
	# HOST GAME and JOIN GAME side by side, big, each with its paragraph
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	v.add_child(cols)
	for c in [["HOST GAME", _host, "Host a local game on your Wi-Fi network. Only people on your Wi-Fi network can join this game."],
			["JOIN GAME", func(): in_local_mp = false; _find_games(), "Join a game on your local Wi-Fi network. You won't be able to see games hosted by anyone else on any other Wi-Fi network other than yours."]]:
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		cols.add_child(col)
		var b = Button.new()
		b.text = c[0]
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(0, 30)
		_green(b)
		b.pressed.connect(c[1])
		col.add_child(b)
		var d = _label(col, c[2], 8, Color(0.8, 0.85, 0.95))
		d.custom_minimum_size = Vector2(0, 0)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lobby_label = _label(v, "", 8, Color(0.7, 0.9, 1))
	lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap_bottom = Control.new()
	gap_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap_bottom)

## the green of the PLAY button (Steam's), for the big buttons
func _green(b: Button) -> void:
	for st in [["normal", Color(0.44, 0.69, 0.13), Color(0.36, 0.56, 0.1)], ["hover", Color(0.55, 0.8, 0.18), Color(0.44, 0.69, 0.13)],
			["pressed", Color(0.33, 0.52, 0.09), Color(0.27, 0.43, 0.07)], ["focus", Color(0.55, 0.8, 0.18), Color(0.85, 1, 0.55)]]:
		var sb = StyleBoxFlat.new()
		sb.bg_color = st[1]
		sb.border_color = st[2]
		sb.set_border_width_all(1 if st[0] != "focus" else 2)
		sb.set_corner_radius_all(3)
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		b.add_theme_stylebox_override(st[0], sb)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(k, Color(1, 1, 1))

## PLAY: big and green (the colour of Steam's play button) with a triangle - the first thing to press (Android port)
const DIFF_W = 110      # the NORMAL box, and the room under it where PLAY stands
func _play_button() -> Button:
	var b = Button.new()
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_green(b)
	# [space][triangle][space][PLAY][space]: the same room everywhere
	const GAP = 9
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var tex = _triangle_icon()
	var tri = TextureRect.new()
	tri.texture = tex
	tri.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	tri.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tri)
	var lab = Label.new()
	lab.text = "PLAY"
	lab.add_theme_font_size_override("font_size", 14)
	lab.add_theme_color_override("font_color", Color(1, 1, 1))
	lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lab)
	var word_w = ThemeDB.fallback_font.get_string_size("PLAY", HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	b.custom_minimum_size = Vector2(GAP * 3 + tex.get_width() + word_w, 32)
	b.pressed.connect(_solo)
	b.add_to_group("first_focus")
	return b

func _triangle_icon() -> ImageTexture:
	var img = Image.create(10, 12, false, Image.FORMAT_RGBA8)
	for y in 12:
		var reach = 6.0 - absf(y - 5.5)          # a play triangle pointing right
		for x in 10:
			if x + 0.5 <= reach * 10.0 / 6.0:
				img.set_pixel(x, y, Color(1, 1, 1))
	return ImageTexture.create_from_image(img)

func _big_button(parent: Node, t: String, f: Callable) -> Button:
	var b = _button(parent, t, f)
	b.add_theme_font_size_override("font_size", 11)
	b.custom_minimum_size = Vector2(0, 22)
	return b

# ------------------------------------------------------------------ GLOBAL MULTIPLAYER (Android port): over the internet
## (embedded ZeroTier + the lobby list: see online.gd). B goes back from every one of these screens.
var _global_back: Callable = Callable()
var _online_label: Label
func _global_multiplayer() -> void:
	_read()
	Online.start()
	Online.browse(false)
	_global_back = func(): _menu()
	_clear()
	var v = _box()
	v.add_theme_constant_override("separation", 4)
	var top = _top_bar(v, "GLOBAL MULTIPLAYER")
	_online_label = _label(top, "", 8, Color(0.7, 0.9, 1))
	_online_label.custom_minimum_size = Vector2(0, 0)
	_online_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	var gap_top = Control.new()
	gap_top.custom_minimum_size = Vector2(0, 4)
	v.add_child(gap_top)
	var srv = _button(v, "HOST SERVER WITHOUT PLAYING", func(): _world_name_screen(func(): _online_action(func(): _global_back = Callable(); test["online"] = "1"; _server_from_menu())))
	srv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	srv.add_theme_font_size_override("font_size", 11)
	srv.custom_minimum_size = Vector2(0, 24)
	_green(srv)
	var sd = _label(v, "Turns this device into an online server that anyone in the world can find and join, without this device playing.", 8, Color(0.8, 0.85, 0.95))
	sd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap = Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.size_flags_stretch_ratio = 2.0
	v.add_child(gap)
	_columns(v, [["HOST PUBLIC GAME", func(): _world_name_screen(func(): _online_action(func(): _host_online(""))), "Host a game anyone in the world can see under JOIN GAME and join."],
		["HOST PRIVATE GAME", func(): _private_password_screen(), "Host a game protected by a password you choose. Only people with the password can join."],
		["JOIN GAME", func(): _online_games(), "See the games people are playing online and join one. Private games ask for their password."]])
	lobby_label = _label(v, "", 8, Color(0.7, 0.9, 1))
	lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var gap_bottom = Control.new()
	gap_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap_bottom)
	_tick(_show_online_state)

## a small BACK at the top left and the title; returns the row (more can be added to it)
func _top_bar(v: Control, title_text: String) -> HBoxContainer:
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	_button(top, "BACK", func(): if _global_back.is_valid(): _global_back.call())
	var title = _label(top, title_text, 12, Color(1, 0.85, 0.3))
	title.custom_minimum_size = Vector2(0, 0)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	return top

## big green buttons side by side, each with its paragraph under it
func _columns(v: Control, items: Array) -> void:
	var cols = HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	v.add_child(cols)
	for c in items:
		var col = VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 4)
		cols.add_child(col)
		var b = Button.new()
		b.text = c[0]
		b.add_theme_font_size_override("font_size", 12 if items.size() > 2 else 14)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		b.custom_minimum_size = Vector2(0, 28)
		_green(b)
		b.pressed.connect(c[1])
		col.add_child(b)
		var d = _label(col, c[2], 8, Color(0.8, 0.85, 0.95))
		d.custom_minimum_size = Vector2(0, 0)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

## run f every half second while this screen is up
func _tick(f: Callable) -> void:
	var t = Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(f)
	ui.add_child(t)
	f.call()

func _show_online_state() -> void:
	if is_instance_valid(_online_label):
		_online_label.text = "   " + Online.status_text()

## hosting and joining need the internet network up; until then the button says so
func _online_action(f: Callable) -> void:
	if not Online.available():
		lobby_label.text = "GLOBAL MULTIPLAYER needs the Android app."
		return
	if not Online.is_online():
		lobby_label.text = Online.status_text() + " - try again in a moment."
		return
	f.call()

func _host_online(password: String) -> void:
	Game.cfg["mode"] = "host"
	if Game.host_game_online(password):
		_global_back = Callable()
		Game.begin()
	elif is_instance_valid(lobby_label):
		lobby_label.text = Game.net_error

## WORLD NAME: what people see in JOIN GAME (a lot of worlds are GOKU - EARTH)
func _world_name_screen(then: Callable) -> void:
	_global_back = func(): _global_multiplayer()
	_clear()
	var v = _box()
	v.add_theme_constant_override("separation", 6)
	_top_bar(v, "WORLD NAME")
	_label(v, "Give your world a name. It is what other players see in JOIN GAME.", 8, Color(0.8, 0.85, 0.95))
	_password_box(v)
	_pw_edit.placeholder_text = "world name"
	_pw_edit.text = Online.world_name
	var go = _button(v, "CONTINUE", func():
		var n = _pw_edit.text.strip_edges().to_upper()
		if n.length() < 2:
			lobby_label.text = "The name needs 2 or more characters."
			return
		Online.world_name = n.left(24)
		then.call())
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_size_override("font_size", 12)
	go.custom_minimum_size = Vector2(90, 26)
	_green(go)
	lobby_label = _label(v, "", 8, Color(0.7, 0.9, 1))
	lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

var _pw_edit: LineEdit
func _password_box(v: Control) -> void:
	_pw_edit = LineEdit.new()
	_pw_edit.placeholder_text = "password"
	_pw_edit.max_length = 24
	_pw_edit.custom_minimum_size = Vector2(160, 0)
	_pw_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pw_edit.add_theme_font_size_override("font_size", 10)
	v.add_child(_pw_edit)

func _private_password_screen() -> void:
	_global_back = func(): _global_multiplayer()
	_clear()
	var v = _box()
	v.add_theme_constant_override("separation", 6)
	_top_bar(v, "HOST PRIVATE GAME")
	_label(v, "Choose a password for your game (4 or more characters). Tell it to the people you want to play with - they type it when they join.", 8, Color(0.8, 0.85, 0.95))
	_password_box(v)
	var go = _button(v, "START PRIVATE GAME", _start_private)
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_size_override("font_size", 12)
	go.custom_minimum_size = Vector2(0, 26)
	_green(go)
	lobby_label = _label(v, "", 8, Color(0.7, 0.9, 1))
	lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _start_private() -> void:
	var pw = _pw_edit.text.strip_edges()
	if pw.length() < 4:
		lobby_label.text = "The password needs 4 or more characters."
		return
	_online_action(func(): _host_online(pw))

var _online_list: VBoxContainer
var _online_sig = "-"
func _online_games() -> void:
	_global_back = func(): Online.browse(false); _global_multiplayer()
	Online.start()
	Online.browse(true)
	_online_sig = "-"
	_clear()
	var v = _box()
	var top = _top_bar(v, "JOIN GAME")
	_online_label = _label(top, "", 8, Color(0.7, 0.9, 1))
	_online_label.custom_minimum_size = Vector2(0, 0)
	_online_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label(v, "Games people are playing online. Pick one to join.", 8)
	_online_list = VBoxContainer.new()
	v.add_child(_online_list)
	lobby_label = _label(v, "", 8, Color(0.7, 0.9, 1))
	_tick(_refresh_online_games)

func _refresh_online_games() -> void:
	_show_online_state()
	if not is_instance_valid(_online_list):
		return
	var sig = Online.list_error
	for g in Online.lobbies:
		sig += "%s|%s|%s|%d|%s;" % [g["id"], g["character"], g["planet"], g["players"], g["private"]]
	if sig == _online_sig:
		return
	_online_sig = sig
	print("[main] online games: ", sig)
	var fo = get_viewport().gui_get_focus_owner()
	var had_focus = fo != null and _online_list.is_ancestor_of(fo)
	for c in _online_list.get_children():
		c.queue_free()
	if Online.list_error != "":
		_label(_online_list, Online.list_error, 8, Color(1, 0.6, 0.5))
		return
	if Online.lobbies.is_empty():
		_label(_online_list, "Looking for games... (nobody is hosting one online right now)", 8, Color(0.75, 0.75, 0.8))
		return
	var first: Button = null
	for g in Online.lobbies:
		var t = "%s  -  %s  -  %s   (%d/%d)%s" % [g.get("world", ""), g["character"], g["planet"], int(g["players"]), int(g["max"]), "   PRIVATE" if g["private"] else ""]
		var b = _big_button(_online_list, t, _pick_online_game.bind(g))
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_green(b)
		if first == null:
			first = b
	if had_focus and first:
		first.grab_focus.call_deferred()

func _pick_online_game(g: Dictionary) -> void:
	if bool(g["private"]):
		_join_password_screen(g)
	else:
		_online_action(func(): _join_online(g, ""))

func _join_password_screen(g: Dictionary) -> void:
	_global_back = func(): _online_games()
	Online.browse(false)
	_clear()
	var v = _box()
	v.add_theme_constant_override("separation", 6)
	_top_bar(v, "PRIVATE GAME")
	_label(v, "%s  -  %s   is a private game. Type its password:" % [g["character"], g["planet"]], 9, Color(0.85, 0.9, 1))
	_password_box(v)
	var go = _button(v, "JOIN", func(): _online_action(func(): _join_online(g, _pw_edit.text.strip_edges())))
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.add_theme_font_size_override("font_size", 12)
	go.custom_minimum_size = Vector2(80, 26)
	_green(go)
	lobby_label = _label(v, "", 8, Color(0.7, 0.9, 1))
	lobby_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _join_online(g: Dictionary, password: String) -> void:
	Online.browse(false)
	Game.net_error = ""
	Game.cfg["mode"] = "join"
	var port = Online.join(g, password)
	if Game.join_game_online(port):
		lobby_label.text = "JOINING ..."
	else:
		lobby_label.text = Game.net_error

# ------------------------------------------------------------------ JOIN GAME: the games on this Wi-Fi
var finding = false
var _find_list: VBoxContainer
var _find_sig = ""
func _find_games() -> void:
	finding = true
	_find_sig = "-"
	_clear()
	var v = _box()
	var top = HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	v.add_child(top)
	_button(top, "BACK", _leave_find)
	var title = _label(top, "JOIN GAME", 12, Color(1, 0.85, 0.3))
	title.custom_minimum_size = Vector2(0, 0)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label(v, "Games on your Wi-Fi network. Pick one to join.", 8)
	_find_list = VBoxContainer.new()
	v.add_child(_find_list)
	lobby_label = _label(v, "", 8, Color(0.7, 0.9, 1))
	Game.lan_scan_start()
	var t = Timer.new()
	t.wait_time = 0.5
	t.autostart = true
	t.timeout.connect(_refresh_find)
	ui.add_child(t)
	_refresh_find()

func _refresh_find() -> void:
	if not finding or not is_instance_valid(_find_list):
		return
	var ips = Game.lan_found.keys()
	ips.sort()
	var sig = ""
	for ip in ips:
		var g: Dictionary = Game.lan_found[ip]
		sig += "%s|%s|%s;" % [ip, g.get("character", ""), g.get("planet", "")]
	if sig == _find_sig:
		return
	_find_sig = sig
	print("[main] games on this Wi-Fi: ", sig)
	var had_focus = get_viewport().gui_get_focus_owner() != null and _find_list.is_ancestor_of(get_viewport().gui_get_focus_owner())
	for c in _find_list.get_children():
		c.queue_free()
	if ips.is_empty():
		_label(_find_list, "Looking for games... (someone on your Wi-Fi has to choose HOST GAME or HOST SERVER WITHOUT PLAYING)", 8, Color(0.75, 0.75, 0.8))
		return
	var first: Button = null
	for ip in ips:
		var g: Dictionary = Game.lan_found[ip]
		var b = _big_button(_find_list, "%s  -  %s" % [str(g.get("character", g.get("name", "?"))), str(g.get("planet", ""))], _join_found.bind(ip))
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		_green(b)
		if first == null:
			first = b
	if had_focus and first:
		first.grab_focus.call_deferred()

func _join_found(ip: String) -> void:
	Game.lan_scan_stop()
	finding = false
	Game.cfg["ip"] = ip
	Game.cfg["mode"] = "join"
	if Game.join_game(ip):
		lobby_label.text = "JOINING ..."
	else:
		lobby_label.text = Game.net_error

func _leave_find() -> void:
	Game.lan_scan_stop()
	finding = false
	_local_multiplayer()

func _refresh_lobby() -> void:
	if lobby_label == null or not is_instance_valid(lobby_label):
		return
	if Game.net_error != "":
		lobby_label.text = Game.net_error
		return
	var names = []
	for id in Game.peers:
		names.append("%s (%s)" % [Game.peers[id]["name"], Assets.CHARACTERS[clampi(int(Game.peers[id]["character"]), 0, Assets.CHARACTERS.size() - 1)]])
	if Game.cfg["mode"] == "host":
		lobby_label.text = "HOSTING - people on your Wi-Fi can join. In the game: " + ", ".join(PackedStringArray(names))
	else:
		lobby_label.text = "CONNECTED. Waiting for the host to start... Players: " + ", ".join(PackedStringArray(names))

func _on_started() -> void:
	_global_back = Callable()
	Online.browse(false)
	in_local_mp = false
	finding = false
	Game.lan_scan_stop()
	if Game.cfg["mode"] == "server":
		return
	if world and is_instance_valid(world) and world.has_method("save_all"):
		world.save_all()
	if ui:
		ui.queue_free()
		ui = null
	get_viewport().gui_release_focus()     # a menu button kept in focus must not take the pad's A in the game
	if world:
		world.queue_free()
	world = Node2D.new()
	world.set_script(load("res://scripts/world.gd"))
	add_child(world)

# ------------------------------------------------------------------ the dedicated server (no window, no player)
## LoG2Coop.exe --headless -- --server --adv=gatorra --seed=12345 [--difficulty=1]
## The world lives on this PC: players JOIN with its IP whenever they like, the world is saved every 10 s.
func _start_server() -> void:
	if not Assets.ready_to_play():
		print("[server] no imported folder: start LoG2Coop.exe once normally and choose your game first")
		get_tree().quit(1)
		return
	Assets.load_data()
	Game.cfg["mode"] = "server"
	Game.cfg["name"] = "SERVER"
	Game.cfg["adventure"] = test.get("adv", "gatorra")
	Game.cfg["seed"] = int(test.get("seed", "12345"))
	Game.cfg["difficulty"] = int(test.get("difficulty", "1"))
	if not (Game.host_game_online("") if test.has("online") else Game.host_game()):
		print("[server] ", Game.net_error)
		get_tree().quit(1)
		return
	Game.begin()
	print("[server] world %s is open on port %d - players JOIN with this PC's (Hamachi) IP" % [Game.world_id(), Game.PORT])
	var srv = Node.new()
	srv.set_script(load("res://scripts/server.gd"))
	add_child(srv)
	if DisplayServer.get_name() != "headless":
		_clear()
		var v = _box()
		_label(v, "LOG2 WORLD SERVER", 12, Color(1, 0.85, 0.3))
		_button(v, "STOP THE SERVER - BACK TO THE MENU", srv.stop)
		srv.status = _label(v, "", 8, Color(0.8, 1, 0.8))

# ------------------------------------------------------------------ test aid (headless runs)
func _start_test() -> void:
	Game.cfg["character"] = int(test.get("ch", "4"))
	Game.cfg["adventure"] = test.get("adv", "gatorra")
	Game.cfg["seed"] = int(test.get("seed", "777"))
	Game.cfg["mode"] = test.get("mode", "solo")
	Game.cfg["name"] = test.get("name", "TEST")
	Game.start_override = int(test.get("start", "-1"))
	Game.cfg["local_players"] = int(test.get("locals", "1"))
	Game.cfg["character2"] = int(test.get("ch2", "0"))
	Game.cfg["name2"] = test.get("name2", "TEST2")
	Game.cfg["respawn_scale"] = float(test.get("respawn", "1"))
	Game.cfg["event_scale"] = float(test.get("events", "1"))
	Game.cfg["wb_node"] = int(test.get("wbnode", "-1"))
	if Game.cfg["mode"] == "host":
		Game.host_game()
		await get_tree().create_timer(float(test.get("wait", "3"))).timeout
		Game.begin()
	elif Game.cfg["mode"] == "wshost":       # test: GLOBAL hosting without ZeroTier (WebSocket on this machine)
		Game.cfg["mode"] = "host"
		Game.host_game_online(test.get("pw", ""))
		if test.has("salt"):        # (a test: a known salt, so the joining copy can make its proof)
			Online.salt = test["salt"]
			Online._proof = Online.proof_of(Online.salt, test.get("pw", ""))
		Game.begin()
	elif Game.cfg["mode"] == "wsjoin":
		Game.cfg["mode"] = "join"
		Online.join_proof = Online.proof_of(test.get("salt", ""), test.get("pw", "")) if test.has("salt") else ""
		Game.join_game_online(Online.PORT)
	elif Game.cfg["mode"] == "join":
		Game.join_game(test.get("ip", "127.0.0.1"))
	else:
		Game.begin()

func _input(ev: InputEvent) -> void:
	# fullscreen: F11 or Alt+Enter (the picture stays sharp: whole-number scaling)
	if ev is InputEventKey and ev.pressed and not ev.echo and (ev.keycode == KEY_F11 or (ev.keycode == KEY_ENTER and ev.alt_pressed)):
		var full = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
		get_viewport().set_input_as_handled()
	# GLOBAL MULTIPLAYER screens: B (or ESC) goes back
	if _global_back.is_valid() and ui != null and is_instance_valid(ui) and ((ev is InputEventJoypadButton and ev.pressed and ev.button_index == Game.pad_btn("b")) or (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE)):
		get_viewport().set_input_as_handled()
		_global_back.call()
		return
	# LOCAL MULTIPLAYER / JOIN GAME: B (or ESC) goes back
	if in_local_mp and ui != null and is_instance_valid(ui) and ((ev is InputEventJoypadButton and ev.pressed and ev.button_index == Game.pad_btn("b")) or (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE)):
		get_viewport().set_input_as_handled()
		in_local_mp = false
		_menu()
		return
	if finding and ui != null and is_instance_valid(ui) and ((ev is InputEventJoypadButton and ev.pressed and ev.button_index == Game.pad_btn("b")) or (ev is InputEventKey and ev.pressed and not ev.echo and ev.keycode == KEY_ESCAPE)):
		get_viewport().set_input_as_handled()
		_leave_find()
		return
	# a pad in the menus: the first press puts the focus on the first button (d-pad moves, A presses)
	if ev is InputEventJoypadButton and ev.pressed and ui != null and is_instance_valid(ui) and ui.is_inside_tree():
		var fo = get_viewport().gui_get_focus_owner()
		if fo == null or not fo.is_visible_in_tree():
			var first = get_tree().get_first_node_in_group("first_focus")      # (PLAY on the main menu)
			if first == null or not is_instance_valid(first) or not first.is_visible_in_tree():
				first = _first_focusable(ui)
			if first:
				first.grab_focus()
				get_viewport().set_input_as_handled()

func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and c.is_visible_in_tree():
			if c.focus_mode == Control.FOCUS_ALL and c is BaseButton and not c.disabled:
				return c
			var r = _first_focusable(c)
			if r:
				return r
	return null

func _physics_process(_dt: float) -> void:
	if test.has("ftime"):
		var now = Time.get_ticks_usec()
		if _ft_last > 0:
			_ft_max = maxi(_ft_max, now - _ft_last)
			if now - _ft_last > 40000: print("[test] slow frame ", Engine.get_physics_frames(), " ", (now - _ft_last) / 1000)
		_ft_last = now
		if Engine.get_physics_frames() % 120 == 0:
			print("[test] worst frame ", _ft_max / 1000.0, " ms")
			_ft_max = 0
	if get_window().size != _fit_size:      # fullscreen, maximise, a new monitor: fit again at once
		_fit_view()
	if test.has("menushot"):
		test_t += 1
		if test_t == 20:
			get_viewport().get_texture().get_image().save_png(test["menushot"])
			get_tree().quit()
		return
	if not test.has("autotest") or world == null:
		return
	test_t += 1
	if test.has("gameshot") and test_t == int(test.get("shotat", "400")):
		get_viewport().get_texture().get_image().save_png(test["gameshot"])
	var script: String = test.get("keys", "")
	# keys: "from:to:keys;..." with keys letters u d l r a b (player 1); keys2 the same for player 2; F = toggle player 2
	if test.has("level") and test_t == 2:
		for L in world.locals:
			L.fighter.level = int(test["level"])
			L.fighter.ep = L.fighter.maxep + 60
			L.fighter.maxep += 60
			L.fighter.zeni = 1000
	if _script_keys(test.get("keys", "")).has("toggle"):
		world._toggle_player2()
	var tk = []
	for i in world.locals.size():
		var k = _script_keys(test.get("keys" if i == 0 else "keys2", ""))
		k.erase("toggle")
		if test.has("bot") and k.is_empty() and (i == 0 or test.has("bot2")):
			k = _bot_keys(world.locals[i], i)
		tk.append(k if not k.is_empty() else {"none": true})
	world.test_keys = tk
	if test.has("watch") and test_t % 60 == 0:
		for pid in Game.remote_states:
			var st = Game.remote_states[pid]
			print("[test] watch ", pid, " node ", st.get("node"), " at ", int(st["x"]), ",", int(st["y"]), " down ", st.get("down"), " me at ", int(world.locals[0].fighter.x), ",", int(world.locals[0].fighter.y), " help ", world.locals[0].helping)
	if test.has("social") and test["social"] == "net" and not Game.remote_states.is_empty():
		var A = world.locals[0]
		var rp = Game.remote_states.keys()[0]
		var pa = world._my_pid(A)
		if test_t == 200 and Game.is_host():
			world._friend_act(A, {"act": "trade", "pid": rp, "name": "FRIEND"})
			world._friend_act(A, {"act": "duel", "pid": rp, "name": "FRIEND"})
		if test_t == 260 and not Game.is_host():
			print("[test] client rows ", world._friend_rows(A).slice(0, 2))
			world._friend_act(A, world._friend_rows(A)[0])
		if not A.trade.is_empty() and A.trade["mine"].is_empty():
			A.trade["mine"] = {"zeni": 10 if Game.is_host() else 25}
			Game.send_social(rp, pa, A.name, "trade_offer", {"offer": A.trade["mine"]})
		if not A.trade.is_empty() and not A.trade["theirs"].is_empty() and not A.trade["ready_me"] and test_t % 40 == 0:
			A.trade["ready_me"] = true
			Game.send_social(rp, pa, A.name, "trade_ready", {"mine": A.trade["mine"], "theirs": A.trade["theirs"]})
			world._trade_check(A)
		if test_t == 330:
			print("[test] net before host=", Game.is_host(), " zeni ", A.fighter.zeni, " trade ", A.trade)
		if test_t == 450:
			print("[test] net after host=", Game.is_host(), " zeni ", A.fighter.zeni, " trade ", A.trade, " invites ", A.invites)
	if test.has("social") and world.locals.size() > 1:
		var A = world.locals[0]
		var B = world.locals[1]
		var pa = world._my_pid(A)
		var pb = world._my_pid(B)
		match test["social"]:
			"duel":
				if test_t == 30: world._friend_act(A, {"act": "duel", "pid": pb, "name": B.name})
				if test_t == 40: world._friend_act(B, world._friend_rows(B)[0])
				if test_t % 20 == 0 and B.fighter.state == "idle": B.fighter.x = A.fighter.x + 16; B.fighter.y = A.fighter.y
				if test_t % 60 == 0: print("[test] pos A ", int(A.fighter.x), ",", int(A.fighter.y), " ", A.fighter.state, " B ", int(B.fighter.x), ",", int(B.fighter.y), " ", B.fighter.state, " inv ", B.fighter.invuln)
				if test_t % 60 == 0: print("[test] duel A ", A.duel, " hp ", A.fighter.hp, "  B ", B.duel, " hp ", B.fighter.hp, "/", B.fighter.maxhp)
			"tradeview":
				if test_t == 30:
					world._friend_act(A, {"act": "trade", "pid": pb, "name": B.name})
				if test_t == 40:
					world._friend_act(B, world._friend_rows(B)[0])
					A.fighter.add_item("senzu", 2)
				if test_t == 70:
					A.trade["mine"] = {"senzu": 2}; Game.send_social(pb, pa, A.name, "trade_offer", {"offer": A.trade["mine"]})
					A.menu["row"] = 0
				if test_t == 110:
					B.trade["mine"] = {"zeni": 300}; Game.send_social(pa, pb, B.name, "trade_offer", {"offer": B.trade["mine"]})
					B.menu["row"] = 4
				if test_t == 150:
					A.trade["ready_me"] = true; Game.send_social(pb, pa, A.name, "trade_ready", {"mine": A.trade["mine"], "theirs": A.trade["theirs"]})
					A.menu["row"] = 5
			"trade":
				if test_t == 30:
					world._friend_act(A, {"act": "trade", "pid": pb, "name": B.name})
					world._friend_act(A, {"act": "party", "pid": pb, "name": B.name})
				if test_t == 40:
					world._friend_act(B, world._friend_rows(B)[0])
					world._friend_act(B, world._friend_rows(B)[0])
					print("[test] party A ", A.party, " B ", B.party, " trade A ", A.trade, " B ", B.trade)
					A.fighter.add_item("senzu", 2)
				if test_t == 50:
					A.trade["mine"] = {"senzu": 1}; Game.send_social(pb, pa, A.name, "trade_offer", {"offer": A.trade["mine"]})
					B.trade["mine"] = {"zeni": 100}; Game.send_social(pa, pb, B.name, "trade_offer", {"offer": B.trade["mine"]})
					print("[test] before A zeni ", A.fighter.zeni, " senzu ", A.fighter.inv.get("senzu", 0), " B zeni ", B.fighter.zeni, " senzu ", B.fighter.inv.get("senzu", 0))
				if test_t == 60:
					A.trade["ready_me"] = true; Game.send_social(pb, pa, A.name, "trade_ready", {"mine": A.trade["mine"], "theirs": A.trade["theirs"]})
				if test_t == 70:
					B.trade["ready_me"] = true; Game.send_social(pa, pb, B.name, "trade_ready", {"mine": B.trade["mine"], "theirs": B.trade["theirs"]}); world._trade_check(B)
				if test_t == 80:
					print("[test] after A zeni ", A.fighter.zeni, " senzu ", A.fighter.inv.get("senzu", 0), " B zeni ", B.fighter.zeni, " senzu ", B.fighter.inv.get("senzu", 0), " trades ", A.trade, B.trade)
	if test.has("downme") and test_t == int(test["downme"]):
		world.locals[0].fighter.invuln = 0
		world.locals[0].fighter.take_hit(99999, 0, 0)
	if test.has("downme") and test_t % 30 == 0:
		print("[test] me state ", world.locals[0].fighter.state, " hp ", world.locals[0].fighter.hp, " down_t ", world.locals[0].fighter.down_t)
	if test.has("downp2") and test_t == int(test["downp2"]) and world.locals.size() > 1:
		world.locals[1].fighter.invuln = 0
		world.locals[1].fighter.take_hit(99999, 0, 0)
	if test.has("downp2") and test_t % 30 == 0 and world.locals.size() > 1:
		print("[test] P2 state ", world.locals[1].fighter.state, " hp ", world.locals[1].fighter.hp, " down_t ", world.locals[1].fighter.down_t)
	if test.has("say") and test_t == int(test["say"].split(":")[0]):
		Game.say(world.locals[0].name, test["say"].split(":")[1], 0)
	if test.has("pos") and test_t == 5:
		# test aid: put player 1 somewhere (area pixels)
		var xy = str(test["pos"]).split(",")
		world.locals[0].fighter.x = float(xy[0]); world.locals[0].fighter.y = float(xy[1])
	if test.has("touch") and test_t == 2:
		world.touch.shown = true
	if test.has("skill") and test_t == 3:
		for L in world.locals:
			var u = L.fighter.unlocked_skills()
			for i in u.size():
				if str(u[i]["id"]) == test["skill"]:
					L.fighter.skill_i = i
	if test.has("nomusic"):
		Music.volume = 0.0
	if test.has("nohud") and test_t == 2:
		world.hud_draw.visible = false
	if test.has("walkto") and test_t >= 10:
		# trailer aid: player 1 runs a real path (A* over the walkable ground) through the given points
		var L0 = world.locals[0]
		if walk_path.is_empty() and test_t == 10:
			var a: Dictionary = L0.area
			var g = AStarGrid2D.new()
			g.region = Rect2i(0, 0, a["tw"], a["th"])
			g.cell_size = Vector2(8, 8)
			g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
			g.update()
			var wk: PackedByteArray = a["walk"]
			var tw: int = a["tw"]
			var th: int = a["th"]
			for y in th:
				for x in tw:
					if wk[y * tw + x] == 0:
						g.set_point_solid(Vector2i(x, y), true)
					else:
						# keep a tile away from walls (the fighter is wider than one tile)
						for dy in range(-1, 2):
							for dx in range(-1, 2):
								var xx = clampi(x + dx, 0, tw - 1)
								var yy = clampi(y + dy, 0, th - 1)
								if wk[yy * tw + xx] == 0:
									g.set_point_weight_scale(Vector2i(x, y), 6.0)
			var cur = Vector2i(int(L0.fighter.x / 8), int(L0.fighter.y / 8))
			for q in str(test["walkto"]).split(";", false):
				var v = q.split(",")
				var sp = Game.planet.safe_point(L0.node_i, Vector2(float(v[0]), float(v[1])))
				var to = Vector2i(int(sp.x / 8), int(sp.y / 8))
				var seg = g.get_point_path(cur, to)
				print("[test] walk leg ", cur, " -> ", to, ": ", seg.size(), " steps")
				for pt in seg:
					walk_path.append(pt + Vector2(4, 4))
				cur = to
		if walk_path.size() > 0:
			var me = Vector2(L0.fighter.x, L0.fighter.y)
			while walk_path.size() > 1 and me.distance_to(walk_path[0]) < 7:
				walk_path.pop_front()
				walk_stuck = 0
			walk_stuck += 1
			if walk_stuck > 40 and walk_path.size() > 1:
				walk_path.pop_front()      # caught on a corner: aim at the next step
				walk_stuck = 0
			var dv = walk_path[0] - me
			var k = {"run": true}
			if dv.x > 2: k["right"] = true
			if dv.x < -2: k["left"] = true
			if dv.y > 2: k["down"] = true
			if dv.y < -2: k["up"] = true
			if walk_path.size() == 1 and dv.length() < 4:
				k = {"none": true}
			world.test_keys[0] = k
	if test.has("glide") and test_t >= 10:
		# trailer aid: player 1 flies along a path over the land (walls ignored), the camera follows
		var pts = []
		for q in str(test["glide"]).split(";", false):
			var v = q.split(",")
			pts.append(Vector2(float(v[0]), float(v[1])))
		var sp = float(test.get("glidespeed", "3"))
		var dist = (test_t - 10) * sp
		var p = pts[0]
		var dv = Vector2.ZERO
		for i in range(1, pts.size()):
			var seg = pts[i] - pts[i - 1]
			if dist <= seg.length():
				p = pts[i - 1] + seg.normalized() * dist
				dv = seg
				break
			dist -= seg.length()
			p = pts[i]
		var L0 = world.locals[0]
		L0.fighter.x = p.x
		L0.fighter.y = p.y
		if dv != Vector2.ZERO:
			var d = (3 if dv.x > 0 else 2) if absf(dv.x) > absf(dv.y) else (0 if dv.y > 0 else 1)
			L0.fighter.dir = d
			world.test_keys[0] = {["down", "up", "left", "right"][d]: true, "run": true}
	if test.has("aim") and (world.test_keys[0].has("sp") or world.test_keys[0].has("b")):
		# trailer aid: face the nearest foe before a special / ki blast
		var L0 = world.locals[0]
		var key0: String = Game.planet.nodes[L0.node_i]["key"]
		var bd = 1e9
		var dv = Vector2.ZERO
		for e in Game.area_states.get(key0, []):
			var v = Vector2(float(e[1]) - L0.fighter.x, float(e[2]) - L0.fighter.y)
			if v.length() < bd and (int(e[9]) & 4) == 0:
				bd = v.length(); dv = v
		if dv != Vector2.ZERO:
			L0.fighter.dir = (3 if dv.x > 0 else 2) if absf(dv.x) > absf(dv.y) else (0 if dv.y > 0 else 1)
	if test.has("god"):
		for L in world.locals:
			L.fighter.hp = maxi(L.fighter.hp, L.fighter.maxhp * 2 / 3)
	if test.has("infep"):
		for L in world.locals:
			L.fighter.ep = L.fighter.maxep
	if test.has("clean") and test_t <= 3:
		world.toasts.clear()      # trailer/test aid: no start messages
	if test.has("spawn") and test_t == 30:
		# test aid: foes of the given types (and "b<type>" for a boss of that kind) right next to player 1
		var L0 = world.locals[0]
		var key0: String = Game.planet.nodes[L0.node_i]["key"]
		if Game.sims.has(key0):
			var sim = Game.sims[key0]
			var i = 0
			for tok in str(test["spawn"]).split(",", false):
				var boss = tok.begins_with("b")
				var t = int(tok.trim_prefix("b"))
				var st = Assets.set_for_type(t)
				var pos = sim._open_near(Vector2(L0.fighter.x + float(test.get("spawnd", "70")) + 30 * (i % 3), L0.fighter.y - 30 + 30 * (i / 3)))
				var e = sim.make_enemy(9000 + i, t, st, pos, maxi(1, L0.fighter.level), test.has("elite"), boss)
				sim.enemies.append(e)
				i += 1
	if test.has("warpat") and test_t == int(test["warpat"]):
		world.map_open = true
		var ev = InputEventKey.new()
		ev.pressed = true
		ev.keycode = KEY_ENTER
		print("[test] warp ", world._others())
		world._map_input(ev)
	if test.has("mapshot") and test_t == int(test["mapshot"]):
		world.map_open = true
	if test.has("shots"):
		for s in test["shots"].split(",", false):
			if test_t == int(s):
				var img = get_viewport().get_texture().get_image()
				var path = str(test.get("out", "/tmp")) + "/shot_%05d.png" % test_t
				var err = img.save_png(path) if img else -1
				print("[test] shot ", path, " ", err)
	if test.has("log") and test_t % int(test["log"]) == 0:
		for L in world.locals:
			var key2: String = Game.planet.nodes[L.node_i]["key"]
			if Game.sims.has(key2):
				var ks = {}
				for sh in Game.sims[key2].eshots:
					ks[sh["k"]] = ks.get(sh["k"], 0) + 1
				print("[test] shots ", ks)
				var st = []
				for e in Game.sims[key2].enemies:
					st.append("%d:%s/%s%s@%d,%d hp%d" % [e["id"], e["state"], str(e.get("st", {}).get("id", "")) + "#" + str(e.get("ai_stack", []).map(func(q): return q[1])), "" if e["alive"] else "(dead)", e["x"], e["y"], e["hp"]])
				print("[test] enemies ", st)
			print("[test] alive ", Game.area_states.get(key2, []).size(), " drops ", Game.area_drops.get(key2, []), " hp ", L.fighter.hp, "/", L.fighter.maxhp, " sims ", Game.sims.get(key2).enemies.size() if Game.sims.has(key2) else -1)
			print("[test] t ", test_t, " P", L.k + 1, " node ", L.node_i, " at ", int(L.fighter.x), ",", int(L.fighter.y), " screen ", world.svs[0].size / 2.0 + world.views[L.node_i].offset + Vector2(L.fighter.x, L.fighter.y) - world.cams[world.locals.find(L)].position, " line ", world.line_px, " split ", world.split_now, " dir ", world.split_dir, " views ", world.views.size(), " partners ", Game.remote_states.keys())
	if test_t == int(test.get("frames", "600")):
		for L in world.locals:
			print("[test] music ", Music.current, " made ", Music.made.keys(), " playing ", Music.a.playing, " stream ", Music.a.stream, " sfx ", Sfx.streams.size())
			print("[test] quests P", L.k + 1, " ", L.fighter.quests, " done ", L.fighter.qdone, " equip ", L.fighter.equip)
			print("[test] inv P", L.k + 1, " ", L.fighter.inv, " zeni ", L.fighter.zeni, " quick ", L.fighter.quick)
			print("[test] done at ", test_t, " P", L.k + 1, " node ", L.node_i, " hp ", L.fighter.hp, " lvl ", L.fighter.level, " exp ", L.fighter.exp, " kills ", L.kills, " partners ", Game.remote_states.size(), " enemies here ", Game.area_states.get(Game.planet.nodes[L.node_i]["key"], []).size(), " host ", Game.is_host())
		get_tree().quit()

func _script_keys(script: String) -> Dictionary:
	var k = {}
	for part in script.split(";", false):
		var p = part.split(":")
		if p.size() == 3 and test_t >= int(p[0]) and test_t < int(p[1]):
			for ch in p[2]:
				k[{"u": "up", "d": "down", "l": "left", "r": "right", "a": "a", "b": "b", "F": "toggle", "s": "sp", "t": "tr", "i": "it", "n": "nx", "m": "mn", "g": "run"}.get(ch, "x")] = true
	return k

# test aid: a tour through a land - A* over its walk grid, from map to map (shows the joined world)
var walk_path = []
var walk_stuck = 0
var tour_grid: AStarGrid2D
var tour_area = ""
var tour_path = []
var tour_goal = 0
func _tour_keys(L) -> Dictionary:
	var f = L.fighter
	var a: Dictionary = L.area
	if tour_area != str(a["key"]):
		tour_area = str(a["key"])
		tour_grid = AStarGrid2D.new()
		tour_grid.region = Rect2i(0, 0, a["tw"], a["th"])
		tour_grid.cell_size = Vector2(8, 8)
		tour_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		tour_grid.update()
		var walk: PackedByteArray = a["walk"]
		var tw: int = a["tw"]
		for y in a["th"]:
			for x in tw:
				if walk[y * tw + x] == 0:
					tour_grid.set_point_solid(Vector2i(x, y), true)
		# doors and ways to other regions: walk past them, not into them (this tour stays in one region)
		for ex in Game.planet.nodes[L.node_i]["exits"]:
			var r: Array = ex["rect"]
			for y in range(int(r[1]) / 8 - 1, int(r[3]) / 8 + 2):
				for x in range(int(r[0]) / 8 - 1, int(r[2]) / 8 + 2):
					if tour_grid.is_in_boundsv(Vector2i(x, y)):
						tour_grid.set_point_solid(Vector2i(x, y), true)
		tour_path = []
		tour_goal = 0
	if tour_path.is_empty():
		var info = a.get("land", {}).get("info", {})
		var ms: Array = info.get("maps", [])
		if ms.size() <= 1:
			# a house or a small place: back out through the nearest door
			var best = null
			var bd = 1e9
			for ex in Game.planet.nodes[L.node_i]["exits"]:
				var r: Array = ex["rect"]
				var c = Vector2((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0)
				if c.distance_to(Vector2(f.x, f.y)) < bd:
					bd = c.distance_to(Vector2(f.x, f.y)); best = c
			if best == null:
				return {}
			var dv0 = best - Vector2(f.x, f.y)
			var k0 = {}
			if dv0.x > 2: k0["right"] = true
			elif dv0.x < -2: k0["left"] = true
			if dv0.y > 2: k0["down"] = true
			elif dv0.y < -2: k0["up"] = true
			return k0
		var km = Assets.json(Assets.base_dir.path_join("kit/maps.json"))
		for tries in ms.size():
			var m = ms[tour_goal % ms.size()]
			var size = Vector2(320, 240)
			for mm in km["maps"]:
				if mm["key"] == m[0]:
					size = Vector2(int(mm["tw"]) * 8, int(mm["th"]) * 8)
			var goal = Game.planet.safe_point(L.node_i, Vector2(float(m[1]), float(m[2])) + size / 2.0)
			var from = Vector2i(int(f.x) / 8, int(f.y) / 8)
			var to = Vector2i(int(goal.x) / 8, int(goal.y) / 8)
			if tour_grid.is_in_boundsv(from) and tour_grid.is_in_boundsv(to) and not tour_grid.is_point_solid(to):
				tour_grid.set_point_solid(from, false)
				tour_path = Array(tour_grid.get_id_path(from, to))
				if tour_path.size() > 4:
					print("[test] tour to map ", m[0], " (", tour_path.size(), " steps)")
					break
				if tour_path.size() > 0:
					tour_path = []   # already there: the next one
			tour_goal += 1
	if tour_path.is_empty():
		return {}
	var here = Vector2(f.x, f.y)
	while not tour_path.is_empty() and (Vector2(tour_path[0]) * 8 + Vector2(4, 4)).distance_to(here) < 6:
		tour_path.pop_front()
	if tour_path.is_empty():
		tour_goal += 1      # arrived: on to the next map
		return {}
	# knocked off the way (or back on your feet somewhere else): plan again to the same map
	if (Vector2(tour_path[0]) * 8 + Vector2(4, 4)).distance_to(here) > 28:
		tour_path = []
		return {}
	if test.has("nofight"):
		var dv1 = Vector2(tour_path[0]) * 8 + Vector2(4, 4) - here
		var k1 = {}
		if dv1.x > 1.5: k1["right"] = true
		elif dv1.x < -1.5: k1["left"] = true
		if dv1.y > 1.5: k1["down"] = true
		elif dv1.y < -1.5: k1["up"] = true
		return k1
	# a foe right in the way: fight it
	var key2: String = Game.planet.nodes[L.node_i]["key"]
	for e in Game.area_states.get(key2, []):
		var ev = Vector2(float(e[1]), float(e[2])) - here
		var by_door = false
		for ex in Game.planet.nodes[L.node_i]["exits"]:
			var r: Array = ex["rect"]
			if Rect2(r[0] - 40, r[1] - 40, r[2] - r[0] + 80, r[3] - r[1] + 80).has_point(here + ev):
				by_door = true
		if ev.length() < 30 and not (int(e[9]) & 4) and not by_door:
			var kk = {}
			if absf(ev.x) > absf(ev.y):
				kk["right" if ev.x > 0 else "left"] = test_t % 6 == 0
			else:
				kk["down" if ev.y > 0 else "up"] = test_t % 6 == 0
			kk["a"] = test_t % 18 < 3
			return kk
	var dv = Vector2(tour_path[0]) * 8 + Vector2(4, 4) - here
	var k = {}
	if dv.x > 1.5: k["right"] = true
	elif dv.x < -1.5: k["left"] = true
	if dv.y > 1.5: k["down"] = true
	elif dv.y < -1.5: k["up"] = true
	return k

func _bot_keys(L, li: int) -> Dictionary:
	if test.has("tour") and li == 0:
		return _tour_keys(L)
	# test aid: walk to the nearest enemy and fight it (punch chain, now and then a ki blast); no enemy: the next way out
	var f = L.fighter
	var node_i: int = L.node_i
	var key: String = Game.planet.nodes[node_i]["key"]
	var best = null
	var bd = 1e9
	for e in Game.area_states.get(key, []):
		var d = Vector2(float(e[1]) - f.x, float(e[2]) - f.y).length()
		if d < bd:
			bd = d; best = e
	var k = {}
	var target = Vector2.ZERO
	if test.has("explore") or (li == 1 and test.has("explore2")):
		best = null
	if best != null:
		target = Vector2(float(best[1]), float(best[2]))
	else:
		var ex = Game.planet.nodes[node_i]["exits"]
		if ex.is_empty():
			return k
		var pick = ex[(test_t / 700 + node_i + li) % ex.size()]
		var r = pick["rect"]
		target = Vector2((r[0] + r[2]) / 2.0, (r[1] + r[3]) / 2.0)
	var dv = target - Vector2(f.x, f.y)
	if best != null and dv.length() < 26:
		# face it, then hit
		if absf(dv.x) > absf(dv.y):
			k["right" if dv.x > 0 else "left"] = test_t % 6 == 0
		else:
			k["down" if dv.y > 0 else "up"] = test_t % 6 == 0
		k["a"] = test_t % 18 < 3
		return k
	if best != null and dv.length() < 90 and test_t % 120 < 3 and f.ep > 4 and (absf(dv.x) < 8 or absf(dv.y) < 8):
		k["b"] = true
		return k
	if dv.x > 2: k["right"] = true
	elif dv.x < -2: k["left"] = true
	if dv.y > 2: k["down"] = true
	elif dv.y < -2: k["up"] = true
	# stuck: wiggle
	if test_t % 240 > 200:
		k = {"up": test_t % 480 > 440, "down": test_t % 480 <= 440, "right": true}
	return k


## any window, any screen: the picture fills it (no black bars) - a bigger or wider screen shows more of the world,
## the pixels stay sharp (each game pixel is a whole number of screen pixels: 4 on a 1080p screen, 5 on 1440p)
var _fit_size = Vector2i.ZERO
var _ft_last = 0
var _ft_max = 0
func _fit_view() -> void:
	if dev != null and is_instance_valid(dev):
		return      # the DEV TOOLS size the screen themselves
	var win = get_window()
	var ws = win.size
	if ws.x <= 0 or ws.y <= 0:
		return
	var z = int(Game.cfg.get("view_zoom", 0)) if Game.cfg is Dictionary else 0
	var k = z if z > 0 else maxi(1, int(ws.y / 256))
	var sz = Vector2i(maxi(240, ws.x / k), maxi(160, ws.y / k))
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	# fractional: the picture always fills the whole window or screen (never a black border), at k x pixels
	win.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	win.content_scale_size = sz
	_fit_size = ws
