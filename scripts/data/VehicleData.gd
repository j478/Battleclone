extends Resource
class_name VehicleData

enum MovementType { GROUND, HOVER, FLIGHT }

@export var vehicle_name: String = "Vehicle"
@export var max_health: float = 200.0
@export var max_shield: float = 100.0
@export var shield_regen_per_second: float = 15.0
@export var shield_regen_delay: float = 4.0

@export var max_speed: float = 12.0
@export var acceleration: float = 10.0
@export var turn_rate_degrees: float = 90.0
@export var movement_type: MovementType = MovementType.GROUND
@export var hover_height: float = 1.5

## FLIGHT only: pitch rate, soft altitude ceiling, and a purely cosmetic
## mesh-bank angle applied on turns (never fed into the actual body
## orientation -- see Vehicle.gd).
@export var pitch_rate_degrees: float = 60.0
@export var flight_ceiling: float = 70.0
@export var bank_angle_degrees: float = 35.0

@export var primary_weapon: WeaponData
@export var turret_weapon: WeaponData

@export var occupant_eject_damage: float = 40.0
@export var body_color: Color = Color(0.5, 0.5, 0.55)
