## Vapor blob player controller.
##
## Floaty softbody movement using QuarkPhysics. The blob is always rising
## slightly and the player steers with directional input. Zone detection
## (water, currents, winds) uses the same polygon-overlap helper as the water
## form. Manages trail spawning, death feedback, and plant-danger visuals.
extends QSoftBodyNode

const FeedbackVfx: GDScript = preload("res://Scripts/Player/player_feedback_vfx.gd")

# --- Inspector ---

@export_group("Object References")
@export var face:          AnimatedSprite2D
@export var mesh:          QMeshPolygonNode
@export var camera:        Camera2D
@export var player_states: Node
@export var connector:     Node2D
@export var light:         Light2D

@export_group("Blob Physics")
@export var _shape_matching:           bool  = false
@export var _area_perserving:          bool  = true
@export var _area_perserving_rate:     float = 0.6
@export var _area_perserving_rigidity: float = 0.4
@export var _rigidity:                 float = 0.01

@export_group("Movement")
@export var speed:        float = 0.3
@export var float_force:  float = 0.55  # Constant upward buoyancy applied every frame.
@export var expand_speed: float = 1.0

@export_group("Death Feedback")
@export var death_knockback_force_scale:  float = 0.12
@export var death_knockback_burst_frames: int   = 8
@export var death_hit_effect_strength:    float = 1.0
@export var death_hit_shake_intensity:    float = 36.0
@export var death_hit_flash_speed:        float = 42.0

@export_group("Plant Danger Feedback")
@export var plant_warning_start_ratio:      float = 0.55
@export var plant_warning_mid_color:        Color = Color(1.0, 0.75, 0.38, 0.95)
@export var plant_warning_critical_color:   Color = Color(1.0, 0.2, 0.2, 1.0)
@export var plant_warning_max_stroke_width: float = 8.0
@export var plant_warning_min_flash_hz:     float = 3.5
@export var plant_warning_max_flash_hz:     float = 11.0

@export_group("Feedback VFX")
@export_range(0.1, 2.0, 0.05) var feedback_particle_amount_scale:  float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_speed_scale:   float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_size_scale:    float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_spread_scale:  float = 1.0
@export_range(0.0, 1.5, 0.05) var feedback_particle_gravity_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var feedback_glow_energy_scale:      float = 1.0
@export_range(0.0, 2.0, 0.05) var feedback_glow_scale_scale:       float = 1.0

# --- Internal State ---

# Form flags — set by PlayerState on spawn, not exposed to the inspector.
var _is_water: bool = false
var _is_ice:   bool = false
var _is_vapor: bool = true

var current_trail:        Trail   = null
var prev_position:        Vector2 = Vector2.ZERO
var velocity:             Vector2 = Vector2.ZERO
var inherited_velocity:   Vector2 = Vector2.ZERO
var apply_inherited_once: bool    = true

# Zone detection flags
var in_water:    bool = false
var in_currentr: bool = false
var in_currentl: bool = false
var in_currentd: bool = false
var in_currentu: bool = false
var in_windr:    bool = false
var in_windl:    bool = false
var in_windu:    bool = false
var in_windd:    bool = false

# Death / feedback state
var _death_feedback_applied:      bool           = false
var _hit_material:                ShaderMaterial = null
var _death_knockback_frames_left: int            = 0
var _death_knockback_dir:         Vector2        = Vector2.ZERO
var _death_knockback_force:       float          = 0.0
var _base_stroke_color:           Color          = Color.WHITE
var _base_stroke_width:           float          = 1.0
var _plant_warning_visual_active: bool           = false

var _vapor_burst_cooldown:  float   = 0.0
var _previous_input_vector: Vector2 = Vector2.ZERO
var _previous_pos:          Vector2 = Vector2.ZERO



# --- Zone Detection ---

# Returns true if the blob center is inside any zone node belonging to [group].
# Each zone node must have at least one CollisionPolygon2D child defining its shape.
func _check_zone(group: StringName) -> bool:
	var pos := mesh.get_average_position()
	for zone in get_tree().get_nodes_in_group(group):
		for child in zone.get_children():
			if child is CollisionPolygon2D:
				var world_poly: Array[Vector2] = []
				for p in (child as CollisionPolygon2D).polygon:
					world_poly.append(child.to_global(p))
				if Geometry2D.is_point_in_polygon(pos, world_poly):
					return true
	return false


func _update_zones() -> void:
	in_water    = _check_zone(&"water")
	in_currentr = _check_zone(&"currentr")
	in_currentl = _check_zone(&"currentl")
	in_currentd = _check_zone(&"currentd")
	in_currentu = _check_zone(&"currentu")
	in_windr    = _check_zone(&"wind_r")
	in_windl    = _check_zone(&"wind_l")
	in_windu    = _check_zone(&"wind_u")
	in_windd    = _check_zone(&"wind_d")


