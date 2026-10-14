extends Node
## The game's moves, transformations, items and music live in plain JSON files (content/*.json).
## The copies in a "content" folder next to LoG2Coop.exe win over the built-in ones: change a number,
## add a move, a form or an item there and start the game - no programming needed.
## (Entries with the same "id" replace the built-in one; new ids are added.)

var skills = []
var forms = []
var items = []
var item_by_id = {}
var zeni = {}
var songs = {}
var sound_map = {}       # sound name -> the game's own samples (sounds.json)
var gear = []
var quests = []
var events = []         # events.json: scenes and story steps (DEV TOOLS - EVENTS)
var shops = []          # shops.json: what each shop sells
var loot = []           # loot.json: what each kind of foe can drop
var story = {}          # story.json: a game of your own (title, hero, where it starts, intro, credits)
var states = []         # states.json: poison, slow, blind... (and forms you are put in for a while)
var rom_specials = {}   # rom_specials.json: the heroes' own attacks, as the game draws them
var social_cfg = {}     # social.json: party exp share, duel damage
var people_cfg = {}     # people.json: talk range, names, lines for the quiet ones, additions
const SLOTS = ["weights", "armor", "scouter", "boots", "belt"]
const RARITY = ["", "COMMON", "RARE", "EPIC", "LEGENDARY"]
const RARITY_COL = [Color(1, 1, 1), Color(0.92, 0.92, 0.92), Color(0.4, 0.7, 1), Color(0.8, 0.5, 1), Color(1, 0.78, 0.25)]
var enemy_cfg = {}       # groups, styles
var enemy_types = {}     # type number -> {style, ...}
var problems = []

func _ready() -> void:
	reload()

func user_dir() -> String:
	return Assets.exe_dir().path_join("content")

func reload() -> void:
	problems.clear()
	Assets.refresh_heroes()
	skills = _merged("skills", "skills")
	forms = _merged("forms", "forms")
	items = _merged("items", "items")
	gear = _merged("gear", "gear")
	quests = _merged("quests", "quests")
	events = _merged("events", "events")
	shops = _merged("shops", "shops")
	loot = _merged("loot", "loot")
	states = _merged("states", "states")
	story = {}
	for sp in Mods.content_paths("story"):
		if FileAccess.file_exists(sp):
			var t = Mods.read_json(sp)
			if t is Dictionary and t.get("story") is Dictionary and str(t["story"].get("title", "")) != "":
				story = t["story"]
	item_by_id.clear()
	for it in items:
		item_by_id[str(it["id"])] = it
	for g in gear:
		var gg: Dictionary = g
		if not gg.has("max"):
			gg["max"] = 9
		gg["color"] = RARITY_COL[clampi(int(gg.get("rarity", 1)), 1, 4)].to_html(false)
		gg["info"] = gear_text(gg)
		item_by_id[str(gg["id"])] = gg
	var zi = _read("items")
	zeni = zi.get("zeni", {"drop": 0.5, "min": 4, "max": 18, "per_level": 2})
	songs = _read("music").get("songs", {})
	sound_map = _read("sounds").get("sounds", {})
	enemy_cfg = _read("enemies")
	people_cfg = _read("people")
	social_cfg = _read("social")
	rom_specials = _read("rom_specials")
	enemy_types.clear()
	for t in _merged_key("enemies", "types", "type"):
		enemy_types[int(t["type"])] = t
	if problems.size() > 0:
		print("[content] ", problems)

## built-in file, then the user's file on top (merged by id)
func _merged(file: String, key: String) -> Array:
	var base: Array = _load("res://content/%s.json" % file).get(key, [])
	var out = base.duplicate(true)
	for path in Mods.content_paths(file):
		out = _merge_ids(out, _load(path).get(key, []))
	return out

func _merge_ids(out: Array, add: Array) -> Array:
	for e in add:
		if not e is Dictionary or not e.has("id"):
			continue
		var found = false
		for i in out.size():
			if str(out[i].get("id", "")) == str(e["id"]):
				out[i] = e
				found = true
				break
		if not found:
			out.append(e)
	return out

func _merged_key(file: String, key: String, idk: String) -> Array:
	var all: Array = _load("res://content/%s.json" % file).get(key, [])
	for path in Mods.content_paths(file):
		all = all + _load(path).get(key, [])
	var by = {}
	for e in all:
		if e is Dictionary and e.has(idk):
			by[str(e[idk])] = e
	return by.values()

