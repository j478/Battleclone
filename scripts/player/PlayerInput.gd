extends Node
class_name PlayerInput

## Reads the human player's input and writes it into the shared Unit
## fields each frame. This is the only script in the project that reads
## the Input map directly — AIBrain.gd produces the exact same fields
## from its own decision logic, so swapping this out is all networked
## multiplayer would need later.

@onready var unit: Unit = get_parent() as Unit
@onready var camera_rig: CameraRig = unit.get_node("CameraRig") as CameraRig

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera_rig.apply_mouse_delta(event.relative)
	elif event.is_action_pressed("toggle_camera"):
		camera_rig.toggle_first_person()
	elif event.is_action_pressed("pause"):
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if captured else Input.MOUSE_MODE_CAPTURED

func _physics_process(_delta: float) -> void:
	if unit.health.is_dead:
		return

	var raw := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	unit.move_input = raw
	unit.look_direction = camera_rig.get_look_direction()
	unit.sprint_held = Input.is_action_pressed("sprint")
	unit.crouch_held = Input.is_action_pressed("crouch")
	unit.fire_held = Input.is_action_pressed("fire")
	unit.reload_pressed = Input.is_action_just_pressed("reload")
	if Input.is_action_just_pressed("jump"):
		unit.jump_pressed = true

	var aiming := Input.is_action_pressed("aim")
	camera_rig.set_aiming(aiming)
