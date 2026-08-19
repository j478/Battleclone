extends Node3D
class_name CameraRig

## Owns mouse-look (yaw here, pitch on the child Pivot) and the
## first/third-person camera toggle. PlayerInput just forwards mouse
## delta and the toggle key here, then reads get_look_direction().

const MOUSE_SENSITIVITY := 0.0025
const PITCH_MIN := deg_to_rad(-80.0)
const PITCH_MAX := deg_to_rad(80.0)
const DEFAULT_FOV := 75.0
const ADS_FOV := 55.0
const FOV_LERP_SPEED := 10.0

@onready var pivot: Node3D = $Pivot
@onready var spring_arm: SpringArm3D = $Pivot/SpringArm3D
@onready var tps_camera: Camera3D = $Pivot/SpringArm3D/TPSCamera
@onready var fps_camera: Camera3D = $Pivot/FPSCamera

var is_first_person: bool = false
var aiming: bool = false
var _pitch: float = 0.0

func _ready() -> void:
	_set_active_camera()

func apply_mouse_delta(delta: Vector2) -> void:
	rotate_y(-delta.x * MOUSE_SENSITIVITY)
	_pitch = clamp(_pitch - delta.y * MOUSE_SENSITIVITY, PITCH_MIN, PITCH_MAX)
	pivot.rotation.x = _pitch

func toggle_first_person() -> void:
	is_first_person = not is_first_person
	_set_active_camera()

func set_aiming(value: bool) -> void:
	aiming = value

func _process(delta: float) -> void:
	var cam := get_active_camera()
	if cam:
		var target_fov := ADS_FOV if aiming else DEFAULT_FOV
		cam.fov = lerp(cam.fov, target_fov, FOV_LERP_SPEED * delta)

func _set_active_camera() -> void:
	tps_camera.current = not is_first_person
	fps_camera.current = is_first_person
	spring_arm.visible = not is_first_person

func get_active_camera() -> Camera3D:
	return fps_camera if is_first_person else tps_camera

func get_look_direction() -> Vector3:
	return -pivot.global_transform.basis.z
