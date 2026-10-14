extends Control
## DEV TOOLS - CHECK: everything your team made, looked over before you share it - doors with nowhere to arrive,
## people or foes stuck in walls, missing sprite sets or items, events that jump to labels that aren't there,
## lines too long for the text box, maps nobody can reach... GO THERE takes you to it.
## And HISTORY: your edits as they were at every save - RESTORE goes back.

var tools
var built = false
var list: ItemList
var problems = []         # [{text, level 0 info / 1 warning / 2 error, key?, pos?, tab?}]
var hist: ItemList
var msg: Label

func show_editor() -> void:
	if not built:
		_build()
	_fill_history()

func _build() -> void:
	built = true
	var bg = ColorRect.new(); bg.color = Color(0.07, 0.08, 0.13); bg.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(bg)
	var h = HBoxContainer.new(); h.set_anchors_preset(Control.PRESET_FULL_RECT); h.offset_top = 4; h.offset_left = 4; h.offset_right = -4; h.offset_bottom = -4
	add_child(h)
	var v = VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(v)
	var bar = HBoxContainer.new(); v.add_child(bar)
	var cb = Button.new(); cb.text = "CHECK EVERYTHING"; cb.pressed.connect(run_check); bar.add_child(cb)
	var gb = Button.new(); gb.text = "GO THERE"; gb.pressed.connect(_go); bar.add_child(gb)
	msg = Label.new(); msg.autowrap_mode = TextServer.AUTOWRAP_WORD; msg.add_theme_font_size_override("font_size", 10); msg.add_theme_color_override("font_color", Color(1, 0.9, 0.55))
	msg.text = "CHECK EVERYTHING looks over your maps, characters, events, shops and mods. Red: it will not work. Yellow: probably not what you want."
	v.add_child(msg)
	list = ItemList.new(); list.size_flags_vertical = Control.SIZE_EXPAND_FILL; list.add_theme_font_size_override("font_size", 10)
	list.item_activated.connect(func(_i): _go())
	v.add_child(list)
	var rv = VBoxContainer.new(); rv.custom_minimum_size = Vector2(250, 0); h.add_child(rv)
	var l = Label.new(); l.text = "HISTORY (a copy at every save)"; l.add_theme_font_size_override("font_size", 11); l.add_theme_color_override("font_color", Color(1, 0.85, 0.35)); rv.add_child(l)
	hist = ItemList.new(); hist.size_flags_vertical = Control.SIZE_EXPAND_FILL; hist.add_theme_font_size_override("font_size", 10); rv.add_child(hist)
	var hb = HBoxContainer.new(); rv.add_child(hb)
	var bk = Button.new(); bk.text = "BACK UP NOW"; bk.pressed.connect(func(): var n = Mods.backup(true); msg.text = "Backed up: " + n; _fill_history()); hb.add_child(bk)
	var rs = Button.new(); rs.text = "RESTORE"; rs.pressed.connect(_restore); hb.add_child(rs)

func _fill_history() -> void:
	hist.clear()
	for b in Mods.list_backups():
		hist.add_item(b.replace("_", "  "))
		hist.set_item_metadata(hist.item_count - 1, b)

func _restore() -> void:
	var s = hist.get_selected_items()
	if s.is_empty():
		msg.text = "Choose a backup in the list first."
		return
	var nm = str(hist.get_item_metadata(s[0]))
	var d = ConfirmationDialog.new()
	d.dialog_text = "Go back to your edits as they were at %s?\n(What you have now is backed up first.)" % nm
	d.confirmed.connect(func():
		msg.text = Mods.restore(nm)
		if tools:
			tools._packs_changed()
		_fill_history()
		d.queue_free())
	d.canceled.connect(func(): d.queue_free())
	add_child(d)
	d.popup_centered()

# ------------------------------------------------------------------ the checks
func _add(level: int, text: String, extra: Dictionary = {}) -> void:
	var p = extra.duplicate()
	p["level"] = level
	p["text"] = text
	problems.append(p)

