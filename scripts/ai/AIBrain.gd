extends Node
class_name AIBrain

## Produces the same move_input/look_direction/fire_held fields
## PlayerInput does, but from a small state machine instead of the
## keyboard/mouse. Decision-making (target/CP selection, line-of-sight
## checks) is timer-staggered per bot rather than every physics frame,
## so bot count scales without spiking CPU.
##
## Also drives vehicles: a bot can walk to, board, drive/gun, and
## dismount a vehicle using this same staggered-decision shape. It calls
## VehicleSeat.occupy()/force_exit_vehicle() directly (bypassing the
## Area3D proximity signal, which stays player-only) and writes the same
## Vehicle intent fields PlayerInput._drive_vehicle() does — this file is
## the only thing that changes to add AI vehicle usage.

enum BotState { ADVANCE, ENGAGE, CAPTURE, SEEK_VEHICLE }
enum VehicleBotState { DRIVE_TO_OBJECTIVE, ENGAGE, FLIGHT_TAKEOFF, FLIGHT_PATROL, FLIGHT_ENGAGE }

const DECISION_INTERVAL_MIN := 0.35
const DECISION_INTERVAL_MAX := 0.6
const ENGAGE_RANGE := 35.0
const CAPTURE_RADIUS_SLOP := 1.5
const ARRIVE_DISTANCE := 1.0
const SPLASH_SAFETY_MARGIN := 1.3 # don't fire a splash weapon if the blast would reach us

const VEHICLE_SEEK_MIN_OBJECTIVE_DIST := 20.0 # skip the vehicle scan entirely for close objectives
const VEHICLE_SEEK_MAX_DETOUR := 54.0 # hard cap, no long detours to reach a vehicle
const VEHICLE_SEEK_TIME_MARGIN := 0.85 # driving must be meaningfully faster, not marginally
const VEHICLE_SEAT_ARRIVE_DISTANCE := 3.0
const VEHICLE_SEEK_TIMEOUT := 10.0 # give up and go on foot if a seat can't be reached
const VEHICLE_RESERVATION_DURATION := 6.0
const VEHICLE_ENGAGE_RANGE := 55.0
const VEHICLE_DISMOUNT_RADIUS := 6.0 # dismount once this close to the objective to actually capture it
const VEHICLE_STEER_FULL_LOCK_DEG := 45.0
const VEHICLE_THROTTLE_EASE_DEG := 90.0
const VEHICLE_THROTTLE_MIN := 0.2 # keeps the vehicle pivoting toward target instead of stalling
const VEHICLE_FIRE_HEADING_TOLERANCE_DEG := 15.0 # forward-fixed weapons shouldn't fire while badly misaligned
const MAP_BOUNDARY_LIMIT := 180.0 # ground extends to ~210; steer back well before actually reaching the edge
const VEHICLE_OBSTACLE_LOOKAHEAD := 6.0

const STARFIGHTER_SEEK_MAX_DIST := 120.0 # don't detour far on foot just to try for a fighter
const FLIGHT_ENGAGE_RANGE := 120.0 # less than the cannon's range_meters -- commit before actually in range
const FLIGHT_FIRE_TOLERANCE_DEG := 20.0
const FLIGHT_STEER_FULL_LOCK_DEG := 35.0
const FLIGHT_THROTTLE_EASE_DEG := 60.0
const FLIGHT_THROTTLE_MIN := 0.35 # keep flying forward even mid-turn, never stall out
const FLIGHT_MIN_ALTITUDE := 12.0 # Vehicle.gd has no floor of its own -- AI has to self-impose one
const FLIGHT_MIN_ALTITUDE_CLIMB_TARGET := 30.0 # absolute altitude to climb toward once under the floor
const FLIGHT_PATROL_MIN_ALT := 20.0
const FLIGHT_PATROL_MAX_ALT := 55.0 # comfortably under Vehicle's flight_ceiling default of 70
const FLIGHT_PATROL_RADIUS := 240.0 # comfortably inside Vehicle's FLIGHT_BOUNDARY_RADIUS of 300
const FLIGHT_PATROL_ARRIVE_DIST := 8.0

@onready var unit: Unit = get_parent() as Unit
@onready var nav_agent: NavigationAgent3D = unit.get_node("NavigationAgent3D") as NavigationAgent3D

