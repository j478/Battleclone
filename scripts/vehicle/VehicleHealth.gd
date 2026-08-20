extends Health
class_name VehicleHealth

## Health component for vehicles: adds a regenerating shield layer in
## front of the inherited Health/apply_damage/died behavior. Shield
## absorbs damage first and regenerates after a no-damage delay; once
## it's depleted, damage flows through to the normal Health pipeline
## unchanged (same signals, same death handling).

signal shield_changed(current: float, max: float)

var max_shield: float = 0.0
var current_shield: float = 0.0
var shield_regen_per_second: float = 0.0
var shield_regen_delay: float = 4.0

var _time_since_shield_damage: float = 999.0

func configure_shield(new_max_shield: float, regen_per_second: float, regen_delay: float) -> void:
	max_shield = new_max_shield
	current_shield = new_max_shield
	shield_regen_per_second = regen_per_second
	shield_regen_delay = regen_delay
	shield_changed.emit(current_shield, max_shield)

func setup(new_max_health: float) -> void:
	super.setup(new_max_health)
	current_shield = max_shield
	_time_since_shield_damage = 999.0
	shield_changed.emit(current_shield, max_shield)

func _process(delta: float) -> void:
	super._process(delta)
	if is_dead:
		return
	_time_since_shield_damage += delta
	if _time_since_shield_damage >= shield_regen_delay and current_shield < max_shield:
		current_shield = min(max_shield, current_shield + shield_regen_per_second * delta)
		shield_changed.emit(current_shield, max_shield)

func apply_damage(amount: float, instigator: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	_time_since_shield_damage = 0.0
	var remaining: float = amount
	if current_shield > 0.0:
		var absorbed: float = min(current_shield, remaining)
		current_shield -= absorbed
		remaining -= absorbed
		shield_changed.emit(current_shield, max_shield)
	if remaining > 0.0:
		super.apply_damage(remaining, instigator)

func revive() -> void:
	super.revive()
	current_shield = max_shield
	_time_since_shield_damage = 999.0
	shield_changed.emit(current_shield, max_shield)
