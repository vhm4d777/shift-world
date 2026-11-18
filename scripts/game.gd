extends Node
## Global game state: progress, settings, save file and input bindings.

const VERSION := "2.0.0"
const AUTHOR := "Shift Worlds Team"
const SAVE_PATH := "user://save.json"
const LEVEL_COUNT := 121          # stages: 110 levels + 11 bosses
const NAME_MAX := 12

## Player skins: palette for the Light and Dark worlds plus an accessory.
const SKINS := [
	{"name": "Drifter", "price": 0, "acc": "",
		"pal": [{"o": "2b2350", "c": "f4f2ff", "h": "c9c3f0", "f": "3b2f6b", "e": "7fe3ff", "s": "4fc3ff"},
			{"o": "c08cff", "c": "3a1d55", "h": "26103a", "f": "0b0414", "e": "ffffff", "s": "ff2e55"}]},
	{"name": "Ember", "price": 15, "acc": "",
		"pal": [{"o": "4a1a10", "c": "ffd8b0", "h": "f2a070", "f": "5a2010", "e": "fff3a0", "s": "ff7a3d"},
			{"o": "ff9a50", "c": "5a1a0a", "h": "3a0e05", "f": "120402", "e": "ffe080", "s": "ff4a1a"}]},
	{"name": "Mint", "price": 25, "acc": "band",
		"pal": [{"o": "17463a", "c": "e0fff2", "h": "a8e8cc", "f": "1e5a48", "e": "40ffb0", "s": "2ee6a0"},
			{"o": "60ffc0", "c": "0f3a30", "h": "082820", "f": "02100c", "e": "c0fff0", "s": "00d68a"}]},
	{"name": "Royal", "price": 40, "acc": "crown",
		"pal": [{"o": "2a1450", "c": "efe6ff", "h": "c4a8f0", "f": "3a1a70", "e": "ffd84a", "s": "9b5bff"},
			{"o": "ffd84a", "c": "3a1466", "h": "250a45", "f": "0c0418", "e": "ffe890", "s": "ffb020"}]},
	{"name": "Shadow", "price": 70, "acc": "horns",
		"pal": [{"o": "101014", "c": "4a4a58", "h": "34343e", "f": "08080a", "e": "ff2e55", "s": "2a2a33"},
			{"o": "ff2e55", "c": "18080e", "h": "0c0408", "f": "000000", "e": "ff5577", "s": "b0124a"}]},
	{"name": "Solar", "price": 100, "acc": "halo",
		"pal": [{"o": "6a4a10", "c": "fff6d0", "h": "ffe08a", "f": "7a5010", "e": "ff9a20", "s": "ffd040"},
			{"o": "ffe070", "c": "5a3a08", "h": "3a2404", "f": "140c00", "e": "ffffff", "s": "ffb000"}]},
	{"name": "Glacier", "price": 150, "acc": "band",
		"pal": [{"o": "1a3a6a", "c": "f0faff", "h": "bfe4ff", "f": "20508a", "e": "40d8ff", "s": "a6ecff"},
			{"o": "a6ecff", "c": "0e2a4a", "h": "081a30", "f": "020a14", "e": "ffffff", "s": "40c0ff"}]},
	{"name": "Rift Walker", "price": 240, "acc": "crown",
		"pal": [{"o": "3a0a4a", "c": "ffe6ff", "h": "f0a8ff", "f": "4a1060", "e": "4fc3ff", "s": "ff2e9a"},
			{"o": "4fc3ff", "c": "2a0640", "h": "18022a", "f": "06000c", "e": "ff2e9a", "s": "4fc3ff"}]},
]

## Weapons for boss fights. cd = seconds between shots, spread in degrees.
const WEAPONS := [
	{"name": "Spark Pistol", "price": 0, "dmg": 1, "cd": 0.28, "speed": 260.0, "count": 1, "spread": 0.0, "size": 2.0, "pierce": false, "color": "7fe3ff"},
	{"name": "Twin Blaster", "price": 30, "dmg": 1, "cd": 0.22, "speed": 280.0, "count": 2, "spread": 4.0, "size": 2.0, "pierce": false, "color": "9bff7a"},
	{"name": "Scatter Gun", "price": 60, "dmg": 1, "cd": 0.40, "speed": 250.0, "count": 5, "spread": 34.0, "size": 2.0, "pierce": false, "color": "ffb347"},
	{"name": "Plasma Rifle", "price": 110, "dmg": 3, "cd": 0.30, "speed": 300.0, "count": 1, "spread": 0.0, "size": 3.0, "pierce": false, "color": "c77dff"},
	{"name": "Rift Repeater", "price": 170, "dmg": 1, "cd": 0.085, "speed": 330.0, "count": 1, "spread": 0.0, "size": 2.0, "pierce": false, "color": "ff5c8a"},
	{"name": "Storm Caster", "price": 250, "dmg": 2, "cd": 0.16, "speed": 310.0, "count": 3, "spread": 14.0, "size": 2.0, "pierce": false, "color": "7ab8ff"},
	{"name": "Prism Cannon", "price": 360, "dmg": 7, "cd": 0.50, "speed": 340.0, "count": 1, "spread": 0.0, "size": 5.0, "pierce": true, "color": "fff3a0"},
]

