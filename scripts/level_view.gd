class_name LevelView
extends Node2D
## Draws a Sim: baked tile layers, entities, the player, particles and
## the dimension-shift transition. Also converts sim events into effects.

const TS := 16
const LIGHT := 0
const DARK := 1

# Palettes [light, dark]
const C_STONE := [Color("d6daf6"), Color("2a1435")]
const C_STONE_DEEP := [Color("c3c4ee"), Color("1d0c26")]
const C_MORTAR := [Color("b2b2e2"), Color("1a0a22")]
const C_SPECK := [Color("eef0ff"), Color("3c1f4a")]
const C_TOP := [Color("ffffff"), Color("ff2e55")]
const C_TOP2 := [Color("a6ecff"), Color("8a1838")]
const C_SIDE := [Color("a9a6dd"), Color("1f0d29")]
const C_BOTTOM := [Color("9d97d6"), Color("13061a")]
const C_OUTLINE := [Color("5b4fa0"), Color("07020b")]
const C_ACCENT := [Color("4fc3ff"), Color("ff2e55")]
const C_ACCENT2 := [Color("9b7bff"), Color("b0124a")]
const C_TEXT := [Color("2b2350"), Color("ffd6de")]

const CRYSTAL_FILL := Color("bfe9ff")
const CRYSTAL_EDGE := Color("3f8fd9")
const CRYSTAL_HI := Color("ffffff")
const OBSIDIAN_FILL := Color("3b0c2c")
const OBSIDIAN_EDGE := Color("ff2e55")
const OBSIDIAN_VEIN := Color("a3123d")
const GHOST_LIGHT := Color(0.45, 0.75, 1.0, 0.55)
const GHOST_DARK := Color(0.85, 0.2, 0.45, 0.6)

const SPIKE_W := [1, 1, 3, 3, 3, 5, 5, 5]

const PLAYER_FRAMES := {
	"body": [
		"............",
		"....oooo....",
		"...occcco...",
		"..occcccco..",
		"..occfefeo..",
		"..occffffo..",
		"..osssssso..",
		"..ohccccco..",
		".ohcccccco..",
		".ohcccccco..",
		".ohhcccccco.",
		".ohhcccccco.",
		"..ohhcccco..",
		"..ohhcccco..",
	],
	"idle": ["...oo..oo...", "...oo..oo..."],
	"run0": ["..oo....oo..", ".oo......oo."],
	"run1": ["...oo.oo....", "...oo.oo...."],
	"run2": ["..oo...oo...", "..o.....oo.."],
	"run3": ["....oo.oo...", "....oo.oo..."],
	"jump": ["...oooo.....", "............"],
	"fall": ["..oo....oo..", ".o........o."],
}
const PLAYER_PAL := [
	{"o": Color("2b2350"), "c": Color("f4f2ff"), "h": Color("c9c3f0"), "f": Color("3b2f6b"), "e": Color("7fe3ff"), "s": Color("4fc3ff")},
	{"o": Color("c08cff"), "c": Color("3a1d55"), "h": Color("26103a"), "f": Color("0b0414"), "e": Color("ffffff"), "s": Color("ff2e55")},
]

var sim: Sim
var post: ShaderMaterial
var anim := 0.0
var tile_tex := [null, null]
var bg_far := []
var bg_mid := []
var sprites := [{}, {}]

var old_world := LIGHT
var shift_fx := 1.0
var particles: Array = []
var shake := 0.0
var shake_offset := Vector2.ZERO
var flash := 0.0
var flash_color := Color.WHITE
var wave_t := -1.0
var wave_center := Vector2.ZERO
var aberration := 0.0

var player_prev := Vector2.ZERO
var player_cur := Vector2.ZERO
var mover_prev: Array = []
var run_time := 0.0
var squash := Vector2.ONE
var blocked_fx := 0.0
var show_player := true
var win_fx := -1.0
var respawn_fx := 0.0
var scarf: Array[Vector2] = []
var near_sign := -1
var shake_enabled := true
var title_mode := false   # used by menus: only backgrounds + ambience
var title_world := LIGHT


func _ready() -> void:
	bg_far = [load("res://assets/bg_light_far.png"), load("res://assets/bg_dark_far.png")]
	bg_mid = [load("res://assets/bg_light_mid.png"), load("res://assets/bg_dark_mid.png")]
	for w in 2:
		for key in PLAYER_FRAMES.keys():
			if key == "body":
				continue
			sprites[w][key] = _bake_player(w, key)
	for i in 5:
		scarf.append(Vector2.ZERO)


# ------------------------------------------------------------------ setup

func set_sim(s: Sim) -> void:
	sim = s
	near_sign = -1
	particles.clear()
	shift_fx = 1.0
	old_world = sim.world
	win_fx = -1.0
	show_player = true
	snap_player()
	tile_tex[LIGHT] = _bake_tiles(LIGHT)
	tile_tex[DARK] = _bake_tiles(DARK)


func snap_player() -> void:
	player_cur = Vector2(sim.px, sim.py)
	player_prev = player_cur
	for i in scarf.size():
		scarf[i] = player_cur + Vector2(5, 7)


func before_step() -> void:
	player_prev = Vector2(sim.px, sim.py)
	mover_prev.clear()
	for m in sim.movers:
		mover_prev.append(Vector2(m["x"], m["y"]))


func after_step() -> void:
	player_cur = Vector2(sim.px, sim.py)
	if sim.on_ground and abs(sim.vx) > 8.0:
		run_time += 1.0 / 60.0
	else:
		run_time = 0.0
	_handle_events(sim.events)


