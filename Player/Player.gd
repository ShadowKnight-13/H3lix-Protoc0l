extends CharacterBody2D
class_name Player

const SPEED = 300.01
const JUMP_HEIGHT: float = -500.0
const JUMP_CUT_MULTIPLIER: float = 0.2
const FRICTION: float = 22.5

const GRAVITY_NORMAL: float = 19
const GRAVITY_WALL_SLIDE: float = 100.5
const WALL_JUMP_PUSH_FORCE: float = 600.0

# === COYOTE TIME ===
const COYOTE_TIME: float = 0.2  # seconds after leaving a platform where jump is still allowed 

# === DASH / CROUCH CONSTANTS ===
const DASH_SPEED: float = 700.0
const CROUCH_SPEED: float = 150.0
const DASH_DURATION: float = 0.3
const DASH_COOLDOWN: float = 0.4
const DIVE_VERTICAL_BOOST: float = 200.0
const AIR_DASH_HORIZONTAL_TIME: float = 0.15
const DASH_JUMP_SPEED_MULTIPLIER: float = 1.2
const DASH_JUMP_HEIGHT_MULTIPLIER: float = 1.3
const DASH_JUMP_AIR_CONTROL: float = 0.3
const MAX_HEALTH: int = 3

# === AIR-DASH GAP DETECTION ===
const GAP_PROBE_REACH: float = 90.0        # Horizontal px probed ahead of the leading edge for a gap
const GAP_PROBE_HEIGHT_BONUS: float = 20.0 # Extra probe height added above+below the dash collision half-height
const GAP_PROBE_RAY_COUNT: int = 14        # Vertical rays in the forward probe column
const GAP_PROBE_COLLISION_MASK: int = 2    # World-geometry collision layer (matches tiles/walls)
const GAP_SNAP_TWEEN_TIME: float = 0.10    # Duration (s) of the vertical snap interpolation
const GAP_SNAP_COOLDOWN: float = 0.30      # Cooldown after a snap fires to prevent per-frame retriggering
const GAP_SNAP_MIN_DELTA_Y: float = 2.0    # Minimum Y offset required to bother snapping
const RESPAWN_DAMAGE_GUARD_FRAMES: int = 2

# === STEP-UP / LEDGE CONSTANTS ===
const STEP_UP_MAX_HEIGHT: float = 30.0
const STEP_UP_CHECK_DISTANCE: float = 10.0

# === LEDGE HANG CONSTANTS ===
const LEDGE_HANG_OFFSET_Y: float = 2.0    # Vertical offset between hang and stand position
const LEDGE_CLIMB_TWEEN_TIME: float = 0.18  # Seconds to tween onto ledge top
const LEDGE_HANG_HORIZONTAL_NUDGE: float = 4.0   # Pixels to move onto ledge when standing
const LEDGE_FLOOR_PROBE_ITERATIONS: int = 8      # How many vertical steps to scan for ledge top
const LEDGE_FLOOR_PROBE_STEP: float = 4.0        # Y spacing between probe steps
const LEDGE_FLOOR_PROBE_UP: float = 16.0         # Ray start offset above each probe step
const LEDGE_FLOOR_PROBE_DOWN: float = 32.0       # Ray reach below each probe step

# === WALL PROBE CONSTANTS ===
const WALL_PROBE_COLLISION_MASK: int = 2
const WALL_PROBE_MAX_RESULTS: int = 8
const WALL_PROBE_LATERAL_REACH: float = 8.0
const WALL_PROBE_SIDE_INSET: float = 1.0
const WALL_PROBE_HALF_WIDTH: float = 3.5
const WALL_PROBE_TOP_HEIGHT: float = 8.0
const WALL_PROBE_BOTTOM_HEIGHT: float = 8.0
const WALL_PROBE_MIN_MIDDLE_HEIGHT: float = 2.0
const WALL_PROBE_MIDDLE_SEGMENTS: int = 3

# === CRUSH DETECTION CONSTANTS ===
const MIN_CRUSHING_VELOCITY: float = 1.0       # Minimum platform speed to be considered moving
const MIN_UPWARD_CRUSH_VELOCITY: float = -1.0  # Platform y-velocity must be below this to crush upward
const CRUSH_PUSH_THRESHOLD: float = 10.0       # Minimum pushing force (platform velocity dot into player) to trigger velocity-based crush
const CRUSH_VELOCITY_RATIO_THRESHOLD: float = 0.3  # Player's real velocity must be below 30% of platform's to be considered stuck

var wall_stick_time := 0.0
const WALL_STICK_DURATION := 0.5

var wall_jump_lock: float = 0.0
const WALL_JUMP_LOCK_TIME: float = 0.15
var is_stuck_to_wall := false

## === HEALTH & STATE FLAGS ===
var health = MAX_HEALTH
var is_dead := false
var _ignore_damage_until_frame: int = -1
var is_wall_jumping := false
var is_jumping := false
var is_dash_jumping := false
var was_on_floor_last_frame := false
var skip_gravity_this_frame := false
var needs_collision_restore := false
var facing_direction := 1.0  # Track which way player is facing (1 = right, -1 = left)
var stepped_up := false

## === COYOTE TIME STATE ===
var coyote_timer: float = 0.0

## === DASH / CROUCH STATE ===
var is_dashing := false
var dash_time_remaining := 0.0
var dash_cooldown_remaining := 0.0
var dash_direction := 1.0
var is_air_dive := false
var air_dash_used := false
var air_dash_horizontal_timer := 0.0
var is_crouching := false

## === AIR-DASH GAP SNAP STATE ===
var _gap_snapping: bool = false       # true while vertical snap tween is active
var _gap_snap_cooldown: float = 0.0   # prevents retriggering on the same obstruction
var _gap_snap_target_y: float = 0.0   # target global_position.y for the snap
var _gap_snap_start_y: float = 0.0    # global_position.y when snap was triggered
var _gap_snap_timer: float = 0.0      # elapsed time within the snap tween

## === NODES / CHILDREN ===
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var interaction_area = $InteractionArea

var debug_rays = []
var debug_rays_visible := false
var wall_probe_cache: Dictionary = {}
var wall_probe_cache_frame: int = -1

## === LEDGE HANG STATE ===
var is_ledge_hanging := false
var is_ledge_climbing := false
var is_ledge_hang_transitioning := false
var ledge_hang_point: Vector2 = Vector2.ZERO
var ledge_stand_point: Vector2 = Vector2.ZERO
var ledge_hang_wall_normal: Vector2 = Vector2.ZERO

signal health_changed

func player_death():
	# When health reaches 0, ask Main to respawn instead of reloading the scene.
	if health > 0:
		return
	is_dead = true
	_reset_attack_state(true)

	var main := get_tree().get_first_node_in_group("GameMain")
	if main and main.has_method("reset_current_level_on_death"):
		main.call("reset_current_level_on_death")
		return

	# Fallback: if Main can't be found for some reason, keep old behavior.
	queue_free()
	get_tree().reload_current_scene()

func kill_player():
	if health <= 0 or is_dead:
		return  # Already dead
	is_dead = true
	health = 0
	velocity = Vector2.ZERO
	set_physics_process(false)
	player_death()
	coyote_timer = 0.0

func damage_player():
	if is_dead or (_ignore_damage_until_frame >= 0 and Engine.get_physics_frames() < _ignore_damage_until_frame):
		return
	health = max(health - 1, 0)
	if health <= 0:
		is_dead = true
	$SFX/hurt.play()
	emit_signal("health_changed", health)

