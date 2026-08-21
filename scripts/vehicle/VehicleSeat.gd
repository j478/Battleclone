extends Area3D
class_name VehicleSeat

## Vehicle entry trigger + occupancy bookkeeping, mirroring how
## CommandPost.gd detects occupants via Area3D body_entered/exited.
## Possession/camera-swap logic itself lives in PlayerInput (it already
## owns all Input-map reads); this node just tracks who's nearby, who's
## seated, and exposes the seat's own CameraRig/ExitPoint.

enum SeatRole { DRIVER, GUNNER }

signal occupied(seat: VehicleSeat)
signal vacated(seat: VehicleSeat)

@export var seat_role: SeatRole = SeatRole.DRIVER
@export var seat_label: String = "driver"

@onready var camera_rig: CameraRig = get_node_or_null("CameraRig")
@onready var exit_point: Marker3D = get_node_or_null("ExitPoint")

var vehicle: Vehicle
var occupant_unit: Unit
var occupant_player_input: Node

## Soft claim so multiple AI bots don't all converge on one empty seat.
## Auto-expires so a bot that dies or gets distracted mid-walk doesn't
## permanently lock a seat other bots can see is empty. A human player
## can still walk up and take a reserved seat regardless.
var reserved_by: Node = null
var _reservation_expires_msec: int = 0

var _nearby_player_input: Node

func _ready() -> void:
	vehicle = get_parent() as Vehicle
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if occupant_unit or not (body is Unit):
		return
	var player_input := body.get_node_or_null("PlayerInput")
	if not player_input:
		return
	_nearby_player_input = player_input
	player_input.nearby_seat = self
	EventBus.emit_signal("interact_prompt_changed", "Press F to board as %s" % seat_label)

func _on_body_exited(body: Node) -> void:
	if _nearby_player_input and is_instance_valid(_nearby_player_input) and body == _nearby_player_input.unit:
		if _nearby_player_input.nearby_seat == self:
			_nearby_player_input.nearby_seat = null
			EventBus.emit_signal("interact_prompt_changed", "")
		_nearby_player_input = null

func can_occupy(unit: Unit) -> bool:
	return occupant_unit == null and (vehicle.faction_id == -1 or unit.faction_id == vehicle.faction_id)

func reserve(claimant: Node, duration_seconds: float) -> bool:
	if occupant_unit != null or is_reserved_by_other(claimant):
		return false
	reserved_by = claimant
	_reservation_expires_msec = Time.get_ticks_msec() + int(duration_seconds * 1000.0)
	return true

func release_reservation(claimant: Node) -> void:
	if reserved_by == claimant:
		reserved_by = null

func is_reserved_by_other(claimant: Node) -> bool:
	if reserved_by == null or not is_instance_valid(reserved_by) or reserved_by == claimant:
		return false
	return Time.get_ticks_msec() < _reservation_expires_msec

func occupy(unit: Unit, player_input: Node) -> void:
	reserved_by = null
	occupant_unit = unit
	occupant_player_input = player_input
	unit.enter_vehicle()
	occupied.emit(self)

func exit_seat() -> Transform3D:
	var xform: Transform3D = exit_point.global_transform if exit_point else global_transform
	occupant_unit = null
	occupant_player_input = null
	# Nothing else ever clears Vehicle's intent fields -- without this, a
	# vehicle just keeps driving/firing at whatever its last command was
	# forever once abandoned, since its own _physics_process doesn't know
	# or care whether anyone is still steering it. This is the one
	# chokepoint every dismount path (player/AI, voluntary/forced) already
	# routes through.
	if vehicle:
		if seat_role == SeatRole.DRIVER:
			vehicle.move_input = Vector2.ZERO
			vehicle.fire_held = false
		else:
			vehicle.turret_fire_held = false
	vacated.emit(self)
	return xform

func force_exit_vehicle(instigator: Node, eject_damage: float) -> void:
	if occupant_player_input and is_instance_valid(occupant_player_input):
		occupant_player_input.force_exit_vehicle(instigator, eject_damage)