func world_shown() -> int:
	if title_mode or sim == null:
		return title_world
	return sim.world


func title_shift() -> void:
	old_world = title_world
	title_world = 1 - title_world
	shift_fx = 0.0
	wave_t = 0.0
	wave_center = Vector2(240, 136)
	aberration = 0.6


# ------------------------------------------------------------------ events & fx

func _handle_events(events: Array) -> void:
	for e in events:
		var n: String = e[0]
		var p := Vector2(e[1], e[2])
		match n:
			"shift":
				old_world = 1 - sim.world
				shift_fx = 0.0
				add_shake(2.0)
				wave_t = 0.0
				wave_center = p
				aberration = 1.0
				flash = 0.25
				flash_color = Color("ffffff") if sim.world == LIGHT else Color("ff2e55")
				_burst(p, 22, [C_ACCENT[sim.world], C_ACCENT[1 - sim.world], Color.WHITE], 70.0, 0.5, 0.0)
				Sound.play("shift_dark" if sim.world == DARK else "shift_light", 0.03)
				Sound.set_world(sim.world == DARK)
			"shift_blocked":
				blocked_fx = 0.35
				add_shake(1.5)
				Sound.play("blocked")
			"jump":
				squash = Vector2(0.75, 1.3)
				_burst(p, 5, [C_SPECK[sim.world], C_SIDE[sim.world]], 30.0, 0.3, 200.0, Vector2(0, -10))
				Sound.play("jump", 0.06)
			"land":
				squash = Vector2(1.35, 0.7)
				_burst(p, 6, [C_SPECK[sim.world], C_SIDE[sim.world]], 35.0, 0.3, 150.0, Vector2(0, -12))
				Sound.play("land", 0.1, -4.0)
			"die":
				show_player = false
				add_shake(6.0)
				flash = 0.45
				flash_color = Color("ff2e55")
				var pal: Dictionary = PLAYER_PAL[sim.world]
				_burst(p, 34, [pal["c"], pal["h"], pal["s"], pal["e"]], 120.0, 0.9, 260.0)
				Sound.play("die")
			"shard":
				add_shake(2.0)
				flash = 0.2
				flash_color = Color("fff3a0")
				_burst(p, 26, [Color("fff3a0"), Color.WHITE, C_ACCENT[sim.world]], 90.0, 0.8, 0.0)
				Sound.play("shard")
			"checkpoint":
				_burst(p, 18, [C_ACCENT[sim.world], Color.WHITE], 60.0, 0.6, -40.0)
				Sound.play("checkpoint")
			"lever":
				add_shake(3.0)
				_burst(p, 10, [C_ACCENT[sim.world], Color.WHITE], 50.0, 0.4, 100.0)
				Sound.play("lever")
			"crack":
				Sound.play("crack", 0.2)
			"crumble":
				add_shake(1.5)
				_burst(p, 12, [Color("b9a3e8") if sim.world == LIGHT else Color("5a1f45"), C_SIDE[sim.world]], 40.0, 0.7, 300.0)
				Sound.play("crumble", 0.1)
			"win":
				win_fx = 0.0
				flash = 0.5
				flash_color = Color.WHITE
				_burst(p, 40, [C_ACCENT[0], C_ACCENT[1], Color.WHITE], 100.0, 1.0, 0.0)
				Sound.play("win")
			"bolt_fire":
				_burst(p, 4, [Color("ff2e55"), Color("ffb0c0")], 30.0, 0.25, 0.0)
				Sound.play("bolt", 0.1, -6.0)
			"bolt_fizzle":
				_burst(p, 5, [Color("ff2e55"), Color("ffb0c0")], 40.0, 0.25, 0.0)
				Sound.play("fizzle", 0.15, -8.0)


func on_respawn() -> void:
	show_player = true
	snap_player()
	shift_fx = 1.0
	old_world = sim.world
	respawn_fx = 1.0
	var c := player_cur + Vector2(5, 7)
	for i in 20:
		var a := TAU * i / 20.0
		var start := c + Vector2(cos(a), sin(a)) * 26.0
		particles.append({"p": start, "v": (c - start) * 2.2, "life": 0.45, "max": 0.45, "c": C_ACCENT[sim.world], "s": 2.0, "g": 0.0, "front": true})
	Sound.play("respawn")
	Sound.set_world(sim.world == DARK, true)


func add_shake(a: float) -> void:
	if shake_enabled:
		shake = max(shake, a)


func _burst(p: Vector2, n: int, colors: Array, speed: float, life: float, grav: float, bias: Vector2 = Vector2.ZERO) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * randf_range(0.3, 1.0) + bias
		particles.append({"p": p, "v": v, "life": life * randf_range(0.6, 1.0), "max": life, "c": colors[randi() % colors.size()], "s": [1.0, 1.0, 2.0][randi() % 3], "g": grav, "front": true})


func _ambient(delta: float) -> void:
	var w := world_shown()
	var count := 0
	for p in particles:
		if not p["front"]:
			count += 1
	if count < 70 and randf() < delta * 14.0:
		if w == LIGHT:
			particles.append({"p": Vector2(randf() * 480, 280), "v": Vector2(randf_range(-6, 6), randf_range(-14, -6)), "life": 9.0, "max": 9.0, "c": [Color(1, 1, 1, 0.8), Color("a6ecff"), Color("d9ccff")][randi() % 3], "s": 1.0, "g": 0.0, "front": false, "wob": randf() * TAU})
		else:
			particles.append({"p": Vector2(randf() * 480, 280), "v": Vector2(randf_range(-4, 10), randf_range(-24, -10)), "life": 7.0, "max": 7.0, "c": [Color("ff2e55"), Color("ff7a3d"), Color("b0124a")][randi() % 3], "s": 1.0, "g": 0.0, "front": false, "wob": randf() * TAU})


