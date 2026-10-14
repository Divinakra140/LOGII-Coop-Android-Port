extends RefCounted
## EVENTS in the game (made in DEV TOOLS - EVENTS, content/events.json): scenes, talks with choices, story flags,
## rewards, doors that open later, bosses. One event runs per player at a time; while it runs it has the buttons.
##
## event: {"id", "name", "trigger": {"type": "talk"|"area"|"enter"|"start"|"defeat", "person", "map", "kind"},
##         "if": {"flags": [...], "not_flags": [...], "level": n, "quest_done": id, "has_item": id}, "once": true,
##         "steps": [{"do": ...}, ...]}
## steps: say {who, text}  choice {text, options: [[label, goto]]}  label {name}  goto {label}  if_flag {name, goto}
##        flag {name, on}  give {item, count}  take {item, count}  zeni {amount}  exp {amount}  heal
##        quest {id}  finish_quest {id}  wait {frames}  fade  warp {map, x, y}  spawn {kind, level, boss, x, y}
##        shop {id}  sound {name}  music {name}  toast {text}  end
##  scenes: move {who, x, y, speed, wait}  face {who, dir}  pose {who, pose, loop}  camera {x, y | who, zoom, frames, wait}
##          camera_back  shake {amount}  show_person {name, set, x, y, dir}  hide_person {who}  emote {who, kind}
##          say {face: sprite set}  boss_fight {kind, level, x, y, name, win, lose, phases "0.5:label"}  fight_on
##  logic:  var {name, op, value, max}  if_var {name, cmp, value, goto}  timer {name, seconds, show}  if_timer {name, goto}
##  story:  companion {who, name, level, leave}  switch_hero {hero}  open_area / close_area {x0, y0, x1, y1, id}  save  the_end

var world

func _init(w) -> void:
	world = w

func find(id: String) -> Dictionary:
	for e in Content.events:
		if str(e.get("id", "")) == id:
			return e
	return {}

## may this event start for this player now?
func allowed(L, e: Dictionary) -> bool:
	var f = L.fighter
	if e.is_empty():
		return false
	if bool(e.get("once", true)) and f.flags.has("event:" + str(e["id"])):
		return false
	var c: Dictionary = e.get("if", {})
	for fl in c.get("flags", []):
		if not f.flags.get(str(fl), false):
			return false
	for fl in c.get("not_flags", []):
		if f.flags.get(str(fl), false):
			return false
	if int(c.get("level", 0)) > f.level:
		return false
	if str(c.get("quest_done", "")) != "" and not f.qdone.has(str(c["quest_done"])):
		return false
	if str(c.get("has_item", "")) != "" and int(f.inv.get(str(c["has_item"]), 0)) <= 0:
		return false
	if str(c.get("has_state", "")) != "" and not f.states.has(str(c["has_state"])):
		return false
	if str(c.get("in_form", "")) != "" and str(f.form().get("id", "")) != str(c["in_form"]):
		return false
	if str(c.get("has_form", "")) != "" and not f.flags.has("form:" + str(c["has_form"])):
		return false
	return true

func start(L, id: String) -> bool:
	var e = find(id)
	if e.is_empty() or not L.ev.is_empty() or not allowed(L, e):
		return false
	L.ev = {"id": id, "pc": 0, "wait": 0, "sel": 0, "say": {}, "choice": [], "hold": true}
	L.fighter.flags["event:" + id] = true
	L.talk = {}
	_run(L)
	return true

## the triggers
func on_talk(L, person: Dictionary) -> bool:
	if str(person.get("event", "")) != "" and start(L, str(person["event"])):
		return true
	var nm = str(person.get("name", ""))
	for e in Content.events:
		var t: Dictionary = e.get("trigger", {})
		if str(t.get("type", "")) == "talk" and str(t.get("person", "")).to_upper() == nm.to_upper() and allowed(L, e):
			return start(L, str(e["id"]))
	return false

