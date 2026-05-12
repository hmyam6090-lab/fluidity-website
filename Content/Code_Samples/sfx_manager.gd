## SfxManager
##
## What this script does:
## - Centralizes one-shot SFX playback for player, UI, and environmental events.
## - Creates/uses one AudioStreamPlayer per SFX event and stores them in `_players`.
## - Auto-ensures the configured SFX bus exists (`sfx_bus`, default: "SFX").
## - Auto-hooks all BaseButton nodes so hover/click SFX work globally.
## - Exposes helper methods for options UI (`get_sfx_bus_name`, `set_sfx_volume_percent`).
##
## How playback works:
## - Public methods (for example `play_hover`, `play_temp_change`) call `_play_event`.
## - `_play_event` optionally applies cooldown throttling via `_can_play`.
## - Events are identified by constants (`EVENT_*`) and mapped to players in `_build_players`.
##
## How to add a new SFX event:
## 1) Add a new `EVENT_*` constant.
## 2) Add an exported `*_stream` variable (preload your new audio file if desired).
## 3) Register it in `_build_players` with `_register_player(EVENT_..., your_stream)`.
## 4) Add a public wrapper method (for example `play_my_new_sfx()`) calling `_play_event`.
## 5) Call that wrapper from gameplay/UI scripts through the `SfxManager` autoload.
##
## Replace or tweak existing SFX:
## - Replace the exported stream value in Inspector (autoload scene) or change preload path here.
## - Adjust cooldown exports (`ui_hover_cooldown`, `ui_select_cooldown`, `temp_repeat_interval`).
## - Change bus routing by editing `sfx_bus` (volume slider follows this bus automatically).
##
## Note:
## - If a stream is null, that event is skipped safely.
extends Node

const EVENT_WATER_JUMP := &"water_jump"
const EVENT_ICE_JUMP := &"ice_jump"
const EVENT_SWITCH_STATES := &"switch_states"
const EVENT_WATER_TO_VAPOR := &"water_to_vapor"
const EVENT_TEMP_UP := &"temp_up"
const EVENT_TEMP_DOWN := &"temp_down"
const EVENT_DEATH := &"death"
const EVENT_ROOM_CHANGE := &"room_change"
const EVENT_WATER := &"water"
const EVENT_WIND := &"wind"
const EVENT_PLANT := &"plant"
const EVENT_UI_HOVER := &"ui_hover"
const EVENT_UI_SELECT := &"ui_select"
const EVENT_UI_POP := &"ui_pop"
const EVENT_ACHIEVEMENT_UNLOCK := &"achievement_unlock"
const EVENT_LEVEL_TRANSITION := &"level_transition"

@export_group("General")
@export var sfx_bus: StringName = &"SFX"

@export_group("Player Streams")
@export var water_jump_stream: AudioStream = preload("res://Assets/Audio/SFX/water_jump.mp3")
@export var ice_jump_stream: AudioStream = preload("res://Assets/Audio/SFX/ice_jump.mp3")
@export var switch_states_stream: AudioStream = preload("res://Assets/Audio/SFX/vapor_whoosh.mp3")
@export var water_to_vapor_stream: AudioStream = preload("res://Assets/Audio/SFX/water_to_vapor.wav")
@export var temp_up_stream: AudioStream = preload("res://Assets/Audio/SFX/temp_up.wav")
@export var temp_down_stream: AudioStream = preload("res://Assets/Audio/SFX/temp_down.wav")
@export var death_stream: AudioStream = preload("res://Assets/Audio/SFX/ice_shatter.mp3")

@export_group("Environmental Streams")
@export var room_change_stream: AudioStream
@export var water_stream: AudioStream
@export var wind_stream: AudioStream
@export var plant_stream: AudioStream

@export_group("UI Streams")
@export var ui_hover_stream: AudioStream = preload("res://Assets/Audio/SFX/UI hover.wav")
@export var ui_select_stream: AudioStream = preload("res://Assets/Audio/SFX/UI select.wav")
@export var ui_pop_stream: AudioStream
@export var achievement_unlock_stream: AudioStream = preload("res://Assets/Audio/SFX/temp_up.wav")
@export var level_transition_stream: AudioStream

