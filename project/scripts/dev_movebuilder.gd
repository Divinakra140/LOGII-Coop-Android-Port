extends AcceptDialog
## DEV TOOLS - MOVES - BUILD A MOVE: a special move from its kind (beam, ball, volley, dash...), its numbers and
## colour, with a moving preview of how far, how fast and how big it is. OK puts it in the list (then SAVE).

signal built(move: Dictionary)

const KINDS = {
	"beam": "A beam held out from the hands (hold the button).", "bomb": "A ball that flies and bursts.",
	"volley": "Many small blasts at once.", "wave": "A wave that grows from you.", "dash": "Fly forward hitting everything.",
	"slash": "A cutting disc.", "stretch": "A long reaching strike.", "flash": "A blinding flash around you.",
	"heal": "Heals you (and friends near).", "buff": "Stronger for a while."}
var mv = {"id": "my_move", "name": "MY MOVE", "who": ["GOKU"], "level": 1, "ep": 5, "cooldown": 60, "type": "bomb", "power": 2.5,
	"stat": "pwr", "speed": 5.0, "range": 220, "width": 10, "color": "ffd27f", "sfx": "beam", "info": "My own move."}
var pv: Control
var t = 0.0
var desc: Label

func _ready() -> void:
	title = "BUILD A MOVE"
	size = Vector2i(560, 440)
	var h = HBoxContainer.new(); add_child(h)
	var v = VBoxContainer.new(); v.custom_minimum_size = Vector2(300, 0); h.add_child(v)
	_line(v, "id", "id"); _line(v, "name", "name")
	var who = OptionButton.new()
	for i in Assets.CHARACTERS.size():
		who.add_item(Assets.CHARACTERS[i])
	who.select(maxi(0, Assets.CHARACTERS.find("GOKU")))
	who.item_selected.connect(func(i): mv["who"] = [Assets.CHARACTERS[i]])
	v.add_child(who)
	var kp = OptionButton.new()
	for k in KINDS:
		kp.add_item(k.to_upper())
	kp.select(KINDS.keys().find(mv["type"]))
	kp.item_selected.connect(func(i): mv["type"] = KINDS.keys()[i]; desc.text = KINDS[mv["type"]])
	v.add_child(kp)
	desc = Label.new(); desc.text = KINDS[mv["type"]]; desc.autowrap_mode = TextServer.AUTOWRAP_WORD; desc.add_theme_font_size_override("font_size", 10); v.add_child(desc)
	_num(v, "from level", "level", 1, 99, 1)
	_num(v, "ki cost", "ep", 0, 40, 1)
	_num(v, "wait between (1/60 s)", "cooldown", 0, 600, 5)
	_num(v, "power", "power", 0.1, 20, 0.1)
	_num(v, "speed", "speed", 0.5, 20, 0.5)
	_num(v, "range", "range", 20, 600, 10)
	_num(v, "size", "width", 2, 40, 1)
	var cp = ColorPickerButton.new(); cp.color = Color.html(mv["color"]); cp.custom_minimum_size = Vector2(120, 24); cp.edit_alpha = false
	cp.color_changed.connect(func(c): mv["color"] = c.to_html(false))
	v.add_child(cp)
	pv = Control.new(); pv.custom_minimum_size = Vector2(240, 160); pv.draw.connect(_draw_preview); h.add_child(pv)
	confirmed.connect(func(): built.emit(mv.duplicate(true)))

func _line(p: Control, label: String, k: String) -> void:
	var r = HBoxContainer.new(); p.add_child(r)
	var l = Label.new(); l.text = label; l.custom_minimum_size = Vector2(120, 0); l.add_theme_font_size_override("font_size", 10); r.add_child(l)
	var e = LineEdit.new(); e.text = str(mv[k]); e.custom_minimum_size = Vector2(160, 0); r.add_child(e)
	e.text_changed.connect(func(tx): mv[k] = tx.to_upper() if k == "name" else tx.strip_edges().to_lower().replace(" ", "_"))

func _num(p: Control, label: String, k: String, lo: float, hi: float, step: float) -> void:
	var r = HBoxContainer.new(); p.add_child(r)
	var l = Label.new(); l.text = label; l.custom_minimum_size = Vector2(150, 0); l.add_theme_font_size_override("font_size", 10); r.add_child(l)
	var s = SpinBox.new(); s.min_value = lo; s.max_value = hi; s.step = step; s.value = float(mv[k]); r.add_child(s)
	s.value_changed.connect(func(x): mv[k] = int(x) if step >= 1 else x)

func _process(dt: float) -> void:
	t += dt
	if pv:
		pv.queue_redraw()

## the hero at the left; the move going right, as far and as fast as its numbers say (1 pixel here = 2 in the game)
func _draw_preview() -> void:
	var sz = pv.size
	pv.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.15, 0.25, 0.15))
	var hero = Vector2(24, sz.y / 2)
	pv.draw_rect(Rect2(hero - Vector2(5, 10), Vector2(10, 18)), Color(1, 0.6, 0.2))
	var col = Color.html(str(mv["color"]))
	var rng = float(mv["range"]) / 2.0
	var spd = float(mv["speed"]) * 30.0
	var w = float(mv["width"])
	var period = maxf(0.6, rng / spd + 0.5)
	var k = fmod(t, period)
	var d = minf(rng, k * spd)
	pv.draw_line(hero + Vector2(rng, -30), hero + Vector2(rng, 30), Color(1, 1, 1, 0.25), 1.0)
	match str(mv["type"]):
		"beam", "stretch":
			pv.draw_line(hero + Vector2(6, 0), hero + Vector2(6 + d, 0), col, w * 0.6)
			pv.draw_circle(hero + Vector2(6 + d, 0), w * 0.5, col.lightened(0.4))
		"bomb", "slash":
			pv.draw_circle(hero + Vector2(6 + d, 0), w * 0.5, col)
			if d >= rng:
				pv.draw_circle(hero + Vector2(6 + d, 0), w * 1.5, Color(col, 0.5))
		"volley":
			for i in 5:
				pv.draw_circle(hero + Vector2(6 + d * (0.7 + 0.08 * i), (i - 2) * w * 0.8), w * 0.3, col)
		"wave":
			pv.draw_arc(hero, maxf(2.0, d), -0.6, 0.6, 16, col, w * 0.4)
		"dash":
			pv.draw_rect(Rect2(hero + Vector2(d - 5, -10), Vector2(10, 18)), col)
		"flash":
			pv.draw_circle(hero, maxf(2.0, d), Color(col, 0.4))
		"heal":
			for i in 6:
				pv.draw_circle(hero + Vector2(cos(t * 3 + i), sin(t * 3 + i)) * 16, 2, Color(0.5, 1, 0.5))
		"buff":
			pv.draw_arc(hero, 14 + sin(t * 6) * 2, 0, TAU, 24, col, 2)
	pv.draw_string(ThemeDB.fallback_font, Vector2(4, sz.y - 6), "range %d   speed %.1f   power %.1f" % [int(mv["range"]), float(mv["speed"]), float(mv["power"])], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.8))