func on_enter(L, key: String) -> void:
	for e in Content.events:
		var t: Dictionary = e.get("trigger", {})
		if str(t.get("type", "")) == "enter" and str(t.get("map", "")) == key and allowed(L, e):
			start(L, str(e["id"]))
			return

func on_start(L) -> void:
	for e in Content.events:
		if str(e.get("trigger", {}).get("type", "")) == "start" and allowed(L, e):
			start(L, str(e["id"]))
			return

func on_defeat(L, kind: int) -> void:
	for e in Content.events:
		var t: Dictionary = e.get("trigger", {})
		if str(t.get("type", "")) == "defeat" and int(t.get("kind", -1)) == kind and allowed(L, e):
			start(L, str(e["id"]))
			return

## walking into an event box of the map (DEV TOOLS - EVENT tool)
func check_area(L) -> void:
	if not L.ev.is_empty():
		return
	var trig: Array = Game.planet.nodes[L.node_i]["spec"].get("triggers", [])
	var inside = {}
	for t in trig:
		var r: Array = t["rect"]
		if bool(t.get("attack", false)):
			# (a rock to break, a switch to hit: only an attack landing in the box starts it)
			if _attack_in(L.fighter, r) and allowed(L, find(str(t["event"]))):
				start(L, str(t["event"]))
				return
			continue
		if L.fighter.x >= float(r[0]) and L.fighter.x <= float(r[2]) and L.fighter.y >= float(r[1]) and L.fighter.y <= float(r[3]):
			inside[str(t["event"])] = true
			if not L.in_trig.has(str(t["event"])):
				start(L, str(t["event"]))
	L.in_trig = inside

# ------------------------------------------------------------------ running
## one tick: true while the event has the buttons
func tick(L, raw: Dictionary) -> bool:
	if L.ev.is_empty():
		return false
	var ev: Dictionary = L.ev
	var a = bool(raw.get("a", false))
	var a_new = a and not ev.get("a_prev", true)
	var up_new = bool(raw.get("up", false)) and not ev.get("up_prev", true)
	var dn_new = bool(raw.get("down", false)) and not ev.get("dn_prev", true)
	ev["a_prev"] = a; ev["up_prev"] = bool(raw.get("up", false)); ev["dn_prev"] = bool(raw.get("down", false))
	_step_moves(L)
	if ev.has("fight"):
		var fr = _step_fight(L)
		if fr == "go":
			_run(L)
			return not L.ev.is_empty() and str(L.ev.get("until", "")) != "fight"
		if str(ev.get("until", "")) == "fight":
			return false          # (the fight goes on: the player has the buttons)
		_hold_boss(L)
	var u = str(ev.get("until", ""))
	if u == "moves":
		if ev.get("moves", []).is_empty():
			ev["until"] = ""
			_run(L)
		return true
	if u == "camera":
		if L.cut_cam.is_empty() or int(L.cut_cam.get("t", 0)) >= int(L.cut_cam.get("n", 1)):
			ev["until"] = ""
			_run(L)
		return true
	if int(ev["wait"]) > 0:
		ev["wait"] -= 1
		if ev["wait"] <= 0:
			_run(L)
		return true
	if not ev["choice"].is_empty():
		if up_new:
			ev["sel"] = (int(ev["sel"]) + ev["choice"].size() - 1) % ev["choice"].size(); Sfx.play("move", 0.6)
		if dn_new:
			ev["sel"] = (int(ev["sel"]) + 1) % ev["choice"].size(); Sfx.play("move", 0.6)
		if a_new:
			var to = str(ev["choice"][int(ev["sel"])][1])
			ev["choice"] = []
			ev["say"] = {}
			Sfx.play("menu", 0.7)
			if to != "":
				_goto(L, to)
			_run(L)
		return true
	if not ev["say"].is_empty():
		if a_new:
			ev["say"] = {}
			Sfx.play("move", 0.7)
			_run(L)
		return true
	_run(L)
	return not L.ev.is_empty()

