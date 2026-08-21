extends BaseEnemy

@export var patrol_speed: float = 80.0
@export var patrol_range: float = 200.0
@export var dive_speed: float = 260.0
@export var dive_cooldown: float = 2.0
@export var max_dive_depth: float = 300.0
@export var dive_safety_margin: float = 32.0
@export var sight_range: float = 220.0
@export var stuck_time_threshold: float = 0.4
@export var stuck_distance_threshold: float = 4.0
@export var evasion_speed: float = 90.0
@export var max_return_evasions: int = 5

enum State { PATROL, DIVE, RETURN }

var state: State = State.PATROL
var _dir: int = 1
var _start_y: float = 0.0
var _left_limit: float = 0.0
var _right_limit: float = 0.0
var _dive_direction: Vector2 = Vector2.DOWN
var _dive_cooldown_timer: float = 0.0
var is_diving: bool = false

var _stuck_timer: float = 0.0
var _last_position: Vector2 = Vector2.ZERO
var _evasion_dir: int = 1
var _return_evasion_count: int = 0

@onready var player: Node2D = null

func _ready() -> void:
	super._ready()
	_start_y = global_position.y
	_left_limit = global_position.x - patrol_range * 0.5
	_right_limit = global_position.x + patrol_range * 0.5
	_last_position = global_position

	player = get_tree().get_first_node_in_group("player")

func _physics_process(delta: float) -> void:
	_update_cooldown(delta)

	match state:
		State.PATROL:
			$AnimationPlayer.play('fly')
			_patrol_update(delta)
		State.DIVE:
			_dive_update(delta)
		State.RETURN:
			_return_update(delta)

	move_and_slide()
	_handle_obstructions(delta)

	if velocity.x != 0:
		$Sprite2D.flip_h = velocity.x > 0

func _handle_obstructions(delta: float) -> void:
	# Generic stuck detection: if we're barely moving despite trying to,
	# nudge sideways to slide around whatever is blocking us so we don't
	# get permanently wedged against a platform, wall, etc.
	if state == State.PATROL:
		_stuck_timer = 0.0
		_last_position = global_position
		return

	if global_position.distance_to(_last_position) < stuck_distance_threshold:
		_stuck_timer += delta
	else:
		_stuck_timer = 0.0

	_last_position = global_position

	if _stuck_timer >= stuck_time_threshold:
		_evade_obstruction()

func _evade_obstruction() -> void:
	_stuck_timer = 0.0

	if state == State.DIVE:
		# Bail out of the dive rather than grinding against an obstacle.
		_enter_return_state()
		return

	if state == State.RETURN:
		# Slide sideways away from whatever is blocking the climb, but keep
		# trying to reach the original patrol height afterwards instead of
		# giving up on it after a single obstruction.
		if get_slide_collision_count() > 0:
			var normal := get_last_slide_collision().get_normal()
			_evasion_dir = -1 if normal.x >= 0.0 else 1
		global_position.x += _evasion_dir * evasion_speed * get_physics_process_delta_time()
		velocity = Vector2.ZERO
		_return_evasion_count += 1

		# Only give up on reaching the original patrol height after
		# repeatedly failing to climb around obstructions.
		if _return_evasion_count >= max_return_evasions:
			_start_y = global_position.y
			state = State.PATROL
			_return_evasion_count = 0

func _update_cooldown(delta: float) -> void:
	if _dive_cooldown_timer > 0.0:
		_dive_cooldown_timer -= delta

func _patrol_update(_delta: float) -> void:
	velocity.x = _dir * patrol_speed
	velocity.y = 0.0

	if global_position.x <= _left_limit:
		_dir = 1
	elif global_position.x >= _right_limit:
		_dir = -1

	_try_start_dive()

func _try_start_dive() -> void:
	if _dive_cooldown_timer > 0.0:
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return

	var to_player := player.global_position - global_position
	if abs(to_player.x) <= sight_range and to_player.y > 0.0:
		# Player is roughly below and within horizontal range
		_dive_direction = to_player.normalized()
		state = State.DIVE
		is_diving = true
		$dive.play()

func _dive_update(_delta: float) -> void:
	# Mild steering toward the player during dive (optional)
	if player != null:
		var to_player := player.global_position - global_position
		if to_player.length() > 0.0:
			var desired_dir := to_player.normalized()
			_dive_direction = _dive_direction.lerp(desired_dir, 0.05).normalized()

	velocity = _dive_direction * dive_speed

	# Compute a target dive depth that tries to reach the player height,
	# but never exceeds the configured maximum depth from the start height.
	var target_dive_y := _start_y + max_dive_depth
	if player != null:
		target_dive_y = min(player.global_position.y + dive_safety_margin, target_dive_y)

	if global_position.y >= target_dive_y:
		_enter_return_state()

func _enter_return_state() -> void:
	state = State.RETURN
	_dive_cooldown_timer = dive_cooldown
	is_diving = false
	_return_evasion_count = 0

func _return_update(_delta: float) -> void:
	# Fly back up toward the original patrol height
	var target := Vector2(global_position.x, _start_y)
	var to_target := target - global_position

	if to_target.length() < 5.0:
		global_position = target
		velocity = Vector2.ZERO
		state = State.PATROL
		_return_evasion_count = 0
	else:
		velocity = to_target.normalized() * patrol_speed

func _on_hurt_box_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return

	# Only deal damage during the dive window
	if is_diving and body.has_method("damage_player"):
		body.damage_player()
		_enter_return_state()
