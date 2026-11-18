class_name BossFight
extends RefCounted
## Boss behaviour for the arena stages. Owned and stepped by Sim.
##
## Boss projectiles belong to a world: LIGHT (0) and DARK (1) projectiles only
## hurt you while you are in that world, BOTH (2) always hurt. Shifting is how
## you dodge. Every boss tier adds attack patterns and gets faster; below half
## health the boss enters a second, angrier phase.

const LIGHT := 0
const DARK := 1
const BOTH := 2
const FLOOR_Y := 224.0
const LEFT_X := 16.0
const RIGHT_X := 464.0

var sim: Sim
var tier := 1
var x := 240.0
var y := -40.0
var w := 30.0
var h := 28.0
var hp := 30
var max_hp := 30
var phase := 1
var state := "intro"          # intro, idle, attack, dying, dead
var t := 0.0
var atk := ""
var atk_step := 0
var atk_t := 0.0
var atk_count := 0
var atk_world := 0
var cooldown := 1.0
var flash := 0.0
var telegraph := 0.0
var home_x := 240.0
var home_y := 72.0
var vx := 0.0
var vy := 0.0
var patterns: Array = []
var last_pattern := ""
var boom_t := 0.0

var bullets: Array = []       # {x, y, vx, vy, r, w, life}
var waves: Array = []         # {x, y, dir, speed}
var lasers: Array = []        # {y, h, w, t, warn, dur}
var orbs: Array = []          # {x, y, w, hp, life}


func setup(s: Sim, boss_tier: int) -> void:
	sim = s
	tier = boss_tier
	max_hp = 30 + 15 * (tier - 1)
	hp = max_hp
	w = minf(26.0 + tier * 2.0, 46.0)
	h = w * 0.9
	x = home_x
	y = -50.0
	phase = 1
	state = "intro"
	t = 0.0
	cooldown = 1.0
	flash = 0.0
	telegraph = 0.0
	vx = 0.0
	vy = 0.0
	last_pattern = ""
	bullets.clear()
	waves.clear()
	lasers.clear()
	orbs.clear()
	patterns = ["fan", "ring"]
	if tier >= 2: patterns.append("rain")
	if tier >= 3: patterns.append("slam")
	if tier >= 4: patterns.append("laser")
	if tier >= 5: patterns.append("dash")
	if tier >= 6: patterns.append("summon")


func rect() -> Rect2:
	return Rect2(x - w / 2.0, y - h / 2.0, w, h)


func vulnerable() -> bool:
	return state == "idle" or state == "attack"


func speed_mult() -> float:
	return 1.0 + (tier - 1) * 0.06 + (0.22 if phase == 2 else 0.0)


func bullet_speed() -> float:
	return (72.0 + tier * 7.0) * (1.15 if phase == 2 else 1.0)


func _pcx() -> float:
	return sim.px + Sim.PW / 2.0


func _pcy() -> float:
	return sim.py + Sim.PH / 2.0


# ------------------------------------------------------------------ step

func step(dt: float) -> void:
	t += dt
	flash = maxf(0.0, flash - dt * 6.0)
	match state:
		"intro":
			y = lerpf(y, home_y, minf(1.0, dt * 2.2))
			if t > 1.8:
				_set_state("idle")
				cooldown = 0.8
				sim._emit("boss_roar", x, y)
		"idle":
			_hover(dt)
			cooldown -= dt
			if cooldown <= 0.0:
				_start_attack()
		"attack":
			_run_attack(dt)
		"dying":
			y += sin(t * 30.0) * 0.6
			boom_t -= dt
			if boom_t <= 0.0:
				boom_t = 0.16
				sim._emit("boss_boom", x + randf_range(-w * 0.6, w * 0.6), y + randf_range(-h * 0.6, h * 0.6))
			if t > 2.6:
				_set_state("dead")
				sim._emit("boss_dead", x, y)
				sim.won = true
				sim._emit("win", x, y)
	_update_projectiles(dt)
	_check_player_bullets()
	if vulnerable() and rect().grow(-3).intersects(sim.hurt_rect()):
		sim.hurt(1, x)


func _set_state(s: String) -> void:
	state = s
	t = 0.0


func _hover(dt: float) -> void:
	var tx := home_x + sin(sim.time * 0.7 * speed_mult()) * 150.0
	var ty := home_y + sin(sim.time * 1.6) * 14.0
	x = lerpf(x, tx, minf(1.0, dt * 2.0))
	y = lerpf(y, ty, minf(1.0, dt * 2.0))
	telegraph = maxf(0.0, telegraph - dt * 3.0)


