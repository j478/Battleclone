extends CharacterBody3D
class_name Vehicle

## Shared vehicle logic. Custom kinematic movement (not VehicleBody3D
## wheel physics) so a legged walker and a hovering speeder share one
## movement function, the same way Unit.gd handles soldier movement.
## Driven by VehicleSeat occupants writing intent fields each physics
## frame — the same "intent producer" pattern PlayerInput/AIBrain use
## for Unit, just with vehicle-shaped fields (steer/throttle instead of
## strafe/forward).

const AIR_GRAVITY := 18.0
const HOVER_CORRECTION_RATE := 8.0

@export var faction_id: int = -1
@export var vehicle_data: VehicleData

@onready var health: VehicleHealth = $Health
@onready var weapon_handler: WeaponHandler = $WeaponHandler
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var turret_pivot: Node3D = get_node_or_null("TurretPivot")
@onready var turret_weapon_handler: WeaponHandler = get_node_or_null("TurretPivot/TurretWeaponHandler")

var display_name: String = "Vehicle"

# Driver intent
var move_input: Vector2 = Vector2.ZERO # x = steer, y = throttle
var fire_held: bool = false

# Gunner intent (only meaningful if turret_pivot exists)
var turret_look_direction: Vector3 = Vector3.FORWARD
var turret_fire_held: bool = false

var driver_seat: VehicleSeat
var gunner_seat: VehicleSeat

func _ready() -> void:
	add_to_group("vehicles")
	for child in get_children():
		if child is VehicleSeat:
			if child.seat_role == VehicleSeat.SeatRole.DRIVER:
				driver_seat = child
			else:
				gunner_seat = child
	if vehicle_data:
		apply_vehicle_data(vehicle_data)
	health.died.connect(_on_died)

func apply_vehicle_data(data: VehicleData) -> void:
	vehicle_data = data
	display_name = data.vehicle_name
	health.setup(data.max_health)
	health.configure_shield(data.max_shield, data.shield_regen_per_second, data.shield_regen_delay)
	weapon_handler.equip(data.primary_weapon, self)
	if turret_weapon_handler and data.turret_weapon:
		turret_weapon_handler.equip(data.turret_weapon, self)
	var mesh := get_node_or_null("MeshInstance3D")
	if mesh and mesh.get_surface_override_material_count() > 0:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data.body_color
		mesh.set_surface_override_material(0, mat)

func get_health() -> Health:
	return health

const FALL_DEATH_Y := -20.0 # safety net: driving off the map edge shouldn't fall forever

func _physics_process(delta: float) -> void:
	if health.is_dead:
		return

	if global_position.y < FALL_DEATH_Y:
		health.apply_damage(health.max_health + health.max_shield, null)
		return

	var speed: float = vehicle_data.max_speed if vehicle_data else 10.0
	var accel: float = vehicle_data.acceleration if vehicle_data else 8.0
	var turn_rate: float = deg_to_rad(vehicle_data.turn_rate_degrees if vehicle_data else 90.0)

	rotate_y(-move_input.x * turn_rate * delta)

	var forward := -global_transform.basis.z
	var target_velocity := forward * move_input.y * speed

	if vehicle_data and vehicle_data.is_hover:
		_process_hover(delta, target_velocity)
	else:
		_process_grounded(delta, target_velocity, accel)

	move_and_slide()

	if turret_pivot:
		turret_pivot.look_at(turret_pivot.global_position + turret_look_direction, Vector3.UP)
		if turret_fire_held and turret_weapon_handler:
			turret_weapon_handler.try_fire(turret_pivot.global_transform)

	if fire_held:
		weapon_handler.try_fire(global_transform)

func _process_grounded(delta: float, target_velocity: Vector3, accel: float) -> void:
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_horizontal := Vector3(target_velocity.x, 0.0, target_velocity.z)
	horizontal = horizontal.move_toward(target_horizontal, accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	if is_on_floor():
		velocity.y = 0.0
	else:
		velocity.y -= AIR_GRAVITY * delta

func _process_hover(delta: float, target_velocity: Vector3) -> void:
	velocity.x = target_velocity.x
	velocity.z = target_velocity.z
	var hover_target: float = vehicle_data.hover_height if vehicle_data else 1.5

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 0.5
	var to: Vector3 = global_position + Vector3.DOWN * (hover_target + 4.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # world only
	var result: Dictionary = space_state.intersect_ray(query)

	if result:
		var target_y: float = result.position.y + hover_target
		velocity.y = (target_y - global_position.y) * HOVER_CORRECTION_RATE
	else:
		velocity.y -= AIR_GRAVITY * delta

func _on_died(instigator: Node) -> void:
	EventBus.emit_signal("vehicle_destroyed", self, instigator)
	var eject_damage: float = vehicle_data.occupant_eject_damage if vehicle_data else 40.0
	for seat in [driver_seat, gunner_seat]:
		if seat and seat.occupant_unit:
			seat.force_exit_vehicle(instigator, eject_damage)
	set_physics_process(false)
	visible = false
	collision_shape.disabled = true
	await get_tree().create_timer(1.5).timeout
	queue_free()
