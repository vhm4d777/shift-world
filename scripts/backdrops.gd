class_name Backdrops
extends RefCounted
## Procedural parallax backgrounds for worlds 2-11 (world 1 uses the original
## painted PNGs). Each theme has a Light and a Dark version: a static far layer
## and a horizontally tiling mid layer that scrolls.

const W := 480
const H := 272

# Per theme: [light, dark] settings.
#   sky: top/bottom colours, glow: [x, y, radius, colour], far/mid: silhouette layer colours
#   kind: silhouette style, tint: multiplies the level tiles, fog: haze colour
const THEMES := {
	1: {"kind": "crystal",
		"sky": [["0e4a5c", "7fd6d0"], ["120626", "3a1050"]], "glow": [[380, 60, 70, "c8fff4"], [120, 70, 60, "c070ff"]],
		"far": [["4a9aa8", "2c6c80"], ["2a1040", "1a0830"]], "mid": [["2a6070", "123c4a"], ["1a0628", "0a0214"]],
		"accent": ["e0ffff", "d070ff"], "tint": ["eafcff", "f0e0ff"], "fog": ["c8f4ff", "6a2a90"]},
	2: {"kind": "city",
		"sky": [["ff9a7a", "ffd6a0"], ["0a0420", "3a0a4a"]], "glow": [[240, 210, 90, "ffe0a0"], [360, 60, 40, "ff7ad0"]],
		"far": [["c87a8a", "a05a70"], ["1e0a38", "160628"]], "mid": [["6a3a5a", "4a2040"], ["0c0418", "06020c"]],
		"accent": ["fff0b0", "2ef0ff"], "tint": ["fff0ec", "f0e4ff"], "fog": ["ffc0a0", "8a2a9a"]},
	3: {"kind": "forest",
		"sky": [["9ad8a0", "e8f8c8"], ["06140e", "1a2a20"]], "glow": [[100, 50, 60, "ffffe0"], [380, 50, 34, "ff6a5a"]],
		"far": [["5aa070", "3c805a"], ["0e2a1e", "0a1e16"]], "mid": [["2a5a3a", "16402a"], ["04100a", "020804"]],
		"accent": ["f0ffd0", "ffd04a"], "tint": ["f0fff0", "e8f4ec"], "fog": ["d8ffd8", "2a5a40"]},
	4: {"kind": "ruins",
		"sky": [["4ac8e0", "c8f4ff"], ["020c24", "0a2a4a"]], "glow": [[300, 30, 80, "ffffff"], [140, 40, 40, "60d0ff"]],
		"far": [["6ab0c8", "4a90b0"], ["0a2440", "06182e"]], "mid": [["3a7a98", "205a78"], ["041428", "020a18"]],
		"accent": ["ffffff", "60f0ff"], "tint": ["e8f8ff", "e0ecff"], "fog": ["a0f0ff", "104a7a"]},
	5: {"kind": "volcano",
		"sky": [["f0b070", "ffe0b0"], ["1a0404", "5a0a0a"]], "glow": [[240, 250, 120, "ffb040"], [240, 260, 140, "ff3a10"]],
		"far": [["b06a40", "8a4a2a"], ["3a0808", "200404"]], "mid": [["6a3420", "4a2010"], ["140202", "080000"]],
		"accent": ["fff0a0", "ff6a20"], "tint": ["fff0e0", "ffe4e0"], "fog": ["ffd0a0", "a01a0a"]},
	6: {"kind": "peaks",
		"sky": [["8ac8ff", "e8f6ff"], ["020818", "0a2040"]], "glow": [[90, 50, 50, "ffffff"], [360, 40, 30, "e0f0ff"]],
		"far": [["b8d8f8", "90b8e0"], ["14284a", "0c1a34"]], "mid": [["6a90c0", "4a70a0"], ["081428", "040a18"]],
		"accent": ["ffffff", "50ffb0"], "tint": ["f4faff", "e8f0ff"], "fog": ["ffffff", "205a70"]},
	7: {"kind": "storm",
		"sky": [["7a8aa8", "c8d0e0"], ["0c0418", "301050"]], "glow": [[240, 40, 70, "e8f0ff"], [240, 40, 60, "b070ff"]],
		"far": [["8a94b0", "6a7490"], ["241040", "180830"]], "mid": [["4a5470", "343c58"], ["100620", "080310"]],
		"accent": ["ffffff", "c8a0ff"], "tint": ["f0f2ff", "f0e8ff"], "fog": ["e0e8ff", "4a2080"]},
	8: {"kind": "space",
		"sky": [["6a4a9a", "d8b0e8"], ["000004", "0a0420"]], "glow": [[340, 90, 60, "ffd0f0"], [120, 80, 50, "6a8aff"]],
		"far": [["9a7ac8", "7a5aa8"], ["1a1040", "0e0828"]], "mid": [["4a3a7a", "302458"], ["0a0618", "04020c"]],
		"accent": ["ffffff", "a0c0ff"], "tint": ["f8f0ff", "eae8ff"], "fog": ["f0d0ff", "2a2a7a"]},
	9: {"kind": "gears",
		"sky": [["c8a060", "f0dca0"], ["100804", "3a2010"]], "glow": [[240, 120, 90, "fff0c0"], [240, 140, 80, "ff8a30"]],
		"far": [["a07a40", "80602a"], ["301a0a", "201006"]], "mid": [["5a4020", "402a10"], ["120802", "080400"]],
		"accent": ["fff0c0", "ffb040"], "tint": ["fff8ec", "fff0e4"], "fog": ["ffe8c0", "6a3a10"]},
	10: {"kind": "void",
		"sky": [["9a86c8", "e8c8b0"], ["000000", "14000a"]], "glow": [[240, 136, 130, "ffffff"], [240, 136, 120, "ff2e55"]],
		"far": [["8a78b0", "6a5890"], ["1a0010", "0e0008"]], "mid": [["5a4878", "3a2a58"], ["080004", "000000"]],
		"accent": ["ffd84a", "ff2e55"], "tint": ["fffaf0", "ffe8ee"], "fog": ["fff4e0", "5a0020"]},
}


