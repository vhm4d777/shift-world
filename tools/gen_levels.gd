extends SceneTree
## Procedural level generator for SHIFT WORLDS levels 11-110.
##
## Every candidate map is verified with the real simulation and the solver
## (tests/solver.gd); only maps with a found route to the exit are kept. Tokens
## are placed on cells the solver's route passes through, so every token is
## reachable. Difficulty rises with the level number.
##
## godot --headless -s res://tools/gen_levels.gd -- gen <first> <last>   (normal level numbers, 11..110)
## godot --headless -s res://tools/gen_levels.gd -- orig                 (tokens for levels 1-10)
## godot --headless -s res://tools/gen_levels.gd -- assemble             (writes scripts/levels_gen.gd)

const COLS := 30
const ROWS := 17
const CACHE := "res://tools/gen_cache"

const WORDS := [
	[],
	[["Prism", "Geode", "Quartz", "Glimmer", "Facet", "Lumen", "Opal", "Shard", "Gleam", "Mirror"], ["Hollow", "Steps", "Grotto", "Vein", "Drop", "Maze", "Ledges", "Cavern", "Tunnel", "Spires"]],
	[["Neon", "Chrome", "Pixel", "Static", "Signal", "Laser", "Voltage", "Circuit", "Hologram", "Synth"], ["Alley", "Rooftops", "Avenue", "Tower", "District", "Overpass", "Plaza", "Arcade", "Skyline", "Underpass"]],
	[["Mossy", "Whisper", "Fern", "Thorn", "Bramble", "Willow", "Hollow", "Ancient", "Root", "Firefly"], ["Glade", "Canopy", "Thicket", "Trail", "Grove", "Clearing", "Branches", "Path", "Ring", "Wilds"]],
	[["Sunken", "Tidal", "Coral", "Drowned", "Pearl", "Abyssal", "Salt", "Kelp", "Echoing", "Lost"], ["Halls", "Arches", "Vault", "Pillars", "Temple", "Steps", "Reef", "Atrium", "Crypt", "Gate"]],
	[["Ember", "Ashen", "Molten", "Cinder", "Scorched", "Blazing", "Smoke", "Magma", "Burning", "Sulfur"], ["Dunes", "Crater", "Flats", "Vents", "Ridge", "Basin", "Fissure", "Wastes", "Forge", "Rift"]],
	[["Frozen", "Glacial", "Frost", "Rime", "Hail", "Snowy", "Icicle", "Polar", "Winter", "Pale"], ["Peaks", "Pass", "Cliffs", "Ascent", "Summit", "Crevasse", "Slopes", "Shelf", "Spire", "Drift"]],
	[["Thunder", "Storm", "Gale", "Static", "Tempest", "Lightning", "Howling", "Cloud", "Squall", "Rumbling"], ["Spire", "Stair", "Bridge", "Eye", "Balcony", "Crown", "Ladder", "Bastion", "Climb", "Heights"]],
	[["Star", "Comet", "Nebula", "Lunar", "Orbit", "Cosmic", "Astral", "Solar", "Meteor", "Zenith"], ["Garden", "Drift", "Bloom", "Field", "Path", "Halo", "Belt", "Orchard", "Ring", "Trail"]],
	[["Cog", "Gear", "Brass", "Piston", "Spring", "Ticking", "Rusty", "Steam", "Pendulum", "Rivet"], ["Works", "Chamber", "Shaft", "Engine", "Mill", "Gallery", "Assembly", "Clock", "Press", "Depths"]],
	[["Void", "Null", "Final", "Endless", "Silent", "Hollow", "Last", "Abyss", "Fading", "Eternal"], ["Heart", "Edge", "Threshold", "Descent", "Fracture", "Pulse", "Core", "Breach", "Horizon", "Echo"]],
]

var solver := Solver.new()
var rng := RandomNumberGenerator.new()
var g: Array = []          # grid of single-character strings
var reserved := {}         # cells that must stay empty (headroom above platforms)
var plats: Array = []      # [{x0, x1, r, kind}]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(CACHE)
	if args.is_empty():
		print("usage: gen <first> <last> | orig | assemble")
		quit(1)
		return
	match args[0]:
		"gen":
			var first := int(args[1])
			var last := int(args[2])
			for n in range(first, last + 1):
				if FileAccess.file_exists(CACHE + "/level_%03d.json" % n):
					print("level %d cached" % n)
					continue
				generate(n)
		"orig":
			original_tokens()
		"assemble":
			assemble()
	quit(0)


