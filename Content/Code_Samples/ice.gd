extends CharacterBody2D

const FeedbackVfx = preload("res://Scripts/Player/player_feedback_vfx.gd")

@export_group("Object References")
@export var camera : Camera2D
@export var player_states : Node


@export_group("Movement")
@export var move_speed: float = 2000.0
@export var jump_force: float = 580.0
@export var acceleration: float = 1500.0
@export var deceleration: float = 1000.0

@export_group("Air Control")
@export var air_acceleration: float = 1000.0
@export var air_deceleration: float = 1000.0
@export var max_fall_speed: float = 2000.0

@export_group("Jump Feel")
@export var gravity: float = 1500.0
@export var fall_gravity_multiplier: float = 1.5  ## Faster falling than rising
@export var jump_buffer_time: float = 0.12        ## Accepts jump input slightly early
@export var coyote_time: float = 0.1              ## Can jump briefly after walking off edge
@export var shatter_threshold: float = move_speed * .8
@export var shatter_warning: float = shatter_threshold * .6

@export_group("Shatter Danger Feedback")
@export var shatter_warning_flash_color: Color = Color(0.08, 0.98, 1.0, 1.0)
@export var shatter_lethal_flash_color: Color = Color(1.0, 0.05, 0.82, 1.0)
@export var shatter_warning_min_flash_speed: float = 10.0
@export var shatter_warning_max_flash_speed: float = 30.0
@export var shatter_warning_min_hit_effect: float = 0.18
@export var shatter_warning_max_hit_effect: float = 0.88
@export var shatter_warning_min_shake: float = 3.0
@export var shatter_warning_max_shake: float = 26.0
@export var shatter_warning_light_boost: float = 0.4
@export var shatter_warning_scale_pulse: float = 0.015
@export var shatter_lethal_scale_pulse: float = 0.045

@export_group("Melt Trail")
@export var melt_trail_enabled: bool = true
@export var melt_trail_min_slide_speed: float = 110.0
@export var melt_trail_width: float = 16.0
@export var melt_trail_point_count: int = 40
@export var melt_trail_fade_duration: float = 1.2
@export var melt_trail_offset_y: float = -1.0
@export var melt_trail_color: Color = Color(0.52, 0.90, 1.0, 0.38)

@export_group("Plant Danger Feedback")
@export var plant_warning_start_ratio: float = 0.55
@export var plant_warning_mid_tint: Color = Color(1.0, 0.78, 0.42, 1.0)
@export var plant_warning_critical_tint: Color = Color(1.0, 0.25, 0.25, 1.0)
@export var plant_warning_hit_effect: float = 0.55
@export var plant_warning_min_flash_speed: float = 12.0
@export var plant_warning_max_flash_speed: float = 24.0

@export_group("Feedback VFX")
@export_range(0.1, 2.0, 0.05) var feedback_particle_amount_scale: float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_speed_scale: float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_size_scale: float = 1.0
@export_range(0.1, 2.0, 0.05) var feedback_particle_spread_scale: float = 1.0
@export_range(0.0, 1.5, 0.05) var feedback_particle_gravity_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var feedback_glow_energy_scale: float = 1.0
@export_range(0.0, 2.0, 0.05) var feedback_glow_scale_scale: float = 1.0

var _anim_squash: float = 1.0
var _anim_lean: float = 0.0
var _bob_timer: float = 0.0
var _was_on_floor_anim: bool = false
var _shake_offset: Vector2 = Vector2.ZERO
var _base_scale: Vector2 = Vector2.ZERO
var _left_melt_trail: Trail = null
var _right_melt_trail: Trail = null

@export_group("Player States")
var _is_water = false
var _is_ice = true
var _is_vapor = false

## Internal state
var _jump_buffer_timer: float = 0.0
var _coyote_timer: float = 0.0
var _was_on_floor: bool = false

var jump_smoke = load("res://Scenes/Player/jumpsmoke.tscn")

