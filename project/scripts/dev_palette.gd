extends Control
## DEV TOOLS: every tile of the game, 14 to a row - click one to paint with it. Wheel: scroll.

signal picked(tile: int)

const COLS = 14
const CELL = 16
var chosen = 1
var top_row = 0
var tex: Texture2D
var game = ""          # "" this game's tiles; "bf" Buu's Fury's (the DEV TOOLS library)
var count = 0

func _ready() -> void:
	var simg = Assets.sheet_image(game)
	tex = ImageTexture.create_from_image(simg) if simg != null else null
	if game == "":
		count = Assets.kit_tiles
	else:
		var lj = Assets.json(Assets.base_dir.path_join("lib/%s/maps.json" % game))
		count = int(lj.get("tiles", 0)) if lj != null else 0
	jump_to(chosen & 0xFFFF)

## a tile number of this palette -> the cell value painted
func cell_of(t: int) -> int:
	if game == "" or t <= 0:
		return t
	return t | (1 << 20) | (int(Assets.LIB_GAMES[game]) << 21)

func _is_mine(c: int) -> bool:
	return (game == "" and not (c & (1 << 20))) or (game != "" and (c & (1 << 20)) and ((c >> 21) & 7) == int(Assets.LIB_GAMES[game]))
	mouse_filter = Control.MOUSE_FILTER_STOP

func jump_to(t: int) -> void:
	top_row = maxi(0, t / COLS - 4)
	queue_redraw()

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP:
			top_row = maxi(0, top_row - 3)
		elif ev.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			top_row = mini(top_row + 3, count / COLS)
		elif ev.button_index == MOUSE_BUTTON_LEFT:
			var c = int(ev.position.x) / CELL
			var r = int(ev.position.y) / CELL
			if c < COLS:
				var t = (top_row + r) * COLS + c
				if t > 0 and t < count:
					chosen = cell_of(t)
					picked.emit(chosen)
		queue_redraw()
		accept_event()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.1, 0.1, 0.15))
	if tex == null:
		return
	var rows = int(size.y) / CELL
	for r in rows:
		for c in COLS:
			var t = (top_row + r) * COLS + c
			if t <= 0 or t >= count:
				continue
			var src = Rect2((t % 64) * 8, (t / 64) * 8, 8, 8)
			draw_texture_rect_region(tex, Rect2(c * CELL, r * CELL, CELL, CELL), src)
			if t == (chosen & 0xFFFF) and _is_mine(chosen):
				draw_rect(Rect2(c * CELL, r * CELL, CELL, CELL), Color(1, 1, 0.3), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(2, size.y - 2), "tiles %d - %d" % [top_row * COLS, (top_row + rows) * COLS], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.7))
