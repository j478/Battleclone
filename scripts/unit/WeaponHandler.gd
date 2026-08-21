extends Node
class_name WeaponHandler

## Owns the currently equipped WeaponData, ammo/cooldown/reload timers,
## and fires hitscan or projectile shots depending on the data. Used
## identically by the player and AI so bots and player deal damage the
## same way and hit the same collision layers.

const BOLT_SCENE := preload("res://scenes/weapons/Bolt.tscn")
const PROJECTILE_SCENE := preload("res://scenes/weapons/Projectile.tscn")

signal fired
signal ammo_changed(current: int, clip_size: int)
signal reload_started(duration: float)

@export var muzzle_path: NodePath

var weapon_data: WeaponData
var current_ammo: int = 0
var shooter: Node

var _cooldown: float = 0.0
var _reloading: bool = false
var _reload_timer: float = 0.0
var _muzzle: Node3D

func _ready() -> void:
	if muzzle_path != NodePath():
		_muzzle = get_node(muzzle_path)

## data may be null -- an unequip, used for secondary/grenade slots on
## classes that don't have one. can_fire() already guards on
## weapon_data != null, so an unequipped handler safely no-ops.
func equip(data: WeaponData, owning_shooter: Node) -> void:
	weapon_data = data
	shooter = owning_shooter
	current_ammo = data.ammo_per_clip if data else 0
	_reloading = false
	_cooldown = 0.0
	ammo_changed.emit(current_ammo, data.ammo_per_clip if data else 0)

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown -= delta
	if _reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			_finish_reload()

func can_fire() -> bool:
	return weapon_data != null and not _reloading and _cooldown <= 0.0 and current_ammo > 0

func try_fire(aim_transform: Transform3D) -> bool:
	if not can_fire():
		if weapon_data and current_ammo <= 0 and not _reloading:
			start_reload()
		return false

	_cooldown = 1.0 / weapon_data.fire_rate
	current_ammo -= 1
	ammo_changed.emit(current_ammo, weapon_data.ammo_per_clip)
	fired.emit()

	var origin: Vector3 = _muzzle.global_position if _muzzle else aim_transform.origin
	var spread_dir := _apply_spread(aim_transform.basis.z * -1.0, weapon_data.spread_degrees)

	if weapon_data.fire_mode == WeaponData.FireMode.HITSCAN:
		_fire_hitscan(origin, spread_dir)
	elif weapon_data.fire_mode == WeaponData.FireMode.HEAL:
		_fire_heal(origin, spread_dir)
	else:
		_fire_projectile(origin, spread_dir)

	if current_ammo <= 0:
		start_reload()
	return true

func start_reload() -> void:
	if _reloading or weapon_data == null or current_ammo == weapon_data.ammo_per_clip:
		return
	_reloading = true
	_reload_timer = weapon_data.reload_time
	reload_started.emit(weapon_data.reload_time)

func _finish_reload() -> void:
	_reloading = false
	current_ammo = weapon_data.ammo_per_clip
	ammo_changed.emit(current_ammo, weapon_data.ammo_per_clip)

func _apply_spread(direction: Vector3, degrees: float) -> Vector3:
	if degrees <= 0.0:
		return direction
	var rad := deg_to_rad(degrees)
	var yaw := randf_range(-rad, rad)
	var pitch := randf_range(-rad, rad)
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	return (basis * direction).normalized()

func _fire_hitscan(origin: Vector3, direction: Vector3) -> void:
	var space_state: PhysicsDirectSpaceState3D = shooter.get_world_3d().direct_space_state
	var end: Vector3 = origin + direction * weapon_data.range_meters
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [shooter.get_rid()] if shooter.has_method("get_rid") else []
	query.collision_mask = (1 << 0) | (1 << 1) # world + units
	# The muzzle sits ahead of the shooter's own body, so at close range
	# (vehicles especially -- their collision capsules run nose-to-tail)
	# the ray origin can end up already inside the target's collision
	# shape. intersect_ray() silently reports no hit for a shape the ray
	# starts inside unless told otherwise, which meant point-blank shots
	# fired dead-on simply never registered -- confirmed via a headless
	# two-fighter dogfight harness where fire_held stayed true at 4m/0deg
	# alignment but shields fully regenerated instead of dropping.
	query.hit_from_inside = true
	var result: Dictionary = space_state.intersect_ray(query)

	var hit_point := end
	if result:
		hit_point = result.position
		var collider = result.collider
		if collider and collider.has_method("get_health") and collider != shooter:
			var health: Health = collider.get_health()
			if health:
				health.apply_damage(weapon_data.damage, shooter)

	_spawn_bolt(origin, hit_point)

## Same raycast as _fire_hitscan (same mask, same shooter-exclusion), but
## heals instead of damaging -- weapon_data.damage is reused as the
## heal-per-shot amount rather than adding a new field. No faction check:
## damage already has none today (friendly fire is allowed), so healing
## an enemy is a harmless non-issue, not worth gating. Vehicles share the
## unit collision layer and already expose get_health(), so this repairs
## them too for free.
func _fire_heal(origin: Vector3, direction: Vector3) -> void:
	var space_state: PhysicsDirectSpaceState3D = shooter.get_world_3d().direct_space_state
	var end: Vector3 = origin + direction * weapon_data.range_meters
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.exclude = [shooter.get_rid()] if shooter.has_method("get_rid") else []
	query.collision_mask = (1 << 0) | (1 << 1) # world + units
	# The muzzle sits ahead of the shooter's own body, so at close range
	# (vehicles especially -- their collision capsules run nose-to-tail)
	# the ray origin can end up already inside the target's collision
	# shape. intersect_ray() silently reports no hit for a shape the ray
	# starts inside unless told otherwise, which meant point-blank shots
	# fired dead-on simply never registered -- confirmed via a headless
	# two-fighter dogfight harness where fire_held stayed true at 4m/0deg
	# alignment but shields fully regenerated instead of dropping.
	query.hit_from_inside = true
	var result: Dictionary = space_state.intersect_ray(query)

	var hit_point := end
	if result:
		hit_point = result.position
		var collider = result.collider
		if collider and collider.has_method("get_health") and collider != shooter:
			var health: Health = collider.get_health()
			if health:
				health.heal(weapon_data.damage)

	_spawn_bolt(origin, hit_point)

func _spawn_bolt(from: Vector3, to: Vector3) -> void:
	var bolt := BOLT_SCENE.instantiate()
	shooter.get_tree().current_scene.add_child(bolt)
	bolt.launch(from, to, weapon_data.tracer_speed)

func _fire_projectile(origin: Vector3, direction: Vector3) -> void:
	var proj := PROJECTILE_SCENE.instantiate()
	shooter.get_tree().current_scene.add_child(proj)
	proj.global_position = origin
	proj.launch(direction, weapon_data, shooter)
