class_name Solver
extends RefCounted
## Best-first search over player inputs using the real game simulation.
## Shared by tests/solve.gd and tools/gen_levels.gd.

const K := 8

var actions := []
var limit := 80000


func _init() -> void:
	for sh in [false, true]:
		for h in [0, -1, 1]:
			for j in [false, true]:
				actions.append([h, j, sh])


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


## Returns [snapshot or null, nodes expanded, path]. A path is a list of [action index, frames].
func search(s: Sim, start: Array, goal) -> Array:
	s.restore(start)
	var start_flipped := s.gates_flipped
	var tgt := target(s, goal)
	var heap := []
	var counter := 0
	_push(heap, [0.0, counter, start, 0, []])
	var seen := {key(s): true}
	var expanded := 0
	while not heap.is_empty() and expanded < limit:
		var node: Array = _pop(heap)
		expanded += 1
		for ai in actions.size():
			var a: Array = actions[ai]
			s.restore(node[2])
			var was_held := s.jump_held
			var used := K
			for f in K:
				s.step(frame_input(a, f, was_held))
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


func frame_input(a: Array, f: int, was_held: bool) -> Dictionary:
	return {"left": a[0] < 0, "right": a[0] > 0, "jump_held": a[1],
		"jump_pressed": a[1] and f == 0 and not was_held, "shift_pressed": a[2] and f == 0}


## Replays a path from a fresh level load; calls visit(sim) after every frame.
func replay(s: Sim, level: int, path: Array, visit: Callable) -> void:
	s.load_level(level)
	for step in path:
		var a: Array = actions[int(step[0])]
		var was_held := s.jump_held
		for f in int(step[1]):
			s.step(frame_input(a, f, was_held))
			visit.call(s)


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
