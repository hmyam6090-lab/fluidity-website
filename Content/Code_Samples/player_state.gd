## Central player form and state controller.
##
## Manages the temperature system, form transitions between water, ice, and vapor,
## death and respawn sequencing, surface/plant sticking, and camera-shake on death.
## PlayerState is added as a child of the level root and communicates with the
## active player node via duck-typing (has_method checks) so that any form can
## be swapped in without breaking the controller.
extends Node

# --- Inspector ---

@export var player: Node2D

@export_group("SFX")
@export var death_sfx: AudioStreamPlayer2D

@export_group("Death Effect")
@export var death_effect_delay:            float = 0.6
@export var death_knockback_strength:      float = 800.0
@export var death_camera_shake_duration:   float = 0.16
@export var death_camera_shake_strength:   float = 30.0
@export var death_flash_duration:          float = 0.5
@export var death_flash_color:             Color = Color(0.6, 0.941, 1.0, 1.0)

@export_group("Player Stats")
@export var is_dead:          bool  = false
@export var temperature_min:  float = 0.0
@export var temperature_max:  float = 100.0
@export var temperature:      float = 50.0

@export_group("Form-Change Mechanic")
@export var ice_threshold:   float = 0.0
@export var water_threshold: float = 1.0
@export var vapor_threshold: float = 100.0

@export_group("Form-Change Stamina Costs")
@export var temperature_stamina_cost_to_ice:   float = 0.1
@export var temperature_stamina_cost_to_vapor: float = 0.55

@export_group("Form Transition Bridge")
@export var form_transition_pulse_duration:  float = 0.16
@export var form_transition_flash_alpha:     float = 0.12
@export var form_transition_flash_duration:  float = 0.10

@export_group("Temperature Input")
@export var temp_up:                          bool  = false
@export var temp_down:                        bool  = false
@export var temperature_input_speed:          float = 340.0
@export var temperature_idle_return_speed:    float = 200.0
@export var temperature_exhausted_return_speed: float = 180.0
@export var temperature_stamina_duration:     float = 1.35
@export var temperature_stamina_capacity:     float = 1.0
@export var temperature_stamina_recovery_rate: float = 0.9
@export var temperature_stamina_resume_threshold: float = 0.25
@export var temperature_room_delta_cap:       float = 50.0

@export_group("Temp Stamina Indicator")
@export var temp_indicator_offset:  Vector2 = Vector2(56.0, -24.0)
@export var temp_indicator_z_index: int     = 4096

@export_group("Level Specific Mechanics")
@export var is_stick:                      bool  = false
@export var stick_velocity:                float = 5.0
@export var room_state:                    Node
@export var plant_stick_force:             float = 0.15
@export var plant_stick_max_offset:        float = 48.0
@export var plant_input_counter_boost:     float = 1.5
@export var plant_input_counter_min:       float = 0.55
@export var plant_input_counter_force:     float = 0.18
@export var plant_bounce_force:            float = 13.0
@export var plant_regrab_cooldown:         float = 0.2
@export var surface_jump_force_lock_duration: float = 0.12

@export_group("Respawn Points")
@export var respawn_markers: Array[Marker2D] = []

# --- Internal State ---

# Current scene path — cached each frame to know where to reload on death.
var _current_scene_path: String = ""

var _is_ice:   bool = false
var _is_water: bool = false
var _is_vapor: bool = false
var _current_form: String = ""

var temp_cooldown:                    float = 0.0
var _room_base_temperature:           float = 50.0
var _temperature_stamina:             float = 1.0
var _temperature_input_active:        bool  = false
var _temperature_stamina_exhausted:   bool  = false
var _temperature_actively_changing:   bool  = false

var respawn_points := {}
var death_transition_in_progress := false
var _death_respawn_timer := 0.0
var _pending_respawn_scene_path: String = ""
var _death_player_to_free: Node2D
var _pending_death_knockback_dir := Vector2.ZERO

var _death_camera: Camera2D
var _death_camera_base_offset := Vector2.ZERO
var _death_shake_timer := 0.0

var _death_flash_material: ShaderMaterial
var _stick_source: Node2D
var _stick_anchor_position := Vector2.ZERO
var _stick_anchor_local := Vector2.ZERO
var _stick_normal := Vector2.UP
var _plant_regrab_timer := 0.0
var _surface_jump_force_lock_timer := 0.0

const FORM_WATER := "water"
const FORM_ICE := "ice"
const FORM_VAPOR := "vapor"

const FORM_PAIR_WATER_TO_ICE := 0
const FORM_PAIR_ICE_TO_WATER := 1
const FORM_PAIR_WATER_TO_VAPOR := 2
const FORM_PAIR_VAPOR_TO_WATER := 3
const FORM_PAIR_ICE_TO_VAPOR := 4
const FORM_PAIR_VAPOR_TO_ICE := 5
const SHATTER_DEATH_TUTORIAL_ID := "tutorial::first_shatter_death"
const SHATTER_DEATH_TUTORIAL_SCENE: PackedScene = preload("res://Scenes/Levels/Tut_sign_overlay.tscn")

var form_transition_in_progress := false
var _form_transition_source_player: Node2D
var _form_transition_source_form := ""
var _form_transition_target_form := ""
var _form_transition_pair := -1
var _active_shatter_death_overlay: CanvasLayer

var _water_player_scene: PackedScene = preload("res://Scenes/Player/water.tscn")
var _ice_player_scene: PackedScene = preload("res://Scenes/Player/ice.tscn")
var _vapor_player_scene: PackedScene = preload("res://Scenes/Player/water_vapor.tscn")
var _form_transition_bridge_scene: PackedScene = preload("res://Scenes/Player/VFX/form_transition_bridge.tscn")
var _temperature_stamina_indicator: Node2D

func _ready() -> void:
	is_stick = false
	respawn_points.clear()
	for i in range(respawn_markers.size()):
		var marker := respawn_markers[i]
		if marker == null:
			continue
		respawn_points[i + 1] = marker
	_resolve_player()
	_current_form = _detect_form_from_player(player)
	_room_base_temperature = clamp(temperature, temperature_min, temperature_max)
	_temperature_stamina = max(0.01, temperature_stamina_capacity)
	# If we have a pending respawn position (either from death or a continued run), apply it after load
	if Globals.was_dead or ("has_respawn_position" in Globals and Globals.has_respawn_position):
		call_deferred("_apply_respawn_after_scene_load")
	elif Globals != null and "pending_new_run_spawn" in Globals and Globals.pending_new_run_spawn:
		call_deferred("_apply_new_run_spawn_after_scene_load")