var _bot_state: BotState = BotState.ADVANCE
var _vehicle_state: VehicleBotState = VehicleBotState.DRIVE_TO_OBJECTIVE
var _decision_timer: float = randf_range(0.0, DECISION_INTERVAL_MAX)
var _target_post: Node = null
var _target_enemy = null # Unit or Vehicle — duck-typed (faction_id, health, global_position)

# Vehicle seeking (on foot, walking toward a reserved seat)
var _target_vehicle: Vehicle = null
var _target_seat: VehicleSeat = null
var _seek_vehicle_started_msec: int = 0

# Vehicle possession (mirrors PlayerInput's possessed_seat/possessed_vehicle)
var possessed_seat: VehicleSeat = null
var possessed_vehicle: Vehicle = null

# Flight patrol (wandering waypoint while no enemy fighter is visible)
var _flight_patrol_target: Vector3 = Vector3.ZERO

func _ready() -> void:
	nav_agent.path_desired_distance = 0.75
	nav_agent.target_desired_distance = 1.0

func _physics_process(delta: float) -> void:
	if possessed_vehicle:
		_physics_process_vehicle(delta)
		return

	if unit.health.is_dead:
		return

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(DECISION_INTERVAL_MIN, DECISION_INTERVAL_MAX)
		_make_decision()

	match _bot_state:
		BotState.ENGAGE:
			_tick_engage()
		BotState.SEEK_VEHICLE:
			_tick_seek_vehicle()
		_:
			_tick_navigate()

func _physics_process_vehicle(delta: float) -> void:
	if not is_instance_valid(possessed_vehicle) or possessed_vehicle.health.is_dead:
		return

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer = randf_range(DECISION_INTERVAL_MIN, DECISION_INTERVAL_MAX)
		if possessed_seat.seat_role == VehicleSeat.SeatRole.DRIVER:
			_make_vehicle_driver_decision()
		else:
			_make_vehicle_gunner_decision()

	if not possessed_vehicle: # a decision this tick may have dismounted us (e.g. driver left)
		return

	if possessed_seat.seat_role == VehicleSeat.SeatRole.DRIVER:
		match _vehicle_state:
			VehicleBotState.ENGAGE:
				_tick_vehicle_engage()
			VehicleBotState.FLIGHT_TAKEOFF:
				_tick_flight_takeoff()
			VehicleBotState.FLIGHT_PATROL:
				_tick_flight_patrol()
			VehicleBotState.FLIGHT_ENGAGE:
				_tick_flight_engage()
			_:
				_tick_vehicle_drive_to_objective()
	else:
		_tick_vehicle_gunner()

# ---------------------------------------------------------------------------
# Foot decision-making
# ---------------------------------------------------------------------------

func _make_decision() -> void:
	_target_enemy = _find_visible_enemy(unit.global_position, ENGAGE_RANGE)
	if _target_enemy:
		_release_vehicle_claim()
		_bot_state = BotState.ENGAGE
		return

	if _bot_state == BotState.SEEK_VEHICLE and _target_seat and is_instance_valid(_target_seat) and _target_seat.can_occupy(unit):
		return # keep pursuing the same reserved seat instead of re-rolling every decision tick

	if _maybe_seek_starfighter():
		return

	_target_post = _find_capture_target()
	if not _target_post:
		_release_vehicle_claim()
		_bot_state = BotState.ADVANCE
		return

	if _evaluate_vehicle_option():
		return

	_release_vehicle_claim()
	nav_agent.target_position = _target_post.global_position
	var dist: float = unit.global_position.distance_to(_target_post.global_position)
	var radius: float = _target_post.capture_radius if "capture_radius" in _target_post else 4.0
	_bot_state = BotState.CAPTURE if dist <= radius + CAPTURE_RADIUS_SLOP else BotState.ADVANCE

func _find_visible_enemy(origin: Vector3, max_range: float):
	var closest = null
	var closest_dist: float = max_range
	var candidates: Array = []
	candidates.append_array(unit.get_tree().get_nodes_in_group("units"))
	candidates.append_array(unit.get_tree().get_nodes_in_group("vehicles"))
	for node in candidates:
		if node == unit or node == possessed_vehicle:
			continue
		if node.faction_id == unit.faction_id or node.health.is_dead:
			continue
		var dist: float = origin.distance_to(node.global_position)
		if dist >= closest_dist:
			continue
		if _has_line_of_sight(origin, node):
			closest = node
			closest_dist = dist
	return closest

