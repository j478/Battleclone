extends Resource
class_name WeaponData

enum FireMode { HITSCAN, PROJECTILE, HEAL }

@export var weapon_name: String = "Blaster"
@export var fire_mode: FireMode = FireMode.HITSCAN
@export var damage: float = 20.0
@export var fire_rate: float = 8.0 # shots per second
@export var range_meters: float = 80.0
@export var spread_degrees: float = 1.5
@export var ammo_per_clip: int = 30
@export var reload_time: float = 1.8
@export var is_automatic: bool = true
@export var splash_radius: float = 0.0 # >0 for explosives
@export var splash_damage: float = 0.0
@export var projectile_speed: float = 25.0 # only used for PROJECTILE fire mode
@export var tracer_speed: float = 220.0 # visual-only bolt speed for HITSCAN