var effect = AudioServer.get_bus_effect(AudioServer.get_bus_index("Master"), 0) as AudioEffectLowPassFilter

var inherited_velocity: Vector2 = Vector2.ZERO

var momentum_timer := 0.15

var in_water := false
var in_currentr := false
var in_currentl := false
var in_currentd := false
var in_currentu := false
var in_currentdr := false
var _base_sprite_modulate: Color = Color.WHITE
var _sprite_hit_material: ShaderMaterial = null
var _plant_warning_visual_active := false
var _shatter_warning_shader_active := false
var _base_light_energy := 0.0
var _base_light_color := Color.WHITE

func _ready():
	camera = get_parent().get_node("Camera2D")
	player_states = get_parent().get_node("PlayerState")
	_base_scale = $Sprite2D.scale 

	# Ensure this material is unique per player instance, and idle by default.
	var sprite := $Sprite2D
	_base_sprite_modulate = sprite.modulate
	if sprite.material is ShaderMaterial:
		sprite.material = (sprite.material as ShaderMaterial).duplicate()
		_sprite_hit_material = sprite.material as ShaderMaterial
		_sprite_hit_material.set_shader_parameter("get_hit", false)

	var warning_light := $PointLight2D
	if warning_light:
		_base_light_energy = warning_light.energy
		_base_light_color = warning_light.color
	FeedbackVfx.setup_aura(self, null, FeedbackVfx.FORM_ICE, _feedback_vfx_tuning())


func _exit_tree() -> void:
	_stop_melt_trails()

func check_water():
	in_water = false
	
	var points_to_check = [
		to_global(Vector2(0, 0)),          # center
		to_global(Vector2(24, 0)),         # right
		to_global(Vector2(-24, 0)),        # left
		to_global(Vector2(0, 24)),         # bottom
		to_global(Vector2(0, -24))         # top
	]

	for water in get_tree().get_nodes_in_group("water"):
		for child in water.get_children():
			if child is CollisionPolygon2D:

				var global_poly = []
				for p in child.polygon:
					global_poly.append(child.to_global(p))

				for point in points_to_check:
					if Geometry2D.is_point_in_polygon(point, global_poly):
						in_water = true
						return

func check_currentr():
	in_currentr = false
	
	var points_to_check = [
		to_global(Vector2(0, 0)),          # center
		to_global(Vector2(24, 0)),         # right
		to_global(Vector2(-24, 0)),        # left
		to_global(Vector2(0, 24)),         # bottom
		to_global(Vector2(0, -24))         # top
	]

	for water in get_tree().get_nodes_in_group("currentr"):
		for child in water.get_children():
			if child is CollisionPolygon2D:

				var global_poly = []
				for p in child.polygon:
					global_poly.append(child.to_global(p))

				for point in points_to_check:
					if Geometry2D.is_point_in_polygon(point, global_poly):
						in_currentr = true
						return

func check_currentl():
	in_currentl = false
	
	var points_to_check = [
		to_global(Vector2(0, 0)),          # center
		to_global(Vector2(24, 0)),         # right
		to_global(Vector2(-24, 0)),        # left
		to_global(Vector2(0, 24)),         # bottom
		to_global(Vector2(0, -24))         # top
	]

	for water in get_tree().get_nodes_in_group("currentl"):
		for child in water.get_children():
			if child is CollisionPolygon2D:

				var global_poly = []
				for p in child.polygon:
					global_poly.append(child.to_global(p))

				for point in points_to_check:
					if Geometry2D.is_point_in_polygon(point, global_poly):
						in_currentl = true
						return