func _has_line_of_sight(origin: Vector3, target) -> bool:
	var from: Vector3 = origin + Vector3.UP
	var to: Vector3 = target.global_position + Vector3.UP
	var space_state: PhysicsDirectSpaceState3D = unit.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array = [unit.get_rid()]
	if possessed_vehicle and is_instance_valid(possessed_vehicle):
		exclude.append(possessed_vehicle.get_rid())
	query.exclude = exclude
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
	# Only bail on a genuinely degenerate (near-zero) direction, to avoid
	# NaN from normalizing a zero vector. Do NOT early-stop just because
	# the *next intermediate waypoint* is close (that used to compare
	# against ARRIVE_DISTANCE) -- a freshly computed short path can have
	# its first waypoint already within that distance of the bot's
	# current position, which permanently zeroed movement and left the
	# bot deadlocked (zero velocity forever, never close enough to
	# is_navigation_finished() to advance past it). Whether we've
	# actually arrived at the *destination* is what is_navigation_finished()
	# above already answers correctly.
	if to_point.length_squared() < 0.0001:
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
	unit.fire_held = _has_line_of_sight(unit.global_position, _target_enemy) and not too_close_for_splash

# ---------------------------------------------------------------------------
# Vehicle seeking / boarding / dismounting (foot-side)
# ---------------------------------------------------------------------------

## Opportunistic, chance-based (not scheduled/guaranteed): unlike
## _evaluate_vehicle_option, this isn't about reaching a ground objective
## faster, so it's a separate roll rather than folded into that function.
## Self-limits to about one pilot per faction since a claimed/occupied
## seat fails can_occupy/is_reserved_by_other for every other bot.
func _maybe_seek_starfighter() -> bool:
	if _bot_state == BotState.CAPTURE:
		return false # don't abandon an active capture for a joyride
	var chance: float = unit.class_data.flight_seek_chance if unit.class_data else 0.12
	if randf() > chance:
		return false
	var fighter: Vehicle = _find_available_starfighter()
	if not fighter:
		return false
	var seat: VehicleSeat = fighter.driver_seat
	if not seat or not seat.can_occupy(unit) or seat.is_reserved_by_other(self):
		return false
	if unit.global_position.distance_to(fighter.global_position) > STARFIGHTER_SEEK_MAX_DIST:
		return false
	return _try_commit_seek(fighter, seat)

func _find_available_starfighter() -> Vehicle:
	for node in unit.get_tree().get_nodes_in_group("vehicles"):
		var vehicle: Vehicle = node
		if not vehicle or vehicle.health.is_dead:
			continue
		if vehicle.faction_id != -1 and vehicle.faction_id != unit.faction_id:
			continue
		if not vehicle.vehicle_data or vehicle.vehicle_data.movement_type != VehicleData.MovementType.FLIGHT:
			continue
		return vehicle
	return null

