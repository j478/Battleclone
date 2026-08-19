extends Node
class_name StateMachine

## Generic finite state machine. Child nodes are States (extend State.gd);
## the child's `name` is used as its state key. Used by both the player
## movement controller and the AI brain so the two systems share one pattern.

@export var initial_state: NodePath

var current_state: State
var states: Dictionary = {}

func _ready() -> void:
	for child in get_children():
		if child is State:
			states[child.name] = child
			child.state_machine = self
	if initial_state != NodePath():
		var start := get_node(initial_state) as State
		_change(start)
	elif get_child_count() > 0:
		_change(get_child(0) as State)

func _process(delta: float) -> void:
	if current_state:
		current_state.tick(delta)

func _physics_process(delta: float) -> void:
	if current_state:
		current_state.physics_tick(delta)

func transition_to(state_name: String) -> void:
	if not states.has(state_name):
		push_warning("StateMachine: unknown state '%s'" % state_name)
		return
	_change(states[state_name])

func _change(next: State) -> void:
	if current_state == next:
		return
	if current_state:
		current_state.exit()
	current_state = next
	if current_state:
		current_state.enter()