func _process(delta: float) -> void:
	if _plant_regrab_timer > 0.0:
		_plant_regrab_timer -= delta
	if _surface_jump_force_lock_timer > 0.0:
		_surface_jump_force_lock_timer = max(0.0, _surface_jump_force_lock_timer - delta)

	# Re-resolve the player reference if the node was freed (e.g. mid-transition).
	if not is_instance_valid(player):
		_resolve_player()

	if is_stick and (not _is_water_form_active() or not is_instance_valid(_stick_source)):
		clear_plant_stick(false)

	if room_state and "room_num" in room_state:
		Globals.current_room = room_state.room_num
	# Cache current scene path each frame so death/respawn knows which scene to reload.
	_current_scene_path = get_tree().current_scene.scene_file_path
	if is_instance_valid(player):
		if is_dead and not death_transition_in_progress:
			_begin_respawn_transition()
		if is_stick and player.name == "Player":
			player.use_custom_gravity = true
			player.custom_gravity = Vector2(Vector2i(0, 0))
			player.velocity_limit = stick_velocity
			if player.name == "Player": 
				player.floor_timer = 8
		else:
			if player.name == "Player":
				player.velocity_limit = 0.0
				if _surface_jump_force_lock_timer > 0.0:
					player.use_custom_gravity = true
					player.custom_gravity = Vector2.ZERO
				else:
					player.use_custom_gravity = false
	
	_update_death_sequence(delta)
	_update_death_camera_shake(delta)

	temp_change(delta)
	if is_instance_valid(player) and not death_transition_in_progress and not form_transition_in_progress:
		check_temp_form()
	_update_temperature_stamina_indicator()

# --- Form Transition ---

func set_pending_death_knockback(direction: Vector2) -> void:
	if direction.length_squared() > 0.0001:
		_pending_death_knockback_dir = direction.normalized()

func set_pending_shatter_death_tutorial() -> void:
	if Globals != null:
		Globals.pending_shatter_death_tutorial_after_respawn = true

func is_form_transition_lock_active() -> bool:
	return false

func request_form_transition(source_player: Node2D, target_form: String) -> bool:
	if not is_instance_valid(source_player):
		return false
	if death_transition_in_progress or form_transition_in_progress:
		return false

	var target := target_form.to_lower()
	if target != FORM_WATER and target != FORM_ICE and target != FORM_VAPOR:
		return false

	if not is_instance_valid(player):
		_resolve_player()
	if is_instance_valid(player) and source_player != player:
		return false

	var source := _detect_form_from_player(source_player)
	if source.is_empty() or source == target:
		return false

	var pair := _get_transition_pair(source, target)
	if pair < 0:
		return false

	_form_transition_source_player = source_player
	_form_transition_source_form = source
	_form_transition_target_form = target
	_form_transition_pair = pair
	form_transition_in_progress = true

	var source_pos := _get_player_world_position(source_player)
	_spawn_form_transition_bridge(source_pos, pair, false)
	_apply_form_transition_pulse(source_player, pair, true)
	if SfxManager != null and SfxManager.has_method("play_form_transition"):
		SfxManager.play_form_transition(source, target)

	target_form = _form_transition_target_form
	var swapped := _perform_form_transition_swap()
	if swapped and AchievementManager != null and AchievementManager.has_method("notify_form_transition"):
		AchievementManager.notify_form_transition(target_form)
	if target_form != FORM_ICE:
		_finish_form_transition()
	return swapped

func _resolve_player() -> void:
	var parent_node := get_parent()
	if parent_node == null:
		return

	var p: Node2D = parent_node.get_node_or_null("Player")
	if p == null:
		p = parent_node.get_node_or_null("Player1")
	if p == null:
		p = parent_node.get_node_or_null("Player2")

	player = p

# --- Death / Respawn ---

func _get_room_num() -> int:
	if room_state and "room_num" in room_state:
		return room_state.room_num
	return int(Globals.current_room)

func _begin_respawn_transition() -> void:
	_cancel_form_transition()
	death_transition_in_progress = true
	_set_player_death_face(player)
	clear_plant_stick(false)
	Globals.respawn_room = _get_room_num()
	Globals.current_room = int(Globals.respawn_room)
	_cache_respawn_target_position()
	Globals.was_dead = true
	if AchievementManager != null and AchievementManager.has_method("notify_player_death"):
		AchievementManager.notify_player_death()

	_pending_respawn_scene_path = _current_scene_path
	_death_player_to_free = player
	_death_respawn_timer = max(0.01, death_effect_delay)
	
	_apply_death_knockback()
	_start_death_flash()
	_start_death_camera_shake()

	is_dead = false

func _show_shatter_death_tutorial_if_needed() -> void:
	if Globals == null:
		return
	if not Globals.pending_shatter_death_tutorial_after_respawn:
		return
	Globals.pending_shatter_death_tutorial_after_respawn = false

	if Globals != null and Globals.has_method("has_completed_overlay_tutorial"):
		if Globals.has_completed_overlay_tutorial(SHATTER_DEATH_TUTORIAL_ID):
			return

	if is_instance_valid(_active_shatter_death_overlay):
		return

	if SHATTER_DEATH_TUTORIAL_SCENE == null:
		return

	var current_scene := get_tree().current_scene
	if current_scene == null:
		return

	var overlay_host := SHATTER_DEATH_TUTORIAL_SCENE.instantiate()
	if overlay_host == null:
		return

	var overlay := overlay_host.get_node_or_null("TutorialOverlay") as CanvasLayer
	if overlay == null:
		overlay_host.queue_free()
		return

	overlay_host.remove_child(overlay)
	overlay_host.queue_free()
	current_scene.add_child(overlay)
	_active_shatter_death_overlay = overlay

	if _active_shatter_death_overlay.has_method("configure_tutorial"):
		_active_shatter_death_overlay.call(
			"configure_tutorial",
			"Shatter Warning",
			"Ice can shatter if you hit surfaces too fast.\n\nSlow down before impact or avoid steep drops to survive.",
			null
		)

	if _active_shatter_death_overlay.has_signal("overlay_closed"):
		_active_shatter_death_overlay.connect("overlay_closed", Callable(self, "_on_shatter_death_tutorial_closed"), CONNECT_ONE_SHOT)

	if _active_shatter_death_overlay.has_method("open_overlay"):
		_active_shatter_death_overlay.call("open_overlay")

	if Globals != null and Globals.has_method("mark_overlay_tutorial_completed"):
		Globals.mark_overlay_tutorial_completed(SHATTER_DEATH_TUTORIAL_ID)

