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

# === STEP-UP / LEDGE CONSTANTS ===
const STEP_UP_MAX_HEIGHT: float = 30.0
const STEP_UP_CHECK_DISTANCE: float = 10.0

# === LEDGE GRAB CONSTANTS ===
const LEDGE_GRAB_DISTANCE: float = 30.0  # Reduced - how far above player to check for ledge

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
var health = 3
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

## === NODES / CHILDREN ===
@onready var melee_hitbox: Area2D = $MeleeHitbox
@onready var interaction_area = $InteractionArea

var debug_rays = []
var debug_rays_visible := false

signal health_changed

func player_death():
	# When health reaches 0, ask Main to respawn instead of reloading the scene.
	if health > 0:
		return

	var main := get_tree().get_first_node_in_group("GameMain")
	if main and main.has_method("reset_current_level_on_death"):
		main.call("reset_current_level_on_death")
		return

	# Fallback: if Main can't be found for some reason, keep old behavior.
	queue_free()
	get_tree().reload_current_scene()

func kill_player():
	if health <= 0:
		return  # Already dead
	health = 0
	velocity = Vector2.ZERO
	set_physics_process(false)
	player_death()
	coyote_timer = 0.0

func damage_player():
	health = max(health - 1, 0)
	$SFX/hurt.play()
	emit_signal("health_changed", health)

func reset_for_respawn() -> void:
	# Reset movement/combat state so respawns don't inherit dash/crouch collisions.
	velocity = Vector2.ZERO
	set_physics_process(true)

	# Wall/ledge related state.
	wall_stick_time = 0.0
	wall_jump_lock = 0.0
	is_stuck_to_wall = false
	is_wall_jumping = false

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

	# Collision shape back to full height.
	$CollisionShape2D.scale.y = 1.0
	$CollisionShape2D.position.y = 0

	# Combat state.
	is_attacking = false
	_attack_timer = 0.0
	_attack_cooldown_timer = 0.0
	if melee_hitbox:
		melee_hitbox.monitoring = false
		melee_hitbox.monitorable = false
	
	# --- FIX: Reset the animation player and attack visual ---
	$AnimationPlayer.stop()
	$AnimationPlayer.play("Idle")
	$Hit.visible = false

func heal(amount: int = 1) -> void:
	health = min(health + amount, 3)
	emit_signal("health_changed", health)

func update_animations(x_input: float) -> void:
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

func is_on_grippable_wall() -> bool:
	if not is_on_wall():
		return false
	
	for i in range(get_slide_collision_count()):
		var collision := get_slide_collision(i)
		var collider := collision.get_collider()
		
		# Handle TileMapLayer using groups
		if collider is TileMapLayer:
			if collider.is_in_group("grippable_wall"):
				return true
			# Slippery or ungrouped - not grippable
			continue
				
		# Handle physics bodies (moving platforms, etc.)
		elif "collision_layer" in collider:
			# Check if on layer 2 (World - Platforming)
			if collider.collision_layer & (1 << 1):
				return true
	
	# No grippable walls found
	return false

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
				# Dash ended
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
					# === AIR DASH HORIZONTAL PHASE ===
					if air_dash_horizontal_timer < AIR_DASH_HORIZONTAL_TIME:
						# Horizontal phase - maintain velocity, no gravity
						air_dash_horizontal_timer += delta
						velocity.y = 0  # Keep horizontal during this phase
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
		
		# Determine which wall we're on
		var wall_normal = get_wall_normal()
		var on_left_wall = is_on_grippable_wall() and wall_normal.x > 0  # UPDATED
		var on_right_wall = is_on_grippable_wall() and wall_normal.x < 0  # UPDATED
		
		# Check if pressing AWAY from wall
		var pressing_away_from_wall = false
		if on_left_wall and x_input > 0:
			pressing_away_from_wall = true
		elif on_right_wall and x_input < 0:
			pressing_away_from_wall = true
		
		# Check if we JUST touched a GRIPPABLE wall (and should grab it)
		# UPDATED: Use is_on_grippable_wall() instead of is_on_wall()
		if is_on_grippable_wall() and not is_on_floor() and not is_stuck_to_wall and not pressing_away_from_wall:
			# Only grab if moving downward (falling) or just barely upward
			if velocity.y >= -100:  # Allow slight upward velocity
				is_stuck_to_wall = true
				wall_stick_time = 0.0

		# === WALL STICK & SLIDE PHYSICS ===
		var is_wall_sliding = false

		# Apply wall stick/slide physics if stuck ON A GRIPPABLE WALL
		# UPDATED: Use is_on_grippable_wall() instead of is_on_wall()
		if is_stuck_to_wall and is_on_grippable_wall() and not is_on_floor():
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
			if pressing_away_from_wall or not is_on_grippable_wall() or is_on_floor():
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
	
	# === LEDGE GRAB MECHANIC ===
	# Check for ledge grab when in the air and touching a wall
	# BUT NOT when wall sliding (to prevent raycasting issues)
	# AND only on grippable walls (not slippery walls)
	if not is_on_floor() and is_on_wall() and not is_stuck_to_wall and is_on_grippable_wall():
		var ledge_data = check_for_ledge()
		if ledge_data != Vector2.ZERO:
			# Teleport to ledge position
			global_position = ledge_data
			velocity.y = 0  # Cancel vertical velocity
			# Release from wall if stuck
			is_stuck_to_wall = false
			wall_stick_time = 0.0
	
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
		
		if top_result:
			# Found the top! Calculate step height
			var step_top_y = top_result.position.y
			var player_bottom_y = global_position.y + feet_offset
			
			var step_height_measured = player_bottom_y - step_top_y
			
			# Only step up if it's within our max height AND positive
			if step_height_measured > 0 and step_height_measured <= STEP_UP_MAX_HEIGHT:
				return step_height_measured
	
	return 0.0