@export_group("Cooldowns")
@export var ui_hover_cooldown: float = 0.05
@export var ui_select_cooldown: float = 0.06
@export var temp_repeat_interval: float = 0.14

var _players: Dictionary = {}
var _last_play_time_ms: Dictionary = {}
var _tracked_buttons: Dictionary = {}
var _last_temp_direction: int = 0


func _ready() -> void:
	_ensure_sfx_bus_exists()
	_build_players()
	_hook_existing_buttons()
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func _build_players() -> void:
	_players.clear()
	_register_player(EVENT_WATER_JUMP, water_jump_stream)
	_register_player(EVENT_ICE_JUMP, ice_jump_stream)
	_register_player(EVENT_SWITCH_STATES, switch_states_stream)
	_register_player(EVENT_WATER_TO_VAPOR, water_to_vapor_stream)
	_register_player(EVENT_TEMP_UP, temp_up_stream)
	_register_player(EVENT_TEMP_DOWN, temp_down_stream)
	_register_player(EVENT_DEATH, death_stream)
	_register_player(EVENT_ROOM_CHANGE, room_change_stream)
	_register_player(EVENT_WATER, water_stream)
	_register_player(EVENT_WIND, wind_stream)
	_register_player(EVENT_PLANT, plant_stream)
	_register_player(EVENT_UI_HOVER, ui_hover_stream)
	_register_player(EVENT_UI_SELECT, ui_select_stream)
	_register_player(EVENT_UI_POP, ui_pop_stream)
	_register_player(EVENT_ACHIEVEMENT_UNLOCK, achievement_unlock_stream)
	_register_player(EVENT_LEVEL_TRANSITION, level_transition_stream)
	
	_set_player_volume(EVENT_UI_SELECT,      -9.0)
	_set_player_volume(EVENT_UI_HOVER,      -12.0)
	_set_player_volume(EVENT_SWITCH_STATES, -40.0)
	_set_player_volume(EVENT_TEMP_DOWN,     -30.0)
	_set_player_volume(EVENT_TEMP_UP,       -30.0)
	_set_player_volume(EVENT_WATER_TO_VAPOR,-20.0)
	_set_player_volume(EVENT_ACHIEVEMENT_UNLOCK, -10.0)


func _set_player_volume(event_key: StringName, volume_db: float) -> void:
	var player := _players.get(event_key) as AudioStreamPlayer
	if player != null:
		player.volume_db = volume_db


func _register_player(event_key: StringName, stream: AudioStream) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.name = String(event_key)
	player.stream = stream
	player.bus = sfx_bus
	add_child(player)
	_players[event_key] = player


func get_sfx_bus_name() -> StringName:
	return sfx_bus


func set_sfx_volume_percent(percent: float) -> void:
	_ensure_sfx_bus_exists()
	var bus_index := AudioServer.get_bus_index(sfx_bus)
	if bus_index == -1:
		return
	AudioServer.set_bus_volume_db(bus_index, _percent_to_db(percent))


func _ensure_sfx_bus_exists() -> void:
	var bus_index := AudioServer.get_bus_index(sfx_bus)
	if bus_index == -1:
		AudioServer.add_bus(AudioServer.get_bus_count())
		var new_index := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(new_index, sfx_bus)

	for event_key in _players.keys():
		var player := _players[event_key] as AudioStreamPlayer
		if player != null:
			player.bus = sfx_bus


func _percent_to_db(percent: float) -> float:
	if percent <= 0.0:
		return -80.0
	return linear_to_db(percent / 100.0)


func _play_event(event_key: StringName, cooldown_seconds: float = 0.0, pitch_scale: float = 1.0) -> void:
	var player := _players.get(event_key) as AudioStreamPlayer
	if player == null:
		return
	if cooldown_seconds > 0.0 and not _can_play(event_key, cooldown_seconds):
		return
	player.pitch_scale = max(0.01, pitch_scale)
	player.play()