func check_currentd():
	in_currentd = false
	
	var points_to_check = [
		to_global(Vector2(0, 0)),          # center
		to_global(Vector2(24, 0)),         # right
		to_global(Vector2(-24, 0)),        # left
		to_global(Vector2(0, 24)),         # bottom
		to_global(Vector2(0, -24))         # top
	]

	for water in get_tree().get_nodes_in_group("currentd"):
		for child in water.get_children():
			if child is CollisionPolygon2D:

				var global_poly = []
				for p in child.polygon:
					global_poly.append(child.to_global(p))

				for point in points_to_check:
					if Geometry2D.is_point_in_polygon(point, global_poly):
						in_currentd = true
						return
					
func check_currentdr():
	in_currentdr = false
	
	var points_to_check = [
		to_global(Vector2(0, 0)),          # center
		to_global(Vector2(24, 0)),         # right
		to_global(Vector2(-24, 0)),        # left
		to_global(Vector2(0, 24)),         # bottom
		to_global(Vector2(0, -24))         # top
	]

	for water in get_tree().get_nodes_in_group("currentdr"):
		for child in water.get_children():
			if child is CollisionPolygon2D:

				var global_poly = []
				for p in child.polygon:
					global_poly.append(child.to_global(p))

				for point in points_to_check:
					if Geometry2D.is_point_in_polygon(point, global_poly):
						in_currentdr = true
						return
						
					
func check_currentu():
	in_currentu = false
	
	var points_to_check = [
		to_global(Vector2(0, 0)),          # center
		to_global(Vector2(24, 0)),         # right
		to_global(Vector2(-24, 0)),        # left
		to_global(Vector2(0, 24)),         # bottom
		to_global(Vector2(0, -24))         # top
	]

	for water in get_tree().get_nodes_in_group("currentu"):
		for child in water.get_children():
			if child is CollisionPolygon2D:

				var global_poly = []
				for p in child.polygon:
					global_poly.append(child.to_global(p))

				for point in points_to_check:
					if Geometry2D.is_point_in_polygon(point, global_poly):
						in_currentu = true
						return