func _on_shatter_death_tutorial_closed() -> void:
	if is_instance_valid(_active_shatter_death_overlay):
		_active_shatter_death_overlay.queue_free()
	_active_shatter_death_overlay = null

func _update_death_sequence(delta: float) -> void:
	if _death_respawn_timer <= 0.0:
		return

	_death_respawn_timer -= delta
	if _death_respawn_timer > 0.0:
		return
	if _pending_respawn_scene_path.is_empty():
		return

	if is_instance_valid(_death_player_to_free):
		_death_player_to_free.queue_free()
	_death_player_to_free = null

	var next_scene := _pending_respawn_scene_path
	_pending_respawn_scene_path = ""
	LevelTransition.change_scene_to(next_scene)

func _apply_death_knockback() -> void:
	if not is_instance_valid(player):
		_pending_death_knockback_dir = Vector2.ZERO
		return
	if not (player is CharacterBody2D):
		_pending_death_knockback_dir = Vector2.ZERO
		return

	var dir := _pending_death_knockback_dir
	_pending_death_knockback_dir = Vector2.ZERO
	if dir.length_squared() <= 0.0001:
		var v: Vector2 = (player as CharacterBody2D).velocity
		if v.length_squared() > 0.0001:
			dir = -v.normalized()
	if dir.length_squared() <= 0.0001:
		dir = Vector2.UP

	(player as CharacterBody2D).velocity = dir * death_knockback_strength

func _start_death_camera_shake() -> void:
	_death_camera = _find_camera()
	if not is_instance_valid(_death_camera):
		return
	_death_camera_base_offset = _death_camera.offset
	_death_shake_timer = max(0.0, death_camera_shake_duration)

func _update_death_camera_shake(delta: float) -> void:
	if _death_shake_timer <= 0.0:
		return
	if not is_instance_valid(_death_camera):
		_death_camera = _find_camera()
		if not is_instance_valid(_death_camera):
			_death_shake_timer = 0.0
			return
		_death_camera_base_offset = _death_camera.offset

	_death_shake_timer -= delta
	var t = clamp(_death_shake_timer / max(0.001, death_camera_shake_duration), 0.0, 1.0)
	var strength = death_camera_shake_strength * t
	_death_camera.offset = _death_camera_base_offset + Vector2(
		randf_range(-strength, strength),
		randf_range(-strength, strength)
	)
	if _death_shake_timer <= 0.0:
		_death_camera.offset = _death_camera_base_offset

func _find_camera() -> Camera2D:
	var parent_node := get_parent()
	if parent_node != null:
		var direct := parent_node.get_node_or_null("Camera2D")
		if direct is Camera2D:
			return direct

	var scene := get_tree().current_scene
	if scene == null:
		return null
	var found := scene.find_child("Camera2D", true, false)
	if found is Camera2D:
		return found
	return null

func _start_death_flash() -> void:
	_death_flash_material = null
	if not is_instance_valid(player):
		return
	if player.has_method("prefers_no_death_shader_flash") and player.prefers_no_death_shader_flash():
		return

	var sprite := player.get_node_or_null("Sprite2D")
	if sprite == null:
		sprite = player.find_child("Sprite2D", true, false)
	if sprite == null:
		return
	if not (sprite is CanvasItem):
		return

	var mat := (sprite as CanvasItem).material
	if mat is ShaderMaterial:
		(sprite as CanvasItem).material = (mat as ShaderMaterial).duplicate()
		_death_flash_material = (sprite as CanvasItem).material as ShaderMaterial

	if _death_flash_material == null:
		return

	# Per request: leave hit_effect at max; only toggle get_hit.
	_death_flash_material.set_shader_parameter("get_hit", true)

func _set_death_hit_effect(value: float) -> void:
	if _death_flash_material != null:
		_death_flash_material.set_shader_parameter("hit_effect", value)

func _end_death_flash() -> void:
	if _death_flash_material != null:
		_death_flash_material.set_shader_parameter("hit_effect", 0.0)
		_death_flash_material.set_shader_parameter("get_hit", false)


func _set_player_death_face(target_player: Node) -> void:
	if target_player == null:
		return
	var face_node = target_player.get_node_or_null("Face")
	if face_node == null:
		face_node = target_player.find_child("Face", true, false)
	if not (face_node is AnimatedSprite2D):
		return
	var face := face_node as AnimatedSprite2D
	if face.sprite_frames != null and face.sprite_frames.has_animation("sad"):
		face.play("sad")
	elif face.sprite_frames != null and face.sprite_frames.has_animation("default"):
		face.play("default")

func _perform_form_transition_swap() -> bool:
	if not is_instance_valid(_form_transition_source_player):
		_cancel_form_transition()
		return false

	var target_scene := _get_form_scene(_form_transition_target_form)
	if target_scene == null:
		_cancel_form_transition()
		return false

	var parent_node := _form_transition_source_player.get_parent()
	if parent_node == null:
		parent_node = get_tree().current_scene
	if parent_node == null:
		_cancel_form_transition()
		return false

	var spawn_position := _get_player_world_position(_form_transition_source_player)
	var transition_velocity := _get_player_transition_velocity(_form_transition_source_player)
	var instance := target_scene.instantiate()
	if not (instance is Node2D):
		_cancel_form_transition()
		return false

	var new_player := instance as Node2D
	if parent_node is Node2D:
		new_player.position = (parent_node as Node2D).to_local(spawn_position)
	else:
		new_player.position = spawn_position
	parent_node.add_child(new_player)

	if _form_transition_target_form == FORM_ICE:
		var ice_body := new_player as CharacterBody2D
		var restore_process := new_player.is_processing()
		var restore_physics := new_player.is_physics_processing()
		var original_collision_layer := ice_body.collision_layer
		var original_collision_mask := ice_body.collision_mask
		ice_body.collision_layer = 0
		ice_body.collision_mask = 0
		ice_body.set_process(false)
		ice_body.set_physics_process(false)
		_reset_transition_motion_on_target(new_player, Vector2.ZERO)
		_prepare_ice_transition_spawn(new_player, spawn_position, transition_velocity, original_collision_layer, original_collision_mask, restore_process, restore_physics)
	else:
		_reset_transition_motion_on_target(new_player, transition_velocity)
		_reset_transition_motion_next_physics(new_player, transition_velocity)
	player = new_player
	_sync_transition_camera(new_player)
	_spawn_form_transition_bridge(spawn_position, _form_transition_pair, true)
	_spawn_form_transition_fullscreen_flash(_form_transition_pair)
	_apply_form_transition_pulse(new_player, _form_transition_pair, false)

	var old_player := _form_transition_source_player
	_form_transition_source_player = null
	if is_instance_valid(old_player):
		old_player.queue_free()

	return true

