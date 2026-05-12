## Dual-player crossfade music system.
##
## Two AudioStreamPlayers (A and B) swap roles each time a new track starts,
## fading the outgoing one to silence while fading the incoming one up to the
## target volume. Supports scene-based routing, context overrides (e.g. per-room
## music), sync groups (seamless loop switching between related tracks), and
## track chains (automatic queuing of a follow-up context when a track ends).
extends Node

@export_group("Playback")
@export var music_bus: StringName = &"Master"
@export var default_volume_db: float = -8.0
@export var crossfade_time: float = 0.6

@export_group("Tracks")
@export var default_track: AudioStream
@export var scene_tracks: Dictionary = {}
@export var context_tracks: Dictionary = {}
@export var track_chains: Dictionary = {}  # AudioStream -> StringName context to play next


var _player_a: AudioStreamPlayer
var _player_b: AudioStreamPlayer
var _active_player: AudioStreamPlayer
var _inactive_player: AudioStreamPlayer

var _current_stream: AudioStream = null
var _current_scene_path: String = ""
var _current_context: StringName = &""
var sync_groups: Array[Array] = []

var track_volumes: Dictionary = {}


func _ready() -> void:
	_player_a = AudioStreamPlayer.new()
	_player_b = AudioStreamPlayer.new()
	add_child(_player_a)
	add_child(_player_b)

	_player_a.bus = String(music_bus)
	_player_b.bus = String(music_bus)
	_player_a.volume_db = default_volume_db
	_player_b.volume_db = -80.0

	_player_a.process_mode = Node.PROCESS_MODE_ALWAYS
	_player_b.process_mode = Node.PROCESS_MODE_ALWAYS

	_active_player = _player_a
	_inactive_player = _player_b

	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# --- Scene Tracks ---

	scene_tracks["res://Game_Content/UI/main_menu.tscn"] = preload("res://Assets/Audio/Music/Menu/main_menu.wav")
	scene_tracks["res://Game_Content/FINAL_LEVELS/level_1.tscn"] = preload("res://Assets/Audio/Music/Ice/ice-final-1(loop).wav")
	scene_tracks["res://Game_Content/FINAL_LEVELS/level_2.tscn"] = preload("res://Assets/Audio/Music/Ice/ice-final(finale).wav")
	scene_tracks["res://Game_Content/Quan_Levels/level_3.tscn"] = preload("res://Assets/Audio/Music/Runoff/fluidityrunoffloop3.wav")
	scene_tracks["res://Game_Content/FINAL_LEVELS/level_3_5.tscn"] = preload("res://Assets/Audio/Music/Vapor/vapor_loop1_v1.wav")
	scene_tracks["res://Game_Content/FINAL_LEVELS/level_4.tscn"] = preload("res://Assets/Audio/Music/Vapor/vapor_loop1_v4.wav")
	
	# --- Context Tracks ---

	context_tracks[&"iceloop1"] = preload("res://Assets/Audio/Music/Ice/ice-final-2(loop).wav")
	context_tracks[&"iceloop2"] = preload("res://Assets/Audio/Music/Ice/ice-final-2(loop).wav")
	context_tracks[&"iceloop3"] = preload("res://Assets/Audio/Music/Ice/ice-final-3(loop).wav")
	context_tracks[&"iceloop4"] = preload("res://Assets/Audio/Music/Ice/ice-loop-final.wav")
	context_tracks[&"runoffintro"] = preload("res://Assets/Audio/Music/Runoff/fluidityrunoffintro.wav")
	context_tracks[&"runoffloop1"] = preload("res://Assets/Audio/Music/Runoff/fluidityrunoffloop1.wav")
	context_tracks[&"runoffloop2"] = preload("res://Assets/Audio/Music/Runoff/fluidityrunoffloop2.wav")
	context_tracks[&"runoffloop3"] = preload("res://Assets/Audio/Music/Runoff/fluidityrunoffloop3.wav")
	context_tracks[&"runoffloop4"] = preload("res://Assets/Audio/Music/Runoff/fluidityrunoffloop4.wav")
	context_tracks[&"runoffloop5"] = preload("res://Assets/Audio/Music/Runoff/fluidityrunoffloop5.wav")
	context_tracks[&"runoffloop6"] = preload("res://Assets/Audio/Music/Runoff/fluidityrunoffloop6_withstrings.wav")
	context_tracks[&"vaporloop1"] = preload("res://Assets/Audio/Music/Vapor/vapor_loop1_v1.wav")
	context_tracks[&"vaporloop2"] = preload("res://Assets/Audio/Music/Vapor/vapor_loop1_v2.wav")
	context_tracks[&"vaporloop3"] = preload("res://Assets/Audio/Music/Vapor/vapor_loop1_v3.wav")
	context_tracks[&"vaporloop4"] = preload("res://Assets/Audio/Music/Vapor/vapor_loop1_v4.wav")
	context_tracks[&"vaportransition"] = preload("res://Assets/Audio/Music/Vapor/vapor_transition.wav")
	context_tracks[&"vaporloop5"] = preload("res://Assets/Audio/Music/Vapor/vapor_loop2_v1.wav")
	context_tracks[&"vaporloop6"]   = preload("res://Assets/Audio/Music/Vapor/vapor_loop2_v2.wav")
	context_tracks[&"vaporfinale"]  = preload("res://Assets/Audio/Music/Vapor/vapor_finale.wav")


	# --- Track Chains ---

	track_chains[preload("res://Assets/Audio/Music/Ice/ice-final(finale).wav")] = &"runoffintro"
	track_chains[preload("res://Assets/Audio/Music/Runoff/fluidityrunoffintro.wav")] = &"runoffloop1"
	track_chains[preload("res://Assets/Audio/Music/Vapor/vapor_transition.wav")] = &"vaporloop5"

	_player_a.finished.connect(_on_track_finished)
	_player_b.finished.connect(_on_track_finished)
	
	# --- Sync Groups ---

	sync_groups = [
		[&"iceloop1", &"iceloop2", &"iceloop3", &"iceloop4"],
		[&"runoffloop1", &"runoffloop2", &"runoffloop3", &"runoffloop4", &"runoffloop5", &"runoffloop6"],
		[&"vaporloop1", &"vaporloop2", &"vaporloop3", &"vaporloop4"],
		[&"vaporloop5", &"vaporloop6"]
	]
	
	# --- Per-Track Volume Overrides ---

	track_volumes[&"iceloop2"] = -6.0   # quieter than default
	track_volumes[&"iceloop3"] = -9.0
	track_volumes[&"iceloop4"] = -10.0
	track_volumes[&"runoffloop1"] = 0.0 
	track_volumes[&"runoffloop2"] = 0.0 
	track_volumes[&"runoffloop3"] = 0.0 
	track_volumes[&"runoffloop4"] = 0.0   
	track_volumes[&"runoffloop5"] = 0.0
	track_volumes[&"runoffloop6"] = 0.0
	track_volumes[&"vaporloop1"] = 0.0
