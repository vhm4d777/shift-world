class_name Sim
extends RefCounted
## Deterministic game simulation for SHIFT WORLDS.
## Holds a level's state and advances it in fixed 1/60 s steps.
## Rendering, audio and input live elsewhere; this class only reports events.

const TS := 16
const COLS := 30
const ROWS := 17
const LIGHT := 0
const DARK := 1

# Player tuning (pixels / seconds)
const PW := 10
const PH := 14
const RUN := 105.0
const ACC_GROUND := 1150.0
const DEC_GROUND := 1500.0
const ACC_AIR := 850.0
const DEC_AIR := 550.0
const JUMP_V := 345.0
const JUMP_CUT := -120.0
const GRAVITY := 1000.0
const APEX_GRAVITY_MULT := 0.6
const MAX_FALL := 330.0
const COYOTE := 0.09
const BUFFER := 0.12

const MOVER_SPEED := 42.0
const LIFT_SPEED := 36.0
const WALKER_SPEED := 32.0
const WALKER_W := 14
const WALKER_H := 16
const WISP_SPEED := 40.0
const WISP_HOME_SPEED := 22.0
const WISP_RANGE := 120.0
const TURRET_PERIOD := 1.9
const BOLT_SPEED := 115.0
const CRUMBLE_TIME := 0.45
const CRUMBLE_RESPAWN := 3.0

# Tile codes (ASCII)
const T_EMPTY := 46   # .
const T_STONE := 35   # #
const T_LIGHT := 76   # L
const T_DARK := 68    # D
const T_SPIKE := 94   # ^
const T_LSPIKE := 108 # l
const T_DSPIKE := 100 # d
const T_GATE := 71    # G
const T_OGATE := 79   # O
const T_CRUMBLE := 66 # B
const T_STOP := 58    # :

var level_index := 0
var level_name := ""
var grid := PackedByteArray()

var world := LIGHT
var gates_flipped := false
var time := 0.0
var shifts := 0
var won := false
var dead := false

# Player
var px := 0.0
var py := 0.0
var vx := 0.0
var vy := 0.0
var on_ground := false
var coyote := 0.0
var jump_buffer := 0.0
var jump_held := false
var facing := 1
var cp_x := 0.0
var cp_y := 0.0
var cp_world := LIGHT

# Entities
var crumble_cells := {}            # cell index -> crumble index
var crumble_state := PackedInt32Array()   # 0 intact, 1 cracking, 2 broken
var crumble_timer := PackedFloat32Array()
var crumble_pos: Array[Vector2i] = []
var levers: Array[Rect2] = []
var lever_inside: Array[bool] = []
var checkpoints: Array[Rect2] = []
var checkpoint_active := -1
var shard_rect := Rect2()
var has_shard := false
var shard_taken := false
var exit_rect := Rect2()
var signs: Array = []              # [{rect, text, cell}]
var movers: Array = []             # [{x,y,w,h,axis,dir,speed,dx,dy}]
var walkers: Array = []            # [{x,y,dir,x0,y0,dir0}]
var wisps: Array = []              # [{x,y,hx,hy}]
var turrets: Array = []            # [{cx,cy,dir,t}]
var bolts: Array = []              # [{x,y,vx}]

var events: Array = []             # [[name, x, y], ...] produced by the last step
var solver_mode := false           # lighter bookkeeping for automated tests


