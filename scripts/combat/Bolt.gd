extends Node3D
class_name Bolt

## Purely visual tracer for hitscan weapons. Damage is already applied by
## WeaponHandler's raycast before this spawns — this just sells the shot.

var _from: Vector3
var _to: Vector3
var _speed: float
var _traveled: float = 0.0
var _total_distance: float

func launch(from: Vector3, to: Vector3, speed: float) -> void:
	_from = from
	_to = to
	_speed = speed
	_total_distance = from.distance_to(to)
	global_position = from
	if _total_distance > 0.01:
		look_at(to, Vector3.UP)

func _process(delta: float) -> void:
	if _total_distance <= 0.01:
		queue_free()
		return
	_traveled += _speed * delta
	var t: float = clamp(_traveled / _total_distance, 0.0, 1.0)
	global_position = _from.lerp(_to, t)
	if t >= 1.0:
		queue_free()
