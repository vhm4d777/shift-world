extends SceneTree
## Renders screenshots of every screen and level (run under a display / xvfb).
## godot -s res://tests/screenshots.gd -- <out_dir>

var out := "/tmp/shots"
var main

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	run()

func wait(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out + "/" + name + ".png")
	print("shot ", name)

func hold(action: String, frames: int) -> void:
	Input.action_press(action)
	await wait(frames)
	Input.action_release(action)

func tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	await physics_frame
	Input.action_release(action)
	await physics_frame

func run() -> void:
	await wait(90)
	await shot("01_title")
	await wait(300)
	await shot("02_title_dark")
	main.set_state(main.S.SELECT)
	main.menu_index = 3
	await wait(30)
	await shot("03_select")
	main.settings_return = main.S.TITLE
	main.set_state(main.S.SETTINGS)
	await wait(10)
	await shot("04_settings")
	main.set_state(main.S.CONTROLS)
	await wait(10)
	await shot("05_controls")
	main.set_state(main.S.CREDITS)
	await wait(10)
	await shot("06_credits")
	main.set_state(main.S.INTRO)
	await wait(300)
	await shot("07_intro")
	for i in 10:
		main.start_level(i)
		await wait(20)
		if i == 0:
			await shot("10_level01_card")
		await wait(150)
		await shot("lvl%02d_light" % (i + 1))
		await tap("shift")
		await wait(8)
		if i == 0:
			await shot("11_level01_shifting")
		await wait(40)
		await shot("lvl%02d_dark" % (i + 1))
	main.start_level(0)
	await wait(170)
	await hold("move_right", 40)
	await wait(5)
	await shot("12_sign")
	main._pause()
	await wait(10)
	await shot("13_pause")
	main._activate_pause("resume")
	main.sim.shard_taken = true
	main.level_deaths = 3
	main._finish_level()
	await wait(40)
	await shot("14_complete")
	main.set_state(main.S.ENDING)
	main.view.title_mode = true
	await wait(420)
	await shot("15_ending")
	quit()