func _evaluate_vehicle_option() -> bool:
	var objective_pos: Vector3 = _target_post.global_position
	var dist_to_objective: float = unit.global_position.distance_to(objective_pos)
	if dist_to_objective < VEHICLE_SEEK_MIN_OBJECTIVE_DIST:
		return false

	var move_speed: float = unit.class_data.move_speed if unit.class_data else 5.5
	var walk_time_direct: float = dist_to_objective / move_speed

	var best_vehicle: Vehicle = null
	var best_seat: VehicleSeat = null
	var best_detour_time: float = INF
	var best_gunner_vehicle: Vehicle = null
	var best_gunner_seat: VehicleSeat = null
	var best_gunner_dist: float = INF

	var candidates: Array = []
	candidates.append_array(unit.get_tree().get_nodes_in_group("vehicles"))
	for node in candidates:
		var vehicle: Vehicle = node
		if not vehicle or (vehicle.faction_id != -1 and vehicle.faction_id != unit.faction_id):
			continue
		if vehicle.health.is_dead:
			continue
		if vehicle.vehicle_data and vehicle.vehicle_data.movement_type == VehicleData.MovementType.FLIGHT:
			continue # AI flying is out of scope for this pass -- don't let bots block the only seat
		var dist_to_vehicle: float = unit.global_position.distance_to(vehicle.global_position)
		if dist_to_vehicle > VEHICLE_SEEK_MAX_DETOUR:
			continue

		var driver_seat: VehicleSeat = vehicle.driver_seat
		if driver_seat and driver_seat.can_occupy(unit) and not driver_seat.is_reserved_by_other(self):
			var vehicle_speed: float = vehicle.vehicle_data.max_speed if vehicle.vehicle_data else 10.0
			var detour_time: float = dist_to_vehicle / move_speed + objective_pos.distance_to(vehicle.global_position) / vehicle_speed
			if detour_time < best_detour_time:
				best_detour_time = detour_time
				best_vehicle = vehicle
				best_seat = driver_seat

		var gunner_seat: VehicleSeat = vehicle.gunner_seat
		if gunner_seat and driver_seat and driver_seat.occupant_unit and gunner_seat.can_occupy(unit) and not gunner_seat.is_reserved_by_other(self):
			if dist_to_vehicle < best_gunner_dist:
				best_gunner_dist = dist_to_vehicle
				best_gunner_vehicle = vehicle
				best_gunner_seat = gunner_seat

	if best_vehicle and best_detour_time < walk_time_direct * VEHICLE_SEEK_TIME_MARGIN:
		if _try_commit_seek(best_vehicle, best_seat):
			return true

	if best_gunner_vehicle:
		if _try_commit_seek(best_gunner_vehicle, best_gunner_seat):
			return true

	return false

func _try_commit_seek(vehicle: Vehicle, seat: VehicleSeat) -> bool:
	if not seat.reserve(self, VEHICLE_RESERVATION_DURATION):
		return false
	_target_vehicle = vehicle
	_target_seat = seat
	_seek_vehicle_started_msec = Time.get_ticks_msec()
	# Ground-flattened on purpose: hover vehicles' Y jitters slightly every
	# physics frame from their own hover-correction, and NavigationAgent3D
	# recomputes its path whenever target_position changes — feeding it a
	# jittery Y (even set only once, but especially if re-set later) risks
	# constant path thrashing that never lets the bot settle into moving.
	nav_agent.target_position = Vector3(seat.global_position.x, unit.global_position.y, seat.global_position.z)
	_bot_state = BotState.SEEK_VEHICLE
	return true

func _release_vehicle_claim() -> void:
	if _target_seat and is_instance_valid(_target_seat):
		_target_seat.release_reservation(self)
	_target_seat = null
	_target_vehicle = null

func _tick_seek_vehicle() -> void:
	if not _target_seat or not is_instance_valid(_target_seat) or not is_instance_valid(_target_vehicle):
		_release_vehicle_claim()
		_bot_state = BotState.ADVANCE
		return
	if not _target_seat.can_occupy(unit):
		_release_vehicle_claim()
		_bot_state = BotState.ADVANCE
		return
	if Time.get_ticks_msec() - _seek_vehicle_started_msec > VEHICLE_SEEK_TIMEOUT * 1000.0:
		_release_vehicle_claim()
		_bot_state = BotState.ADVANCE
		return

	var to_seat: Vector3 = _target_seat.global_position - unit.global_position
	to_seat.y = 0.0 # horizontal-only: don't let a hovering seat's height affect arrival
	var dist: float = to_seat.length()
	if dist <= VEHICLE_SEAT_ARRIVE_DISTANCE:
		_board_vehicle()
		return

	_tick_navigate()

func _board_vehicle() -> void:
	var seat: VehicleSeat = _target_seat
	var vehicle: Vehicle = _target_vehicle
	_target_seat = null
	_target_vehicle = null
	if not seat.can_occupy(unit):
		_bot_state = BotState.ADVANCE
		return
	seat.occupy(unit, self)
	possessed_seat = seat
	possessed_vehicle = vehicle
	if seat.seat_role == VehicleSeat.SeatRole.DRIVER:
		if vehicle.vehicle_data and vehicle.vehicle_data.movement_type == VehicleData.MovementType.FLIGHT:
			vehicle.begin_flight_liftoff() # the AI equivalent of the player's jump-key press
			_vehicle_state = VehicleBotState.FLIGHT_TAKEOFF
		else:
			_vehicle_state = VehicleBotState.DRIVE_TO_OBJECTIVE
	_decision_timer = 0.0