func _physics_process(delta: float) -> void:
	if (_is_water or _is_vapor) and player_states and player_states.has_method("request_form_transition"):
		var target_form := "water" if _is_water else "vapor"
		if player_states.request_form_transition(self, target_form):
			_stop_melt_trails()
			return
	if inherited_velocity != Vector2.ZERO:
		velocity = inherited_velocity
		inherited_velocity = Vector2.ZERO

	var is_dying = player_states != null and "death_transition_in_progress" in player_states and player_states.death_transition_in_progress
	if is_dying:
		_stop_melt_trails()
	_update_face_for_death(is_dying)
	_update_timers(delta)
	_apply_gravity(delta)
	if not is_dying:
		_handle_jump()
		_handle_horizontal(delta)
	check_water()
	check_currentl()
	check_currentr()
	check_currentu()
	check_currentd()
	check_currentdr()
	if in_water:
		var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
		velocity.y -= gravity * delta * 2.0
		velocity.y = max(velocity.y, -4000)  # cap upward speed
	if in_currentu:
		var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
		velocity.y -= gravity * delta * 4.0
	if in_currentd:
		var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
		velocity.y -= gravity * delta * 0.3
	if in_currentr:
		var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
		velocity.y -= gravity * delta * 2.0
		velocity.x += gravity * delta * 0.5
	if in_currentl:
		var gravity = ProjectSettings.get_setting("physics/2d/default_gravity")
		velocity.y -= gravity * delta * 2.0
		velocity.x -= gravity * delta * 0.5
		
	var precollision_velocity = velocity

	if in_water or in_currentd or in_currentr or in_currentl or in_currentu == true:
		AudioServer.set_bus_effect_enabled(
			AudioServer.get_bus_index("Master"), 0, true)
		effect.cutoff_hz = lerp(effect.cutoff_hz, 1000.0, 0.7)
	else:
		effect.cutoff_hz = lerp(effect.cutoff_hz, 20000.0, 0.5)
		if effect.cutoff_hz > 20000.0:
			AudioServer.set_bus_effect_enabled(AudioServer.get_bus_index("Master"), 0, false)

	move_and_slide()
	_update_melt_trails()
	
	_animate_sprite(delta, precollision_velocity)
	
	for i in get_slide_collision_count():
		var collision = get_slide_collision(i)
		var impact_speed = precollision_velocity.dot(-collision.get_normal())
		if not is_dying and player_states and not player_states.is_dead and impact_speed > shatter_threshold:
			# respawn logic (feed collision normal so PlayerState can knock us back cleanly)
			FeedbackVfx.spawn_ice_crash_effect(self, collision.get_position(), precollision_velocity, _feedback_vfx_tuning())
			FeedbackVfx.pulse_aura(self, null, FeedbackVfx.FORM_ICE, 1.5, _feedback_vfx_tuning())
			if player_states.has_method("set_pending_death_knockback"):
				player_states.set_pending_death_knockback(collision.get_normal())
			if player_states.has_method("set_pending_shatter_death_tutorial"):
				player_states.set_pending_shatter_death_tutorial()
			player_states.is_dead = true
			$sounds/ice_shatter.play()
			print("shattered!")
			break
			
	_update_coyote(delta)
	
	# shows the player when they're going to shatter
	var sprite = $Sprite2D 
	var base_tint: Color
	if is_dying:
		base_tint = Color(1, 1, 1, 1)  # keep neutral so death flash reads cleanly
	elif precollision_velocity.length() > shatter_warning:
		if not $sounds/ice_toofastwhoosh.playing:
			$sounds/ice_toofastwhoosh.play()
		base_tint = _base_sprite_modulate
	else:
		base_tint = _base_sprite_modulate
		$sounds/ice_toofastwhoosh.stop()

	sprite.modulate = _get_plant_warning_tint(base_tint, is_dying)
	_update_shatter_warning_visual(precollision_velocity.length(), is_dying)
	var motion_ratio := clampf(
		max(abs(velocity.x) / max(move_speed, 1.0), abs(precollision_velocity.y) / max(max_fall_speed, 1.0)),
		0.0,
		1.0
	)
	FeedbackVfx.update_aura(self, null, FeedbackVfx.FORM_ICE, motion_ratio, delta, _feedback_vfx_tuning())


func _update_face_for_death(is_dying: bool) -> void:
	var face_node = $Sprite2D.get_node_or_null("Face")
	if not (face_node is AnimatedSprite2D):
		return
	var face := face_node as AnimatedSprite2D
	if not is_dying:
		return
	if face.sprite_frames != null and face.sprite_frames.has_animation("sad"):
		face.play("sad")
	elif face.sprite_frames != null and face.sprite_frames.has_animation("default"):
		face.play("default")


func _update_face_for_shatter_warning(can_shatter: bool) -> void:
	if player_states != null and "death_transition_in_progress" in player_states and player_states.death_transition_in_progress:
		return
	var face_node = $Sprite2D.get_node_or_null("Face")
	if not (face_node is AnimatedSprite2D):
		return
	var face := face_node as AnimatedSprite2D
	if face.sprite_frames == null:
		return
	if can_shatter and face.sprite_frames.has_animation("angry"):
		if face.animation != "angry":
			face.play("angry")
	elif face.sprite_frames.has_animation("default"):
		if face.animation != "default":
			face.play("default")


func _update_melt_trails() -> void:
	if not melt_trail_enabled:
		_stop_melt_trails()
		return

	var is_sliding = is_on_floor() and not in_water and abs(velocity.x) >= melt_trail_min_slide_speed
	if not is_sliding:
		_stop_melt_trails()
		$sounds/ice_running.stop()
		return

	if not $sounds/ice_running.playing:
		$sounds/ice_running.play()
	
	_ensure_melt_trails()
	var points := _get_melt_contact_points()
	_left_melt_trail.add_point_world(points[0])
	_right_melt_trail.add_point_world(points[1])