func _can_play(event_key: StringName, cooldown_seconds: float) -> bool:
	var now_ms: int = Time.get_ticks_msec()
	var required_ms: int = int(cooldown_seconds * 1000.0)
	var last_ms: int = int(_last_play_time_ms.get(event_key, -required_ms))
	if now_ms - last_ms < required_ms:
		return false
	_last_play_time_ms[event_key] = now_ms
	return true


func _hook_existing_buttons() -> void:
	var root := get_tree().root
	if root == null:
		return
	_hook_buttons_recursive(root)


func _hook_buttons_recursive(node: Node) -> void:
	if node is BaseButton:
		_track_button(node as BaseButton)
	for child in node.get_children():
		_hook_buttons_recursive(child)


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_track_button(node as BaseButton)


func _track_button(button: BaseButton) -> void:
	var instance_id := button.get_instance_id()
	if _tracked_buttons.has(instance_id):
		return

	_tracked_buttons[instance_id] = button
	if not button.mouse_entered.is_connected(_on_button_hovered):
		button.mouse_entered.connect(_on_button_hovered)
	if not button.pressed.is_connected(_on_button_pressed):
		button.pressed.connect(_on_button_pressed)
	if not button.tree_exited.is_connected(_on_button_tree_exited.bind(instance_id)):
		button.tree_exited.connect(_on_button_tree_exited.bind(instance_id))


func _on_button_hovered() -> void:
	play_hover()


func _on_button_pressed() -> void:
	play_click()


func _on_button_tree_exited(instance_id: int) -> void:
	_tracked_buttons.erase(instance_id)


# --- Player SFX ---

func play_water_jump() -> void:
	_play_event(EVENT_WATER_JUMP)


func play_ice_jump() -> void:
	_play_event(EVENT_ICE_JUMP)


func play_switch_states() -> void:
	_play_event(EVENT_SWITCH_STATES)


func play_water_to_vapor() -> void:
	_play_event(EVENT_WATER_TO_VAPOR)

func stop_water_to_vapor() -> void:
	var player := _players.get(EVENT_WATER_TO_VAPOR) as AudioStreamPlayer
	if player == null or not player.playing:
		return
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -80.0, 0.5)
	tween.tween_callback(player.stop)
	# Reset volume so it's ready for next time
	tween.tween_callback(func(): player.volume_db = -20.0)

func play_form_transition(source_form: String, target_form: String) -> void:
	if source_form.to_lower() == "water" and target_form.to_lower() == "vapor":
		play_water_to_vapor()
		return
	
	if source_form.to_lower() == "vapor":
		stop_water_to_vapor()
	play_switch_states()


func play_temp_change(direction_up: bool) -> void:
	var next_direction := 1 if direction_up else -1
	var cooldown := 0.0 if next_direction != _last_temp_direction else temp_repeat_interval
	_last_temp_direction = next_direction
	_play_event(EVENT_TEMP_UP if direction_up else EVENT_TEMP_DOWN, cooldown)


func stop_temp_change_feedback() -> void:
	_last_temp_direction = 0


func play_death() -> void:
	_play_event(EVENT_DEATH)


# --- UI SFX ---

func play_hover() -> void:
	_play_event(EVENT_UI_HOVER, ui_hover_cooldown, randf_range(0.95, 1.05))


func play_click() -> void:
	_play_event(EVENT_UI_SELECT, ui_select_cooldown, randf_range(0.95, 1.05))


func play_select() -> void:
	play_click()


func play_pop() -> void:
	_play_event(EVENT_UI_POP)


func play_achievement_unlock() -> void:
	_play_event(EVENT_ACHIEVEMENT_UNLOCK)


func play_level_transition() -> void:
	_play_event(EVENT_LEVEL_TRANSITION)


# --- Environmental SFX ---

func play_room_change() -> void:
	_play_event(EVENT_ROOM_CHANGE)


func play_water() -> void:
	_play_event(EVENT_WATER)


func play_wind() -> void:
	_play_event(EVENT_WIND)


func play_plant() -> void:
	_play_event(EVENT_PLANT)
