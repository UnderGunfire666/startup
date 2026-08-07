extends PanelContainer

signal region_selected

@onready var current_label: Label = $MarginContainer/VBox/CurrentLabel
@onready var region_list: VBoxContainer = $MarginContainer/VBox/RegionScroll/RegionList
@onready var status_label: Label = $MarginContainer/VBox/StatusLabel


func _ready() -> void:
	refresh()


func refresh() -> void:
	_clear_region_cards()
	status_label.text = ""

	var state := GameManager.store_state
	var region := GameManager.get_region(state.selected_region_id)

	if region == null:
		current_label.text = "当前区域：未选择"
	else:
		current_label.text = "当前区域：%s" % region.name

	for r in GameManager.all_regions:
		region_list.add_child(_build_region_card(r))


func _clear_region_cards() -> void:
	for child in region_list.get_children():
		child.queue_free()


func _build_region_card(region: RegionData) -> Control:
	var state := GameManager.store_state
	var player := GameManager.player_state
	var familiarity := state.get_region_familiarity(region.id)
	var interest := state.get_region_interest(region.id)
	var is_current := state.selected_region_id == region.id

	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "%s：%s" % [region.id, region.name]
	title.add_theme_font_size_override("font_size", 18)
	card.add_child(title)

	var public_info := Label.new()
	public_info.text = "辐射人口：%d ｜ 人口密度：%s ｜ 消费能力：%s" % [
		region.radiation_population, region.population_density, region.spending_power
	]
	public_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(public_info)

	var progress_info := Label.new()
	progress_info.text = "了解程度：%.0f%%（你需要≥%.0f%%才能开店）｜兴趣程度：%.0f%%（你需要≥%.0f%%）" % [
		familiarity, player.get_required_region_familiarity(),
		interest, player.get_required_region_interest(),
	]
	progress_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(progress_info)

	if familiarity > 0.0:
		var detail_info := Label.new()
		detail_info.text = "停留性：%s ｜ 竞争强度：%s ｜ 周末客流倍率：%.1fx ｜ 主力人群：%s" % [
			region.dwell_time, region.competition_level, region.weekend_modifier,
			"、".join(region.primary_groups),
		]
		detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(detail_info)
	else:
		var locked_info := Label.new()
		locked_info.text = "停留性、竞争强度、客流细节：考察后逐步了解"
		locked_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(locked_info)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)

	var select_button := Button.new()
	if is_current:
		select_button.text = "当前已选定"
		select_button.disabled = true
	elif state.is_open:
		select_button.text = "门店已开业，无法更换"
		select_button.disabled = true
	else:
		select_button.text = "选定此区域"
		select_button.pressed.connect(func():
			var result: Dictionary = GameManager.select_region(region.id)
			status_label.text = ("✅ " if result.success else "⚠ ") + result.reason
			if result.success:
				refresh()
				region_selected.emit()
			else:
				refresh()
		)
	button_row.add_child(select_button)

	card.add_child(button_row)
	card.add_child(HSeparator.new())
	return card