func _ensure_melt_trails() -> void:
	if _left_melt_trail == null:
		_left_melt_trail = _create_melt_trail(0.95)
	if _right_melt_trail == null:
		_right_melt_trail = _create_melt_trail(0.75)


func _create_melt_trail(alpha_scale: float) -> Trail:
	var trail := Trail.create()
	trail.width = melt_trail_width
	trail.max_points = max(2, melt_trail_point_count)
	trail.fade_duration = max(0.01, melt_trail_fade_duration)
	trail.default_color = melt_trail_color
	trail.modulate = Color(1.0, 1.0, 1.0, alpha_scale)
	trail.z_index = z_index - 1
	get_tree().current_scene.add_child(trail)
	return trail


func _get_melt_contact_points() -> Array[Vector2]:
	var collision_shape := $CollisionShape2D
	var center = collision_shape.global_position
	var half_width := 16.0
	var foot_y = center.y + 30.0 + melt_trail_offset_y

	if collision_shape.shape is RectangleShape2D:
		var rect := collision_shape.shape as RectangleShape2D
		var scale_vec := get_global_transform().get_scale()
		var scale_x = abs(scale_vec.x)
		var scale_y = abs(scale_vec.y)
		half_width = rect.size.x * 0.34 * scale_x
		foot_y = center.y + rect.size.y * 0.5 * scale_y + melt_trail_offset_y

	return [
		Vector2(center.x - half_width, foot_y),
		Vector2(center.x + half_width, foot_y),
	]


func _stop_melt_trails() -> void:
	if _left_melt_trail != null:
		_left_melt_trail.stop()
		_left_melt_trail = null
	if _right_melt_trail != null:
		_right_melt_trail.stop()
		_right_melt_trail = null


func _update_timers(delta: float) -> void:
	# Count down buffer and coyote timers
	if _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta
	if _coyote_timer > 0.0:
		_coyote_timer -= delta

	# Buffer jump input slightly before landing
	if Input.is_action_just_pressed("ui_accept"):
		_jump_buffer_timer = jump_buffer_time


func _apply_gravity(delta: float) -> void:
	if in_water or in_currentd or in_currentl or in_currentr or in_currentu:
		velocity.y = velocity.y/1.028
		return
		
	if is_on_floor() and abs(velocity.y) < 50:
		velocity.y = 0.0
		return

	# Fall faster than rising for better game feel
	var current_gravity := gravity
	if velocity.y > 0.0:
		current_gravity *= fall_gravity_multiplier

	velocity.y += current_gravity * delta
	velocity.y = min(velocity.y, max_fall_speed)


func _handle_jump() -> void:
	var can_jump := is_on_floor() or _coyote_timer > 0.0
	var wants_jump := _jump_buffer_timer > 0.0

	if can_jump and wants_jump:
		velocity.y = -jump_force
		FeedbackVfx.spawn_jump_effect(self, FeedbackVfx.FORM_ICE, global_position + Vector2(0, 35), velocity, _feedback_vfx_tuning())
		FeedbackVfx.pulse_aura(self, null, FeedbackVfx.FORM_ICE, 0.95, _feedback_vfx_tuning())
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		$sounds/ice_jump.pitch_scale = randf_range(0.95, 1.05)
		$sounds/ice_jump.play()

	# Variable jump height — release early to jump lower -- NIXED FOR TESTING, PERHAPS KEEP
#	if Input.is_action_just_released("ui_accept") and velocity.y < -jump_force * 0.4:
#		velocity.y = -jump_force * 0.4


func _handle_horizontal(delta):
	var dir = Input.get_axis("ui_left", "ui_right")
	
	if not is_on_floor():
		# In air: only very slight influence, don't fight momentum
		velocity.x += dir * air_acceleration * 0.5 * delta
	elif momentum_timer > 0:
		# Slight influence without killing momentum
		velocity.x += dir * acceleration * 0.5 * delta
	else:
		# Normal movement
		if dir != 0:
			velocity.x += dir * acceleration * delta
		else:
			velocity.x = move_toward(velocity.x, 0, deceleration * delta)
	
	velocity.x = clamp(velocity.x, -move_speed, move_speed)
	
	momentum_timer -= delta
	
