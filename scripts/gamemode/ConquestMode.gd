extends Node3D
class_name ConquestMode

## Root script for a ground conquest map: spawns bots for both factions,
## drives the player's class-select-then-spawn flow, and respawns dead
## units (player and bots alike) at an owned command post after a delay.

const PLAYER_SOLDIER_SCENE := preload("res://scenes/units/soldier/PlayerSoldier.tscn")
const AI_SOLDIER_SCENE := preload("res://scenes/units/ai/AISoldier.tscn")

@export var bot_count_per_faction: int = 6
@export var respawn_delay: float = 5.0
@export var faction_a_data: FactionData
@export var faction_b_data: FactionData

@onready var units_root: Node3D = $UnitsRoot
@onready var hud: HUD = $UILayer/HUD
@onready var class_select: ClassSelect = $UILayer/ClassSelect
@onready var nav_region: NavigationRegion3D = $NavigationRegion3D

var player_unit: Unit

func _ready() -> void:
	if nav_region:
		nav_region.bake_navigation_mesh(false)
	EventBus.unit_died.connect(_on_unit_died)
	class_select.class_chosen.connect(_on_player_class_chosen)
	class_select.show_for_faction(GameManager.LOCAL_PLAYER_FACTION, _faction_data(GameManager.LOCAL_PLAYER_FACTION))
	_spawn_bots(GameManager.FACTION_A_ID, faction_a_data)
	_spawn_bots(GameManager.FACTION_B_ID, faction_b_data)

func _faction_data(faction_id: int) -> FactionData:
	return faction_a_data if faction_id == GameManager.FACTION_A_ID else faction_b_data

func _on_player_class_chosen(class_data: ClassData) -> void:
	if not player_unit:
		player_unit = PLAYER_SOLDIER_SCENE.instantiate() as Unit
		player_unit.faction_id = GameManager.LOCAL_PLAYER_FACTION
		units_root.add_child(player_unit)
	# Rebind every spawn, not just the first: HUD hides the crosshair on
	# death (HUD._on_unit_died) and nothing else ever shows it again --
	# without rebinding here it stayed hidden for the rest of the match
	# after the player's first death.
	hud.bind_to_unit(player_unit)
	player_unit.apply_class(class_data)
	var spawn_post: CommandPost = _pick_spawn_post(GameManager.LOCAL_PLAYER_FACTION)
	player_unit.respawn_at(_jittered_spawn_transform(spawn_post) if spawn_post else player_unit.global_transform)

func _spawn_bots(faction_id: int, faction_data: FactionData) -> void:
	if not faction_data or faction_data.available_classes.is_empty():
		return
	for i in bot_count_per_faction:
		var bot: Unit = AI_SOLDIER_SCENE.instantiate() as Unit
		bot.faction_id = faction_id
		bot.name = "AISoldier_F%d_%d" % [faction_id, i]
		units_root.add_child(bot)
		var class_data: ClassData = faction_data.available_classes.pick_random()
		var spawn_post: CommandPost = _pick_spawn_post(faction_id)
		if spawn_post:
			bot.global_transform = _jittered_spawn_transform(spawn_post)
		bot.apply_class(class_data)

func _pick_spawn_post(faction_id: int) -> CommandPost:
	var owned: Array = MatchState.command_posts.filter(func(p): return p.owner_faction_id == faction_id)
	if owned.is_empty():
		return null
	return owned.pick_random() as CommandPost

func _jittered_spawn_transform(post: CommandPost) -> Transform3D:
	var xform := post.get_spawn_transform()
	var angle := randf_range(0.0, TAU)
	var radius := randf_range(0.5, 2.5)
	xform.origin += Vector3(cos(angle), 0.0, sin(angle)) * radius
	xform = xform.rotated_local(Vector3.UP, randf_range(0.0, TAU))
	return xform

func _on_unit_died(victim: Node, _killer: Node, victim_faction: int, _killer_faction: int) -> void:
	if not is_instance_valid(victim):
		return
	await get_tree().create_timer(respawn_delay).timeout
	if not is_instance_valid(victim) or GameManager.state == GameManager.GameState.POST_MATCH:
		return

	if victim == player_unit:
		class_select.show_for_faction(GameManager.LOCAL_PLAYER_FACTION, _faction_data(GameManager.LOCAL_PLAYER_FACTION))
		return

	var faction_data: FactionData = _faction_data(victim_faction)
	if not faction_data or faction_data.available_classes.is_empty():
		return
	var class_data: ClassData = faction_data.available_classes.pick_random()
	var spawn_post: CommandPost = _pick_spawn_post(victim_faction)
	if spawn_post:
		victim.global_transform = _jittered_spawn_transform(spawn_post)
	(victim as Unit).apply_class(class_data)
	(victim as Unit).respawn_at(victim.global_transform)