## how a foe of this type fights: {"style": ..., plus that style's numbers}
## the attack a boss of this kind mixes into its moves (its own attack in the game)
func own_attack(t: int) -> String:
	return {"laser": "laser", "fireball": "fire", "bomber": "bomb", "stomper": "rings"}.get(str(enemy_types.get(t, {}).get("style", "")), "")

func enemy_style(t: int, rng: RandomNumberGenerator) -> Dictionary:
	var grp = Rules.group_of(t)
	var g: Dictionary = enemy_cfg.get("groups", {}).get(grp, {"style": "melee"})
	var style = str(g.get("style", "melee"))
	if rng.randf() < float(g.get("shooter_chance", 0.0)):
		style = "fireball"
	var over: Dictionary = enemy_types.get(t, {})
	style = str(over.get("style", style))
	var out: Dictionary = enemy_cfg.get("styles", {}).get(style, {}).duplicate()
	out.merge(over, true)
	out["style"] = style
	return out

func _read(file: String) -> Dictionary:
	var d = _load("res://content/%s.json" % file)
	for path in Mods.content_paths(file):
		var u = _load(path)
		for k in u:
			if u[k] is Dictionary and d.get(k) is Dictionary:
				var m: Dictionary = d[k].duplicate(true)
				m.merge(u[k], true)
				d[k] = m
			else:
				d[k] = u[k]
	return d

func _load(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt = FileAccess.get_file_as_string(path)
	if txt.strip_edges() == "":
		return {}
	var j = JSON.new()
	if j.parse(txt) == OK and j.data is Dictionary:
		return j.data
	problems.append("could not read %s: line %d, %s (a comma or quote missing?)" % [path, j.get_error_line(), j.get_error_message()])
	return {}

static func color(hex, fallback: Color = Color(1, 1, 1)) -> Color:
	if hex == null or str(hex) == "":
		return fallback
	return Color.html(str(hex))

func _who(e: Dictionary, ch: int) -> bool:
	var nm: String = Assets.CHARACTERS[ch]
	# a hero of your own also has its base hero's moves and forms (unless heroes.json says "inherit": false)
	var base_nm = ""
	if ch >= Assets.BASE_HEROES.size() and bool(Mods.hero_entry(nm).get("inherit", true)):
		base_nm = Assets.BASE_HEROES[Assets.hero_base(ch)]
	var w = e.get("who", [])
	if w is String:
		return w == nm or w == "ALL" or (base_nm != "" and w == base_nm)
	for x in w:
		if str(x) == nm or str(x) == "ALL" or (base_nm != "" and str(x) == base_nm):
			return true
	return false

func skills_for(ch: int) -> Array:
	var out = []
	for s in skills:
		if _who(s, ch):
			out.append(s)
	out.sort_custom(func(a, b): return int(a.get("level", 1)) < int(b.get("level", 1)))
	return out

func forms_for(ch: int) -> Array:
	var out = []
	for f in forms:
		if _who(f, ch):
			out.append(f)
	out.sort_custom(func(a, b): return int(a.get("level", 1)) < int(b.get("level", 1)))
	return out

func item(id: String) -> Dictionary:
	return item_by_id.get(id, {})

func is_gear(id: String) -> bool:
	return item_by_id.get(id, {}).has("slot")

## "+5 STR +2 END +10% SPEED - LEVEL 6 - RARE"
func gear_text(g: Dictionary) -> String:
	var parts = []
	for k in ["str", "pwr", "end"]:
		if float(g.get(k, 0)) != 0:
			parts.append("+%d %s" % [int(g[k]), {"str": "STR", "pwr": "POW", "end": "END"}[k]])
	for k in ["speed", "exp"]:
		if float(g.get(k, 0)) != 0:
			parts.append("+%d%% %s" % [roundi(float(g[k]) * 100), k.to_upper()])
	return "%s - %s - LEVEL %d - %s" % [str(g.get("slot", "")).to_upper(), " ".join(PackedStringArray(parts)), int(g.get("level", 1)), RARITY[clampi(int(g.get("rarity", 1)), 1, 4)]]

func state(id: String) -> Dictionary:
	for st in states:
		if str(st.get("id", "")) == id:
			return st
	return {}

func form_by_id(id: String) -> Dictionary:
	for f in forms:
		if str(f.get("id", "")) == id:
			return f
	return {}
