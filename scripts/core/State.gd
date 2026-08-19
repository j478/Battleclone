extends Node
class_name State

## Base class for a single StateMachine state. Override enter/exit/tick.
## `owner_unit` is set by whoever owns the machine (Unit.gd / AIBrain.gd)
## so states can read/mutate shared unit state without re-fetching nodes.

var state_machine: StateMachine
var owner_unit: Node

func enter() -> void:
	pass

func exit() -> void:
	pass

func tick(_delta: float) -> void:
	pass

func physics_tick(_delta: float) -> void:
	pass
