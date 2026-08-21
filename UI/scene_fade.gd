extends CanvasLayer

## Owns its own fade-out/level-load/cleanup sequence so it keeps running even
## if whatever triggered it (e.g. a door) is freed mid-transition — for
## example when the player and an enemy kill each other on the same frame
## while a door transition's fade is in progress, resetting the level and
## freeing the door. Without this, the door's own coroutine would be aborted
## partway through (since Godot cannot resume a suspended `await` on a freed
## node), leaving this fade stuck fully opaque forever (a permanent black
## screen).
@onready var _anim: AnimationPlayer = $Fade

## Plays "fade_out", then asks `main` to load `level` (falling back to
## changing the scene directly), then frees itself. Safe to call even if the
## node that instantiated this fade is freed before the sequence completes.
func transition_to(level: String, main: Node) -> void:
	show()
	_anim.play("fade_out")
	await _anim.animation_finished

	if is_instance_valid(main) and main.has_method("load_level"):
		main.call("load_level", level)
	else:
		var tree: SceneTree = get_tree()
		if tree:
			tree.change_scene_to_file("res://Main.tscn")
			await tree.process_frame
			var main_after: Node = tree.get_first_node_in_group("GameMain")
			if main_after and main_after.has_method("load_level"):
				main_after.call("load_level", level)

	queue_free()
