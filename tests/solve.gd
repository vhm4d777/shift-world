extends SceneTree
## Automated level verification for the ten handcrafted levels: best-first
## search over player inputs using the real game simulation. Confirms every exit
## and memory shard is reachable. (Levels 11-110 are verified by
## tools/gen_levels.gd when they are generated, and all 110 are replayed by
## tests/playthrough.gd.)
## Run: godot --headless -s res://tests/solve.gd [-- level_number]

# Intermediate goals per level (levels that need a lever pulled first).
const PLAN := {
	2: ["lever", "exit"],
	3: [[336, 140, 32, 20], "exit"],
	7: [[16, 140, 48, 20], "lever", "exit"],
	8: [[336, 124, 40, 20], "lever", "exit"],
	9: ["lever", [400, 40, 64, 24], "exit"],
}
const SHARD_PLAN := {8: [[336, 124, 40, 20], "shard"]}


func _init() -> void:
	var solver := Solver.new()
	var only := -1
	for a in OS.get_cmdline_user_args():
		only = int(a) - 1
	var ok := true
	for i in Levels.LEVELS.size():
		if only >= 0 and i != only:
			continue
		var t0 := Time.get_ticks_msec()
		var s := Sim.new()
		var data := Levels.get_normal(i)
		s.load_data(data, i)
		var exit_ok := true
		var nodes := 0
		var snap := s.snapshot()
		var path := []
		for goal in PLAN.get(i, ["exit"]):
			var r := solver.search(s, snap, goal)
			nodes += r[1]
			if r[0] == null:
				exit_ok = false
				print("   failed at goal: ", goal)
				break
			snap = r[0]
			path.append_array(r[2])
		if exit_ok:
			var f := FileAccess.open("res://tests/solutions/level_%02d.json" % (i + 1), FileAccess.WRITE)
			f.store_string(JSON.stringify({"frames_per_action": Solver.K, "actions": solver.actions, "path": path}))
			f.close()
		var shard_ok := true
		if s.has_shard:
			s.load_data(data, i)
			var sn := s.snapshot()
			for goal in SHARD_PLAN.get(i, ["shard"]):
				var r2 := solver.search(s, sn, goal)
				nodes += r2[1]
				if r2[0] == null:
					shard_ok = false
					break
				sn = r2[0]
		print("Level %2d %-18s exit:%s shard:%s nodes:%d  %.1fs" % [i + 1, data["name"], exit_ok, shard_ok, nodes, (Time.get_ticks_msec() - t0) / 1000.0])
		if not exit_ok or not shard_ok:
			ok = false
	print("ALL OK" if ok else "SOME LEVELS FAILED")
	quit(0 if ok else 1)
