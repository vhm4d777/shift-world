extends Node2D
## Top-level game flow: menus, gameplay loop, HUD and screen transitions.

enum S { TITLE, INTRO, SELECT, SETTINGS, CONTROLS, CREDITS, PLAY, PAUSE, COMPLETE, ENDING, CONFIRM_RESET, NAME, SHOP }

const W := 480
const H := 272
const COL_LIGHT := Color("4fc3ff")
const COL_DARK := Color("ff2e55")
const COL_TEXT := Color("f2eeff")
const COL_DIM := Color("8f86b8")
const COL_GOLD := Color("fff3a0")
const COL_COIN := Color("ffd84a")
const COL_PANEL := Color(0.035, 0.012, 0.06, 0.88)
const PER_PAGE := 11

const INTRO_LINES := [
	"Between every world lies a seam.",
	"You fell into it.",
	"Now you belong to both the Light and the Dark,",
	"and neither one will let you go.",
	"Find the rifts.  Shift to survive.",
]
const ENDING_LINES := [
	"The Rift Heart falls silent.",
	"Light and Dark fold back into a single sky.",
	"You walk out into the morning...",
	"...but you will always remember both sides.",
]

var state := S.TITLE
var state_time := 0.0
var sim := Sim.new()
var view: LevelView
var ui: Node2D
var post_rect: ColorRect

var menu_index := 0
var item_rects: Array = []       # [Rect2, index] or [Rect2, -1, Callable] for mouse support
var settings_return := S.TITLE
var credits_return := S.TITLE

var fade := 1.0
var fade_dir := -1.0
var fade_callback: Callable = Callable()

var death_timer := -1.0
var win_timer := -1.0
var level_deaths := 0
var card_time := 0.0
var last_new_best := false
var title_shift_timer := 0.0
var last_mouse := Vector2(-1, -1)
var input_provider: Callable = Callable()   # automated tests can feed inputs here
var ignore_jump_frames := 0                 # swallow the key press that closed a menu

var name_buf := ""
var name_return: Callable = Callable()
var shop_tab := 0                           # 0 skins, 1 weapons
var shop_msg := ""
var shop_msg_time := 0.0
var boss_bar_lag := 1.0
var preview_cache := {}


func _ready() -> void:
	view = LevelView.new()
	add_child(view)
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 1
	add_child(fx_layer)
	post_rect = ColorRect.new()
	post_rect.size = Vector2(W, H)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/post.gdshader")
	post_rect.material = mat
	fx_layer.add_child(post_rect)
	view.post = mat
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 2
	add_child(ui_layer)
	ui = Node2D.new()
	ui_layer.add_child(ui)
	ui.draw.connect(_draw_ui)
	view.shake_enabled = Game.screen_shake
	Sound.start_music()
	_enter_title()


func _exit_tree() -> void:
	PixelFont.release()


# ------------------------------------------------------------------ transitions

func go(callback: Callable) -> void:
	if fade_dir > 0.0:
		return
	fade_dir = 1.0
	fade_callback = callback


func set_state(s: S) -> void:
	state = s
	state_time = 0.0
	menu_index = 0


func _enter_title() -> void:
	set_state(S.TITLE)
	view.title_mode = true
	view.sim = null
	view.title_world = 0
	view.set_theme(0)
	view.particles.clear()
	view.name_tag = ""
	Sound.set_track("main")
	Sound.set_world(false)
	Sound.set_muffled(false)
	Sound.set_music_level(0.85)


func start_level(i: int) -> void:
	Game.current_level = i
	sim.weapon = Game.weapon_stats()
	sim.load_level(i)
	view.title_mode = false
	view.rebake_player()
	view.set_sim(sim)
	level_deaths = 0
	death_timer = -1.0
	win_timer = -1.0
	boss_bar_lag = 1.0
	card_time = 3.2 if sim.is_boss() else 2.6
	set_state(S.PLAY)
	ignore_jump_frames = 2
	if sim.is_boss():
		Sound.set_track("boss")
	else:
		Sound.set_track("theme2" if Levels.world_of(i) % 2 == 1 else "main")
	Sound.set_world(false, true)
	Sound.set_muffled(false)
	Sound.set_music_level(1.0)


func _ask_name(after: Callable) -> void:
	name_buf = Game.player_name
	name_return = after
	set_state(S.NAME)


# ------------------------------------------------------------------ main loop

func _process(delta: float) -> void:
	state_time += delta
	card_time = max(0.0, card_time - delta)
	shop_msg_time = max(0.0, shop_msg_time - delta)
	if fade_dir > 0.0:
		fade = min(1.0, fade + delta * 4.0)
		if fade >= 1.0:
			fade_dir = -1.0
			if fade_callback.is_valid():
				var cb := fade_callback
				fade_callback = Callable()
				cb.call()
	else:
		fade = max(0.0, fade - delta * 3.0)
	if state in [S.TITLE, S.SELECT, S.SETTINGS, S.CONTROLS, S.CREDITS, S.INTRO, S.ENDING, S.CONFIRM_RESET, S.NAME, S.SHOP] and view.title_mode:
		title_shift_timer += delta
		if title_shift_timer > 4.5:
			title_shift_timer = 0.0
			view.title_shift()
			Sound.set_menu_mix(0.35 if view.title_world == 1 else 0.0)
	if state == S.PLAY or state == S.PAUSE:
		view.name_tag = Game.player_name if sim.time < 2.5 and not sim.won else ""
		if sim.boss != null:
			var ratio := float(sim.boss.hp) / sim.boss.max_hp
			boss_bar_lag = move_toward(boss_bar_lag, ratio, delta * (0.4 if boss_bar_lag > ratio else 2.0))
	_mouse_hover()
	ui.queue_redraw()


func _physics_process(_delta: float) -> void:
	if state != S.PLAY:
		return
	if death_timer >= 0.0:
		death_timer -= 1.0 / 60.0
		if death_timer < 0.0:
			sim.respawn()
			view.on_respawn()
			boss_bar_lag = 1.0
		return
	if win_timer >= 0.0:
		win_timer -= 1.0 / 60.0
		if win_timer < 0.0:
			_finish_level()
		return
	var input := {
		"left": Input.is_action_pressed("move_left"),
		"right": Input.is_action_pressed("move_right"),
		"jump_pressed": Input.is_action_just_pressed("jump"),
		"jump_held": Input.is_action_pressed("jump"),
		"shift_pressed": Input.is_action_just_pressed("shift"),
		"fire": Input.is_action_pressed("fire"),
	}
	if ignore_jump_frames > 0:
		ignore_jump_frames -= 1
		input["jump_pressed"] = false
	if input_provider.is_valid():
		input = input_provider.call()
	view.before_step()
	sim.step(input)
	view.after_step()
	if sim.dead:
		level_deaths += 1
		death_timer = 1.1 if sim.is_boss() else 0.8
	elif sim.won:
		win_timer = 1.3
		Sound.set_music_level(0.5)


func _finish_level() -> void:
	view.name_tag = ""
	last_new_best = Game.complete_level(sim.level_index, sim.time, sim.shard_taken, level_deaths, sim.taken_indices())
	set_state(S.COMPLETE)
	if Game.last_earned > 0:
		Sound.play("buy")


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if fade_dir > 0.0:
		return
	if state == S.NAME:
		_input_name(event)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state != S.PLAY:
			_mouse_click()
		return
	match state:
		S.TITLE: _input_title(event)
		S.INTRO: _input_intro(event)
		S.SELECT: _input_select(event)
		S.SETTINGS: _input_settings(event)
		S.CONTROLS, S.CREDITS: _input_info(event)
		S.PLAY: _input_play(event)
		S.PAUSE: _input_pause(event)
		S.COMPLETE: _input_complete(event)
		S.ENDING: _input_ending(event)
		S.CONFIRM_RESET: _input_confirm(event)
		S.SHOP: _input_shop(event)