func reset_for_respawn(spawn_health: int = MAX_HEALTH) -> void:
	health = clampi(spawn_health, 1, MAX_HEALTH)
	is_dead = false
	_ignore_damage_until_frame = Engine.get_physics_frames() + RESPAWN_DAMAGE_GUARD_FRAMES
	emit_signal("health_changed", health)

	# Reset movement/combat state so respawns don't inherit dash/crouch collisions.
	velocity = Vector2.ZERO
	set_physics_process(true)

	# Wall/ledge related state.
	wall_stick_time = 0.0
	wall_jump_lock = 0.0
	is_stuck_to_wall = false
	is_wall_jumping = false
	is_ledge_hanging = false
	is_ledge_climbing = false
	is_ledge_hang_transitioning = false
	ledge_hang_point = Vector2.ZERO
	ledge_stand_point = Vector2.ZERO
	ledge_hang_wall_normal = Vector2.ZERO

	# Jump/dash state.
	is_jumping = false
	is_dash_jumping = false
	skip_gravity_this_frame = false
	is_dashing = false
	dash_time_remaining = 0.0
	dash_cooldown_remaining = 0.0
	dash_direction = 1.0
	is_air_dive = false
	air_dash_used = false
	air_dash_horizontal_timer = 0.0
	is_crouching = false

	# Gap-snap state.
	_gap_snapping = false
	_gap_snap_cooldown = 0.0

	# Collision shape back to full height.
	$CollisionShape2D.scale.y = 1.0
	$CollisionShape2D.position.y = 0

	# Combat state.
	_reset_attack_state(true)

func heal(amount: int = 1) -> void:
	health = min(health + amount, MAX_HEALTH)
	emit_signal("health_changed", health)

func update_animations(x_input: float) -> void:
	if is_dead:
		if $AnimationPlayer.current_animation == "Attack":
			$AnimationPlayer.stop()
		$AnimationPlayer.play("Idle")
		return

	# 1. ACTION PRIORITY (Non-interruptible states)
	# These return early so movement logic doesn't overwrite them.
	if is_attacking:
		$AnimationPlayer.play("Attack") 
		return
		
	if is_dashing:
		$AnimationPlayer.play("Dash")
		# Maintain sprite direction during dash
		$Sprite2D.flip_h = dash_direction < 0
		return

	# Ledge climb (tween in progress)
	if is_ledge_climbing:
		$AnimationPlayer.play("Getup")
		return

	# Ledge hang (waiting for jump input)
	if is_ledge_hanging:
		$AnimationPlayer.play("Wall_slide")
		$Sprite2D.flip_h = (ledge_hang_wall_normal.x > 0)
		return

	# 2. AIRBORNE STATES
	if not is_on_floor():
		if is_stuck_to_wall:
			$AnimationPlayer.play("Wall_slide")
			# Flip based on which wall we are sticking to
			var wall_normal = get_wall_normal()
			$Sprite2D.flip_h = (wall_normal.x > 0) 
		elif velocity.y < 0:
			$AnimationPlayer.play("Jump")
			_handle_horizontal_flip(x_input)
		else:
			$AnimationPlayer.play("Fall")
			_handle_horizontal_flip(x_input)
			
	# 3. GROUND STATES
	else:
		if is_crouching:
			# Using "Dash" as a placeholder for crouch as seen in your source
			$AnimationPlayer.play("Dash") 
		elif stepped_up:
			$AnimationPlayer.play("Getup")
		elif x_input != 0:
			$AnimationPlayer.play("Run")
		else:
			$AnimationPlayer.play("Idle")
		
		_handle_horizontal_flip(x_input)

# Helper to keep the code clean
func _handle_horizontal_flip(x_input: float) -> void:
	if x_input < 0:
		$Sprite2D.flip_h = true
		$Hit.position.x = -30
		$Hit.flip_h = true
	elif x_input > 0:
		$Sprite2D.flip_h = false
		$Hit.position.x = 30
		$Hit.flip_h = false

func _middle_probe_segment_count() -> int:
	return max(1, WALL_PROBE_MIDDLE_SEGMENTS)

func _middle_probe_name(index: int) -> String:
	return "middle_%d" % index

func _empty_wall_probe_data() -> Dictionary:
	var middle_segment_count: int = _middle_probe_segment_count()
	var probes := {
		"top": {"hit": false, "hit_grippable": false, "hit_slippery": false},
		"middle": {"hit": false, "hit_grippable": false, "hit_slippery": false},
		"bottom": {"hit": false, "hit_grippable": false, "hit_slippery": false}
	}
	for i in range(middle_segment_count):
		probes[_middle_probe_name(i + 1)] = {"hit": false, "hit_grippable": false, "hit_slippery": false}

	return {
		"has_contact": false,
		"has_grippable_contact": false,
		"has_slippery_contact": false,
		"can_wall_slide_jump": false,
		"probes": probes
	}

func _is_collider_grippable_wall(collider: Object) -> bool:
	if collider == null:
		return false
	
	if collider is Node:
		# If both groups are present, slippery wins to avoid accidental stick on mixed-tag walls.
		if collider.is_in_group("slippery_wall"):
			return false
		
		if collider.is_in_group("grippable_wall"):
			return true
	
	# TileMapLayer walls remain non-grippable unless explicitly tagged above.
	if collider is TileMapLayer:
		return false
	
	if "collision_layer" in collider:
		return (collider.collision_layer & (1 << 1)) != 0
	
	return false

func _run_wall_probe(space_state: PhysicsDirectSpaceState2D, origin: Vector2, direction: float, probe_half_size: Vector2) -> Dictionary:
	var probe_shape := RectangleShape2D.new()
	probe_shape.size = probe_half_size * 2.0
	
	var query := PhysicsShapeQueryParameters2D.new()
	query.shape = probe_shape
	query.transform = Transform2D(0.0, origin)
	query.motion = Vector2(direction * WALL_PROBE_LATERAL_REACH, 0.0)
	query.exclude = [self]
	query.collision_mask = WALL_PROBE_COLLISION_MASK
	
	var hits := space_state.intersect_shape(query, WALL_PROBE_MAX_RESULTS)
	var hit_grippable := false
	var hit_slippery := false
	
	for hit in hits:
		var collider: Object = hit.get("collider", null)
		if _is_collider_grippable_wall(collider):
			hit_grippable = true
		else:
			hit_slippery = true
	
	var hit_any := not hits.is_empty()
	var cast_end := origin + Vector2(direction * WALL_PROBE_LATERAL_REACH, 0.0)
	var debug_color := Color.CYAN
	
	if hit_grippable:
		debug_color = Color(0.1, 0.95, 0.1, 0.95)
	elif hit_slippery:
		debug_color = Color(1.0, 0.45, 0.15, 0.95)
	
	if debug_rays_visible:
		debug_rays.append({"type": "line", "start": origin, "end": cast_end, "color": debug_color})
		debug_rays.append({"type": "rect", "center": origin, "size": probe_shape.size, "color": Color(debug_color.r, debug_color.g, debug_color.b, 0.6)})
		debug_rays.append({"type": "rect", "center": cast_end, "size": probe_shape.size, "color": Color(debug_color.r, debug_color.g, debug_color.b, 0.35)})
	
	return {
		"hit": hit_any,
		"hit_grippable": hit_grippable,
		"hit_slippery": hit_slippery
	}