func run_check() -> Array:
	problems = []
	var node_of = {}
	for i in Game.planet.nodes.size():
		node_of[str(Game.planet.nodes[i]["key"])] = i
	# maps: every map your team changed (and every map of your own)
	var keys = ["land/0/0"]
	for nm in Mods.custom_maps():
		keys.append("custom/" + nm)
	var reached = {}
	var names = {}           # everyone standing on the maps (for the story steps that name someone)
	for key in keys:
		var a = Assets.area(key)
		if a.is_empty():
			_add(2, "%s: the map cannot be read" % key)
			continue
		for pp in a.get("people", []):
			names[str(pp.get("name", "")).to_upper()] = true
		var p = Mods.merged(key)
		var own = Mods.patch(key)
		for d in own["doors_add"]:
			var to = str(d.get("to", key))
			reached[to] = true
			var r: Array = d["rect"]
			var c = Vector2((float(r[0]) + float(r[2])) / 2.0, (float(r[1]) + float(r[3])) / 2.0)
			if not node_of.has(to):
				_add(2, "%s: a door leads to %s, which is not there" % [key, to], {"key": key, "pos": c})
				continue
			var ta = Assets.area(to)
			var arr = Vector2(float(d["arrive"][0]), float(d["arrive"][1]))
			if not ta.is_empty() and not Assets.walkable(ta, arr.x, arr.y):
				_add(2, "%s: a door's arrival on %s is inside a wall (you would be stuck)" % [key, to], {"key": to, "pos": arr})
		for pe in own["people_add"]:
			var q = Vector2(float(pe["x"]), float(pe["y"]))
			if Assets.sprite_set(int(pe.get("set", 0))).is_empty():
				_add(2, "%s: %s has sprite set %d, which is not there" % [key, str(pe.get("name", "?")), int(pe.get("set", 0))], {"key": key, "pos": q})
			if not _reachable(a, q, 14.0):
				_add(1, "%s: nobody can walk up to %s (walls all round)" % [key, str(pe.get("name", "?"))], {"key": key, "pos": q})
			if str(pe.get("shop", "")) != "" and not Content.shops.any(func(s): return str(s["id"]) == str(pe["shop"])):
				_add(2, "%s: %s keeps shop %s, which is not there" % [key, str(pe.get("name", "?")), str(pe["shop"])], {"key": key, "pos": q, "tab": "SHOPS"})
			if str(pe.get("event", "")) != "" and not Content.events.any(func(e): return str(e["id"]) == str(pe["event"])):
				_add(2, "%s: %s starts event %s, which is not there" % [key, str(pe.get("name", "?")), str(pe["event"])], {"key": key, "pos": q, "tab": "EVENTS"})
		for e in own["enemies_add"]:
			var q = Vector2(float(e[2]), float(e[3]))
			if int(e[0]) < 0 or int(e[0]) > 127:
				_add(2, "%s: foe kind %d does not exist (0-127)" % [key, int(e[0])], {"key": key, "pos": q})
			elif not Assets.walkable(a, q.x, q.y):
				_add(1, "%s: foe %d stands in a wall" % [key, int(e[0])], {"key": key, "pos": q})
		for it in own["items"]:
			var q = Vector2(float(it["x"]), float(it["y"]))
			if Content.item(str(it.get("id", ""))).is_empty():
				_add(2, "%s: treasure '%s' is not an item" % [key, str(it.get("id", ""))], {"key": key, "pos": q})
			elif not _reachable(a, q, 10.0):
				_add(1, "%s: treasure %s cannot be reached" % [key, str(it.get("id", ""))], {"key": key, "pos": q})
		for z in own["zones"]:
			var r: Array = z["rect"]
			var c = Vector2((float(r[0]) + float(r[2])) / 2.0, (float(r[1]) + float(r[3])) / 2.0)
			var open = 0
			for k in 12:
				if Assets.walkable(a, lerpf(float(r[0]), float(r[2]), randf()), lerpf(float(r[1]), float(r[3]), randf())):
					open += 1
			if open == 0:
				_add(1, "%s: a foe zone is all walls" % key, {"key": key, "pos": c})
		for t in own["triggers"]:
			var r: Array = t["rect"]
			if not Content.events.any(func(e): return str(e["id"]) == str(t.get("event", ""))):
				_add(2, "%s: an event box starts %s, which is not there" % [key, str(t.get("event", ""))], {"key": key, "pos": Vector2(float(r[0]), float(r[1])), "tab": "EVENTS"})
	for nm in Mods.custom_maps():
		var k2 = "custom/" + nm
		var any_door = reached.has(k2)
		for e in Content.events:
			for st in e.get("steps", []):
				if str(st.get("do", "")) == "warp" and str(st.get("map", "")) == k2:
					any_door = true
		if not any_door:
			_add(1, "%s: no door (or event) leads there - nobody can get in" % k2, {"key": k2, "pos": Vector2.ZERO})
	# events
	for e in Content.events:
		var eid = str(e.get("id", "?"))
		var labels = {}
		for st in e.get("steps", []):
			if str(st.get("do", "")) == "label":
				labels[str(st.get("name", ""))] = true
		var shown = {}
		var had_fight = false
		for st in e.get("steps", []):
			var d = str(st.get("do", ""))
			var who = str(st.get("who", "PLAYER")).to_upper()
			if d in ["move", "face", "pose", "emote", "hide_person"] or (d == "camera" and who != ""):
				if who != "PLAYER" and who != "" and not shown.has(who) and not names.has(who):
					_add(1, "event %s: %s names %s - nobody of that name is on the maps or shown before (SHOW PERSON)" % [eid, d.to_upper(), who], {"tab": "EVENTS"})
			match d:
				"show_person":
					shown[str(st.get("name", "")).to_upper()] = true
					if Assets.sprite_set(int(st.get("set", 54))).is_empty():
						_add(2, "event %s: SHOW PERSON uses sprite set %d, which is not there" % [eid, int(st.get("set", 54))], {"tab": "EVENTS"})
				"if_var", "if_timer":
					var lab2 = str(st.get("goto", ""))
					if lab2 != "" and not labels.has(lab2):
						_add(2, "event %s: jumps to label %s, which is not there" % [eid, lab2], {"tab": "EVENTS"})
				"boss_fight":
					had_fight = true
					for k in ["win", "lose"]:
						if str(st.get(k, "")) != "" and not labels.has(str(st[k])):
							_add(2, "event %s: the boss fight's %s goes to label %s, which is not there" % [eid, k.to_upper(), str(st[k])], {"tab": "EVENTS"})
					for part in str(st.get("phases", "")).split(",", false):
						var kv = part.split(":")
						if kv.size() != 2 or not kv[0].strip_edges().is_valid_float():
							_add(2, "event %s: boss phase '%s' - write it like 0.5:label" % [eid, part], {"tab": "EVENTS"})
						elif not labels.has(kv[1].strip_edges()):
							_add(2, "event %s: boss phase goes to label %s, which is not there" % [eid, kv[1].strip_edges()], {"tab": "EVENTS"})
					if int(st.get("kind", 8)) < 0 or int(st.get("kind", 8)) > 127:
						_add(2, "event %s: boss kind %d - the game's foes are 0-127" % [eid, int(st.get("kind", 8))], {"tab": "EVENTS"})
					if str(st.get("win", "")) == "":
						_add(1, "event %s: the boss fight has no WIN label - after the win the next step simply runs" % eid, {"tab": "EVENTS"})
				"fight_on":
					if not had_fight:
						_add(1, "event %s: FIGHT ON without a BOSS FIGHT before it" % eid, {"tab": "EVENTS"})
				"switch_hero":
					if Assets.CHARACTERS.find(str(st.get("hero", "")).to_upper()) < 0:
						_add(2, "event %s: SWITCH HERO to %s - not a hero" % [eid, str(st.get("hero", ""))], {"tab": "EVENTS"})
				"companion":
					var cw = str(st.get("who", "PICCOLO"))
					if not bool(st.get("leave", false)) and Assets.CHARACTERS.find(cw.to_upper()) < 0 and not (cw.is_valid_int() and not Assets.sprite_set(int(cw)).is_empty()):
						_add(2, "event %s: COMPANION %s - use a hero's name or a sprite set number" % [eid, cw], {"tab": "EVENTS"})
				"the_end":
					if Content.story.is_empty():
						_add(1, "event %s: THE END shows the credits from the STORY tab - it has no title yet" % eid, {"tab": "STORY"})
				"goto", "if_flag":
					var lab = str(st.get("label", st.get("goto", "")))
					if lab != "" and not labels.has(lab):
						_add(2, "event %s: jumps to label %s, which is not there" % [eid, lab], {"tab": "EVENTS"})
				"choice":
					for o in st.get("options", []):
						if str(o[1]) != "" and not labels.has(str(o[1])):
							_add(2, "event %s: answer %s goes to label %s, which is not there" % [eid, str(o[0]), str(o[1])], {"tab": "EVENTS"})
				"give", "take":
					if Content.item(str(st.get("item", ""))).is_empty():
						_add(2, "event %s: %s '%s' is not an item" % [eid, d, str(st.get("item", ""))], {"tab": "EVENTS"})
				"quest", "finish_quest":
					if not Content.quests.any(func(q): return str(q["id"]) == str(st.get("id", ""))):
						_add(2, "event %s: mission %s is not there" % [eid, str(st.get("id", ""))], {"tab": "EVENTS"})
				"shop":
					if not Content.shops.any(func(s): return str(s["id"]) == str(st.get("id", ""))):
						_add(2, "event %s: shop %s is not there" % [eid, str(st.get("id", ""))], {"tab": "EVENTS"})
				"warp":
					if not node_of.has(str(st.get("map", ""))):
						_add(2, "event %s: warps to %s, which is not a map" % [eid, str(st.get("map", ""))], {"tab": "EVENTS"})
			if d in ["say", "choice"]:
				var n = preload("res://scripts/dev_events.gd").box_lines(str(st.get("text", "")))
				if n > 3:
					_add(1, "event %s: a line is too long for the text box (%d lines, 3 fit)" % [eid, n], {"tab": "EVENTS"})
		var tr: Dictionary = e.get("trigger", {})
		if str(tr.get("type", "")) == "talk" and str(tr.get("person", "")) == "":
			_add(1, "event %s: starts when talking to... nobody named" % eid, {"tab": "EVENTS"})
		if e.get("steps", []).is_empty():
			_add(1, "event %s: has no steps" % eid, {"tab": "EVENTS"})
	# the story
	if not Content.story.is_empty():
		var sto: Dictionary = Content.story
		var ie = str(sto.get("intro_event", ""))
		if ie != "" and not Content.events.any(func(e): return str(e["id"]) == ie):
			_add(2, "story: the intro event %s is not there" % ie, {"tab": "STORY"})
		if Assets.CHARACTERS.find(str(sto.get("hero", "GOKU")).to_upper()) < 0:
			_add(2, "story: hero %s is not a hero" % str(sto.get("hero", "")), {"tab": "STORY"})
		var sm = str(sto.get("start_map", "land/0/0"))
		if not node_of.has(sm):
			_add(2, "story: start_map %s is not a map" % sm, {"tab": "STORY"})
		elif not Assets.walkable(Assets.area(sm), float(sto.get("x", 0)), float(sto.get("y", 0))):
			_add(2, "story: the start (%d, %d) is inside a wall" % [int(sto.get("x", 0)), int(sto.get("y", 0))], {"tab": "STORY", "key": sm, "pos": Vector2(float(sto.get("x", 0)), float(sto.get("y", 0)))})
	# heroes, foes, shops, loot, moves
	for i in Assets.CHARACTERS.size():
		var st = Assets.character_set(i)
		if Assets.sprite_set(st).is_empty():
			_add(2, "hero %s: sprite set %d is not there" % [Assets.CHARACTERS[i], st], {"tab": "HEROES"})
	for t in Content.enemy_types:
		var o: Dictionary = Content.enemy_types[t]
		if o.has("set") and int(o["set"]) >= 0 and Assets.sprite_set(int(o["set"])).is_empty():
			_add(2, "foe kind %d: sprite set %d is not there" % [int(t), int(o["set"])], {"tab": "ENEMIES"})
	for s in Content.shops:
		for it in s.get("items", []):
			if Content.item(str(it.get("id", ""))).is_empty():
				_add(2, "shop %s: sells '%s', which is not an item" % [str(s.get("id", "")), str(it.get("id", ""))], {"tab": "SHOPS"})
	for lt in Content.loot:
		for dr in lt.get("drops", []):
			if Content.item(str(dr.get("item", ""))).is_empty():
				_add(2, "loot of foe %s: '%s' is not an item" % [str(lt.get("id", "")), str(dr.get("item", ""))], {"tab": "LOOT"})
	const KINDS = ["beam", "bomb", "dash", "volley", "wave", "stretch", "flash", "heal", "slash", "buff"]
	for sk in Content.skills:
		if not str(sk.get("type", "")) in KINDS and not sk.has("rom"):
			_add(1, "move %s: kind '%s' is not one the game knows" % [str(sk.get("id", "")), str(sk.get("type", ""))], {"tab": "MOVES"})
	# forms and states named somewhere that aren't there
	var fids = {}
	for fm in Content.forms:
		fids[str(fm.get("id", ""))] = true
		if not str(fm.get("unlock", "level")) in ["level", "reward", "event"]:
			_add(1, "form %s: unlock '%s' - use level, reward or event" % [str(fm.get("id", "")), str(fm.get("unlock", ""))], {"tab": "FORMS"})
		if str(fm.get("unlock", "level")) == "reward":
			var given = false
			for q in Content.quests:
				if str(fm.get("id", "")) in q.get("reward", {}).get("forms", []):
					given = true
			for e in Content.events:
				for st in e.get("steps", []):
					if str(st.get("do", "")) == "unlock_form" and str(st.get("id", "")) == str(fm.get("id", "")):
						given = true
			if not given:
				_add(1, "form %s: unlock = reward, but no mission or event gives it" % str(fm.get("id", "")), {"tab": "FORMS"})
	var sids = {}
	for st0 in Content.states:
		sids[str(st0.get("id", ""))] = true
		if str(st0.get("form", "")) != "" and not fids.has(str(st0["form"])):
			_add(2, "state %s: form %s is not there" % [str(st0.get("id", "")), str(st0["form"])], {"tab": "STATES"})
	for q in Content.quests:
		for fid in q.get("reward", {}).get("forms", []):
			if not fids.has(str(fid)):
				_add(2, "mission %s: reward form %s is not there" % [str(q.get("id", "")), str(fid)], {"tab": "MISSIONS"})
		for sid in q.get("reward", {}).get("states", []):
			if not sids.has(str(sid)):
				_add(2, "mission %s: reward state %s is not there" % [str(q.get("id", "")), str(sid)], {"tab": "MISSIONS"})
	for sk in Content.skills:
		if str(sk.get("then_form", "")) != "" and not fids.has(str(sk["then_form"])):
			_add(2, "move %s: then_form %s is not there" % [str(sk.get("id", "")), str(sk["then_form"])], {"tab": "MOVES"})
		if str(sk.get("self_state", "")) != "" and not sids.has(str(sk["self_state"])):
			_add(2, "move %s: self_state %s is not there" % [str(sk.get("id", "")), str(sk["self_state"])], {"tab": "MOVES"})
		if sk.get("inflict") is Dictionary and not sids.has(str(sk["inflict"].get("state", ""))):
			_add(2, "move %s: inflict state %s is not there" % [str(sk.get("id", "")), str(sk["inflict"].get("state", ""))], {"tab": "MOVES"})
	for t in Content.enemy_types:
		var inf = Content.enemy_types[t].get("inflict")
		if inf is Dictionary and not sids.has(str(inf.get("state", ""))):
			_add(2, "foe kind %d: inflict state %s is not there" % [int(t), str(inf.get("state", ""))], {"tab": "ENEMIES"})
	for e in Content.events:
		for st in e.get("steps", []):
			var dd = str(st.get("do", ""))
			if dd in ["unlock_form", "lock_form", "transform"] and not fids.has(str(st.get("id", ""))):
				_add(2, "event %s: form %s is not there" % [str(e.get("id", "?")), str(st.get("id", ""))], {"tab": "EVENTS"})
			if dd == "state" and str(st.get("id", "")) != "all" and not sids.has(str(st.get("id", ""))):
				_add(2, "event %s: state %s is not there" % [str(e.get("id", "?")), str(st.get("id", ""))], {"tab": "EVENTS"})
	for c in Mods.conflicts():
		_add(0, "mods: " + c, {"tab": "SHARE"})
	for pb in Content.problems:
		_add(2, str(pb))
	problems.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
	list.clear()
	for p in problems:
		list.add_item(["  ", "! ", "!! "][int(p["level"])] + str(p["text"]))
		list.set_item_custom_fg_color(list.item_count - 1, [Color(0.75, 0.85, 1), Color(1, 0.85, 0.3), Color(1, 0.45, 0.4)][int(p["level"])])
	msg.text = "All good - nothing found." if problems.is_empty() else "%d things found (red first). Choose one, GO THERE." % problems.size()
	return problems

## can someone walk up to this point? (a free tile next to it that joins open ground)
static func _reachable(a: Dictionary, q: Vector2, r: float) -> bool:
	var free = 0
	for k in 16:
		var d = Vector2.from_angle(k * TAU / 16.0) * r
		if Assets.walkable(a, q.x + d.x, q.y + d.y):
			free += 1
	return free >= 2

func _go() -> void:
	var s = list.get_selected_items()
	if s.is_empty() or tools == null:
		return
	var p: Dictionary = problems[s[0]]
	if p.has("key"):
		tools._show_tab("MAP")
		if tools.key != str(p["key"]):
			tools._go_map(str(p["key"]))
		var pos: Vector2 = p.get("pos", Vector2.ZERO)
		if pos != Vector2.ZERO:
			tools.cam.position = pos
			tools.cam.zoom = Vector2(2, 2)
		tools._say(str(p["text"]))
	elif p.has("tab"):
		tools._show_tab(str(p["tab"]))
