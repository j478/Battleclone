extends CharacterBody3D
class_name Vehicle

## Shared vehicle logic. Custom kinematic movement (not VehicleBody3D
## wheel physics) so a legged walker, a hovering speeder, and a flying
## starfighter share one movement function, the same way Unit.gd handles
## soldier movement. Driven by VehicleSeat occupants writing intent
## fields each physics frame — the same "intent producer" pattern
## PlayerInput/AIBrain use for Unit, just with vehicle-shaped fields.

const AIR_GRAVITY := 18.0
const HOVER_CORRECTION_RATE := 8.0
const FLIGHT_PITCH_LIMIT := 1.3962634 # 80 degrees
const FLIGHT_BOUNDARY_RADIUS := 100.0 # soft push-back starts past this XZ distance from center
const FLIGHT_BOUNDARY_PUSH := 20.0
const BANK_LERP_SPEED := 6.0
const LIFTOFF_HEIGHT := 4.0 # meters climbed automatically on boarding, BFII-style
const LIFTOFF_RISE_SPEED := 5.0
const LANDING_TRIGGER_HEIGHT := 12.0 # must be within this many meters of the ground to land
const LANDING_DESCENT_SPEED := 6.0
const LANDING_REST_EPSILON := 0.15

signal landing_completed

@export var faction_id: int = -1
@export var vehicle_data: VehicleData

@onready var health: VehicleHealth = $Health
@onready var weapon_handler: WeaponHandler = $WeaponHandler
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var turret_pivot: Node3D = get_node_or_null("TurretPivot")
@onready var turret_weapon_handler: WeaponHandler = get_node_or_null("TurretPivot/TurretWeaponHandler")
@onready var hull_mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")

var display_name: String = "Vehicle"

# Driver intent (GROUND/HOVER)
var move_input: Vector2 = Vector2.ZERO # x = steer, y = throttle
var fire_held: bool = false

# Driver intent (FLIGHT only)
var flight_pitch_input: float = 0.0 # -1..1, positive = nose up
var flight_yaw_input: float = 0.0 # -1..1
var flight_throttle_input: float = 0.0 # 0..1

# Gunner intent (only meaningful if turret_pivot exists)
var turret_look_direction: Vector3 = Vector3.FORWARD
var turret_fire_held: bool = false

var driver_seat: VehicleSeat
var gunner_seat: VehicleSeat

var _flight_yaw: float = 0.0
var _flight_pitch: float = 0.0
var _flight_initialized: bool = false
var _liftoff_active: bool = false
var _liftoff_target_y: float = 0.0
var _landing_active: bool = false
var _grounded: bool = true # parked/landed vs. airborne, for the jump-key liftoff/land toggle

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

	var mode: VehicleData.MovementType = vehicle_data.movement_type if vehicle_data else VehicleData.MovementType.GROUND

	if mode == VehicleData.MovementType.FLIGHT:
		_process_flight(delta)
	else:
		var speed: float = vehicle_data.max_speed if vehicle_data else 10.0
		var accel: float = vehicle_data.acceleration if vehicle_data else 8.0
		var turn_rate: float = deg_to_rad(vehicle_data.turn_rate_degrees if vehicle_data else 90.0)

		rotate_y(-move_input.x * turn_rate * delta)

		var forward := -global_transform.basis.z
		var target_velocity := forward * move_input.y * speed

		if mode == VehicleData.MovementType.HOVER:
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

## Triggered by the player (jump, see PlayerInput) once they're ready to
## fly, not automatically on boarding -- the ship stays parked and fully
## locked (_process_parked) until they ask for this. Rising straight up
## first, ignoring attitude input for the climb, sidesteps ever pitching
## hard into the ground collider right at liftoff (nose into the pad
## especially, which move_and_slide() doesn't recover from gracefully)
## without having to patch collision response for every possible
## ground-contact angle.
func begin_flight_liftoff() -> void:
	_flight_yaw = rotation.y
	_flight_pitch = 0.0
	_flight_initialized = true
	_liftoff_active = true
	_grounded = false
	_liftoff_target_y = global_position.y + LIFTOFF_HEIGHT
	velocity = Vector3.ZERO

func is_grounded() -> bool:
	return _grounded

func is_flight_transitioning() -> bool:
	return _liftoff_active or _landing_active

func get_flight_yaw() -> float:
	return _flight_yaw

func get_flight_pitch() -> float:
	return _flight_pitch

func _process_liftoff(delta: float) -> void:
	global_transform.basis = Basis(Vector3.UP, _flight_yaw)
	velocity = Vector3.UP * LIFTOFF_RISE_SPEED
	if global_position.y >= _liftoff_target_y:
		_liftoff_active = false
		velocity = Vector3.ZERO
	if hull_mesh:
		hull_mesh.rotation.z = lerp_angle(hull_mesh.rotation.z, 0.0, BANK_LERP_SPEED * delta)

func _get_height_above_ground(max_distance: float = 200.0) -> float:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position
	var to: Vector3 = global_position + Vector3.DOWN * max_distance
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # world only
	var result: Dictionary = space_state.intersect_ray(query)
	return global_position.y - result.position.y if result else INF