func _move_to(tx: float, ty: float, dt: float, rate: float = 4.0) -> bool:
	x = lerpf(x, tx, minf(1.0, dt * rate))
	y = lerpf(y, ty, minf(1.0, dt * rate))
	return absf(x - tx) < 3.0 and absf(y - ty) < 3.0


func _start_attack() -> void:
	var choices := patterns.duplicate()
	if choices.size() > 1:
		choices.erase(last_pattern)
	atk = choices[randi() % choices.size()]
	last_pattern = atk
	atk_step = 0
	atk_t = 0.0
	atk_count = 0
	atk_world = randi() % 2
	_set_state("attack")


func _end_attack() -> void:
	telegraph = 0.0
	_set_state("idle")
	var base := maxf(0.5, 1.6 - tier * 0.08)
	cooldown = base * (0.7 if phase == 2 else 1.0)


func _run_attack(dt: float) -> void:
	atk_t += dt
	match atk:
		"fan": _atk_fan(dt)
		"ring": _atk_ring(dt)
		"rain": _atk_rain(dt)
		"slam": _atk_slam(dt)
		"dash": _atk_dash(dt)
		"laser": _atk_laser(dt)
		"summon": _atk_summon(dt)


# --- patterns

func _atk_fan(dt: float) -> void:
	_hover(dt * 0.4)
	var volleys := 2 + tier / 3 + (1 if phase == 2 else 0)
	if atk_step == 0:
		telegraph = minf(1.0, atk_t / 0.45)
		if atk_t >= 0.45:
			atk_step = 1
			atk_t = 0.4
	elif atk_t >= 0.4:
		atk_t = 0.0
		var n := mini(3 + tier / 2, 9)
		var spread := deg_to_rad(40.0 + n * 5.0)
		var base := Vector2(_pcx() - x, _pcy() - y).angle()
		var world := (atk_world + atk_count) % 2
		for i in n:
			var a := base - spread / 2.0 + spread * (i / float(max(1, n - 1)))
			_bullet(x, y, a, bullet_speed(), 3.0, world)
		if tier >= 5:
			_bullet(x, y, base, bullet_speed() * 1.2, 3.0, BOTH)
		sim._emit("boss_fire", x, y)
		atk_count += 1
		telegraph = 0.0
		if atk_count >= volleys:
			_end_attack()


func _atk_ring(dt: float) -> void:
	_hover(dt * 0.3)
	var rings := 2 + (1 if phase == 2 else 0) + (1 if tier >= 7 else 0)
	if atk_step == 0:
		telegraph = minf(1.0, atk_t / 0.5)
		if atk_t >= 0.5:
			atk_step = 1
			atk_t = 0.6
	elif atk_t >= 0.6:
		atk_t = 0.0
		var n := mini(10 + int(tier * 1.5), 26)
		var off := atk_count * 0.5 + randf() * 0.3
		for i in n:
			var world := (atk_world + atk_count) % 2
			if tier >= 8 and i % 3 == 0:
				world = 1 - world
			_bullet(x, y, off + TAU * i / n, bullet_speed() * 0.8, 3.0, world)
		sim._emit("boss_fire", x, y)
		atk_count += 1
		telegraph = 0.0
		if atk_count >= rings:
			_end_attack()


func _atk_rain(dt: float) -> void:
	_move_to(240.0, 40.0, dt, 2.5)
	var dur := 2.2 + tier * 0.08
	var rate := maxf(0.05, 0.13 - tier * 0.005) * (0.75 if phase == 2 else 1.0)
	if atk_t < dur:
		telegraph = 0.6
		if atk_t >= (atk_count + 1) * rate:
			atk_count += 1
			var bx := randf_range(LEFT_X + 4.0, RIGHT_X - 4.0)
			var world := randi() % 2
			if tier >= 6 and randf() < 0.15:
				world = BOTH
			bullets.append({"x": bx, "y": 18.0, "vx": randf_range(-10.0, 10.0), "vy": bullet_speed() * 0.85, "r": 3.0, "w": world, "life": 4.0})
	else:
		_end_attack()