func load_level(i: int) -> void:
	level_index = i
	var data: Dictionary = Levels.get_level(i)
	level_name = data["name"]
	var rows: Array = data["map"]
	var sign_texts: Array = data.get("signs", [])
	grid = PackedByteArray()
	grid.resize(COLS * ROWS)
	crumble_cells.clear()
	crumble_pos.clear()
	levers.clear()
	lever_inside.clear()
	checkpoints.clear()
	signs.clear()
	movers.clear()
	walkers.clear()
	wisps.clear()
	turrets.clear()
	bolts.clear()
	has_shard = false
	shard_taken = false
	var sign_i := 0
	for cy in ROWS:
		var row: String = rows[cy]
		assert(row.length() == COLS, "Level %d row %d has length %d" % [i, cy, row.length()])
		for cx in COLS:
			var ch := row.unicode_at(cx)
			var code := T_EMPTY
			var x := cx * TS
			var y := cy * TS
			match char(ch):
				"#", "L", "D", "^", "l", "d", "G", "O", ":":
					code = ch
				"B":
					code = T_CRUMBLE
					crumble_cells[cy * COLS + cx] = crumble_pos.size()
					crumble_pos.append(Vector2i(cx, cy))
				"P":
					cp_x = x + (TS - PW) / 2.0
					cp_y = y + TS - PH
				"E":
					exit_rect = Rect2(x + 2, y - 14, 12, 30)
				"C":
					checkpoints.append(Rect2(x + 3, y, 10, 16))
				"*":
					has_shard = true
					shard_rect = Rect2(x + 3, y + 3, 10, 10)
				"S":
					levers.append(Rect2(x + 2, y + 4, 12, 12))
					lever_inside.append(false)
				"?":
					var t: String = sign_texts[sign_i] if sign_i < sign_texts.size() else ""
					sign_i += 1
					signs.append({"rect": Rect2(x - 20, y - 24, 56, 40), "text": t, "cell": Vector2i(cx, cy)})
				"w", "W":
					var d0 := 1 if ch == 119 else -1
					walkers.append({"x": float(x + 1), "y": float(y + TS - WALKER_H), "dir": d0, "x0": float(x + 1), "y0": float(y + TS - WALKER_H), "dir0": d0})
				"f":
					wisps.append({"x": float(x + 8), "y": float(y + 8), "hx": float(x + 8), "hy": float(y + 8)})
				"t", "T":
					code = T_STONE
					turrets.append({"cx": cx, "cy": cy, "dir": (-1 if ch == 116 else 1), "t": 0.0})
				"h":
					if cx == 0 or row.unicode_at(cx - 1) != 104:
						var n := 0
						while cx + n < COLS and row.unicode_at(cx + n) == 104:
							n += 1
						movers.append({"x": float(x), "y": float(y), "w": n * TS, "h": 8, "axis": 0, "dir": 1, "speed": MOVER_SPEED, "dx": 0.0, "dy": 0.0, "x0": float(x), "y0": float(y)})
				"v":
					if cx == 0 or row.unicode_at(cx - 1) != 118:
						var n := 0
						while cx + n < COLS and row.unicode_at(cx + n) == 118:
							n += 1
						movers.append({"x": float(x), "y": float(y), "w": n * TS, "h": 8, "axis": 1, "dir": -1, "speed": LIFT_SPEED, "dx": 0.0, "dy": 0.0, "x0": float(x), "y0": float(y)})
			grid[cy * COLS + cx] = code
	crumble_state = PackedInt32Array()
	crumble_state.resize(crumble_pos.size())
	crumble_timer = PackedFloat32Array()
	crumble_timer.resize(crumble_pos.size())
	world = LIGHT
	cp_world = LIGHT
	gates_flipped = false
	checkpoint_active = -1
	time = 0.0
	shifts = 0
	won = false
	respawn()
	events.clear()


func respawn() -> void:
	px = cp_x
	py = cp_y
	vx = 0.0
	vy = 0.0
	world = cp_world
	dead = false
	on_ground = false
	coyote = 0.0
	jump_buffer = 0.0
	jump_held = false
	bolts.clear()
	for w in walkers:
		w["x"] = w["x0"]
		w["y"] = w["y0"]
		w["dir"] = w["dir0"]
	for f in wisps:
		f["x"] = f["hx"]
		f["y"] = f["hy"]
	for t in turrets:
		t["t"] = 0.0
	for i in crumble_state.size():
		crumble_state[i] = 0
		crumble_timer[i] = 0.0
	for i in lever_inside.size():
		lever_inside[i] = levers[i].intersects(Rect2(px, py, PW, PH))


# ---------------------------------------------------------------- tiles