# ------------------------------------------------------------------ frame update

func _process(delta: float) -> void:
	anim += delta
	shift_fx = min(1.0, shift_fx + delta / 0.3)
	blocked_fx = max(0.0, blocked_fx - delta)
	respawn_fx = max(0.0, respawn_fx - delta * 2.5)
	flash = max(0.0, flash - delta * 2.2)
	aberration = max(0.0, aberration - delta * 3.0)
	squash = squash.lerp(Vector2.ONE, min(1.0, delta * 14.0))
	if win_fx >= 0.0:
		win_fx += delta
	if shake > 0.0:
		shake = max(0.0, shake - delta * 18.0)
		shake_offset = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)).round()
	else:
		shake_offset = Vector2.ZERO
	position = shake_offset
	if wave_t >= 0.0:
		wave_t += delta
		if wave_t > 0.6:
			wave_t = -1.0
	_ambient(delta)
	var keep := []
	for p in particles:
		p["life"] -= delta
		if p["life"] <= 0.0:
			continue
		var v: Vector2 = p["v"]
		v.y += p["g"] * delta
		var pos: Vector2 = p["p"] + v * delta
		if p.has("wob"):
			pos.x += sin(anim * 1.5 + p["wob"]) * 0.15
		p["v"] = v
		p["p"] = pos
		keep.append(p)
	particles = keep
	_update_scarf(delta)
	_update_post()
	queue_redraw()


func _update_post() -> void:
	if post == null:
		return
	if wave_t >= 0.0:
		var c := (wave_center + position) / Vector2(480, 272)
		post.set_shader_parameter("center", c)
		post.set_shader_parameter("radius", wave_t * 1.6)
		post.set_shader_parameter("strength", 0.018 * (1.0 - wave_t / 0.6))
	else:
		post.set_shader_parameter("radius", -1.0)
	post.set_shader_parameter("aberration", aberration * 0.006)
	post.set_shader_parameter("flash", flash)
	post.set_shader_parameter("flash_color", Vector3(flash_color.r, flash_color.g, flash_color.b))


func player_draw_pos() -> Vector2:
	var f := Engine.get_physics_interpolation_fraction()
	return player_prev.lerp(player_cur, f)


func _update_scarf(delta: float) -> void:
	if sim == null:
		return
	var pp := player_draw_pos()
	var facing := sim.facing
	var anchor := pp + Vector2(5 - facing * 3, 6)
	scarf[0] = anchor
	for i in range(1, scarf.size()):
		var target: Vector2 = scarf[i - 1] + Vector2(-facing * 2.0, 0.6 + sin(anim * 10.0 + i) * 0.6)
		scarf[i] = scarf[i].lerp(target, min(1.0, delta * 30.0))
		var d: Vector2 = scarf[i] - scarf[i - 1]
		if d.length() > 2.5:
			scarf[i] = scarf[i - 1] + d.normalized() * 2.5


# ------------------------------------------------------------------ drawing

func _draw() -> void:
	var w := world_shown()
	var t := shift_fx
	_draw_background(w, t)
	for p in particles:
		if not p["front"]:
			_draw_particle(p)
	if title_mode or sim == null:
		return
	# dim the backdrop so the playfield reads clearly
	var dim_l := Color(0.16, 0.10, 0.40, 0.26)
	var dim_d := Color(0.0, 0.0, 0.0, 0.32)
	draw_rect(Rect2(0, 0, 480, 272), dim_l if w == LIGHT else dim_d)
	draw_texture(tile_tex[w], Vector2.ZERO)
	if t < 1.0:
		draw_texture(tile_tex[old_world], Vector2.ZERO, Color(1, 1, 1, 1.0 - _ease(t)))
	_draw_dynamic_tiles(w)
	_draw_signs(w)
	_draw_checkpoints(w)
	_draw_exit(w)
	_draw_shard(w)
	_draw_levers(w)
	_draw_movers(w)
	_draw_turrets(w)
	_draw_walkers(w)
	_draw_wisps(w)
	_draw_bolts()
	_draw_player(w)
	for p in particles:
		if p["front"]:
			_draw_particle(p)


func _ease(t: float) -> float:
	return 1.0 - pow(1.0 - t, 3.0)


func _draw_particle(p: Dictionary) -> void:
	var c: Color = p["c"]
	var a: float = clamp(p["life"] / p["max"] * 1.5, 0.0, 1.0)
	var s: float = p["s"]
	draw_rect(Rect2(p["p"].floor(), Vector2(s, s)), Color(c.r, c.g, c.b, c.a * a))


func _draw_background(w: int, t: float) -> void:
	var scroll := fmod(anim * (4.0 if w == LIGHT else 2.5), 480.0)
	_draw_bg_world(w, scroll, 1.0)
	if t < 1.0:
		_draw_bg_world(old_world, scroll, 1.0 - _ease(t))


func _draw_bg_world(w: int, scroll: float, alpha: float) -> void:
	var mod := Color(1, 1, 1, alpha)
	draw_texture(bg_far[w], Vector2.ZERO, mod)
	var x := -floorf(scroll)
	draw_texture(bg_mid[w], Vector2(x, 0), mod)
	draw_texture(bg_mid[w], Vector2(x + 480, 0), mod)