func _update_coyote(delta: float) -> void:
	# Start coyote timer the moment the player walks off an edge
	if _was_on_floor and not is_on_floor() and velocity.y >= 0.0:
		_coyote_timer = coyote_time
	_was_on_floor = is_on_floor()
	
func _animate_sprite(delta: float, pre_vel: Vector2) -> void:
	var sprite = $Sprite2D

	# --- Squash & Stretch ---
	var target_scale_y = 1.0
	var target_scale_x = 1.0

	if not is_on_floor():
		var stretch = clamp(abs(velocity.y) / jump_force, 0.0, 1.0)
		if velocity.y < 0:
			target_scale_y = lerp(_base_scale.y, _base_scale.y * 1.25, stretch)
			target_scale_x = lerp(_base_scale.x, _base_scale.x * 0.82, stretch)
		else:
			target_scale_y = lerp(_base_scale.y, _base_scale.y * 1.15, stretch)
			target_scale_x = lerp(_base_scale.x, _base_scale.x * 0.88, stretch)
	else:
		if not _was_on_floor_anim:
			var impact = clamp(abs(pre_vel.y) / 800.0, 0.0, 1.0)
			_anim_squash = lerp(0.62, 0.80, 1.0 - impact)
			$sounds/ice_land.pitch_scale = randf_range(0.95, 1.05)
			$sounds/ice_land.volume_db = lerpf(-10.0, 0.0, impact)
			$sounds/ice_land.play()
			if abs(pre_vel.y) > 110.0:
				var landing_points := _get_melt_contact_points()
				var landing_position := (landing_points[0] + landing_points[1]) * 0.5
				FeedbackVfx.spawn_landing_effect(self, FeedbackVfx.FORM_ICE, landing_position, abs(pre_vel.y), _feedback_vfx_tuning())
				FeedbackVfx.pulse_aura(self, null, FeedbackVfx.FORM_ICE, 0.72 + impact * 0.8, _feedback_vfx_tuning())
		target_scale_y = _base_scale.y * _anim_squash
		target_scale_x = _base_scale.x * (2.0 - _anim_squash)
		
	# Recover squash back to 1.0
	_anim_squash = move_toward(_anim_squash, 1.0, delta * 8.0)

	# Smooth toward target scale
	sprite.scale.y = lerp(sprite.scale.y, target_scale_y, delta * 18.0)
	sprite.scale.x = lerp(sprite.scale.x, target_scale_x, delta * 18.0)

	# --- Lean based on acceleration/velocity ---
	var lean_target = clamp(velocity.x / move_speed, -1.0, 1.0) * 10.0  # max 10 degrees
	# Extra lean snap when changing direction
	if sign(velocity.x) != sign(pre_vel.x) and abs(velocity.x) > 100:
		lean_target *= 1.5
	_anim_lean = lerp(_anim_lean, lean_target, delta * 12.0)
	sprite.rotation_degrees = _anim_lean

	# --- Idle bob (only on floor, only when still) ---
	_bob_timer += delta
	var bob_amount = 0.0
	if is_on_floor():
		var speed_factor = 1.0 - clamp(abs(velocity.x) / move_speed, 0.0, 1.0)
		bob_amount = sin(_bob_timer * 4.5) * 1.8 * speed_factor  # gentle 1.8px bob
	sprite.position.y = lerp(sprite.position.y, bob_amount, delta * 20.0)

	# --- Near-shatter warning shake ---
	if pre_vel.length() > shatter_threshold * 0.75:
		var shake_strength = clamp((pre_vel.length() - shatter_threshold * 0.75) / (shatter_threshold * 0.25), 0.0, 1.0)
		_shake_offset = Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)) * shake_strength * 3.0
	else:
		_shake_offset = _shake_offset.lerp(Vector2.ZERO, delta * 20.0)
	sprite.position.x = _shake_offset.x

	# --- Red tint warning (your existing logic, kept here) ---
	if pre_vel.length() > shatter_threshold:
		sprite.modulate = sprite.modulate.lerp(Color(0.7, 0.0, 0.0, sprite.modulate.a), 0.35)

	_was_on_floor_anim = is_on_floor()