func _nav(event: InputEvent, count: int, horizontal: bool = false) -> bool:
	var prev := menu_index
	var up := "move_left" if horizontal else "move_up"
	var down := "move_right" if horizontal else "move_down"
	if event.is_action_pressed(up):
		menu_index = (menu_index - 1 + count) % count
	elif event.is_action_pressed(down):
		menu_index = (menu_index + 1) % count
	if prev != menu_index:
		Sound.play("menu_move")
		return true
	return false


func _confirm(event: InputEvent) -> bool:
	return event.is_action_pressed("confirm")


func _back(event: InputEvent) -> bool:
	return event.is_action_pressed("back")


# --- title

func _title_items() -> Array:
	var items := []
	if Game.has_progress():
		items.append(["CONTINUE", "continue"])
		items.append(["NEW GAME", "new"])
	else:
		items.append(["PLAY", "new"])
	items.append(["LEVEL SELECT", "select"])
	items.append(["SHOP", "shop"])
	items.append(["SETTINGS", "settings"])
	items.append(["CREDITS", "credits"])
	items.append(["QUIT", "quit"])
	return items


func _input_title(event: InputEvent) -> void:
	var items := _title_items()
	_nav(event, items.size())
	if _confirm(event):
		_activate_title(items[menu_index][1])


func _activate_title(action: String) -> void:
	Sound.play("menu_select")
	match action:
		"continue":
			var next := 0
			for i in Game.LEVEL_COUNT:
				if Game.is_unlocked(i) and not Game.completed.has(str(i)):
					next = i
					break
				next = i
			go(start_level.bind(next))
		"new":
			var begin := func():
				if Game.seen_intro:
					start_level(0)
				else:
					set_state(S.INTRO)
			if Game.player_name == "":
				go(_ask_name.bind(begin))
			elif Game.seen_intro:
				go(start_level.bind(0))
			else:
				go(func(): set_state(S.INTRO))
		"select":
			go(func():
				set_state(S.SELECT)
				menu_index = _first_open_stage())
		"shop":
			go(func():
				set_state(S.SHOP)
				shop_tab = 0
				menu_index = Game.skin)
		"settings":
			settings_return = S.TITLE
			go(func(): set_state(S.SETTINGS))
		"credits":
			credits_return = S.TITLE
			go(func(): set_state(S.CREDITS))
		"quit":
			go(func(): get_tree().quit())


func _first_open_stage() -> int:
	for i in Game.LEVEL_COUNT:
		if Game.is_unlocked(i) and not Game.completed.has(str(i)):
			return i
	return 0


func _input_intro(event: InputEvent) -> void:
	if _confirm(event) or _back(event) or event.is_action_pressed("jump"):
		Game.seen_intro = true
		Game.save_game()
		Sound.play("menu_select")
		go(start_level.bind(0))


# --- name entry