func _goto(L, label: String) -> void:
	var e = find(str(L.ev["id"]))
	var steps: Array = e.get("steps", [])
	for i in steps.size():
		if str(steps[i].get("do", "")) == "label" and str(steps[i].get("name", "")) == label:
			L.ev["pc"] = i + 1
			return
	L.ev["pc"] = steps.size()

## run steps until one waits (a line to read, a choice, a pause) or the event ends
func _run(L) -> void:
	var guard = 0
	while not L.ev.is_empty() and guard < 200:
		guard += 1
		var e = find(str(L.ev["id"]))
		var steps: Array = e.get("steps", [])
		var pc = int(L.ev["pc"])
		if pc >= steps.size():
			L.ev = {}
			break
		var st: Dictionary = steps[pc]
		L.ev["pc"] = pc + 1
		var f = L.fighter
		match str(st.get("do", "")):
			"say":
				L.ev["say"] = {"who": str(st.get("who", "")), "text": _text(L, str(st.get("text", ""))), "face": int(st.get("face", -1))}
				return
			"choice":
				L.ev["say"] = {"who": str(st.get("who", "")), "text": _text(L, str(st.get("text", ""))), "face": int(st.get("face", -1))}
				L.ev["choice"] = st.get("options", [["OK", ""]])
				L.ev["sel"] = 0
				return
			"label":
				pass
			"goto":
				_goto(L, str(st.get("label", "")))
			"if_flag":
				if f.flags.get(str(st.get("name", "")), false):
					_goto(L, str(st.get("goto", "")))
			"flag":
				if bool(st.get("on", true)):
					f.flags[str(st.get("name", ""))] = true
				else:
					f.flags.erase(str(st.get("name", "")))
			"give":
				var n = f.add_item(str(st.get("item", "senzu")), int(st.get("count", 1)))
				if n > 0:
					world.toasts.append(["GOT %s x%d" % [str(Content.item(str(st.get("item", ""))).get("name", st.get("item", ""))), n], Color(0.7, 1, 0.8), 160])
			"take":
				var id = str(st.get("item", ""))
				f.inv[id] = maxi(0, int(f.inv.get(id, 0)) - int(st.get("count", 1)))
			"zeni":
				f.zeni = maxi(0, f.zeni + int(st.get("amount", 0)))
				world.toasts.append(["%+d ZENI" % int(st.get("amount", 0)), Color(1, 0.9, 0.5), 140])
			"exp":
				var up = f.add_exp(maxi(1, int(st.get("amount", 0))), world.levels)
				world.toasts.append(["+%d EXP%s" % [int(st.get("amount", 0)), "  LEVEL UP!" if up else ""], Color(0.6, 1, 0.6), 160])
			"heal":
				f.hp = f.maxhp; f.ep = f.maxep
			"unlock_form":
				var fid = str(st.get("id", ""))
				if f.unlock_form(fid):
					world.toasts.append(["NEW TRANSFORMATION: %s  (TRANSFORM BUTTON)" % str(Content.form_by_id(fid).get("name", fid)), Color(1, 0.85, 0.3), 300])
			"lock_form":
				f.lock_form(str(st.get("id", "")))
			"transform":
				f.force_form(str(st.get("id", "")))
			"revert":
				if f.form_i >= 0:
					f._revert()
			"state":
				if bool(st.get("off", false)):
					if str(st.get("id", "")) == "all":
						f.clear_states()
					else:
						f.remove_state(str(st.get("id", "")))
				else:
					f.add_state(str(st.get("id", "")), float(st.get("seconds", -1)))
			"quest":
				var qid = str(st.get("id", ""))
				if not f.quests.has(qid) and not f.qdone.has(qid):
					f.quests[qid] = 0
					world.toasts.append(["NEW MISSION: " + str(_quest_name(qid)), Color(0.6, 1, 0.7), 200])
			"finish_quest":
				var qid2 = str(st.get("id", ""))
				for q in Content.quests:
					if str(q["id"]) == qid2 and f.quests.has(qid2):
						world._quest_done(L, q)
			"wait":
				L.ev["wait"] = int(st.get("frames", 60))
				return
			"fade":
				L.fade = 1.0; L.fade_dir = -1
			"warp":
				var key = str(st.get("map", ""))
				for ni in Game.planet.nodes.size():
					if str(Game.planet.nodes[ni]["key"]) == key:
						world._warp(L, ni, Vector2(float(st.get("x", 0)), float(st.get("y", 0))))
						break
			"spawn":
				var sim = Game.sims.get(str(Game.planet.nodes[L.node_i]["key"]))
				if sim:
					var t = int(st.get("kind", 8))
					var p = Vector2(float(st.get("x", f.x + 60)), float(st.get("y", f.y)))
					if float(st.get("x", -1)) < 0:
						p = Vector2(f.x + 60, f.y)
					var e2 = sim.make_enemy(8000 + sim.enemies.size(), t, Assets.set_for_type(t), sim._open_near(p), maxi(1, int(st.get("level", f.level))), false, bool(st.get("boss", false)))
					e2["respawn_ms"] = 1 << 40
					e2["minion"] = true
					sim.enemies.append(e2)
			"shop":
				world._open_shop(L, str(st.get("id", "")))
			"sound":
				Sfx.play(str(st.get("name", "menu")))
			"music":
				Music.play(str(st.get("name", "field")))
			"toast":
				world.toasts.append([_text(L, str(st.get("text", ""))), Color(1, 0.95, 0.7), 200])
			"end":
				L.ev = {}
				break
			# ---------------------------------------------------- scenes
			"move":
				var who = str(st.get("who", "PLAYER"))
				if not L.ev.has("moves"):
					L.ev["moves"] = []
				L.ev["moves"].append({"who": who, "x": float(st.get("x", f.x)), "y": float(st.get("y", f.y)), "speed": maxf(0.2, float(st.get("speed", 1.0)))})
				if bool(st.get("wait", true)):
					L.ev["until"] = "moves"
					return
			"face":
				_face(L, str(st.get("who", "PLAYER")), _dir_of(st.get("dir", "down")))
			"pose":
				var pw = str(st.get("who", "PLAYER"))
				var pz = int(st.get("pose", 0))
				if pw.to_upper() == "PLAYER":
					f.scene_pose = pz if pz >= 0 else -1
					f.scene_t = 0; f.scene_loop = bool(st.get("loop", false))
				else:
					var pp = _person(L, pw)
					if not pp.is_empty():
						pp["cut_pose"] = [pz, bool(st.get("loop", false)), Engine.get_physics_frames()] if pz >= 0 else []
			"camera":
				var to = Vector2(float(st.get("x", f.x)), float(st.get("y", f.y)))
				var cw = str(st.get("who", ""))
				if cw != "":
					if cw.to_upper() == "PLAYER":
						to = Vector2(f.x, f.y)
					else:
						var cp = _person(L, cw)
						if not cp.is_empty():
							to = Vector2(float(cp["x"]), float(cp["y"]))
				L.cut_cam = {"from": L.cam if L.cam != Vector2.ZERO else Vector2(f.x, f.y - 12), "to": to, "t": 0, "n": maxi(1, int(st.get("frames", 45))), "zoom": maxf(0.5, float(st.get("zoom", 1.0)))}
				if bool(st.get("wait", true)):
					L.ev["until"] = "camera"
					return
			"camera_back":
				L.cut_cam = {}
			"shake":
				L.shake = maxf(L.shake, float(st.get("amount", 4)))
			"show_person":
				var np = {"name": str(st.get("name", "SOMEONE")), "set": int(st.get("set", 54)), "x": float(st.get("x", f.x + 30)), "y": float(st.get("y", f.y)),
					"lines": [], "cut_dir": _dir_of(st.get("dir", "down"))}
				_remove_person(L, np["name"])
				L.area["people"].append(np)
				f.flags["shown:%s:%s" % [_key(L), np["name"]]] = np.duplicate()
				f.flags.erase("hidden:%s:%s" % [_key(L), str(np["name"]).to_upper()])
			"hide_person":
				var hw = str(st.get("who", ""))
				var hp2 = _person(L, hw)
				if not hp2.is_empty():
					hp2["hidden"] = true
				f.flags["hidden:%s:%s" % [_key(L), hw.to_upper()]] = [float(hp2["x"]), float(hp2["y"])] if not hp2.is_empty() else true
				f.flags.erase("shown:%s:%s" % [_key(L), hw])
			"emote":
				var ew = str(st.get("who", "PLAYER"))
				var kind = str(st.get("kind", "!"))
				if ew.to_upper() == "PLAYER":
					world.emote_player(L, kind)
				else:
					var ep2 = _person(L, ew)
					if not ep2.is_empty():
						ep2["emote"] = [kind, Engine.get_physics_frames() + 100]
			"boss_fight":
				if _start_fight(L, st):
					L.ev["until"] = "fight"
					return
			"fight_on":
				if L.ev.has("fight"):
					L.ev["until"] = "fight"
					return
			# ---------------------------------------------------- logic
			"var":
				var vn = "var:" + str(st.get("name", "x"))
				var cur_v = float(f.flags.get(vn, 0))
				var val = float(st.get("value", 0))
				match str(st.get("op", "set")):
					"add": cur_v += val
					"sub": cur_v -= val
					"mul": cur_v *= val
					"random": cur_v = randi_range(int(val), int(st.get("max", val + 10)))
					_: cur_v = val
				f.flags[vn] = cur_v
			"if_var":
				var vv = float(f.flags.get("var:" + str(st.get("name", "x")), 0))
				var cv = float(st.get("value", 0))
				var ok = false
				match str(st.get("cmp", "=")):
					"=", "==": ok = is_equal_approx(vv, cv)
					"!=": ok = not is_equal_approx(vv, cv)
					"<": ok = vv < cv
					"<=": ok = vv <= cv
					">": ok = vv > cv
					">=": ok = vv >= cv
				if ok:
					_goto(L, str(st.get("goto", "")))
			"timer":
				f.flags["timer:" + str(st.get("name", "t"))] = {"end": int(Time.get_unix_time_from_system() * 1000.0) + int(float(st.get("seconds", 30)) * 1000), "show": bool(st.get("show", true))}
			"if_timer":
				var td = f.flags.get("timer:" + str(st.get("name", "t")), {})
				if td is Dictionary and not td.is_empty() and int(Time.get_unix_time_from_system() * 1000.0) >= int(td.get("end", 0)):
					f.flags.erase("timer:" + str(st.get("name", "t")))
					_goto(L, str(st.get("goto", "")))
			# ---------------------------------------------------- story
			"companion":
				if bool(st.get("leave", false)):
					world.companion_leave(L, str(st.get("name", "")))
				else:
					world.companion_join(L, str(st.get("who", "PICCOLO")), str(st.get("name", "")), int(st.get("level", 0)))
			"switch_hero":
				world.switch_hero(L, str(st.get("hero", "GOKU")))
				f = L.fighter
			"open_area", "close_area":
				var r = [float(st.get("x0", 0)), float(st.get("y0", 0)), float(st.get("x1", 0)), float(st.get("y1", 0))]
				var oid = str(st.get("id", "area%d" % hash(str(r))))
				var opening = str(st.get("do", "")) == "open_area"
				f.flags["open:" + oid] = {"key": _key(L), "rect": r, "walk": opening}
				world.apply_open(_key(L), r, opening)
			"save":
				Game.save_fighter(f, L.k)
				world.save_all()
				world.toasts.append(["THE STORY IS SAVED", Color(0.7, 1, 0.8), 160])
				Sfx.play("levelup", 0.5)
			"the_end":
				L.ev = {}
				Game.save_fighter(f, L.k)
				world.show_credits()
				break
	if guard >= 200:
		L.ev = {}
	if L.ev.is_empty():
		_cleanup(L)
		Game.save_fighter(L.fighter, L.k)      # the story so far is kept

