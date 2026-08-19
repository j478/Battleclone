extends Control
class_name HUD

@onready var health_bar: ProgressBar = $Margin/VBox/HealthRow/HealthBar
@onready var health_label: Label = $Margin/VBox/HealthRow/HealthLabel
@onready var ammo_label: Label = $Margin/VBox/AmmoLabel
@onready var ticket_a_label: Label = $Margin/VBox/TicketsRow/TicketALabel
@onready var ticket_b_label: Label = $Margin/VBox/TicketsRow/TicketBLabel
@onready var kill_feed: VBoxContainer = $KillFeedMargin/KillFeed
@onready var match_end_label: Label = $MatchEndLabel
@onready var crosshair: Control = $Crosshair

const KILL_FEED_LIFETIME := 4.0
const MAX_KILL_FEED_ENTRIES := 6

var _bound_unit: Unit

func _ready() -> void:
	EventBus.tickets_changed.connect(_on_tickets_changed)
	EventBus.unit_died.connect(_on_unit_died)
	EventBus.match_ended.connect(_on_match_ended)
	ticket_a_label.text = "Faction A: %d" % MatchState.STARTING_TICKETS
	ticket_b_label.text = "Faction B: %d" % MatchState.STARTING_TICKETS

func bind_to_unit(unit: Unit) -> void:
	if _bound_unit and is_instance_valid(_bound_unit):
		_bound_unit.health.damaged.disconnect(_on_health_changed)
		_bound_unit.health.healed.disconnect(_on_health_changed)
		_bound_unit.weapon_handler.ammo_changed.disconnect(_on_ammo_changed)
	_bound_unit = unit
	unit.health.damaged.connect(_on_health_changed)
	unit.health.healed.connect(_on_health_changed)
	unit.weapon_handler.ammo_changed.connect(_on_ammo_changed)
	_refresh_health()
	crosshair.visible = true

func _on_health_changed(_amount: float = 0.0, _instigator: Node = null) -> void:
	_refresh_health()

func _refresh_health() -> void:
	if not _bound_unit:
		return
	health_bar.max_value = _bound_unit.health.max_health
	health_bar.value = _bound_unit.health.current_health
	health_label.text = "%d / %d" % [_bound_unit.health.current_health, _bound_unit.health.max_health]

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
	if victim == _bound_unit:
		crosshair.visible = false

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
