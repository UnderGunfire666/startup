extends Control
## 地图页：鼠标点选一个或多个区块。
## Phase 2：调查行动直接绑定选中的 Block，不再通过 SurveyArea 启动调查。
## Phase 7：通过调查方式下拉菜单提供“随便逛逛”和“按顺序逛”两种模式。
## SurveyArea 数据仍保留在存档层，后续阶段再清理。

@onready var map_canvas: CityMapCanvas = $HBoxContainer/MapScrollContainer/MapCanvas
@onready var instruction_label: Label = $HBoxContainer/SidePanel/InstructionLabel
@onready var report_label: Label = $HBoxContainer/SidePanel/ReportScroll/ReportLabel
@onready var status_label: Label = $HBoxContainer/SidePanel/StatusLabel
@onready var clear_selection_button: Button = $HBoxContainer/SidePanel/ClearSelectionButton
@onready var research_mode_option: OptionButton = $HBoxContainer/SidePanel/ResearchModeOption
@onready var start_research_button: Button = $HBoxContainer/SidePanel/StartResearchButton

## 已发现门面列表容器。
@onready var storefront_list: VBoxContainer = $HBoxContainer/SidePanel/StorefrontScroll/StorefrontList

var _sequence_research: RegionResearchSequence = null
const RESEARCH_MODE_SELECTED_BLOCKS := 0
const RESEARCH_MODE_SEQUENTIAL := 1


func _ready() -> void:
	map_canvas.setup(GameManager.all_city_regions, GameManager.all_blocks)
	map_canvas.selected_blocks_changed.connect(_on_selected_blocks_changed)
	map_canvas.storefront_clicked.connect(_on_storefront_clicked)
	clear_selection_button.pressed.connect(_on_clear_selection_pressed)
	research_mode_option.item_selected.connect(_on_research_mode_selected)
	start_research_button.pressed.connect(_on_start_research_pressed)
	ScheduleManager.schedule_changed.connect(_on_schedule_changed)
	ScheduleManager.hour_effect_applied.connect(_on_action_progress_applied)
	GameManager.storefronts_discovered.connect(_on_storefronts_discovered)

	research_mode_option.clear()
	research_mode_option.add_item("调查所选区块", RESEARCH_MODE_SELECTED_BLOCKS)
	research_mode_option.add_item("按顺序逛（自动前往）", RESEARCH_MODE_SEQUENTIAL)
	research_mode_option.tooltip_text = "按顺序逛会在完成当前区块后自动前往下一个选中区块。"

	_sequence_research = RegionResearchSequence.new()
	_sequence_research.changed.connect(_on_sequence_changed)
	_sequence_research.completed.connect(_on_sequence_completed)
	_sequence_research.failed.connect(_on_sequence_failed)

	instruction_label.text = "点击地图上的区块进行选择；再次点击已选区块可取消选择。选择调查方式后，点击“开始调查”。"
	ScheduleManager.set_selected_map_block_ids(map_canvas.selected_block_ids)
	refresh()


func refresh() -> void:
	map_canvas.refresh_storefronts(GameManager.all_storefronts)
	_refresh_report()
	_refresh_storefront_list()
	_refresh_research_controls()


func _on_selected_blocks_changed(block_ids: Array[String]) -> void:
	ScheduleManager.set_selected_map_block_ids(block_ids)
	_refresh_report()
	_refresh_research_controls()


func _on_clear_selection_pressed() -> void:
	map_canvas.clear_block_selection()
	ScheduleManager.set_selected_map_block_ids([])
	status_label.text = "已清空区块选择"


func _on_start_research_pressed() -> void:
	var selected_blocks := map_canvas.get_selected_blocks()
	var block_ids := _get_incomplete_block_ids(selected_blocks)
	if block_ids.is_empty():
		status_label.text = "⚠ 所选区块都已经完全了解"
		_refresh_report()
		return

	var result: Dictionary
	if research_mode_option.get_selected_id() == RESEARCH_MODE_SEQUENTIAL:
		result = _sequence_research.start(block_ids)
	else:
		result = ScheduleManager.start_action_now("region_research", "", block_ids)
	status_label.text = ("✅ " if result.get("can", false) else "⚠ ") + str(result.get("reason", ""))
	_refresh_research_controls()


func _on_research_mode_selected(_mode_id: int) -> void:
	_refresh_research_controls()


func _on_schedule_changed() -> void:
	_refresh_report()
	_refresh_storefront_list()
	_refresh_research_controls()
	if ScheduleManager.current_action == null and not ScheduleManager.completed_entries_today.is_empty():
		var last_entry: ScheduledActionEntry = ScheduleManager.completed_entries_today.back()
		if last_entry.action_id == "deep_inspection":
			var storefront := GameManager.get_storefront(last_entry.target_id)
			var storefront_name := storefront.name if storefront != null else last_entry.target_id
			status_label.text = "✅ 深度勘验完成：%s" % storefront_name if last_entry.status == "completed" else "⚠ 深度勘验已停止：%s" % last_entry.failure_reason