func _build_wall_probe_rects(half_body_size: Vector2) -> Dictionary:
	var full_height := half_body_size.y * 2.0
	if full_height <= 0.0 or half_body_size.x <= 0.0:
		return {}
	
	var clamped_min_middle_height = min(WALL_PROBE_MIN_MIDDLE_HEIGHT, full_height)
	var available_top_and_bottom_height = max(0.0, full_height - clamped_min_middle_height)
	var desired_top_height = max(0.0, WALL_PROBE_TOP_HEIGHT)
	var desired_bottom_height = max(0.0, WALL_PROBE_BOTTOM_HEIGHT)
	var desired_top_bottom_height = desired_top_height + desired_bottom_height
	var top_height := 0.0
	var bottom_height := 0.0
	
	if desired_top_bottom_height > 0.0:
		var scale = min(1.0, available_top_and_bottom_height / desired_top_bottom_height)
		top_height = desired_top_height * scale
		bottom_height = desired_bottom_height * scale
	
	var middle_height = max(0.0, full_height - top_height - bottom_height)
	var probe_half_w = min(WALL_PROBE_HALF_WIDTH, half_body_size.x)
	
	return {
		"half_w": probe_half_w,
		"top_half_size": Vector2(probe_half_w, top_height * 0.5),
		"middle_half_size": Vector2(probe_half_w, middle_height * 0.5),
		"bottom_half_size": Vector2(probe_half_w, bottom_height * 0.5),
		"top_center_y": -half_body_size.y + (top_height * 0.5),
		"middle_center_y": -half_body_size.y + top_height + (middle_height * 0.5),
		"bottom_center_y": half_body_size.y - (bottom_height * 0.5)
	}

func _get_wall_probe_data() -> Dictionary:
	var frame := Engine.get_physics_frames()
	if wall_probe_cache_frame == frame:
		return wall_probe_cache
	
	var data := _empty_wall_probe_data()
	var world_2d := get_world_2d()
	if world_2d == null:
		wall_probe_cache = data
		wall_probe_cache_frame = frame
		return data
	
	var collision_node := $CollisionShape2D
	var collision_shape := collision_node.shape as RectangleShape2D
	if collision_shape == null:
		wall_probe_cache = data
		wall_probe_cache_frame = frame
		return data
	
	var facing = sign(facing_direction)
	if facing == 0:
		# Fallback keeps probes aligned with the rendered facing if direction was never initialized.
		facing = -1.0 if $Sprite2D.flip_h else 1.0
	
	var half_body_size := Vector2(
		collision_shape.size.x * abs(collision_node.scale.x) * 0.5,
		collision_shape.size.y * abs(collision_node.scale.y) * 0.5
	)
	var probe_rects := _build_wall_probe_rects(half_body_size)
	if probe_rects.is_empty():
		wall_probe_cache = data
		wall_probe_cache_frame = frame
		return data
	
	var side_offset_x = facing * max(0.0, half_body_size.x - probe_rects.half_w - WALL_PROBE_SIDE_INSET)
	var shape_center = global_position + collision_node.position
	var probe_specs := {
		"top": {"center_y": probe_rects.top_center_y, "half_size": probe_rects.top_half_size},
		"bottom": {"center_y": probe_rects.bottom_center_y, "half_size": probe_rects.bottom_half_size}
	}
	var probe_order: Array[String] = ["top"]
	var middle_probe_names: Array[String] = []
	var middle_segment_count: int = _middle_probe_segment_count()
	var middle_height = probe_rects.middle_half_size.y * 2.0
	var middle_segment_height = middle_height / float(middle_segment_count)
	var middle_segment_half_h = middle_segment_height * 0.5
	var middle_start_y = probe_rects.middle_center_y - (middle_height * 0.5) + middle_segment_half_h

	for i in range(middle_segment_count):
		var probe_name := _middle_probe_name(i + 1)
		middle_probe_names.append(probe_name)
		probe_order.append(probe_name)
		probe_specs[probe_name] = {
			"center_y": middle_start_y + middle_segment_height * float(i),
			"half_size": Vector2(probe_rects.half_w, middle_segment_half_h)
		}
	probe_order.append("bottom")
	var space_state := world_2d.direct_space_state
	
	for probe_name in probe_order:
		var probe_origin = shape_center + Vector2(side_offset_x, probe_specs[probe_name].center_y)
		var probe_result := _run_wall_probe(space_state, probe_origin, facing, probe_specs[probe_name].half_size)
		data.probes[probe_name] = probe_result
		data.has_contact = data.has_contact or probe_result.hit
		data.has_grippable_contact = data.has_grippable_contact or probe_result.hit_grippable
		data.has_slippery_contact = data.has_slippery_contact or probe_result.hit_slippery

	var middle_combined := {"hit": false, "hit_grippable": false, "hit_slippery": false}
	for probe_name in middle_probe_names:
		var probe_result: Dictionary = data.probes[probe_name]
		middle_combined.hit = middle_combined.hit or probe_result.hit
		middle_combined.hit_grippable = middle_combined.hit_grippable or probe_result.hit_grippable
		middle_combined.hit_slippery = middle_combined.hit_slippery or probe_result.hit_slippery
	data.probes.middle = middle_combined
	
	data.can_wall_slide_jump = data.probes.top.hit_grippable and data.probes.middle.hit_grippable
	wall_probe_cache = data
	wall_probe_cache_frame = frame
	return data

func is_on_grippable_wall() -> bool:
	return _get_wall_probe_data().has_grippable_contact

func is_on_slippery_wall() -> bool:
	var probe_data := _get_wall_probe_data()
	return probe_data.has_slippery_contact and not probe_data.has_grippable_contact

func can_wall_slide_jump() -> bool:
	return _get_wall_probe_data().can_wall_slide_jump

func _ready() -> void:
	$Hit.visible = false
	# Support enemies that use Area2D hurtboxes (e.g. DogEnemy Hurtbox).
	if melee_hitbox and not melee_hitbox.area_entered.is_connected(_on_melee_hitbox_area_entered):
		melee_hitbox.area_entered.connect(_on_melee_hitbox_area_entered)