func _finish_form_transition() -> void:
	form_transition_in_progress = false
	_form_transition_source_player = null
	_form_transition_source_form = ""
	_form_transition_target_form = ""
	_form_transition_pair = -1

	if not is_instance_valid(player):
		_resolve_player()

func _cancel_form_transition() -> void:
	form_transition_in_progress = false
	_form_transition_source_player = null
	_form_transition_source_form = ""
	_form_transition_target_form = ""
	_form_transition_pair = -1

func _get_form_scene(form_name: String) -> PackedScene:
	match form_name:
		FORM_WATER:
			return _water_player_scene
		FORM_ICE:
			return _ice_player_scene
		FORM_VAPOR:
			return _vapor_player_scene
		_:
			return null

func _detect_form_from_player(node: Node) -> String:
	if node == null:
		return ""

	if node is CharacterBody2D:
		return FORM_ICE

	var script_res = node.get_script()
	if script_res is Script:
		var script_path := (script_res as Script).resource_path
		if script_path.ends_with("blob-movement.gd"):
			return FORM_WATER
		if script_path.ends_with("vapor_softbody.gd"):
			return FORM_VAPOR
		if script_path.ends_with("ice.gd"):
			return FORM_ICE

	if "_is_water" in node and node._is_water:
		return FORM_WATER
	if "_is_ice" in node and node._is_ice:
		return FORM_ICE
	if "_is_vapor" in node and node._is_vapor:
		return FORM_VAPOR
	return ""

func _get_transition_pair(source_form: String, target_form: String) -> int:
	if source_form == FORM_WATER and target_form == FORM_ICE:
		return FORM_PAIR_WATER_TO_ICE
	if source_form == FORM_ICE and target_form == FORM_WATER:
		return FORM_PAIR_ICE_TO_WATER
	if source_form == FORM_WATER and target_form == FORM_VAPOR:
		return FORM_PAIR_WATER_TO_VAPOR
	if source_form == FORM_VAPOR and target_form == FORM_WATER:
		return FORM_PAIR_VAPOR_TO_WATER
	if source_form == FORM_ICE and target_form == FORM_VAPOR:
		return FORM_PAIR_ICE_TO_VAPOR
	if source_form == FORM_VAPOR and target_form == FORM_ICE:
		return FORM_PAIR_VAPOR_TO_ICE
	return -1

func _get_player_world_position(node: Node) -> Vector2:
	if node == null:
		return Vector2.ZERO
	if node.has_method("get_blob_position"):
		return node.get_blob_position()
	if node is Node2D:
		return (node as Node2D).global_position
	return Vector2.ZERO

func _get_player_transition_velocity(node: Node) -> Vector2:
	if node == null:
		return Vector2.ZERO

	if "velocity" in node:
		var candidate = node.velocity
		if candidate is Vector2:
			return candidate
	if node is CharacterBody2D:
		return (node as CharacterBody2D).velocity
	if node.has_method("get_velocity"):
		var candidate_velocity = node.get_velocity()
		if candidate_velocity is Vector2:
			return candidate_velocity
	if node.has_method("get_blob_velocity"):
		var candidate_blob_velocity = node.get_blob_velocity()
		if candidate_blob_velocity is Vector2:
			return candidate_blob_velocity

	return Vector2.ZERO

func _reset_transition_motion_on_target(target_player: Node2D, preserved_velocity: Vector2 = Vector2.ZERO) -> void:
	if not is_instance_valid(target_player):
		return

	if "inherited_velocity" in target_player:
		target_player.inherited_velocity = preserved_velocity
	if "apply_inherited_once" in target_player:
		target_player.apply_inherited_once = preserved_velocity.length_squared() > 0.0001
	if "velocity" in target_player:
		target_player.velocity = preserved_velocity
	elif target_player is CharacterBody2D:
		(target_player as CharacterBody2D).velocity = preserved_velocity

func _reset_transition_motion_next_physics(target_player: Node2D, preserved_velocity: Vector2 = Vector2.ZERO) -> void:
	call_deferred("_reset_transition_motion_next_physics_deferred", target_player, preserved_velocity)

func _reset_transition_motion_next_physics_deferred(target_player: Node2D, preserved_velocity: Vector2) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(target_player):
		return
	_reset_transition_motion_on_target(target_player, preserved_velocity)

	var pos := _get_player_world_position(target_player)
	if "prev_position" in target_player:
		target_player.prev_position = pos
	if "_previous_pos" in target_player:
		target_player._previous_pos = pos

func _prepare_ice_transition_spawn(new_player: Node2D, spawn_position: Vector2, preserved_velocity: Vector2, original_collision_layer: int, original_collision_mask: int, restore_process: bool, restore_physics: bool) -> void:
	call_deferred("_prepare_ice_transition_spawn_deferred", new_player, spawn_position, preserved_velocity, original_collision_layer, original_collision_mask, restore_process, restore_physics)

func _prepare_ice_transition_spawn_deferred(new_player: Node2D, spawn_position: Vector2, preserved_velocity: Vector2, original_collision_layer: int, original_collision_mask: int, restore_process: bool, restore_physics: bool) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(new_player):
		_finish_form_transition()
		return

	var safe_spawn_position := _find_safe_ice_spawn_position(new_player, spawn_position, original_collision_mask)
	new_player.global_position = safe_spawn_position

	if new_player is CharacterBody2D:
		var ice_body := new_player as CharacterBody2D
		ice_body.collision_layer = original_collision_layer
		ice_body.collision_mask = original_collision_mask

	_reset_transition_motion_on_target(new_player, preserved_velocity)
	var spawn_world_position := _get_player_world_position(new_player)
	if "prev_position" in new_player:
		new_player.prev_position = spawn_world_position
	if "_previous_pos" in new_player:
		new_player._previous_pos = spawn_world_position
	new_player.set_process(restore_process)
	new_player.set_physics_process(restore_physics)
	_finish_form_transition()

