class_name ActorView
extends Node2D
## Draws one frame of a sprite set (the game's own frames, from the import) at the object's point.

var set_data = {}
var anim = 0
var dir = 0
var frame = 0
var tint = Color(1, 1, 1, 1)
var flash = false
var concealed = false
var size_scale = 1.0
var label = ""
var label_color = Color(1, 1, 1)
var hp_frac = 1.0          # under 1: a small health bar over the head
var bubble = ""            # a chat message over the head
var aura = Color(0, 0, 0, 0)   # a transformation's aura (alpha 0: none)
var set_id = -1

func set_sprite_set(d: Dictionary) -> void:
	set_data = d
	queue_redraw()

func frames_of(a: int, d: int) -> Array:
	if set_data.is_empty():
		return []
	var slots: Array = set_data["slots"]
	var s = a * 4 + d
	if s < 0 or s >= slots.size():
		return []
	return slots[s]

func show_frame(a: int, d: int, f: int) -> void:
	if a != anim or d != dir or f != frame:
		anim = a; dir = d; frame = f
		queue_redraw()

func _draw() -> void:
	if set_data.is_empty() or concealed:
		return
	var fr = frames_of(anim, dir)
	var a = anim
	if fr.is_empty():
		fr = frames_of(0, dir)
		a = 0
		if fr.is_empty():
			return
	var f: Dictionary = fr[frame % fr.size()]
	if aura.a > 0.0:
		# a flickering flame around the fighter
		var tt = Engine.get_physics_frames()
		# centred on the fighter's own pixels (not the sprite's box, which has empty room on one side)
		var bb = _opaque_box(f, frame % fr.size(), a * 4 + dir)
		var hgt = bb.size.y * size_scale
		var base = Vector2(f["x"] + bb.position.x + bb.size.x * 0.5, f["y"] + bb.position.y + bb.size.y * 0.55) * size_scale
		for i in 3:
			var k = (tt / 3 + i * 5) % 8
			var w = (bb.size.x * 0.5 + 5 + k) * size_scale
			var col = Color(aura.r, aura.g, aura.b, 0.18 + 0.06 * i)
			var pts = PackedVector2Array([base + Vector2(-w * 0.55, hgt * 0.5), base + Vector2(-w * 0.62, -hgt * 0.1),
				base + Vector2(-w * 0.25, -hgt * 0.62 - k), base + Vector2(0, -hgt * 0.8 - k * 1.5), base + Vector2(w * 0.25, -hgt * 0.62 - k),
				base + Vector2(w * 0.62, -hgt * 0.1), base + Vector2(w * 0.55, hgt * 0.5)])
			draw_colored_polygon(pts, col)
	var cell: int = set_data["cell"]
	var slot = a * 4 + dir
	var src = Rect2((frame % fr.size()) * cell, slot * cell, f["w"], f["h"])
	var dst = Rect2(Vector2(f["x"], f["y"]) * size_scale, Vector2(f["w"], f["h"]) * size_scale)
	var c = tint
	if flash:
		c = Color(tint.r * 1.8, tint.g * 1.8, tint.b * 1.8, tint.a)
	draw_texture_rect_region(set_data["tex"], dst, src, c)
	if label != "":
		var font = ThemeDB.fallback_font
		draw_string_outline(font, Vector2(-70, (f["y"] - 4) * size_scale), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 8, 2, Color(0, 0, 0, 0.7))
		draw_string(font, Vector2(-70, (f["y"] - 4) * size_scale), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 8, label_color)
	var top = f["y"] * size_scale - (12 if label != "" else 2)
	if hp_frac < 0.999 and hp_frac > 0.0:
		draw_rect(Rect2(-11, top - 3, 22, 4), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(-10, top - 2, 20 * hp_frac, 2), Color(0.95, 0.25, 0.2) if hp_frac < 0.35 else Color(0.95, 0.8, 0.2))
		top -= 5
	if bubble != "":
		var font2 = ThemeDB.fallback_font
		var w = minf(160.0, font2.get_string_size(bubble, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x + 8)
		draw_rect(Rect2(-w / 2, top - 14, w, 12), Color(1, 1, 1, 0.92))
		draw_rect(Rect2(-w / 2, top - 14, w, 12), Color(0, 0, 0, 0.9), false, 1.0)
		draw_string(font2, Vector2(-w / 2 + 4, top - 5), bubble, HORIZONTAL_ALIGNMENT_LEFT, w - 6, 8, Color(0.05, 0.05, 0.1))

## the part of a frame that has pixels (cached per sprite set image)
static var _boxes = {}
static var _imgs = {}
func _opaque_box(f: Dictionary, fi: int, slot: int) -> Rect2:
	var tex: Texture2D = set_data["tex"]
	var key = "%d:%d:%d" % [tex.get_rid().get_id(), slot, fi]
	if _boxes.has(key):
		return _boxes[key]
	var cell: int = set_data["cell"]
	var ik = tex.get_rid().get_id()
	if not _imgs.has(ik):
		_imgs[ik] = tex.get_image()
	var img: Image = _imgs[ik]
	var r = Rect2(0, 0, f["w"], f["h"])
	if img != null:
		var x0 = 999; var y0 = 999; var x1 = -1; var y1 = -1
		for y in int(f["h"]):
			for x in int(f["w"]):
				if img.get_pixel(fi * cell + x, slot * cell + y).a > 0.1:
					x0 = mini(x0, x); y0 = mini(y0, y); x1 = maxi(x1, x); y1 = maxi(y1, y)
		if x1 >= 0:
			r = Rect2(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
	_boxes[key] = r
	return r