func _input_name(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_BACKSPACE:
				if name_buf.length() > 0:
					name_buf = name_buf.substr(0, name_buf.length() - 1)
					Sound.play("type")
				return
			KEY_ENTER, KEY_KP_ENTER:
				_confirm_name()
				return
			KEY_ESCAPE:
				if Game.player_name != "":
					Sound.play("menu_back")
					_leave_name()
				return
		if event.unicode >= 32 and not event.echo:
			var ch := char(event.unicode)
			if name_buf.length() < Game.NAME_MAX and PixelFont.has_glyph(ch) and not (ch == " " and name_buf == ""):
				name_buf += ch.to_upper()
				Sound.play("type", 0.1)
			else:
				Sound.play("blocked")
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_click()
		return
	if event.is_action_pressed("confirm"):
		if name_buf.strip_edges() == "":
			name_buf = "PLAYER"
		_confirm_name()


func _confirm_name() -> void:
	var n := name_buf.strip_edges()
	if n == "":
		Sound.play("blocked")
		return
	Game.player_name = n
	Game.save_game()
	Sound.play("menu_select")
	_leave_name()


func _leave_name() -> void:
	if name_return.is_valid():
		var cb := name_return
		name_return = Callable()
		go(cb)
	else:
		go(_enter_title)


# --- level select

func _input_select(event: InputEvent) -> void:
	var prev := menu_index
	var pos := menu_index % PER_PAGE
	var page := menu_index / PER_PAGE
	if event.is_action_pressed("move_left"):
		menu_index = max(0, menu_index - 1)
	elif event.is_action_pressed("move_right"):
		menu_index = min(Game.LEVEL_COUNT - 1, menu_index + 1)
	elif event.is_action_pressed("move_up"):
		if pos >= 6:
			menu_index -= 6
		else:
			menu_index = max(0, menu_index - PER_PAGE)
	elif event.is_action_pressed("move_down"):
		if pos + 6 < PER_PAGE:
			menu_index += 6
		else:
			menu_index = min(Game.LEVEL_COUNT - 1, (page + 1) * PER_PAGE + pos % 6)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_PAGEUP:
		menu_index = max(0, menu_index - PER_PAGE)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_PAGEDOWN:
		menu_index = min(Game.LEVEL_COUNT - 1, menu_index + PER_PAGE)
	if prev != menu_index:
		Sound.play("menu_move")
	if _confirm(event):
		_pick_level(menu_index)
	elif _back(event):
		Sound.play("menu_back")
		go(_enter_title)


func _pick_level(i: int) -> void:
	if Game.is_unlocked(i):
		Sound.play("menu_select")
		go(start_level.bind(i))
	else:
		Sound.play("blocked")


func _turn_page(d: int) -> void:
	var page := clampi(menu_index / PER_PAGE + d, 0, Levels.WORLDS - 1)
	menu_index = page * PER_PAGE
	Sound.play("menu_move")


# --- shop

func _shop_list() -> Array:
	return Game.SKINS if shop_tab == 0 else Game.WEAPONS


func _input_shop(event: InputEvent) -> void:
	var list := _shop_list()
	_nav(event, list.size())
	if event.is_action_pressed("move_left") or event.is_action_pressed("move_right"):
		_set_shop_tab(1 - shop_tab)
	elif _confirm(event):
		_shop_buy(menu_index)
	elif _back(event):
		Sound.play("menu_back")
		go(_enter_title)


func _set_shop_tab(t: int) -> void:
	if t == shop_tab:
		return
	shop_tab = t
	menu_index = Game.skin if t == 0 else Game.weapon
	shop_msg = ""
	Sound.play("menu_move")


func _shop_buy(i: int) -> void:
	var kind := "skin" if shop_tab == 0 else "weapon"
	var res := Game.shop_action(kind, i)
	match res:
		"poor":
			Sound.play("blocked")
			shop_msg = "NOT ENOUGH TOKENS"
		"bought":
			Sound.play("buy")
			shop_msg = "BOUGHT & EQUIPPED!"
		"equipped":
			Sound.play("menu_select")
			shop_msg = "EQUIPPED"
	shop_msg_time = 1.6
	if kind == "skin":
		view.rebake_player()


# --- settings

func _settings_items() -> Array:
	return [
		["MUSIC VOLUME", "music", "%d" % roundi(Game.music_volume * 10)],
		["SOUND VOLUME", "sfx", "%d" % roundi(Game.sfx_volume * 10)],
		["FULLSCREEN", "fullscreen", "ON" if Game.fullscreen else "OFF"],
		["SCREEN SHAKE", "shake", "ON" if Game.screen_shake else "OFF"],
		["SPEEDRUN TIMER", "timer", "ON" if Game.show_timer else "OFF"],
		["PLAYER NAME", "name", Game.player_name if Game.player_name != "" else "-"],
		["CONTROLS", "controls", ""],
		["RESET PROGRESS", "reset", ""],
		["BACK", "back", ""],
	]


func _input_settings(event: InputEvent) -> void:
	var items := _settings_items()
	_nav(event, items.size())
	var action: String = items[menu_index][1]
	var dir := 0
	if event.is_action_pressed("move_left"):
		dir = -1
	elif event.is_action_pressed("move_right"):
		dir = 1
	if dir != 0:
		_adjust_setting(action, dir)
	elif _confirm(event):
		_adjust_setting(action, 0)
	elif _back(event):
		_leave_settings()


func _adjust_setting(action: String, dir: int) -> void:
	match action:
		"music":
			Game.music_volume = _step_volume(Game.music_volume, dir)
		"sfx":
			Game.sfx_volume = _step_volume(Game.sfx_volume, dir)
		"fullscreen":
			Game.fullscreen = not Game.fullscreen
			Game.apply_display()
		"shake":
			Game.screen_shake = not Game.screen_shake
			view.shake_enabled = Game.screen_shake
		"timer":
			Game.show_timer = not Game.show_timer
		"name":
			if dir == 0:
				Sound.play("menu_select")
				var ret := settings_return
				var back := func():
					set_state(S.SETTINGS)
					settings_return = ret
					menu_index = 5
				_ask_name(back)
			return
		"controls":
			if dir == 0:
				Sound.play("menu_select")
				set_state(S.CONTROLS)
			return
		"reset":
			if dir == 0:
				Sound.play("menu_select")
				set_state(S.CONFIRM_RESET)
				menu_index = 1
			return
		"back":
			if dir == 0:
				_leave_settings()
			return
	Sound.apply_volumes()
	Game.save_game()
	Sound.play("menu_move")


func _step_volume(v: float, dir: int) -> float:
	if dir == 0:
		v = 0.0 if v >= 0.95 else v + 0.1
	else:
		v += 0.1 * dir
	return snappedf(clampf(v, 0.0, 1.0), 0.1)


func _leave_settings() -> void:
	Sound.play("menu_back")
	Game.save_game()
	if settings_return == S.PAUSE:
		set_state(S.PAUSE)
		menu_index = 2
	else:
		go(_enter_title)


func _input_confirm(event: InputEvent) -> void:
	_nav(event, 2, true)
	_nav(event, 2)
	if _confirm(event):
		if menu_index == 0:
			Game.reset_progress()
			view.rebake_player()
			Sound.play("die")
		else:
			Sound.play("menu_back")
		set_state(S.SETTINGS)
		menu_index = 7
	elif _back(event):
		Sound.play("menu_back")
		set_state(S.SETTINGS)
		menu_index = 7


func _input_info(event: InputEvent) -> void:
	if _confirm(event) or _back(event):
		Sound.play("menu_back")
		if state == S.CONTROLS:
			set_state(S.SETTINGS)
			menu_index = 6
		elif credits_return == S.ENDING or credits_return == S.TITLE:
			go(_enter_title)


# --- gameplay

func _input_play(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_pause()
	elif event.is_action_pressed("restart") and win_timer < 0.0:
		go(start_level.bind(sim.level_index))


func _pause() -> void:
	Sound.play("menu_select")
	Sound.set_muffled(true)
	set_state(S.PAUSE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and state == S.PLAY and win_timer < 0.0:
		_pause()


func _pause_items() -> Array:
	return [["RESUME", "resume"], ["RESTART LEVEL", "restart"], ["SETTINGS", "settings"], ["LEVEL SELECT", "select"], ["MAIN MENU", "title"]]


func _input_pause(event: InputEvent) -> void:
	var items := _pause_items()
	_nav(event, items.size())
	if event.is_action_pressed("pause") and state_time > 0.1:
		_activate_pause("resume")
	elif _confirm(event):
		_activate_pause(items[menu_index][1])


func _activate_pause(action: String) -> void:
	match action:
		"resume":
			Sound.play("menu_back")
			Sound.set_muffled(false)
			set_state(S.PLAY)
			card_time = 0.0
			ignore_jump_frames = 2
		"restart":
			Sound.play("menu_select")
			go(start_level.bind(sim.level_index))
		"settings":
			Sound.play("menu_select")
			settings_return = S.PAUSE
			set_state(S.SETTINGS)
		"select":
			Sound.play("menu_select")
			go(func():
				_enter_title()
				set_state(S.SELECT)
				menu_index = sim.level_index)
		"title":
			Sound.play("menu_back")
			go(_enter_title)


func _complete_items() -> Array:
	if sim.level_index == Game.LEVEL_COUNT - 1:
		return [["CONTINUE", "ending"], ["RETRY", "retry"], ["LEVEL SELECT", "select"]]
	return [["NEXT LEVEL" if not Levels.is_boss(sim.level_index + 1) else "FACE THE BOSS", "next"], ["RETRY", "retry"], ["LEVEL SELECT", "select"]]


func _input_complete(event: InputEvent) -> void:
	if state_time < 0.4:
		return
	var items := _complete_items()
	_nav(event, items.size())
	if _confirm(event):
		_activate_complete(items[menu_index][1])


func _activate_complete(action: String) -> void:
	Sound.play("menu_select")
	match action:
		"next":
			go(start_level.bind(sim.level_index + 1))
		"retry":
			go(start_level.bind(sim.level_index))
		"select":
			go(func():
				_enter_title()
				set_state(S.SELECT)
				menu_index = min(sim.level_index + 1, Game.LEVEL_COUNT - 1))
		"ending":
			go(func():
				_enter_title()
				set_state(S.ENDING))


func _input_ending(event: InputEvent) -> void:
	if state_time > 2.0 and (_confirm(event) or _back(event)):
		Sound.play("menu_select")
		credits_return = S.ENDING
		go(func(): set_state(S.CREDITS))


# ------------------------------------------------------------------ mouse

func _mouse_hover() -> void:
	var m := ui.get_local_mouse_position()
	if m == last_mouse:
		return
	last_mouse = m
	for r in item_rects:
		if r[1] >= 0 and r[0].has_point(m) and menu_index != r[1]:
			menu_index = r[1]
			Sound.play("menu_move")


func _mouse_click() -> void:
	var m := ui.get_local_mouse_position()
	for r in item_rects:
		if r[0].has_point(m):
			if r.size() > 2:
				r[2].call()
				return
			menu_index = r[1]
			var ev := InputEventAction.new()
			ev.action = "confirm"
			ev.pressed = true
			_unhandled_input(ev)
			return


# ------------------------------------------------------------------ UI drawing

func _draw_ui() -> void:
	item_rects.clear()
	match state:
		S.TITLE: _draw_title()
		S.INTRO: _draw_text_screen(INTRO_LINES, "PRESS ENTER")
		S.SELECT: _draw_select()
		S.SETTINGS: _draw_settings()
		S.CONTROLS: _draw_controls()
		S.CREDITS: _draw_credits()
		S.PLAY: _draw_hud()
		S.PAUSE:
			_draw_hud()
			_draw_pause()
		S.COMPLETE:
			_draw_complete()
		S.ENDING: _draw_ending()
		S.CONFIRM_RESET: _draw_confirm()
		S.NAME: _draw_name()
		S.SHOP: _draw_shop()
	if fade > 0.0:
		ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, _smooth(fade)))


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _accent() -> Color:
	var w := view.world_shown()
	return COL_LIGHT if w == 0 else COL_DARK


func _panel(r: Rect2, accent: Color = Color(0, 0, 0, 0)) -> void:
	if accent.a == 0.0:
		accent = _accent()
	ui.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), Color(0, 0, 0, 0.35))
	ui.draw_rect(r, COL_PANEL)
	ui.draw_rect(r, accent.darkened(0.35), false, 1.0)
	ui.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 1)), accent)


func _text(t: String, pos: Vector2, col: Color = COL_TEXT, scale: int = 1) -> void:
	PixelFont.draw(ui, t, pos, col, scale, Color(0, 0, 0, 0.6))


