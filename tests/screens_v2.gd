extends SceneTree
## Renders screenshots of the 2.0 screens (needs a display, not --headless).
## SHIFTWORLDS_SAVE=shots.json godot -s res://tests/screens_v2.gd -- <out_dir>

var out := "user://shots"
var main
var game

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	game = root.get_node("Game")
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	run()

func wait(n: int) -> void:
	for i in n:
		await process_frame

func shot(name: String) -> void:
	await process_frame
	root.get_texture().get_image().save_png(out + "/" + name + ".png")
	print("shot ", name)

func run() -> void:
	game.reset_progress()
	game.player_name = "ИГРОК"
	game.tokens = 230
	game.unlocked = 40
	for i in 14:
		game.completed[str(i)] = true
		game.best_times[str(i)] = 12.5 + i
		game.token_got[str(i)] = [0, 1]
	game.owned_skins = [0, 1, 3]
	await wait(60)
	await shot("01_title")
	main.name_buf = "ИГРОК"
	main.set_state(main.S.NAME)
	await wait(10)
	await shot("02_name")
	main.set_state(main.S.SHOP)
	main.shop_tab = 0
	main.menu_index = 3
	await wait(10)
	await shot("03_shop_skins")
	main.shop_tab = 1
	main.menu_index = 5
	await wait(20)
	await shot("04_shop_weapons")
	main.set_state(main.S.SELECT)
	main.menu_index = 2
	await wait(10)
	await shot("05_select_w1")
	main.set_state(main.S.SELECT)
	main.menu_index = 14
	await wait(10)
	await shot("06_select_w2")
	main.settings_return = main.S.TITLE
	main.set_state(main.S.SETTINGS)
	await wait(5)
	await shot("07_settings")
	game.skin = 3
	for stage in [0, 13, 36, 57, 79, 101, 119]:
		main.start_level(stage)
		await wait(200)
		await shot("lvl_%03d_light" % stage)
		Input.action_press("shift")
		await wait(3)
		Input.action_release("shift")
		await wait(40)
		await shot("lvl_%03d_dark" % stage)
	game.weapon = 3
	for stage in [10, 65, 120]:
		main.start_level(stage)
		await wait(60)
		await shot("boss_%03d_card" % stage)
		main.sim.invincible = true
		Input.action_press("fire")
		await wait(330)
		await shot("boss_%03d_fight_a" % stage)
		await wait(200)
		await shot("boss_%03d_fight_b" % stage)
		Input.action_release("fire")
	main.start_level(13)
	await wait(20)
	main.sim.tokens_taken[0] = true
	main.sim.time = 21.3
	main._finish_level()
	await wait(40)
	await shot("20_complete")
	quit()
