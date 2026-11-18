extends SceneTree
## End-to-end test: plays all 110 levels through the real game scene (main loop,
## death/win handling, level-complete screen, save system, tokens) using the
## recorded solver inputs, and checks that progress and every token are saved.
## SHIFTWORLDS_SAVE=test_save.json godot --headless -s res://tests/playthrough.gd

var main
var game
var queue: Array = []

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
	var tokens_total := 0
	for lvl in Levels.NORMAL_LEVELS:
		var stage: int = (lvl / 10) * Levels.PER_WORLD + lvl % 10
		var data: Dictionary = JSON.parse_string(FileAccess.open("res://tests/solutions/level_%02d.json" % (lvl + 1), FileAccess.READ).get_as_text())
		var acts: Array = data["actions"]
		queue.clear()
		var held := false
		for step in data["path"]:
			var a: Array = acts[int(step[0])]
			var start_held := held
			for fr in int(step[1]):
				queue.append({"left": a[0] < 0, "right": a[0] > 0, "jump_held": a[1],
					"jump_pressed": a[1] and fr == 0 and not start_held, "shift_pressed": a[2] and fr == 0})
			held = a[1]
		main.start_level(stage)
		while not queue.is_empty():
			await physics_frame
		for i in 110:
			await physics_frame
		var ok: bool = main.state == main.S.COMPLETE and game.completed.has(str(stage))
		var got: int = game.tokens_found(stage)
		var want: int = Levels.token_count(stage)
		tokens_total += got
		if got != want:
			ok = false
		if not ok or lvl % 10 == 9:
			print("Level %3d (stage %3d): %s  deaths=%d time=%.2f tokens=%d/%d" % [lvl + 1, stage, "COMPLETE" if ok else "FAILED (state %d)" % main.state, main.level_deaths, main.sim.time, got, want])
		if not ok:
			failures += 1
	print("Unlocked: ", game.unlocked, "  wallet: ", game.tokens, "  tokens found: ", tokens_total)
	print("PLAYTHROUGH OK" if failures == 0 else "PLAYTHROUGH FAILURES: %d" % failures)
	game.reset_progress()
	quit(failures)