func _exit_vehicle_ai() -> void:
	var seat: VehicleSeat = possessed_seat
	if not seat:
		return
	var xform: Transform3D = seat.exit_seat()
	unit.exit_vehicle(xform)
	possessed_seat = null
	possessed_vehicle = null
	_bot_state = BotState.ADVANCE
	_decision_timer = 0.0

## Called by VehicleSeat when the vehicle is destroyed while occupied —
## the AI equivalent of PlayerInput.force_exit_vehicle().
func force_exit_vehicle(instigator: Node, eject_damage: float) -> void:
	var seat: VehicleSeat = possessed_seat
	if not seat:
		return
	var xform: Transform3D = seat.exit_seat()
	unit.exit_vehicle(xform)
	possessed_seat = null
	possessed_vehicle = null
	_bot_state = BotState.ADVANCE
	_decision_timer = 0.0
	unit.health.apply_damage(eject_damage, instigator)

# ---------------------------------------------------------------------------
# Driving
# ---------------------------------------------------------------------------

func _make_vehicle_driver_decision() -> void:
	if possessed_vehicle.vehicle_data and possessed_vehicle.vehicle_data.movement_type == VehicleData.MovementType.FLIGHT:
		_make_flight_decision()
		return

	# Stick with the current target while it's still valid instead of
	# re-scanning from scratch every decision tick: _find_visible_enemy's
	# LOS raycast is a single ray at range, and a momentary miss (terrain,
	# another vehicle, a bad angle) would otherwise drop ENGAGE for one
	# tick, drive forward, then reacquire the same enemy and stop again --
	# a rapid stop/go oscillation that looked like "inching forward" while
	# also leaving the vehicle sitting half-exposed the whole time instead
	# of committing to the fight.
	if _vehicle_state == VehicleBotState.ENGAGE and is_instance_valid(_target_enemy) and not _target_enemy.health.is_dead:
		var dist_to_target: float = possessed_vehicle.global_position.distance_to(_target_enemy.global_position)
		if dist_to_target <= VEHICLE_ENGAGE_RANGE * 1.2:
			return

	_target_enemy = _find_visible_enemy(possessed_vehicle.global_position, VEHICLE_ENGAGE_RANGE)
	if _target_enemy:
		_vehicle_state = VehicleBotState.ENGAGE
		return
	_target_post = _find_capture_target()
	_vehicle_state = VehicleBotState.DRIVE_TO_OBJECTIVE

func _tick_vehicle_drive_to_objective() -> void:
	if not _target_post or not is_instance_valid(_target_post):
		possessed_vehicle.move_input = Vector2.ZERO
		possessed_vehicle.fire_held = false
		return

	var radius: float = _target_post.capture_radius if "capture_radius" in _target_post else 4.0
	var dist: float = possessed_vehicle.global_position.distance_to(_target_post.global_position)
	if dist <= radius + VEHICLE_DISMOUNT_RADIUS:
		_exit_vehicle_ai()
		return

	possessed_vehicle.move_input = _compute_steer_throttle(possessed_vehicle, _target_post.global_position)
	possessed_vehicle.fire_held = false

func _tick_vehicle_engage() -> void:
	if not is_instance_valid(_target_enemy) or _target_enemy.health.is_dead:
		_vehicle_state = VehicleBotState.DRIVE_TO_OBJECTIVE
		return

	var vehicle: Vehicle = possessed_vehicle
	var to_enemy: Vector3 = _target_enemy.global_position - vehicle.global_position
	var dist: float = Vector2(to_enemy.x, to_enemy.z).length()

	var weapon_data: WeaponData = vehicle.weapon_handler.weapon_data
	var blast_radius: float = weapon_data.splash_radius if weapon_data else 0.0
	var too_close: bool = blast_radius > 0.0 and dist < blast_radius * SPLASH_SAFETY_MARGIN
	# No reverse/strafe in this movement model, so true kiting/circling
	# isn't achievable -- but a vehicle with no minimum range would always
	# aim for the enemy's exact position and keep closing on a moving or
	# distant target indefinitely, which is how they'd end up chasing
	# clear across the map (including toward the edges). Once already
	# within comfortable firing range, stop closing and just turn to
	# track/aim instead.
	var effective_range: float = (weapon_data.range_meters * 0.75) if weapon_data else VEHICLE_ENGAGE_RANGE
	var in_firing_range: bool = dist <= effective_range

	var heading_error: float = _heading_error(vehicle, _target_enemy.global_position)
	var aligned: bool = abs(rad_to_deg(heading_error)) <= VEHICLE_FIRE_HEADING_TOLERANCE_DEG

	if too_close:
		var target_point: Vector3 = vehicle.global_position - to_enemy.normalized() * 12.0 # back off
		vehicle.move_input = _compute_steer_throttle(vehicle, target_point)
	elif in_firing_range:
		var steer: float = clamp(-heading_error / deg_to_rad(VEHICLE_STEER_FULL_LOCK_DEG), -1.0, 1.0)
		vehicle.move_input = Vector2(steer, 0.0) # hold position, just turn to aim
	else:
		vehicle.move_input = _compute_steer_throttle(vehicle, _target_enemy.global_position)

	vehicle.fire_held = not too_close and aligned and in_firing_range and _has_line_of_sight(vehicle.global_position, _target_enemy)

