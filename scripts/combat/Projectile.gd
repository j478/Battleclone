extends Node3D
class_name Projectile

## True physics projectile for rockets/thermal detonators, where travel
## time and dodging matter. Moves manually and raycasts each physics step
## instead of relying on RigidBody CCD, which keeps behavior predictable
## at high speed.
##
## A grenade (weapon_data.fuse_time > 0) bounces off whatever it hits
## instead of exploding on contact, settles into rolling once resting on
## a roughly flat surface, and detonates purely on the fuse timer --
## matching the reference game's "cook, bounce, roll, boom" instead of
## exploding the instant it touches anything (including a player it
## bounced off, which shouldn't take contact damage from that).

const MAX_LIFETIME := 6.0
const BOUNCE_RESTITUTION := 0.45 # velocity kept per bounce
const ROLL_FRICTION := 3.0 # horizontal damping once resting on the ground
const GROUNDED_NORMAL_DOT := 0.7 # how upward a surface normal must be to count as "ground"
const RESTING_SPEED_THRESHOLD := 2.0 # settle into rolling once a bounce leaves it slower than this

var _velocity: Vector3
var _weapon_data: WeaponData
var _shooter: Node
var _lifetime: float = 0.0
var _is_grenade: bool = false
var _fuse_remaining: float = 0.0
var _resting: bool = false

func launch(direction: Vector3, weapon_data: WeaponData, shooter: Node) -> void:
	_velocity = direction.normalized() * weapon_data.projectile_speed
	_weapon_data = weapon_data
	_shooter = shooter
	_is_grenade = weapon_data.fuse_time > 0.0
	_fuse_remaining = weapon_data.fuse_time
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime > MAX_LIFETIME:
		queue_free()
		return

	if _is_grenade:
		_fuse_remaining -= delta
		if _fuse_remaining <= 0.0:
			_explode(global_position, null)
			return

	if not _resting:
		# Rockets keep the original soft arc; a grenade falls at real
		# gravity so its bounce/roll actually reads as a thrown object.
		_velocity += Vector3.DOWN * 9.8 * delta * (1.0 if _is_grenade else 0.3)

	var from := global_position
	var to := from + _velocity * delta

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [_shooter.get_rid()] if _shooter and _shooter.has_method("get_rid") else []
	query.collision_mask = (1 << 0) | (1 << 1)
	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		if _is_grenade:
			_bounce(result.position, result.normal)
		else:
			_explode(result.position, result.collider)
		return

	if _resting:
		var horizontal := Vector3(_velocity.x, 0.0, _velocity.z)
		horizontal = horizontal.move_toward(Vector3.ZERO, ROLL_FRICTION * delta)
		_velocity.x = horizontal.x
		_velocity.z = horizontal.z
		global_position += _velocity * delta
	else:
		global_position = to

func _bounce(at: Vector3, normal: Vector3) -> void:
	# Nudge off the surface so the very next step doesn't immediately
	# re-intersect the same collider.
	global_position = at + normal * 0.05
	_velocity = _velocity.bounce(normal) * BOUNCE_RESTITUTION
	if normal.dot(Vector3.UP) > GROUNDED_NORMAL_DOT and _velocity.length() < RESTING_SPEED_THRESHOLD:
		_resting = true
		_velocity.y = 0.0

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
