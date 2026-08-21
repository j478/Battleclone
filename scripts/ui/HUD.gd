extends Control
class_name HUD

@onready var health_bar: ProgressBar = $Margin/VBox/HealthRow/HealthBar
@onready var health_label: Label = $Margin/VBox/HealthRow/HealthLabel
@onready var shield_row: HBoxContainer = $Margin/VBox/ShieldRow
@onready var shield_bar: ProgressBar = $Margin/VBox/ShieldRow/ShieldBar
@onready var shield_label: Label = $Margin/VBox/ShieldRow/ShieldLabel
@onready var ammo_label: Label = $Margin/VBox/AmmoLabel
@onready var grenade_label: Label = $Margin/VBox/GrenadeLabel
@onready var ticket_a_label: Label = $Margin/VBox/TicketsRow/TicketALabel
@onready var ticket_b_label: Label = $Margin/VBox/TicketsRow/TicketBLabel
@onready var kill_feed: VBoxContainer = $KillFeedMargin/KillFeed
@onready var match_end_label: Label = $MatchEndLabel
@onready var crosshair: Control = $Crosshair
@onready var interact_prompt: Label = $InteractPrompt

const KILL_FEED_LIFETIME := 4.0
const MAX_KILL_FEED_ENTRIES := 6

var _bound_health: Health
var _bound_weapon_handler: WeaponHandler
var _bound_grenade_handler: WeaponHandler
var _bound_unit: Unit
var _bound_target: Node # whichever Unit/Vehicle is currently bound
var _bound_vehicle: Vehicle
var _bound_seat_role: int = -1 # VehicleSeat.SeatRole, or -1 when not driving
var _kill_feed_entries: Array = [] # [{label: Label, expires_at_msec: int}]

func _ready() -> void:
	EventBus.tickets_changed.connect(_on_tickets_changed)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.vehicle_destroyed.connect(_on_vehicle_destroyed)
	EventBus.match_ended.connect(_on_match_ended)
	EventBus.interact_prompt_changed.connect(_on_interact_prompt_changed)
	EventBus.player_entered_vehicle.connect(_on_player_entered_vehicle)
	EventBus.player_exited_vehicle.connect(_on_player_exited_vehicle)
	ticket_a_label.text = "Faction A: %d" % MatchState.STARTING_TICKETS
	ticket_b_label.text = "Faction B: %d" % MatchState.STARTING_TICKETS
	shield_row.visible = false
	interact_prompt.visible = false

func bind_to_unit(unit: Unit) -> void:
	_bind_health(unit.health)
	_bind_ammo(unit.weapon_handler)
	_bind_grenade_ammo(unit.grenade_handler)
	_bind_weapon_switch_signal(unit)
	_bound_target = unit
	_bound_vehicle = null
	_bound_seat_role = -1
	crosshair.visible = true

func bind_to_vehicle(vehicle: Vehicle, seat: VehicleSeat) -> void:
	_bind_health(vehicle.health)
	var is_gunner: bool = seat.seat_role == VehicleSeat.SeatRole.GUNNER
	var wh: WeaponHandler = vehicle.turret_weapon_handler if is_gunner and vehicle.turret_weapon_handler else vehicle.weapon_handler
	_bind_ammo(wh)
	_bind_grenade_ammo(null) # vehicles don't have grenades
	_bind_weapon_switch_signal(null)
	_bound_target = vehicle
	_bound_vehicle = vehicle
	_bound_seat_role = seat.seat_role
	crosshair.visible = true

## A ground/hover driver's weapon fires along the vehicle's heading, not
## camera look direction (steering a chassis and aiming a camera don't
## mix), so a screen-centered crosshair would lie about where shots go.
## Project the vehicle's actual forward direction into view instead, and
## fade it out when that direction isn't even on screen. A FLIGHT
## driver's mouse steers the hull itself (see PlayerInput._is_flying),
## so camera look and heading never diverge there -- same as the
## gunner's turret, it keeps the normal centered crosshair.
func _process(_delta: float) -> void:
	_update_kill_feed_expiry()

	if not crosshair.visible:
		return
	var is_steered_driver: bool = _bound_vehicle and is_instance_valid(_bound_vehicle) \
		and _bound_seat_role == VehicleSeat.SeatRole.DRIVER \
		and _bound_vehicle.vehicle_data \
		and _bound_vehicle.vehicle_data.movement_type != VehicleData.MovementType.FLIGHT
	if is_steered_driver:
		_update_driver_crosshair()
	else:
		crosshair.modulate.a = 1.0
		crosshair.position = get_viewport_rect().size / 2.0 - crosshair.size / 2.0

