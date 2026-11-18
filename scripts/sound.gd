extends Node
## Audio manager: sound effect pool and the synchronised music layers.
## Every track has a Light and a Dark layer that always play together;
## shifting crossfades them. There are three tracks: the main theme, a second
## level theme and the boss theme.

const SFX_NAMES := ["jump", "land", "shift_dark", "shift_light", "blocked", "die", "shard",
	"checkpoint", "lever", "crack", "crumble", "win", "bolt", "fizzle", "menu_move",
	"menu_select", "menu_back", "respawn",
	"token", "fire", "boss_hit", "hurt", "boss_roar", "explosion", "boss_die", "buy",
	"laser_charge", "laser", "slam", "phase", "orb_pop", "boss_fire", "type"]

const TRACKS := {
	"main": ["res://audio/music_light.wav", "res://audio/music_dark.wav"],
	"theme2": ["res://audio/music2_light.wav", "res://audio/music2_dark.wav"],
	"boss": ["res://audio/boss_light.wav", "res://audio/boss_dark.wav"],
}

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _light: AudioStreamPlayer
var _dark: AudioStreamPlayer
var _track_streams := {}     # name -> [light stream, dark stream]
var _track := "main"
var _pending_track := ""
var _swap := 1.0             # 1 = full volume, fades to 0 while swapping tracks
var _mix := 0.0              # 0 = light, 1 = dark
var _mix_target := 0.0
var _music_level := 1.0      # extra attenuation (menus, transitions)
var _music_level_target := 1.0
var _lowpass: AudioEffectLowPassFilter
var _music_bus := 0
var _sfx_bus := 0
var _last_played := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_music_bus = _make_bus("Music")
	_sfx_bus = _make_bus("SFX")
	_lowpass = AudioEffectLowPassFilter.new()
	_lowpass.cutoff_hz = 900.0
	AudioServer.add_bus_effect(_music_bus, _lowpass)
	AudioServer.set_bus_effect_enabled(_music_bus, 0, false)
	for n in SFX_NAMES:
		_streams[n] = load("res://audio/%s.wav" % n)
	for i in 14:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for t in TRACKS:
		_track_streams[t] = [_loop_stream(TRACKS[t][0]), _loop_stream(TRACKS[t][1])]
	_light = _make_player()
	_dark = _make_player()
	_light.stream = _track_streams["main"][0]
	_dark.stream = _track_streams["main"][1]
	apply_volumes()


func _make_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _loop_stream(path: String) -> AudioStreamWAV:
	var stream: AudioStreamWAV = load(path)
	stream = stream.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	return stream


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p


func start_music() -> void:
	if not _light.playing:
		_light.play()
		_dark.play()


## Switches to another music track with a short fade.
func set_track(track: String) -> void:
	if track == _track and _pending_track == "":
		return
	if track == _track:
		_pending_track = ""
		return
	_pending_track = track


func apply_volumes() -> void:
	_set_bus_volume(_music_bus, Game.music_volume)
	_set_bus_volume(_sfx_bus, Game.sfx_volume)


func _set_bus_volume(bus: int, v: float) -> void:
	AudioServer.set_bus_mute(bus, v <= 0.001)
	AudioServer.set_bus_volume_db(bus, linear_to_db(max(v, 0.001)))


## 0.0 = Light World music, 1.0 = Dark World music.
func set_world(dark: bool, instant: bool = false) -> void:
	_mix_target = 1.0 if dark else 0.0
	if instant:
		_mix = _mix_target


func set_menu_mix(blend: float) -> void:
	_mix_target = blend


func set_muffled(on: bool) -> void:
	AudioServer.set_bus_effect_enabled(_music_bus, 0, on)


func set_music_level(level: float) -> void:
	_music_level_target = level


func _process(delta: float) -> void:
	_mix = move_toward(_mix, _mix_target, delta * 3.5)
	_music_level = move_toward(_music_level, _music_level_target, delta * 1.5)
	if _pending_track != "":
		_swap = move_toward(_swap, 0.0, delta * 3.0)
		if _swap <= 0.0:
			_track = _pending_track
			_pending_track = ""
			var playing := _light.playing
			_light.stream = _track_streams[_track][0]
			_dark.stream = _track_streams[_track][1]
			if playing:
				_light.play()
				_dark.play()
	else:
		_swap = move_toward(_swap, 1.0, delta * 2.0)
	# equal-power crossfade
	var l := cos(_mix * PI * 0.5) * _music_level * _swap
	var d := sin(_mix * PI * 0.5) * _music_level * _swap
	_light.volume_db = linear_to_db(max(l, 0.0001)) - 4.0
	_dark.volume_db = linear_to_db(max(d, 0.0001)) - 4.0
	# keep the two layers sample-aligned
	if _light.playing and _dark.playing:
		var drift := _light.get_playback_position() - _dark.get_playback_position()
		if abs(drift) > 0.08 and abs(drift) < 30.0:
			_dark.seek(_light.get_playback_position())


## min_gap limits how often the same sound can restart (rapid-fire weapons).
func play(sfx_name: String, pitch_jitter: float = 0.0, volume_db: float = 0.0, min_gap: float = 0.0) -> void:
	if not _streams.has(sfx_name):
		return
	if min_gap > 0.0:
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(_last_played.get(sfx_name, -10.0)) < min_gap:
			return
		_last_played[sfx_name] = now
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sfx_name]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db
	p.play()