static func tint(theme: int, world: int) -> Color:
	if not THEMES.has(theme):
		return Color.WHITE
	return Color(THEMES[theme]["tint"][world])


static func fog(theme: int, world: int) -> Color:
	if not THEMES.has(theme):
		return Color(1, 1, 1, 0) if world == 0 else Color(1.0, 0.18, 0.33, 0)
	return Color(THEMES[theme]["fog"][world])


## Returns [far texture, mid texture] for a theme and world.
static func bake(theme: int, world: int) -> Array:
	var cfg: Dictionary = THEMES[theme]
	var rng := RandomNumberGenerator.new()
	rng.seed = theme * 97 + world * 13
	var far := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var mid := Image.create(W, H, false, Image.FORMAT_RGBA8)
	mid.fill(Color(0, 0, 0, 0))
	var sky: Array = cfg["sky"][world]
	_gradient(far, Color(sky[0]), Color(sky[1]))
	var glow: Array = cfg["glow"][world]
	_glow(far, glow[0], glow[1], glow[2], Color(glow[3]))
	if world == 1 or cfg["kind"] == "space":
		_stars(far, rng, 140 if cfg["kind"] == "space" else 70)
	var fc: Array = cfg["far"][world]
	var mc: Array = cfg["mid"][world]
	var acc := Color(cfg["accent"][world])
	match cfg["kind"]:
		"crystal": _crystal(far, mid, rng, fc, mc, acc)
		"city": _city(far, mid, rng, fc, mc, acc, world)
		"forest": _forest(far, mid, rng, fc, mc, acc, world)
		"ruins": _ruins(far, mid, rng, fc, mc, acc)
		"volcano": _volcano(far, mid, rng, fc, mc, acc, world)
		"peaks": _peaks(far, mid, rng, fc, mc, acc, world)
		"storm": _storm(far, mid, rng, fc, mc, acc, world)
		"space": _space(far, mid, rng, fc, mc, acc)
		"gears": _gears(far, mid, rng, fc, mc, acc)
		"void": _void(far, mid, rng, fc, mc, acc, world)
	_haze(far, Color(cfg["fog"][world]))
	return [ImageTexture.create_from_image(far), ImageTexture.create_from_image(mid)]


# ------------------------------------------------------------------ helpers

static func _gradient(img: Image, top: Color, bottom: Color) -> void:
	for y in H:
		var t := float(y) / (H - 1)
		img.fill_rect(Rect2i(0, y, W, 1), top.lerp(bottom, t * t * (3.0 - 2.0 * t)))


