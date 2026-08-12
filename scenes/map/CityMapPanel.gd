extends Control
## 地图页：鼠标点选一个或多个区块。
## Phase 2：调查行动直接绑定选中的 Block，不再通过 SurveyArea 启动调查。
## SurveyArea 数据仍保留在存档层，后续阶段再清理。

@onready var map_canvas: CityMapCanvas = $HBoxContainer/MapScrollContainer/MapCanvas
@onready var instruction_label: Label = $HBoxContainer/SidePanel/InstructionLabel
@onready var report_label: Label = $HBoxContainer/SidePanel/ReportScroll/ReportLabel
@onready var status_label: Label = $HBoxContainer/SidePanel/StatusLabel
@onready var clear_selection_button: Button = $HBoxContainer/SidePanel/ClearSelectionButton
@onready var start_research_button: Button = $HBoxContainer/SidePanel/StartResearchButton

## 已发现门面列表容器。
@onready var storefront_list: VBoxContainer = $HBoxContainer/SidePanel/StorefrontScroll/StorefrontList


func _ready() -> void:
	map_canvas.setup(GameManager.all_city_regions, GameManager.all_blocks)
	map_canvas.selected_blocks_changed.connect(_on_selected_blocks_changed)
	map_canvas.storefront_clicked.connect(_on_storefront_clicked)
	clear_selection_button.pressed.connect(_on_clear_selection_pressed)
	start_research_button.pressed.connect(_on_start_research_pressed)

	instruction_label.text = "点击地图上的区块进行选择；再次点击已选区块可取消选择。可同时选择多个区块。当前阶段可直接调查所选区块。"
	refresh()


func refresh() -> void:
	## Phase 2 不再让地图依赖 SurveyArea 作为调查入口。
	map_canvas.refresh_storefronts(GameManager.all_storefronts)
	_refresh_report()
	_refresh_storefront_list()


func _on_selected_blocks_changed(_block_ids: Array[String]) -> void:
	_refresh_report()


func _on_clear_selection_pressed() -> void:
	map_canvas.clear_block_selection()
	status_label.text = "已清空区块选择"


func _on_start_research_pressed() -> void:
	var selected_blocks := map_canvas.get_selected_blocks()
	if selected_blocks.is_empty():
		status_label.text = "⚠ 请先选择至少一个区块"
		return

	var block_ids: Array[String] = []
	for block in selected_blocks:
		if GameManager.get_block_understanding(block.id) < 100.0:
			block_ids.append(block.id)

	if block_ids.is_empty():
		status_label.text = "⚠ 所选区块都已经完全了解"
		_refresh_report()
		return

	var result := ScheduleManager.start_action_now("region_research", "", block_ids)
	status_label.text = ("✅ " if result.get("can", false) else "⚠ ") + str(result.get("reason", ""))


func _on_storefront_clicked(storefront_id: String) -> void:
	status_label.text = "已点击门面：%s" % storefront_id


func _refresh_report() -> void:
	var selected_blocks := map_canvas.get_selected_blocks()
	if selected_blocks.is_empty():
		report_label.text = "尚未选择区块。\n\n选择区块后，这里会显示当前选择及其了解度。"
		start_research_button.disabled = true
		return

	var lines: Array[String] = []
	lines.append("已选择区块：%d 个" % selected_blocks.size())
	lines.append("")

	var has_incomplete_block := false
	for block in selected_blocks:
		var understanding := GameManager.get_block_understanding(block.id)
		if understanding < 100.0:
			has_incomplete_block = true
		lines.append("• %s：%.0f%%了解度" % [block.name, understanding])

	report_label.text = "\n".join(lines)
	start_research_button.disabled = has_incomplete_block == false or (ScheduleManager.current_action != null and ScheduleManager.current_action.is_active)


## 遍历所有已发现门面，维持当前地图页的选址/尽调功能。
func _refresh_storefront_list() -> void:
	for child in storefront_list.get_children():
		child.queue_free()

	var discovered: Array[StorefrontData] = []
	for storefront in GameManager.all_storefronts:
		if GameManager.get_storefront_diligence(storefront.id) != "not_viewed":
			discovered.append(storefront)

	if discovered.is_empty():
		var empty_label := Label.new()
		empty_label.text = "当前暂未发现门面。"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		storefront_list.add_child(empty_label)
		return

	for storefront in discovered:
		storefront_list.add_child(_build_storefront_row(storefront))


func _build_storefront_row(storefront: StorefrontData) -> Control:
	var box := VBoxContainer.new()

	var diligence := GameManager.get_storefront_diligence(storefront.id)
	var diligence_text: String = {
		"initial_viewing": "初步看铺",
		"full_diligence": "完整尽调",
	}.get(diligence, diligence)

	var name_label := Label.new()
	name_label.text = "%s（%s ｜ 状态：%s）" % [storefront.name, storefront.notes, diligence_text]
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	if diligence == "initial_viewing":
		var deep_btn := Button.new()
		deep_btn.text = "深度勘验"
		deep_btn.pressed.connect(func():
			var result := ScheduleManager.start_action_now("deep_inspection", storefront.id)
			status_label.text = ("✅ " if result.get("can", false) else "⚠ ") + str(result.get("reason", ""))
		)
		row.add_child(deep_btn)

	var select_btn := Button.new()
	select_btn.text = "选定此门面（落实到当前企划）"
	select_btn.pressed.connect(func(): _on_select_storefront_pressed(storefront))
	row.add_child(select_btn)

	box.add_child(row)
	box.add_child(HSeparator.new())
	return box


func _on_select_storefront_pressed(storefront: StorefrontData) -> void:
	var store := GameManager.store_state
	if store == null:
		status_label.text = "⚠ 你还没有开店企划，请先去'我的店铺'新建一个"
		return

	if store.is_open:
		status_label.text = "⚠ 当前企划对应的店铺已经开业，不能更换门面"
		return

	var region_result := GameManager.select_region(storefront.region_id)
	if not region_result.get("success", false):
		status_label.text = "⚠ %s" % region_result.get("reason", "")
		return

	var storefront_result := GameManager.select_storefront(storefront.id)
	status_label.text = ("✅ " if storefront_result.get("success", false) else "⚠ ") + str(storefront_result.get("reason", ""))

	if storefront_result.get("success", false):
		refresh()