#	 scene tracks use their path as key
	track_volumes["res://Game_Content/FQuan_Levels/level_3.tscn"] = 0.0

	_play_for_current_scene(true)

func _get_volume_for_stream(stream: AudioStream) -> float:
	# Check context tracks
	for key in context_tracks:
		if context_tracks[key] == stream and track_volumes.has(key):
			return track_volumes[key]
	# Check scene tracks
	for key in scene_tracks:
		if scene_tracks[key] == stream and track_volumes.has(key):
			return track_volumes[key]
	return default_volume_db

func _process(_delta: float) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return

	var scene_path := tree.current_scene.scene_file_path
	if scene_path != _current_scene_path:
		_current_scene_path = scene_path
		if _current_context == &"":
			_play_for_current_scene()

func _same_sync_group(a: StringName, b: StringName) -> bool:
	for group in sync_groups:
		if a in group and b in group:
			return true
	return false

func set_context(context_id: StringName, force_restart: bool = false) -> void:
	if context_id == &"":
		clear_context()
		return

	_current_context = context_id
	var stream := _resolve_context_track(context_id)
	if stream == null:
		play_default(force_restart)
		return
	_play_stream(stream, force_restart)

func clear_context(context_id: StringName = &"") -> void:
	if context_id != &"" and context_id != _current_context:
		return
	_current_context = &""
	_play_for_current_scene()

func play_scene(scene_path: String, force_restart: bool = false) -> void:
	_current_scene_path = scene_path
	if _current_context != &"":
		return
	var stream := _resolve_scene_track(scene_path)
	if stream == null:
		stream = default_track
	_play_stream(stream, force_restart)

func play_default(force_restart: bool = false) -> void:
	_play_stream(default_track, force_restart)

func set_music_volume_db(volume_db: float) -> void:
	default_volume_db = volume_db
	if _active_player != null:
		_active_player.volume_db = volume_db

func stop_music(fade_time: float = -1.0) -> void:
	var duration := crossfade_time if fade_time < 0.0 else fade_time
	if _active_player != null and _active_player.playing:
		var tween := create_tween()
		tween.tween_property(_active_player, "volume_db", -80.0, duration)
		tween.tween_callback(_active_player.stop)
	_current_stream = null

func _play_for_current_scene(force_restart: bool = false) -> void:
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		play_default(force_restart)
		return

	var scene_path := tree.current_scene.scene_file_path
	_current_scene_path = scene_path
	play_scene(scene_path, force_restart)

func _resolve_scene_track(scene_path: String) -> AudioStream:
	if scene_tracks.has(scene_path):
		return scene_tracks[scene_path] as AudioStream

	var scene_name := scene_path.get_file().get_basename()
	if scene_tracks.has(scene_name):
		return scene_tracks[scene_name] as AudioStream

	return null

func _resolve_context_track(context_id: StringName) -> AudioStream:
	if context_tracks.has(context_id):
		return context_tracks[context_id] as AudioStream
	var context_string := String(context_id)
	if context_tracks.has(context_string):
		return context_tracks[context_string] as AudioStream
	return null

func _on_track_finished() -> void:
	if _current_stream != null and track_chains.has(_current_stream):
		var next_context: StringName = track_chains[_current_stream]
		set_context(next_context)

func _get_context_for_stream(stream: AudioStream) -> StringName:
	for key in context_tracks:
		if context_tracks[key] == stream:
			return key
	return &""

func _play_stream(stream: AudioStream, force_restart: bool = false) -> void:
	if stream == null:
		stop_music(0.2)
		return

	if not force_restart and stream == _current_stream and _active_player.playing:
		return

	_current_stream = stream

	var playback_pos := 0.0
	if _active_player.playing and _same_sync_group(_current_context, _get_context_for_stream(stream)):
		playback_pos = _active_player.get_playback_position()

	_inactive_player.stream    = stream
	_inactive_player.volume_db = -80.0
	_inactive_player.play(playback_pos)

	var target_volume := _get_volume_for_stream(stream)

	var tween := create_tween()
	tween.tween_property(_inactive_player, "volume_db", target_volume, crossfade_time)
	if _active_player.playing:
		tween.parallel().tween_property(_active_player, "volume_db", -10.0, crossfade_time)
		tween.tween_callback(_active_player.stop)

	var old_active := _active_player
	_active_player = _inactive_player
	_inactive_player = old_active