func can_land() -> bool:
	return _get_height_above_ground() <= LANDING_TRIGGER_HEIGHT

## The counterpart to begin_flight_liftoff(): a controlled, input-ignoring
## descent to whatever's directly below. Bound to a separate key from
## seat-exit (see PlayerInput) so landing near the ground and bailing
## out mid-air can never be confused for each other. The player stays
## seated once landed -- jump takes off again, interact hops out.
func begin_flight_landing() -> void:
	_liftoff_active = false
	_landing_active = true

func _process_landing(delta: float) -> void:
	_flight_pitch = move_toward(_flight_pitch, 0.0, deg_to_rad(90.0) * delta)
	global_transform.basis = Basis(Vector3.UP, _flight_yaw) * Basis(Vector3.RIGHT, _flight_pitch)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var from: Vector3 = global_position + Vector3.UP * 0.5
	var to: Vector3 = global_position + Vector3.DOWN * 50.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	query.collision_mask = 1 # world only
	var result: Dictionary = space_state.intersect_ray(query)
	var rest_y: float = result.position.y if result else global_position.y

	if global_position.y - rest_y > LANDING_REST_EPSILON:
		velocity = Vector3.DOWN * LANDING_DESCENT_SPEED
	else:
		global_position.y = rest_y
		velocity = Vector3.ZERO
		_landing_active = false
		_grounded = true
		landing_completed.emit()

	if hull_mesh:
		hull_mesh.rotation.z = lerp_angle(hull_mesh.rotation.z, 0.0, BANK_LERP_SPEED * delta)

## While grounded (parked on a pad, or freshly landed), attitude and
## throttle input are completely ignored -- the ship sits dead still and
## dead level until begin_flight_liftoff() explicitly takes it airborne
## again. Without this gate, a human at the stick could pitch/yaw/throttle
## a grounded ship exactly like it was already flying, which is exactly
## the "tail end lifts into the air while wedged against the ground"
## problem liftoff/landing exist to prevent -- and it also let the ship
## fly off under its own power without ever going through
## begin_flight_liftoff(), leaving is_grounded() lying about reality and
## breaking the jump-key liftoff/land toggle.
func _process_parked(delta: float) -> void:
	global_transform.basis = Basis(Vector3.UP, _flight_yaw)
	velocity = Vector3.ZERO
	if hull_mesh:
		hull_mesh.rotation.z = lerp_angle(hull_mesh.rotation.z, 0.0, BANK_LERP_SPEED * delta)

## Rebuilds the hull's basis fresh every frame from two persistent,
## independently-clamped scalars rather than stacking rotate_y()/
## rotate_object_local() calls -- incremental local-axis rotation drifts
## over many frames, this doesn't. Roll is cosmetic only (mesh bank),
## never fed into the body's actual orientation, since the weapon fires
## dead-ahead along the hull and doesn't need true 3-axis attitude.
func _process_flight(delta: float) -> void:
	if not _flight_initialized:
		_flight_yaw = rotation.y
		_flight_pitch = 0.0
		_flight_initialized = true

	if _liftoff_active:
		_process_liftoff(delta)
		return

	if _landing_active:
		_process_landing(delta)
		return

	if _grounded:
		_process_parked(delta)
		return

	var yaw_rate: float = deg_to_rad(vehicle_data.turn_rate_degrees if vehicle_data else 90.0)
	var pitch_rate: float = deg_to_rad(vehicle_data.pitch_rate_degrees if vehicle_data else 60.0)

	_flight_yaw -= flight_yaw_input * yaw_rate * delta
	_flight_pitch = clamp(_flight_pitch + flight_pitch_input * pitch_rate * delta, -FLIGHT_PITCH_LIMIT, FLIGHT_PITCH_LIMIT)
	global_transform.basis = Basis(Vector3.UP, _flight_yaw) * Basis(Vector3.RIGHT, _flight_pitch)

	var speed: float = vehicle_data.max_speed if vehicle_data else 10.0
	var accel: float = vehicle_data.acceleration if vehicle_data else 8.0
	var forward := -global_transform.basis.z
	var target_velocity := forward * flight_throttle_input * speed
	velocity = velocity.move_toward(target_velocity, accel * delta)

	var ceiling: float = vehicle_data.flight_ceiling if vehicle_data else 70.0
	if global_position.y >= ceiling and velocity.y > 0.0:
		velocity.y = 0.0

	var horizontal_pos := Vector3(global_position.x, 0.0, global_position.z)
	var dist_from_center: float = horizontal_pos.length()
	if dist_from_center > FLIGHT_BOUNDARY_RADIUS:
		var inward: Vector3 = -horizontal_pos.normalized()
		velocity.x += inward.x * FLIGHT_BOUNDARY_PUSH * delta
		velocity.z += inward.z * FLIGHT_BOUNDARY_PUSH * delta

	if hull_mesh:
		var bank_angle: float = vehicle_data.bank_angle_degrees if vehicle_data else 35.0
		var bank_target: float = -flight_yaw_input * deg_to_rad(bank_angle)
		hull_mesh.rotation.z = lerp_angle(hull_mesh.rotation.z, bank_target, BANK_LERP_SPEED * delta)

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