## === MAIN PHYSICS LOOP ===
func _physics_process(delta):
	if health <= 0:
		player_death()
		return

	var x_input = Input.get_axis("move_left", "move_right")
	var jump_pressed := Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("jump_controller")
	var jump_released := Input.is_action_just_released("jump") or Input.is_action_just_released("jump_controller")
	var dash_pressed := Input.is_action_just_pressed("dash") or Input.is_action_just_pressed("dash_controller")
	var wall_probe_data := _get_wall_probe_data()
	
	# === LEDGE CLIMBING: tween owns position, freeze all input/physics ===
	if is_ledge_climbing:
		velocity = Vector2.ZERO
		_update_attack_timers(delta)
		_update_melee_hitbox_position()
		if not is_ledge_hang_transitioning:
			move_and_slide()
		was_on_floor_last_frame = is_on_floor()
		player_death()
		return

	# === LEDGE HANGING: freeze in place, await jump input ===
	if is_ledge_hanging:
		_handle_ledge_hang_input(jump_pressed)
		update_animations(x_input)
		_update_attack_timers(delta)
		_update_melee_hitbox_position()
		move_and_slide()
		was_on_floor_last_frame = is_on_floor()
		player_death()
		return
	
	if Input.is_action_just_pressed("interact") or Input.is_action_just_pressed("interact_controller"):
		if interaction_area and interaction_area.has_method("trigger_interact"):
			interaction_area.trigger_interact()
	# Reset gravity skip flag at start of frame
	skip_gravity_this_frame = false
	
	# === COYOTE TIME ===
	if is_on_floor():
		coyote_timer = COYOTE_TIME
	elif is_jumping:
		coyote_timer = 0.0  # No coyote time if the player jumped intentionally
	else:
		coyote_timer = max(coyote_timer - delta, 0.0)
	
	# Update dash cooldown
	if dash_cooldown_remaining > 0:
		dash_cooldown_remaining = max(dash_cooldown_remaining - delta, 0.0)
	
	# Decrement gap-snap cooldown so probing re-arms after a full GAP_SNAP_COOLDOWN window
	if _gap_snap_cooldown > 0.0:
		_gap_snap_cooldown = maxf(_gap_snap_cooldown - delta, 0.0)
	
	# Melee attack input
	if Input.is_action_just_pressed("attack") or Input.is_action_just_pressed("attack_controller"):
		_try_attack()
	# === RESET JUMP FLAGS ON LANDING ===

	if is_on_floor() and not was_on_floor_last_frame:
		is_jumping = false
		is_dash_jumping = false
		air_dash_used = false
	# Clamp horizontal velocity to normal speed on landing
	if abs(velocity.x) > SPEED * 1.1:  # Allow small buffer
		velocity.x = sign(velocity.x) * SPEED
	# Restore collision if it was waiting and there's space
	if needs_collision_restore:
		if can_stand_up():
			$CollisionShape2D.scale.y = 1.0
			$CollisionShape2D.position.y = 0
			needs_collision_restore = false
			is_crouching = false
		else:
			# Entering crouch - maintain reduced collision
			$CollisionShape2D.scale.y = 0.5
			$CollisionShape2D.position.y = $CollisionShape2D.shape.size.y * 0.25
			is_crouching = true
			needs_collision_restore = false

	# ADDITIONAL SAFETY: Always reset jumping flag if on floor
	if is_on_floor() and is_jumping:
		is_jumping = false
		is_dash_jumping = false
		air_dash_used = false
		
		# Clamp horizontal velocity to normal speed on landing
		if abs(velocity.x) > SPEED * 1.1:  # Allow small buffer
			velocity.x = sign(velocity.x) * SPEED
		# Restore collision if it was waiting and there's space
		if needs_collision_restore:
			if can_stand_up():
				$CollisionShape2D.scale.y = 1.0
				$CollisionShape2D.position.y = 0
				needs_collision_restore = false
				is_crouching = false
			else:
				# Entering crouch - maintain reduced collision
				$CollisionShape2D.scale.y = 0.5
				$CollisionShape2D.position.y = $CollisionShape2D.shape.size.y * 0.25
				is_crouching = true
				needs_collision_restore = false
	
	
	# Ground jump
	# Ground jump (with coyote time)
	if is_on_floor():
		air_dash_used = false

	if (is_on_floor() or coyote_timer > 0.0) and jump_pressed and not is_dashing:
		velocity.y = JUMP_HEIGHT
		is_jumping = true
		is_dash_jumping = false
		skip_gravity_this_frame = true
		coyote_timer = 0.0  # Consume coyote time so they can't double-jump
	
	# === DASH/DIVE LOGIC ===
	if is_dashing:
		
		# === CHECK FOR DASH JUMP FIRST - BEFORE applying dash movement ===
		if jump_pressed and is_on_floor():
			# Jump from dash - POWERFUL combined momentum!
			is_dashing = false
			is_air_dive = false
			air_dash_horizontal_timer = 0.0
			dash_cooldown_remaining = DASH_COOLDOWN
			
			# Restore collision height immediately (we're jumping from ground)
			$CollisionShape2D.scale.y = 1.0
			$CollisionShape2D.position.y = 0
			needs_collision_restore = false
			
			# POWERFUL dash jump with boosted height AND speed
			velocity.y = JUMP_HEIGHT * DASH_JUMP_HEIGHT_MULTIPLIER  # 30% higher jump!
			velocity.x = dash_direction * DASH_SPEED * DASH_JUMP_SPEED_MULTIPLIER  # 20% faster!
			
			is_jumping = true
			is_dash_jumping = true  # Mark as dash jump
			skip_gravity_this_frame = true  # Don't apply gravity this frame!
			
		elif jump_pressed and is_air_dive:
			# Can't jump during air dive (optional)
			pass
		else:
			# Not jumping, continue normal dash behavior
			dash_time_remaining -= delta
			
			if dash_time_remaining <= 0:
				# Dash ended — cancel any active gap snap
				_gap_snapping = false
				is_dashing = false
				is_air_dive = false
				air_dash_horizontal_timer = 0.0
				dash_cooldown_remaining = DASH_COOLDOWN
	
				# Only restore collision shape if there's space above
				if can_stand_up():
					$CollisionShape2D.scale.y = 1.0
					$CollisionShape2D.position.y = 0
					needs_collision_restore = false
					is_crouching = false
				else:
					# No space to stand — enter crouch state
					# CRITICAL: Keep the collision shape at reduced height
					$CollisionShape2D.scale.y = 0.5
					$CollisionShape2D.position.y = $CollisionShape2D.shape.size.y * 0.25
					is_crouching = true
					needs_collision_restore = false
			else:
				# Continue dashing
				velocity.x = dash_direction * DASH_SPEED
				
				if is_air_dive:
					# === AIR-DASH GAP DETECTION ===
					# Once per cooldown window, probe for a wall opening ahead and
					# snap the player into it so the dash flows through smoothly.
					if not _gap_snapping and _gap_snap_cooldown <= 0.0:
						var snap_y := _probe_air_dash_gap()
						if not is_nan(snap_y) and absf(snap_y - global_position.y) >= GAP_SNAP_MIN_DELTA_Y:
							_gap_snapping = true
							_gap_snap_cooldown = GAP_SNAP_COOLDOWN
							_gap_snap_start_y = global_position.y
							_gap_snap_target_y = snap_y
							_gap_snap_timer = 0.0

					# Vertical velocity: suppressed during snap so the interpolation
					# drives Y; otherwise follow normal air-dive curve.
					if _gap_snapping:
						velocity.y = 0.0  # snap tween owns the vertical axis
					elif air_dash_horizontal_timer < AIR_DASH_HORIZONTAL_TIME:
						# Horizontal phase - maintain velocity, no gravity
						air_dash_horizontal_timer += delta
						velocity.y = 0.0  # Keep horizontal during this phase
					else:
						# Horizontal phase over - apply gravity
						velocity.y += GRAVITY_NORMAL
						
						# Add extra downward momentum for dive feel
						if velocity.y < DIVE_VERTICAL_BOOST:
							velocity.y += GRAVITY_NORMAL * 2  # fall faster during dive
				else:
					# Ground dash - apply gravity normally
					velocity.y += GRAVITY_NORMAL

	
	# === INITIATE DASH/DIVE ===
	if dash_pressed and not is_dashing and dash_cooldown_remaining <= 0:
		# Check if we're on a GRIPPABLE wall FIRST (highest priority)
		# UPDATED: Use is_on_grippable_wall() instead of is_on_wall()
		if is_stuck_to_wall and is_on_grippable_wall() and not is_on_floor():
			# WALL DASH - Automatically dash away from wall
			is_dashing = true
			is_air_dive = true
			air_dash_horizontal_timer = 0.0
			dash_time_remaining = DASH_DURATION
			wall_stick_time = 0.0
			is_stuck_to_wall = false  # Release from wall
			
			# Dash AWAY from the wall automatically
			var wall_normal = get_wall_normal()
			dash_direction = sign(wall_normal.x)
			
			# Reduce collision height for dash
			$CollisionShape2D.scale.y = 0.5
			$CollisionShape2D.position.y = $CollisionShape2D.shape.size.y * 0.25
			
			# Set velocities for horizontal dash away from wall
			velocity.x = dash_direction * DASH_SPEED
			velocity.y = 0  # Start horizontal
			air_dash_used = true
			
			
		elif is_on_floor():
			# Ground dash - requires horizontal movement
			if abs(x_input) > 0.1:  # Must be moving horizontally
				is_dashing = true
				is_air_dive = false
				air_dash_horizontal_timer = 0.0
				dash_time_remaining = DASH_DURATION
				
				# Use input direction for dash
				dash_direction = sign(x_input)
				
				# Reduce collision height by half
				$CollisionShape2D.scale.y = 0.5
				$CollisionShape2D.position.y = $CollisionShape2D.shape.size.y * 0.25
				
				velocity.x = dash_direction * DASH_SPEED
				
				# OPTIONAL: keep player grounded during dash
				if velocity.y < 10:
					velocity.y = 10  # Small downward nudge to stay grounded
		else:
			# Air dive - no horizontal movement required
			if air_dash_used:
				# Only one air dash per airtime.
				pass
			else:
				is_dashing = true
				is_air_dive = true
				air_dash_horizontal_timer = 0.0  # Reset horizontal phase timer
				dash_time_remaining = DASH_DURATION
				air_dash_used = true
				
				# Determine dive direction (use input, or facing direction if no input)
				if abs(x_input) > 0.1:
					dash_direction = sign(x_input)
				else:
					# Dive in facing direction if no input
					dash_direction = facing_direction
				
				# Reduce collision height
				$CollisionShape2D.scale.y = 0.5
				$CollisionShape2D.position.y = $CollisionShape2D.shape.size.y * 0.25
				
				# Set dive velocities - start horizontal
				velocity.x = dash_direction * DASH_SPEED
				velocity.y = 0  # Start perfectly horizontal
	
	# Skip normal movement logic if dashing
	if not is_dashing:
		# === TRY ENTER LEDGE HANG ===
		# Must run before wall-stick attach so ledge hang takes priority when eligible.
		if not is_on_floor():
			_try_enter_ledge_hang()

		var on_grippable_wall = wall_probe_data.has_grippable_contact
		var can_slide_jump_on_wall = wall_probe_data.can_wall_slide_jump
		
		# Determine which wall we're on
		var wall_normal = get_wall_normal()
		var on_left_wall = on_grippable_wall and wall_normal.x > 0  # UPDATED
		var on_right_wall = on_grippable_wall and wall_normal.x < 0  # UPDATED
		
		# Check if pressing AWAY from wall
		var pressing_away_from_wall = false
		if on_left_wall and x_input > 0:
			pressing_away_from_wall = true
		elif on_right_wall and x_input < 0:
			pressing_away_from_wall = true
		
		# Check if we JUST touched a GRIPPABLE wall (and should attach to it)
		# UPDATED: Use is_on_grippable_wall() instead of is_on_wall()
		if on_grippable_wall and not is_on_floor() and not is_stuck_to_wall and not pressing_away_from_wall and not is_ledge_hanging:
			# Only attach if moving downward (falling) or just barely upward
			if velocity.y >= -100:  # Allow slight upward velocity
				is_stuck_to_wall = true
				wall_stick_time = 0.0

		# === WALL STICK & SLIDE PHYSICS ===
		var is_wall_sliding = false

		# Apply wall stick/slide physics only when top+middle probes are grippable.
		if is_stuck_to_wall and can_slide_jump_on_wall and not is_on_floor():
			is_wall_sliding = true
	
			if wall_stick_time < WALL_STICK_DURATION:
				wall_stick_time += delta
				velocity.y = 0
			else:
				velocity.y = GRAVITY_WALL_SLIDE
	
			# Handle wall jump
			if jump_pressed:
				velocity.y = JUMP_HEIGHT
				velocity.x = wall_normal.x * WALL_JUMP_PUSH_FORCE
				wall_jump_lock = WALL_JUMP_LOCK_TIME
				is_wall_jumping = true
				is_jumping = true
				is_dash_jumping = false  # Wall jumps are NOT dash jumps
				# Refresh one air dash after a successful wall jump.
				air_dash_used = false
				skip_gravity_this_frame = true  # Don't apply gravity on jump frame
				wall_stick_time = 0.0
				is_stuck_to_wall = false  # Release from wall
		
		# Check if we should STOP sticking to wall (AFTER checking actions)
		# This way dash/jump take priority over manual release
		# UPDATED: Use is_on_grippable_wall() instead of is_on_wall()
		if is_stuck_to_wall and not is_wall_sliding:
			# Only release manually if NOT currently on wall OR pressing away OR on floor
			if pressing_away_from_wall or not can_slide_jump_on_wall or is_on_floor():
				is_stuck_to_wall = false
				wall_stick_time = 0.0

		
		# Apply gravity when NOT on wall
		if not is_wall_sliding:
			wall_stick_time = 0.0
			
			# Apply normal gravity - BUT NOT on jump frames
			if not is_on_floor() and not skip_gravity_this_frame:
				velocity.y += GRAVITY_NORMAL
		
		# === VARIABLE JUMP HEIGHT ===
		# Only cut normal jumps, not dash jumps
		if jump_released and is_jumping and velocity.y < 0:
			if not is_dash_jumping:
				if velocity.y < 0:
					velocity.y *= JUMP_CUT_MULTIPLIER 
				else:
					pass
		
		# Horizontal movement (removed to keep output cleaner - doesn't affect velocity.y)
		if wall_jump_lock > 0.0:
			wall_jump_lock -= delta
			velocity.x = lerp(velocity.x, x_input * SPEED, 0.075)
		elif is_dash_jumping and not is_on_floor():
			if x_input != 0:
				velocity.x = lerp(velocity.x, x_input * SPEED, DASH_JUMP_AIR_CONTROL)
			else:
				velocity.x = lerp(velocity.x, 0.0, DASH_JUMP_AIR_CONTROL * 0.5)
		elif is_crouching:
			# Check each frame if space has opened up to stand
			if can_stand_up():
				$CollisionShape2D.scale.y = 1.0
				$CollisionShape2D.position.y = 0
				needs_collision_restore = false
				is_crouching = false
			else:
				# MAKE SURE collision stays reduced while crouching
				$CollisionShape2D.scale.y = 0.5
				$CollisionShape2D.position.y = $CollisionShape2D.shape.size.y * 0.25
			# Move at reduced crouch speed
			if x_input != 0:
				velocity.x = lerp(velocity.x, x_input * CROUCH_SPEED, 0.15)
				facing_direction = sign(x_input)
			else:
				velocity.x = move_toward(velocity.x, 0, FRICTION)
		else:
			if x_input != 0:
				velocity.x = lerp(velocity.x, x_input * SPEED, 0.15)
				facing_direction = sign(x_input)  # Track facing direction
			else:
				velocity.x = move_toward(velocity.x, 0, FRICTION)
		
		update_animations(x_input)
	else:
		# === DASHING/DIVING ANIMATION ===
		$AnimationPlayer.play("Dash")
		# Maintain sprite direction during dash
		$Sprite2D.flip_h = dash_direction < 0
		facing_direction = dash_direction  # Update facing direction during dash
	_update_attack_timers(delta)
	_update_melee_hitbox_position()
	move_and_slide()

	# === AIR-DASH GAP SNAP: advance vertical interpolation ===
	# Runs AFTER move_and_slide so physics doesn't fight the snap each frame.
	# velocity.y was set to 0 above, so move_and_slide only applied horizontal motion;
	# we now directly place the Y to the eased interpolation target.
	if _gap_snapping:
		_gap_snap_timer += delta
		var t := minf(_gap_snap_timer / GAP_SNAP_TWEEN_TIME, 1.0)
		# Ease-out quadratic: decelerates smoothly into the gap
		var t_eased := 1.0 - (1.0 - t) * (1.0 - t)
		global_position.y = lerpf(_gap_snap_start_y, _gap_snap_target_y, t_eased)
		if t >= 1.0:
			_gap_snapping = false

	# === STEP-UP MECHANIC ===
	# Check if we should step up a small obstacle
	# Works during normal movement AND dash/slide

	var step_height = 0.0  # Declare OUTSIDE the if block

	if is_on_floor() and not is_jumping:
		step_height = check_for_step(x_input)  # Now just assign, not declare
	
	if step_height > 0:
		# Instantly move the player up by the step height (pixel-perfect style)
		position.y -= step_height
		stepped_up = true
	
	# Track floor state for next frame
	was_on_floor_last_frame = is_on_floor()
	
	player_death()

