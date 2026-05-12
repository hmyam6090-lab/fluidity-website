extends QSoftBodyNode

# Water blob player controller. Handles softbody physics movement, environmental zone
# detection (water, currents, wind, clouds), jump input buffering, and visual feedback
# for death and plant-danger states. All form and state logic is delegated to PlayerState.

const FeedbackVfx:       GDScript  = preload("res://Scripts/Player/player_feedback_vfx.gd")
const JUMP_SMOKE_SCENE:  PackedScene = preload("res://Scenes/Player/jumpsmoke.tscn")


# --- Inspector Exports ---

@export_group("Object References")
@export var face:          AnimatedSprite2D
@export var mesh:          QMeshPolygonNode
@export var camera:        Camera2D
@export var player_states: Node
@export var connector:     Node2D
@export var light:         PointLight2D

@export_group("Blob Physics")
@export var _shape_matching:           bool  = false
@export var _area_perserving:          bool  = true
@export var _area_perserving_rate:     float = 0.7
@export var _area_perserving_rigidity: float = 0.2
@export var _rigidity:                 float = 0.05

@export_group("Movement")
@export var speed:                    float = 0.21
@export var jump_force:               float = -5.5
@export var floor_timer:              int   = 0
@export var jump_input_buffer_frames: int   = 4
@export var fall_gravity_multiplier:  float = 1.8

@export_group("Death Feedback")
@export var death_knockback_force_scale:  float = 0.03
@export var death_knockback_burst_frames: int   = 3
@export var death_overflow_duration:      float = 0.24
@export var death_overflow_wobble_cycles: float = 2.0
@export var death_overflow_wobble_amount: float = 0.18
@export var death_burst_lead_time:        float = 0.08

@export_group("Plant Danger Feedback")
@export var plant_warning_start_ratio:    float = 0.55
@export var plant_warning_mid_color:      Color = Color(1.0, 0.75, 0.38, 0.95)
@export var plant_warning_critical_color: Color = Color(1.0, 0.2,  0.2,  1.0)
@export var plant_warning_max_stroke_width: float = 2.2
@export var plant_warning_min_flash_hz:   float = 3.5
@export var plant_warning_max_flash_hz:   float = 11.0

@export_group("Roll SFX")
@export var roll_sound_min_speed: float = 1.0
@export var roll_sound_max_speed: float = 200.0
@export var roll_sound_max_db:    float = 0.0
@export var roll_sound_min_db:    float = -40.0

@export_group("Feedback VFX")
@export_range(0.1, 2.0, 0.05) var feedback_particle_amount_scale:  float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_speed_scale:   float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_size_scale:    float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_spread_scale:  float = 1.0
@export_range(0.0, 1.5, 0.05) var feedback_particle_gravity_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var feedback_glow_energy_scale:      float = 1.0
@export_range(0.0, 2.0, 0.05) var feedback_glow_scale_scale:       float = 1.0


# --- Form State (written by PlayerState, read here to trigger transitions) ---

var _is_water: bool = true
var _is_ice:   bool = false
var _is_vapor: bool = false


# --- Runtime State ---

var prev_position:        Vector2 = Vector2.ZERO
var velocity:             Vector2 = Vector2.ZERO
var inherited_velocity:   Vector2 = Vector2.ZERO
var apply_inherited_once: bool    = true
var transforming:         bool    = false
var _previous_pos:        Vector2 = Vector2.ZERO
var _jump_buffer_frames_left: int = 0

# Zone detection flags, refreshed every physics frame via _update_zones().
var in_water:    bool = false
var in_currentr: bool = false
var in_currentl: bool = false
var in_currentd: bool = false
var in_currentu: bool = false
var in_currentdr: bool = false
var in_windr:    bool = false
var in_windl:    bool = false
var in_windu:    bool = false
var in_windd:    bool = false
var on_cloudl:   bool = false
var on_cloudr:   bool = false

# Death feedback
var _death_feedback_applied:     bool    = false
var _hit_material:               ShaderMaterial = null
var _death_knockback_frames_left: int    = 0
var _death_knockback_dir:        Vector2 = Vector2.ZERO
var _death_knockback_force:      float   = 0.0
var _death_elapsed:              float   = 0.0
var _death_burst_spawned:        bool    = false