static func _blend(img: Image, x: int, y: int, c: Color, a: float) -> void:
	if x < 0 or x >= W or y < 0 or y >= H or a <= 0.0:
		return
	var o := img.get_pixel(x, y)
	img.set_pixel(x, y, Color(lerpf(o.r, c.r, a), lerpf(o.g, c.g, a), lerpf(o.b, c.b, a), maxf(o.a, a)))


static func _glow(img: Image, cx: int, cy: int, r: int, c: Color) -> void:
	for y in range(cy - r * 2, cy + r * 2):
		for x in range(cx - r * 2, cx + r * 2):
			var d := Vector2(x - cx, y - cy).length() / r
			if d < 2.0:
				var a := clampf(1.0 - d / 2.0, 0.0, 1.0)
				a = a * a * 0.55
				if d < 0.35:
					a = 0.95
				_blend(img, x, y, c, a)


static func _stars(img: Image, rng: RandomNumberGenerator, n: int) -> void:
	for i in n:
		var x := rng.randi_range(0, W - 1)
		var y := rng.randi_range(0, int(H * 0.7))
		var b := rng.randf_range(0.4, 1.0)
		_blend(img, x, y, Color(1, 1, 1), b)
		if rng.randf() < 0.12:
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				_blend(img, x + o.x, y + o.y, Color(1, 1, 1), b * 0.4)


static func _haze(img: Image, c: Color) -> void:
	# atmospheric haze near the horizon for depth
	for y in range(int(H * 0.55), H):
		var t := float(y - H * 0.55) / (H * 0.45)
		var a := t * 0.18
		for x in W:
			_blend(img, x, y, c, a)


## Fills a silhouette under heights[] with a vertical gradient and a lit rim.
static func _silhouette(img: Image, heights: PackedFloat32Array, top: Color, bottom: Color, rim: Color, rim_a: float = 0.6) -> void:
	for x in W:
		var h0 := int(heights[x])
		if h0 >= H:
			continue
		h0 = maxi(h0, 0)
		for y in range(h0, H):
			var t := float(y - h0) / maxf(1.0, H - h0)
			img.set_pixel(x, y, top.lerp(bottom, minf(1.0, t * 1.6)))
		_blend(img, x, h0, rim, rim_a)