func _find_safe_ice_spawn_position(new_player: Node2D, spawn_position: Vector2, collision_mask: int) -> Vector2:
	if not is_instance_valid(new_player):
		return spawn_position

	var collision_shape := new_player.get_node_or_null("CollisionShape2D")
	if not (collision_shape is CollisionShape2D):
		return spawn_position

	var shape_node := collision_shape as CollisionShape2D
	if shape_node.shape == null:
		return spawn_position

	var viewport := get_viewport()
	if viewport == null:
		return spawn_position

	var world = viewport.get_world_2d()
	if world == null:
		return spawn_position

	var base_distance := _get_ice_spawn_escape_distance(shape_node.shape)
	var direction_order := [
		Vector2.UP,
		Vector2.UP + Vector2.LEFT,
		Vector2.UP + Vector2.RIGHT,
		Vector2.LEFT,
		Vector2.RIGHT,
		Vector2.DOWN + Vector2.LEFT,
		Vector2.DOWN + Vector2.RIGHT,
		Vector2.DOWN,
	]
	var distance_multipliers := [0.0, 1.0, 1.5, 2.0, 2.5, 3.0]
	var original_position := new_player.global_position

	for distance_multiplier in distance_multipliers:
		var candidate_position = spawn_position + Vector2.UP * base_distance * distance_multiplier
		if _is_ice_spawn_position_clear(world.direct_space_state, new_player, shape_node, candidate_position, collision_mask):
			new_player.global_position = original_position
			return candidate_position

	for distance_multiplier in distance_multipliers:
		for direction in direction_order:
			var offset = direction.normalized() * base_distance * distance_multiplier
			var candidate_position = spawn_position + offset
			if _is_ice_spawn_position_clear(world.direct_space_state, new_player, shape_node, candidate_position, collision_mask):
				new_player.global_position = original_position
				return candidate_position

	new_player.global_position = original_position
	return spawn_position + Vector2.UP * base_distance * 3.0

func _is_ice_spawn_position_clear(space_state: PhysicsDirectSpaceState2D, new_player: Node2D, shape_node: CollisionShape2D, candidate_position: Vector2, collision_mask: int) -> bool:
	if space_state == null:
		return true
	if shape_node == null or shape_node.shape == null:
		return true
	if not is_instance_valid(new_player):
		return true

	new_player.global_position = candidate_position

	var params := PhysicsShapeQueryParameters2D.new()
	params.shape = shape_node.shape
	params.transform = shape_node.global_transform
	params.collision_mask = collision_mask
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return space_state.intersect_shape(params, 1).is_empty()

func _get_ice_spawn_escape_distance(shape: Shape2D) -> float:
	if shape is RectangleShape2D:
		var rect := shape as RectangleShape2D
		return max(rect.size.x, rect.size.y) * 0.5 + 8.0
	if shape is CircleShape2D:
		var circle := shape as CircleShape2D
		return circle.radius + 8.0
	return 32.0

func _sync_transition_camera(new_player: Node2D) -> void:
	var cam := _find_camera()
	if "camera" in new_player and is_instance_valid(cam):
		new_player.camera = cam
	if is_instance_valid(cam):
		call_deferred("_sync_transition_camera_deferred", cam, new_player)

func _sync_transition_camera_deferred(cam: Camera2D, new_player: Node2D) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(cam):
		return
	if not is_instance_valid(new_player):
		return
	if "blob" in cam:
		cam.blob = new_player

func _spawn_form_transition_bridge(world_position: Vector2, pair: int, entering: bool) -> void:
	if _form_transition_bridge_scene == null:
		return
	var fx = _form_transition_bridge_scene.instantiate()
	if fx == null:
		return
	if fx is Node2D:
		(fx as Node2D).global_position = world_position
	if fx.has_method("configure"):
		fx.configure(pair, entering)

	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(fx)
	else:
		add_child(fx)

func _spawn_form_transition_fullscreen_flash(pair: int) -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	var layer := CanvasLayer.new()
	layer.layer = 120
	var flash := ColorRect.new()
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var colors := _get_transition_palette(pair)
	var tint: Color = colors[0]
	tint.a = clamp(form_transition_flash_alpha, 0.0, 1.0)
	flash.color = tint

	layer.add_child(flash)
	scene.add_child(layer)

	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, max(0.01, form_transition_flash_duration)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_callback(Callable(layer, "queue_free"))

func _apply_form_transition_pulse(player_node: Node2D, pair: int, source_phase: bool) -> void:
	var visual := _get_transition_visual(player_node)
	if visual == null:
		return

	var mat := visual.material
	if not (mat is ShaderMaterial):
		return

	visual.material = (mat as ShaderMaterial).duplicate()
	var shader_mat := visual.material as ShaderMaterial
	if "_hit_material" in player_node:
		player_node._hit_material = shader_mat
	var colors := _get_transition_palette(pair)
	var flash = colors[0]

	shader_mat.set_shader_parameter("flash_color", flash)
	shader_mat.set_shader_parameter("flash_speed", 46.0 if source_phase else 34.0)
	shader_mat.set_shader_parameter("shake_intensity", 0.0)
	shader_mat.set_shader_parameter("hit_effect", 1.0 if source_phase else 0.85)
	shader_mat.set_shader_parameter("get_hit", true)

	var tween := create_tween()
	tween.tween_property(shader_mat, "shader_parameter/hit_effect", 0.0, form_transition_pulse_duration)
	tween.tween_callback(Callable(self, "_finish_form_transition_pulse").bind(shader_mat))

func _finish_form_transition_pulse(shader_mat: ShaderMaterial) -> void:
	if shader_mat == null:
		return
	shader_mat.set_shader_parameter("hit_effect", 0.0)
	shader_mat.set_shader_parameter("get_hit", false)

func _get_transition_visual(player_node: Node2D) -> CanvasItem:
	if not is_instance_valid(player_node):
		return null

	var sprite := player_node.get_node_or_null("Sprite2D")
	if sprite is CanvasItem:
		return sprite as CanvasItem

	var mesh := player_node.get_node_or_null("QMeshPolygonNode")
	if mesh is CanvasItem:
		return mesh as CanvasItem

	var found_sprite := player_node.find_child("Sprite2D", true, false)
	if found_sprite is CanvasItem:
		return found_sprite as CanvasItem

	var found_mesh := player_node.find_child("QMeshPolygonNode", true, false)
	if found_mesh is CanvasItem:
		return found_mesh as CanvasItem

	return null