func _atk_slam(dt: float) -> void:
	var slams := 1 + (1 if phase == 2 else 0) + (1 if tier >= 9 else 0)
	match atk_step:
		0:  # line up above the player
			_move_to(clampf(_pcx(), 40.0, 440.0), 48.0, dt, 5.0)
			telegraph = minf(1.0, atk_t / 0.7)
			if atk_t > 0.7:
				atk_step = 1
				atk_t = 0.0
		1:  # tremble
			x += randf_range(-1.5, 1.5)
			if atk_t > 0.28:
				atk_step = 2
				atk_t = 0.0
				vy = 60.0
		2:  # fall
			vy += 1700.0 * dt
			y += vy * dt
			if y + h / 2.0 >= FLOOR_Y:
				y = FLOOR_Y - h / 2.0
				vy = 0.0
				sim._emit("slam", x, FLOOR_Y)
				var sp := (140.0 + tier * 9.0) * (1.15 if phase == 2 else 1.0)
				waves.append({"x": x - w / 2.0, "y": FLOOR_Y, "dir": -1, "speed": sp})
				waves.append({"x": x + w / 2.0, "y": FLOOR_Y, "dir": 1, "speed": sp})
				if tier >= 7:
					for i in 5:
						_bullet(x, y - h / 2.0, -PI / 2.0 + (i - 2) * 0.35, bullet_speed() * 0.9, 3.0, (atk_world + i) % 2)
				atk_step = 3
				atk_t = 0.0
				telegraph = 0.0
		3:  # recover
			if atk_t > 0.45:
				atk_count += 1
				if atk_count >= slams:
					atk_step = 4
				else:
					atk_step = 0
				atk_t = 0.0
		4:
			if _move_to(home_x, home_y, dt, 3.0) or atk_t > 1.2:
				_end_attack()


func _atk_dash(dt: float) -> void:
	match atk_step:
		0:
			var side := 1 if _pcx() < 240.0 else -1
			var tx := 240.0 + side * 205.0
			_move_to(tx, clampf(_pcy(), 150.0, FLOOR_Y - h / 2.0 - 2.0), dt, 4.0)
			if atk_t > 0.9:
				atk_step = 1
				atk_t = 0.0
				vx = -side * (300.0 + tier * 12.0)
		1:
			telegraph = 1.0 if fmod(atk_t * 10.0, 1.0) < 0.5 else 0.3
			if atk_t > 0.5:
				atk_step = 2
				atk_t = 0.0
				sim._emit("boss_dash", x, y)
		2:
			x += vx * dt
			telegraph = 0.0
			if x < 40.0 or x > 440.0:
				x = clampf(x, 40.0, 440.0)
				sim._emit("slam", x, y)
				if phase == 2 or tier >= 8:
					for i in 6:
						_bullet(x, y, TAU * i / 6.0, bullet_speed() * 0.7, 3.0, (atk_world + i) % 2)
				atk_step = 3
				atk_t = 0.0
		3:
			if _move_to(home_x, home_y, dt, 2.5) or atk_t > 1.4:
				_end_attack()


func _atk_laser(dt: float) -> void:
	_hover(dt * 0.3)
	if atk_step == 0:
		var n := 1 + (1 if phase == 2 else 0) + (1 if tier >= 8 else 0)
		var warn := maxf(0.55, 1.0 - tier * 0.04)
		for i in n:
			var ly := _pcy() if i == 0 else randf_range(40.0, FLOOR_Y - 10.0)
			lasers.append({"y": ly, "h": 10.0, "w": (atk_world + i) % 2, "t": 0.0, "warn": warn + i * 0.25, "dur": 0.6})
		sim._emit("laser_charge", x, y)
		atk_step = 1
	telegraph = 0.8
	if lasers.is_empty():
		_end_attack()


func _atk_summon(dt: float) -> void:
	_hover(dt * 0.5)
	if atk_step == 0:
		telegraph = minf(1.0, atk_t / 0.6)
		if atk_t > 0.6:
			var n := 2 + tier / 4 + (1 if phase == 2 else 0)
			for i in n:
				var a := TAU * i / n
				orbs.append({"x": x + cos(a) * 24.0, "y": y + sin(a) * 24.0, "w": i % 2, "hp": 2 + tier / 3, "life": 7.0})
			sim._emit("boss_summon", x, y)
			atk_step = 1
			atk_t = 0.0
	elif atk_t > 0.4:
		_end_attack()


func _bullet(bx: float, by: float, angle: float, speed: float, r: float, world: int) -> void:
	bullets.append({"x": bx, "y": by, "vx": cos(angle) * speed, "vy": sin(angle) * speed, "r": r, "w": world, "life": 6.0})


# ------------------------------------------------------------------ projectiles