# ---------------------------------------------------------------------------
# Flying (air-to-air only -- see AIBrain doc comment / plan for scope)
# ---------------------------------------------------------------------------

func _make_flight_decision() -> void:
	if possessed_vehicle.is_flight_transitioning():
		return # still climbing out; _tick_flight_takeoff() handles the transition onward

	# Same anti-oscillation fix as ground vehicles: don't re-roll a still-
	# valid target every tick, a momentary LOS miss shouldn't drop the fight.
	if _vehicle_state == VehicleBotState.FLIGHT_ENGAGE and is_instance_valid(_target_enemy) and not _target_enemy.health.is_dead:
		var dist_to_target: float = possessed_vehicle.global_position.distance_to(_target_enemy.global_position)
		if dist_to_target <= FLIGHT_ENGAGE_RANGE * 1.2:
			return

	_target_enemy = _find_visible_flight_enemy()
	_vehicle_state = VehicleBotState.FLIGHT_ENGAGE if _target_enemy else VehicleBotState.FLIGHT_PATROL

## Deliberately separate from _find_visible_enemy (which returns Units
## and Vehicles for foot/ground-vehicle combat) -- this only ever returns
## other FLIGHT-type vehicles, enforcing the air-to-air-only scope
## directly in the query instead of filtering after the fact.
func _find_visible_flight_enemy():
	var vehicle: Vehicle = possessed_vehicle
	var closest: Vehicle = null
	var closest_dist: float = FLIGHT_ENGAGE_RANGE
	for node in unit.get_tree().get_nodes_in_group("vehicles"):
		var other: Vehicle = node
		if not other or other == vehicle or other.faction_id == vehicle.faction_id or other.health.is_dead:
			continue
		if not other.vehicle_data or other.vehicle_data.movement_type != VehicleData.MovementType.FLIGHT:
			continue
		var dist: float = vehicle.global_position.distance_to(other.global_position)
		if dist >= closest_dist:
			continue
		if _has_line_of_sight(vehicle.global_position, other):
			closest = other
			closest_dist = dist
	return closest

func _tick_flight_takeoff() -> void:
	if not possessed_vehicle.is_flight_transitioning():
		_vehicle_state = VehicleBotState.FLIGHT_PATROL
		_flight_patrol_target = Vector3.ZERO # force picking a fresh waypoint next tick

func _tick_flight_patrol() -> void:
	var vehicle: Vehicle = possessed_vehicle
	if _flight_patrol_target == Vector3.ZERO or vehicle.global_position.distance_to(_flight_patrol_target) < FLIGHT_PATROL_ARRIVE_DIST:
		_flight_patrol_target = _pick_patrol_point()
	_steer_flight_toward(vehicle, _flight_patrol_target)
	vehicle.fire_held = false

