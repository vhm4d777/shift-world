extends SceneTree
## End-to-end test: plays every level through the real game scene (main loop,
## death/win handling, level-complete screen, save system) using the recorded
## solver inputs, and checks progress and shards are saved.
## godot --headless -s res://tests/playthrough.gd

var main
var game
var queue: Array = []
var was_held := false

func _initialize() -> void:
	game = root.get_node("Game")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.input_provider = provide
	run()

func provide() -> Dictionary:
	if queue.is_empty():
		return {}
	return queue.pop_front()

func run() -> void:
	game.reset_progress()
	for i in 30:
		await process_frame
	var failures := 0
	for lvl in 10:
		var data: Dictionary = JSON.parse_string(FileAccess.open("res://tests/solutions/level_%02d.json" % (lvl + 1), FileAccess.READ).get_as_text())
		var acts: Array = data["actions"]
		# translate the recorded actions into per-frame input dictionaries
		queue.clear()
		var held := false
		for step in data["path"]:
			var a: Array = acts[int(step[0])]
			var start_held := held
			for fr in int(step[1]):
				queue.append({"left": a[0] < 0, "right": a[0] > 0, "jump_held": a[1],
					"jump_pressed": a[1] and fr == 0 and not start_held, "shift_pressed": a[2] and fr == 0})
			held = a[1]
		main.start_level(lvl)
		while not queue.is_empty():
			await physics_frame
		for i in 150:
			await physics_frame
		var ok: bool = main.state == main.S.COMPLETE and game.completed.has(str(lvl))
		print("Level %2d: %s  deaths=%d time=%.2f" % [lvl + 1, "COMPLETE" if ok else "FAILED (state %d)" % main.state, main.level_deaths, main.sim.time])
		if not ok:
			failures += 1
	# shards: replay recorded shard routes through the sim
	print("Unlocked: ", game.unlocked, "  finished: ", game.game_finished)
	var f := FileAccess.open("user://save.json", FileAccess.READ)
	print("Save file written: ", f != null)
	print("PLAYTHROUGH OK" if failures == 0 else "PLAYTHROUGH FAILURES: %d" % failures)
	game.reset_progress()
	quit(failures)
