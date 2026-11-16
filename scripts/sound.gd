extends Node
## Audio manager: sound effect pool and the two synchronised music layers.
## The Light and Dark tracks always play together; shifting crossfades them.

const SFX_NAMES := ["jump", "land", "shift_dark", "shift_light", "blocked", "die", "shard",
	"checkpoint", "lever", "crack", "crumble", "win", "bolt", "fizzle", "menu_move",
	"menu_select", "menu_back", "respawn"]

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _light: AudioStreamPlayer
var _dark: AudioStreamPlayer
var _mix := 0.0          # 0 = light, 1 = dark
var _mix_target := 0.0
var _music_level := 1.0  # extra attenuation (menus, transitions)
var _music_level_target := 1.0
var _lowpass: AudioEffectLowPassFilter
var _music_bus := 0
var _sfx_bus := 0


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
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_light = _make_music("res://audio/music_light.wav")
	_dark = _make_music("res://audio/music_dark.wav")
	apply_volumes()


func _make_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _make_music(path: String) -> AudioStreamPlayer:
	var stream: AudioStreamWAV = load(path)
	stream = stream.duplicate()
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p


func start_music() -> void:
	if not _light.playing:
		_light.play()
		_dark.play()


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
	# equal-power crossfade
	var l := cos(_mix * PI * 0.5) * _music_level
	var d := sin(_mix * PI * 0.5) * _music_level
	_light.volume_db = linear_to_db(max(l, 0.0001)) - 4.0
	_dark.volume_db = linear_to_db(max(d, 0.0001)) - 4.0
	# keep the two layers sample-aligned
	if _light.playing and _dark.playing:
		var drift := _light.get_playback_position() - _dark.get_playback_position()
		if abs(drift) > 0.08 and abs(drift) < 30.0:
			_dark.seek(_light.get_playback_position())


func play(sfx_name: String, pitch_jitter: float = 0.0, volume_db: float = 0.0) -> void:
	if not _streams.has(sfx_name):
		return
	var p := _pool[_next]
	_next = (_next + 1) % _pool.size()
	p.stream = _streams[sfx_name]
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.volume_db = volume_db
	p.play()
