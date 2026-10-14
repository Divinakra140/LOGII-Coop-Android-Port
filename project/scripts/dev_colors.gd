extends Control
## DEV TOOLS - COLORS: change the colours of any sprite set (in place, or as a new colour VARIANT: a set of its
## own, 3000 and up, e.g. a red Saibaman next to the green one) and of the tile sheets (this game's, Buu's
## Fury's, Legacy of Goku's - every map using them changes). Saved in content/colors.json.

var tools
var list: ItemList
var targets = []          # [{kind: "tiles"|"set"|"variant", key}]
var cur = -1
var rule = {}             # the rule being edited (a reference into Assets.colors)
var preview: ActorView
var tile_view: TextureRect
var orig_view: TextureRect
var sw_box: GridContainer
var picker: ColorPickerButton
var pick_from = ""
var hue_s: HSlider
var sat_s: HSlider
var val_s: HSlider
var info: Label
var name_edit: LineEdit
var set_spin: SpinBox
var built = false
var preset_pick: OptionButton
var preset_name: LineEdit
const BUILTIN_PRESETS = {
	"NIGHT": {"hue": 12.0, "sat": 0.75, "val": 0.55, "swaps": {}},
	"AUTUMN": {"hue": -45.0, "sat": 1.1, "val": 0.95, "swaps": {}},
	"SNOW": {"hue": 0.0, "sat": 0.25, "val": 1.25, "swaps": {}},
	"NAMEK": {"hue": 70.0, "sat": 1.1, "val": 1.0, "swaps": {}},
	"OLD PHOTO": {"hue": 25.0, "sat": 0.3, "val": 1.0, "swaps": {}},
	"EVIL (DARK RED)": {"hue": -120.0, "sat": 1.2, "val": 0.7, "swaps": {}},
	"GHOST": {"hue": 180.0, "sat": 0.4, "val": 1.2, "swaps": {}},
}
var crop_src: Image       # the original picture shown (a part of the sheet / the first poses of the set)
var crop_slots = []
var prev_t = 0
var prev_dir = 0
var tile_row = 0
var dirty = false
var _busy = false

func show_editor() -> void:
	if not built:
		_build()
	_fill()
	if cur < 0 and targets.size() > 0:
		_choose(0)