func tile(cx: int, cy: int) -> int:
	if cx < 0 or cx >= COLS or cy < 0:
		return T_STONE
	if cy >= ROWS:
		return T_EMPTY
	return grid[cy * COLS + cx]


func tile_solid_at(cx: int, cy: int, w: int) -> bool:
	var c := tile(cx, cy)
	match c:
		T_STONE:
			return true
		T_LIGHT:
			return w == LIGHT
		T_DARK:
			return w == DARK
		T_GATE:
			return not gates_flipped
		T_OGATE:
			return gates_flipped
		T_CRUMBLE:
			return crumble_state[crumble_cells[cy * COLS + cx]] != 2
	return false


func blocks_mover(cx: int, cy: int) -> bool:
	var c := tile(cx, cy)
	if c == T_STOP or c == T_STONE or c == T_LIGHT or c == T_DARK:
		return true
	if c == T_GATE:
		return not gates_flipped
	if c == T_OGATE:
		return gates_flipped
	return false


## Returns every solid rectangle overlapping the given box in world `w`.
func solids_in(x: float, y: float, bw: float, bh: float, w: int) -> Array:
	var out := []
	var x0 := int(floor(x / TS))
	var x1 := int(floor((x + bw - 0.001) / TS))
	var y0 := int(floor(y / TS))
	var y1 := int(floor((y + bh - 0.001) / TS))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if tile_solid_at(cx, cy, w):
				out.append(Rect2(cx * TS, cy * TS, TS, TS))
	var box := Rect2(x, y, bw, bh)
	for m in movers:
		var r := Rect2(m["x"], m["y"], m["w"], m["h"])
		if r.intersects(box):
			out.append(r)
	if w == LIGHT:
		for wk in walkers:
			var r := Rect2(wk["x"], wk["y"], WALKER_W, WALKER_H)
			if r.intersects(box):
				out.append(r)
	return out


func can_occupy(x: float, y: float, w: int) -> bool:
	return solids_in(x, y, PW, PH, w).is_empty()


# ---------------------------------------------------------------- step

## input: {left, right, jump_pressed, jump_held, shift_pressed}
func step(input: Dictionary, dt: float = 1.0 / 60.0) -> void:
	events.clear()
	if won or dead:
		return
	time += dt

	# 1. Dimension shift
	if input.get("shift_pressed", false):
		var target := 1 - world
		if can_occupy(px, py, target):
			world = target
			shifts += 1
			_emit("shift", px + PW / 2.0, py + PH / 2.0)
			if world == LIGHT:
				for b in bolts:
					_emit("bolt_fizzle", b["x"], b["y"])
				bolts.clear()
		else:
			_emit("shift_blocked", px + PW / 2.0, py + PH / 2.0)

	# 2. Moving platforms (only run in the Light World)
	_update_movers(dt)
	if dead:
		return

	# 3. Horizontal control
	var dir := 0
	if input.get("left", false):
		dir -= 1
	if input.get("right", false):
		dir += 1
	if dir != 0:
		facing = dir
	var target_vx := dir * RUN
	var accel: float
	if on_ground:
		accel = ACC_GROUND if dir != 0 else DEC_GROUND
	else:
		accel = ACC_AIR if dir != 0 else DEC_AIR
	vx = move_toward(vx, target_vx, accel * dt)

	# 4. Jump with coyote time and buffering
	if input.get("jump_pressed", false):
		jump_buffer = BUFFER
	else:
		jump_buffer = max(0.0, jump_buffer - dt)
	jump_held = input.get("jump_held", false)
	if on_ground:
		coyote = COYOTE
	else:
		coyote = max(0.0, coyote - dt)
	if jump_buffer > 0.0 and coyote > 0.0:
		vy = -JUMP_V
		jump_buffer = 0.0
		coyote = 0.0
		on_ground = false
		_emit("jump", px + PW / 2.0, py + PH)
	if not jump_held and vy < JUMP_CUT:
		vy = JUMP_CUT

	# 5. Gravity
	var g := GRAVITY
	if jump_held and abs(vy) < 45.0:
		g *= APEX_GRAVITY_MULT
	vy = min(vy + g * dt, MAX_FALL)

	# 6. Move and collide
	_move_x(vx * dt)
	var was_ground := on_ground
	var fall_speed := vy
	on_ground = false
	_move_y(vy * dt)
	if on_ground and not was_ground and fall_speed > 120.0:
		_emit("land", px + PW / 2.0, py + PH)

	# 7. World interactions
	_update_crumbles(dt)
	_update_enemies(dt)
	_check_triggers()
	_check_hazards()
	if py > ROWS * TS + 8:
		_die()