func _tick_flight_engage() -> void:
	if not is_instance_valid(_target_enemy) or _target_enemy.health.is_dead:
		_vehicle_state = VehicleBotState.FLIGHT_PATROL
		return

	var vehicle: Vehicle = possessed_vehicle
	var to_target: Vector3 = _target_enemy.global_position - vehicle.global_position
	var dist: float = to_target.length()

	# Lead pursuit, not pure pursuit: steer toward where the target will
	# BE, not where it currently is. Two similarly-fast fighters both
	# always turning toward each other's *current* position never
	# actually close the distance -- it degenerates into an endless
	# tail-chase circle, since the aim point keeps sliding away at
	# roughly the same rate the pursuer closes on it. Lead time is capped
	# low (well under the full time-to-intercept) rather than fully
	# solved for intercept -- a full-solution lead at close range and low
	# separation produces a predicted point that swings wildly relative
	# to actual heading, which (confirmed live) left the nose reliably
	# pointed at empty air instead of the target even at point-blank
	# range. This is a deliberately modest correction: enough to break
	# the circle, not so much it overshoots into never lining up a shot.
	var own_speed: float = vehicle.vehicle_data.max_speed if vehicle.vehicle_data else 34.0
	var lead_time: float = clamp(dist / max(own_speed, 1.0), 0.0, 0.6)
	var predicted_pos: Vector3 = _target_enemy.global_position + _target_enemy.velocity * lead_time
	_steer_flight_toward(vehicle, predicted_pos)

	var forward: Vector3 = -vehicle.global_transform.basis.z
	var aligned: bool = dist > 0.01 and forward.dot(to_target / dist) >= cos(deg_to_rad(FLIGHT_FIRE_TOLERANCE_DEG))

	var weapon_data: WeaponData = vehicle.weapon_handler.weapon_data
	var in_range: bool = weapon_data != null and dist <= weapon_data.range_meters * 0.85

	vehicle.fire_held = aligned and in_range and _has_line_of_sight(vehicle.global_position, _target_enemy)

## Decomposes the aim problem into independent yaw and pitch errors,
## matching Vehicle._process_flight's own yaw-then-pitch composition
## (Basis(UP,yaw) * Basis(RIGHT,pitch)) exactly rather than re-deriving
## heading from the current (possibly pitched) 3D forward vector, which
## degenerates as pitch approaches vertical. Used by both patrol and
## engage. Also the one place AI has to self-impose a minimum altitude --
## Vehicle.gd already clamps the ceiling and softly contains the XZ
## boundary for everyone, but has no floor of its own.
func _steer_flight_toward(vehicle: Vehicle, target_pos: Vector3) -> void:
	var effective_target: Vector3 = target_pos
	if vehicle.global_position.y < FLIGHT_MIN_ALTITUDE:
		effective_target.y = max(effective_target.y, FLIGHT_MIN_ALTITUDE_CLIMB_TARGET)

	var to_target: Vector3 = effective_target - vehicle.global_position
	if to_target.length_squared() < 1.0:
		vehicle.flight_yaw_input = 0.0
		vehicle.flight_pitch_input = 0.0
		vehicle.flight_throttle_input = FLIGHT_THROTTLE_MIN
		return

	# desired_yaw derived directly from Vehicle's own forward formula
	# (forward = -basis.z, basis.z = Basis(UP,yaw)*(0,0,1) => forward =
	# (-sin(yaw), 0, -cos(yaw))), solved for yaw given a target direction.
	var desired_yaw: float = atan2(-to_target.x, -to_target.z)
	var yaw_error: float = wrapf(desired_yaw - vehicle.get_flight_yaw(), -PI, PI)

	var horizontal_dist: float = Vector2(to_target.x, to_target.z).length()
	var desired_pitch: float = atan2(to_target.y, horizontal_dist)
	var pitch_error: float = clamp(desired_pitch - vehicle.get_flight_pitch(), -PI, PI)

	var full_lock: float = deg_to_rad(FLIGHT_STEER_FULL_LOCK_DEG)
	# Negated, same as _compute_steer_throttle's ground-vehicle steer:
	# flight_yaw_input is subtracted from _flight_yaw, so closing a
	# positive error (need to increase _flight_yaw) needs negative input.
	vehicle.flight_yaw_input = clamp(-yaw_error / full_lock, -1.0, 1.0)
	vehicle.flight_pitch_input = clamp(pitch_error / full_lock, -1.0, 1.0)

	var total_error_deg: float = rad_to_deg(abs(yaw_error) + abs(pitch_error))
	vehicle.flight_throttle_input = clamp(1.0 - total_error_deg / FLIGHT_THROTTLE_EASE_DEG, FLIGHT_THROTTLE_MIN, 1.0)