func _build() -> void:
	built = true
	var bg = ColorRect.new(); bg.color = Color(0.07, 0.08, 0.13); bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var h = HBoxContainer.new(); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_top = 4; h.offset_left = 4; h.offset_right = -4; h.offset_bottom = -4
	add_child(h)
	# left: what to colour
	var lv = VBoxContainer.new(); lv.custom_minimum_size = Vector2(210, 0); h.add_child(lv)
	var sh = HBoxContainer.new(); lv.add_child(sh)
	set_spin = SpinBox.new(); set_spin.min_value = 0; set_spin.max_value = 4999; set_spin.value = 60; set_spin.prefix = "set"
	sh.add_child(set_spin)
	var ob = Button.new(); ob.text = "OPEN"; ob.pressed.connect(_open_set); sh.add_child(ob)
	var bb = HBoxContainer.new(); lv.add_child(bb)
	for t in [["NEW VARIANT", _new_variant], ["DELETE", _delete]]:
		var b = Button.new(); b.text = t[0]; b.add_theme_font_size_override("font_size", 10); b.pressed.connect(t[1]); bb.add_child(b)
	list = ItemList.new(); list.size_flags_vertical = Control.SIZE_EXPAND_FILL; list.add_theme_font_size_override("font_size", 10)
	list.item_selected.connect(_choose)
	lv.add_child(list)
	# middle: the picture, before and after
	var mid = VBoxContainer.new(); mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(mid)
	info = Label.new(); info.autowrap_mode = TextServer.AUTOWRAP_WORD; info.add_theme_font_size_override("font_size", 10)
	info.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	info.text = "Pick what to colour on the left (OPEN a sprite set by its number, or a tile sheet). Click a colour below, choose its new colour; or move HUE / SATURATION / BRIGHTNESS for all of it. SAVE keeps it (content/colors.json)."
	mid.add_child(info)
	var sb = HBoxContainer.new(); mid.add_child(sb)
	var save = Button.new(); save.text = "SAVE"; save.pressed.connect(_save); sb.add_child(save)
	var reset = Button.new(); reset.text = "RESET COLOURS"; reset.pressed.connect(_reset); sb.add_child(reset)
	name_edit = LineEdit.new(); name_edit.placeholder_text = "variant name"; name_edit.custom_minimum_size = Vector2(160, 0)
	name_edit.text_changed.connect(func(t): if not rule.is_empty(): rule["name"] = t.to_upper(); dirty = true)
	sb.add_child(name_edit)
	var up = Button.new(); up.text = "SHEET ▲"; up.pressed.connect(func(): tile_row = maxi(0, tile_row - 32); _refresh_picture(true)); sb.add_child(up)
	var dn = Button.new(); dn.text = "SHEET ▼"; dn.pressed.connect(func(): tile_row += 32; _refresh_picture(true)); sb.add_child(dn)
	var holder = Control.new(); holder.custom_minimum_size = Vector2(160, 120); mid.add_child(holder)
	var pbg = ColorRect.new(); pbg.color = Color(0.2, 0.32, 0.2); pbg.size = Vector2(160, 120); holder.add_child(pbg)
	preview = ActorView.new(); preview.position = Vector2(80, 104); preview.scale = Vector2(3, 3); holder.add_child(preview)
	var pics = HBoxContainer.new(); pics.size_flags_vertical = Control.SIZE_EXPAND_FILL; mid.add_child(pics)
	var ov = VBoxContainer.new(); ov.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pics.add_child(ov)
	var l1 = Label.new(); l1.text = "BEFORE"; l1.add_theme_font_size_override("font_size", 10); ov.add_child(l1)
	orig_view = TextureRect.new(); orig_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; orig_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	orig_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; orig_view.size_flags_vertical = Control.SIZE_EXPAND_FILL; ov.add_child(orig_view)
	var nv = VBoxContainer.new(); nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL; pics.add_child(nv)
	var l2 = Label.new(); l2.text = "AFTER"; l2.add_theme_font_size_override("font_size", 10); nv.add_child(l2)
	tile_view = TextureRect.new(); tile_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; tile_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tile_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; tile_view.size_flags_vertical = Control.SIZE_EXPAND_FILL; nv.add_child(tile_view)
	# right: the colours
	var rs = ScrollContainer.new(); rs.custom_minimum_size = Vector2(262, 0); rs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; h.add_child(rs)
	var rv = VBoxContainer.new(); rv.custom_minimum_size = Vector2(250, 0); rs.add_child(rv)
	hue_s = _slider(rv, "HUE", -180, 180, 0, "hue")
	sat_s = _slider(rv, "SATURATION", 0, 2, 1, "sat")
	val_s = _slider(rv, "BRIGHTNESS", 0, 2, 1, "val")
	# looks to put on anything in one click (and your own, saved in content/color_presets.json)
	var pr = HBoxContainer.new(); rv.add_child(pr)
	preset_pick = OptionButton.new(); preset_pick.add_theme_font_size_override("font_size", 9); pr.add_child(preset_pick)
	var ap = Button.new(); ap.text = "APPLY"; ap.add_theme_font_size_override("font_size", 9); ap.pressed.connect(_apply_preset); pr.add_child(ap)
	var ps = HBoxContainer.new(); rv.add_child(ps)
	preset_name = LineEdit.new(); preset_name.placeholder_text = "preset name"; preset_name.custom_minimum_size = Vector2(130, 0); ps.add_child(preset_name)
	var sp = Button.new(); sp.text = "SAVE AS PRESET"; sp.add_theme_font_size_override("font_size", 9); sp.pressed.connect(_save_preset); ps.add_child(sp)
	_fill_presets()
	var l3 = Label.new(); l3.text = "ITS COLOURS (click one, then choose the new colour):"; l3.add_theme_font_size_override("font_size", 10); l3.autowrap_mode = TextServer.AUTOWRAP_WORD; rv.add_child(l3)
	sw_box = GridContainer.new(); sw_box.columns = 7; rv.add_child(sw_box)
	var pl = Label.new(); pl.text = "ITS NEW COLOUR:"; pl.add_theme_font_size_override("font_size", 10); rv.add_child(pl)
	picker = ColorPickerButton.new(); picker.custom_minimum_size = Vector2(240, 30); picker.edit_alpha = false
	picker.color_changed.connect(_picked)
	rv.add_child(picker)
	var pk = picker.get_picker(); pk.presets_visible = false

