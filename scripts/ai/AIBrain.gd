extends Node
class_name AIBrain

## Produces the same move_input/look_direction/fire_held fields
## PlayerInput does, but from a small state machine instead of the
## keyboard/mouse. Decision-making (target/CP selection, line-of-sight
## checks) is timer-staggered per bot rather than every physics frame,
## so bot count scales without spiking CPU.

enum BotState { ADVANCE, ENGAGE, CAPTURE }

const DECISION_INTERVAL_MIN := 0.35
const DECISION_INTERVAL_MAX := 0.6
const ENGAGE_RANGE := 35.0
const CAPTURE_RADIUS_SLOP := 1.5
const ARRIVE_DISTANCE := 1.0
const SPLASH_SAFETY_MARGIN := 1.3 # don't fire a splash weapon if the blast would reach us

@onready var unit: Unit = get_parent() as Unit
@onready var nav_agent: NavigationAgent3D = unit.get_node("NavigationAgent3D") as NavigationAgent3D

var _bot_state: BotState = BotState.ADVANCE
var _decision_timer: float = randf_range(0.0, DECISION_INTERVAL_MAX)
var _target_post: Node = null
var _target_enemy = null # Unit or Vehicle — duck-typed (faction_id, health, global_position)

func _ready() -> void:
	nav_agent.path_desired_distance = 0.75
	nav_agent.target_desired_distance = 1.0

func _physics_process(delta: float) -> void:
	if unit.health.is_dead:
		return

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(DECISION_INTERVAL_MIN, DECISION_INTERVAL_MAX)
		_make_decision()

	match _bot_state:
		BotState.ENGAGE:
			_tick_engage()
		_:
			_tick_navigate()

func _make_decision() -> void:
	_target_enemy = _find_visible_enemy()
	if _target_enemy:
		_bot_state = BotState.ENGAGE
		return

	_target_post = _find_capture_target()
	if _target_post:
		nav_agent.target_position = _target_post.global_position
		var dist: float = unit.global_position.distance_to(_target_post.global_position)
		var radius: float = _target_post.capture_radius if "capture_radius" in _target_post else 4.0
		_bot_state = BotState.CAPTURE if dist <= radius + CAPTURE_RADIUS_SLOP else BotState.ADVANCE
	else:
		_bot_state = BotState.ADVANCE

func _find_visible_enemy():
	var closest = null
	var closest_dist: float = ENGAGE_RANGE
	var candidates: Array = []
	candidates.append_array(unit.get_tree().get_nodes_in_group("units"))
	candidates.append_array(unit.get_tree().get_nodes_in_group("vehicles"))
	for node in candidates:
		if node == unit:
			continue
		if node.faction_id == unit.faction_id or node.health.is_dead:
			continue
		var dist: float = unit.global_position.distance_to(node.global_position)
		if dist >= closest_dist:
			continue
		if _has_line_of_sight(node):
			closest = node
			closest_dist = dist
	return closest

func _has_line_of_sight(target) -> bool:
	var from: Vector3 = unit.global_position + Vector3.UP
	var to: Vector3 = target.global_position + Vector3.UP
	var space_state: PhysicsDirectSpaceState3D = unit.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [unit.get_rid()]
	query.collision_mask = (1 << 0) | (1 << 1)
	var result: Dictionary = space_state.intersect_ray(query)
	return result.is_empty() or result.collider == target

func _find_capture_target() -> Node:
	var best: Node = null
	var best_dist: float = INF
	for post in MatchState.command_posts:
		if post.owner_faction_id == unit.faction_id:
			continue
		var dist: float = unit.global_position.distance_to(post.global_position)
		if dist < best_dist:
			best_dist = dist
			best = post
	return best

func _tick_navigate() -> void:
	if nav_agent.is_navigation_finished():
		unit.move_input = Vector2.ZERO
		return
	var next_point: Vector3 = nav_agent.get_next_path_position()
	var to_point: Vector3 = next_point - unit.global_position
	to_point.y = 0.0
	if to_point.length() < ARRIVE_DISTANCE:
		unit.move_input = Vector2.ZERO
		return
	var desired: Vector3 = to_point.normalized()
	unit.look_direction = desired
	unit.move_input = Vector2(0.0, 1.0)
	unit.fire_held = false

func _tick_engage() -> void:
	if not is_instance_valid(_target_enemy) or _target_enemy.health.is_dead:
		_bot_state = BotState.ADVANCE
		return

	var to_enemy: Vector3 = _target_enemy.global_position - unit.global_position
	var flat_to_enemy := Vector3(to_enemy.x, 0, to_enemy.z)
	unit.look_direction = to_enemy.normalized()

	var forward: Vector3 = flat_to_enemy.normalized()
	var right: Vector3 = forward.cross(Vector3.UP)
	var world_move := Vector3.ZERO
	var dist: float = flat_to_enemy.length()

	var weapon_data: WeaponData = unit.weapon_handler.weapon_data
	var blast_radius: float = weapon_data.splash_radius if weapon_data else 0.0
	var too_close_for_splash: bool = blast_radius > 0.0 and dist < blast_radius * SPLASH_SAFETY_MARGIN

	if too_close_for_splash:
		world_move = -forward # back off so our own blast doesn't catch us
	elif dist > ENGAGE_RANGE * 0.6:
		world_move = forward # close the distance a bit
	unit.move_input = Vector2(world_move.dot(right), world_move.dot(forward))
	unit.fire_held = _has_line_of_sight(_target_enemy) and not too_close_for_splash