# --- dynamic tiles: gates and crumbling bridges

func _draw_dynamic_tiles(w: int) -> void:
	for cy in Sim.ROWS:
		for cx in Sim.COLS:
			var c := sim.grid[cy * Sim.COLS + cx]
			if c == Sim.T_GATE or c == Sim.T_OGATE:
				var solid := (c == Sim.T_GATE) != sim.gates_flipped
				_draw_gate(cx * TS, cy * TS, w, solid)
			elif c == Sim.T_CRUMBLE:
				var k: int = sim.crumble_cells[cy * Sim.COLS + cx]
				_draw_crumble(cx * TS, cy * TS, w, sim.crumble_state[k], sim.crumble_timer[k])


func _draw_gate(x: int, y: int, w: int, solid: bool) -> void:
	var col: Color = Color("6f5bd6") if w == LIGHT else Color("c4204f")
	if solid:
		draw_rect(Rect2(x, y, 16, 16), Color(col.r, col.g, col.b, 0.22))
		for i in 4:
			draw_rect(Rect2(x + 1 + i * 4, y, 2, 16), col)
			draw_rect(Rect2(x + 1 + i * 4, y, 1, 16), col.lightened(0.35))
		draw_rect(Rect2(x, y + 3, 16, 2), col.darkened(0.25))
		draw_rect(Rect2(x, y + 11, 16, 2), col.darkened(0.25))
	else:
		for i in 4:
			for j in range(0, 16, 3):
				draw_rect(Rect2(x + 1 + i * 4, y + j, 1, 1), Color(col.r, col.g, col.b, 0.35))


func _draw_crumble(x: int, y: int, w: int, state: int, timer: float) -> void:
	var plank: Color = Color("c9b8f2") if w == LIGHT else Color("4a1a3a")
	var dark: Color = Color("8a76c9") if w == LIGHT else Color("1f0717")
	var crack: Color = Color("5b4fa0") if w == LIGHT else Color("ff2e55")
	if state == 2:
		if timer > Sim.CRUMBLE_RESPAWN - 0.6 and fmod(anim * 12.0, 1.0) < 0.5:
			draw_rect(Rect2(x, y, 16, 6), Color(plank.r, plank.g, plank.b, 0.35))
		else:
			for i in range(0, 16, 4):
				draw_rect(Rect2(x + i, y, 2, 1), Color(plank.r, plank.g, plank.b, 0.25))
		return
	var off := Vector2.ZERO
	if state == 1:
		off = Vector2(randi_range(-1, 1), randi_range(0, 1))
	draw_rect(Rect2(Vector2(x, y) + off, Vector2(16, 6)), plank)
	draw_rect(Rect2(Vector2(x, y + 5) + off, Vector2(16, 1)), dark)
	draw_rect(Rect2(Vector2(x + 7, y) + off, Vector2(1, 6)), dark)
	draw_rect(Rect2(Vector2(x, y) + off, Vector2(16, 1)), plank.lightened(0.3))
	draw_rect(Rect2(Vector2(x + 2, y + 6) + off, Vector2(2, 3)), dark)
	draw_rect(Rect2(Vector2(x + 12, y + 6) + off, Vector2(2, 3)), dark)
	if state == 1:
		draw_rect(Rect2(Vector2(x + 3, y + 1) + off, Vector2(1, 3)), crack)
		draw_rect(Rect2(Vector2(x + 4, y + 3) + off, Vector2(2, 1)), crack)
		draw_rect(Rect2(Vector2(x + 11, y + 2) + off, Vector2(1, 3)), crack)


# --- entities

func _draw_signs(w: int) -> void:
	near_sign = -1
	var p := Rect2(sim.px, sim.py, Sim.PW, Sim.PH)
	for i in sim.signs.size():
		var s: Dictionary = sim.signs[i]
		var cell: Vector2i = s["cell"]
		var x := cell.x * TS + 3
		var y := cell.y * TS + 5
		var near: bool = s["rect"].intersects(p)
		if near:
			near_sign = i
		var stone: Color = Color("9d97d6") if w == LIGHT else Color("3a1a48")
		draw_rect(Rect2(x, y, 10, 11), C_OUTLINE[w])
		draw_rect(Rect2(x + 1, y + 1, 8, 10), stone)
		var glyph: Color = C_ACCENT[w] if near else (Color("ffffff") if w == LIGHT else Color("8a4a6a"))
		if near:
			glyph = glyph.lightened(0.3 + 0.2 * sin(anim * 6.0))
		PixelFont.draw(self, "?", Vector2(x + 3, y + 2), glyph)


func _draw_checkpoints(w: int) -> void:
	for i in sim.checkpoints.size():
		var r: Rect2 = sim.checkpoints[i]
		var x := r.position.x
		var y := r.end.y
		var active := i == sim.checkpoint_active
		var stone: Color = Color("8f88d8") if w == LIGHT else Color("2a1238")
		draw_rect(Rect2(x + 2, y - 10, 6, 10), C_OUTLINE[w])
		draw_rect(Rect2(x + 3, y - 9, 4, 9), stone)
		draw_rect(Rect2(x + 1, y - 2, 8, 2), C_OUTLINE[w])
		var gem: Color = C_ACCENT[w] if active else (Color("b8b4e0") if w == LIGHT else Color("4a2a58"))
		var bob := sin(anim * 3.0) * 1.5 if active else 0.0
		var gy := y - 16 + bob
		draw_rect(Rect2(x + 4, gy, 2, 1), gem)
		draw_rect(Rect2(x + 3, gy + 1, 4, 3), gem)
		draw_rect(Rect2(x + 4, gy + 4, 2, 1), gem)
		if active:
			draw_circle(Vector2(x + 5, gy + 2.5), 6.0 + sin(anim * 5.0), Color(gem.r, gem.g, gem.b, 0.18))
			if randf() < 0.15:
				particles.append({"p": Vector2(x + 5 + randf_range(-2, 2), gy), "v": Vector2(0, -18), "life": 0.6, "max": 0.6, "c": gem, "s": 1.0, "g": 0.0, "front": true})