## === LEDGE GRAB HELPERS ===
func check_for_ledge() -> Vector2:
	#debug_rays.clear()  # Clear previous frame's debug data
	
	if not is_on_wall():
		return Vector2.ZERO
	
	var world_2d = get_world_2d()
	if world_2d == null:
		return Vector2.ZERO  # Can't check; skip ledge detection
	var space_state = world_2d.direct_space_state
	var wall_normal = get_wall_normal()
	
	# Direction INTO the wall (opposite of normal)
	var into_wall_direction = -wall_normal.x
	
	# Get collision shape info
	var collision_shape = $CollisionShape2D.shape
	var dplayer_width = collision_shape.size.x / 2.0
	var player_height = collision_shape.size.y / 2.0
	
	# Start checking from the BOTTOM of the player (feet level)
	var player_bottom_y = global_position.y + player_height
	
	# Check upward in smaller increments for better detection
	for i in range(6):
		var check_offset = i * 5.0
		var check_y = player_bottom_y - check_offset
		
		if check_offset > LEDGE_GRAB_DISTANCE:
			break
		
		# Check if there's still a wall at this height
		# Cast from player position TOWARD the wall
		var wall_check_start = Vector2(global_position.x, check_y)
		var wall_check_end = wall_check_start + Vector2(into_wall_direction * 20, 0)
		
		# Store debug info
		if debug_rays_visible:
			debug_rays.append({"type": "line", "start": wall_check_start, "end": wall_check_end, "color": Color.YELLOW})
		
		var wall_query = PhysicsRayQueryParameters2D.create(wall_check_start, wall_check_end)
		wall_query.exclude = [self]
		wall_query.collision_mask = 2
		
		var wall_result = space_state.intersect_ray(wall_query)
		
		# If we DON'T hit a wall at this height, the wall has ended - check for floor
		if not wall_result:
			# Now check if there's a floor where the wall used to be
			# Cast downward from where the wall check ended (into the wall area)
			var floor_check_start = wall_check_end  # Start from where wall check ended
			var floor_check_end = floor_check_start + Vector2(0, 50)
			
			# Store debug info
			if debug_rays_visible:
				debug_rays.append({"type": "line", "start": floor_check_start, "end": floor_check_end, "color": Color.GREEN})
			# Store debug info
			#debug_rays.append({"type": "line", "start": floor_check_start, "end": floor_check_end, "color": Color.GREEN})
			
			var floor_query = PhysicsRayQueryParameters2D.create(floor_check_start, floor_check_end)
			floor_query.exclude = [self]
			floor_query.collision_mask = 2
			
			var floor_result = space_state.intersect_ray(floor_query)
			
			if floor_result:
				# Store debug info
				if debug_rays_visible:
					debug_rays.append({"type": "circle", "pos": floor_result.position, "color": Color.RED})
				
				# Found a valid ledge! But first check if player fits
				var teleport_pos = Vector2(
					floor_result.position.x,
					floor_result.position.y - player_height - 2
				)
				
				# Check if there's enough space for the player
				# Account for current collision shape scale (0.5 when dashing, 1.0 normally)
				var current_scale = $CollisionShape2D.scale.y
				var required_height = player_height * current_scale
				# Cast upward from feet level (teleport_pos) to where the player's head would be
				var space_check_start = teleport_pos
				var space_check_end = teleport_pos + Vector2(0, -required_height)
				
				var space_query = PhysicsRayQueryParameters2D.create(space_check_start, space_check_end)
				space_query.exclude = [self]
				space_query.collision_mask = 2  # World collision layer
				
				if debug_rays_visible:
					debug_rays.append({"type": "line", "start": space_check_start, "end": space_check_end, "color": Color.CYAN})
				
				var space_result = space_state.intersect_ray(space_query)
				
				# If we hit something, there's not enough space
				if space_result:
					if debug_rays_visible:
						debug_rays.append({"type": "circle", "pos": space_result.position, "color": Color.ORANGE})
					continue  # Try next height check
				
				# Space is clear - return the teleport position
				return teleport_pos
	
	return Vector2.ZERO

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
	if is_attacking or _attack_cooldown_timer > 0.0 or is_dashing:
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
	