func _ctext(t: String, y: float, col: Color = COL_TEXT, scale: int = 1, cx: float = W / 2.0) -> void:
	PixelFont.draw_centered(ui, t, cx, y, col, scale, Color(0, 0, 0, 0.6))


func _menu(items: Array, cx: float, y0: float, spacing: float = 14.0) -> void:
	for i in items.size():
		var label: String = items[i][0]
		var y := y0 + i * spacing
		var sel := i == menu_index
		var col := COL_TEXT if sel else COL_DIM
		var wdt := PixelFont.text_width(label)
		var x := floorf(cx - wdt / 2.0)
		if sel:
			var a := _accent()
			var bob := 1.0 if fmod(state_time * 2.0, 1.0) < 0.5 else 0.0
			ui.draw_rect(Rect2(x - 14, y - 3, wdt + 28, 13), Color(a.r, a.g, a.b, 0.18))
			_text(">", Vector2(x - 10 + bob, y), a)
			_text("<", Vector2(x + wdt + 6 - bob, y), a)
		_text(label, Vector2(x, y), col)
		item_rects.append([Rect2(x - 16, y - 3, wdt + 32, 13), i])


func _draw_coin(c: Vector2, r: float = 3.5) -> void:
	ui.draw_circle(c, r + 0.8, Color("a8740a"))
	ui.draw_circle(c, r, COL_COIN)
	ui.draw_circle(c + Vector2(-1, -1), r * 0.4, Color("fff6c0"))


## Draws a coin followed by a number; returns the width used.
func _coin_text(t: String, pos: Vector2, col: Color = COL_COIN) -> float:
	_draw_coin(pos + Vector2(4, 3.5))
	_text(t, pos + Vector2(11, 0), col)
	return 11.0 + PixelFont.text_width(t)


func _draw_wallet() -> void:
	var t := str(Game.tokens)
	var wdt := 11.0 + PixelFont.text_width(t)
	ui.draw_rect(Rect2(W - wdt - 14, 4, wdt + 10, 13), Color(0.02, 0.0, 0.04, 0.6))
	_coin_text(t, Vector2(W - wdt - 9, 7))


func _draw_logo(y: float, scale: int = 5) -> void:
	var t := state_time
	var title := "SHIFT"
	var cx := W / 2.0
	var glitch := 0.0
	if fmod(t, 4.5) > 4.35:
		glitch = randf_range(-3, 3)
	var tw := PixelFont.text_width(title, scale)
	var x := floorf(cx - tw / 2.0)
	PixelFont.draw(ui, title, Vector2(x - 2 + glitch, y), Color(COL_LIGHT.r, COL_LIGHT.g, COL_LIGHT.b, 0.9), scale)
	PixelFont.draw(ui, title, Vector2(x + 2 - glitch, y + 1), Color(COL_DARK.r, COL_DARK.g, COL_DARK.b, 0.9), scale)
	PixelFont.draw(ui, title, Vector2(x, y), Color.WHITE, scale)
	var sub := "WORLDS"
	var sw := PixelFont.text_width(sub, 2)
	var sx := floorf(cx - sw / 2.0)
	var half := sx + sw / 2.0
	PixelFont.draw(ui, sub, Vector2(sx, y + 7 * scale + 6), Color("0b0410"), 2)
	var lx := sx
	for ch in sub:
		var cw := PixelFont.text_width(ch, 2)
		var col := Color("d9e4ff") if lx + cw / 2.0 < half else Color("ff5577")
		PixelFont.draw(ui, ch, Vector2(lx, y + 7 * scale + 5), col, 2)
		lx += cw + 2


func _draw_title() -> void:
	_draw_logo(26)
	var items := _title_items()
	_panel(Rect2(W / 2.0 - 70, 102, 140, items.size() * 14 + 12))
	_menu(items, W / 2.0, 109)
	_text("V" + Game.VERSION, Vector2(6, H - 12), COL_DIM)
	var tag := "110 LEVELS  -  11 BOSSES"
	_text(tag, Vector2(W - 6 - PixelFont.text_width(tag), H - 12), COL_DIM)
	if Game.player_name != "":
		ui.draw_rect(Rect2(4, 4, PixelFont.text_width(Game.player_name) + 30, 13), Color(0.02, 0.0, 0.04, 0.6))
		_draw_person(Vector2(9, 6))
		_text(Game.player_name, Vector2(19, 7), COL_TEXT)
	_draw_wallet()
	if Game.has_progress():
		_ctext("LEVELS %d/110   BOSSES %d/11   SHARDS %d/10" % [_levels_done(), Game.bosses_count(), Game.shard_count()], H - 26, COL_DIM)


func _draw_person(p: Vector2) -> void:
	ui.draw_rect(Rect2(p + Vector2(2, 0), Vector2(4, 4)), COL_TEXT)
	ui.draw_rect(Rect2(p + Vector2(0, 5), Vector2(8, 4)), COL_TEXT)


func _levels_done() -> int:
	var n := 0
	for k in Game.completed:
		if not Levels.is_boss(int(k)):
			n += 1
	return n


func _draw_text_screen(lines: Array, prompt: String) -> void:
	ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, 0.6))
	var y := 70.0
	for i in lines.size():
		var a: float = clamp((state_time - i * 0.8) / 0.6, 0.0, 1.0)
		_ctext(lines[i], y + i * 18, Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, a))
	if state_time > lines.size() * 0.8 and fmod(state_time, 1.0) < 0.7:
		_ctext(prompt, H - 40, _accent())


func _draw_name() -> void:
	ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, 0.55))
	var r := Rect2(110, 70, 260, 130)
	_panel(r)
	_ctext("WHAT IS YOUR NAME?", 84, COL_TEXT, 2)
	var box := Rect2(150, 112, 180, 22)
	ui.draw_rect(box, Color(0, 0, 0, 0.5))
	ui.draw_rect(box, _accent(), false, 1.0)
	var shown := name_buf
	var tw := PixelFont.text_width(shown, 2)
	var tx := floorf(W / 2.0 - tw / 2.0)
	PixelFont.draw(ui, shown, Vector2(tx, 116), Color.WHITE, 2, Color(0, 0, 0, 0.6))
	if fmod(state_time, 1.0) < 0.55:
		ui.draw_rect(Rect2(tx + tw + 2, 116, 2, 14), _accent())
	_ctext("%d / %d" % [name_buf.length(), Game.NAME_MAX], 140, COL_DIM)
	var ok := Rect2(W / 2.0 - 30, 158, 60, 16)
	var hover := ok.has_point(ui.get_local_mouse_position())
	ui.draw_rect(ok, Color(_accent().r, _accent().g, _accent().b, 0.35 if hover else 0.2))
	ui.draw_rect(ok, _accent(), false, 1.0)
	_ctext("OK", 163, COL_TEXT)
	item_rects.append([ok, -1, _confirm_name])
	_ctext("TYPE YOUR NAME  (LATIN OR CYRILLIC)    ENTER: SAVE    BACKSPACE: ERASE", H - 30, COL_DIM)
	if Game.player_name != "":
		_ctext("ESC: CANCEL", H - 16, COL_DIM)


