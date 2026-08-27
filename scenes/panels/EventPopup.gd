class_name EventPopup
extends PopupPanel

@onready var title_label: Label = $Margin/VBox/Title
@onready var message_label: Label = $Margin/VBox/Message
@onready var options_box: VBoxContainer = $Margin/VBox/OptionsScroll/Options

var _queue: Array[ActiveGameEvent] = []
var _current: ActiveGameEvent = null

func enqueue(event: ActiveGameEvent) -> void:
	if event == null:
		return
	_queue.append(event)
	_show_next()

func _show_next() -> void:
	if _current != null or _queue.is_empty():
		return
	_current = _queue.pop_front()
	title_label.text = ("[紧急] " if _current.interaction == GameEventDefinition.Interaction.INTERRUPT else "") + _current.title
	message_label.text = _current.message
	for child in options_box.get_children(): child.queue_free()
	if _current.interaction == GameEventDefinition.Interaction.DECISION:
		for option in _current.options:
			var button := Button.new()
			button.text = str(option.get("label", option.get("id", "")))
			button.disabled = not bool(option.get("available", true))
			if button.disabled:
				button.tooltip_text = str(option.get("locked_reason", "需要特定角色特性"))
				button.text += "（" + button.tooltip_text + "）"
			else:
				button.pressed.connect(_resolve_option.bind(str(option.get("id", ""))))
			options_box.add_child(button)
			var description := str(option.get("description", "")).strip_edges()
			if not description.is_empty():
				var description_label := Label.new()
				description_label.text = description
				description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				description_label.modulate = Color(0.76, 0.76, 0.76) if not button.disabled else Color(0.52, 0.52, 0.52)
				options_box.add_child(description_label)
	else:
		var acknowledge := Button.new()
		acknowledge.text = "知道了"
		acknowledge.pressed.connect(_acknowledge)
		options_box.add_child(acknowledge)
	popup_centered()

func _resolve_option(option_id: String) -> void:
	if _current != null:
		EventManager.resolve_decision(_current.instance_id, option_id)
	_finish_current()

func _acknowledge() -> void:
	if _current != null and _current.interaction == GameEventDefinition.Interaction.INTERRUPT:
		EventManager.resolve_interrupt(_current.instance_id)
	_finish_current()

func _finish_current() -> void:
	hide()
	_current = null
	call_deferred("_show_next")