func _draw_exit(_w: int) -> void:
	var c := sim.exit_rect.get_center()
	var pulse := 1.0 + sin(anim * 3.0) * 0.08
	var rx := 7.0 * pulse
	var ry := 15.0 * pulse
	draw_circle(c, 18.0, Color(0.6, 0.3, 1.0, 0.10))
	draw_set_transform(c, 0.0, Vector2(rx / ry, 1.0))
	draw_circle(Vector2.ZERO, ry, Color("12031c"))
	draw_circle(Vector2.ZERO, ry * 0.7, Color("2a0b44"))
	draw_circle(Vector2.ZERO, ry * 0.4, Color("5b1f8a"))
	draw_set_transform(Vector2.ZERO)
	for i in 18:
		var a := anim * 2.2 + TAU * i / 18.0
		var p := c + Vector2(cos(a) * rx, sin(a) * ry)
		var col: Color = C_ACCENT[LIGHT] if i % 2 == 0 else C_ACCENT[DARK]
		draw_rect(Rect2(p.floor(), Vector2(2, 2)), col)
	for i in 8:
		var a := -anim * 3.5 + TAU * i / 8.0
		var p := c + Vector2(cos(a) * rx * 0.5, sin(a) * ry * 0.5)
		draw_rect(Rect2(p.floor(), Vector2(1, 1)), Color.WHITE)
	if randf() < 0.3:
		var a := randf() * TAU
		var start := c + Vector2(cos(a) * 20, sin(a) * 26)
		particles.append({"p": start, "v": (c - start) * 1.6, "life": 0.6, "max": 0.6, "c": C_ACCENT[randi() % 2], "s": 1.0, "g": 0.0, "front": true})


func _draw_shard(w: int) -> void:
	if not sim.has_shard or sim.shard_taken:
		return
	var c := sim.shard_rect.get_center() + Vector2(0, sin(anim * 2.5) * 2.0)
	var spin: float = abs(cos(anim * 2.0))
	var hw := 1.0 + spin * 3.5
	draw_circle(c, 9.0 + sin(anim * 4.0), Color(1.0, 0.95, 0.6, 0.15))
	var col := Color("fff3a0")
	var pts := PackedVector2Array([c + Vector2(0, -6), c + Vector2(hw, 0), c + Vector2(0, 6), c + Vector2(-hw, 0)])
	draw_colored_polygon(pts, col)
	draw_line(c + Vector2(0, -6), c + Vector2(0, 6), Color.WHITE)
	draw_rect(Rect2(c + Vector2(-hw * 0.5, -2), Vector2(1, 1)), Color.WHITE)
	if randf() < 0.12:
		particles.append({"p": c + Vector2(randf_range(-6, 6), randf_range(-6, 6)), "v": Vector2(0, -8), "life": 0.5, "max": 0.5, "c": Color.WHITE if w == LIGHT else col, "s": 1.0, "g": 0.0, "front": true})


func _draw_levers(w: int) -> void:
	for r in sim.levers:
		var base := Vector2(r.position.x + 6, r.end.y)
		var ang := deg_to_rad(35.0 if sim.gates_flipped else -35.0)
		var tip := base + Vector2(sin(ang), -cos(ang)) * 10.0
		draw_line(base + Vector2(0, -2), tip, C_OUTLINE[w], 2.0)
		draw_rect(Rect2(tip - Vector2(2, 2), Vector2(4, 4)), C_ACCENT[w])
		draw_rect(Rect2(base.x - 5, base.y - 3, 10, 3), C_OUTLINE[w])
		draw_rect(Rect2(base.x - 4, base.y - 3, 8, 1), C_SIDE[w].lightened(0.3))


func _draw_movers(w: int) -> void:
	var f := Engine.get_physics_interpolation_fraction()
	for i in sim.movers.size():
		var m: Dictionary = sim.movers[i]
		var pos := Vector2(m["x"], m["y"])
		if i < mover_prev.size():
			pos = mover_prev[i].lerp(pos, f)
		pos = pos.round()
		var mw: int = m["w"]
		if w == LIGHT:
			draw_rect(Rect2(pos, Vector2(mw, 8)), Color("4b3f8f"))
			draw_rect(Rect2(pos + Vector2(1, 1), Vector2(mw - 2, 5)), Color("e8ecff"))
			draw_rect(Rect2(pos + Vector2(1, 5), Vector2(mw - 2, 2)), Color("9a92dc"))
			for k in range(4, mw - 2, 8):
				draw_rect(Rect2(pos + Vector2(k, 3), Vector2(1, 1)), Color("6f63c0"))
			var blink := Color("4fc3ff") if fmod(anim * 2.0, 1.0) < 0.5 else Color("bff0ff")
			draw_rect(Rect2(pos + Vector2(mw / 2 - 1, 2), Vector2(2, 2)), blink)
		else:
			draw_rect(Rect2(pos, Vector2(mw, 8)), Color("05010a"))
			draw_rect(Rect2(pos + Vector2(1, 1), Vector2(mw - 2, 5)), Color("3d3150"))
			draw_rect(Rect2(pos + Vector2(1, 5), Vector2(mw - 2, 2)), Color("2a2038"))
			# frozen-time frost specks
			for k in range(2, mw - 2, 5):
				draw_rect(Rect2(pos + Vector2(k, 1 + (k % 3)), Vector2(1, 1)), Color("a6b4ff"))
			draw_rect(Rect2(pos + Vector2(mw / 2 - 1, 2), Vector2(2, 2)), Color("ff2e55"))


