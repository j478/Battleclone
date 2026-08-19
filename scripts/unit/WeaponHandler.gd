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

func equip(data: WeaponData, owning_shooter: Node) -> void:
	weapon_data = data
	shooter = owning_shooter
	current_ammo = data.ammo_per_clip
	_reloading = false
	_cooldown = 0.0
	ammo_changed.emit(current_ammo, weapon_data.ammo_per_clip)

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

func _spawn_bolt(from: Vector3, to: Vector3) -> void:
	var bolt := BOLT_SCENE.instantiate()
	shooter.get_tree().current_scene.add_child(bolt)
	bolt.launch(from, to, weapon_data.tracer_speed)

func _fire_projectile(origin: Vector3, direction: Vector3) -> void:
	var proj := PROJECTILE_SCENE.instantiate()
	shooter.get_tree().current_scene.add_child(proj)
	proj.global_position = origin
	proj.launch(direction, weapon_data, shooter)