# Public wrappers kept for compatibility with external callers.
func check_water()    -> void: in_water    = _check_zone(&"water")
func check_currentr() -> void: in_currentr = _check_zone(&"currentr")
func check_currentl() -> void: in_currentl = _check_zone(&"currentl")
func check_currentd() -> void: in_currentd = _check_zone(&"currentd")
func check_currentu() -> void: in_currentu = _check_zone(&"currentu")
func check_windr()    -> void: in_windr    = _check_zone(&"wind_r")
func check_windl()    -> void: in_windl    = _check_zone(&"wind_l")
func check_windu()    -> void: in_windu    = _check_zone(&"wind_u")
func check_windd()    -> void: in_windd    = _check_zone(&"wind_d")


# --- Position / Velocity API ---

func get_blob_position() -> Vector2:
	return mesh.get_average_position()


func get_blob_velocity() -> Vector2:
	# QSoftBodyNode has no built-in velocity. Derive it from position delta.
	return mesh.get_average_position() - _previous_pos



func _ready() -> void:
	set_shape_matching_enabled(_shape_matching)
	set_area_preserving_enabled(_area_perserving)
	set_area_preserving_rate(_area_perserving_rate)
	set_area_preserving_rigidity(_area_perserving_rigidity)
	set_rigidity(_rigidity)
	set_self_collision_enabled(true)

	prev_position = mesh.get_average_position()
	connector.position = prev_position

	face          = $Face
	mesh          = $QMeshPolygonNode
	light         = $PointLight2D
	camera        = get_parent().get_node("Camera2D")
	player_states = get_parent().get_node("PlayerState")

	_setup_hit_material()
	_cache_base_stroke_style()
	FeedbackVfx.setup_aura(self, light, FeedbackVfx.FORM_VAPOR, _feedback_vfx_tuning())
	FeedbackVfx.ensure_vapor_ambient(self, _feedback_vfx_tuning())


func _process(_delta: float) -> void:
	# QuarkPhysics does not always fire _physics_process; sync the connector here
	# to prevent it from falling one frame behind.
	connector.position = mesh.get_average_position()


func _physics_process(delta: float) -> void:
	var current_position := mesh.get_average_position()
	connector.position = current_position
	velocity           = (current_position - prev_position) / delta
	prev_position      = current_position

	if _vapor_burst_cooldown > 0.0:
		_vapor_burst_cooldown -= delta

	# --- Death ---

	var is_dying: bool = (
		player_states != null
		and "death_transition_in_progress" in player_states
		and player_states.death_transition_in_progress
	)

	if is_dying:
		_apply_death_feedback_once()
		_apply_death_knockback_burst()
		_reset_plant_warning_visual()
	else:
		_death_feedback_applied      = false
		_death_knockback_frames_left = 0
		_update_plant_warning_visual()

	# --- Form Transition ---

	if _is_water:
		if player_states and player_states.has_method("request_form_transition") and player_states.request_form_transition(self, "water"):
			if current_trail:
				current_trail.stop()
				current_trail = null
			return

	# --- Inherited Velocity (on form swap) ---

	if apply_inherited_once and inherited_velocity.length() > 0.01:
		apply_force(inherited_velocity * 0.01)
		apply_inherited_once = false

	# --- Face & Light ---

	if face:
		if is_dying and face.sprite_frames != null and face.sprite_frames.has_animation("sad"):
			face.play("sad")
		else:
			face.play("default")
		face.global_position = current_position
	if light:
		light.global_position = current_position

	# --- Input ---

	var input_vector := Vector2(
		float(Input.is_action_pressed("ui_right")) - float(Input.is_action_pressed("ui_left")),
		float(Input.is_action_pressed("ui_down"))  - float(Input.is_action_pressed("ui_up"))
	)

	# --- VFX ---

	var motion_ratio := clampf(velocity.length() / 280.0, 0.0, 1.0)
	FeedbackVfx.update_aura(self, light, FeedbackVfx.FORM_VAPOR, motion_ratio, delta, _feedback_vfx_tuning())
	FeedbackVfx.update_vapor_ambient(self, motion_ratio, _feedback_vfx_tuning())

	var wants_burst: bool = (
		input_vector.length_squared() > 0.0
		and (_previous_input_vector.length_squared() == 0.0 or _previous_input_vector.dot(input_vector) < 0.35)
	)
	if wants_burst and _vapor_burst_cooldown <= 0.0:
		FeedbackVfx.spawn_vapor_burst(self, current_position, -input_vector * 180.0, 0.85 + motion_ratio * 0.5, _feedback_vfx_tuning())
		FeedbackVfx.pulse_aura(self, light, FeedbackVfx.FORM_VAPOR, 0.65 + motion_ratio * 0.35, _feedback_vfx_tuning())
		_vapor_burst_cooldown = 0.18

	_previous_input_vector = input_vector

	# --- Trail ---

	if current_trail == null:
		current_trail = Trail.create()
		get_tree().current_scene.add_child(current_trail)
	current_trail.add_point_world(current_position)

	# --- Zones ---

	_update_zones()

	# --- Environmental Forces ---

	# Constant buoyancy
	apply_force(Vector2(0, -float_force))

	if in_water:
		apply_force(Vector2(0, -float_force))
	if in_currentu:
		apply_force(Vector2(0, -float_force * 1.5))
	if in_currentd:
		apply_force(Vector2(0,  float_force * 0.5))
	if in_currentl:
		apply_force(Vector2(-float_force, 0))
	if in_currentr:
		apply_force(Vector2( float_force, 0))
	if in_windr:
		apply_force(Vector2( 1.0, 0))
	if in_windl:
		apply_force(Vector2(-1.0, 0))
	if in_windu:
		apply_force(Vector2(0, -1.0))
	if in_windd:
		apply_force(Vector2(0,  1.0))

	# --- Directional Thrust ---

	apply_force(input_vector * speed)

	_previous_pos = current_position




