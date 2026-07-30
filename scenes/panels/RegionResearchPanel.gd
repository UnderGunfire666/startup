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
	var is_researched := region.id in state.researched_region_ids
	var is_current := state.selected_region_id == region.id

	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "%s：%s" % [region.id, region.name]
	title.add_theme_font_size_override("font_size", 18)
	card.add_child(title)

	var public_info := Label.new()
	public_info.text = (
		"辐射人口：%d ｜ 人口密度：%s ｜ 消费能力：%s"
		% [region.radiation_population, region.population_density, region.spending_power]
	)
	public_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(public_info)

	var transport_info := Label.new()
	transport_info.text = "客流来源：%s ｜ 租金基准：%s" % [
		_join_or_dash(region.traffic_sources),
		region.rent_baseline
	]
	transport_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(transport_info)

	if is_researched:
		var research_info := Label.new()
		research_info.text = (
			"停留性：%s ｜ 竞争强度：%s ｜ 周末客流倍率：%.1fx"
			% [region.dwell_time, region.competition_level, region.weekend_modifier]
		)
		research_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(research_info)

		var groups_info := Label.new()
		groups_info.text = "主力人群：%s ｜ 次要人群：%s" % [
			_join_or_dash(region.primary_groups),
			_join_or_dash(region.secondary_groups)
		]
		groups_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(groups_info)

		if region.notes != "":
			var notes_info := Label.new()
			notes_info.text = "备注：%s" % region.notes
			notes_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			card.add_child(notes_info)
	else:
		var locked_info := Label.new()
		locked_info.text = "停留性、竞争强度、周末客流倍率、人群构成：调研后解锁"
		locked_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(locked_info)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 10)

	var research_button := Button.new()
	if is_researched:
		research_button.text = "已调研"
		research_button.disabled = true
	else:
		var discounted_cost := _get_discounted_cost(region)
		research_button.text = "调研此区域（¥%.0f）" % discounted_cost
		research_button.pressed.connect(func() -> void:
			_on_research_pressed(region.id)
		)
	button_row.add_child(research_button)

	var select_button := Button.new()
	if is_current:
		select_button.text = "当前已选定"
		select_button.disabled = true
	elif not is_researched:
		select_button.text = "需先调研"
		select_button.disabled = true
	elif state.is_open:
		select_button.text = "门店已开业，无法更换"
		select_button.disabled = true
	else:
		select_button.text = "选定此区域"
		select_button.pressed.connect(func() -> void:
			_on_select_pressed(region.id)
		)
	button_row.add_child(select_button)

	card.add_child(button_row)
	card.add_child(HSeparator.new())
	return card


func _get_discounted_cost(region: RegionData) -> float:
	var origin := GameManager.get_origin(GameManager.store_state.selected_origin_id)
	var discount: float = 0.0
	if origin != null:
		discount = origin.research_discount_rate
	return region.research_cost * (1.0 - discount)


func _join_or_dash(arr) -> String:
	if arr == null or (arr is Array and arr.is_empty()):
		return "—"
	if arr is Array:
		return "；".join(arr)
	return str(arr)


func _on_research_pressed(region_id: String) -> void:
	var result: Dictionary = GameManager.research_region(region_id)
	if not result.get("success", false):
		status_label.text = "⚠ %s" % result.get("reason", "调研失败")
		return

	status_label.text = "✅ %s" % result.get("reason", "调研完成")
	refresh()


func _on_select_pressed(region_id: String) -> void:
	var result: Dictionary = GameManager.select_region(region_id)
	if not result.get("success", false):
		status_label.text = "⚠ %s" % result.get("reason", "选择区域失败")
		return

	status_label.text = "✅ %s" % result.get("reason", "区域已选定")
	refresh()
	region_selected.emit()