func _on_action_progress_applied(action_id: String, _elapsed_hours: float, _progress_ratio: float, _effect_mult: float) -> void:
	if action_id == "region_research":
		_refresh_report()
		_refresh_research_controls()
	elif action_id == "deep_inspection":
		_refresh_storefront_list()
		var active := ScheduleManager.current_action
		if active != null:
			var storefront := GameManager.get_storefront(active.target_id)
			if storefront != null:
				status_label.text = "🔎 正在深度勘验「%s」：%.0f%%" % [storefront.name, GameManager.get_storefront_diligence_progress(storefront.id)]


func _on_sequence_changed() -> void:
	_refresh_report()
	_refresh_research_controls()


func _on_sequence_completed() -> void:
	status_label.text = "✅ 已按顺序完成所有选中区块的调查"
	_refresh_report()
	_refresh_research_controls()


func _on_sequence_failed(reason_code: String, reason: String) -> void:
	status_label.text = "⚠ %s" % reason
	_refresh_report()
	_refresh_research_controls()


func _on_storefronts_discovered(_storefront_ids: Array[String]) -> void:
	refresh()
	var names: Array[String] = []
	for sid in _storefront_ids:
		var sf := GameManager.get_storefront(sid)
		if sf != null:
			names.append(sf.name)
	if not names.is_empty():
		status_label.text = "🏪 新发现门面：%s" % "、".join(names)


func _refresh_research_controls() -> void:
	var selected_blocks := map_canvas.get_selected_blocks()
	var has_incomplete := not _get_incomplete_block_ids(selected_blocks).is_empty()
	var action_running := ScheduleManager.current_action != null and ScheduleManager.current_action.is_active
	var sequence_running := _sequence_research != null and _sequence_research.active
	research_mode_option.disabled = action_running or sequence_running
	start_research_button.disabled = not has_incomplete or action_running or sequence_running
	start_research_button.text = "按顺序逛（进行中）" if sequence_running else "开始调查"


func _get_incomplete_block_ids(selected_blocks: Array[BlockData]) -> Array[String]:
	var block_ids: Array[String] = []
	for block in selected_blocks:
		if GameManager.get_block_understanding(block.id) < 100.0:
			block_ids.append(block.id)
	return block_ids


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

	if _sequence_research != null and _sequence_research.active:
		var current_sequence_block := _sequence_research.get_current_block_id()
		var sequence_block := GameManager.get_block(current_sequence_block)
		if sequence_block != null:
			lines.append("")
			lines.append("按顺序逛：正在考察「%s」" % sequence_block.name)

	report_label.text = "\n".join(lines)
	var action_running := ScheduleManager.current_action != null and ScheduleManager.current_action.is_active
	start_research_button.disabled = not has_incomplete_block or action_running or (_sequence_research != null and _sequence_research.active)


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
	var diligence_progress := GameManager.get_storefront_diligence_progress(storefront.id)
	var diligence_text: String = {
		"initial_viewing": "初步看铺",
		"full_diligence": "完整尽调",
	}.get(diligence, diligence)

	var name_label := Label.new()
	var progress_text := "（%.0f%%）" % diligence_progress if diligence == "initial_viewing" else ""
	name_label.text = "%s（%s ｜ 状态：%s%s）" % [storefront.name, storefront.notes, diligence_text, progress_text]
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	if diligence == "initial_viewing":
		var deep_btn := Button.new()
		var is_inspecting := ScheduleManager.current_action != null and ScheduleManager.current_action.is_active and ScheduleManager.current_action.action_id == "deep_inspection" and ScheduleManager.current_action.target_id == storefront.id
		deep_btn.text = "深度勘验中（%.0f%%）" % diligence_progress if is_inspecting else "深度勘验（%.0f%%）" % diligence_progress
		deep_btn.disabled = ScheduleManager.current_action != null and ScheduleManager.current_action.is_active
		deep_btn.pressed.connect(func():
			var result := ScheduleManager.start_action_now("deep_inspection", storefront.id)
			status_label.text = ("✅ " if result.get("can", false) else "⚠ ") + str(result.get("reason", ""))
			_refresh_storefront_list()
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

	var storefront_result := GameManager.select_storefront(storefront.id)
	status_label.text = ("✅ " if storefront_result.get("success", false) else "⚠ ") + str(storefront_result.get("reason", ""))

	if storefront_result.get("success", false):
		refresh()
