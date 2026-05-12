## Per-level room layout controller.
##
## Registers the room grid (centers, bounds, base temperatures) with Globals on
## scene load, then detects which room the player is currently in each frame and
## routes the correct base temperature to PlayerState. Also triggers music
## context changes and run-progress saves when the player enters a new room.
extends Node

@export_group("Player")
@export var player_state: Node

@export_group("Temperature")
@export var temp_change_rate: float = 40.0
@export var default_base_temp: float = 50.0
@export var room_base_temps: Array[float] = []

@export_group("Room Runtime")
@export var room_num: int = 1

@export_group("Rooms")
@export var room_centers: Array[Marker2D] = []
@export var room_mins: Array[Marker2D] = []
@export var room_maxs: Array[Marker2D] = []

@export_group("Music")
@export var room_music_contexts: Dictionary[int, String] = {}

func _ready() -> void:
	if player_state == null:
		player_state = get_parent().get_node_or_null("PlayerState")

	Globals.register_room_layout(room_centers, room_mins, room_maxs, room_base_temps)

	if not Globals.has_room_layout():
		push_error("No valid rooms configured for room_state. Populate room_centers/room_mins/room_maxs in the inspector.")
		return

	if not Globals.has_room(room_num):
		room_num = Globals.get_first_room_id(room_num)

	if player_state:
		if not _is_pending_new_run_spawn():
			var player_pos = _get_player_position()
			if player_pos != null:
				var detected_room := Globals.get_room_for_position(player_pos)
				if detected_room != -1:
					room_num = detected_room

		Globals.set_current_room(room_num)

		var target_temp: float = _get_target_temp_for_room(room_num)
		if player_state.has_method("set_room_base_temperature"):
			player_state.set_room_base_temperature(target_temp)
		if "temperature" in player_state:
			player_state.temperature = target_temp

	if not _is_pending_new_run_spawn():
		_on_room_entered(room_num)


func _exit_tree() -> void:
	if Globals.has_room_layout():
		Globals.clear_room_layout()

func _process(delta: float) -> void:
	if player_state == null:
		player_state = get_parent().get_node_or_null("PlayerState")
	if player_state == null:
		return
	if not Globals.has_room_layout():
		return
	if _is_pending_new_run_spawn():
		return

	var player_pos = _get_player_position()
	if player_pos != null:
		var detected_room := Globals.get_room_for_position(player_pos)
		if detected_room != -1 and detected_room != room_num:
			room_num = detected_room
			Globals.set_current_room(room_num)
			_on_room_entered(room_num)

	var target_temp: float = _get_target_temp_for_room(room_num)
	if player_state.has_method("set_room_base_temperature"):
		player_state.set_room_base_temperature(target_temp)
	elif "temperature" in player_state:
		player_state.temperature = move_toward(player_state.temperature, target_temp, temp_change_rate * delta)

# --- Room Enter Callback ---

func _on_room_entered(id: int) -> void:
	if room_music_contexts.has(id):
		MusicManager.set_context(StringName(room_music_contexts[id]))

	# Treat entering a new room as a checkpoint — persist run progress here.
	# Before saving, let the player_state cache a respawn target for this room
	if player_state != null and player_state.has_method("_cache_respawn_target_position"):
		player_state.call("_cache_respawn_target_position")


func _is_pending_new_run_spawn() -> bool:
	return Globals != null and "pending_new_run_spawn" in Globals and Globals.pending_new_run_spawn

func _get_player_position() -> Variant:
	if player_state and "player" in player_state and is_instance_valid(player_state.player):
		if player_state.player.has_method("get_blob_position"):
			return player_state.player.get_blob_position()
		return player_state.player.global_position

	var parent_node := get_parent()
	if parent_node == null:
		return null

	var player_node: Node2D = parent_node.get_node_or_null("Player")
	if player_node == null:
		player_node = parent_node.get_node_or_null("Player1")
	if player_node == null:
		player_node = parent_node.get_node_or_null("Player2")
	if player_node == null:
		return null

	if player_node.has_method("get_blob_position"):
		return player_node.get_blob_position()
	return player_node.global_position

func _get_target_temp_for_room(id: int) -> float:
	if id == -1:
		return default_base_temp
	return Globals.get_room_base_temperature(id, default_base_temp)