# Cached softbody defaults, restored after the death animation ends.
var _base_shape_matching:           bool  = false
var _base_area_preserving:          bool  = true
var _base_area_preserving_rate:     float = 0.7
var _base_area_preserving_rigidity: float = 0.2
var _base_rigidity:                 float = 0.05

# Stroke style cache for plant-danger visuals.
var _base_stroke_color:        Color = Color.WHITE
var _base_stroke_width:        float = 1.0
var _plant_warning_visual_active: bool = false

# Low-pass filter for the water-submersion audio effect (fetched in _ready).
var _water_lowpass: AudioEffectLowPassFilter = null



# --- Lifecycle ---

func _ready() -> void:
	set_shape_matching_enabled(_shape_matching)
	set_area_preserving_enabled(_area_perserving)
	set_area_preserving_rate(_area_perserving_rate)
	set_area_preserving_rigidity(_area_perserving_rigidity)
	set_rigidity(_rigidity)
	set_self_collision_enabled(true)
	connect("collision", _on_body_collision)

	face          = $Face
	light         = $PointLight2D
	mesh          = $QMeshPolygonNode
	camera        = get_parent().get_node("Camera2D")
	player_states = get_parent().get_node("PlayerState")

	prev_position = mesh.get_average_position()

	# Fetch the water-submersion low-pass filter from the Master bus (effect slot 0).
	_water_lowpass = AudioServer.get_bus_effect(AudioServer.get_bus_index("Master"), 0) as AudioEffectLowPassFilter

	_setup_hit_material()
	_cache_base_stroke_style()
	FeedbackVfx.setup_aura(self, light, FeedbackVfx.FORM_WATER, _feedback_vfx_tuning())

	# Cache the softbody defaults so they can be restored after the death animation.
	_base_shape_matching           = _shape_matching
	_base_area_preserving          = _area_perserving
	_base_area_preserving_rate     = _area_perserving_rate
	_base_area_preserving_rigidity = _area_perserving_rigidity
	_base_rigidity                 = _rigidity

	RenderingServer.set_default_clear_color(Color.GRAY)


func _process(_delta: float) -> void:
	# Keep the connector synced every frame; QuarkPhysics does not always
	# fire _physics_process, so this prevents the connector falling behind.
	connector.position = mesh.get_average_position()


# --- Zone Detection ---

# Returns true if the blob's centre is inside any collision polygon belonging
# to nodes in the given group. Used for all water, current, wind, and cloud checks.
func _check_zone(group: StringName) -> bool:
	var pos := mesh.get_average_position()
	for zone in get_tree().get_nodes_in_group(group):
		for child in zone.get_children():
			if child is CollisionPolygon2D:
				var global_poly: Array = []
				for p in (child as CollisionPolygon2D).polygon:
					global_poly.append(child.to_global(p))
				if Geometry2D.is_point_in_polygon(pos, global_poly):
					return true
	return false


# Refreshes all zone flags in one pass each physics frame.
func _update_zones() -> void:
	in_water     = _check_zone(&"water")
	in_currentr  = _check_zone(&"currentr")
	in_currentl  = _check_zone(&"currentl")
	in_currentd  = _check_zone(&"currentd")
	in_currentu  = _check_zone(&"currentu")
	in_currentdr = _check_zone(&"currentdr")
	in_windu     = _check_zone(&"wind_u")
	in_windd     = _check_zone(&"wind_d")
	in_windr     = _check_zone(&"wind_r")
	in_windl     = _check_zone(&"wind_l")
	on_cloudl    = _check_zone(&"cloudl")
	on_cloudr    = _check_zone(&"cloudr")


# Individual wrappers kept as public API in case external nodes call them by name.
func check_water()     -> void: in_water     = _check_zone(&"water")
func check_currentr()  -> void: in_currentr  = _check_zone(&"currentr")
func check_currentl()  -> void: in_currentl  = _check_zone(&"currentl")
func check_currentd()  -> void: in_currentd  = _check_zone(&"currentd")
func check_currentu()  -> void: in_currentu  = _check_zone(&"currentu")
func check_currentdr() -> void: in_currentdr = _check_zone(&"currentdr")
func check_windu()     -> void: in_windu     = _check_zone(&"wind_u")
func check_windd()     -> void: in_windd     = _check_zone(&"wind_d")
func check_windr()     -> void: in_windr     = _check_zone(&"wind_r")
func check_windl()     -> void: in_windl     = _check_zone(&"wind_l")
func check_cloudl()    -> void: on_cloudl    = _check_zone(&"cloudl")
func check_cloudr()    -> void: on_cloudr    = _check_zone(&"cloudr")