func can_stand_up() -> bool:
	if $CollisionShape2D.scale.y >= 1.0:
		return true
	
	var world_2d = get_world_2d()
	if world_2d == null:
		return true  # Can't check; assume safe to stand
	var space_state = world_2d.direct_space_state
	var collision_shape = $CollisionShape2D.shape
	var player_height = collision_shape.size.y
	var height_difference = player_height * 0.5  # The amount we're adding
	
	# Check from current top of collision to where new top would be
	var collision_offset = $CollisionShape2D.position.y
	var ray_start = global_position + Vector2(0, collision_offset - player_height * 0.25)  # Current top
	var ray_end = ray_start - Vector2(0, height_difference + 5.0)  # Add small buffer
	
	var query = PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.exclude = [self]
	query.collision_mask = 0xFFFFFFFF  # Detect all layers including tilesets
	
	var result = space_state.intersect_ray(query)
	
	var can_stand = result.is_empty()
	var debug_color = Color.GREEN if can_stand else Color.RED
	if debug_rays_visible:
		debug_rays.append({
			"type": "line",
			"start": ray_start,
			"end": ray_end if can_stand else result.position,
			"color": debug_color
		})
	
	return can_stand

## === STEP-UP MECHANIC HELPERS ===
# Check if there's a step in front of the player and return the step height
func check_for_step(x_input: float) -> float:
	
	# Only check for steps when on the ground
	if not is_on_floor():
		return 0.0
	# Player must be pressing toward the direction they're facing OR dashing
	var trying_to_move_forward = false
	
	if is_dashing:
		trying_to_move_forward = true
	else:
		if abs(x_input) > 0.1:
			if sign(x_input) == sign(facing_direction):
				trying_to_move_forward = true
	
	if not trying_to_move_forward:
		return 0.0
	
	# Use the direction the player is facing
	var step_direction = facing_direction
	
	# Create a raycast to check for obstacles ahead
	var world_2d = get_world_2d()
	if world_2d == null:
		return 0.0  # Can't check; skip step detection
	var space_state = world_2d.direct_space_state
	
	# Get the collision shape size
	var collision_shape = $CollisionShape2D.shape
	var player_width = collision_shape.size.x / 2.0
	var player_height = collision_shape.size.y
	
	# Check for wall ahead at player's FEET level
	# Start from the front edge AND near the bottom
	var feet_offset = player_height * 0.4  # Slightly above the very bottom to avoid floor
	var ray_start = global_position + Vector2(step_direction * player_width, feet_offset)
	var ray_end = ray_start + Vector2(step_direction * STEP_UP_CHECK_DISTANCE, 0)
	
	var query = PhysicsRayQueryParameters2D.create(ray_start, ray_end)
	query.exclude = [self]
	query.collision_mask = 2  # Only check "World" layer (layer 2)
	
	var result = space_state.intersect_ray(query)
	
	if debug_rays_visible:
		var hit_color = Color.ORANGE if result else Color(1.0, 0.65, 0.0, 0.4)
		debug_rays.append({"type": "line", "start": ray_start,
				"end": result.position if result else ray_end, "color": hit_color})
	
	# If we hit a wall
	if result:
		
		# Now check how high the wall is by casting a ray downward from above
		var check_height = STEP_UP_MAX_HEIGHT
		var top_check_start = result.position + Vector2(step_direction * 2, -check_height)
		var top_check_end = result.position + Vector2(step_direction * 2, 0)
		
		var top_query = PhysicsRayQueryParameters2D.create(top_check_start, top_check_end)
		top_query.exclude = [self]
		top_query.collision_mask = 2
		
		var top_result = space_state.intersect_ray(top_query)
		
		if debug_rays_visible:
			var top_color = Color.YELLOW if top_result else Color(1.0, 1.0, 0.0, 0.4)
			debug_rays.append({"type": "line", "start": top_check_start,
					"end": top_result.position if top_result else top_check_end, "color": top_color})
			if top_result:
				debug_rays.append({"type": "circle", "pos": top_result.position, "color": Color.CYAN})
		
		if top_result:
			# Found the top! Calculate step height.
			# player_bottom_y must use the actual collision-shape half-height (feet),
			# NOT feet_offset (the detection-ray height which is 0.4 × height).
			# Using feet_offset here was the regression: the teleport undershoots
			# by player_height * 0.1 px, leaving the player partially inside the step.
			var step_top_y = top_result.position.y -10
			var player_bottom_y = global_position.y + player_height / 2.0
			
			var step_height_measured = player_bottom_y - step_top_y
			
			# Only step up if it's within our max height AND positive
			if step_height_measured > 0 and step_height_measured <= STEP_UP_MAX_HEIGHT:
				return step_height_measured
	
	return 0.0

