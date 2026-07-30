extends PanelContainer

signal storefront_selected

@onready var region_hint_label: Label = $MarginContainer/VBox/RegionHintLabel
@onready var current_label: Label = $MarginContainer/VBox/CurrentLabel
@onready var storefront_list: VBoxContainer = $MarginContainer/VBox/StorefrontScroll/StorefrontList
@onready var status_label: Label = $MarginContainer/VBox/StatusLabel


func _ready() -> void:
	refresh()


func refresh() -> void:
	_clear_cards()
	status_label.text = ""

	var state := GameManager.store_state
	var region := GameManager.get_region(state.selected_region_id)

	if region == null:
		region_hint_label.text = "请先在「区域调研」中选定区域"
		region_hint_label.visible = true
		current_label.text = "当前门面：未选择"
		return

	region_hint_label.visible = false

	var storefront := GameManager.get_storefront(state.selected_storefront_id)
	if storefront == null:
		current_label.text = "当前门面：未选择（区域：%s）" % region.name
	else:
		current_label.text = "当前门面：%s（区域：%s）" % [storefront.name, region.name]

	var list := GameManager.get_storefronts_for_region(region.id)
	if list.is_empty():
		var empty_label := Label.new()
		empty_label.text = "该区域暂无可选门面"
		storefront_list.add_child(empty_label)
		return

	for sf in list:
		storefront_list.add_child(_build_storefront_card(sf))


func _clear_cards() -> void:
	for child in storefront_list.get_children():
		child.queue_free()


func _build_storefront_card(sf: StorefrontData) -> Control:
	var state := GameManager.store_state
	var is_current := state.selected_storefront_id == sf.id

	var card := VBoxContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "%s：%s" % [sf.id, sf.name]
	title.add_theme_font_size_override("font_size", 18)
	card.add_child(title)

	var basic_info := Label.new()
	basic_info.text = (
		"面积：%.0f㎡ ｜ 月租：¥%.0f ｜ 装修档次：%s"
		% [sf.area, sf.get_monthly_rent_yuan(), sf.decoration_level]
	)
	basic_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(basic_info)

	var flow_info := Label.new()
	flow_info.text = (
		"门面类型：%s ｜ 客流分成：%.0f%% ｜ 设备状况：%s ｜ 基础承载：%d/时段"
		% [sf.storefront_flow, sf.flow_share * 100.0, sf.equipment_condition, sf.hourly_capacity_base]
	)
	flow_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(flow_info)

	var cat_info := Label.new()
	cat_info.text = "支持品类：%s" % _join_or_dash(sf.supported_categories)
	cat_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(cat_info)

	if sf.notes != "":
		var notes_info := Label.new()
		notes_info.text = "备注：%s" % sf.notes
		notes_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(notes_info)

	var select_button := Button.new()
	if is_current:
		select_button.text = "当前已选定"
		select_button.disabled = true
	elif state.is_open:
		select_button.text = "门店已开业，无法更换"
		select_button.disabled = true
	else:
		select_button.text = "选定此门面"
		select_button.pressed.connect(func() -> void:
			_on_select_pressed(sf.id)
		)
	card.add_child(select_button)

	card.add_child(HSeparator.new())
	return card


func _join_or_dash(arr: Array) -> String:
	if arr.is_empty():
		return "—"
	return "；".join(arr)


func _on_select_pressed(storefront_id: String) -> void:
	var result: Dictionary = GameManager.select_storefront(storefront_id)
	if not result.get("success", false):
		status_label.text = "⚠ %s" % result.get("reason", "选择门面失败")
		return

	status_label.text = "✅ %s" % result.get("reason", "门面已选定")
	refresh()
	storefront_selected.emit()