func _emit(name: String, x: float, y: float) -> void:
	events.append([name, x, y])


func _move_x(amount: float) -> void:
	if amount == 0.0:
		return
	px += amount
	var hits := solids_in(px, py, PW, PH, world)
	if hits.is_empty():
		return
	if amount > 0.0:
		var edge := INF
		for r in hits:
			edge = min(edge, r.position.x)
		px = edge - PW
	else:
		var edge := -INF
		for r in hits:
			edge = max(edge, r.end.x)
		px = edge
	vx = 0.0


func _move_y(amount: float) -> void:
	if amount == 0.0:
		return
	py += amount
	var hits := solids_in(px, py, PW, PH, world)
	if hits.is_empty():
		return
	if amount > 0.0:
		var edge := INF
		for r in hits:
			edge = min(edge, r.position.y)
		py = edge - PH
		on_ground = true
	else:
		var edge := -INF
		for r in hits:
			edge = max(edge, r.end.y)
		py = edge
	vy = 0.0


func _update_movers(dt: float) -> void:
	for m in movers:
		m["dx"] = 0.0
		m["dy"] = 0.0
	if world != LIGHT:
		return
	for m in movers:
		var mx: float = m["x"]
		var my: float = m["y"]
		var mw: int = m["w"]
		var mh: int = m["h"]
		var riding: bool = on_ground and abs((py + PH) - my) < 0.6 and px + PW > mx and px < mx + mw
		var delta: float = m["speed"] * dt * m["dir"]
		var nx := mx
		var ny := my
		if m["axis"] == 0:
			nx += delta
		else:
			ny += delta
		if _mover_blocked(nx, ny, mw, mh):
			m["dir"] = -m["dir"]
			continue
		m["x"] = nx
		m["y"] = ny
		m["dx"] = nx - mx
		m["dy"] = ny - my
		var box := Rect2(nx, ny, mw, mh)
		if riding:
			if m["dx"] != 0.0:
				_move_x_carried(m["dx"])
			if m["dy"] < 0.0:
				py = ny - PH
				if not solids_in_static(px, py, PW, PH).is_empty():
					_die()
					return
			elif m["dy"] > 0.0:
				py = ny - PH
		elif box.intersects(Rect2(px, py, PW, PH)):
			# Pushed by a platform that is not carrying the player.
			if m["axis"] == 0:
				px = nx + mw if m["dx"] > 0.0 else nx - PW
			elif m["dy"] < 0.0:
				py = ny - PH
				on_ground = true
				vy = 0.0
			else:
				py = ny + mh
				vy = max(vy, 0.0)
			if not solids_in_static(px, py, PW, PH).is_empty():
				_die()
				return


func _move_x_carried(amount: float) -> void:
	px += amount
	var hits := solids_in_static(px, py, PW, PH)
	if hits.is_empty():
		return
	if amount > 0.0:
		var edge := INF
		for r in hits:
			edge = min(edge, r.position.x)
		px = edge - PW
	else:
		var edge := -INF
		for r in hits:
			edge = max(edge, r.end.x)
		px = edge


## Solids excluding moving platforms (used while being carried).
func solids_in_static(x: float, y: float, bw: float, bh: float) -> Array:
	var out := []
	var x0 := int(floor(x / TS))
	var x1 := int(floor((x + bw - 0.001) / TS))
	var y0 := int(floor(y / TS))
	var y1 := int(floor((y + bh - 0.001) / TS))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if tile_solid_at(cx, cy, world):
				out.append(Rect2(cx * TS, cy * TS, TS, TS))
	return out