## === LEDGE HANG SYSTEM (replaces legacy ledge-grab detection) ===

func _get_player_half_height_world() -> float:
	var collision_node := $CollisionShape2D
	var collision_shape := collision_node.shape as RectangleShape2D
	if collision_shape == null:
		return 0.0
	return collision_shape.size.y * abs(collision_node.scale.y) * 0.5

# Find the ledge hang point (current position) and stand point (top of ledge)
# from current wall probe state. Returns a dict with valid, hang_point, stand_point, wall_normal.
func _compute_ledge_hang_from_probes() -> Dictionary:
	var out := {"valid": false, "hang_point": Vector2.ZERO, "stand_point": Vector2.ZERO, "wall_normal": Vector2.ZERO}

	var probe_data := _get_wall_probe_data()
	var first_mid_probe_name := _middle_probe_name(1)
	if not probe_data.probes.has(first_mid_probe_name):
		return out
	var first_mid_probe: Dictionary = probe_data.probes[first_mid_probe_name]
	if probe_data.probes.top.hit_slippery:
		return out
	if probe_data.probes.top.hit_grippable:
		return out
	if not first_mid_probe.hit_grippable:
		return out

	var world_2d := get_world_2d()
	if world_2d == null:
		return out

	var wall_normal := get_wall_normal()
	if wall_normal == Vector2.ZERO:
		# Derive from facing direction when CharacterBody2D hasn't registered wall contact yet.
		wall_normal = Vector2(-facing_direction, 0.0)

	var space_state := world_2d.direct_space_state
	var into_wall_dir: float = -wall_normal.x  # +1 or -1 toward wall

	var collision_node := $CollisionShape2D
	var collision_shape := collision_node.shape as RectangleShape2D
	if collision_shape == null:
		return out

	var half_h = _get_player_half_height_world()

	# Probe x: place ray past the wall face to detect the ledge top floor surface.
	var edge_probe_x := global_position.x + into_wall_dir * (WALL_PROBE_LATERAL_REACH + 8.0)
	# Start scanning just above the player's head and sweep downward.
	var origin_y = global_position.y - half_h

	var floor_hit := {}
	for i in range(LEDGE_FLOOR_PROBE_ITERATIONS):
		var y = origin_y + float(i) * LEDGE_FLOOR_PROBE_STEP
		var start := Vector2(edge_probe_x, y - LEDGE_FLOOR_PROBE_UP)
		var end_pos := Vector2(edge_probe_x, y + LEDGE_FLOOR_PROBE_DOWN)
		var q := PhysicsRayQueryParameters2D.create(start, end_pos)
		q.exclude = [self]
		q.collision_mask = 2
		floor_hit = space_state.intersect_ray(q)
		if floor_hit:
			break

	if not floor_hit:
		return out

	# Hang point: align the top of the player with the detected ledge top.
	var ledge_top_y = floor_hit.position.y
	var hang_point = Vector2(global_position.x, ledge_top_y + half_h)

	# Stand point: position player so feet land on the ledge top surface,
	# nudged slightly onto the ledge horizontally.
	var stand_point := Vector2(
		global_position.x + into_wall_dir * LEDGE_HANG_HORIZONTAL_NUDGE,
		floor_hit.position.y - half_h - LEDGE_HANG_OFFSET_Y
	)

	out.valid = true
	out.hang_point = hang_point
	out.stand_point = stand_point
	out.wall_normal = wall_normal
	return out


