extends Area3D
class_name CommandPost

## Conquest capture point. Tracks how many of each faction's soldiers
## are standing in the zone, moves capture_progress accordingly, and
## flips ownership at +/-1. Registers itself with MatchState so the
## ticket-bleed and win-condition logic (and, later, space-layer posts)
## all read from one shared list.

signal ownership_changed(new_owner_faction_id: int)

const CAPTURE_RATE := 0.15 # progress per second per uncontested occupant

@export var post_name: String = "Command Post"
@export var capture_radius: float = 4.0
@export var capturable: bool = true
@export var starting_owner_faction_id: int = -1 # -1 = neutral
@export var neutral_color: Color = Color(0.7, 0.7, 0.7)
@export var faction_a_color: Color = Color(0.25, 0.55, 1.0)
@export var faction_b_color: Color = Color(1.0, 0.3, 0.25)

@onready var spawn_point: Marker3D = get_node_or_null("SpawnPoint")
@onready var marker_mesh: MeshInstance3D = get_node_or_null("MarkerDisc")

var owner_faction_id: int = -1
var capture_progress: float = 0.0 # +1 = fully Faction A, -1 = fully Faction B
var is_contested: bool = false

var _occupants_by_faction: Dictionary = {}

func _ready() -> void:
	owner_faction_id = starting_owner_faction_id
	capture_progress = _progress_for_owner(owner_faction_id)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	MatchState.register_command_post(self)
	_update_marker_color()

func _exit_tree() -> void:
	MatchState.unregister_command_post(self)

func _on_body_entered(body: Node) -> void:
	if body is Unit:
		var f: int = body.faction_id
		_occupants_by_faction[f] = _occupants_by_faction.get(f, 0) + 1

func _on_body_exited(body: Node) -> void:
	if body is Unit:
		var f: int = body.faction_id
		if _occupants_by_faction.has(f):
			_occupants_by_faction[f] = max(0, _occupants_by_faction[f] - 1)

func _process(delta: float) -> void:
	if not capturable:
		return
	var a: int = _occupants_by_faction.get(GameManager.FACTION_A_ID, 0)
	var b: int = _occupants_by_faction.get(GameManager.FACTION_B_ID, 0)

	is_contested = a > 0 and b > 0
	if is_contested:
		EventBus.emit_signal("command_post_contested", self)
		return
	if a == 0 and b == 0:
		return

	var direction := 1 if a > 0 else -1
	capture_progress = clamp(capture_progress + direction * CAPTURE_RATE * delta, -1.0, 1.0)
	_update_owner()

func _update_owner() -> void:
	var new_owner := -1
	if capture_progress >= 1.0:
		new_owner = GameManager.FACTION_A_ID
	elif capture_progress <= -1.0:
		new_owner = GameManager.FACTION_B_ID
	if new_owner != -1 and new_owner != owner_faction_id:
		owner_faction_id = new_owner
		_update_marker_color()
		ownership_changed.emit(new_owner)
		EventBus.emit_signal("command_post_captured", self, new_owner)

func _update_marker_color() -> void:
	if not marker_mesh:
		return
	var color := neutral_color
	if owner_faction_id == GameManager.FACTION_A_ID:
		color = faction_a_color
	elif owner_faction_id == GameManager.FACTION_B_ID:
		color = faction_b_color
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	marker_mesh.set_surface_override_material(0, mat)

func _progress_for_owner(faction_id: int) -> float:
	if faction_id == GameManager.FACTION_A_ID:
		return 1.0
	elif faction_id == GameManager.FACTION_B_ID:
		return -1.0
	return 0.0

func get_spawn_transform() -> Transform3D:
	return spawn_point.global_transform if spawn_point else global_transform