static func _quest_name(id: String) -> String:
	for q in Content.quests:
		if str(q["id"]) == id:
			return str(q.get("name", id))
	return id

## the box at the bottom: who speaks, the line, the choices
func draw(c: Control, L, i: int) -> void:
	if L.ev.is_empty() or L.ev["say"].is_empty():
		return
	var vs = c.get_viewport_rect().size
	var font = ThemeDB.fallback_font
	var w = minf(320.0, vs.x - 16) if world.locals.size() == 1 else minf(232.0, vs.x / 2 - 8)
	var x = (vs.x - w) / 2.0 if world.locals.size() == 1 else (4.0 if i == 0 else vs.x - w - 4)
	var ch: Array = L.ev["choice"]
	var txt = str(L.ev["say"].get("text", ""))
	var lh = font.get_height(8)
	var nl = clampi(int(ceil(font.get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, w - 12, 8).y / maxf(1.0, lh))), 1, 3)
	var ty = 14.0 + lh * nl         # under the lines (the box grows with them: no line over its edge)
	var h = ty + 12.0 + 10.0 * ch.size()
	var y = vs.y - h - 8 - 11 * world.toasts.size()
	c.draw_rect(Rect2(x, y, w, h), Color(0.03, 0.04, 0.12, 0.92))
	c.draw_rect(Rect2(x, y, w, h), Color(0.95, 0.85, 0.5, 0.9), false, 1.0)
	var who = str(L.ev["say"].get("who", ""))
	var face = int(L.ev["say"].get("face", -1))
	if face >= 0:
		# a face: the character's first frame (facing you), in a frame left of the box
		var fs = Assets.sprite_set(face)
		if not fs.is_empty() and fs.get("slots", []).size() > 0 and not fs["slots"][0].is_empty():
			var fr: Dictionary = fs["slots"][0][0]
			var fw = float(fr["w"]); var fh = float(fr["h"])
			var box = Rect2(x - 40, y + h - 44, 38, 44)
			if box.position.x < 2:
				box.position.x = x + w + 2
			c.draw_rect(box, Color(0.03, 0.04, 0.12, 0.92))
			c.draw_rect(box, Color(0.95, 0.85, 0.5, 0.9), false, 1.0)
			var sc = minf(minf(34.0 / maxf(1.0, fw), 40.0 / maxf(1.0, fh)), 2.0)
			var dst = Rect2(box.position + (box.size - Vector2(fw, fh) * sc) / 2.0, Vector2(fw, fh) * sc)
			c.draw_texture_rect_region(fs["tex"], dst, Rect2(0, 0, fw, fh))
	if who != "":
		c.draw_string(font, Vector2(x + 6, y + 10), who, HORIZONTAL_ALIGNMENT_LEFT, w - 12, 8, Color(1, 0.85, 0.35))
	c.draw_multiline_string(font, Vector2(x + 6, y + 20), txt, HORIZONTAL_ALIGNMENT_LEFT, w - 12, 8, 3, Color(1, 1, 1))
	for j in ch.size():
		var sel = j == int(L.ev["sel"])
		c.draw_string(font, Vector2(x + 14, y + ty + 4 + j * 10), ("> " if sel else "  ") + str(ch[j][0]), HORIZONTAL_ALIGNMENT_LEFT, w - 20, 8, Color(1, 1, 0.5) if sel else Color(0.85, 0.85, 0.9))
	if ch.is_empty():
		c.draw_string(font, Vector2(x + w - 40, y + h - 4), "A: NEXT", HORIZONTAL_ALIGNMENT_LEFT, -1, 7, Color(0.7, 0.8, 1))