# ------------------------------------------------------------------ generation

func difficulty(n: int) -> float:
	return clampf((n - 11) / 99.0, 0.0, 1.0)


func generate(n: int) -> void:
	var d := difficulty(n)
	var t0 := Time.get_ticks_msec()
	var sim := Sim.new()
	for attempt in 1500:
		rng.seed = hash(n * 7919 + attempt * 104729 + 17)
		var data := build(n, d)
		if data.is_empty():
			continue
		sim.load_data(data, 0)
		var r := solve_route(sim)
		if r[0] == null:
			print("  level %d attempt %d: unsolved (%d nodes)" % [n, attempt, r[1]])
			if OS.get_environment("GEN_DEBUG") == "1":
				print("
".join(PackedStringArray(data["map"])))
			continue
		var path: Array = r[2]
		var shifts := 0
		var frames := 0
		for st in path:
			if solver.actions[int(st[0])][2]:
				shifts += 1
			frames += int(st[1])
		var need_shifts := 0 if d < 0.08 else 1 + int(d * 4.0)
		if shifts < need_shifts or frames < 140 + int(d * 140):
			print("  level %d attempt %d: too easy (shifts %d, frames %d)" % [n, attempt, shifts, frames])
			continue
		data["tokens"] = place_tokens(data, path, 3 + int(d * 3.0) + rng.randi_range(0, 1))
		data["path"] = path
		var f := FileAccess.open(CACHE + "/level_%03d.json" % n, FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		print("level %d '%s' ok: attempt %d, nodes %d, shifts %d, frames %d, %.1fs" % [n, data["name"], attempt, r[1], shifts, frames, (Time.get_ticks_msec() - t0) / 1000.0])
		return
	print("LEVEL %d FAILED" % n)


## Solves the level one platform at a time (the generator knows the intended
## route), then the exit. Returns [final snapshot or null, nodes, path].
func solve_route(sim: Sim) -> Array:
	var snap := sim.snapshot()
	var path := []
	var nodes := 0
	var goals := []
	for i in range(1, plats.size() - 1):
		var p: Dictionary = plats[i]
		goals.append([p["x0"] * 16, (p["r"] - 1) * 16, (p["x1"] - p["x0"] + 1) * 16, 16])
	goals.append("exit")
	for goal in goals:
		solver.limit = 5000
		var r := solver.search(sim, snap, goal)
		nodes += r[1]
		if r[0] == null:
			return [null, nodes, []]
		snap = r[0]
		path.append_array(r[2])
	return [snap, nodes, path]


func setc(x: int, y: int, ch: String) -> void:
	if x >= 0 and x < COLS and y >= 0 and y < ROWS:
		g[y][x] = ch


func getc(x: int, y: int) -> String:
	if x < 0 or x >= COLS or y < 0 or y >= ROWS:
		return "#"
	return g[y][x]


func area_free(x0: int, x1: int, r: int) -> bool:
	# platform cells and four cells of headroom must be empty and unreserved
	for x in range(x0 - 1, x1 + 2):
		for y in range(r - 4, r + 1):
			if x < 1 or x > COLS - 2 or y < 1:
				return false
			if getc(x, y) != ".":
				if x >= x0 and x <= x1:
					return false
				if y < r:
					return false
			if reserved.has(Vector2i(x, y)) and x >= x0 and x <= x1:
				return false
	return true


func place_platform(x0: int, x1: int, r: int, kind: String) -> void:
	for x in range(x0, x1 + 1):
		setc(x, r, kind)
		for y in range(r - 4, r):
			reserved[Vector2i(x, y)] = true
	# keep the jump arc from the previous platform clear
	if not plats.is_empty():
		var prev: Dictionary = plats[plats.size() - 1]
		var cx0: int
		var cx1: int
		if x0 > prev["x1"]:
			cx0 = prev["x1"]
			cx1 = x0
		else:
			cx0 = x1
			cx1 = prev["x0"]
		for x in range(cx0, cx1 + 1):
			for y in range(mini(prev["r"], r) - 4, maxi(prev["r"], r)):
				reserved[Vector2i(x, y)] = true
	plats.append({"x0": x0, "x1": x1, "r": r, "kind": kind})


func pick_kind(d: float, prev: String) -> String:
	var roll := rng.randf()
	if roll < 0.22 + 0.5 * d:
		if prev == "L":
			return "D" if rng.randf() < 0.75 else "L"
		if prev == "D":
			return "L" if rng.randf() < 0.75 else "D"
		return "L" if rng.randf() < 0.5 else "D"
	if d > 0.12 and roll < 0.32 + 0.6 * d:
		return "B"
	return "#"


func build(n: int, d: float) -> Dictionary:
	g = []
	reserved = {}
	plats = []
	for y in ROWS:
		var row := []
		for x in COLS:
			row.append(".")
		g.append(row)
	for x in COLS:
		setc(x, 0, "#")
		setc(x, 15, "#")
		setc(x, 16, "#")
	for y in ROWS:
		setc(0, y, "#")
		setc(COLS - 1, y, "#")
	var pit := d > 0.3 and rng.randf() < 0.3
	for x in range(1, COLS - 1):
		setc(x, 14, "^")
	if pit:
		for x in range(4, COLS - 1):
			setc(x, 14, ".")
			setc(x, 15, ".")
			setc(x, 16, ".")
	# start pad
	var pad := rng.randi_range(2, 3)
	for x in range(1, pad + 1):
		setc(x, 14, "#")
		setc(x, 15, "#")
		setc(x, 16, "#")
	setc(1, 13, "P")
	plats.append({"x0": 1, "x1": pad, "r": 14, "kind": "#"})

	# The route snakes through 1-3 horizontal bands, turning upward at the walls.
	var bands := 1 if d < 0.15 else (2 if d < 0.5 else 3)
	if rng.randf() < 0.25:
		bands = maxi(1, bands - 1)
	var band_rows: Array = []
	match bands:
		1: band_rows = [rng.randi_range(6, 11)]
		2: band_rows = [rng.randi_range(10, 12), rng.randi_range(4, 6)]
		3: band_rows = [12, 7, 3]
	var band := 0
	var target_row: int = band_rows[0]
	var cur: Dictionary = plats[0]
	var dir := 1
	var count := 0
	var prev_kind := "#"
	while count < 20:
		count += 1
		var r: int = cur["r"]
		var dy := clampi(target_row - r, -3, 2)
		if rng.randf() < 0.4:
			dy = clampi(dy + rng.randi_range(-1, 1), -3, 2)
		var nr := clampi(r + dy, 3, 12)
		var gap := 0
		var wmin := maxi(1, 3 - int(d * 2.5))
		var wmax := maxi(wmin, 5 - int(d * 2.0))
		var wdt := rng.randi_range(wmin, wmax)
		var x0 := 0
		var x1 := 0
		var last_band := band >= bands - 1
		var lim_hi := COLS - 3 if last_band else COLS - 4
		var lim_lo := 2 if last_band else 3
		dy = nr - r
		var gmin := 2
		var gmax := 4
		if dy <= -3:
			gmin = 1; gmax = 2
		elif dy == -2:
			gmin = 1; gmax = 3
		elif dy == -1:
			gmin = 2; gmax = 3 + (1 if d > 0.5 else 0)
		elif dy >= 2:
			gmin = 2; gmax = 5
		gap = gmin + int(round(pow(rng.randf(), 1.6 - d) * (gmax - gmin)))
		if dir > 0:
			x0 = int(cur["x1"]) + gap + 1
			x1 = x0 + wdt - 1
		else:
			x1 = int(cur["x0"]) - gap - 1
			x0 = x1 - wdt + 1
		if x1 > lim_hi or x0 < lim_lo:
			if last_band:
				break
			# climb a one-tile ledge by the wall, then run back the other way above
			var lr := r - 3
			var lx := int(cur["x1"]) + 2 if dir > 0 else int(cur["x0"]) - 2
			if lr < 3 or lx < 1 or lx > COLS - 2 or not area_free(lx, lx, lr):
				return {}
			place_platform(lx, lx, lr, "#")
			cur = plats[plats.size() - 1]
			prev_kind = "#"
			band += 1
			target_row = band_rows[band]
			dir = -dir
			continue
		var kind := pick_kind(d, prev_kind)
		if count == 1 and kind == "B":
			kind = "#"
		if not area_free(x0, x1, nr):
			if wdt > 1 and dir > 0 and area_free(x0, x0, nr):
				x1 = x0
			elif wdt > 1 and dir < 0 and area_free(x1, x1, nr):
				x0 = x1
			else:
				return {}
		place_platform(x0, x1, nr, kind)
		prev_kind = kind
		cur = plats[plats.size() - 1]
		if band == bands - 1 and ((dir > 0 and x1 >= COLS - 6) or (dir < 0 and x0 <= 5)):
			break
	if plats.size() < 4 + int(d * 3):
		return {}
	# exit on the last platform, which becomes stone (at least 2 wide)
	var last: Dictionary = plats[plats.size() - 1]
	var lx0: int = last["x0"]
	var lx1: int = last["x1"]
	if lx1 - lx0 < 1:
		if lx1 + 1 <= COLS - 2 and getc(lx1 + 1, last["r"]) == "." and getc(lx1 + 1, last["r"] - 1) == ".":
			lx1 += 1
		elif lx0 - 1 >= 1 and getc(lx0 - 1, last["r"]) == "." and getc(lx0 - 1, last["r"] - 1) == ".":
			lx0 -= 1
	for x in range(lx0, lx1 + 1):
		setc(x, last["r"], "#")
	last["kind"] = "#"
	last["x0"] = lx0
	last["x1"] = lx1
	var ex := (lx0 + lx1 + 1) / 2
	setc(ex, last["r"] - 1, "E")
	if last["r"] - 2 >= 1 and getc(ex, last["r"] - 2) != ".":
		return {}

	decorate(d, pit)
	var rows := []
	for y in ROWS:
		rows.append("".join(PackedStringArray(g[y])))
	var block := clampi((n - 1) / 10, 1, 10)
	var words: Array = WORDS[block]
	var name := "%s %s" % [words[0][(n * 7) % 10], words[1][(n * 3 + n / 10) % 10]]
	return {"name": name, "map": rows, "signs": []}


func decorate(d: float, pit: bool) -> void:
	var middle := plats.slice(1, plats.size() - 1)
	# stone pillars below stone platforms (pure decoration / structure)
	for p in middle:
		if p["kind"] == "#" and rng.randf() < 0.5 and not pit:
			var px: int = rng.randi_range(p["x0"], p["x1"])
			var ok := true
			for y in range(p["r"] + 1, 14):
				if getc(px, y) != "." or reserved.has(Vector2i(px, y)) or reserved.has(Vector2i(px - 1, y)) or reserved.has(Vector2i(px + 1, y)):
					ok = false
			if ok:
				for y in range(p["r"] + 1, 15):
					setc(px, y, "#")
	# one-world spikes on wide stone platforms
	for p in middle:
		if p["kind"] == "#" and p["x1"] - p["x0"] >= 2 and rng.randf() < 0.15 + 0.35 * d:
			var sx: int = rng.randi_range(p["x0"] + 1, p["x1"] - 1)
			if getc(sx, p["r"] - 1) == ".":
				setc(sx, p["r"] - 1, "d" if rng.randf() < 0.5 else "l")
	# wardens on wide stone platforms
	if d > 0.08:
		for p in middle:
			if p["kind"] == "#" and p["x1"] - p["x0"] >= 3 and rng.randf() < 0.25 + 0.35 * d:
				var wx: int = p["x0"] + 1
				if getc(wx, p["r"] - 1) == "." and getc(wx + 1, p["r"] - 1) == ".":
					setc(wx, p["r"] - 1, "w" if rng.randf() < 0.5 else "W")
	# wisps floating near the route
	if d > 0.15:
		var wisps := int(d * 3.0 + rng.randf())
		for i in wisps:
			var p: Dictionary = plats[rng.randi_range(1, plats.size() - 1)]
			var fx: int = clampi(rng.randi_range(p["x0"] - 2, p["x1"] + 2), 2, COLS - 3)
			var fy: int = clampi(p["r"] - rng.randi_range(3, 5), 1, 12)
			if getc(fx, fy) == "." and not reserved.has(Vector2i(fx, fy)):
				setc(fx, fy, "f")
	# sentinels in the side walls at a platform's standing height
	if d > 0.3 and rng.randf() < 0.3 + 0.5 * d:
		var p: Dictionary = plats[rng.randi_range(1, plats.size() - 1)]
		var ty: int = p["r"] - 1
		var left: bool = p["x0"] < COLS / 2
		var wx := COLS - 1 if left else 0
		if ty >= 1 and ty <= 12:
			setc(wx, ty, "t" if wx == COLS - 1 else "T")
	# a checkpoint on a long route
	if plats.size() >= 7:
		var mid: Array = middle.slice(middle.size() / 3, middle.size() * 2 / 3 + 1)
		for p in mid:
			if p["kind"] == "#":
				var cx: int = p["x0"]
				if getc(cx, p["r"] - 1) == ".":
					setc(cx, p["r"] - 1, "C")
					break


func place_tokens(data: Dictionary, path: Array, want: int) -> Array:
	var cells := route_cells(data, path)
	var rows: Array = data["map"]
	var out := []
	if cells.size() < 20:
		return out
	var lo := int(cells.size() * 0.12)
	var hi := int(cells.size() * 0.92)
	for k in want:
		var idx := lo + int((hi - lo) * (k + 0.5) / want)
		for off in [0, 3, -3, 6, -6, 9, -9, 12, -12]:
			var j := clampi(idx + off, lo, hi)
			var c: Vector2i = cells[j]
			if String(rows[c.y])[c.x] != ".":
				continue
			var close := false
			for o in out:
				if maxi(absi(o[0] - c.x), absi(o[1] - c.y)) < 2:
					close = true
			if close:
				continue
			out.append([c.x, c.y])
			break
	return out


func route_cells(data: Dictionary, path: Array) -> Array:
	var sim := Sim.new()
	sim.load_data(data, 0)
	var cells := []
	for st in path:
		var a: Array = solver.actions[int(st[0])]
		var was_held := sim.jump_held
		for f in int(st[1]):
			sim.step(solver.frame_input(a, f, was_held))
			var c := Vector2i(int(floor((sim.px + 5.0) / 16.0)), int(floor((sim.py + 7.0) / 16.0)))
			if cells.is_empty() or cells[cells.size() - 1] != c:
				cells.append(c)
	return cells


# ------------------------------------------------------------------ original levels

func original_tokens() -> void:
	var out := []
	for i in Levels.LEVELS.size():
		var data: Dictionary = Levels.LEVELS[i]
		var sol: Dictionary = JSON.parse_string(FileAccess.open("res://tests/solutions/level_%02d.json" % (i + 1), FileAccess.READ).get_as_text())
		rng.seed = 900 + i
		out.append(place_tokens(data, sol["path"], 3 + i / 3))
		print("level %d tokens %s" % [i + 1, out[i]])
	var f := FileAccess.open(CACHE + "/orig_tokens.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()


# ------------------------------------------------------------------ output

func assemble() -> void:
	var orig: Array = JSON.parse_string(FileAccess.open(CACHE + "/orig_tokens.json", FileAccess.READ).get_as_text())
	var lines := PackedStringArray()
	lines.append("class_name LevelsGen")
	lines.append("extends RefCounted")
	lines.append("## Generated by tools/gen_levels.gd. Do not edit by hand.")
	lines.append("## Token positions are [column, row]. Levels 11-110 were generated and")
	lines.append("## verified solvable with the game simulation.")
	lines.append("")
	lines.append("const ORIG_TOKENS := [")
	for t in orig:
		lines.append("\t%s," % _cells(t))
	lines.append("]")
	lines.append("")
	lines.append("const GEN := [")
	var missing := 0
	for n in range(11, 111):
		var p := CACHE + "/level_%03d.json" % n
		if not FileAccess.file_exists(p):
			missing += 1
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.open(p, FileAccess.READ).get_as_text())
		lines.append("\t{")
		lines.append("\t\t\"name\": \"%s\"," % data["name"])
		lines.append("\t\t\"map\": [")
		for row in data["map"]:
			lines.append("\t\t\t\"%s\"," % row)
		lines.append("\t\t],")
		lines.append("\t\t\"tokens\": %s," % _cells(data["tokens"]))
		lines.append("\t\t\"signs\": [],")
		lines.append("\t},")
		# solver route for the automated playthrough test
		var sf := FileAccess.open("res://tests/solutions/level_%02d.json" % n, FileAccess.WRITE)
		sf.store_string(JSON.stringify({"frames_per_action": Solver.K, "actions": solver.actions, "path": data["path"]}))
		sf.close()
	lines.append("]")
	var f := FileAccess.open("res://scripts/levels_gen.gd", FileAccess.WRITE)
	f.store_string("\n".join(lines) + "\n")
	f.close()
	print("assembled, missing levels: %d" % missing)


func _cells(t: Array) -> String:
	var parts := PackedStringArray()
	for c in t:
		parts.append("[%d, %d]" % [int(c[0]), int(c[1])])
	return "[" + ", ".join(parts) + "]"
