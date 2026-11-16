extends SceneTree
## Captures store-page screenshots mid-play by replaying recorded solutions.
## xvfb-run godot --rendering-driver opengl3 -s res://tests/marketing_shots.gd -- <out_dir>

var out := "/tmp/marketing"
var main
var queue: Array = []

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	main.input_provider = func(): return {} if queue.is_empty() else queue.pop_front()
	run()

func shot(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)

func frames_for(lvl: int) -> Array:
	var data: Dictionary = JSON.parse_string(FileAccess.open("res://tests/solutions/level_%02d.json" % lvl, FileAccess.READ).get_as_text())
	var acts: Array = data["actions"]
	var q := []
	var held := false
	for step in data["path"]:
		var a: Array = acts[int(step[0])]
		var sh := held
		for fr in int(step[1]):
			q.append({"left": a[0] < 0, "right": a[0] > 0, "jump_held": a[1], "jump_pressed": a[1] and fr == 0 and not sh, "shift_pressed": a[2] and fr == 0})
		held = a[1]
	return q

func play_to(lvl: int, frac: float) -> void:
	var q := frames_for(lvl)
	main.start_level(lvl - 1)
	main.card_time = 0.0
	queue = q.slice(0, int(q.size() * frac))
	while not queue.is_empty():
		await physics_frame
	for i in 3:
		await physics_frame

func run() -> void:
	await create_timer(1.5).timeout
	await shot("title")
	for spec in [[1, 0.55, "two_sides"], [4, 0.62, "frozen_wardens"], [6, 0.5, "wisps"], [7, 0.75, "sentinels"], [9, 0.55, "ascension"], [10, 0.7, "the_rift"], [3, 0.45, "gatekeeper"]]:
		await play_to(spec[0], spec[1])
		await shot("%02d_%s" % [spec[0], spec[2]])
	# cover art source: the same moment in both worlds, without HUD
	await play_to(10, 0.42)
	main.ui.visible = false
	for w in [0, 1]:
		main.sim.world = w
		main.view.old_world = w
		main.view.shift_fx = 1.0
		await create_timer(0.2).timeout
		await shot("light_cover" if w == 0 else "dark_cover")
	main.ui.visible = true
	quit()