# ------------------------------------------------------------------ scenes, fights, words
func _key(L) -> String:
	return str(Game.planet.nodes[L.node_i]["key"])

## %s = the player's name, {var:coins} = a number
func _text(L, t: String) -> String:
	t = t.replace("%s", L.name)
	var guard = 0
	while t.find("{var:") >= 0 and guard < 20:
		guard += 1
		var a = t.find("{var:")
		var b = t.find("}", a)
		if b < 0:
			break
		var nm = t.substr(a + 5, b - a - 5)
		var v = float(L.fighter.flags.get("var:" + nm, 0))
		t = t.substr(0, a) + (str(int(v)) if is_equal_approx(v, roundf(v)) else str(v)) + t.substr(b + 1)
	return t

static func _dir_of(d) -> int:
	if d is int or d is float:
		return clampi(int(d), 0, 3)
	return maxi(0, ["down", "up", "left", "right"].find(str(d).to_lower()))

## the person of that name nearest to the player (a big map can have more than one KRILLIN)
func _person(L, name: String) -> Dictionary:
	var best = {}
	var bd = INF
	var me = Vector2(L.fighter.x, L.fighter.y)
	for p in L.area.get("people", []):
		if str(p.get("name", "")).to_upper() == name.to_upper():
			var d = me.distance_squared_to(Vector2(float(p["x"]), float(p["y"])))
			if d < bd:
				bd = d; best = p
	return best

