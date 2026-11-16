extends SceneTree
## Automated level verification: best-first search over player inputs using the
## real game simulation. Confirms every exit and memory shard is reachable.
## Run: godot --headless -s res://tests/solve.gd [-- level_number]

const K := 8
const LIMIT := 80000
# Intermediate goals per level (levels that need a lever pulled first).
# An area goal is [x, y, w, h] that the player's centre must enter.
const PLAN := {
	2: ["lever", "exit"],
	3: [[336, 140, 32, 20], "exit"],
	7: [[16, 140, 48, 20], "lever", "exit"],
	8: [[336, 124, 40, 20], "lever", "exit"],
	9: ["lever", [400, 40, 64, 24], "exit"],
}

const SHARD_PLAN := {8: [[336, 124, 40, 20], "shard"]}

var actions := []

func _init() -> void:
	for sh in [false, true]:
		for h in [0, -1, 1]:
			for j in [false, true]:
				actions.append([h, j, sh])
	var only := -1
	for a in OS.get_cmdline_user_args():
		only = int(a) - 1
	var ok := true
	for i in Levels.count():
		if only >= 0 and i != only:
			continue
		var t0 := Time.get_ticks_msec()
		var s := Sim.new()
		s.load_level(i)
		var exit_ok := true
		var nodes := 0
		var steps: Array = PLAN.get(i, ["exit"])
		var snap := s.snapshot()
		var path := []
		for goal in steps:
			var r := search(s, snap, goal)
			nodes += r[1]
			if r[0] == null:
				exit_ok = false
				print("   failed at goal: ", goal)
				break
			snap = r[0]
			path.append_array(r[2])
		if exit_ok:
			DirAccess.make_dir_recursive_absolute("res://tests/solutions")
			var f := FileAccess.open("res://tests/solutions/level_%02d.json" % (i + 1), FileAccess.WRITE)
			f.store_string(JSON.stringify({"frames_per_action": K, "actions": actions, "path": path}))
			f.close()
		var shard_ok := true
		if s.has_shard:
			s.load_level(i)
			var sn := s.snapshot()
			for goal in SHARD_PLAN.get(i, ["shard"]):
				var r2 := search(s, sn, goal)
				nodes += r2[1]
				if r2[0] == null:
					shard_ok = false
					break
				sn = r2[0]
		print("Level %2d %-18s exit:%s shard:%s nodes:%d  %.1fs" % [i + 1, Levels.get_level(i)["name"], exit_ok, shard_ok, nodes, (Time.get_ticks_msec() - t0) / 1000.0])
		if not exit_ok or not shard_ok:
			ok = false
	print("ALL OK" if ok else "SOME LEVELS FAILED")
	quit(0 if ok else 1)

func key(s: Sim) -> String:
	var k := "%d,%d,%d,%d,%d,%d,%d" % [int(s.px / 3), int(s.py / 3), int(s.vy / 70), s.world, int(s.gates_flipped), int(s.on_ground), int(s.jump_held)]
	for m in s.movers:
		k += ",m%d.%d" % [int(m["x"] / 6), int(m["y"] / 6)]
	for w in s.walkers:
		k += ",w%d" % int(w["x"] / 6)
	for c in s.crumble_state:
		k += str(c)
	return k

func target(s: Sim, goal) -> Vector2:
	if goal is Array:
		return Rect2(goal[0], goal[1], goal[2], goal[3]).get_center()
	match goal:
		"lever": return s.levers[0].get_center()
		"shard": return s.shard_rect.get_center()
	return s.exit_rect.get_center()

func reached(s: Sim, goal, start_flipped: bool) -> bool:
	if goal is Array:
		return Rect2(goal[0], goal[1], goal[2], goal[3]).has_point(Vector2(s.px + 5, s.py + 7))
	match goal:
		"lever": return s.gates_flipped != start_flipped
		"shard": return s.shard_taken
	return s.won

func search(s: Sim, start: Array, goal) -> Array:
	s.restore(start)
	var start_flipped := s.gates_flipped
	var tgt := target(s, goal)
	# binary heap of [priority, counter, snapshot, depth]
	var heap := []
	var counter := 0
	_push(heap, [0.0, counter, start, 0, []])
	var seen := {key(s): true}
	var expanded := 0
	while not heap.is_empty() and expanded < LIMIT:
		var node: Array = _pop(heap)
		expanded += 1
		for ai in actions.size():
			var a: Array = actions[ai]
			s.restore(node[2])
			var was_held := s.jump_held
			var used := K
			for f in K:
				s.step({"left": a[0] < 0, "right": a[0] > 0, "jump_held": a[1],
					"jump_pressed": a[1] and f == 0 and not was_held, "shift_pressed": a[2] and f == 0})
				if s.dead or s.won or reached(s, goal, start_flipped):
					used = f + 1
					break
			if s.dead:
				continue
			if reached(s, goal, start_flipped):
				var done: Array = node[4].duplicate()
				done.append([ai, used])
				return [s.snapshot(), expanded, done]
			if s.won:
				continue
			var k := key(s)
			if seen.has(k):
				continue
			seen[k] = true
			counter += 1
			var d := Vector2(s.px + 5, s.py + 7).distance_to(tgt)
			var np: Array = node[4].duplicate()
			np.append([ai, K])
			_push(heap, [d / 105.0 + (node[3] + 1) * 0.04, counter, s.snapshot(), node[3] + 1, np])
	return [null, expanded, []]

func _less(a: Array, b: Array) -> bool:
	return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1])

func _push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if _less(h[i], h[p]):
			var t = h[i]; h[i] = h[p]; h[p] = t
			i = p
		else:
			break

func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var i := 0
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < h.size() and _less(h[l], h[m]): m = l
			if r < h.size() and _less(h[r], h[m]): m = r
			if m == i: break
			var t = h[i]; h[i] = h[m]; h[m] = t
			i = m
	return top