func _get_transition_palette(pair: int) -> Array:
	match pair:
		FORM_PAIR_WATER_TO_ICE:
			return [Color(0.72, 0.97, 1.0, 1.0), Color(0.58, 0.84, 1.0, 1.0), Color(0.95, 1.0, 1.0, 1.0)]
		FORM_PAIR_ICE_TO_WATER:
			return [Color(0.37, 0.85, 1.0, 1.0), Color(0.22, 0.65, 0.95, 1.0), Color(0.72, 0.96, 1.0, 1.0)]
		FORM_PAIR_WATER_TO_VAPOR:
			return [Color(0.96, 0.98, 1.0, 1.0), Color(0.74, 0.88, 0.98, 1.0), Color(0.86, 0.92, 0.96, 1.0)]
		FORM_PAIR_VAPOR_TO_WATER:
			return [Color(0.78, 0.93, 1.0, 1.0), Color(0.5, 0.78, 1.0, 1.0), Color(0.9, 0.97, 1.0, 1.0)]
		FORM_PAIR_ICE_TO_VAPOR:
			return [Color(0.91, 0.97, 1.0, 1.0), Color(0.7, 0.86, 0.98, 1.0), Color(0.98, 1.0, 1.0, 1.0)]
		FORM_PAIR_VAPOR_TO_ICE:
			return [Color(0.68, 0.9, 1.0, 1.0), Color(0.46, 0.74, 1.0, 1.0), Color(0.88, 0.97, 1.0, 1.0)]
		_:
			return [Color(0.8, 0.9, 1.0, 1.0), Color(0.7, 0.85, 1.0, 1.0), Color(1.0, 1.0, 1.0, 1.0)]

func _cache_respawn_target_position() -> void:
	var marker: Marker2D = _get_respawn_marker(int(Globals.respawn_room))
	if marker != null:
		Globals.respawn_position = marker.global_position
		Globals.has_respawn_position = true
		return

	if is_instance_valid(player):
		if player.has_method("get_blob_position"):
			Globals.respawn_position = player.get_blob_position()
		else:
			Globals.respawn_position = player.global_position
		Globals.has_respawn_position = true

func _apply_respawn() -> void:
	var target_pos := _get_respawn_position()
	_teleport_player(target_pos)

func _apply_respawn_after_scene_load() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_resolve_player()
	if not is_instance_valid(player):
		return

	_apply_respawn()
	await get_tree().physics_frame
	if is_instance_valid(player):
		_teleport_player(_get_respawn_position())
	Globals.current_room = int(Globals.respawn_room)
	Globals.was_dead = false
	Globals.has_respawn_position = false
	death_transition_in_progress = false
	call_deferred("_show_shatter_death_tutorial_if_needed")


func _apply_new_run_spawn_after_scene_load() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	_resolve_player()
	if not is_instance_valid(player):
		_clear_pending_new_run_spawn_state()
		return

	var start_room_id := 1
	if Globals != null and Globals.has_method("get_first_room_id"):
		start_room_id = Globals.get_first_room_id(start_room_id)

	var start_marker: Marker2D = _get_respawn_marker(start_room_id)
	if start_marker != null:
		_teleport_player(start_marker.global_position)
		await get_tree().physics_frame
		if is_instance_valid(player):
			_teleport_player(start_marker.global_position)

	if Globals != null:
		Globals.current_room = start_room_id
		Globals.respawn_room = start_room_id

	_clear_pending_new_run_spawn_state()


func _clear_pending_new_run_spawn_state() -> void:
	if Globals == null:
		return
	Globals.pending_new_run_spawn = false
	Globals.was_dead = false
	Globals.has_respawn_position = false
	Globals.respawn_position = Vector2.ZERO

func _get_respawn_position() -> Vector2:
	if "has_respawn_position" in Globals and Globals.has_respawn_position:
		return Globals.respawn_position

	var marker: Marker2D = _get_respawn_marker(int(Globals.respawn_room))
	if marker != null:
		return marker.global_position

	if is_instance_valid(player):
		if player.has_method("get_blob_position"):
			return player.get_blob_position()
		return player.global_position

	return Vector2.ZERO

func _teleport_player(target_pos: Vector2) -> void:
	if not is_instance_valid(player):
		return

	if player.has_method("get_blob_position") and "mesh" in player and is_instance_valid(player.mesh):
		player.set_velocity_limit(1)
		var mesh = player.mesh
		var current_pos: Vector2 = player.get_blob_position()
		var offset: Vector2 = target_pos - current_pos
		var particle_count: int = mesh.get_particle_count()

		for i in range(particle_count):
			var particle = mesh.get_particle_at(i)
			if particle != null:
				particle.set_global_position(particle.get_global_position() + offset)

		if "connector" in player and is_instance_valid(player.connector):
			player.connector.global_position = target_pos

		if "prev_position" in player:
			player.prev_position = target_pos
		if "_previous_pos" in player:
			player._previous_pos = target_pos
		_reset_softbody_motion_state(target_pos)
		return

	player.global_position = target_pos

func _reset_softbody_motion_state(target_pos: Vector2) -> void:
	if not is_instance_valid(player):
		return

	if "velocity" in player:
		player.velocity = Vector2.ZERO
	if "inherited_velocity" in player:
		player.inherited_velocity = Vector2.ZERO
	if "apply_inherited_once" in player:
		player.apply_inherited_once = false
	if "prev_position" in player:
		player.prev_position = target_pos
	if "_previous_pos" in player:
		player._previous_pos = target_pos

func _is_water_form_active() -> bool:
	return is_instance_valid(player) and "_is_water" in player and player._is_water

# --- Surface / Plant Stick ---

func can_attach_to_sticky_surface() -> bool:
	if death_transition_in_progress:
		return false
	if is_form_transition_lock_active():
		return false
	if _plant_regrab_timer > 0.0:
		return false
	return _is_water_form_active()

func can_attach_to_plant() -> bool:
	return can_attach_to_sticky_surface()

func begin_surface_stick(source: Node2D, source_normal: Vector2 = Vector2.ZERO) -> void:
	if not can_attach_to_sticky_surface():
		return
	if not is_instance_valid(source):
		return

	var anchor_position := _get_player_position_for_stick()
	_stick_source = source
	_stick_anchor_position = anchor_position
	_stick_anchor_local = source.to_local(anchor_position)
	if source_normal.length_squared() > 0.0001:
		_stick_normal = source_normal.normalized()
	else:
		var from_source := anchor_position - source.global_position
		_stick_normal = (from_source if from_source.length_squared() > 0.0001 else Vector2.UP).normalized()
	is_stick = true

