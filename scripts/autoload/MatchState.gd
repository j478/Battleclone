extends Node

## Conquest match state: tickets, command post ownership, win condition.
## Ground-only for this slice, but deliberately holds one shared ticket
## pool per faction rather than per-map — future space-layer command
## posts register into this same dictionary so ground and space count
## toward one shared win condition instead of separate matches.

const STARTING_TICKETS := 150
const BASE_BLEED_PER_SECOND := 1.0 # per point of CP disparity
const MIN_TICKETS_FOR_BLEED := 0

var tickets: Dictionary = {
	GameManager.FACTION_A_ID: STARTING_TICKETS,
	GameManager.FACTION_B_ID: STARTING_TICKETS,
}

var command_posts: Array = []
var _bleed_accumulator: float = 0.0
var _match_over: bool = false

func _ready() -> void:
	EventBus.unit_died.connect(_on_unit_died)

func register_command_post(post: Node) -> void:
	if not command_posts.has(post):
		command_posts.append(post)

func unregister_command_post(post: Node) -> void:
	command_posts.erase(post)

func _process(delta: float) -> void:
	if _match_over or command_posts.is_empty():
		return
	_bleed_accumulator += delta
	if _bleed_accumulator >= 1.0:
		_bleed_accumulator -= 1.0
		_apply_bleed_tick()

func _apply_bleed_tick() -> void:
	var owned_by: Dictionary = {GameManager.FACTION_A_ID: 0, GameManager.FACTION_B_ID: 0}
	for post in command_posts:
		if post.owner_faction_id != -1 and owned_by.has(post.owner_faction_id):
			owned_by[post.owner_faction_id] += 1

	# All posts held by one side: instant win, matches BF2's full-map-capture rule.
	var total_posts := command_posts.size()
	for faction_id in owned_by.keys():
		if owned_by[faction_id] == total_posts and total_posts > 0:
			_end_match(faction_id)
			return

	var a: int = owned_by[GameManager.FACTION_A_ID]
	var b: int = owned_by[GameManager.FACTION_B_ID]
	if a != b:
		var bleeding_faction = GameManager.FACTION_A_ID if a < b else GameManager.FACTION_B_ID
		var disparity: int = abs(a - b)
		_change_tickets(bleeding_faction, -int(BASE_BLEED_PER_SECOND * disparity))

func _on_unit_died(_victim: Node, _killer: Node, faction_id_victim: int, _faction_id_killer: int) -> void:
	_change_tickets(faction_id_victim, -1)

func _change_tickets(faction_id: int, delta: int) -> void:
	if not tickets.has(faction_id) or _match_over:
		return
	tickets[faction_id] = max(MIN_TICKETS_FOR_BLEED, tickets[faction_id] + delta)
	EventBus.emit_signal("tickets_changed", faction_id, tickets[faction_id])
	if tickets[faction_id] <= 0:
		var winner = GameManager.FACTION_B_ID if faction_id == GameManager.FACTION_A_ID else GameManager.FACTION_A_ID
		_end_match(winner)

func _end_match(winning_faction_id: int) -> void:
	if _match_over:
		return
	_match_over = true
	GameManager.end_match(winning_faction_id)