# --- Physics Update ---

func _physics_process(delta: float) -> void:
	var current_position := mesh.get_average_position()
	velocity     = (current_position - prev_position) / delta
	prev_position = current_position

	var is_dying: bool = (
		player_states != null
		and "death_transition_in_progress" in player_states
		and player_states.death_transition_in_progress
	)

	# Clear the transforming flag once PlayerState finishes the form swap.
	if transforming and player_states != null and "form_transition_in_progress" in player_states and not player_states.form_transition_in_progress:
		transforming = false

	if is_dying:
		_apply_death_feedback_once()
		_update_death_overflow_visual(delta, current_position)
		_reset_plant_warning_visual()
		_previous_pos = current_position
		return
	else:
		_reset_death_feedback_state()
		_update_plant_warning_visual()

	# --- Input ---

	var right_pressed := Input.is_action_pressed("ui_right") or Input.is_action_pressed("right") or Input.is_action_pressed("R_Arrow")
	var left_pressed  := Input.is_action_pressed("ui_left")  or Input.is_action_pressed("left")  or Input.is_action_pressed("L_Arrow")
	var horizontal_input := int(right_pressed) - int(left_pressed)

	var vertical_input := int(Input.is_action_pressed("ui_down")) - int(Input.is_action_pressed("ui_up"))
	vertical_input    += int(Input.is_action_pressed("D_Arrow"))  - int(Input.is_action_pressed("U_Arrow"))
	vertical_input     = clampi(vertical_input, -1, 1)

	var stick_input := Vector2(horizontal_input, vertical_input)
	var up_arrow_pressed   := Input.is_action_pressed("U_Arrow")
	var down_arrow_pressed := Input.is_action_pressed("D_Arrow")

	var jump_pressed := Input.is_action_just_pressed("ui_accept")
	var jump_held    := Input.is_action_pressed("ui_accept")
	if jump_pressed:
		_jump_buffer_frames_left = max(1, jump_input_buffer_frames)
	elif _jump_buffer_frames_left > 0:
		_jump_buffer_frames_left -= 1

	# --- Surface Stick / Jump ---

	var can_surface_jump := false
	if player_states:
		if player_states.has_method("is_surface_stick_active"):
			can_surface_jump = player_states.is_surface_stick_active()
		elif player_states.has_method("is_plant_stick_active"):
			can_surface_jump = player_states.is_plant_stick_active()

	var wants_surface_jump       := can_surface_jump and (_jump_buffer_frames_left > 0 or jump_held)
	var suppress_external_forces := wants_surface_jump
	if player_states and player_states.has_method("should_suppress_surface_external_forces"):
		suppress_external_forces = suppress_external_forces or player_states.should_suppress_surface_external_forces()

	if player_states and not suppress_external_forces:
		var stick_force := Vector2.ZERO
		if player_states.has_method("get_surface_stick_force"):
			stick_force = player_states.get_surface_stick_force(current_position, stick_input)
		elif player_states.has_method("get_plant_stick_force"):
			stick_force = player_states.get_plant_stick_force(current_position, stick_input)
		if stick_force.length_squared() > 0.0:
			apply_force(stick_force)

	# --- Form Transition Triggers ---

	if _is_vapor and not transforming:
		if player_states and player_states.has_method("request_form_transition") and player_states.request_form_transition(self, "vapor"):
			transforming = true
			return

	if _is_ice and not transforming:
		if player_states and player_states.has_method("request_form_transition") and player_states.request_form_transition(self, "ice"):
			transforming = true
			return

	# Apply velocity inherited from a form transition (one-shot on spawn).
	if apply_inherited_once and inherited_velocity.length() > 0.01:
		apply_force(inherited_velocity * 0.014)
		apply_inherited_once = false

	# --- Face Animation ---

	var face_offset := Vector2.ZERO
	if face:
		if floor_timer > 0 and face.animation == "angry":
			face.animation = "default"
		elif floor_timer <= 0 and face.animation == "default":
			face.animation = "angry"
			face_offset = Vector2(-3, 0)

	light.global_position = current_position
	FeedbackVfx.update_aura(self, light, FeedbackVfx.FORM_WATER, clampf(velocity.length() / 240.0, 0.0, 1.0), delta, _feedback_vfx_tuning())
	face.global_position = current_position - face_offset

	_previous_pos = current_position

	if floor_timer > 0:
		floor_timer -= 1

	# --- Zone Detection ---

	_update_zones()

	# --- Horizontal Movement ---

	if Input.is_action_pressed("ui_right"):
		if velocity.x < 10:
			for i in range(mesh.get_particle_count()):
				var p := mesh.get_particle_at(i)
				p.set_global_position(p.get_global_position() - Vector2(velocity.x * delta * 0.1, 0))
		apply_force(Vector2(speed, 0))
	elif Input.is_action_pressed("ui_left"):
		if velocity.x > 10:
			for i in range(mesh.get_particle_count()):
				var p := mesh.get_particle_at(i)
				p.set_global_position(p.get_global_position() - Vector2(velocity.x * delta * 0.1, 0))
		apply_force(Vector2(-speed, 0))

	# --- Environmental Forces ---

	var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
	var buoy := Vector2(0, -gravity * 0.000306)

	if not suppress_external_forces:
		if in_water:
			apply_force(buoy)
			if up_arrow_pressed:   apply_force(Vector2(0, -speed * 2))
			if down_arrow_pressed: apply_force(Vector2(0,  speed * 2))
		if in_currentr:
			apply_force(buoy + Vector2(0.2, 0))
			if up_arrow_pressed:   apply_force(Vector2(0, -speed * 2))
			if down_arrow_pressed: apply_force(Vector2(0,  speed * 2))
		if in_currentl:
			apply_force(buoy + Vector2(-0.2, 0))
			if up_arrow_pressed:   apply_force(Vector2(0, -speed * 2))
			if down_arrow_pressed: apply_force(Vector2(0,  speed * 2))
		if in_currentd:
			apply_force(buoy + Vector2(0, 0.5))
			if up_arrow_pressed:   apply_force(Vector2(0, -speed * 2))
			if down_arrow_pressed: apply_force(Vector2(0,  speed * 2))
		if in_currentu:
			apply_force(buoy + Vector2(0, -0.2))
			if up_arrow_pressed:   apply_force(Vector2(0, -speed * 2))
			if down_arrow_pressed: apply_force(Vector2(0,  speed * 2))
		if in_currentdr:
			# Downward-right current: reversed buoyancy (sinks) plus diagonal push.
			apply_force(Vector2(0, gravity * -0.000306) + Vector2(0.1, -0.1))
			if up_arrow_pressed:   apply_force(Vector2(0, -speed * 2))
			if down_arrow_pressed: apply_force(Vector2(0,  speed * 2))

		if in_windu:  apply_force(Vector2( 0.0, -0.4))
		if in_windd:  apply_force(Vector2( 0.0,  0.4))
		if in_windr:  apply_force(Vector2( 0.4,  0.0))
		if in_windl:  apply_force(Vector2(-0.4,  0.0))
		if on_cloudl: apply_force(Vector2(-0.15, 0.0))
		if on_cloudr: apply_force(Vector2( 0.15, 0.0))

	# --- Roll SFX ---

	var ground_speed := abs(velocity.x)
	if floor_timer > 0 and ground_speed > roll_sound_min_speed:
		if not $sounds/water_running.playing:
			$sounds/water_running.play()
		var t := clampf((ground_speed - roll_sound_min_speed) / (roll_sound_max_speed - roll_sound_min_speed), 0.0, 1.0)
		$sounds/water_running.volume_db   = lerpf(roll_sound_min_db, roll_sound_max_db, t)
		$sounds/water_running.pitch_scale = lerpf(0.9, 1.2, t)
	else:
		$sounds/water_running.volume_db = lerpf($sounds/water_running.volume_db, roll_sound_min_db, 0.2)
		if $sounds/water_running.volume_db <= roll_sound_min_db + 1.0:
			$sounds/water_running.stop()

	# --- Water Submersion Low-Pass Filter ---

	if _water_lowpass != null:
		if in_water or in_currentd or in_currentr or in_currentl or in_currentu:
			AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Master"), 0, true)
			_water_lowpass.cutoff_hz = lerp(_water_lowpass.cutoff_hz, 1000.0, 0.5)
		else:
			_water_lowpass.cutoff_hz = lerp(_water_lowpass.cutoff_hz, 20000.0, 0.5)
			if _water_lowpass.cutoff_hz > 20000.0:
				AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Master"), 0, false)

	# --- Jump ---

	var wants_ground_jump := _jump_buffer_frames_left > 0 and floor_timer > 0
	if wants_surface_jump:
		var jump_impulse := Vector2.ZERO
		if player_states:
			if player_states.has_method("consume_surface_stick_jump_impulse"):
				jump_impulse = player_states.consume_surface_stick_jump_impulse(stick_input)
			elif player_states.has_method("consume_plant_bounce_force"):
				jump_impulse = player_states.consume_plant_bounce_force(stick_input)
		if jump_impulse.length_squared() > 0.0:
			inherited_velocity   = Vector2.ZERO
			apply_inherited_once = false
			prev_position        = get_blob_position()
			_previous_pos        = prev_position
			apply_force(jump_impulse)
			$sounds/water_jump.pitch_scale = randf_range(0.9, 1.1)
			$sounds/water_jump.play()
			FeedbackVfx.spawn_jump_effect(self, FeedbackVfx.FORM_WATER, get_blob_position() + Vector2(0, 25), velocity * 42.0 + jump_impulse * 48.0, _feedback_vfx_tuning())
			FeedbackVfx.pulse_aura(self, light, FeedbackVfx.FORM_WATER, 1.0, _feedback_vfx_tuning())
			floor_timer              = 0
			_jump_buffer_frames_left = 0
	elif wants_ground_jump:
		var jump_impulse := Vector2(0, jump_force)
		apply_force(jump_impulse)
		$sounds/water_jump.pitch_scale = randf_range(0.9, 1.1)
		$sounds/water_jump.play()
		FeedbackVfx.spawn_jump_effect(self, FeedbackVfx.FORM_WATER, get_blob_position() + Vector2(0, 25), velocity * 42.0 + jump_impulse * 48.0, _feedback_vfx_tuning())
		FeedbackVfx.pulse_aura(self, light, FeedbackVfx.FORM_WATER, 1.0, _feedback_vfx_tuning())
		floor_timer              = 0
		_jump_buffer_frames_left = 0

	# Additional downward gravity on the falling arc for snappier game feel.
	if not suppress_external_forces and velocity.y > 0:
		apply_force(Vector2(0, gravity * 0.000306 * (fall_gravity_multiplier - 1.0)))