func _draw_turrets(w: int) -> void:
	for t in sim.turrets:
		var x: int = t["cx"] * TS
		var y: int = t["cy"] * TS
		var dir: int = t["dir"]
		draw_rect(Rect2(x, y, 16, 16), C_OUTLINE[w])
		draw_rect(Rect2(x + 1, y + 1, 14, 14), Color("8f88d8") if w == LIGHT else Color("1e0a28"))
		var mx := x + (13 if dir > 0 else 0)
		draw_rect(Rect2(mx, y + 5, 3, 6), C_OUTLINE[w])
		var eye := Vector2(x + 8 + dir * 2, y + 8)
		if w == DARK:
			var charge: float = clamp((t["t"] - (Sim.TURRET_PERIOD - 0.5)) / 0.5, 0.0, 1.0)
			draw_circle(eye, 3.0 + charge * 1.5, Color(1.0, 0.18, 0.33, 0.35 + charge * 0.4))
			draw_rect(Rect2(eye - Vector2(1, 1), Vector2(3, 3)), Color("ff2e55"))
			draw_rect(Rect2(eye, Vector2(1, 1)), Color.WHITE)
		else:
			draw_rect(Rect2(eye.x - 2, eye.y, 5, 1), Color("4b3f8f"))


func _draw_walkers(w: int) -> void:
	for k in sim.walkers:
		var x: float = round(k["x"])
		var y: float = round(k["y"])
		var dir: int = k["dir"]
		if w == LIGHT:
			# frozen crystal form
			draw_rect(Rect2(x, y, 14, 16), CRYSTAL_EDGE)
			draw_rect(Rect2(x + 1, y + 1, 12, 14), CRYSTAL_FILL)
			draw_rect(Rect2(x + 2, y + 2, 3, 1), CRYSTAL_HI)
			draw_rect(Rect2(x + 2, y + 3, 1, 4), CRYSTAL_HI)
			draw_rect(Rect2(x + 9, y + 9, 3, 4), Color("8ccff5"))
			draw_rect(Rect2(x + 4 + (2 if dir > 0 else 0), y + 6, 2, 2), Color("6aa7d6"))
			draw_rect(Rect2(x + 8 + (2 if dir > 0 else 0), y + 6, 2, 2), Color("6aa7d6"))
		else:
			var step := int(anim * 8.0) % 2
			draw_rect(Rect2(x + 1, y + 1, 12, 11), Color("ff2e55"))
			draw_rect(Rect2(x + 2, y + 2, 10, 9), Color("170720"))
			draw_rect(Rect2(x + 3, y, 2, 2), Color("ff2e55"))
			draw_rect(Rect2(x + 9, y, 2, 2), Color("ff2e55"))
			var ex := x + (7 if dir > 0 else 3)
			draw_rect(Rect2(ex, y + 5, 2, 2), Color("ffffff"))
			draw_rect(Rect2(ex + 3, y + 5, 2, 2), Color("ffffff"))
			draw_rect(Rect2(x + 2, y + 12, 2, 4 - step), Color("ff2e55"))
			draw_rect(Rect2(x + 6, y + 12, 2, 3 + step), Color("ff2e55"))
			draw_rect(Rect2(x + 10, y + 12, 2, 4 - step), Color("ff2e55"))


func _draw_wisps(w: int) -> void:
	for f in sim.wisps:
		var c := Vector2(f["x"], f["y"]).round()
		if w == DARK:
			var flick := sin(anim * 14.0 + c.x) * 0.8
			draw_circle(c, 8.0 + flick, Color(1.0, 0.18, 0.33, 0.18))
			draw_circle(c, 5.0, Color("ff2e55"))
			draw_circle(c, 3.0, Color("ffb0c0"))
			draw_rect(Rect2(c - Vector2(2, 1), Vector2(1, 1)), Color("170720"))
			draw_rect(Rect2(c + Vector2(1, -1), Vector2(1, 1)), Color("170720"))
			if randf() < 0.5:
				particles.append({"p": c + Vector2(randf_range(-3, 3), randf_range(-3, 3)), "v": Vector2(randf_range(-6, 6), -14), "life": 0.4, "max": 0.4, "c": Color("ff2e55"), "s": 1.0, "g": 0.0, "front": true})
		else:
			draw_circle(c, 4.0, Color(0.75, 0.9, 1.0, 0.25))
			draw_circle(c, 2.0, Color(1, 1, 1, 0.45))


func _draw_bolts() -> void:
	for b in sim.bolts:
		var p := Vector2(b["x"], b["y"]).round()
		var dir := signf(b["vx"])
		for i in 3:
			draw_rect(Rect2(p - Vector2(dir * (i + 1) * 3, 0) + Vector2(1, 1), Vector2(3, 2)), Color(1.0, 0.18, 0.33, 0.5 - i * 0.15))
		draw_rect(Rect2(p, Vector2(6, 4)), Color("ff2e55"))
		draw_rect(Rect2(p + Vector2(1, 1), Vector2(4, 2)), Color("ffd0da"))


