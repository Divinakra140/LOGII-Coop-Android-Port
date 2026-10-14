extends Node
## Sound effects, best first: a file sounds/<name>.ogg / .mp3 next to LoG2Coop.exe; the GAME'S OWN SAMPLES,
## read from your game at import (imported/sounds/sfx_NN.wav - content/sounds.json says which plays for what,
## a list = a random one of them each time); otherwise a little sound made here from waves and noise.
## names: punch kick ki beam_charge beam dash slash bomb boom wave flash heal hit crit hurt die
##        pickup item zeni levelup transform menu move error

const RATE = 22050
var streams = {}
var players = []
var volume = 0.8

const LONG = {"beam": true, "beam_charge": true, "transform": true, "wave": true, "menu": true, "heal": true, "flash": true, "die": true, "stomp": true, "boom": false}
var _last = {}               # sound name -> the frame it last started
## the game's long noisy bursts, cut short (seconds) with a quick fade - fired again and again they became a wall of noise
const CUT = {"ki": 0.32, "fireball": 0.4, "laser": 0.35, "hit": 0.3, "hurt": 0.3, "crit": 0.4, "throw": 0.3, "dash": 0.35}
const ROM_GAIN = 0.5          # the game's samples are mixed loud (8-bit, full scale)
var _from_rom = {}

func _ready() -> void:
	# many sounds at once on top of the music: a limiter on the master bus keeps it from crackling
	if AudioServer.get_bus_effect_count(0) == 0:
		var lim = ClassDB.instantiate("AudioEffectHardLimiter") if ClassDB.class_exists("AudioEffectHardLimiter") else AudioEffectLimiter.new()
		AudioServer.add_bus_effect(0, lim)
	# the game's samples are 8-bit: a gentle low-pass takes the hiss off without dulling them
	if AudioServer.get_bus_index("SFX") < 0:
		AudioServer.add_bus()
		var bi = AudioServer.bus_count - 1
		AudioServer.set_bus_name(bi, "SFX")
		AudioServer.set_bus_send(bi, "Master")
		var lp = AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 7000.0
		AudioServer.add_bus_effect(bi, lp)
	for i in 14:
		var p = AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		players.append(p)
	_make_all()

func play(name: String, vol: float = 1.0, pitch: float = 1.0) -> void:
	if not streams.has(name) or volume <= 0.01:
		return
	var st = streams[name]
	if _from_rom.has(name):
		vol *= ROM_GAIN
	if st is Array:
		if st.is_empty():
			return
		st = st[randi() % st.size()]
	# the same sound again and again (a punch chain, a hail of ki blasts) must not pile up into noise:
	# at most a few of one kind at a time, not twice in the same few frames - the oldest one is cut instead
	var now = Engine.get_physics_frames()
	if now - int(_last.get(name, -100)) < 4:
		return
	_last[name] = now
	var same = []
	for p in players:
		if p.playing and p.get_meta("nm", "") == name:
			same.append(p)
	var cap = 1 if LONG.get(name, false) else 2
	if same.size() >= cap:
		var old: AudioStreamPlayer = same[0]
		for q in same:
			if q.get_playback_position() > old.get_playback_position():
				old = q
		old.stop()
	for p in players:
		if not p.playing:
			p.stream = st
			p.volume_db = linear_to_db(clampf(vol * volume, 0.001, 2.0))
			p.pitch_scale = pitch * randf_range(0.97, 1.03)
			p.set_meta("nm", name)
			p.set_meta("vol", p.volume_db)
			p.set_meta("stop_at", now + int(CUT.get(name, 0) * 60.0) if CUT.has(name) else -1)
			p.play()
			return

func _make_all() -> void:
	var defs = {
		"punch": [0.07, "noise", 900.0, 200.0, 0.9],
		"kick": [0.10, "noise", 600.0, 120.0, 1.0],
		"ki": [0.18, "square", 900.0, 300.0, 0.5],
		"beam_charge": [0.5, "square", 200.0, 900.0, 0.35],
		"beam": [0.7, "saw", 140.0, 90.0, 0.55],
		"dash": [0.22, "noise", 300.0, 1400.0, 0.6],
		"slash": [0.16, "noise", 2200.0, 500.0, 0.7],
		"bomb": [0.3, "square", 300.0, 120.0, 0.5],
		"boom": [0.6, "noise", 400.0, 40.0, 1.0],
		"wave": [0.45, "noise", 150.0, 60.0, 0.9],
		"flash": [0.35, "sine", 1800.0, 2400.0, 0.4],
		"heal": [0.45, "sine", 500.0, 1100.0, 0.45],
		"hit": [0.08, "noise", 1200.0, 300.0, 0.8],
		"crit": [0.16, "square", 1200.0, 200.0, 0.7],
		"hurt": [0.16, "square", 300.0, 90.0, 0.7],
		"die": [0.35, "square", 500.0, 60.0, 0.55],
		"pickup": [0.12, "square", 900.0, 1600.0, 0.4],
		"item": [0.25, "sine", 700.0, 1400.0, 0.5],
		"zeni": [0.1, "square", 1800.0, 2400.0, 0.3],
		"transform": [0.9, "saw", 80.0, 600.0, 0.6],
		"menu": [0.05, "square", 1200.0, 1200.0, 0.25],
		"move": [0.04, "square", 800.0, 800.0, 0.2],
		"error": [0.15, "square", 160.0, 140.0, 0.35],
		"laser": [0.3, "square", 1600.0, 900.0, 0.35],
		"fireball": [0.25, "noise", 700.0, 300.0, 0.6],
		"throw": [0.12, "noise", 500.0, 900.0, 0.5],
		"stomp": [0.5, "noise", 120.0, 40.0, 1.0],
	}
	streams.clear()
	_from_rom.clear()
	for n in defs:
		var f = _file(n)
		var rom = _rom(n)
		if f != null:
			streams[n] = f
		elif not rom.is_empty():
			streams[n] = rom
			_from_rom[n] = true
		else:
			var d = defs[n]
			streams[n] = _synth(d[0], d[1], d[2], d[3], d[4])
	# level up: a little rising arpeggio
	if _file("levelup") != null:
		streams["levelup"] = _file("levelup")
	elif not _rom("levelup").is_empty():
		streams["levelup"] = _rom("levelup")
		_from_rom["levelup"] = true
	else:
		streams["levelup"] = _arp([523.0, 659.0, 784.0, 1047.0], 0.09)