func _get_plant_warning_tint(base_tint: Color, is_dying: bool) -> Color:
	if is_dying or player_states == null or not player_states.has_method("get_plant_danger_progress"):
		_reset_plant_warning_visual()
		return base_tint

	var progress = clamp(float(player_states.get_plant_danger_progress()), 0.0, 1.0)
	if progress <= 0.0:
		_reset_plant_warning_visual()
		return base_tint

	var warning_ratio = clamp(plant_warning_start_ratio, 0.05, 0.98)
	var danger_tint: Color
	var flash_blend := 0.0
	if progress < warning_ratio:
		var warm_blend = progress / warning_ratio
		danger_tint = _base_sprite_modulate.lerp(plant_warning_mid_tint, warm_blend)
	else:
		var critical_blend = (progress - warning_ratio) / max(0.001, 1.0 - warning_ratio)
		danger_tint = plant_warning_mid_tint.lerp(plant_warning_critical_tint, critical_blend)
		var flash_speed = lerp(plant_warning_min_flash_speed, plant_warning_max_flash_speed, critical_blend)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * flash_speed)
		flash_blend = 0.22 * pulse

	var result := base_tint.lerp(danger_tint, 0.78)
	if flash_blend > 0.0:
		result = result.lerp(Color.WHITE, flash_blend)

	_apply_plant_warning_shader(progress, danger_tint)
	_plant_warning_visual_active = true
	return result


func _update_shatter_warning_visual(speed: float, is_dying: bool) -> void:
	if is_dying:
		_reset_shatter_warning_visual()
		_update_face_for_shatter_warning(false)
		return

	var warning_start = max(1.0, shatter_warning)
	if speed <= warning_start:
		_reset_shatter_warning_visual()
		_update_face_for_shatter_warning(false)
		return

	var warning_range = max(1.0, shatter_threshold - warning_start)
	var warning_ratio = clamp((speed - warning_start) / warning_range, 0.0, 1.0)
	var lethal_ratio = clamp((speed - shatter_threshold) / max(1.0, shatter_threshold * 0.55), 0.0, 1.0)
	var combined_ratio = clamp(max(warning_ratio, lethal_ratio), 0.0, 1.0)
	var can_shatter = speed >= shatter_threshold
	var flash_speed = lerp(shatter_warning_min_flash_speed, shatter_warning_max_flash_speed, combined_ratio)
	var pulse = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.001 * TAU * flash_speed)

	var sprite := $Sprite2D
	var danger_color = shatter_warning_flash_color.lerp(shatter_lethal_flash_color, clamp(warning_ratio + lethal_ratio * 0.8, 0.0, 1.0))
	var lethal_flash = 0.0
	if can_shatter:
		lethal_flash = 0.35 + 0.65 * pulse
	var overlay_strength = 0.24 + 0.24 * combined_ratio + 0.2 * pulse * combined_ratio
	if can_shatter:
		overlay_strength += 0.2 * lethal_flash
	var modulate_target = danger_color
	if can_shatter:
		modulate_target = danger_color.lerp(Color.WHITE, 0.55 * lethal_flash)
	sprite.modulate = sprite.modulate.lerp(modulate_target, clamp(overlay_strength, 0.0, 0.95))

	var pulse_scale = lerp(shatter_warning_scale_pulse, shatter_lethal_scale_pulse, clamp(warning_ratio + lethal_ratio, 0.0, 1.0))
	sprite.scale *= 1.0 + pulse_scale * pulse

	var warning_light := $PointLight2D
	if warning_light:
		var energy_boost = shatter_warning_light_boost * (0.35 + 0.45 * pulse) * combined_ratio
		if can_shatter:
			energy_boost += shatter_warning_light_boost * 0.35 * lethal_flash
		warning_light.energy = _base_light_energy + energy_boost
		warning_light.color = _base_light_color.lerp(modulate_target, 0.55 * combined_ratio + 0.12 * lethal_flash)

	if _sprite_hit_material != null:
		_sprite_hit_material.set_shader_parameter("flash_color", modulate_target)
		_sprite_hit_material.set_shader_parameter("shake_intensity", lerp(shatter_warning_min_shake, shatter_warning_max_shake, combined_ratio))
		_sprite_hit_material.set_shader_parameter("flash_speed", flash_speed * (1.0 if not can_shatter else 1.35))
		_sprite_hit_material.set_shader_parameter("hit_effect", lerp(shatter_warning_min_hit_effect, shatter_warning_max_hit_effect, combined_ratio) + 0.08 * lethal_flash)
		_sprite_hit_material.set_shader_parameter("get_hit", true)
		_shatter_warning_shader_active = true

	_update_face_for_shatter_warning(can_shatter)


