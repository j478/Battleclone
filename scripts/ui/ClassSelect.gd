extends Control
class_name ClassSelect

signal class_chosen(class_data: ClassData)

@onready var title_label: Label = $Panel/VBox/Title
@onready var button_container: VBoxContainer = $Panel/VBox/Buttons

func show_for_faction(faction_id: int, faction_data: FactionData) -> void:
	title_label.text = "Choose your class — %s" % faction_data.faction_name
	for child in button_container.get_children():
		child.queue_free()
	for class_data in faction_data.available_classes:
		var button := Button.new()
		button.text = class_data.class_name_label
		button.pressed.connect(func(): _select(class_data))
		button_container.add_child(button)
	visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false

func _select(class_data: ClassData) -> void:
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	class_chosen.emit(class_data)