func _slider(parent: Control, label: String, lo: float, hi: float, v: float, key: String) -> HSlider:
	var l = Label.new(); l.text = label; l.add_theme_font_size_override("font_size", 10); parent.add_child(l)
	var s = HSlider.new(); s.min_value = lo; s.max_value = hi; s.step = 1 if hi > 10 else 0.02; s.value = v
	s.value_changed.connect(func(x):
		if _busy or rule.is_empty() and cur < 0:
			return
		_rule_now()[key] = x
		dirty = true
		_refresh_picture(false))
	parent.add_child(s)
	return s

# ------------------------------------------------------------------ the list
func _fill() -> void:
	targets = []
	list.clear()
	targets.append({"kind": "tiles", "key": "kit", "name": "TILES: LEGACY OF GOKU II"})
	for g in Assets.LIB_GAMES:
		if Assets.has_library(g):
			targets.append({"kind": "tiles", "key": g, "name": "TILES: " + Assets.LIB_TITLES[g]})
	var ks = Assets.colors["sets"].keys()
	ks.sort_custom(func(a, b): return int(a) < int(b))
	for k in ks:
		targets.append({"kind": "set", "key": str(k), "name": "SET %s" % k})
	for v in Assets.colors["variants"]:
		targets.append({"kind": "variant", "key": int(v["id"]), "name": "%d %s (set %d)" % [int(v["id"]), str(v.get("name", "VARIANT")), int(v.get("base", 0))]})
	for t in targets:
		list.add_item(t["name"])
	if cur >= targets.size():
		cur = -1

func _choose(i: int) -> void:
	cur = i
	list.select(i)
	var t = targets[i]
	rule = _rule_now()
	_busy = true
	hue_s.value = float(rule.get("hue", 0.0)); sat_s.value = float(rule.get("sat", 1.0)); val_s.value = float(rule.get("val", 1.0))
	_busy = false
	name_edit.visible = t["kind"] == "variant"
	name_edit.text = str(rule.get("name", ""))
	tile_row = 0
	_refresh_picture(true)

## the rule of the chosen thing (made when first changed)
func _rule_now() -> Dictionary:
	if cur < 0:
		return {}
	var t = targets[cur]
	match t["kind"]:
		"tiles":
			if not Assets.colors["tiles"].has(t["key"]):
				Assets.colors["tiles"][t["key"]] = {"hue": 0.0, "sat": 1.0, "val": 1.0, "swaps": {}}
			return Assets.colors["tiles"][t["key"]]
		"set":
			if not Assets.colors["sets"].has(t["key"]):
				Assets.colors["sets"][t["key"]] = {"hue": 0.0, "sat": 1.0, "val": 1.0, "swaps": {}}
			return Assets.colors["sets"][t["key"]]
		_:
			return Assets.variant(int(t["key"]))

func _open_set() -> void:
	var n = int(set_spin.value)
	if Assets.sprite_set(n).is_empty():
		info.text = "There is no sprite set %d (this game's 0-299, Buu's Fury 1000+, Legacy of Goku 2000+ after OTHER GAMES)." % n
		return
	var k = str(n)
	if not Assets.colors["sets"].has(k):
		Assets.colors["sets"][k] = {"hue": 0.0, "sat": 1.0, "val": 1.0, "swaps": {}}
	_fill()
	for i in targets.size():
		if targets[i]["kind"] == "set" and targets[i]["key"] == k:
			_choose(i)

