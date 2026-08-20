extends Node3D
class_name VehicleSpawner

## Self-contained vehicle pad: spawns its vehicle on _ready() and again
## respawn_delay seconds after that instance is destroyed. Parallel in
## spirit to CommandPost.gd's self-registration — ConquestMode.gd never
## needs to know vehicles exist.

@export var vehicle_scene: PackedScene
@export var vehicle_data: VehicleData
@export var faction_id: int = -1
@export var respawn_delay: float = 25.0

var _current_vehicle: Vehicle

func _ready() -> void:
	_spawn()

func _spawn() -> void:
	if not vehicle_scene or not vehicle_data:
		return
	var vehicle: Vehicle = vehicle_scene.instantiate() as Vehicle
	vehicle.faction_id = faction_id
	add_child(vehicle)
	vehicle.global_transform = global_transform
	vehicle.apply_vehicle_data(vehicle_data)
	vehicle.health.died.connect(_on_vehicle_died)
	_current_vehicle = vehicle

func _on_vehicle_died(_instigator: Node) -> void:
	await get_tree().create_timer(respawn_delay).timeout
	_spawn()