var unlocked := 1                 # number of levels available
var completed := {}               # "index" -> true
var shards := {}                  # "index" -> true
var best_times := {}              # "index" -> seconds
var total_deaths := 0
var seen_intro := false
var game_finished := false
var player_name := ""
var tokens := 0                   # wallet
var token_got := {}               # "stage" -> [token indices ever collected]
var bosses_beaten := {}           # "stage" -> true
var owned_skins := [0]
var owned_weapons := [0]
var skin := 0
var weapon := 0
var last_earned := 0              # tokens earned by the last finished stage

var music_volume := 0.7
var sfx_volume := 0.8
var fullscreen := false
var screen_shake := true
var show_timer := false

var current_level := 0
## Automated tests set SHIFTWORLDS_SAVE so they never touch the player's real save.
var save_path := SAVE_PATH


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_environment("SHIFTWORLDS_SAVE") != "":
		save_path = "user://" + OS.get_environment("SHIFTWORLDS_SAVE")
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
	_bind("fire", [KEY_J, KEY_F, KEY_C, KEY_CTRL], [JOY_BUTTON_B], [[JOY_AXIS_TRIGGER_RIGHT, 1.0]])
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("fire", mb)
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


func complete_level(i: int, seconds: float, got_shard: bool, deaths: int, taken: Array = []) -> bool:
	## Records a completed level. Returns true if this was a new best time.
	var key := str(i)
	completed[key] = true
	last_earned = 0
	var got: Array = token_got.get(key, [])
	for t in taken:
		if not got.has(int(t)):
			got.append(int(t))
			last_earned += 1
	token_got[key] = got
	if Levels.is_boss(i):
		if bosses_beaten.has(key):
			last_earned += 5
		else:
			last_earned += 20 + 10 * Levels.number(i)
			bosses_beaten[key] = true
	tokens += last_earned
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


func tokens_found(i: int) -> int:
	return (token_got.get(str(i), []) as Array).size()


func bosses_count() -> int:
	return bosses_beaten.size()


func skin_palettes(idx: int = -1) -> Array:
	if idx < 0:
		idx = skin
	var out := []
	for p in SKINS[idx]["pal"]:
		var d := {}
		for k in p:
			d[k] = Color(p[k])
		out.append(d)
	return out


func weapon_stats() -> Dictionary:
	return WEAPONS[weapon]


## Buys or equips an item. kind is "skin" or "weapon". Returns "equipped", "bought" or "poor".
func shop_action(kind: String, idx: int) -> String:
	var owned: Array = owned_skins if kind == "skin" else owned_weapons
	var list: Array = SKINS if kind == "skin" else WEAPONS
	if not owned.has(idx):
		var price: int = list[idx]["price"]
		if tokens < price:
			return "poor"
		tokens -= price
		owned.append(idx)
		_equip(kind, idx)
		save_game()
		return "bought"
	_equip(kind, idx)
	save_game()
	return "equipped"


func _equip(kind: String, idx: int) -> void:
	if kind == "skin":
		skin = idx
	else:
		weapon = idx


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
	tokens = 0
	token_got.clear()
	bosses_beaten.clear()
	owned_skins = [0]
	owned_weapons = [0]
	skin = 0
	weapon = 0
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
		"name": player_name,
		"tokens": tokens,
		"token_got": token_got,
		"bosses_beaten": bosses_beaten,
		"owned_skins": owned_skins,
		"owned_weapons": owned_weapons,
		"skin": skin,
		"weapon": weapon,
		"settings": {
			"music": music_volume,
			"sfx": sfx_volume,
			"fullscreen": fullscreen,
			"shake": screen_shake,
			"timer": show_timer,
		},
	}
	var tmp := save_path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write save file")
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(save_path))


func load_game() -> void:
	if not FileAccess.file_exists(save_path):
		return
	var f := FileAccess.open(save_path, FileAccess.READ)
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
	player_name = str(d.get("name", "")).substr(0, NAME_MAX)
	tokens = maxi(0, int(d.get("tokens", 0)))
	token_got = _as_dict(d.get("token_got", {}))
	bosses_beaten = _as_dict(d.get("bosses_beaten", {}))
	owned_skins = _int_list(d.get("owned_skins", [0]), SKINS.size())
	owned_weapons = _int_list(d.get("owned_weapons", [0]), WEAPONS.size())
	skin = clampi(int(d.get("skin", 0)), 0, SKINS.size() - 1)
	weapon = clampi(int(d.get("weapon", 0)), 0, WEAPONS.size() - 1)
	if not owned_skins.has(skin):
		skin = 0
	if not owned_weapons.has(weapon):
		weapon = 0
	# v1 saves stopped after level 10; open the first boss for players who finished it
	if completed.has("9"):
		unlocked = maxi(unlocked, 11)
	var s: Dictionary = _as_dict(d.get("settings", {}))
	music_volume = clampf(float(s.get("music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(s.get("sfx", sfx_volume)), 0.0, 1.0)
	fullscreen = bool(s.get("fullscreen", fullscreen))
	screen_shake = bool(s.get("shake", screen_shake))
	show_timer = bool(s.get("timer", show_timer))


func _as_dict(v) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _int_list(v, size: int) -> Array:
	var out := [0]
	if typeof(v) == TYPE_ARRAY:
		for x in v:
			var i := int(x)
			if i > 0 and i < size and not out.has(i):
				out.append(i)
	return out