func _remove_person(L, name: String) -> void:
	var ppl: Array = L.area.get("people", [])
	for i in range(ppl.size() - 1, -1, -1):
		if str(ppl[i].get("name", "")).to_upper() == name.to_upper() and ppl[i].get("hidden", false):
			ppl.remove_at(i)

func _face(L, who: String, d: int) -> void:
	if who.to_upper() == "PLAYER":
		L.fighter.dir = d
		L.fighter.scene_dir = d
	else:
		var p = _person(L, who)
		if not p.is_empty():
			p["cut_dir"] = d

## people (and the player) walking where a MOVE step sends them
func _step_moves(L) -> void:
	var mv: Array = L.ev.get("moves", [])
	if mv.is_empty():
		return
	var f = L.fighter
	for m in mv.duplicate():
		var who = str(m["who"])
		var at: Vector2
		var p = {}
		if who.to_upper() == "PLAYER":
			at = Vector2(f.x, f.y)
		else:
			p = _person(L, who)
			if p.is_empty():
				mv.erase(m)
				continue
			at = Vector2(float(p["x"]), float(p["y"]))
		var to = Vector2(float(m["x"]), float(m["y"]))
		var dv = to - at
		var sp = float(m["speed"]) * 1.1
		var d = 0
		if absf(dv.x) > absf(dv.y):
			d = 3 if dv.x > 0 else 2
		else:
			d = 0 if dv.y > 0 else 1
		var done = dv.length() <= sp
		var nxt = to if done else at + dv.normalized() * sp
		if who.to_upper() == "PLAYER":
			f.x = nxt.x; f.y = nxt.y
			f.dir = d
			f.scene_dir = -1 if done else d
			f.scene_pose = -1 if done else 1
			f.scene_loop = true
		else:
			p["x"] = nxt.x; p["y"] = nxt.y
			p["cut_dir"] = d
			p["cut_walk"] = not done
			var sk = "shown:%s:%s" % [_key(L), str(p.get("name", ""))]
			if done and f.flags.get(sk) is Dictionary:
				f.flags[sk]["x"] = nxt.x; f.flags[sk]["y"] = nxt.y; f.flags[sk]["cut_dir"] = d    # (a save finds them where they walked to)
		if done:
			mv.erase(m)