func _reset_shatter_warning_visual() -> void:
	var warning_light := $PointLight2D
	if warning_light:
		warning_light.energy = _base_light_energy
		warning_light.color = _base_light_color

	if not _shatter_warning_shader_active:
		return

	# Keep plant warning shader active if it is currently driving visuals.
	if _plant_warning_visual_active:
		_shatter_warning_shader_active = false
		return

	if _sprite_hit_material != null:
		_sprite_hit_material.set_shader_parameter("hit_effect", 0.0)
		_sprite_hit_material.set_shader_parameter("shake_intensity", 0.0)
		_sprite_hit_material.set_shader_parameter("get_hit", false)
	_shatter_warning_shader_active = false


func _apply_plant_warning_shader(progress: float, danger_color: Color) -> void:
	if _sprite_hit_material == null:
		var sprite := $Sprite2D
		if sprite.material is ShaderMaterial:
			_sprite_hit_material = sprite.material as ShaderMaterial
	if _sprite_hit_material == null:
		return

	var warning_ratio = clamp(plant_warning_start_ratio, 0.05, 0.98)
	var critical_blend := 0.0
	if progress >= warning_ratio:
		critical_blend = (progress - warning_ratio) / max(0.001, 1.0 - warning_ratio)

	_sprite_hit_material.set_shader_parameter("flash_color", danger_color)
	_sprite_hit_material.set_shader_parameter("shake_intensity", 0.0)
	_sprite_hit_material.set_shader_parameter("flash_speed", lerp(plant_warning_min_flash_speed, plant_warning_max_flash_speed, critical_blend))
	_sprite_hit_material.set_shader_parameter("hit_effect", plant_warning_hit_effect)
	_sprite_hit_material.set_shader_parameter("get_hit", true)


func _reset_plant_warning_visual() -> void:
	if not _plant_warning_visual_active:
		return
	if _sprite_hit_material != null:
		_sprite_hit_material.set_shader_parameter("hit_effect", 0.0)
		_sprite_hit_material.set_shader_parameter("get_hit", false)
	_plant_warning_visual_active = false


func _feedback_vfx_tuning() -> Dictionary:
	return {
		"particle_amount_scale": feedback_particle_amount_scale,
		"particle_speed_scale": feedback_particle_speed_scale,
		"particle_size_scale": feedback_particle_size_scale,
		"particle_spread_scale": feedback_particle_spread_scale,
		"particle_gravity_scale": feedback_particle_gravity_scale,
		"glow_energy_scale": feedback_glow_energy_scale,
		"glow_scale_scale": feedback_glow_scale_scale,
	}
