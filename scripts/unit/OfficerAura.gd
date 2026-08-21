extends Node
class_name OfficerAura

## Officer's passive buff: boosts nearby same-faction allies' health
## regen while in range. A plain Node using a periodic clear-and-reapply
## scan (same staggered-timer idiom AIBrain uses) rather than an Area3D
## tracking body_entered/body_exited -- deliberately chosen because it's
## self-healing by construction. Every tick it first undoes exactly what
## it applied last tick, then reapplies fresh based on current state, so
## an officer dying, respawning as a different class (Unit.apply_class
## frees this node, its _process simply stops), or an ally walking away
## all correct themselves automatically. No death/respawn signal wiring
## needed at all.

const TICK_INTERVAL := 0.5

@export var radius: float = 15.0
@export var regen_bonus_amount: float = 6.0

var _owner_unit: Unit
var _buffed_units: Array = []
var _timer: float = 0.0

func _ready() -> void:
	_owner_unit = get_parent() as Unit

func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK_INTERVAL
	_refresh_buffs()

func _refresh_buffs() -> void:
	for unit in _buffed_units:
		if is_instance_valid(unit) and unit.health:
			unit.health.regen_bonus -= regen_bonus_amount
	_buffed_units.clear()

	if not is_instance_valid(_owner_unit) or _owner_unit.health.is_dead:
		return

	for node in get_tree().get_nodes_in_group("units"):
		var unit: Unit = node
		if not unit or unit.health.is_dead or unit.faction_id != _owner_unit.faction_id:
			continue
		if unit.global_position.distance_to(_owner_unit.global_position) > radius:
			continue
		unit.health.regen_bonus += regen_bonus_amount
		_buffed_units.append(unit)