## a story boss fight: the boss comes, the doors close; it ends in WIN (beaten) or LOSE (you are knocked out)
func _start_fight(L, st: Dictionary) -> bool:
	var f = L.fighter
	var key = _key(L)
	var sim = Game.sims.get(key)
	if sim == null:
		return false
	var t = int(st.get("kind", 8))
	var p = Vector2(float(st.get("x", -1)), float(st.get("y", -1)))
	if p.x < 0:
		p = Vector2(f.x + 80, f.y)
	var e = sim.make_enemy(sim.enemies.size(), t, Assets.set_for_type(t), sim._open_near(p), maxi(1, int(st.get("level", f.level))), false, true)
	e["respawn_ms"] = 1 << 40
	e["minion"] = true
	if str(st.get("name", "")) != "":
		e["name"] = str(st["name"])
	if float(st.get("hp", 0)) > 0:
		e["hp"] = maxi(1, roundi(e["hp"] * float(st["hp"]))); e["maxhp"] = e["hp"]
	sim.enemies.append(e)
	sim.awake.append(e)
	var phases = []
	var ph = st.get("phases", "")
	if ph is String:
		for part in ph.split(",", false):
			var kv = part.split(":")
			if kv.size() == 2:
				phases.append([float(kv[0]), kv[1].strip_edges()])
	elif ph is Array:
		phases = ph
	L.ev["fight"] = {"key": key, "id": int(e["id"]), "win": str(st.get("win", "")), "lose": str(st.get("lose", "")), "phases": phases, "lock": bool(st.get("lock", true)), "done": []}
	world.toasts.append([(str(e["name"]) + " APPEARS!") if str(e.get("name", "")) != "" else "A BOSS APPEARS!", Color(1, 0.5, 0.4), 200])
	return true