# --- Death Feedback ---

func _apply_death_knockback_burst() -> void:
	if _death_knockback_frames_left <= 0:
		return
	apply_force(_death_knockback_dir * _death_knockback_force)
	_death_knockback_frames_left -= 1


func _apply_death_feedback_once() -> void:
	if _death_feedback_applied:
		return
	_death_feedback_applied = true

	var knockback_dir := Vector2.UP
	if velocity.length_squared() > 0.0001:
		knockback_dir = -velocity.normalized()

	var knockback_force := 16.0
	if player_states != null and "death_knockback_strength" in player_states:
		knockback_force = float(player_states.death_knockback_strength) * death_knockback_force_scale

	_death_knockback_dir         = knockback_dir
	_death_knockback_force       = knockback_force
	_death_knockback_frames_left = max(1, death_knockback_burst_frames)
	apply_force(knockback_dir * knockback_force * 1.4)

	if _hit_material != null:
		_hit_material.set_shader_parameter("hit_effect",       death_hit_effect_strength)
		_hit_material.set_shader_parameter("shake_intensity",  death_hit_shake_intensity)
		_hit_material.set_shader_parameter("flash_speed",      death_hit_flash_speed)
		_hit_material.set_shader_parameter("get_hit",          true)


# --- Material / Shader Setup ---

func _setup_hit_material() -> void:
	_hit_material = null
	if mesh == null:
		return
	if mesh.material is ShaderMaterial:
		mesh.material = (mesh.material as ShaderMaterial).duplicate()
		_hit_material = mesh.material as ShaderMaterial
		_hit_material.set_shader_parameter("get_hit", false)


func _cache_base_stroke_style() -> void:
	if mesh == null:
		return
	_base_stroke_color = mesh.stroke_color
	_base_stroke_width = mesh.stroke_width


# --- Plant Danger Visual ---

func _update_plant_warning_visual() -> void:
	if mesh == null or player_states == null or not player_states.has_method("get_plant_danger_progress"):
		_reset_plant_warning_visual()
		return

	var progress := clamp(float(player_states.get_plant_danger_progress()), 0.0, 1.0)
	if progress <= 0.0:
		_reset_plant_warning_visual()
		return

	var warning_ratio := clamp(plant_warning_start_ratio, 0.05, 0.98)
	var color: Color
	if progress < warning_ratio:
		color = _base_stroke_color.lerp(plant_warning_mid_color, progress / warning_ratio)
	else:
		var critical_blend := (progress - warning_ratio) / max(0.001, 1.0 - warning_ratio)
		color = plant_warning_mid_color.lerp(plant_warning_critical_color, critical_blend)
		var flash_hz  := lerp(plant_warning_min_flash_hz, plant_warning_max_flash_hz, critical_blend)
		var pulse     := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * flash_hz)
		color          = color.lerp(Color.WHITE, 0.22 * pulse)
		color.a        = clamp(color.a * (0.72 + 0.36 * pulse), 0.0, 1.0)

	mesh.stroke_color = color
	mesh.stroke_width = lerp(_base_stroke_width, plant_warning_max_stroke_width, progress)
	_plant_warning_visual_active = true


func _reset_plant_warning_visual() -> void:
	if not _plant_warning_visual_active or mesh == null:
		return
	mesh.stroke_color            = _base_stroke_color
	mesh.stroke_width            = _base_stroke_width
	_plant_warning_visual_active = false


# --- VFX Tuning ---

func _feedback_vfx_tuning() -> Dictionary:
	return {
		"particle_amount_scale":  feedback_particle_amount_scale,
		"particle_speed_scale":   feedback_particle_speed_scale,
		"particle_size_scale":    feedback_particle_size_scale,
		"particle_spread_scale":  feedback_particle_spread_scale,
		"particle_gravity_scale": feedback_particle_gravity_scale,
		"glow_energy_scale":      feedback_glow_energy_scale,
		"glow_scale_scale":       feedback_glow_scale_scale,
	}

