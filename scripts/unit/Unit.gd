extends CharacterBody3D
class_name Unit

## Shared soldier logic for both the human player and AI bots. Whoever
## drives this unit (PlayerInput or AIBrain) just writes into the public
## `move_input` / `look_direction` / `*_held` fields each frame — the
## movement, aiming, and firing code below is identical either way, so
## bots and the player behave under the exact same rules.

const AIR_CONTROL := 0.35

@export var faction_id: int = 0
@export var class_data: ClassData
var display_name: String = "Soldier"

@onready var health: Health = $Health
@onready var weapon_handler: WeaponHandler = $WeaponHandler
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var aim_pivot: Node3D = $AimPivot

var move_input: Vector2 = Vector2.ZERO # x = strafe, y = forward
var look_direction: Vector3 = Vector3.FORWARD
var sprint_held: bool = false
var crouch_held: bool = false
var jump_pressed: bool = false
var fire_held: bool = false
var reload_pressed: bool = false

var is_crouching: bool = false
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)
var _standing_height: float

func _ready() -> void:
	add_to_group("units")
	if class_data:
		apply_class(class_data)
	health.died.connect(_on_died)
	if collision_shape and collision_shape.shape is CapsuleShape3D:
		_standing_height = collision_shape.shape.height

func apply_class(data: ClassData) -> void:
	class_data = data
	display_name = "%s (%s)" % [data.class_name_label, "A" if faction_id == GameManager.FACTION_A_ID else "B"]
	health.setup(data.max_health)
	weapon_handler.equip(data.primary_weapon, self)
	var mesh := get_node_or_null("MeshInstance3D")
	if mesh and mesh.get_surface_override_material_count() > 0:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data.body_color
		mesh.set_surface_override_material(0, mat)

func get_health() -> Health:
	return health

func _physics_process(delta: float) -> void:
	if health.is_dead:
		return

	if aim_pivot:
		aim_pivot.look_at(aim_pivot.global_position + look_direction, Vector3.UP)

	var target_speed: float = class_data.move_speed if class_data else 5.5
	if crouch_held:
		is_crouching = true
		target_speed = class_data.crouch_speed if class_data else 2.75
	else:
		is_crouching = false
		if sprint_held and move_input.y > 0.1:
			target_speed = class_data.sprint_speed if class_data else 8.0

	_update_crouch_shape()

	var forward := Vector3(look_direction.x, 0, look_direction.z).normalized()
	var right := forward.cross(Vector3.UP)
	var wish_dir := (forward * move_input.y + right * move_input.x)
	if wish_dir.length_squared() > 1.0:
		wish_dir = wish_dir.normalized()

	if is_on_floor():
		velocity.x = wish_dir.x * target_speed
		velocity.z = wish_dir.z * target_speed
		if jump_pressed:
			velocity.y = class_data.jump_velocity if class_data else 6.5
	else:
		velocity.x = lerp(velocity.x, wish_dir.x * target_speed, AIR_CONTROL)
		velocity.z = lerp(velocity.z, wish_dir.z * target_speed, AIR_CONTROL)
		velocity.y -= _gravity * delta

	jump_pressed = false
	move_and_slide()

	if fire_held:
		weapon_handler.try_fire(aim_pivot.global_transform if aim_pivot else global_transform)
	if reload_pressed:
		weapon_handler.start_reload()
		reload_pressed = false

func _update_crouch_shape() -> void:
	if not collision_shape or not (collision_shape.shape is CapsuleShape3D):
		return
	var capsule := collision_shape.shape as CapsuleShape3D
	var target_height: float = _standing_height * 0.6 if is_crouching else _standing_height
	capsule.height = lerp(capsule.height, target_height, 0.2)
	collision_shape.position.y = capsule.height * 0.5

func _on_died(instigator: Node) -> void:
	EventBus.emit_signal("unit_died", self, instigator, faction_id, _faction_of(instigator))
	set_physics_process(false)
	visible = false
	collision_shape.disabled = true

func _faction_of(node: Node) -> int:
	if node and "faction_id" in node:
		return node.faction_id
	return -1

func respawn_at(spawn_transform: Transform3D) -> void:
	global_transform = spawn_transform
	velocity = Vector3.ZERO
	health.revive()
	if class_data:
		weapon_handler.equip(class_data.primary_weapon, self)
	visible = true
	collision_shape.disabled = false
	set_physics_process(true)
