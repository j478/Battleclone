extends Resource
class_name VehicleData

@export var vehicle_name: String = "Vehicle"
@export var max_health: float = 200.0
@export var max_shield: float = 100.0
@export var shield_regen_per_second: float = 15.0
@export var shield_regen_delay: float = 4.0

@export var max_speed: float = 12.0
@export var acceleration: float = 10.0
@export var turn_rate_degrees: float = 90.0
@export var is_hover: bool = false
@export var hover_height: float = 1.5

@export var primary_weapon: WeaponData
@export var turret_weapon: WeaponData

@export var occupant_eject_damage: float = 40.0
@export var body_color: Color = Color(0.5, 0.5, 0.55)