func _draw_player(w: int) -> void:
	if not show_player and win_fx < 0.0:
		return
	var pp := player_draw_pos()
	var key := "idle"
	if not sim.on_ground:
		key = "jump" if sim.vy < 0.0 else "fall"
	elif run_time > 0.0:
		key = "run%d" % (int(run_time * 12.0) % 4)
	var tex: Texture2D = sprites[w][key]
	var origin := pp + Vector2(5, 14)  # feet centre
	var sc := squash
	var rot := 0.0
	if win_fx >= 0.0:
		var k: float = clamp(win_fx / 0.8, 0.0, 1.0)
		origin = origin.lerp(sim.exit_rect.get_center() + Vector2(0, 7), k)
		sc *= (1.0 - k)
		rot = k * TAU * 1.5
		if k >= 1.0:
			return
	# scarf tail (drawn behind the body)
	var pal: Dictionary = PLAYER_PAL[w]
	if win_fx < 0.0:
		for i in range(1, scarf.size()):
			var s: Vector2 = scarf[i]
			draw_rect(Rect2(s.floor(), Vector2(2, 1 if i > 2 else 2)), pal["s"])
	draw_set_transform(origin, rot, Vector2(sc.x * sim.facing, sc.y))
	draw_texture(tex, Vector2(-6, -16))
	draw_set_transform(Vector2.ZERO)
	if blocked_fx > 0.0:
		var a := blocked_fx / 0.35
		draw_rect(Rect2(pp - Vector2(3, 4), Vector2(16, 20)), Color(1.0, 0.2, 0.3, a), false, 1.0)
		PixelFont.draw(self, "X", pp + Vector2(2, -12), Color(1.0, 0.25, 0.35, a))
	if respawn_fx > 0.0:
		draw_circle(pp + Vector2(5, 7), (1.0 - respawn_fx) * 22.0, Color(C_ACCENT[w].r, C_ACCENT[w].g, C_ACCENT[w].b, respawn_fx * 0.4))


# ------------------------------------------------------------------ baking

func _bake_player(w: int, legs_key: String) -> ImageTexture:
	var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rows: Array = PLAYER_FRAMES["body"].duplicate()
	rows.append_array(PLAYER_FRAMES[legs_key])
	var pal: Dictionary = PLAYER_PAL[w]
	for y in rows.size():
		var row: String = rows[y]
		for x in 12:
			var ch := row[x]
			if pal.has(ch):
				img.set_pixel(x, y, pal[ch])
	return ImageTexture.create_from_image(img)