func _draw_select() -> void:
	var page := menu_index / PER_PAGE
	var theme_name: String = Levels.THEMES[page]
	_ctext("WORLD %d: %s" % [page + 1, theme_name.to_upper()], 10, COL_TEXT, 2)
	_draw_wallet()
	# page arrows
	for d in [-1, 1]:
		var ar := Rect2(8 if d < 0 else W - 26, 8, 18, 16)
		var enabled: bool = (page > 0) if d < 0 else (page < Levels.WORLDS - 1)
		if d > 0:
			ar.position.y = 26
		var col := COL_TEXT if enabled else Color("3a2f5a")
		_text("<<" if d < 0 else ">>", ar.position + Vector2(3, 4), col)
		if enabled:
			item_rects.append([ar, -1, _turn_page.bind(d)])
	var cw := 70.0
	var ch := 72.0
	var gap := 6.0
	var x0 := (W - (6 * cw + 5 * gap)) / 2.0
	var y0 := 36.0
	for k in PER_PAGE:
		var i := page * PER_PAGE + k
		var col := k % 6
		var row := k / 6
		var r := Rect2(x0 + col * (cw + gap), y0 + row * (ch + gap), cw, ch)
		if k == PER_PAGE - 1:
			r = Rect2(x0 + 5 * (cw + gap), y0 + (ch + gap), cw, ch)
		var unlocked := Game.is_unlocked(i)
		var sel := i == menu_index
		var boss := Levels.is_boss(i)
		var accent := COL_DARK if boss else (COL_LIGHT if k % 2 == 0 else Color("9b7bff"))
		_panel(r, accent if sel else Color("3a2f5a"))
		if sel:
			ui.draw_rect(r.grow(1), accent, false, 1.0)
		item_rects.append([r, i])
		var c := r.get_center().x
		var key := str(i)
		if not unlocked:
			_draw_lock(Vector2(c, r.position.y + 28))
			PixelFont.draw_centered(ui, "BOSS" if boss else "LOCKED", c, r.end.y - 14, Color("5a5078"))
			continue
		if boss:
			_draw_big_skull(Vector2(c, r.position.y + 16), COL_DARK if not Game.completed.has(key) else COL_GOLD)
			PixelFont.draw_centered(ui, "BOSS", c, r.position.y + 32, COL_DARK)
			var lines := PixelFont.wrap(Levels.BOSSES[i / PER_PAGE]["name"], int(cw) - 6)
			for j in lines.size():
				PixelFont.draw_centered(ui, lines[j], c, r.position.y + 43 + j * 9, COL_TEXT if sel else COL_DIM)
		else:
			PixelFont.draw_centered(ui, str(Levels.number(i)), c, r.position.y + 6, Color.WHITE if sel else COL_TEXT, 2)
			var name: String = Levels.get_normal(Levels.normal_index(i))["name"]
			var lines := PixelFont.wrap(name, int(cw) - 6)
			for j in mini(lines.size(), 2):
				PixelFont.draw_centered(ui, lines[j], c, r.position.y + 26 + j * 9, COL_TEXT if sel else COL_DIM)
			var total := Levels.token_count(i)
			if total > 0:
				var found := Game.tokens_found(i)
				var tt := "%d/%d" % [found, total]
				var tw := 11.0 + PixelFont.text_width(tt)
				_coin_text(tt, Vector2(c - tw / 2.0, r.end.y - 23), COL_COIN if found == total else COL_DIM)
		if Game.completed.has(key):
			var by := r.end.y - 11
			if Game.best_times.has(key):
				var bt := Game.format_time(float(Game.best_times[key]))
				PixelFont.draw(ui, bt, Vector2(r.end.x - 5 - PixelFont.text_width(bt), by), COL_DIM)
			_draw_check(Vector2(r.position.x + 5, by))
			if i < 10:
				_draw_shard_icon(Vector2(r.position.x + 15, by - 1), Game.shards.has(key))
	# page dots
	for p in Levels.WORLDS:
		var dc := COL_TEXT if p == page else Color("3a2f5a")
		ui.draw_rect(Rect2(W / 2.0 - Levels.WORLDS * 5 + p * 10, 196, 6, 3), dc)
	# info about the selected stage
	var info := ""
	if Game.is_unlocked(menu_index):
		if Levels.is_boss(menu_index):
			info = "BOSS: %s - %s" % [Levels.BOSSES[menu_index / PER_PAGE]["name"].to_upper(), Levels.BOSSES[menu_index / PER_PAGE]["title"].to_upper()]
		else:
			info = "LEVEL %d: %s" % [Levels.number(menu_index), Levels.get_normal(Levels.normal_index(menu_index))["name"].to_upper()]
	else:
		info = "FINISH THE PREVIOUS STAGE TO UNLOCK"
	_ctext(info, 210, COL_GOLD)
	_ctext("LEVELS %d/110   BOSSES %d/11" % [_levels_done(), Game.bosses_count()], 226, COL_DIM)
	_ctext("ARROWS: CHOOSE   PGUP/PGDN: WORLD   ENTER: PLAY   ESC: BACK", H - 14, COL_DIM)


func _draw_check(p: Vector2) -> void:
	var c := Color("7dff9a")
	ui.draw_rect(Rect2(p + Vector2(0, 3), Vector2(2, 2)), c)
	ui.draw_rect(Rect2(p + Vector2(2, 5), Vector2(2, 2)), c)
	ui.draw_rect(Rect2(p + Vector2(4, 3), Vector2(2, 2)), c)
	ui.draw_rect(Rect2(p + Vector2(6, 1), Vector2(2, 2)), c)


func _draw_big_skull(c: Vector2, col: Color) -> void:
	ui.draw_circle(c, 8.0, col)
	ui.draw_rect(Rect2(c + Vector2(-5, 4), Vector2(10, 6)), col)
	ui.draw_rect(Rect2(c + Vector2(-5, -2), Vector2(4, 4)), Color("1a1030"))
	ui.draw_rect(Rect2(c + Vector2(1, -2), Vector2(4, 4)), Color("1a1030"))
	ui.draw_rect(Rect2(c + Vector2(-1, 3), Vector2(2, 2)), Color("1a1030"))
	for i in 3:
		ui.draw_rect(Rect2(c + Vector2(-4 + i * 3, 8), Vector2(1, 2)), Color("1a1030"))


func _draw_shard_icon(p: Vector2, got: bool) -> void:
	var col := COL_GOLD if got else Color(0.5, 0.45, 0.65, 0.6)
	var pts := PackedVector2Array([p + Vector2(3, 0), p + Vector2(6, 4), p + Vector2(3, 8), p + Vector2(0, 4)])
	if got:
		ui.draw_colored_polygon(pts, col)
		ui.draw_rect(Rect2(p + Vector2(2, 2), Vector2(1, 2)), Color.WHITE)
	else:
		pts.append(pts[0])
		ui.draw_polyline(pts, col, 1.0)


func _draw_lock(c: Vector2) -> void:
	var col := Color("5a5078")
	ui.draw_rect(Rect2(c + Vector2(-6, -2), Vector2(12, 9)), col)
	ui.draw_rect(Rect2(c + Vector2(-4, -8), Vector2(2, 6)), col)
	ui.draw_rect(Rect2(c + Vector2(2, -8), Vector2(2, 6)), col)
	ui.draw_rect(Rect2(c + Vector2(-4, -9), Vector2(8, 2)), col)
	ui.draw_rect(Rect2(c + Vector2(-1, 1), Vector2(2, 3)), Color("1a1030"))


# --- shop