# --- Collision ---

func _on_body_collision(_body_node: Node, info: Dictionary) -> void:
	var normal: Vector2 = info["normal"]
	if normal.y < -0.3:
		var was_grounded := floor_timer > 0
		floor_timer = 2
		var landing_speed := max(velocity.y, 0.0)
		if not was_grounded and landing_speed > 55.0:
			FeedbackVfx.spawn_landing_effect(self, FeedbackVfx.FORM_WATER, get_blob_position() + Vector2(0, 28), landing_speed * 120.0, _feedback_vfx_tuning())
			FeedbackVfx.pulse_aura(self, light, FeedbackVfx.FORM_WATER, clampf(landing_speed / 160.0, 0.7, 1.4), _feedback_vfx_tuning())
			$sounds/water_land.pitch_scale = randf_range(0.96, 1.06)
			$sounds/water_land.volume_db   = lerpf(-12.0, -1.5, clampf(landing_speed / 180.0, 0.0, 1.0))
			$sounds/water_land.play()


# --- Position / Velocity API ---

func get_blob_position() -> Vector2:
	return mesh.get_average_position()


func get_blob_velocity() -> Vector2:
	# QSoftBodyNode has no built-in velocity. Derive it from position delta.
	# Camera smooths this externally, so raw delta is not needed here.
	return mesh.get_average_position() - _previous_pos