func _new_variant() -> void:
	var base = int(set_spin.value)
	if cur >= 0 and targets[cur]["kind"] == "set":
		base = int(targets[cur]["key"])
	if Assets.sprite_set(Assets.set_base(base)).is_empty():
		info.text = "Choose the set it is made from first (the number box, or a SET in the list)."
		return
	var id = Assets.VARIANT_BASE
	while not Assets.variant(id).is_empty():
		id += 1
	var r = {"id": id, "base": Assets.set_base(base), "name": "VARIANT %d" % (id - Assets.VARIANT_BASE + 1), "hue": 120.0, "sat": 1.0, "val": 1.0, "swaps": {}}
	Assets.colors["variants"].append(r)
	dirty = true
	_fill()
	_choose(targets.size() - 1)
	info.text = "Variant %d made from set %d - a sprite set of its own: give it to a hero, a foe kind or a person (sprite set %d)." % [id, r["base"], id]

func _delete() -> void:
	if cur < 0:
		return
	var t = targets[cur]
	match t["kind"]:
		"tiles":
			Assets.colors["tiles"].erase(t["key"])
		"set":
			Assets.colors["sets"].erase(t["key"])
		"variant":
			Assets.colors["variants"] = Assets.colors["variants"].filter(func(v): return int(v["id"]) != int(t["key"]))
	dirty = true
	cur = -1
	_fill()
	if targets.size() > 0:
		_choose(0)

func _reset() -> void:
	var r = _rule_now()
	if r.is_empty():
		return
	r["hue"] = 0.0; r["sat"] = 1.0; r["val"] = 1.0; r["swaps"] = {}
	dirty = true
	_choose(cur)

# ------------------------------------------------------------------ the picture
func _refresh_picture(new_crop: bool) -> void:
	if cur < 0:
		return
	var t = targets[cur]
	if new_crop:
		crop_slots = []
		if t["kind"] == "tiles":
			var path = Assets.base_dir.path_join("kit/tiles.png") if t["key"] == "kit" else Assets.base_dir.path_join("lib/%s/tiles.png" % t["key"])
			var img = Image.load_from_file(path)
			if img == null:
				return
			var rows = img.get_height() / 8
			tile_row = clampi(tile_row, 0, maxi(0, rows - 32))
			crop_src = img.get_region(Rect2i(0, tile_row * 8, img.get_width(), mini(256, img.get_height() - tile_row * 8)))
		else:
			var base = Assets.set_base(int(t["key"]))
			var img = Image.load_from_file(Assets.set_path(base, "png"))
			var j = Assets.json(Assets.set_path(base, "json"))
			if img == null or j == null:
				return
			var n = mini(j["slots"].size(), 8)       # standing and walking
			crop_slots = j["slots"].slice(0, n)
			crop_src = img.get_region(Rect2i(0, 0, img.get_width(), mini(img.get_height(), n * int(j["cell"]))))
		orig_view.texture = ImageTexture.create_from_image(crop_src)
		_fill_swatches()
	var after = Assets.recolor(crop_src, _rule_now())
	tile_view.texture = ImageTexture.create_from_image(after)
	preview.visible = t["kind"] != "tiles"
	if preview.visible:
		preview.set_sprite_set({"tex": tile_view.texture, "cell": 64, "slots": crop_slots})

func _process(_dt: float) -> void:
	if not visible or preview == null or not preview.visible:
		return
	prev_t += 1
	if prev_t % 120 == 0:
		prev_dir = (prev_dir + 1) % 4
	var fr = preview.frames_of(1, prev_dir)
	preview.show_frame(1, prev_dir, (prev_t / 8) % maxi(1, fr.size()))