func play_stream(st: AudioStream, vol: float = 1.0) -> void:
	for p in players:
		if not p.playing:
			p.stream = st
			p.volume_db = linear_to_db(clampf(vol * ROM_GAIN * maxf(volume, 0.05), 0.001, 2.0))
			p.pitch_scale = 1.0
			p.play()
			return

## after the game is (re)imported
func reload() -> void:
	_samples.clear()
	_own = null
	_make_all()

var _samples = {}
## the game's own samples for a sound (content/sounds.json), as streams
func _rom(n: String) -> Array:
	var out = []
	var ids = Content.sound_map.get(n, [])
	if not ids is Array:
		ids = [ids]
	for id in ids:
		var st = sample(int(id))
		if st != null:
			out.append(st)
	return out

## imported/sounds/sfx_NN.wav (8-bit, as the game has them) -> a stream
func sample(id: int) -> AudioStreamWAV:
	if _samples.has(id):
		return _samples[id]
	var w: AudioStreamWAV = null
	if Assets.base_dir != "":
		var d = FileAccess.get_file_as_bytes(Assets.base_dir.path_join("sounds/sfx_%02d.wav" % id))
		if d.size() > 44 and d.slice(0, 4).get_string_from_ascii() == "RIFF":
			var rate = d.decode_u32(24)
			var o = 12
			while o + 8 <= d.size():
				var tag = d.slice(o, o + 4).get_string_from_ascii()
				var sz = d.decode_u32(o + 4)
				if tag == "data":
					var pcm = d.slice(o + 8, mini(d.size(), o + 8 + sz))
					for i in pcm.size():
						pcm[i] = pcm[i] ^ 0x80      # wav 8-bit is unsigned, Godot's is signed
					w = AudioStreamWAV.new()
					w.format = AudioStreamWAV.FORMAT_8_BITS
					w.mix_rate = rate
					w.data = _padded(pcm)
					break
				o += 8 + sz + (sz & 1)
	_samples[id] = w
	return w

var _own = null     # the files in your sounds folder, read once (on Android each look there is slow)
func _file(n: String):
	if _own == null:
		_own = {}
		for f in DirAccess.get_files_at(Assets.sounds_dir()):
			_own[f.to_lower()] = true
	var p = Assets.sounds_dir().path_join("%s.ogg" % n)
	if _own.has(p.get_file().to_lower()):
		return AudioStreamOggVorbis.load_from_file(p)
	p = Assets.sounds_dir().path_join("%s.mp3" % n)
	if _own.has(p.get_file().to_lower()):
		var m = AudioStreamMP3.new()
		m.data = FileAccess.get_file_as_bytes(p)
		return m
	return null

func _synth(dur: float, wave: String, f0: float, f1: float, amp: float) -> AudioStreamWAV:
	var n = int(dur * RATE)
	var data = PackedByteArray()
	data.resize(n * 2)
	var ph = 0.0
	var noise = 0.0
	var hold = 0
	for i in n:
		var t = float(i) / n
		var f = lerpf(f0, f1, t)
		ph += f / RATE
		var v = 0.0
		match wave:
			"square": v = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			"saw": v = fmod(ph, 1.0) * 2.0 - 1.0
			"sine": v = sin(ph * TAU)
			_:
				# noise, "pitched" by how often it changes
				hold -= 1
				if hold <= 0:
					noise = randf_range(-1, 1)
					hold = maxi(1, int(RATE / maxf(40.0, f)))
				v = noise
		var env = minf(1.0, t * 40.0) * pow(1.0 - t, 1.6)
		var s = clampi(int(v * env * amp * 26000.0), -32767, 32767)
		data.encode_s16(i * 2, s)
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = _padded(data)
	return w

func _arp(notes: Array, step: float) -> AudioStreamWAV:
	var per = int(step * RATE)
	var n = per * notes.size() + per * 2
	var data = PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var k = mini(i / per, notes.size() - 1)
		var t_in = float(i - k * per) / per
		var f: float = notes[k]
		var v = 1.0 if fmod(float(i) * f / RATE, 1.0) < 0.5 else -1.0
		var env = 1.0 if i < per * notes.size() else 1.0 - float(i - per * notes.size()) / (per * 2)
		env *= minf(1.0, t_in * 30.0)
		data.encode_s16(i * 2, clampi(int(v * env * 0.3 * 26000.0), -32767, 32767))
	var w = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = _padded(data)
	return w

func _physics_process(_dt: float) -> void:
	var now = Engine.get_physics_frames()
	for p in players:
		if not p.playing:
			continue
		var st = int(p.get_meta("stop_at", -1))
		if st < 0 or now < st:
			continue
		# a short fade, not a click
		var k = now - st
		if k >= 4:
			p.stop()
		else:
			p.volume_db = float(p.get_meta("vol", 0.0)) - 9.0 * (k + 1)


## silence after the end: Godot 4.7's mixer on Android reads a little past a sound's last sample (a crash there)
static func _padded(d: PackedByteArray) -> PackedByteArray:
	var p = d.duplicate()
	p.resize(d.size() + 1024)
	return p