func _bake_tiles(w: int) -> ImageTexture:
	var img := Image.create(Sim.COLS * TS, Sim.ROWS * TS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for cy in Sim.ROWS:
		for cx in Sim.COLS:
			var c := sim.tile(cx, cy)
			var x := cx * TS
			var y := cy * TS
			match c:
				Sim.T_STONE:
					_img_stone(img, cx, cy, w)
				Sim.T_LIGHT:
					if w == LIGHT:
						_img_crystal(img, cx, cy)
					else:
						_img_ghost(img, cx, cy, Sim.T_LIGHT, GHOST_LIGHT)
				Sim.T_DARK:
					if w == DARK:
						_img_obsidian(img, cx, cy)
					else:
						_img_ghost(img, cx, cy, Sim.T_DARK, GHOST_DARK)
				Sim.T_SPIKE:
					_img_spikes(img, x, y, Color("5b4fa0") if w == LIGHT else Color("ff2e55"), Color.WHITE if w == LIGHT else Color("ffc0cc"), false)
				Sim.T_LSPIKE:
					_img_spikes(img, x, y, Color("4fb6f5"), Color("e0f8ff"), w != LIGHT)
				Sim.T_DSPIKE:
					_img_spikes(img, x, y, Color("ff2e55"), Color("ffd0da"), w != DARK)
	return ImageTexture.create_from_image(img)


func _same(cx: int, cy: int, code: int) -> bool:
	if cx < 0 or cx >= Sim.COLS or cy < 0 or cy >= Sim.ROWS:
		return code == Sim.T_STONE
	var c := sim.tile(cx, cy)
	if code == Sim.T_STONE:
		return c == Sim.T_STONE
	return c == code


func _hash(x: int, y: int) -> int:
	var h := x * 374761393 + y * 668265263
	h = (h ^ (h >> 13)) * 1274126177
	return abs(h ^ (h >> 16))


func _img_stone(img: Image, cx: int, cy: int, w: int) -> void:
	var x := cx * TS
	var y := cy * TS
	var top := not _same(cx, cy - 1, Sim.T_STONE)
	var bot := not _same(cx, cy + 1, Sim.T_STONE)
	var lft := not _same(cx - 1, cy, Sim.T_STONE)
	var rgt := not _same(cx + 1, cy, Sim.T_STONE)
	var interior := not (top or bot or lft or rgt)
	var base: Color = C_STONE_DEEP[w] if interior else C_STONE[w]
	img.fill_rect(Rect2i(x, y, 16, 16), base)
	var off := 0 if cy % 2 == 0 else 8
	img.fill_rect(Rect2i(x, y + 7, 16, 1), C_MORTAR[w])
	img.fill_rect(Rect2i(x + (4 + off) % 16, y, 1, 7), C_MORTAR[w])
	img.fill_rect(Rect2i(x + (12 + off) % 16, y + 8, 1, 8), C_MORTAR[w])
	var h := _hash(cx, cy)
	for i in 3:
		var sx := (h >> (i * 4)) % 14 + 1
		var sy := (h >> (i * 4 + 2)) % 14 + 1
		img.set_pixel(x + sx, y + sy, C_SPECK[w])
	if lft:
		img.fill_rect(Rect2i(x, y, 1, 16), C_OUTLINE[w])
		img.fill_rect(Rect2i(x + 1, y, 1, 16), C_SIDE[w])
	if rgt:
		img.fill_rect(Rect2i(x + 15, y, 1, 16), C_OUTLINE[w])
		img.fill_rect(Rect2i(x + 14, y, 1, 16), C_SIDE[w])
	if bot:
		img.fill_rect(Rect2i(x, y + 14, 16, 1), C_BOTTOM[w])
		img.fill_rect(Rect2i(x, y + 15, 16, 1), C_OUTLINE[w])
	if top:
		img.fill_rect(Rect2i(x, y, 16, 1), C_TOP[w])
		img.fill_rect(Rect2i(x, y + 1, 16, 1), C_TOP2[w])
		if w == LIGHT:
			# little frost tufts
			for i in 3:
				var gx := (h >> (i * 3 + 1)) % 15
				img.set_pixel(x + gx, y + 2, C_TOP2[w])
		else:
			for i in 2:
				var gx := (h >> (i * 5 + 2)) % 15
				img.fill_rect(Rect2i(x + gx, y + 2, 1, 2), Color("5a0f2e"))


func _img_crystal(img: Image, cx: int, cy: int) -> void:
	var x := cx * TS
	var y := cy * TS
	img.fill_rect(Rect2i(x, y, 16, 16), CRYSTAL_FILL)
	var code := Sim.T_LIGHT
	if not _same(cx, cy - 1, code):
		img.fill_rect(Rect2i(x, y, 16, 1), CRYSTAL_EDGE)
		img.fill_rect(Rect2i(x + 1, y + 1, 14, 1), CRYSTAL_HI)
	if not _same(cx, cy + 1, code):
		img.fill_rect(Rect2i(x, y + 15, 16, 1), CRYSTAL_EDGE)
		img.fill_rect(Rect2i(x, y + 14, 16, 1), Color("8ccff5"))
	if not _same(cx - 1, cy, code):
		img.fill_rect(Rect2i(x, y, 1, 16), CRYSTAL_EDGE)
	if not _same(cx + 1, cy, code):
		img.fill_rect(Rect2i(x + 15, y, 1, 16), CRYSTAL_EDGE)
	# facet highlights
	for i in 4:
		img.set_pixel(x + 4 + i, y + 9 - i, CRYSTAL_HI)
	img.set_pixel(x + 11, y + 5, CRYSTAL_HI)
	img.fill_rect(Rect2i(x + 9, y + 10, 3, 2), Color("8ccff5"))


func _img_obsidian(img: Image, cx: int, cy: int) -> void:
	var x := cx * TS
	var y := cy * TS
	img.fill_rect(Rect2i(x, y, 16, 16), OBSIDIAN_FILL)
	var code := Sim.T_DARK
	if not _same(cx, cy - 1, code):
		img.fill_rect(Rect2i(x, y, 16, 1), OBSIDIAN_EDGE)
	if not _same(cx, cy + 1, code):
		img.fill_rect(Rect2i(x, y + 15, 16, 1), Color("7a0f30"))
	if not _same(cx - 1, cy, code):
		img.fill_rect(Rect2i(x, y, 1, 16), OBSIDIAN_EDGE)
	if not _same(cx + 1, cy, code):
		img.fill_rect(Rect2i(x + 15, y, 1, 16), OBSIDIAN_EDGE)
	var h := _hash(cx + 7, cy + 3)
	var vx := 3 + h % 8
	for i in 6:
		img.set_pixel(x + vx + (i % 2), y + 3 + i * 2, OBSIDIAN_VEIN)
	img.set_pixel(x + vx + 1, y + 4, Color("ff5577"))


func _img_ghost(img: Image, cx: int, cy: int, code: int, col: Color) -> void:
	var x := cx * TS
	var y := cy * TS
	img.fill_rect(Rect2i(x, y, 16, 16), Color(col.r, col.g, col.b, 0.07))
	var faint := Color(col.r, col.g, col.b, col.a)
	if not _same(cx, cy - 1, code):
		for i in range(0, 16, 2):
			img.set_pixel(x + i, y, faint)
	if not _same(cx, cy + 1, code):
		for i in range(0, 16, 2):
			img.set_pixel(x + i, y + 15, faint)
	if not _same(cx - 1, cy, code):
		for i in range(0, 16, 2):
			img.set_pixel(x, y + i, faint)
	if not _same(cx + 1, cy, code):
		for i in range(0, 16, 2):
			img.set_pixel(x + 15, y + i, faint)


func _img_spikes(img: Image, x: int, y: int, col: Color, tip: Color, ghost: bool) -> void:
	for s in 3:
		var cx := x + 3 + s * 5
		for k in 8:
			var wdt: int = SPIKE_W[k]
			var c := col
			if k == 0:
				c = tip
			if ghost:
				if k % 2 == 0:
					img.set_pixel(cx - wdt / 2, y + 8 + k, Color(col.r, col.g, col.b, 0.45))
					img.set_pixel(cx + wdt / 2, y + 8 + k, Color(col.r, col.g, col.b, 0.45))
			else:
				img.fill_rect(Rect2i(cx - wdt / 2, y + 8 + k, wdt, 1), c)
				if k > 1:
					img.set_pixel(cx - wdt / 2, y + 8 + k, c.darkened(0.3))
