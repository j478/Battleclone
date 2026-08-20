extends Node

## Global signal bus so unrelated systems (HUD, kill feed, AI) can react
## to gameplay events without holding direct references to each other.

signal unit_died(victim: Node, killer: Node, faction_id_victim: int, faction_id_killer: int)
signal unit_spawned(unit: Node)
signal command_post_captured(post: Node, faction_id: int)
signal command_post_contested(post: Node)
signal match_ended(winning_faction_id: int)
signal tickets_changed(faction_id: int, tickets: int)

signal interact_prompt_changed(text: String)
signal player_entered_vehicle(vehicle: Node, seat: Node)
signal player_exited_vehicle(unit: Node)
signal vehicle_destroyed(vehicle: Node, instigator: Node)