func begin_plant_stick(source: Node2D, source_normal: Vector2 = Vector2.ZERO) -> void:
	begin_surface_stick(source, source_normal)

func clear_surface_stick(apply_cooldown := true) -> void:
	var regrab_cooldown := _get_active_stick_regrab_cooldown()
	is_stick = false
	_stick_source = null
	_stick_anchor_local = Vector2.ZERO
	if apply_cooldown:
		_plant_regrab_timer = regrab_cooldown

func clear_plant_stick(apply_cooldown := true) -> void:
	clear_surface_stick(apply_cooldown)

func get_surface_stick_force(blob_position: Vector2, movement_input: Vector2 = Vector2.ZERO) -> Vector2:
	if not is_stick:
		return Vector2.ZERO
	if not is_instance_valid(_stick_source):
		clear_surface_stick(false)
		return Vector2.ZERO

	var target_position := _get_active_stick_target_position()
	var to_target := target_position - blob_position
	if to_target.length_squared() <= 0.0001:
		return Vector2.ZERO

	var max_offset = max(0.001, _get_active_stick_max_offset())
	if to_target.length() > max_offset:
		to_target = to_target.normalized() * max_offset

	var base_stick_force := to_target * _get_active_stick_force_strength()
	var neutral_push := _stick_normal * _get_active_stick_hold_force()
	return base_stick_force + neutral_push

func get_plant_stick_force(blob_position: Vector2, movement_input: Vector2 = Vector2.ZERO) -> Vector2:
	return get_surface_stick_force(blob_position, movement_input)

func consume_surface_stick_jump_impulse(movement_input: Vector2 = Vector2.ZERO) -> Vector2:
	if not is_stick:
		return Vector2.ZERO
	if is_instance_valid(_stick_source):
		if _stick_source.has_method("get_stick_release_direction"):
			_stick_normal = _stick_source.get_stick_release_direction(player, movement_input)
		elif _stick_source.has_method("get_counterforce_direction_for_jump"):
			_stick_normal = _stick_source.get_counterforce_direction_for_jump(player, movement_input)

	var launch_dir := _stick_normal
	if launch_dir.length_squared() <= 0.0001:
		launch_dir = Vector2.UP
	var launch_force := _get_active_stick_release_force()
	clear_surface_stick(true)
	_begin_surface_jump_force_lock()
	return launch_dir.normalized() * launch_force

func consume_plant_bounce_force(movement_input: Vector2 = Vector2.ZERO) -> Vector2:
	return consume_surface_stick_jump_impulse(movement_input)

func is_surface_stick_active() -> bool:
	return is_stick and is_instance_valid(_stick_source)

func get_surface_stick_source() -> Node2D:
	if not is_surface_stick_active():
		return null
	return _stick_source

func is_plant_stick_active() -> bool:
	return is_surface_stick_active()

func get_plant_stick_source() -> Node2D:
	return get_surface_stick_source()

func should_suppress_surface_external_forces() -> bool:
	return _surface_jump_force_lock_timer > 0.0

func get_surface_stick_feedback_progress() -> float:
	if not is_surface_stick_active():
		return 0.0
	if _stick_source != null:
		if _stick_source.has_method("get_stick_feedback_ratio"):
			return clamp(float(_stick_source.get_stick_feedback_ratio()), 0.0, 1.0)
		if _stick_source.has_method("get_contact_timer_ratio"):
			return clamp(float(_stick_source.get_contact_timer_ratio()), 0.0, 1.0)
	return 0.0

func get_plant_danger_progress() -> float:
	return get_surface_stick_feedback_progress()

func is_surface_stick_feedback_critical() -> bool:
	if not is_surface_stick_active():
		return false
	if _stick_source != null:
		if _stick_source.has_method("is_stick_feedback_critical"):
			return bool(_stick_source.is_stick_feedback_critical())
		if _stick_source.has_method("is_danger_critical"):
			return bool(_stick_source.is_danger_critical())
	return get_surface_stick_feedback_progress() >= 0.85

func is_plant_danger_critical() -> bool:
	return is_surface_stick_feedback_critical()

func _get_active_stick_target_position() -> Vector2:
	if is_instance_valid(_stick_source):
		if _stick_source.has_method("get_stick_target_position"):
			var source_target = _stick_source.get_stick_target_position(_stick_anchor_local, _stick_anchor_position, _stick_normal)
			if source_target is Vector2:
				return source_target
		return _stick_source.to_global(_stick_anchor_local)
	return _stick_anchor_position

func _get_active_stick_force_strength() -> float:
	if is_instance_valid(_stick_source) and _stick_source.has_method("get_stick_force_strength"):
		return float(_stick_source.get_stick_force_strength())
	return plant_stick_force

func _get_active_stick_hold_force() -> float:
	if is_instance_valid(_stick_source) and _stick_source.has_method("get_stick_hold_force"):
		return float(_stick_source.get_stick_hold_force())
	return plant_input_counter_force * plant_input_counter_min

func _get_active_stick_max_offset() -> float:
	if is_instance_valid(_stick_source) and _stick_source.has_method("get_stick_max_offset"):
		return float(_stick_source.get_stick_max_offset())
	return plant_stick_max_offset

func _get_active_stick_release_force() -> float:
	if is_instance_valid(_stick_source) and _stick_source.has_method("get_stick_release_force"):
		return float(_stick_source.get_stick_release_force())
	return plant_bounce_force * 1.2

func _get_active_stick_regrab_cooldown() -> float:
	if is_instance_valid(_stick_source) and _stick_source.has_method("get_stick_regrab_cooldown"):
		return float(_stick_source.get_stick_regrab_cooldown())
	return plant_regrab_cooldown

func _begin_surface_jump_force_lock() -> void:
	_surface_jump_force_lock_timer = max(_surface_jump_force_lock_timer, surface_jump_force_lock_duration)
	if not is_instance_valid(player):
		return
	if player.name != "Player":
		return
	player.velocity_limit = 0.0
	if "use_custom_gravity" in player:
		player.use_custom_gravity = true
	if "custom_gravity" in player:
		player.custom_gravity = Vector2.ZERO

