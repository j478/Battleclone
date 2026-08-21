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

## >0 makes a PROJECTILE bounce off whatever it hits (world or units)
## instead of exploding on contact, and detonate purely when this timer
## runs out -- a thrown grenade, not an impact weapon like the rocket
## launcher (which leaves this at 0).
@export var fuse_time: float = 0.0

## Stand-in held-weapon model, shown at the wielder's Muzzle mount and
## swapped whenever the active weapon changes (see Unit.gd). Grey-box
## sized/colored per weapon rather than a real asset, same spirit as the
## rest of this project's primitive art.
@export var model_length: float = 0.6
@export var model_width: float = 0.09
@export var model_color: Color = Color(0.15, 0.15, 0.18)