# Returns true if the player-shaped body can occupy 'pos' without overlapping world geometry.
func _can_occupy_at_position(pos: Vector2) -> bool:
	var world_2d := get_world_2d()
	if world_2d == null:
		return true
	var space_state := world_2d.direct_space_state

	var collision_node := $CollisionShape2D
	var src_shape := collision_node.shape as RectangleShape2D
	if src_shape == null:
		return true

	# Use full standing collision size regardless of current crouch scale.
	var stand_shape := RectangleShape2D.new()
	stand_shape.size = src_shape.size

	var qp := PhysicsShapeQueryParameters2D.new()
	qp.shape = stand_shape
	qp.transform = Transform2D(0.0, pos + collision_node.position)
	qp.exclude = [self]
	qp.collision_mask = 2

	var hits := space_state.intersect_shape(qp, 1)
	return hits.is_empty()


# Called each frame while is_ledge_hanging to maintain freeze and handle jump input.
func _handle_ledge_hang_input(jump_pressed: bool) -> void:
	# Release hang if player somehow lands (e.g., platform rises).
	if is_on_floor():
		is_ledge_hanging = false
		return

	# Freeze position and velocity every frame.
	velocity = Vector2.ZERO
	global_position = ledge_hang_point

	if not jump_pressed:
		return

	# If pressing away from the ledge while jumping, perform a wall jump instead of climbing.
	var x_input := Input.get_axis("move_left", "move_right")
	var pressing_away_from_ledge = x_input != 0.0 and sign(x_input) == sign(ledge_hang_wall_normal.x)

	is_ledge_hanging = false

	if pressing_away_from_ledge:
		velocity.y = JUMP_HEIGHT
		velocity.x = ledge_hang_wall_normal.x * WALL_JUMP_PUSH_FORCE
		wall_jump_lock = WALL_JUMP_LOCK_TIME
		is_wall_jumping = true
		is_jumping = true
		is_dash_jumping = false
		air_dash_used = false
		return

	if not _can_occupy_at_position(ledge_stand_point):
		# No room to stand on top → wall jump away from wall.
		velocity.y = JUMP_HEIGHT
		velocity.x = ledge_hang_wall_normal.x * WALL_JUMP_PUSH_FORCE
		wall_jump_lock = WALL_JUMP_LOCK_TIME
		is_wall_jumping = true
		is_jumping = true
		is_dash_jumping = false
		air_dash_used = false
		return

	# Room available: tween player onto the ledge top.
	is_ledge_climbing = true
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", ledge_stand_point, LEDGE_CLIMB_TWEEN_TIME)
	t.finished.connect(func() -> void:
		is_ledge_climbing = false
		velocity = Vector2.ZERO
	)


# Evaluate whether probe conditions are right to enter ledge hang and do so if so.
func _try_enter_ledge_hang() -> void:
	if is_ledge_hanging or is_ledge_climbing:
		return
	if is_on_floor() or is_dashing:
		return

	var ledge := _compute_ledge_hang_from_probes()
	if not ledge.valid:
		return

	# Verify there is enough clearance for the player's full collider at the
	# intended hang position before committing to the hang state and tweening
	# the player there.  If the space is blocked (e.g. by nearby geometry)
	# skip the hang transition and let existing fall/slide logic continue.
	if not _can_occupy_at_position(ledge.hang_point):
		return

	is_ledge_hanging = true
	ledge_hang_point = ledge.hang_point
	ledge_stand_point = ledge.stand_point
	ledge_hang_wall_normal = ledge.wall_normal
	velocity = Vector2.ZERO
	is_ledge_hanging = false
	is_ledge_climbing = true
	is_ledge_hang_transitioning = true
	is_stuck_to_wall = false
	wall_stick_time = 0.0
	skip_gravity_this_frame = true  # Suppress gravity on the entry frame.
	var t := create_tween()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", ledge_hang_point, LEDGE_CLIMB_TWEEN_TIME)
	t.finished.connect(func() -> void:
		velocity = Vector2.ZERO
		is_ledge_climbing = false
		is_ledge_hang_transitioning = false
		is_ledge_hanging = true
	)


## === DEBUG VISUALIZATION ===
func _process(_delta):
	# Toggle debug rays with F3
	if Input.is_action_just_pressed("debug_raycast"):
		debug_rays_visible = !debug_rays_visible
		print("Debug raycasts: ", "ON" if debug_rays_visible else "OFF")
	
	queue_redraw()
	# DEBUG: Update ColorRect to match collision shape size
	if OS.is_debug_build() and has_node("ColorRect") and has_node("CollisionShape2D"):
		var color_rect = $ColorRect
		var collision = $CollisionShape2D
		var shape = collision.shape as RectangleShape2D
		
		if shape:
			# Make it visible for debugging
			color_rect.visible = debug_rays_visible
			
			# Calculate the actual size based on shape size and scale
			var actual_width = shape.size.x * collision.scale.x
			var actual_height = shape.size.y * collision.scale.y
			
			# Update ColorRect size (centered around origin)
			color_rect.offset_left = -actual_width / 2
			color_rect.offset_right = actual_width / 2
			color_rect.offset_top = -actual_height / 2 + collision.position.y
			color_rect.offset_bottom = actual_height / 2 + collision.position.y
			
			# Optional: Change color based on state for better debugging
			if is_crouching:
				color_rect.color = Color(1, 0.5, 0, 0.5)  # Orange when crouching
			elif is_dashing:
				color_rect.color = Color(1, 0, 0, 0.5)  # Red when dashing
			else:
				color_rect.color = Color(0.2, 0.6, 1, 0.5)  # Blue normally

func _draw():
	if not debug_rays_visible:
		return
	
	# Draw all stored debug rays
	for ray in debug_rays:
		if ray.type == "line":
			draw_line(ray.start - global_position, ray.end - global_position, ray.color, 2.0)
		elif ray.type == "circle":
			draw_circle(ray.pos - global_position, 5, ray.color)
		elif ray.type == "rect":
			var rect_size: Vector2 = ray.size
			var rect_center: Vector2 = ray.center - global_position
			var rect := Rect2(rect_center - rect_size * 0.5, rect_size)
			draw_rect(rect, ray.color, false, 1.5)
	
	# Clear AFTER drawing, ready for next physics frame
	debug_rays.clear()

## === MELEE COMBAT STATE & HELPERS ===
var is_attacking: bool = false
var attack_duration: float = 0.18
var attack_cooldown: float = 0.25
var _attack_timer: float = 0.0
var _attack_cooldown_timer: float = 0.0

