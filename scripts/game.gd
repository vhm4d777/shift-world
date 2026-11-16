extends Node
## Global game state: progress, settings, save file and input bindings.

const VERSION := "1.0.0"
const AUTHOR := "Shift Worlds Team"
const SAVE_PATH := "user://save.json"
const LEVEL_COUNT := 10

var unlocked := 1                 # number of levels available
var completed := {}               # "index" -> true
var shards := {}                  # "index" -> true
var best_times := {}              # "index" -> seconds
var total_deaths := 0
var seen_intro := false
var game_finished := false

var music_volume := 0.7
var sfx_volume := 0.8
var fullscreen := false
var screen_shake := true
var show_timer := false

var current_level := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_game()
	apply_display()


# ------------------------------------------------------------------ input

func _setup_input() -> void:
	_bind("move_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]])
	_bind("move_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]])
	_bind("move_up", [KEY_W, KEY_UP], [JOY_BUTTON_DPAD_UP], [[JOY_AXIS_LEFT_Y, -1.0]])
	_bind("move_down", [KEY_S, KEY_DOWN], [JOY_BUTTON_DPAD_DOWN], [[JOY_AXIS_LEFT_Y, 1.0]])
	_bind("jump", [KEY_SPACE, KEY_W, KEY_UP, KEY_Z], [JOY_BUTTON_A], [])
	_bind("shift", [KEY_SHIFT, KEY_X, KEY_K], [JOY_BUTTON_X, JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_LEFT_SHOULDER], [])
	_bind("restart", [KEY_R], [JOY_BUTTON_Y], [])
	_bind("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START], [])
	_bind("confirm", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [JOY_BUTTON_A], [])
	_bind("back", [KEY_ESCAPE, KEY_BACKSPACE], [JOY_BUTTON_B], [])
	_bind("fullscreen", [KEY_F11], [], [])


func _bind(action: String, keys: Array, buttons: Array, axes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.4)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in axes:
		var e := InputEventJoypadMotion.new()
		e.axis = a[0]
		e.axis_value = a[1]
		InputMap.action_add_event(action, e)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		fullscreen = not fullscreen
		apply_display()
		save_game()


# ------------------------------------------------------------------ display

func apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_fit_window()


## Picks the largest whole-number scale of 480x272 that fits on the current screen.
func _fit_window() -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return
	var scale := 1
	while 480 * (scale + 1) <= usable.size.x - 40 and 272 * (scale + 1) <= usable.size.y - 60:
		scale += 1
	var size := Vector2i(480 * scale, 272 * scale)
	DisplayServer.window_set_size(size)
	DisplayServer.window_set_position(usable.position + (usable.size - size) / 2)


# ------------------------------------------------------------------ progress

func is_unlocked(i: int) -> bool:
	return i < unlocked


func complete_level(i: int, seconds: float, got_shard: bool, deaths: int) -> bool:
	## Records a completed level. Returns true if this was a new best time.
	var key := str(i)
	completed[key] = true
	if got_shard:
		shards[key] = true
	total_deaths += deaths
	var new_best := false
	if not best_times.has(key) or seconds < float(best_times[key]):
		best_times[key] = seconds
		new_best = true
	unlocked = max(unlocked, min(i + 2, LEVEL_COUNT))
	if i == LEVEL_COUNT - 1:
		game_finished = true
	save_game()
	return new_best


func shard_count() -> int:
	return shards.size()


func completed_count() -> int:
	return completed.size()


func has_progress() -> bool:
	return completed.size() > 0


func reset_progress() -> void:
	unlocked = 1
	completed.clear()
	shards.clear()
	best_times.clear()
	total_deaths = 0
	seen_intro = false
	game_finished = false
	save_game()


static func format_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	var cs := int(t * 100.0) % 100
	return "%d:%02d.%02d" % [m, s, cs]


# ------------------------------------------------------------------ save file

func save_game() -> void:
	var data := {
		"version": VERSION,
		"unlocked": unlocked,
		"completed": completed,
		"shards": shards,
		"best_times": best_times,
		"total_deaths": total_deaths,
		"seen_intro": seen_intro,
		"game_finished": game_finished,
		"settings": {
			"music": music_volume,
			"sfx": sfx_volume,
			"fullscreen": fullscreen,
			"shake": screen_shake,
			"timer": show_timer,
		},
	}
	var tmp := SAVE_PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save file")
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(SAVE_PATH))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file was unreadable; starting fresh.")
		return
	var d: Dictionary = parsed
	unlocked = clampi(int(d.get("unlocked", 1)), 1, LEVEL_COUNT)
	completed = _as_dict(d.get("completed", {}))
	shards = _as_dict(d.get("shards", {}))
	best_times = _as_dict(d.get("best_times", {}))
	total_deaths = int(d.get("total_deaths", 0))
	seen_intro = bool(d.get("seen_intro", false))
	game_finished = bool(d.get("game_finished", false))
	var s: Dictionary = _as_dict(d.get("settings", {}))
	music_volume = clampf(float(s.get("music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(s.get("sfx", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(s.get("fullscreen", fullscreen))
	screen_shake = bool(s.get("shake", screen_shake))
	show_timer = bool(s.get("timer", show_timer))


func _as_dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}
