extends Node3D
class_name Projectile

## True physics projectile for rockets/thermal detonators, where travel
## time and dodging matter. Moves manually and raycasts each physics step
## instead of relying on RigidBody CCD, which keeps behavior predictable
## at high speed.

const MAX_LIFETIME := 6.0

var _velocity: Vector3
var _weapon_data: WeaponData
var _shooter: Node
var _lifetime: float = 0.0

func launch(direction: Vector3, weapon_data: WeaponData, shooter: Node) -> void:
	_velocity = direction.normalized() * weapon_data.projectile_speed
	_weapon_data = weapon_data
	_shooter = shooter
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		queue_free()
		return

	_velocity += Vector3.DOWN * 9.8 * delta * 0.3 # slight arc, not a full ballistic sim
	var from := global_position
	var to := from + _velocity * delta

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_shooter.get_rid()] if _shooter and _shooter.has_method("get_rid") else []
	query.collision_mask = (1 << 0) | (1 << 1)
	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		_explode(result.position, result.collider)
		return

	global_position = to

func _explode(at: Vector3, direct_hit_collider: Object) -> void:
	if direct_hit_collider and direct_hit_collider.has_method("get_health"):
		var health: Health = direct_hit_collider.get_health()
		if health:
			health.apply_damage(_weapon_data.damage, _shooter)

	if _weapon_data.splash_radius > 0.0:
		var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var shape := SphereShape3D.new()
		shape.radius = _weapon_data.splash_radius
		var params := PhysicsShapeQueryParameters3D.new()
		params.shape = shape
		params.transform = Transform3D(Basis(), at)
		params.collision_mask = (1 << 1)
		var hits: Array[Dictionary] = space_state.intersect_shape(params, 16)
		for hit in hits:
			var collider: Node3D = hit.collider
			if collider == direct_hit_collider or not collider.has_method("get_health"):
				continue
			var health: Health = collider.get_health()
			if health:
				var dist: float = at.distance_to(collider.global_position)
				var falloff: float = clamp(1.0 - (dist / _weapon_data.splash_radius), 0.0, 1.0)
				health.apply_damage(_weapon_data.splash_damage * falloff, _shooter)

	queue_free()