func _skin_preview(idx: int, w: int) -> ImageTexture:
	var key := "%d_%d" % [idx, w]
	if not preview_cache.has(key):
		var pal: Dictionary = Game.skin_palettes(idx)[w]
		var img := Image.create(12, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var rows: Array = LevelView.PLAYER_FRAMES["body"].duplicate()
		rows.append_array(LevelView.PLAYER_FRAMES["idle"])
		for y in rows.size():
			for x in 12:
				var ch: String = rows[y][x]
				if pal.has(ch):
					img.set_pixel(x, y, pal[ch])
		preview_cache[key] = ImageTexture.create_from_image(img)
	return preview_cache[key]


func _draw_shop() -> void:
	ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, 0.45))
	_ctext("SHOP", 8, COL_GOLD, 2)
	_draw_wallet()
	# tabs
	var tabs := ["SKINS", "WEAPONS"]
	for t in 2:
		var tr := Rect2(16 + t * 106, 28, 100, 16)
		var sel := t == shop_tab
		ui.draw_rect(tr, Color(_accent().r, _accent().g, _accent().b, 0.3 if sel else 0.08))
		ui.draw_rect(tr, _accent() if sel else Color("3a2f5a"), false, 1.0)
		_ctext(tabs[t], 33, COL_TEXT if sel else COL_DIM, 1, tr.get_center().x)
		item_rects.append([tr, -1, _set_shop_tab.bind(t)])
	var list := _shop_list()
	var lr := Rect2(16, 48, 206, 196)
	_panel(lr)
	var owned: Array = Game.owned_skins if shop_tab == 0 else Game.owned_weapons
	var equipped := Game.skin if shop_tab == 0 else Game.weapon
	for i in list.size():
		var y := lr.position.y + 8 + i * 22
		var row := Rect2(lr.position.x + 4, y - 3, lr.size.x - 8, 19)
		var sel := i == menu_index
		if sel:
			var a := _accent()
			ui.draw_rect(row, Color(a.r, a.g, a.b, 0.2))
			ui.draw_rect(row, a, false, 1.0)
		item_rects.append([row, i])
		_text(list[i]["name"].to_upper(), Vector2(row.position.x + 6, y + 3), COL_TEXT if sel else COL_DIM)
		var right := ""
		var rc := COL_DIM
		if i == equipped:
			right = "EQUIPPED"
			rc = Color("7dff9a")
		elif owned.has(i):
			right = "OWNED"
		if right != "":
			_text(right, Vector2(row.end.x - 6 - PixelFont.text_width(right), y + 3), rc)
		else:
			var pt := str(list[i]["price"])
			var tw := 11.0 + PixelFont.text_width(pt)
			_coin_text(pt, Vector2(row.end.x - 6 - tw, y + 3), COL_COIN if Game.tokens >= int(list[i]["price"]) else Color("8a6a40"))
	# preview
	var pr := Rect2(230, 48, 234, 196)
	_panel(pr)
	var item: Dictionary = list[menu_index]
	_ctext(item["name"].to_upper(), pr.position.y + 8, COL_TEXT, 2, pr.get_center().x)
	if shop_tab == 0:
		for w in 2:
			var cx := pr.position.x + 62 + w * 110
			var cy := pr.position.y + 50
			var bg := Rect2(cx - 44, cy - 10, 88, 112)
			ui.draw_rect(bg, Color("dfe4ff") if w == 0 else Color("14061e"))
			ui.draw_rect(bg, COL_LIGHT if w == 0 else COL_DARK, false, 1.0)
			var tex := _skin_preview(menu_index, w)
			var pal: Dictionary = Game.skin_palettes(menu_index)[w]
			var sc := 5.0
			var bob := sin(state_time * 3.0 + w) * 2.0
			var origin := Vector2(cx, cy + 90 + bob)
			ui.draw_set_transform(origin, 0.0, Vector2(sc, sc))
			ui.draw_texture(tex, Vector2(-6, -16))
			view._draw_accessory(item["acc"], pal, w, ui)
			ui.draw_set_transform(Vector2.ZERO)
			_ctext("LIGHT" if w == 0 else "DARK", bg.end.y + 4, COL_LIGHT if w == 0 else COL_DARK, 1, cx)
	else:
		var stats := [
			["DAMAGE", float(item["dmg"]) / 7.0, str(item["dmg"])],
			["FIRE RATE", clampf((1.0 / float(item["cd"])) / 12.0, 0.05, 1.0), "%.1f/S" % (1.0 / float(item["cd"]))],
			["SHOTS", float(item["count"]) / 5.0, str(item["count"])],
			["DPS", clampf(float(item["dmg"]) * float(item["count"]) / float(item["cd"]) / 20.0, 0.03, 1.0), "%d" % roundi(float(item["dmg"]) * float(item["count"]) / float(item["cd"]))],
		]
		for i in stats.size():
			var y := pr.position.y + 34 + i * 18
			_text(stats[i][0], Vector2(pr.position.x + 10, y), COL_DIM)
			var bar := Rect2(pr.position.x + 84, y, 100, 7)
			ui.draw_rect(bar, Color("2a2140"))
			ui.draw_rect(Rect2(bar.position, Vector2(bar.size.x * clampf(stats[i][1], 0.0, 1.0), bar.size.y)), Color(item["color"]))
			_text(stats[i][2], Vector2(bar.end.x + 6, y), COL_TEXT)
		if item["pierce"]:
			_ctext("PIERCES THROUGH TARGETS", pr.position.y + 110, COL_GOLD, 1, pr.get_center().x)
		# firing range demo
		var range_r := Rect2(pr.position.x + 10, pr.position.y + 124, pr.size.x - 20, 60)
		ui.draw_rect(range_r, Color(0, 0, 0, 0.4))
		var gx := range_r.position.x + 12
		var gy := range_r.get_center().y
		ui.draw_rect(Rect2(gx - 6, gy - 2, 12, 4), Color("8f86b8"))
		ui.draw_rect(Rect2(gx + 2, gy - 1, 6, 2), Color(item["color"]))
		var period := float(item["cd"])
		var col := Color(item["color"])
		var n := int(item["count"])
		var spread := deg_to_rad(float(item["spread"]))
		for shot in 8:
			var age := fmod(state_time, period) + shot * period
			var dist := age * float(item["speed"]) * 0.5
			if dist > range_r.size.x - 20:
				continue
			for k in n:
				var a := 0.0
				if n > 1:
					a = -spread / 2.0 + spread * k / float(n - 1)
				var off := 0.0
				if n > 1 and float(item["spread"]) < 8.0:
					off = (k - (n - 1) / 2.0) * 5.0
				var p := Vector2(gx + 10 + cos(a) * dist, gy + off + sin(a) * dist)
				if range_r.has_point(p):
					ui.draw_circle(p, float(item["size"]) + 1.5, Color(col.r, col.g, col.b, 0.3))
					ui.draw_circle(p, float(item["size"]), col)
	var owned_now: bool = owned.has(menu_index)
	var hint := "ENTER: EQUIP" if owned_now else "ENTER: BUY FOR %d TOKENS" % int(item["price"])
	if menu_index == equipped:
		hint = "EQUIPPED"
	_ctext(hint, pr.end.y - 12, COL_GOLD if not owned_now else COL_TEXT, 1, pr.get_center().x)
	if shop_msg_time > 0.0:
		_ctext(shop_msg, 250, COL_GOLD if shop_msg != "NOT ENOUGH TOKENS" else COL_DARK)
	else:
		_ctext("WEAPONS ARE USED IN BOSS FIGHTS.  COLLECT TOKENS IN LEVELS TO BUY MORE.", 250, COL_DIM)
	_ctext("UP/DOWN: CHOOSE   LEFT/RIGHT: TAB   ENTER: BUY/EQUIP   ESC: BACK", H - 10, COL_DIM)