func _update_driver_crosshair() -> void:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		crosshair.modulate.a = 0.0
		return

	var forward: Vector3 = -_bound_vehicle.global_transform.basis.z
	var aim_point: Vector3 = _bound_vehicle.global_position + forward * 20.0
	var to_point: Vector3 = aim_point - cam.global_position
	if to_point.dot(-cam.global_transform.basis.z) <= 0.1:
		crosshair.modulate.a = 0.0 # vehicle heading is behind/beside the camera
		return

	var screen_pos: Vector2 = cam.unproject_position(aim_point)
	var viewport_size: Vector2 = get_viewport_rect().size
	if screen_pos.x < 0.0 or screen_pos.x > viewport_size.x or screen_pos.y < 0.0 or screen_pos.y > viewport_size.y:
		crosshair.modulate.a = 0.0 # off-screen
		return

	crosshair.modulate.a = 1.0
	crosshair.position = screen_pos - crosshair.size / 2.0

func _bind_health(health: Health) -> void:
	if _bound_health and is_instance_valid(_bound_health):
		_bound_health.damaged.disconnect(_on_health_changed)
		_bound_health.healed.disconnect(_on_health_changed)
		if _bound_health is VehicleHealth:
			_bound_health.shield_changed.disconnect(_on_shield_changed)
	_bound_health = health
	health.damaged.connect(_on_health_changed)
	health.healed.connect(_on_health_changed)
	if health is VehicleHealth:
		health.shield_changed.connect(_on_shield_changed)
		shield_row.visible = true
		_on_shield_changed(health.current_shield, health.max_shield)
	else:
		shield_row.visible = false
	_refresh_health()

func _bind_ammo(weapon_handler: WeaponHandler) -> void:
	if _bound_weapon_handler and is_instance_valid(_bound_weapon_handler):
		_bound_weapon_handler.ammo_changed.disconnect(_on_ammo_changed)
	_bound_weapon_handler = weapon_handler
	weapon_handler.ammo_changed.connect(_on_ammo_changed)
	if weapon_handler.weapon_data:
		_on_ammo_changed(weapon_handler.current_ammo, weapon_handler.weapon_data.ammo_per_clip)

## Separate from the main ammo binding above -- the grenade slot is
## always-available (never the "active" weapon), so it gets its own
## small display rather than sharing/overwriting the main ammo label.
func _bind_grenade_ammo(handler: WeaponHandler) -> void:
	if _bound_grenade_handler and is_instance_valid(_bound_grenade_handler):
		_bound_grenade_handler.ammo_changed.disconnect(_on_grenade_ammo_changed)
	_bound_grenade_handler = handler
	if handler:
		handler.ammo_changed.connect(_on_grenade_ammo_changed)
	grenade_label.visible = handler != null and handler.weapon_data != null
	if handler and handler.weapon_data:
		_on_grenade_ammo_changed(handler.current_ammo, handler.weapon_data.ammo_per_clip)

## Unit.weapon_switched fires whenever Q swaps the active slot, so the
## ammo readout follows whichever weapon is actually live -- same
## disconnect/reconnect rebind pattern as _bind_health/_bind_ammo above.
func _bind_weapon_switch_signal(unit: Unit) -> void:
	if _bound_unit and is_instance_valid(_bound_unit):
		_bound_unit.weapon_switched.disconnect(_on_weapon_switched)
	_bound_unit = unit
	if unit:
		unit.weapon_switched.connect(_on_weapon_switched)

func _on_weapon_switched(handler: WeaponHandler) -> void:
	_bind_ammo(handler)

func _on_health_changed(_amount: float = 0.0, _instigator: Node = null) -> void:
	_refresh_health()

func _refresh_health() -> void:
	if not _bound_health:
		return
	health_bar.max_value = _bound_health.max_health
	health_bar.value = _bound_health.current_health
	health_label.text = "%d / %d" % [_bound_health.current_health, _bound_health.max_health]

