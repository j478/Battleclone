extends Node

## Top-level game state: what mode we're in, and the local player's
## chosen faction/class for the current life. Scene-loading logic
## belongs here so no scene ever hard-references another scene path.

enum GameState { BOOT, CLASS_SELECT, PLAYING, POST_MATCH }

const FACTION_A_ID := 0
const FACTION_B_ID := 1
const LOCAL_PLAYER_FACTION := FACTION_A_ID

var state: GameState = GameState.BOOT
var local_player_class: ClassData
var local_player_unit: Node = null

func request_respawn(with_class: ClassData) -> void:
	local_player_class = with_class
	EventBus.emit_signal("unit_spawned", null)
	state = GameState.PLAYING

func end_match(winning_faction_id: int) -> void:
	state = GameState.POST_MATCH
	EventBus.emit_signal("match_ended", winning_faction_id)