func _draw_settings() -> void:
	if settings_return == S.PAUSE:
		ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, 0.55))
	var r := Rect2(110, 22, 260, 228)
	_panel(r)
	_ctext("SETTINGS", 32, COL_TEXT, 2)
	var items := _settings_items()
	for i in items.size():
		var y := 60.0 + i * 19.0
		var sel := i == menu_index
		var col := COL_TEXT if sel else COL_DIM
		if sel:
			var a := _accent()
			ui.draw_rect(Rect2(r.position.x + 8, y - 4, r.size.x - 16, 15), Color(a.r, a.g, a.b, 0.18))
			_text(">", Vector2(r.position.x + 12, y), a)
		_text(items[i][0], Vector2(r.position.x + 24, y), col)
		var v: String = items[i][2]
		var action: String = items[i][1]
		if action == "music" or action == "sfx":
			var level := int(v)
			for k in 10:
				var bx := r.end.x - 108 + k * 8
				ui.draw_rect(Rect2(bx, y, 6, 7), (_accent() if k < level else Color("2a2140")))
			_text(v, Vector2(r.end.x - 24, y), col)
		elif action == "name":
			_text(v, Vector2(r.end.x - 14 - PixelFont.text_width(v), y), COL_GOLD if sel else COL_DIM)
		elif v != "":
			var vc := (_accent() if v == "ON" else COL_DIM) if sel else COL_DIM
			_text("< " + v + " >" if sel else v, Vector2(r.end.x - 20 - PixelFont.text_width("< " + v + " >" if sel else v), y), vc)
		item_rects.append([Rect2(r.position.x + 8, y - 4, r.size.x - 16, 15), i])
	_ctext("LEFT/RIGHT: CHANGE    ENTER: SELECT    ESC: BACK", H - 12, COL_DIM)


func _draw_confirm() -> void:
	var r := Rect2(120, 90, 240, 90)
	_panel(r, COL_DARK)
	_ctext("ERASE ALL PROGRESS?", 104, COL_TEXT)
	_ctext("Levels, tokens and shop items. Cannot be undone.", 120, COL_DIM)
	var labels := ["YES, ERASE", "CANCEL"]
	for i in 2:
		var cx := 190.0 + i * 100.0
		var sel := i == menu_index
		var wdt := PixelFont.text_width(labels[i])
		var br := Rect2(cx - wdt / 2.0 - 8, 148, wdt + 16, 15)
		if sel:
			ui.draw_rect(br, Color(COL_DARK.r, COL_DARK.g, COL_DARK.b, 0.3))
			ui.draw_rect(br, COL_DARK, false, 1.0)
		_ctext(labels[i], 152, COL_TEXT if sel else COL_DIM, 1, cx)
		item_rects.append([br, i])


func _draw_controls() -> void:
	var r := Rect2(60, 20, 360, 234)
	_panel(r)
	_ctext("CONTROLS", 30, COL_TEXT, 2)
	var rows := [
		["MOVE", "A / D  or  ARROW KEYS", "LEFT STICK / D-PAD"],
		["JUMP", "SPACE  (W, UP, Z)", "A / CROSS"],
		["SHIFT WORLDS", "SHIFT  (X, K)", "X / SQUARE, BUMPERS"],
		["SHOOT (BOSSES)", "J / F / C / CTRL / CLICK", "B / CIRCLE, R TRIGGER"],
		["RESTART LEVEL", "R", "Y / TRIANGLE"],
		["PAUSE", "ESC  or  P", "START"],
		["FULLSCREEN", "F11", "-"],
	]
	_text("ACTION", Vector2(72, 58), _accent())
	_text("KEYBOARD", Vector2(166, 58), _accent())
	_text("GAMEPAD", Vector2(306, 58), _accent())
	for i in rows.size():
		var y := 74 + i * 15
		_text(rows[i][0], Vector2(72, y), COL_TEXT)
		_text(rows[i][1], Vector2(166, y), COL_DIM)
		_text(rows[i][2], Vector2(306, y), COL_DIM)
	var tips := PixelFont.wrap("Hold JUMP for higher jumps. You can SHIFT in mid-air. Boss attacks only hurt you in their own world: blue in Light, red in Dark, purple in both. Shift to dodge!", 330)
	for i in tips.size():
		_ctext(tips[i], 186 + i * 11, COL_GOLD)
	_ctext("PRESS ESC TO RETURN", 240, COL_DIM)


func _draw_credits() -> void:
	ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, 0.55))
	_draw_logo(12, 3)
	var lines := [
		["A GAME BY", COL_DIM], [Game.AUTHOR, COL_TEXT], ["", COL_DIM],
		["DESIGN, CODE, PIXEL ART, MUSIC & SOUND", COL_DIM],
		["Created from scratch for GitHub Game Off 2026", COL_TEXT],
		["All art and audio are original and procedurally made.", COL_TEXT], ["", COL_DIM],
		["BUILT WITH", COL_DIM], ["Godot Engine 4.5 - godotengine.org (MIT License)", COL_TEXT], ["", COL_DIM],
	]
	if Game.player_name != "":
		lines.append(["STARRING", COL_DIM])
		lines.append([Game.player_name, COL_GOLD])
	lines.append(["THANK YOU FOR PLAYING!", COL_GOLD])
	for i in lines.size():
		_ctext(lines[i][0], 64 + i * 13, lines[i][1])
	_ctext("V" + Game.VERSION + "   PRESS ENTER", H - 12, COL_DIM)


func _draw_hud() -> void:
	var lvl := "%s  %s" % [Levels.label(sim.level_index), sim.level_name.to_upper()]
	ui.draw_rect(Rect2(0, 0, PixelFont.text_width(lvl) + 12, 13), Color(0.02, 0.0, 0.04, 0.55))
	_text(lvl, Vector2(5, 3), COL_DARK if sim.is_boss() else COL_TEXT)
	var rx := W - 5.0
	if Game.show_timer:
		var ts := Game.format_time(sim.time)
		rx -= PixelFont.text_width(ts)
		_text(ts, Vector2(rx, 3), COL_TEXT)
		rx -= 10
	var dt := "x%d" % level_deaths
	rx -= PixelFont.text_width(dt)
	_text(dt, Vector2(rx, 3), COL_DIM)
	rx -= 9
	_draw_skull(Vector2(rx, 3))
	rx -= 14
	if sim.has_shard:
		_draw_shard_icon(Vector2(rx, 2), sim.shard_taken)
		rx -= 10
	if sim.tokens.size() > 0:
		var tt := "%d/%d" % [sim.tokens_collected(), sim.tokens.size()]
		rx -= 11.0 + PixelFont.text_width(tt) + 4
		_coin_text(tt, Vector2(rx, 3), COL_COIN if sim.tokens_collected() == sim.tokens.size() else COL_TEXT)
	# world indicator
	var w := sim.world
	var c := Vector2(W / 2.0, 7)
	if w == 0:
		ui.draw_circle(c, 4.0, Color("fff6c8"))
		for i in 8:
			var a := TAU * i / 8.0 + state_time
			ui.draw_rect(Rect2((c + Vector2(cos(a), sin(a)) * 6.5).floor(), Vector2.ONE), Color("fff6c8"))
	else:
		ui.draw_circle(c, 4.5, COL_DARK)
		ui.draw_circle(c + Vector2(2, -1), 3.5, Color("1a0726"))
	_text("LIGHT" if w == 0 else "DARK", Vector2(c.x + 10, 3), COL_LIGHT if w == 0 else COL_DARK)
	if sim.is_boss():
		_draw_boss_hud()
	# level title card
	if card_time > 0.0:
		var total := 3.2 if sim.is_boss() else 2.6
		var a: float = clamp(card_time / 0.6, 0.0, 1.0) * clamp((total - card_time) / 0.4, 0.0, 1.0)
		var accent := COL_DARK if sim.is_boss() else _accent()
		ui.draw_rect(Rect2(0, 92, W, 64 if sim.is_boss() else 52), Color(0.02, 0.0, 0.04, 0.6 * a))
		_ctext(Levels.label(sim.level_index), 100, Color(accent.r, accent.g, accent.b, a))
		_ctext(sim.level_name.to_upper(), 114, Color(1, 1, 1, a), 2)
		if sim.is_boss():
			var info: Dictionary = Levels.get_level(sim.level_index)
			_ctext(String(info.get("title", "")).to_upper(), 134, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, a))
			_ctext("J / F / CLICK: SHOOT    SHIFT: DODGE", 146, Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, a))
	# hint stones
	if view.near_sign >= 0 and view.near_sign < sim.signs.size() and card_time <= 0.0:
		var text: String = sim.signs[view.near_sign]["text"]
		var lines := PixelFont.wrap(text, 380)
		var bh := lines.size() * 10 + 10
		var top := sim.py > 120
		var by := 20.0 if top else H - bh - 8.0
		var r := Rect2(40, by, 400, bh)
		_panel(r)
		for i in lines.size():
			_ctext(lines[i], by + 6 + i * 10, COL_TEXT)
	if sim.level_index == 0 and state == S.PLAY and sim.time < 6.0 and card_time <= 0.0 and view.near_sign < 0:
		_ctext("ESC: PAUSE    R: RESTART", H - 12, Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, 0.8))