static func _periodic(rng: RandomNumberGenerator, base: float, amps: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(W)
	var phases := []
	for a in amps:
		phases.append(rng.randf() * TAU)
	for x in W:
		var v := base
		for i in amps.size():
			v -= amps[i] * sin(TAU * (i + 1) * 2.0 * x / W + phases[i])
		out[x] = v
	return out


static func _jagged(rng: RandomNumberGenerator, base: float, amp: float, peaks: int) -> PackedFloat32Array:
	# periodic triangle mountains
	var out := PackedFloat32Array()
	out.resize(W)
	var pts := []
	for i in peaks:
		pts.append([W * (i + rng.randf_range(0.2, 0.8)) / peaks, base - amp * rng.randf_range(0.4, 1.0)])
	for x in W:
		var best := float(H)
		for p in pts:
			for wrap in [-W, 0, W]:
				var dx := absf(x - (p[0] + wrap))
				best = minf(best, p[1] + dx * 0.9)
		out[x] = minf(best, base + 20)
	return out


# ------------------------------------------------------------------ themes

static func _crystal(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color) -> void:
	_silhouette(far, _jagged(rng, 210, 90, 9), Color(fc[0]), Color(fc[1]), acc, 0.5)
	# stalactites from the ceiling (far)
	for i in 26:
		var x := rng.randi_range(0, W - 1)
		var len := rng.randi_range(20, 70)
		var wdt := rng.randi_range(4, 10)
		for y in len:
			var half := int(wdt * (1.0 - float(y) / len) / 2.0)
			for dx in range(-half, half + 1):
				_blend(far, (x + dx + W) % W, y, Color(fc[1]), 0.9)
	var h := _jagged(rng, 250, 80, 6)
	_silhouette(mid, h, Color(mc[0]), Color(mc[1]), acc, 0.8)
	# glowing crystal clusters on the mid layer
	for i in 14:
		var x := rng.randi_range(0, W - 1)
		var base := int(h[x]) + 2
		var ch := rng.randi_range(8, 22)
		for y in ch:
			var half := int(3 * (1.0 - float(y) / ch))
			for dx in range(-half, half + 1):
				_blend(mid, (x + dx + W) % W, base - y, acc.lerp(Color(mc[0]), 0.3 + 0.5 * float(absi(dx)) / 3.0), 0.85)


static func _city(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color, world: int) -> void:
	_buildings(far, rng, 150, 70, Color(fc[0]), Color(fc[1]), acc, 0.25 if world == 0 else 0.5, 6, 14)
	_buildings(mid, rng, 190, 60, Color(mc[0]), Color(mc[1]), acc, 0.2 if world == 0 else 0.6, 10, 26)
	if world == 1:
		# neon signs
		var neon := [Color("2ef0ff"), Color("ff2e9a"), Color("ffe04a")]
		for i in 7:
			var x := rng.randi_range(0, W - 12)
			var y := rng.randi_range(150, 200)
			var c: Color = neon[rng.randi() % neon.size()]
			mid.fill_rect(Rect2i(x, y, rng.randi_range(6, 12), 2), c)


static func _buildings(img: Image, rng: RandomNumberGenerator, base: int, amp: int, top: Color, bottom: Color, light: Color, lit: float, wmin: int, wmax: int) -> void:
	var x := 0
	while x < W:
		var bw := rng.randi_range(wmin, wmax)
		var by := base - rng.randi_range(0, amp)
		for xx in range(x, mini(x + bw, W)):
			for y in range(by, H):
				var t := float(y - by) / (H - by)
				img.set_pixel(xx, y, top.lerp(bottom, t))
		img.fill_rect(Rect2i(x, by, mini(bw, W - x), 1), top.lightened(0.2))
		# windows
		for wy in range(by + 4, H - 4, 5):
			for wx in range(x + 2, mini(x + bw - 2, W - 1), 3):
				if rng.randf() < lit:
					img.set_pixel(wx, wy, light)
		if rng.randf() < 0.3:
			img.fill_rect(Rect2i(x + bw / 2, by - 8, 1, 8), top)
			img.set_pixel(x + bw / 2, by - 9, Color("ff2e55"))
		x += bw + rng.randi_range(0, 3)


static func _forest(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color, world: int) -> void:
	_silhouette(far, _periodic(rng, 190, [12.0, 6.0, 3.0]), Color(fc[0]), Color(fc[1]), acc, 0.25)
	_trees(far, rng, 200, 40, Color(fc[0]), 30)
	var hills := _periodic(rng, 236, [8.0, 4.0])
	_silhouette(mid, hills, Color(mc[0]), Color(mc[1]), acc, 0.3)
	_trees(mid, rng, 240, 70, Color(mc[0]), 22)
	if world == 1:
		for i in 40:
			_blend(mid, rng.randi_range(0, W - 1), rng.randi_range(120, 250), acc, 0.9)


static func _trees(img: Image, rng: RandomNumberGenerator, base: int, hmax: int, col: Color, n: int) -> void:
	for i in n:
		var x := rng.randi_range(0, W - 1)
		var th := rng.randi_range(hmax / 2, hmax)
		var tw := th / 3
		var by := base + rng.randi_range(-6, 6)
		for y in th:
			var half := int(tw * float(y) / th) + (1 if y % 6 > 3 else 0)
			for dx in range(-half, half + 1):
				var px := (x + dx + W) % W
				var py := by - th + y
				if py >= 0 and py < H:
					img.set_pixel(px, py, col.darkened(0.08 * float(dx + half) / maxf(1.0, half * 2.0)))
		img.fill_rect(Rect2i(x, by, 2, H - by), col.darkened(0.2))


static func _ruins(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color) -> void:
	_silhouette(far, _periodic(rng, 200, [10.0, 5.0]), Color(fc[0]), Color(fc[1]), acc, 0.3)
	# columns and arches
	var x := 10
	while x < W - 20:
		var ch := rng.randi_range(50, 110)
		var cw := rng.randi_range(8, 14)
		var by := 240
		var top := Color(mc[0])
		var bottom := Color(mc[1])
		var broken := rng.randf() < 0.4
		var hh := ch if not broken else ch / 2 + rng.randi_range(0, 20)
		for xx in range(x, x + cw):
			for y in range(by - hh, H):
				mid.set_pixel(xx, y, top.lerp(bottom, float(y - (by - hh)) / (H - by + hh)))
		mid.fill_rect(Rect2i(x - 2, by - hh, cw + 4, 4), top.lightened(0.15))
		for k in range(x + 2, x + cw - 1, 3):
			mid.fill_rect(Rect2i(k, by - hh + 5, 1, hh - 5), top.darkened(0.15))
		x += cw + rng.randi_range(22, 50)
	# light rays from the surface
	for i in 6:
		var rx := rng.randi_range(0, W)
		for y in 200:
			var wdt := 6 + y / 12
			for dx in wdt:
				_blend(far, (rx + dx + y / 3) % W, y, acc, 0.05 * (1.0 - y / 200.0))


static func _volcano(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color, world: int) -> void:
	var h := _jagged(rng, 220, 120, 3)
	_silhouette(far, h, Color(fc[0]), Color(fc[1]), acc, 0.7)
	# lava streams down the slopes
	for i in 5:
		var x := rng.randi_range(0, W - 1)
		var y := int(h[x])
		while y < H - 2:
			_blend(far, x, y, acc, 0.85 if world == 1 else 0.5)
			y += 1
			x = (x + rng.randi_range(-1, 1) + W) % W
	_silhouette(mid, _jagged(rng, 260, 60, 8), Color(mc[0]), Color(mc[1]), acc, 0.6)
	for i in 60:
		_blend(far, rng.randi_range(0, W - 1), rng.randi_range(0, 200), acc, rng.randf_range(0.3, 0.8))


static func _peaks(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color, world: int) -> void:
	var h := _jagged(rng, 200, 130, 5)
	_silhouette(far, h, Color(fc[0]), Color(fc[1]), Color.WHITE, 0.6)
	# snow caps
	for x in W:
		var y0 := int(h[x])
		for y in range(y0, mini(y0 + 10 + (x * 7) % 5, H)):
			_blend(far, x, y, Color.WHITE, 0.75 if world == 0 else 0.35)
	if world == 1:
		# aurora ribbons
		for band in 3:
			var ph := rng.randf() * TAU
			for x in W:
				var cy := 40 + band * 18 + int(12 * sin(TAU * 2.0 * x / W + ph))
				for k in 26:
					_blend(far, x, cy + k, acc, 0.22 * (1.0 - k / 26.0))
	_silhouette(mid, _jagged(rng, 250, 70, 7), Color(mc[0]), Color(mc[1]), Color.WHITE, 0.5)


static func _storm(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color, world: int) -> void:
	# cloud banks
	for layer in 2:
		var base := 40 + layer * 30
		for i in 22:
			var cx := rng.randi_range(0, W)
			var r := rng.randi_range(14, 30)
			for y in range(base - r, base + r):
				for x in range(cx - r * 2, cx + r * 2):
					var d := Vector2((x - cx) * 0.5, y - base).length() / r
					if d < 1.0:
						_blend(far, (x + W) % W, y, Color(fc[layer]).lightened(0.1 * (1.0 - d)), 0.6)
	# lightning bolt
	var lx := rng.randi_range(80, 400)
	var ly := 60
	while ly < 230:
		_blend(far, lx, ly, acc, 1.0)
		_blend(far, lx + 1, ly, acc, 0.5)
		ly += 1
		if rng.randf() < 0.2:
			lx += rng.randi_range(-3, 3)
	# towers
	var x := 0
	while x < W:
		var tw := rng.randi_range(8, 16)
		var th := rng.randi_range(60, 140)
		var top := Color(mc[0])
		for xx in range(x, mini(x + tw, W)):
			for y in range(H - th, H):
				mid.set_pixel(xx, y, top.lerp(Color(mc[1]), float(y - (H - th)) / th))
		mid.fill_rect(Rect2i(x + tw / 2, H - th - 10, 1, 10), top)
		if world == 1:
			mid.set_pixel(x + tw / 2, H - th - 11, acc)
		x += tw + rng.randi_range(20, 60)


static func _space(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color) -> void:
	# nebula clouds
	for i in 10:
		var cx := rng.randi_range(0, W)
		var cy := rng.randi_range(20, 160)
		var r := rng.randi_range(25, 60)
		var col := Color(fc[i % 2]).lerp(acc, 0.3)
		for y in range(cy - r, cy + r):
			for x in range(cx - r, cx + r):
				var d := Vector2(x - cx, y - cy).length() / r
				if d < 1.0:
					_blend(far, (x + W) % W, y, col, 0.12 * (1.0 - d))
	# planet with a ring
	var px := 120
	var py := 90
	var pr := 30
	for y in range(py - pr, py + pr):
		for x in range(px - pr, px + pr):
			var d := Vector2(x - px, y - py).length()
			if d < pr:
				var shade := clampf((x - px + y - py) / float(pr * 2) + 0.5, 0.0, 1.0)
				_blend(far, x, y, Color(fc[0]).lerp(Color(fc[1]).darkened(0.4), shade), 1.0)
	for a in 360:
		var t := deg_to_rad(a)
		var rx := px + int(cos(t) * pr * 1.7)
		var ry := py + int(sin(t) * pr * 0.35)
		if sin(t) > 0 or Vector2(rx - px, ry - py).length() > pr:
			_blend(far, rx, ry, acc, 0.8)
	# floating asteroid garden
	for i in 20:
		var cx := rng.randi_range(0, W)
		var cy := rng.randi_range(150, 260)
		var r := rng.randi_range(4, 14)
		for y in range(cy - r, cy + r):
			for x in range(cx - r, cx + r):
				if Vector2(x - cx, (y - cy) * 1.3).length() < r:
					var col := Color(mc[0]) if y < cy else Color(mc[1])
					mid.set_pixel((x + W) % W, clampi(y, 0, H - 1), col)
		_blend(mid, cx, cy - r + 1, acc, 0.6)


static func _gears(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color) -> void:
	for i in 8:
		_gear(far, rng.randi_range(0, W), rng.randi_range(40, 220), rng.randi_range(20, 50), Color(fc[i % 2]), rng)
	for i in 6:
		_gear(mid, rng.randi_range(0, W), rng.randi_range(170, 270), rng.randi_range(18, 40), Color(mc[i % 2]), rng)
	# vertical pipes (kept vertical so they never read as platforms)
	for i in 5:
		var x := rng.randi_range(0, W - 6)
		var top := rng.randi_range(120, 200)
		mid.fill_rect(Rect2i(x, top, 5, H - top), Color(mc[0]))
		mid.fill_rect(Rect2i(x + 1, top, 1, H - top), acc.darkened(0.5))


static func _gear(img: Image, cx: int, cy: int, r: int, col: Color, rng: RandomNumberGenerator) -> void:
	var teeth := 8 + r / 6
	for y in range(cy - r - 6, cy + r + 6):
		for x in range(cx - r - 6, cx + r + 6):
			var v := Vector2(x - cx, y - cy)
			var d := v.length()
			var a := v.angle()
			var tooth := fmod((a + PI) / TAU * teeth, 1.0) < 0.5
			var outer := r + (5 if tooth else 0)
			if d < outer and d > r * 0.35:
				if d < r * 0.5 or (d > r * 0.55 and fmod((a + PI) / TAU * 5.0, 1.0) < 0.75) or d > r * 0.8:
					img.set_pixel((x + W) % W, clampi(y, 0, H - 1), col.lightened(0.15 * (1.0 - d / outer)))


static func _void(far: Image, mid: Image, rng: RandomNumberGenerator, fc: Array, mc: Array, acc: Color, world: int) -> void:
	# concentric rings around the glowing heart
	for k in 9:
		var r := 20 + k * 22
		for a in 720:
			var t := deg_to_rad(a / 2.0)
			var wob := sin(t * 5.0 + k) * 4.0
			_blend(far, 240 + int(cos(t) * (r + wob) * 1.4), 136 + int(sin(t) * (r + wob) * 0.7), acc if k % 2 == 0 else Color(fc[0]), 0.35 - k * 0.03)
	# floating shards
	for i in 30:
		var cx := rng.randi_range(0, W)
		var cy := rng.randi_range(130, 270)
		var s := rng.randi_range(3, 10)
		for y in s * 2:
			var half := s - absi(y - s)
			for dx in range(-half / 2, half / 2 + 1):
				mid.set_pixel((cx + dx + W) % W, clampi(cy + y - s, 0, H - 1), Color(mc[0]) if dx < 0 else Color(mc[1]))
		_blend(mid, cx, cy - s, acc, 0.9)