func _on_shield_changed(current: float, max_shield: float) -> void:
	shield_bar.max_value = max_shield
	shield_bar.value = current
	shield_label.text = "%d / %d" % [current, max_shield]

func _on_ammo_changed(current: int, clip_size: int) -> void:
	ammo_label.text = "%d / %d" % [current, clip_size]

func _on_grenade_ammo_changed(current: int, clip_size: int) -> void:
	# bind_to_unit runs before apply_class() actually equips anything, so
	# the initial _bind_grenade_ammo() call can't yet know visibility --
	# this signal (fired by every equip()/try_fire()/reload) is the
	# reliable place to decide it instead. clip_size is 0 only when
	# equip() was called with a null WeaponData (no throwable for this
	# class), so it doubles as an equipped/unequipped signal.
	grenade_label.visible = clip_size > 0
	grenade_label.text = "Grenades: %d / %d" % [current, clip_size]

func _on_tickets_changed(faction_id: int, tickets: int) -> void:
	if faction_id == GameManager.FACTION_A_ID:
		ticket_a_label.text = "Faction A: %d" % tickets
	else:
		ticket_b_label.text = "Faction B: %d" % tickets

func _on_unit_died(victim: Node, killer: Node, _victim_faction: int, _killer_faction: int) -> void:
	var victim_name: String = _display_name_of(victim)
	var killer_name: String = _display_name_of(killer) if killer and killer != victim else "the environment"
	_push_kill_feed("%s eliminated %s" % [killer_name, victim_name])
	if victim == _bound_target:
		crosshair.visible = false

func _on_vehicle_destroyed(vehicle: Node, instigator: Node) -> void:
	var vehicle_name: String = _display_name_of(vehicle)
	var killer_name: String = _display_name_of(instigator) if instigator else "the environment"
	_push_kill_feed("%s destroyed a %s" % [killer_name, vehicle_name])
	if vehicle == _bound_target:
		crosshair.visible = false

func _on_interact_prompt_changed(text: String) -> void:
	interact_prompt.text = text
	interact_prompt.visible = text != ""

func _on_player_entered_vehicle(vehicle: Node, seat: Node) -> void:
	bind_to_vehicle(vehicle, seat)

func _on_player_exited_vehicle(unit: Node) -> void:
	bind_to_unit(unit)

func _display_name_of(unit: Node) -> String:
	if not unit:
		return "Someone"
	if "display_name" in unit:
		return unit.display_name
	return unit.name

## Tracks its own entries and expires them from _process instead of a
## per-entry SceneTreeTimer+lambda: that pattern raced against the
## count-based eviction below (an evicted label could still have a
## pending timer holding a now-freed reference, which errors when
## Godot tries to invoke the callable with a freed captured Object).
func _push_kill_feed(text: String) -> void:
	var label := Label.new()
	label.text = text
	kill_feed.add_child(label)
	_kill_feed_entries.append({"label": label, "expires_at_msec": Time.get_ticks_msec() + int(KILL_FEED_LIFETIME * 1000.0)})
	# queue_free() doesn't reduce get_child_count() until end of frame, so
	# this must be "if", not "while" -- a while here spins forever the
	# instant eviction is needed, since the count never drops within this
	# call. Only one entry is ever added per call, so one eviction is
	# always enough.
	if kill_feed.get_child_count() > MAX_KILL_FEED_ENTRIES:
		var oldest: Node = kill_feed.get_child(0)
		oldest.queue_free()
		var kept: Array = []
		for entry in _kill_feed_entries:
			if entry["label"] != oldest:
				kept.append(entry)
		_kill_feed_entries = kept

func _update_kill_feed_expiry() -> void:
	if _kill_feed_entries.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var remaining: Array = []
	for entry in _kill_feed_entries:
		var label: Label = entry["label"]
		if not is_instance_valid(label):
			continue
		if now >= entry["expires_at_msec"]:
			label.queue_free()
		else:
			remaining.append(entry)
	_kill_feed_entries = remaining

func _on_match_ended(winning_faction_id: int) -> void:
	var name := "Faction A" if winning_faction_id == GameManager.FACTION_A_ID else "Faction B"
	match_end_label.text = "%s wins!" % name
	match_end_label.visible = true