var melee_offset := Vector2(40, 0) #this can change to match hitbox

func _try_attack() -> void:
	if is_dead or health <= 0 or is_attacking or _attack_cooldown_timer > 0.0 or is_dashing:
		return

	is_attacking = true
	_attack_timer = attack_duration
	_attack_cooldown_timer = attack_cooldown
	$AnimationPlayer.play("Attack")
	print("Attack started")

	melee_hitbox.monitoring = true
	melee_hitbox.monitorable = true



func _update_attack_timers(delta: float) -> void:
	if _attack_cooldown_timer > 0.0:
		_attack_cooldown_timer -= delta

	if is_attacking:
		_attack_timer -= delta
		if _attack_timer <= 0.0:
			is_attacking = false
			melee_hitbox.monitoring = false
			melee_hitbox.monitorable = false

func _reset_attack_state(reset_animation: bool = false) -> void:
	is_attacking = false
	_attack_timer = 0.0
	_attack_cooldown_timer = 0.0

	if melee_hitbox:
		melee_hitbox.monitoring = false
		melee_hitbox.monitorable = false

	$Hit.visible = false

	if reset_animation:
		$AnimationPlayer.stop()
		$AnimationPlayer.play("Idle")


func _update_melee_hitbox_position() -> void:
	if melee_hitbox:
		melee_hitbox.position = Vector2(melee_offset.x * facing_direction, melee_offset.y)


func _on_melee_hitbox_body_entered(body: Node2D) -> void:
	if not is_attacking:
		return

	if body.has_method("take_damage"):
		body.take_damage(1)

func _on_melee_hitbox_area_entered(area: Area2D) -> void:
	if not is_attacking:
		return

	# Common pattern: enemy has an Area2D Hurtbox as a child.
	# Try the area itself, then parent, then owner.
	if area.has_method("take_damage"):
		area.call("take_damage", 1)
		return

	var parent := area.get_parent()
	if parent and parent.has_method("take_damage"):
		parent.call("take_damage", 1)
		return

	var owner_node := area.owner
	if owner_node and owner_node.has_method("take_damage"):
		owner_node.call("take_damage", 1)

func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if anim_name == "Getup":
		stepped_up = false


## === AIR-DASH GAP DETECTION ===

# Casts a vertical column of rays in the dash direction to find a wall opening
# large enough for the player's current (dash-reduced) collision shape.
#
# The probe starts at the player's leading edge and reaches GAP_PROBE_REACH px
# forward.  A ray that misses means open space at that Y; consecutive misses form
# a candidate gap.  The best (longest) clear run is validated with a shape cast
# before committing to the snap.
#
# Returns the target global_position.y to centre the player in the gap, or NAN.
func _probe_air_dash_gap() -> float:
	var world_2d := get_world_2d()
	if world_2d == null:
		return NAN
	var space_state = world_2d.direct_space_state

	var collision_node = $CollisionShape2D
	var src_shape = collision_node.shape as RectangleShape2D
	if src_shape == null:
		return NAN

	# Effective collision half-extents during dash (scale is applied to the shape)
	var player_half_w = src_shape.size.x * absf(collision_node.scale.x) * 0.5
	var player_half_h = src_shape.size.y * absf(collision_node.scale.y) * 0.5
	var player_h      = player_half_h * 2.0

	# The actual centre of the collision shape in world space (offset by node position)
	var shape_center_y = global_position.y + collision_node.position.y

	# Probe column: slightly taller than the player so nearby gaps are also detected
	var probe_half_h = player_half_h + GAP_PROBE_HEIGHT_BONUS * 0.5
	var probe_top_y  = shape_center_y - probe_half_h
	var probe_bot_y  = shape_center_y + probe_half_h

	# Horizontal extents of the probe: start at leading edge, end GAP_PROBE_REACH ahead
	var leading_x   = global_position.x + dash_direction * player_half_w
	var probe_end_x = leading_x + dash_direction * GAP_PROBE_REACH

	var total_probe_h = probe_bot_y - probe_top_y
	# Requires at least 2 rays to form a meaningful step; GAP_PROBE_RAY_COUNT is 14.
	if GAP_PROBE_RAY_COUNT < 2 or total_probe_h <= 0.0:
		return NAN
	var step = total_probe_h / float(GAP_PROBE_RAY_COUNT - 1)

	# Cast each ray horizontally and record whether it was clear
	var clear: Array[bool] = []
	for i in range(GAP_PROBE_RAY_COUNT):
		var y         = probe_top_y + i * step
		var ray_start = Vector2(leading_x, y)
		var ray_end   = Vector2(probe_end_x, y)
		var q = PhysicsRayQueryParameters2D.create(ray_start, ray_end)
		q.exclude        = [self]
		q.collision_mask = GAP_PROBE_COLLISION_MASK
		var result = space_state.intersect_ray(q)
		clear.append(result.is_empty())

		if debug_rays_visible:
			var dbg_col = Color(0.0, 0.85, 0.0, 0.75) if result.is_empty() \
						  else Color(0.85, 0.15, 0.15, 0.75)
			debug_rays.append({
				"type": "line",
				"start": ray_start,
				"end": result.position if not result.is_empty() else ray_end,
				"color": dbg_col
			})

	# Minimum number of consecutive clear rays required to fit the player
	var min_clear := maxi(1, int(ceilf(player_h / step)))

	# Find the longest consecutive run of clear rays (best candidate gap)
	var best_start := -1
	var best_len   := 0
	var cur_start  := -1
	var cur_len    := 0
	for i in range(GAP_PROBE_RAY_COUNT):
		if clear[i]:
			if cur_len == 0:
				cur_start = i
			cur_len += 1
			if cur_len > best_len:
				best_len  = cur_len
				best_start = cur_start
		else:
			cur_len = 0

	if best_len < min_clear:
		return NAN  # No opening large enough for the player

	# Centre of the clear band in world Y (shape-centre coordinates)
	var gap_top          = probe_top_y + best_start * step
	var gap_bot          = probe_top_y + (best_start + best_len - 1) * step
	var gap_center_world = (gap_top + gap_bot) * 0.5

	# Convert to the global_position.y the player needs after snapping
	var target_pos_y = gap_center_world - collision_node.position.y

	# Final safety check: ensure the dash-reduced shape actually fits there
	if not _can_fit_dash_shape_at(Vector2(global_position.x, target_pos_y)):
		return NAN

	return target_pos_y


# Shape-cast check: can the player's current (dash-reduced) collision shape
# occupy 'pos' (used as global_position) without overlapping world geometry?
func _can_fit_dash_shape_at(pos: Vector2) -> bool:
	var world_2d := get_world_2d()
	if world_2d == null:
		return true
	var space_state := world_2d.direct_space_state

	var collision_node := $CollisionShape2D
	var src_shape := collision_node.shape as RectangleShape2D
	if src_shape == null:
		return true

	# Build a rectangle matching the dash-reduced extents
	var check_shape      := RectangleShape2D.new()
	check_shape.size = Vector2(
		src_shape.size.x * absf(collision_node.scale.x),
		src_shape.size.y * absf(collision_node.scale.y)
	)

	var qp := PhysicsShapeQueryParameters2D.new()
	qp.shape          = check_shape
	# The collision node has a local Y offset during dash; reproduce it here
	qp.transform      = Transform2D(0.0, pos + collision_node.position)
	qp.exclude        = [self]
	qp.collision_mask = GAP_PROBE_COLLISION_MASK

	var hits := space_state.intersect_shape(qp, 1)
	return hits.is_empty()