func _mover_blocked(x: float, y: float, w: int, h: int) -> bool:
	var x0 := int(floor(x / TS))
	var x1 := int(floor((x + w - 0.001) / TS))
	var y0 := int(floor(y / TS))
	var y1 := int(floor((y + h - 0.001) / TS))
	if y0 < 0 or y1 >= ROWS:
		return true
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			if blocks_mover(cx, cy):
				return true
	return false


func _update_crumbles(dt: float) -> void:
	if on_ground:
		var cy := int(floor((py + PH + 1) / TS))
		var x0 := int(floor(px / TS))
		var x1 := int(floor((px + PW - 0.001) / TS))
		for cx in range(x0, x1 + 1):
			var key := cy * COLS + cx
			if crumble_cells.has(key):
				var k: int = crumble_cells[key]
				if crumble_state[k] == 0:
					crumble_state[k] = 1
					crumble_timer[k] = 0.0
					_emit("crack", cx * TS + 8, cy * TS + 4)
	var player := Rect2(px, py, PW, PH)
	for k in crumble_state.size():
		var s := crumble_state[k]
		if s == 1:
			crumble_timer[k] += dt
			if crumble_timer[k] >= CRUMBLE_TIME:
				crumble_state[k] = 2
				crumble_timer[k] = 0.0
				_emit("crumble", crumble_pos[k].x * TS + 8, crumble_pos[k].y * TS + 8)
		elif s == 2:
			crumble_timer[k] += dt
			if crumble_timer[k] >= CRUMBLE_RESPAWN:
				var r := Rect2(crumble_pos[k].x * TS, crumble_pos[k].y * TS, TS, TS)
				if not r.intersects(player):
					crumble_state[k] = 0
					crumble_timer[k] = 0.0


func _update_enemies(dt: float) -> void:
	var pcx := px + PW / 2.0
	var pcy := py + PH / 2.0
	var hurt := Rect2(px + 1, py + 1, PW - 2, PH - 1)
	# Wardens patrol in the Dark World and freeze into crystal in the Light World.
	if world == DARK:
		for w in walkers:
			var nx: float = w["x"] + w["dir"] * WALKER_SPEED * dt
			var y: float = w["y"]
			var front: float = nx + WALKER_W if w["dir"] > 0 else nx
			var fcx := int(floor((front - (0.001 if w["dir"] > 0 else 0.0)) / TS))
			var wall := false
			for cy in range(int(floor(y / TS)), int(floor((y + WALKER_H - 0.001) / TS)) + 1):
				if tile_solid_at(fcx, cy, DARK):
					wall = true
			var floor_cy := int(floor((y + WALKER_H + 1) / TS))
			var ground := tile_solid_at(fcx, floor_cy, DARK)
			if wall or not ground:
				w["dir"] = -w["dir"]
			else:
				w["x"] = nx
			var r := Rect2(w["x"], w["y"] - 1, WALKER_W, WALKER_H + 1)
			if r.intersects(hurt):
				_die()
				return
	# Wisps hunt in the Dark World and drift home in the Light World.
	for f in wisps:
		var fx: float = f["x"]
		var fy: float = f["y"]
		var tx: float = f["hx"]
		var ty: float = f["hy"]
		var spd := WISP_HOME_SPEED
		if world == DARK and Vector2(pcx - fx, pcy - fy).length() < WISP_RANGE:
			tx = pcx
			ty = pcy
			spd = WISP_SPEED
		var to := Vector2(tx - fx, ty - fy)
		var d := to.length()
		if d > 0.5:
			var stepv: Vector2 = to / d * min(d, spd * dt)
			f["x"] = fx + stepv.x
			f["y"] = fy + stepv.y
		if world == DARK and Vector2(pcx - f["x"], pcy - f["y"]).length() < 9.0:
			_die()
			return
	# Sentinels fire bolts only in the Dark World.
	if world == DARK:
		for t in turrets:
			t["t"] += dt
			if t["t"] >= TURRET_PERIOD:
				t["t"] = 0.0
				var bx: float = t["cx"] * TS + (TS + 1 if t["dir"] > 0 else -7)
				var by: float = t["cy"] * TS + 6
				bolts.append({"x": bx, "y": by, "vx": BOLT_SPEED * t["dir"]})
				_emit("bolt_fire", bx, by + 2)
		var keep := []
		for b in bolts:
			b["x"] += b["vx"] * dt
			var cx := int(floor((b["x"] + 3) / TS))
			var cy := int(floor((b["y"] + 2) / TS))
			if b["x"] < -8 or b["x"] > COLS * TS + 8 or tile_solid_at(cx, cy, DARK):
				_emit("bolt_fizzle", b["x"], b["y"])
				continue
			if Rect2(b["x"], b["y"], 6, 4).intersects(hurt):
				_die()
				return
			keep.append(b)
		bolts = keep