func _pick_patrol_point() -> Vector3:
	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(20.0, FLIGHT_PATROL_RADIUS)
	var altitude: float = randf_range(FLIGHT_PATROL_MIN_ALT, FLIGHT_PATROL_MAX_ALT)
	return Vector3(cos(angle) * radius, altitude, sin(angle) * radius)

# ---------------------------------------------------------------------------
# Gunning
# ---------------------------------------------------------------------------

func _make_vehicle_gunner_decision() -> void:
	var driver_seat: VehicleSeat = possessed_vehicle.driver_seat
	if not driver_seat or not driver_seat.occupant_unit:
		_exit_vehicle_ai() # driver left, no point staying
		return
	_target_enemy = _find_visible_enemy(possessed_vehicle.global_position, VEHICLE_ENGAGE_RANGE)

func _tick_vehicle_gunner() -> void:
	var vehicle: Vehicle = possessed_vehicle
	if not is_instance_valid(_target_enemy) or _target_enemy.health.is_dead:
		vehicle.turret_fire_held = false
		return

	var turret_pivot: Node3D = vehicle.turret_pivot
	var origin: Vector3 = turret_pivot.global_position if turret_pivot else vehicle.global_position
	vehicle.turret_look_direction = (_target_enemy.global_position - origin).normalized()
	vehicle.turret_fire_held = _has_line_of_sight(origin, _target_enemy)

# ---------------------------------------------------------------------------
# Shared steering math
# ---------------------------------------------------------------------------

func _heading_error(vehicle: Vehicle, target_pos: Vector3) -> float:
	var to_target: Vector3 = target_pos - vehicle.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.0001:
		return 0.0
	var forward: Vector3 = -vehicle.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized().signed_angle_to(to_target.normalized(), Vector3.UP)

func _compute_steer_throttle(vehicle: Vehicle, target_pos: Vector3) -> Vector2:
	var pos: Vector3 = vehicle.global_position
	var effective_target: Vector3 = target_pos
	# A bad/distant target (e.g. chasing an enemy) shouldn't be able to
	# walk a vehicle off the map -- once past the safety margin, ignore
	# whatever we were actually steering toward and head back to center
	# until we're comfortably inside it again.
	if abs(pos.x) > MAP_BOUNDARY_LIMIT or abs(pos.z) > MAP_BOUNDARY_LIMIT:
		effective_target = Vector3.ZERO

	var to_target: Vector3 = effective_target - pos
	to_target.y = 0.0
	if to_target.length() < 1.0:
		return Vector2.ZERO
	var heading_error: float = _heading_error(vehicle, effective_target)
	# Negated: confirmed live that the unnegated sign steered the vehicle
	# away from its target (Vehicle._physics_process's
	# rotate_y(-move_input.x * turn_rate * delta) turns the opposite way
	# from what signed_angle_to's convention would suggest).
	var steer: float = clamp(-heading_error / deg_to_rad(VEHICLE_STEER_FULL_LOCK_DEG), -1.0, 1.0)
	var throttle: float = clamp(1.0 - abs(heading_error) / deg_to_rad(VEHICLE_THROTTLE_EASE_DEG), VEHICLE_THROTTLE_MIN, 1.0)

	var obstacle_steer_bias: float = _obstacle_steer_bias(vehicle)
	if obstacle_steer_bias != 0.0:
		steer = clamp(steer + obstacle_steer_bias, -1.0, 1.0)
		throttle *= 0.5

	return Vector2(steer, throttle)

## Short forward raycast against world geometry (crates, terrain -- not
## other units/vehicles, so it doesn't flinch away from soldiers or get
## confused avoiding the very vehicle it might be chasing) so vehicles
## swerve around obstacles directly ahead instead of just shoving into
## them via plain collision.
func _obstacle_steer_bias(vehicle: Vehicle) -> float:
	var forward: Vector3 = -vehicle.global_transform.basis.z
	var from: Vector3 = vehicle.global_position + Vector3.UP * 0.5
	var to: Vector3 = from + forward * VEHICLE_OBSTACLE_LOOKAHEAD
	var space_state: PhysicsDirectSpaceState3D = vehicle.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [vehicle.get_rid()]
	query.collision_mask = 1 # world only
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		return 0.0
	var right: Vector3 = forward.cross(Vector3.UP)
	var to_hit: Vector3 = result.position - vehicle.global_position
	return 1.0 if to_hit.dot(right) < 0.0 else -1.0