func _get_player_position_for_stick() -> Vector2:
	if not is_instance_valid(player):
		return Vector2.ZERO
	if player.has_method("get_blob_position"):
		return player.get_blob_position()
	return player.global_position

# --- Respawn Markers & Teleport ---

func _get_respawn_marker(room_num: int) -> Marker2D:
	if respawn_points.has(room_num):
		return respawn_points[room_num]
	return null

func set_room_base_temperature(base_temperature: float) -> void:
	_room_base_temperature = clamp(base_temperature, temperature_min, temperature_max)

func get_temperature_stamina_ratio() -> float:
	var stamina_capacity = max(0.01, temperature_stamina_capacity)
	return clamp(_temperature_stamina / stamina_capacity, 0.0, 1.0)

func is_temperature_input_active() -> bool:
	return _temperature_input_active

func is_temperature_stamina_exhausted() -> bool:
	return _temperature_stamina_exhausted

func is_temperature_actively_changing() -> bool:
	return _temperature_actively_changing

func _ensure_temperature_stamina_indicator() -> void:
	if is_instance_valid(_temperature_stamina_indicator):
		return

	var scene := get_tree().current_scene
	if scene == null:
		return

	_temperature_stamina_indicator = scene.find_child("TemperatureStaminaIndicator", true, false) as Node2D
	if not is_instance_valid(_temperature_stamina_indicator):
		return

	if _temperature_stamina_indicator.has_method("set_player_state"):
		_temperature_stamina_indicator.call("set_player_state", self)
	if _temperature_stamina_indicator.has_method("set_follow_offset"):
		_temperature_stamina_indicator.call("set_follow_offset", temp_indicator_offset)

func _update_temperature_stamina_indicator() -> void:
	_ensure_temperature_stamina_indicator()
	if not is_instance_valid(_temperature_stamina_indicator):
		return

	_temperature_stamina_indicator.z_index = temp_indicator_z_index
	if _temperature_stamina_indicator.has_method("set_player_state"):
		_temperature_stamina_indicator.call("set_player_state", self)
	if _temperature_stamina_indicator.has_method("set_follow_offset"):
		_temperature_stamina_indicator.call("set_follow_offset", temp_indicator_offset)

# --- Temperature System ---

func temp_change(delta: float) -> void:
	if delta <= 0.0:
		return

	_temperature_actively_changing = false
	var stamina_capacity = max(0.01, temperature_stamina_capacity)

	var half_range = max(0.0, temperature_room_delta_cap)
	var min_allowed_temp = max(temperature_min, _room_base_temperature - half_range)
	var max_allowed_temp = min(temperature_max, _room_base_temperature + half_range)
	if min_allowed_temp > max_allowed_temp:
		var clamped_base = clamp(_room_base_temperature, temperature_min, temperature_max)
		min_allowed_temp = clamped_base
		max_allowed_temp = clamped_base

	var holding_up := Input.is_action_pressed("Temp_Up")
	var holding_down := Input.is_action_pressed("Temp_Down")
	var input_direction := 0.0
	if holding_up != holding_down:
		input_direction = 1.0 if holding_up else -1.0

	temp_up = input_direction > 0.0
	temp_down = input_direction < 0.0
	_temperature_input_active = not is_zero_approx(input_direction)

	if _temperature_input_active and not _temperature_stamina_exhausted:
		var before_input_temperature := temperature
		temperature += input_direction * temperature_input_speed * delta
		temperature = clamp(temperature, min_allowed_temp, max_allowed_temp)
		_temperature_actively_changing = abs(temperature - before_input_temperature) > 0.0001
		_temperature_stamina -= (delta / max(0.01, temperature_stamina_duration)) * stamina_capacity
		if _temperature_stamina <= 0.0:
			_temperature_stamina = 0.0
			_temperature_stamina_exhausted = true
	elif not _temperature_input_active:
		_temperature_stamina += temperature_stamina_recovery_rate * delta * stamina_capacity
		if _temperature_stamina >= temperature_stamina_resume_threshold * stamina_capacity:
			_temperature_stamina_exhausted = false

	_temperature_stamina = clamp(_temperature_stamina, 0.0, stamina_capacity)

	var return_speed := temperature_idle_return_speed
	if _temperature_stamina_exhausted:
		return_speed = temperature_exhausted_return_speed
	elif _temperature_input_active:
		return_speed = 0.0

	if return_speed > 0.0:
		temperature = move_toward(temperature, _room_base_temperature, return_speed * delta)

	temperature = clamp(temperature, min_allowed_temp, max_allowed_temp)
	temp_cooldown = 0.0

	if _temperature_actively_changing:
		if SfxManager != null and SfxManager.has_method("play_temp_change"):
			SfxManager.play_temp_change(input_direction > 0.0)
	elif SfxManager != null and SfxManager.has_method("stop_temp_change_feedback"):
		SfxManager.stop_temp_change_feedback()
			

# Evaluate whether the current temperature warrants a form change and flag the player.
func check_temp_form() -> void:
	var next_form := ""
	if temperature <= ice_threshold:
		next_form = FORM_ICE
	elif temperature >= water_threshold and temperature < vapor_threshold:
		next_form = FORM_WATER
	elif temperature >= vapor_threshold:
		next_form = FORM_VAPOR

	if next_form.is_empty():
		return

	var previous_form := _current_form
	_current_form = next_form

	_is_ice = next_form == FORM_ICE
	_is_water = next_form == FORM_WATER
	_is_vapor = next_form == FORM_VAPOR

	player._is_ice = _is_ice
	player._is_water = _is_water
	player._is_vapor = _is_vapor

	if not previous_form.is_empty() and previous_form != next_form:
		_apply_form_transition_stamina_cost(next_form)

func get_current_form() -> String:
	if _current_form.is_empty() and is_instance_valid(player):
		return _detect_form_from_player(player)
	return _current_form

func _apply_form_transition_stamina_cost(target_form: String) -> void:
	var cost_ratio := 0.0
	match target_form:
		FORM_ICE:
			cost_ratio = temperature_stamina_cost_to_ice
		FORM_VAPOR:
			cost_ratio = temperature_stamina_cost_to_vapor
		_:
			cost_ratio = 0.0

	if cost_ratio <= 0.0:
		return

	var stamina_capacity = max(0.01, temperature_stamina_capacity)
	_temperature_stamina = clamp(_temperature_stamina - (cost_ratio * stamina_capacity), 0.0, stamina_capacity)
	if _temperature_stamina <= 0.0:
		_temperature_stamina_exhausted = true
	