func _hits_player(world: int) -> bool:
	return world == BOTH or world == sim.world


func _update_projectiles(dt: float) -> void:
	var hurt := sim.hurt_rect()
	var keep := []
	for b in bullets:
		b["x"] += b["vx"] * dt
		b["y"] += b["vy"] * dt
		b["life"] -= dt
		if b["life"] <= 0.0 or b["x"] < 0.0 or b["x"] > 480.0 or b["y"] < -10.0 or b["y"] > FLOOR_Y + 2.0:
			if b["y"] > FLOOR_Y:
				sim._emit("bolt_fizzle", b["x"], FLOOR_Y - 2.0)
			continue
		if _hits_player(b["w"]) and _circle_rect(b["x"], b["y"], b["r"], hurt):
			sim.hurt(1, b["x"])
			sim._emit("bolt_fizzle", b["x"], b["y"])
			continue
		keep.append(b)
	bullets = keep

	var wk := []
	for wv in waves:
		wv["x"] += wv["dir"] * wv["speed"] * dt
		if wv["x"] < LEFT_X or wv["x"] > RIGHT_X:
			continue
		if Rect2(wv["x"] - 5.0, FLOOR_Y - 11.0, 10.0, 11.0).intersects(hurt):
			sim.hurt(1, wv["x"] - wv["dir"] * 10.0)
		wk.append(wv)
	waves = wk

	var lk := []
	for l in lasers:
		l["t"] += dt
		if l["t"] >= l["warn"] and l["t"] - dt < l["warn"]:
			sim._emit("laser_fire", 240.0, l["y"])
		if l["t"] >= l["warn"]:
			if l["t"] >= l["warn"] + l["dur"]:
				continue
			if _hits_player(l["w"]) and Rect2(0, l["y"] - l["h"] / 2.0, 480, l["h"]).intersects(hurt):
				sim.hurt(1, sim.px + 5.0 - sim.facing * 4.0)
		lk.append(l)
	lasers = lk

	var ok := []
	var pc := Vector2(_pcx(), _pcy())
	for o in orbs:
		o["life"] -= dt
		if o["life"] <= 0.0:
			sim._emit("bolt_fizzle", o["x"], o["y"])
			continue
		var p := Vector2(o["x"], o["y"])
		var hunting: bool = o["w"] == sim.world
		var spd := (34.0 + tier * 2.5) if hunting else 10.0
		var tgt := pc if hunting else Vector2(x, y)
		var d := p.distance_to(tgt)
		if d > 0.5:
			p += (tgt - p) / d * minf(d, spd * dt)
		o["x"] = p.x
		o["y"] = p.y
		if hunting and p.distance_to(pc) < 9.0:
			sim.hurt(1, p.x)
			sim._emit("bolt_fizzle", p.x, p.y)
			continue
		ok.append(o)
	orbs = ok


func _circle_rect(cx: float, cy: float, r: float, rr: Rect2) -> bool:
	var nx := clampf(cx, rr.position.x, rr.end.x)
	var ny := clampf(cy, rr.position.y, rr.end.y)
	return Vector2(cx - nx, cy - ny).length_squared() < r * r


func _check_player_bullets() -> void:
	var keep := []
	var r := rect()
	for b in sim.pbullets:
		var hit := false
		for o in orbs:
			if Vector2(o["x"], o["y"]).distance_to(Vector2(b["x"], b["y"])) < 6.0 + b["r"]:
				o["hp"] -= b["dmg"]
				hit = true
				sim._emit("orb_hit", o["x"], o["y"])
				if o["hp"] <= 0:
					o["life"] = 0.0
					sim._emit("orb_pop", o["x"], o["y"])
				break
		if not hit and vulnerable() and not b.get("hit_boss", false) and _circle_rect(b["x"], b["y"], b["r"], r):
			hit = true
			b["hit_boss"] = true
			_damage(b["dmg"], b["x"], b["y"])
		if hit and not b["pierce"]:
			continue
		keep.append(b)
	sim.pbullets = keep


func _damage(dmg: int, bx: float, by: float) -> void:
	hp = maxi(0, hp - dmg)
	flash = 1.0
	sim._emit("boss_hit", bx, by)
	if phase == 1 and hp <= max_hp / 2:
		phase = 2
		sim._emit("boss_phase", x, y)
	if hp <= 0:
		bullets.clear()
		lasers.clear()
		orbs.clear()
		waves.clear()
		boom_t = 0.0
		_set_state("dying")
		sim._emit("boss_die", x, y)
