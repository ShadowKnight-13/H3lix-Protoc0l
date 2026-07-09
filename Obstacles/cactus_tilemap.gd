extends TileMapLayer

## Deals damage to the player when they touch cactus tiles.
##
## Attach this script to any TileMapLayer that represents cactus hazard tiles.
## It polls every physics frame (respecting [member hurt_cooldown]) and calls
## [method Player.damage_player] when the player's collision shape overlaps a tile.

## Seconds the player must wait between consecutive damage hits from this tilemap.
@export var hurt_cooldown: float = 0.5

var _hurt_timer: float = 0.0

func _physics_process(delta: float) -> void:
	_hurt_timer = max(0.0, _hurt_timer - delta)
	if _hurt_timer > 0.0:
		return

	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player == null:
		return

	if _player_overlaps_cactus(player):
		if player.has_method("damage_player"):
			player.call("damage_player")
			_hurt_timer = hurt_cooldown

## Returns true if the player's CollisionShape2D overlaps any tile in this TileMapLayer.
func _player_overlaps_cactus(player: Node2D) -> bool:
	var cs := player.get_node_or_null("CollisionShape2D") as CollisionShape2D
	if cs == null or cs.shape == null:
		return false

	var space_state := get_world_2d().direct_space_state
	var qp := PhysicsShapeQueryParameters2D.new()
	qp.shape = cs.shape
	# Use the collision shape's full world transform so crouching/scaling is handled correctly.
	qp.transform = cs.global_transform
	# Check all layers; we filter by collider identity below so any TileSet layer config works.
	qp.collision_mask = 0xFFFFFFFF
	qp.exclude = [player]

	var hits := space_state.intersect_shape(qp, 8)
	for hit in hits:
		if hit.get("collider") == self:
			return true
	return false