func _fight_foe(L) -> Dictionary:
	var fi: Dictionary = L.ev["fight"]
	var sim = Game.sims.get(str(fi["key"]))
	if sim == null:
		return {}
	var id = int(fi["id"])
	if id < sim.enemies.size() and int(sim.enemies[id]["id"]) == id:
		return sim.enemies[id]
	for e in sim.enemies:
		if int(e["id"]) == id:
			return e
	return {}

## "go": the event goes on (won, lost, or a phase), "": still fighting
func _step_fight(L) -> String:
	var fi: Dictionary = L.ev["fight"]
	var e = _fight_foe(L)
	var f = L.fighter
	if e.is_empty() or not e["alive"] or e["state"] == "dying":
		L.ev.erase("fight")
		L.ev["until"] = ""
		if str(fi["win"]) != "":
			_goto(L, str(fi["win"]))
		return "go"
	if f.state == "down":
		L.ev.erase("fight")
		L.ev["until"] = ""
		f.revive(f.x, f.y)
		e["state"] = "dying"; e["t"] = 40       # (the boss leaves: the story decides what happens)
		if str(fi["lose"]) != "":
			_goto(L, str(fi["lose"]))
		return "go"
	if str(L.ev.get("until", "")) == "fight":
		var frac = float(e["hp"]) / maxf(1.0, float(e["maxhp"]))
		for ph in fi["phases"]:
			if ph.size() >= 2 and frac <= float(ph[0]) and not fi["done"].has(str(ph[1])):
				fi["done"].append(str(ph[1]))
				L.ev["until"] = ""
				_goto(L, str(ph[1]))
				return "go"
	return ""

func _hold_boss(L) -> void:
	var e = _fight_foe(L)
	if not e.is_empty():
		e["hold"] = 2

## the event is over: the scene lets go of everyone
func _cleanup(L) -> void:
	var f = L.fighter
	f.scene_pose = -1
	f.scene_dir = -1
	L.cut_cam = {}
	for p in L.area.get("people", []):
		p.erase("cut_walk")
		p.erase("cut_pose")

static func _attack_in(f, r: Array) -> bool:
	var rr = Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))
	for sh in f.shots:
		if rr.grow(4).has_point(Vector2(float(sh.get("x", -9999)), float(sh.get("y", -9999)))):
			return true
	if f.state in ["attack", "rush", "skill"]:
		var fwd = [Vector2(0, 1), Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0)][clampi(f.dir, 0, 3)]
		if rr.grow(2).has_point(Vector2(f.x, f.y - 8) + fwd * 16.0):
			return true
	return false
