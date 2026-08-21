extends Area3D
class_name CommandPost

## Conquest capture point. Tracks how many of each faction's soldiers
## are standing in the zone, moves capture_progress accordingly, and
## flips ownership at +/-1. Registers itself with MatchState so the
## ticket-bleed and win-condition logic (and, later, space-layer posts)
## all read from one shared list.

signal ownership_changed(new_owner_faction_id: int)

const CAPTURE_RATE := 0.15 # progress per second per uncontested occupant
const CAPTURE_BAR_MAX_HEIGHT := 3.0
const CAPTURE_BAR_BASE_Y := 0.11

@export var post_name: String = "Command Post"
@export var capture_radius: float = 4.0
@export var capturable: bool = true
@export var starting_owner_faction_id: int = -1 # -1 = neutral
@export var neutral_color: Color = Color(0.7, 0.7, 0.7)
@export var faction_a_color: Color = Color(0.25, 0.55, 1.0)
@export var faction_b_color: Color = Color(1.0, 0.3, 0.25)

@onready var spawn_point: Marker3D = get_node_or_null("SpawnPoint")
@onready var marker_mesh: MeshInstance3D = get_node_or_null("MarkerDisc")
@onready var capture_bar: MeshInstance3D = get_node_or_null("CaptureBar")

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
	# CommandPost.tscn pre-assigns a BoxMesh to CaptureBar so it has a
	# sane shape in the editor -- but every instance of the scene shares
	# that exact same Resource object unless given its own copy here, so
	# without this every post's bar would resize/reposition in lockstep
	# with whichever post last wrote to the shared mesh (looked like bars
	# floating mid-air or growing the wrong way, since each post's own
	# position offset was computed for ITS progress but the rendered mesh
	# size belonged to whichever post updated last).
	if capture_bar:
		capture_bar.mesh = BoxMesh.new()
	_update_capture_visuals()

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
	_update_capture_visuals()

func _update_owner() -> void:
	var new_owner := -1
	if capture_progress >= 1.0:
		new_owner = GameManager.FACTION_A_ID
	elif capture_progress <= -1.0:
		new_owner = GameManager.FACTION_B_ID
	if new_owner != -1 and new_owner != owner_faction_id:
		owner_faction_id = new_owner
		ownership_changed.emit(new_owner)
		EventBus.emit_signal("command_post_captured", self, new_owner)

## Both the disc's color and the capture-bar's fill height track
## capture_progress continuously (not just the discrete owner flip), so
## a post visibly trends toward whichever faction is capturing it well
## before it actually flips -- previously the disc only changed color
## the instant ownership changed, giving no sense of "how close."
func _update_capture_visuals() -> void:
	_update_marker_color()
	_update_capture_bar()

func _update_marker_color() -> void:
	if not marker_mesh:
		return
	var color: Color = neutral_color.lerp(faction_a_color, capture_progress) if capture_progress >= 0.0 \
		else neutral_color.lerp(faction_b_color, -capture_progress)
	var mat := marker_mesh.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 1.5
		marker_mesh.set_surface_override_material(0, mat)
	mat.albedo_color = color
	mat.emission = color

func _update_capture_bar() -> void:
	if not capture_bar:
		return
	var fill: float = abs(capture_progress)
	var box := capture_bar.mesh as BoxMesh
	if not box:
		box = BoxMesh.new()
		capture_bar.mesh = box
	box.size = Vector3(0.4, max(fill * CAPTURE_BAR_MAX_HEIGHT, 0.02), 0.4)
	capture_bar.position.y = CAPTURE_BAR_BASE_Y + box.size.y / 2.0
	var mat := capture_bar.get_surface_override_material(0) as StandardMaterial3D
	if not mat:
		mat = StandardMaterial3D.new()
		mat.emission_enabled = true
		mat.emission_energy_multiplier = 1.5
		capture_bar.set_surface_override_material(0, mat)
	var color: Color = faction_a_color if capture_progress >= 0.0 else faction_b_color
	mat.albedo_color = color
	mat.emission = color

func _progress_for_owner(faction_id: int) -> float:
	if faction_id == GameManager.FACTION_A_ID:
		return 1.0
	elif faction_id == GameManager.FACTION_B_ID:
		return -1.0
	return 0.0

func get_spawn_transform() -> Transform3D:
	return spawn_point.global_transform if spawn_point else global_transform
