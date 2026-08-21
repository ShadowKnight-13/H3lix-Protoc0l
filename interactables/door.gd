extends StaticBody2D

@onready var interactable: Area2D = $interactable
@onready var anim_player: AnimationPlayer = $"Door Animator/AnimationPlayer"

@export_file("*.tscn") var level: String = ""
@export var door_open_animation: StringName = &"open"
@export var door_fallback_wait_seconds: float = 0.25

const SceneFadeScene: PackedScene = preload("res://UI/scene_fade.tscn")

var _is_transitioning: bool = false

func _ready() -> void:
	interactable.interacted.connect(_on_interact)

func _on_interact() -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	if level == "":
		push_warning("Door has no target_scene_path set")
		_is_transitioning = false
		return

	# 1) Door opens while this node is still in the tree.
	if anim_player and anim_player.has_animation(door_open_animation):
		anim_player.play(door_open_animation)
		await anim_player.animation_finished
	else:
		await get_tree().create_timer(door_fallback_wait_seconds).timeout

	# 2) Fade out (new instance each time — avoids duplicate parenting).
	# The fade owns its own fade-out/load/cleanup coroutine (see scene_fade.gd)
	# so the transition finishes correctly even if this door is freed in the
	# meantime — e.g. the player and an enemy killing each other on the same
	# frame resets the level (and this door with it) while the fade is still
	# playing. Awaiting that chain here would otherwise leave the fade stuck
	# fully opaque forever (a permanent black screen) once this node is gone.
	var fade: CanvasLayer = SceneFadeScene.instantiate()
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(fade)

	var main: Node = get_tree().get_first_node_in_group("GameMain")
	fade.call("transition_to", level, main)

	_is_transitioning = false
