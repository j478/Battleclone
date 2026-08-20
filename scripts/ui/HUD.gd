extends Control
class_name HUD

@onready var health_bar: ProgressBar = $Margin/VBox/HealthRow/HealthBar
@onready var health_label: Label = $Margin/VBox/HealthRow/HealthLabel
@onready var shield_row: HBoxContainer = $Margin/VBox/ShieldRow
@onready var shield_bar: ProgressBar = $Margin/VBox/ShieldRow/ShieldBar
@onready var shield_label: Label = $Margin/VBox/ShieldRow/ShieldLabel
@onready var ammo_label: Label = $Margin/VBox/AmmoLabel
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
var _bound_target: Node # whichever Unit/Vehicle is currently bound

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
	_bound_target = unit
	crosshair.visible = true

func bind_to_vehicle(vehicle: Vehicle, seat: VehicleSeat) -> void:
	_bind_health(vehicle.health)
	var is_gunner: bool = seat.seat_role == VehicleSeat.SeatRole.GUNNER
	var wh: WeaponHandler = vehicle.turret_weapon_handler if is_gunner and vehicle.turret_weapon_handler else vehicle.weapon_handler
	_bind_ammo(wh)
	_bound_target = vehicle
	crosshair.visible = true

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

func _push_kill_feed(text: String) -> void:
	var label := Label.new()
	label.text = text
	kill_feed.add_child(label)
	if kill_feed.get_child_count() > MAX_KILL_FEED_ENTRIES:
		kill_feed.get_child(0).queue_free()
	get_tree().create_timer(KILL_FEED_LIFETIME).timeout.connect(func():
		if is_instance_valid(label):
			label.queue_free()
	)

func _on_match_ended(winning_faction_id: int) -> void:
	var name := "Faction A" if winning_faction_id == GameManager.FACTION_A_ID else "Faction B"
	match_end_label.text = "%s wins!" % name
	match_end_label.visible = true