## the picture's own colours, the most used first
func _fill_swatches() -> void:
	for c in sw_box.get_children():
		c.queue_free()
	var count = {}
	var px: PackedInt32Array = crop_src.get_data().to_int32_array() if crop_src.get_format() == Image.FORMAT_RGBA8 else PackedInt32Array()
	if px.is_empty():
		var im: Image = crop_src.duplicate(); im.convert(Image.FORMAT_RGBA8); px = im.get_data().to_int32_array()
	var step = maxi(1, px.size() / 60000)
	var i = 0
	while i < px.size():
		var v = px[i]
		if (v >> 24) & 0xFF != 0:
			count[v | 0xFF000000] = count.get(v | 0xFF000000, 0) + 1
		i += step
	var ks = count.keys()
	ks.sort_custom(func(a, b): return count[a] > count[b])
	var swaps: Dictionary = _rule_now().get("swaps", {})
	for k in ks.slice(0, 48):
		var c = Color8(k & 0xFF, (k >> 8) & 0xFF, (k >> 16) & 0xFF)
		var hx = c.to_html(false)
		var b = Button.new(); b.custom_minimum_size = Vector2(28, 22); b.tooltip_text = hx
		var st = StyleBoxFlat.new(); st.bg_color = c
		if swaps.has(hx):
			st.border_color = Color.html(str(swaps[hx])); st.set_border_width_all(4)
		b.add_theme_stylebox_override("normal", st); b.add_theme_stylebox_override("hover", st)
		b.pressed.connect(func(): pick_from = hx; picker.color = Color.html(str(swaps.get(hx, hx))); info.text = "Colour %s: choose its new colour with the picker (the border shows the new one)." % hx)
		sw_box.add_child(b)

func _picked(c: Color) -> void:
	if pick_from == "" or cur < 0:
		return
	var r = _rule_now()
	if not r.has("swaps"):
		r["swaps"] = {}
	if c.to_html(false) == pick_from:
		r["swaps"].erase(pick_from)
	else:
		r["swaps"][pick_from] = c.to_html(false)
	dirty = true
	_refresh_picture(false)

func _presets() -> Dictionary:
	var out = BUILTIN_PRESETS.duplicate(true)
	for f in Mods.content_paths("color_presets"):
		var t = Mods.read_json(f)
		if t is Dictionary and t.get("presets") is Dictionary:
			out.merge(t["presets"], true)
	return out

func _fill_presets() -> void:
	preset_pick.clear()
	for k in _presets():
		preset_pick.add_item(k)

func _apply_preset() -> void:
	if cur < 0 or preset_pick.item_count == 0:
		return
	var p: Dictionary = _presets().get(preset_pick.get_item_text(preset_pick.selected), {})
	var r = _rule_now()
	for k in ["hue", "sat", "val"]:
		r[k] = float(p.get(k, r.get(k, 1.0 if k != "hue" else 0.0)))
	if not r.has("swaps"):
		r["swaps"] = {}
	r["swaps"].merge(p.get("swaps", {}), true)
	dirty = true
	_choose(cur)
	info.text = "Preset %s put on it - SAVE to keep it." % preset_pick.get_item_text(preset_pick.selected)

func _save_preset() -> void:
	var nm = preset_name.text.strip_edges().to_upper()
	if nm == "" or cur < 0:
		info.text = "Give the preset a name (and choose what to take it from)."
		return
	var path = Assets.exe_dir().path_join("content/color_presets.json")
	var t = Mods.read_json(path)
	if not t is Dictionary:
		t = {"presets": {}}
	t["presets"][nm] = _rule_now().duplicate(true)
	t["presets"][nm].erase("id"); t["presets"][nm].erase("base"); t["presets"][nm].erase("name")
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(t, "  "))
		f.close()
	_fill_presets()
	info.text = "Preset %s saved (content/color_presets.json) - APPLY it to any set or tile sheet." % nm

func _save() -> void:
	# rules left plain are left out
	var out = {"sets": {}, "variants": Assets.colors["variants"], "tiles": {}}
	for k in Assets.colors["sets"]:
		if not Assets.rule_is_plain(Assets.colors["sets"][k]):
			out["sets"][k] = Assets.colors["sets"][k]
	for k in Assets.colors["tiles"]:
		if not Assets.rule_is_plain(Assets.colors["tiles"][k]):
			out["tiles"][k] = Assets.colors["tiles"][k]
	Mods.backup()
	var path = Assets.exe_dir().path_join("content/colors.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		info.text = "Could not save content/colors.json - is the game folder read-only?"
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	var keep = Assets.colors
	Assets.load_colors()
	dirty = false
	if tools and tools.has_method("colors_changed"):
		tools.colors_changed()
	info.text = "Saved to content/colors.json. The maps and characters use the new colours now (and in the game)."
	_fill()
