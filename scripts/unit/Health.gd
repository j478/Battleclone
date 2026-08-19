extends Node
class_name Health

## Damage/death/regen component. Attached to both the player soldier and
## AI soldiers so combat math only exists in one place.

signal damaged(amount: float, instigator: Node)
signal died(instigator: Node)
signal healed(amount: float)

@export var max_health: float = 100.0
@export var regen_per_second: float = 4.0
@export var regen_delay: float = 6.0 # seconds of no damage before regen starts, matches BF2 pacing

var current_health: float
var is_dead: bool = false

var _time_since_damage: float = 999.0

func _ready() -> void:
	current_health = max_health

func setup(new_max_health: float) -> void:
	max_health = new_max_health
	current_health = max_health
	is_dead = false

func _process(delta: float) -> void:
	if is_dead:
		return
	_time_since_damage += delta
	if _time_since_damage >= regen_delay and current_health < max_health:
		heal(regen_per_second * delta)

func apply_damage(amount: float, instigator: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	_time_since_damage = 0.0
	current_health -= amount
	damaged.emit(amount, instigator)
	if current_health <= 0.0:
		current_health = 0.0
		is_dead = true
		died.emit(instigator)

func heal(amount: float) -> void:
	if is_dead:
		return
	current_health = min(max_health, current_health + amount)
	healed.emit(amount)

func revive() -> void:
	is_dead = false
	current_health = max_health
	_time_since_damage = 999.0