func _check_triggers() -> void:
	var p := Rect2(px, py, PW, PH)
	for i in levers.size():
		var inside := levers[i].intersects(p)
		if inside and not lever_inside[i]:
			gates_flipped = not gates_flipped
			_emit("lever", levers[i].get_center().x, levers[i].get_center().y)
		lever_inside[i] = inside
	for i in checkpoints.size():
		if i != checkpoint_active and checkpoints[i].intersects(p) and on_ground:
			checkpoint_active = i
			cp_x = checkpoints[i].position.x + 5 - PW / 2.0
			cp_y = checkpoints[i].end.y - PH
			cp_world = world
			_emit("checkpoint", checkpoints[i].get_center().x, checkpoints[i].position.y)
	if has_shard and not shard_taken and shard_rect.intersects(p):
		shard_taken = true
		_emit("shard", shard_rect.get_center().x, shard_rect.get_center().y)
	if exit_rect.intersects(p):
		won = true
		_emit("win", exit_rect.get_center().x, exit_rect.get_center().y)


func _check_hazards() -> void:
	if won:
		return
	var hurt := Rect2(px + 1, py + 1, PW - 2, PH - 1)
	var x0 := int(floor(hurt.position.x / TS))
	var x1 := int(floor(hurt.end.x / TS))
	var y0 := int(floor(hurt.position.y / TS))
	var y1 := int(floor(hurt.end.y / TS))
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var c := tile(cx, cy)
			var active := c == T_SPIKE or (c == T_LSPIKE and world == LIGHT) or (c == T_DSPIKE and world == DARK)
			if active and Rect2(cx * TS + 2, cy * TS + 7, 12, 9).intersects(hurt):
				_die()
				return


func _die() -> void:
	if dead:
		return
	dead = true
	_emit("die", px + PW / 2.0, py + PH / 2.0)


# ---------------------------------------------------------------- solver support

func snapshot() -> Array:
	return [px, py, vx, vy, on_ground, coyote, jump_buffer, jump_held, world, gates_flipped,
		crumble_state.duplicate(), crumble_timer.duplicate(), movers.duplicate(true),
		walkers.duplicate(true), wisps.duplicate(true), turrets.duplicate(true), bolts.duplicate(true),
		lever_inside.duplicate(), shard_taken, won, dead, time, facing]


func restore(s: Array) -> void:
	px = s[0]; py = s[1]; vx = s[2]; vy = s[3]; on_ground = s[4]; coyote = s[5]
	jump_buffer = s[6]; jump_held = s[7]; world = s[8]; gates_flipped = s[9]
	crumble_state = s[10].duplicate(); crumble_timer = s[11].duplicate()
	movers = s[12].duplicate(true); walkers = s[13].duplicate(true); wisps = s[14].duplicate(true)
	turrets = s[15].duplicate(true); bolts = s[16].duplicate(true)
	lever_inside = s[17].duplicate(); shard_taken = s[18]; won = s[19]; dead = s[20]; time = s[21]
	facing = s[22]
