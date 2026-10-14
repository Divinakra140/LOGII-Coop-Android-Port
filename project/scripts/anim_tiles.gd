class_name AnimTiles
extends Node2D
## The animated map tiles of one layer (water, waterfalls): the game's own frames and timings.

var cells = []      # [tx, ty, entry]
var descs = []      # {slot, tiles, row, durations}
var tex: Texture2D
var t = 0
var frames = []     # current frame per descriptor
var lut = {}        # slot -> [desc index, tile]

func setup(a: Dictionary, layer: int) -> void:
	tex = a["anim_tex"]
	descs = a["anim"]
	for c in a["meta"].get("anim", []):
		if int(c[0]) == layer:
			cells.append([int(c[1]), int(c[2]), int(c[3])])
	for i in descs.size():
		var d: Dictionary = descs[i]
		for k in int(d["tiles"]):
			lut[int(d["slot"]) + k] = [i, k]
	frames.resize(descs.size())
	frames.fill(0)

func tick() -> void:
	if cells.is_empty() or tex == null:
		return
	t += 1
	var changed = false
	for i in descs.size():
		var dur: Array = descs[i]["durations"]
		var total = 0
		for v in dur:
			total += maxi(1, int(v))
		var m = t % maxi(1, total)
		var f = 0
		var acc = 0
		for k in dur.size():
			acc += maxi(1, int(dur[k]))
			if m < acc:
				f = k
				break
		if frames[i] != f:
			frames[i] = f
			changed = true
	if changed:
		queue_redraw()

func _draw() -> void:
	if tex == null:
		return
	for c in cells:
		var e: int = c[2]
		var slot = e & 0x3FF
		if not lut.has(slot):
			continue
		var di: int = lut[slot][0]
		var tile: int = lut[slot][1]
		var row: int = int(descs[di]["row"]) + int(frames[di])
		var hf = (e & 0x400) != 0
		var vf = (e & 0x800) != 0
		if hf or vf:
			draw_set_transform(Vector2(c[0] * 8 + (8 if hf else 0), c[1] * 8 + (8 if vf else 0)), 0.0, Vector2(-1 if hf else 1, -1 if vf else 1))
			draw_texture_rect_region(tex, Rect2(0, 0, 8, 8), Rect2(tile * 8, row * 8, 8, 8))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			draw_texture_rect_region(tex, Rect2(c[0] * 8, c[1] * 8, 8, 8), Rect2(tile * 8, row * 8, 8, 8))
