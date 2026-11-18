extends SceneTree

const BD := preload("res://scripts/backdrops.gd")
## Renders the procedural world backdrops (scripts/backdrops.gd) to PNG files in
## assets/themes so the game can load them instantly.
## godot --headless -s res://tools/bake_backdrops.gd

func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/themes")
	for theme in range(1, 11):
		for w in 2:
			var t0 := Time.get_ticks_msec()
			var tex: Array = BD.bake(theme, w)
			var wn := "light" if w == 0 else "dark"
			tex[0].get_image().save_png("res://assets/themes/bg_%02d_%s_far.png" % [theme, wn])
			tex[1].get_image().save_png("res://assets/themes/bg_%02d_%s_mid.png" % [theme, wn])
			print("theme %d %s  %d ms" % [theme, wn, Time.get_ticks_msec() - t0])
	quit(0)
