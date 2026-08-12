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

	## 注意：本面板属于过渡期遗留UI。选址的了解度门槛已随本次重构移除，
	## 这里不再展示"了解程度/兴趣程度"进度条——该系统的替代方案是地图上
	## 按区块了解度逐步解锁信息，详见CityMapPanel。这个面板未来会被
	## "直接点地图上的门面"流程取代，届时会整体移除。
	var detail_info := Label.new()
	detail_info.text = "停留性：%s ｜ 竞争强度：%s ｜ 周末客流倍率：%.1fx ｜ 主力人群：%s" % [
		region.dwell_time, region.competition_level, region.weekend_modifier,
		"、".join(region.primary_groups),
	]
	detail_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(detail_info)

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