# --- Death Feedback ---

func _apply_death_knockback_burst() -> void:
	if _death_knockback_frames_left <= 0:
		return
	apply_force(_death_knockback_dir * _death_knockback_force)
	_death_knockback_frames_left -= 1


# The water blob uses its own overflow visual rather than a shader hit-flash.
func prefers_no_death_shader_flash() -> bool:
	return true


func _apply_death_feedback_once() -> void:
	if _death_feedback_applied:
		return
	_death_feedback_applied = true
	_death_elapsed = 0.0
	_death_burst_spawned = false
	if "use_custom_gravity" in self:
		use_custom_gravity = true
		custom_gravity = Vector2.ZERO
	set_shape_matching_enabled(true)
	set_area_preserving_enabled(false)
	set_area_preserving_rate(max(_base_area_preserving_rate, 0.9))
	set_area_preserving_rigidity(0.05)
	set_rigidity(0.008)

	var knockback_dir := Vector2.UP
	if velocity.length_squared() > 0.0001:
		knockback_dir = -velocity.normalized()

	var knockback_force := 16.0
	if player_states != null and "death_knockback_strength" in player_states:
		knockback_force = float(player_states.death_knockback_strength) * death_knockback_force_scale
	_death_knockback_dir   = knockback_dir
	_death_knockback_force = knockback_force
	_death_knockback_frames_left = max(1, death_knockback_burst_frames)
	apply_force(knockback_dir * knockback_force)