func _draw_boss_hud() -> void:
	# player health
	var y := 16.0
	ui.draw_rect(Rect2(0, 14, 104, 13), Color(0.02, 0.0, 0.04, 0.55))
	_text("HP", Vector2(5, y + 1), COL_TEXT)
	var low := sim.player_hp <= 2 and fmod(state_time * 3.0, 1.0) < 0.5
	for i in sim.max_hp:
		var r := Rect2(19 + i * 13, y, 11, 8)
		ui.draw_rect(r.grow(1), Color(0, 0, 0, 0.6))
		if i < sim.player_hp:
			ui.draw_rect(r, Color("ff5577") if not low else Color.WHITE)
			ui.draw_rect(Rect2(r.position + Vector2(1, 1), Vector2(r.size.x - 2, 2)), Color("ffb0c0"))
		else:
			ui.draw_rect(r, Color("2a1030"))
	var wname: String = Game.weapon_stats()["name"]
	_text(wname.to_upper(), Vector2(5, 30), Color(sim.weapon["color"]))
	# boss health
	var b := sim.boss
	if b.state == "intro" and b.t < 0.6:
		return
	var bar := Rect2(90, H - 15, 300, 8)
	ui.draw_rect(Rect2(bar.position.x - 6, bar.position.y - 13, bar.size.x + 12, 25), Color(0.02, 0.0, 0.04, 0.65))
	var name := "%s" % sim.level_name.to_upper()
	_ctext(name, bar.position.y - 10, COL_DARK if b.phase == 2 else COL_TEXT)
	ui.draw_rect(bar.grow(1), Color(0, 0, 0, 0.8))
	ui.draw_rect(bar, Color("2a1030"))
	var ratio := float(b.hp) / b.max_hp
	ui.draw_rect(Rect2(bar.position, Vector2(bar.size.x * boss_bar_lag, bar.size.y)), Color(1, 1, 1, 0.75))
	var fill := Color("ff2e55") if b.phase == 2 else Color(LevelView.BOSS_LOOKS[(b.tier - 1) % LevelView.BOSS_LOOKS.size()][3])
	if b.flash > 0.5:
		fill = Color.WHITE
	ui.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), fill)
	ui.draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, 2)), fill.lightened(0.4))
	ui.draw_rect(Rect2(bar.position.x + bar.size.x * 0.5, bar.position.y - 1, 1, bar.size.y + 2), COL_GOLD)


func _draw_skull(p: Vector2) -> void:
	var col := COL_DIM
	ui.draw_rect(Rect2(p + Vector2(1, 0), Vector2(5, 1)), col)
	ui.draw_rect(Rect2(p + Vector2(0, 1), Vector2(7, 3)), col)
	ui.draw_rect(Rect2(p + Vector2(1, 4), Vector2(5, 2)), col)
	ui.draw_rect(Rect2(p + Vector2(1, 2), Vector2(2, 1)), Color("1a1030"))
	ui.draw_rect(Rect2(p + Vector2(4, 2), Vector2(2, 1)), Color("1a1030"))


func _draw_pause() -> void:
	ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, 0.55))
	var r := Rect2(150, 60, 180, 140)
	_panel(r)
	_ctext("PAUSED", 72, COL_TEXT, 2)
	_menu(_pause_items(), W / 2.0, 100, 16)
	_ctext("SHIFT: CHANGE WORLD   SPACE: JUMP   R: RESTART", H - 14, COL_DIM)


func _draw_complete() -> void:
	ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, 0.45))
	var r := Rect2(120, 26, 240, 228)
	_panel(r, COL_GOLD)
	var k: float = clamp(state_time / 0.4, 0.0, 1.0)
	var boss := Levels.is_boss(sim.level_index)
	_ctext("BOSS DEFEATED!" if boss else "LEVEL COMPLETE", 40, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, k), 2)
	_ctext(sim.level_name.to_upper(), 60, COL_TEXT)
	if Game.player_name != "":
		_ctext("WELL DONE, %s!" % Game.player_name, 72, COL_DIM)
	var key := str(sim.level_index)
	var rows := [
		["TIME", Game.format_time(sim.time)],
		["BEST", Game.format_time(float(Game.best_times.get(key, sim.time)))],
		["DEATHS", str(level_deaths)],
	]
	if not boss:
		rows.append(["SHIFTS", str(sim.shifts)])
		rows.append(["TOKENS", "%d / %d" % [sim.tokens_collected(), sim.tokens.size()]])
	if sim.has_shard:
		rows.append(["SHARD", "FOUND!" if sim.shard_taken else "MISSED"])
	for i in rows.size():
		var y := 88 + i * 13
		_text(rows[i][0], Vector2(150, y), COL_DIM)
		var col := COL_TEXT
		if rows[i][0] == "SHARD":
			col = COL_GOLD if sim.shard_taken else Color("8a7aa8")
		if rows[i][0] == "TOKENS":
			col = COL_COIN
		_text(rows[i][1], Vector2(330 - PixelFont.text_width(rows[i][1]), y), col)
	var ey := 88 + rows.size() * 13 + 4
	if Game.last_earned > 0:
		var et := "+%d TOKENS" % Game.last_earned
		var tw := 11.0 + PixelFont.text_width(et)
		_coin_text(et, Vector2(W / 2.0 - tw / 2.0, ey), COL_COIN)
	elif last_new_best and fmod(state_time, 0.8) < 0.55:
		_ctext("- NEW BEST TIME! -", ey, COL_GOLD)
	_menu(_complete_items(), W / 2.0, 196, 15)


func _draw_ending() -> void:
	ui.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.0, 0.04, 0.6))
	for i in ENDING_LINES.size():
		var a: float = clamp((state_time - i * 1.0) / 0.8, 0.0, 1.0)
		_ctext(ENDING_LINES[i], 30 + i * 16, Color(COL_TEXT.r, COL_TEXT.g, COL_TEXT.b, a))
	var a2: float = clamp((state_time - 4.5) / 0.8, 0.0, 1.0)
	if a2 > 0.0:
		_ctext("THE END", 104, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, a2), 3)
		if Game.player_name != "":
			_ctext("CONGRATULATIONS, %s!" % Game.player_name, 132, Color(1, 1, 1, a2))
		var total := 0.0
		for v in Game.best_times.values():
			total += float(v)
		_ctext("LEVELS %d / 110     BOSSES %d / 11     SHARDS %d / 10" % [_levels_done(), Game.bosses_count(), Game.shard_count()], 150, Color(1, 1, 1, a2))
		_ctext("TOTAL BEST TIME  %s     TOTAL DEATHS  %d     TOKENS  %d" % [Game.format_time(total), Game.total_deaths, Game.tokens], 164, Color(1, 1, 1, a2))
		if Game.shard_count() >= 10:
			_ctext("Every memory recovered. You are whole again.", 186, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, a2))
		else:
			_ctext("Some memories are still lost between the worlds...", 186, Color(COL_DIM.r, COL_DIM.g, COL_DIM.b, a2))
	if state_time > 2.0 and fmod(state_time, 1.0) < 0.7:
		_ctext("PRESS ENTER", H - 24, _accent())
