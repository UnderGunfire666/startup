extends PanelContainer

signal origin_selected

@onready var current_label: Label = $MarginContainer/VBox/CurrentLabel
@onready var origin_list: VBoxContainer = $MarginContainer/VBox/OriginScroll/OriginList
@onready var status_label: Label = $MarginContainer/VBox/StatusLabel

func _ready() -> void:
	refresh()

func refresh() -> void:
	_clear_origin_cards()
	status_label.text = ""

	var state := GameManager.store_state
	var player := GameManager.player_state
	var current_origin := GameManager.get_origin(state.selected_origin_id)

	if current_origin == null:
		current_label.text = "当前出身：未选择"
	else:
		current_label.text = (
			"当前出身：%s ｜ 现金：¥%.0f ｜ 口碑：%.0f ｜ 压力：%.0f"
			% [
				current_origin.name,
				player.cash,
				state.reputation,
				player.stress
			]
		)

	for origin in GameManager.all_origins:
		origin_list.add_child(_build_origin_card(origin))

func _clear_origin_cards() -> void:
	for child in origin_list.get_children():
		child.queue_free()

func _build_origin_card(origin: OriginData) -> Control:
	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = origin.name
	title.add_theme_font_size_override("font_size", 18)
	card.add_child(title)

	var description := Label.new()
	description.text = origin.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(description)

	var stats := Label.new()
	stats.text = "初始资金：¥%.0f ｜ 初始口碑：%.0f ｜ 初始压力：%.0f" % [
		origin.starting_cash,
		origin.initial_reputation,
		origin.initial_stress
	]
	card.add_child(stats)

	var effect := Label.new()
	effect.text = _get_effect_text(origin)
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(effect)

	var select_button := Button.new()
	select_button.text = "选择「%s」" % origin.name

	var is_current := GameManager.store_state.selected_origin_id == origin.id
	if is_current:
		select_button.text = "当前已选择"
		select_button.disabled = true
	elif GameManager.store_state.is_open:
		select_button.text = "门店已开业，无法更换"
		select_button.disabled = true

	select_button.pressed.connect(func() -> void:
		_on_select_origin_pressed(origin.id)
	)
	card.add_child(select_button)

	card.add_child(HSeparator.new())
	return card

func _get_effect_text(origin: OriginData) -> String:
	var effects: Array[String] = []

	if origin.research_discount_rate > 0.0:
		effects.append(
			"调研与深度考察费用减免 %.0f%%"
			% (origin.research_discount_rate * 100.0)
		)

	if origin.first_opening_staff_penalty_reduction > 0.0:
		effects.append(
			"首次开业时，关键员工缺失惩罚减弱 %.0f%%"
			% (origin.first_opening_staff_penalty_reduction * 100.0)
		)

	if effects.is_empty():
		return "优势：无额外修正，拥有更充足的开局资金。"

	return "优势：" + "；".join(effects)

func _on_select_origin_pressed(origin_id: String) -> void:
	var result: Dictionary = GameManager.select_origin(origin_id)

	if not result.get("success", false):
		status_label.text = "⚠ %s" % result.get("reason", "选择出身失败")
		return

	status_label.text = "✅ %s" % result.get("reason", "出身已选择")
	refresh()
	origin_selected.emit()