func _update_death_overflow_visual(delta: float, current_position: Vector2) -> void:
	_death_elapsed += delta
	_apply_death_knockback_burst()

	if face:
		if face.sprite_frames != null and face.sprite_frames.has_animation("sad"):
			face.play("sad")
		else:
			face.play("default")
		face.global_position = current_position
	if light:
		light.global_position = current_position
	if connector:
		connector.position = current_position

	if mesh:
		var t := clamp(_death_elapsed / max(0.001, death_overflow_duration), 0.0, 1.0)
		var wobble := sin(t * TAU * death_overflow_wobble_cycles) * death_overflow_wobble_amount * (1.0 - t)
		mesh.stroke_width   = max(_base_stroke_width, _base_stroke_width * (1.0 + 0.8 * t + abs(wobble) * 0.9))
		mesh.stroke_color.a = clamp(_base_stroke_color.a * (1.0 + 0.2 * t), 0.0, 1.0)

	var death_delay := 0.6
	if player_states != null and "death_effect_delay" in player_states:
		death_delay = max(0.01, float(player_states.death_effect_delay))
	if not _death_burst_spawned and _death_elapsed >= max(0.01, death_delay - death_burst_lead_time):
		_spawn_water_death_burst(current_position)


func _spawn_water_death_burst(origin: Vector2) -> void:
	_death_burst_spawned = true
	for i in range(3):
		var burst: Node = JUMP_SMOKE_SCENE.instantiate()
		if burst is Node2D:
			(burst as Node2D).global_position = origin + Vector2(randf_range(-16.0, 16.0), randf_range(-12.0, 10.0))
			(burst as Node2D).scale          *= randf_range(1.2, 1.9)
			(burst as Node2D).rotation        = randf_range(-0.45, 0.45)
		if burst is CanvasItem:
			(burst as CanvasItem).modulate = Color(0.58, 0.96, 1.0, 0.95)
		get_tree().current_scene.add_child(burst)


func _reset_death_feedback_state() -> void:
	if not _death_feedback_applied and _death_elapsed <= 0.0:
		return
	_death_feedback_applied      = false
	_death_knockback_frames_left = 0
	_death_elapsed               = 0.0
	_death_burst_spawned         = false
	if "use_custom_gravity" in self:
		use_custom_gravity = false
	set_shape_matching_enabled(_base_shape_matching)
	set_area_preserving_enabled(_base_area_preserving)
	set_area_preserving_rate(_base_area_preserving_rate)
	set_area_preserving_rigidity(_base_area_preserving_rigidity)
	set_rigidity(_base_rigidity)
	_reset_plant_warning_visual()


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
		"particle_amount_scale": feedback_particle_amount_scale,
		"particle_speed_scale":  feedback_particle_speed_scale,
		"particle_size_scale":   feedback_particle_size_scale,
		"particle_spread_scale": feedback_particle_spread_scale,
		"particle_gravity_scale":feedback_particle_gravity_scale,
		"glow_energy_scale":     feedback_glow_energy_scale,
		"glow_scale_scale":      feedback_glow_scale_scale,
	}
