extends Resource
class_name ClassData

@export var class_name_label: String = "Trooper"
@export var max_health: float = 100.0
@export var move_speed: float = 5.5
@export var sprint_speed: float = 8.0
@export var crouch_speed: float = 2.75
@export var jump_velocity: float = 6.5
@export var primary_weapon: WeaponData
@export var secondary_weapon: WeaponData
@export var body_color: Color = Color(0.6, 0.6, 0.65)

## Per-decision-tick chance an AI bot on this class will go claim an
## unclaimed starfighter (see AIBrain._maybe_seek_starfighter). Dial-able
## per class so a future dedicated pilot class can set this much higher
## without touching AIBrain.gd.
@export_range(0.0, 1.0) var flight_seek_chance: float = 0.12
