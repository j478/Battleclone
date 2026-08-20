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

@onready var unit: Unit = get_parent() as Unit
@onready var camera_rig: CameraRig = unit.get_node("CameraRig") as CameraRig

var active_camera_rig: CameraRig
var nearby_seat: VehicleSeat
var possessed_seat: VehicleSeat
var possessed_vehicle: Vehicle

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	active_camera_rig = camera_rig

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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

func _physics_process(_delta: float) -> void:
	if possessed_seat:
		_drive_vehicle()
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

func _drive_vehicle() -> void:
	if not is_instance_valid(possessed_vehicle) or possessed_vehicle.health.is_dead:
		return
	var raw := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if possessed_seat.seat_role == VehicleSeat.SeatRole.DRIVER:
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
