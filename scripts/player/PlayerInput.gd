extends Node
class_name PlayerInput

## Reads the human player's input and writes it into the shared Unit
## fields each frame. This is the only script in the project that reads
## the Input map directly — AIBrain.gd produces the exact same fields
## from its own decision logic, so swapping this out is all networked
## multiplayer would need later.
##
## Also owns vehicle possession: entering/exiting swaps which node's
## intent fields this script writes into (Unit vs. Vehicle) and which
## CameraRig it forwards mouse look to, without either Unit.gd or
## Vehicle.gd needing to know input exists.

const FLIGHT_STICK_SENSITIVITY := 0.006
const FLIGHT_STICK_RECENTER_RATE := 2.5 # per second, move_toward back to centered
const FLIGHT_THROTTLE_RATE := 0.6 # per second, held lever -- retains value on release

@onready var unit: Unit = get_parent() as Unit
@onready var camera_rig: CameraRig = unit.get_node("CameraRig") as CameraRig

var active_camera_rig: CameraRig
var nearby_seat: VehicleSeat
var possessed_seat: VehicleSeat
var possessed_vehicle: Vehicle

## Spring-centered virtual stick for flight pitch/yaw. Accumulated from
## mouse motion and recentered every physics tick -- a raw-delta scheme
## would stop turning the instant the mouse stops moving, which is wrong
## for something that should hold a bank while the mouse sits off-center.
var _flight_stick: Vector2 = Vector2.ZERO
var _flight_throttle: float = 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	active_camera_rig = camera_rig

func _is_flying() -> bool:
	return possessed_seat and possessed_seat.seat_role == VehicleSeat.SeatRole.DRIVER \
		and possessed_vehicle and possessed_vehicle.vehicle_data \
		and possessed_vehicle.vehicle_data.movement_type == VehicleData.MovementType.FLIGHT

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _is_flying():
			_flight_stick.x = clamp(_flight_stick.x + event.relative.x * FLIGHT_STICK_SENSITIVITY, -1.0, 1.0)
			_flight_stick.y = clamp(_flight_stick.y - event.relative.y * FLIGHT_STICK_SENSITIVITY, -1.0, 1.0)
		else:
			active_camera_rig.apply_mouse_delta(event.relative)
	elif event.is_action_pressed("toggle_camera"):
		active_camera_rig.toggle_first_person()
	elif event.is_action_pressed("interact"):
		if possessed_seat:
			_exit_vehicle()
		elif nearby_seat:
			_enter_vehicle(nearby_seat)
	elif event.is_action_pressed("pause"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if possessed_seat:
		_drive_vehicle(delta)
		return

	if unit.health.is_dead:
		return

	var raw := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	unit.move_input = raw
	unit.look_direction = camera_rig.get_look_direction()
	unit.sprint_held = Input.is_action_pressed("sprint")
	unit.crouch_held = Input.is_action_pressed("crouch")
	unit.fire_held = Input.is_action_pressed("fire")
	unit.reload_pressed = Input.is_action_just_pressed("reload")
	if Input.is_action_just_pressed("jump"):
		unit.jump_pressed = true

	var aiming := Input.is_action_pressed("aim")
	camera_rig.set_aiming(aiming)

func _drive_vehicle(delta: float) -> void:
	if not is_instance_valid(possessed_vehicle) or possessed_vehicle.health.is_dead:
		return
	if possessed_seat.seat_role == VehicleSeat.SeatRole.DRIVER:
		if _is_flying():
			_flight_stick = _flight_stick.move_toward(Vector2.ZERO, FLIGHT_STICK_RECENTER_RATE * delta)
			possessed_vehicle.flight_yaw_input = _flight_stick.x
			possessed_vehicle.flight_pitch_input = _flight_stick.y
			if Input.is_action_pressed("move_forward"):
				_flight_throttle = clamp(_flight_throttle + FLIGHT_THROTTLE_RATE * delta, 0.0, 1.0)
			elif Input.is_action_pressed("move_back"):
				_flight_throttle = clamp(_flight_throttle - FLIGHT_THROTTLE_RATE * delta, 0.0, 1.0)
			possessed_vehicle.flight_throttle_input = _flight_throttle
			possessed_vehicle.fire_held = Input.is_action_pressed("fire")
		else:
			var raw := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
			possessed_vehicle.move_input = raw
			possessed_vehicle.fire_held = Input.is_action_pressed("fire")
	else:
		possessed_vehicle.turret_look_direction = active_camera_rig.get_look_direction()
		possessed_vehicle.turret_fire_held = Input.is_action_pressed("fire")

func _enter_vehicle(seat: VehicleSeat) -> void:
	if not seat.can_occupy(unit):
		return
	seat.occupy(unit, self)
	possessed_seat = seat
	possessed_vehicle = seat.vehicle
	nearby_seat = null
	_flight_stick = Vector2.ZERO
	_flight_throttle = 0.0
	if seat.camera_rig:
		active_camera_rig = seat.camera_rig
		active_camera_rig.activate()
	EventBus.emit_signal("interact_prompt_changed", "")
	EventBus.emit_signal("player_entered_vehicle", possessed_vehicle, possessed_seat)

func _exit_vehicle() -> void:
	var seat := possessed_seat
	var xform: Transform3D = seat.exit_seat()
	unit.exit_vehicle(xform)
	_clear_possession()
	EventBus.emit_signal("player_exited_vehicle", unit)

## Called by VehicleSeat when the vehicle is destroyed while occupied.
func force_exit_vehicle(instigator: Node, eject_damage: float) -> void:
	var seat := possessed_seat
	if not seat:
		return
	var xform: Transform3D = seat.exit_seat()
	unit.exit_vehicle(xform)
	_clear_possession()
	unit.health.apply_damage(eject_damage, instigator)
	EventBus.emit_signal("player_exited_vehicle", unit)

func _clear_possession() -> void:
	possessed_seat = null
	possessed_vehicle = null
	active_camera_rig = camera_rig
	active_camera_rig.activate()
