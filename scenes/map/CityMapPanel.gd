extends Control
signal storefront_interior_requested(storefront_id: String)
signal storefront_details_requested(storefront_id: String)
## 地图页：鼠标点选一个或多个区块。
## Phase 2：调查行动直接绑定选中的 Block，不再通过 SurveyArea 启动调查。
## Phase 7：通过调查方式下拉菜单提供“随便逛逛”和“按顺序逛”两种模式。
## SurveyArea 数据仍保留在存档层，后续阶段再清理。

@onready var map_canvas: CityMapCanvas = $HBoxContainer/MapScrollContainer/MapCanvas
@onready var instruction_label: Label = $HBoxContainer/SidePanel/InstructionLabel
@onready var report_label: Label = $HBoxContainer/SidePanel/ReportScroll/ReportLabel
@onready var status_label: Label = $HBoxContainer/SidePanel/StatusLabel
@onready var clear_selection_button: Button = $HBoxContainer/SidePanel/ClearSelectionButton
@onready var travel_target_label: Label = $HBoxContainer/SidePanel/TravelCard/TravelTargetLabel
@onready var travel_mode_option: OptionButton = $HBoxContainer/SidePanel/TravelCard/TravelModeOption
@onready var start_travel_button: Button = $HBoxContainer/SidePanel/TravelCard/StartTravelButton
@onready var show_all_storefronts_button: Button = $HBoxContainer/SidePanel/ShowAllStorefrontsButton
@onready var awareness_overlay_toggle: CheckBox = $HBoxContainer/SidePanel/AwarenessOverlayToggle
@onready var research_mode_option: OptionButton = $HBoxContainer/SidePanel/ResearchModeOption
@onready var research_focus_option: OptionButton = $HBoxContainer/SidePanel/ResearchFocusOption
@onready var start_research_button: Button = $HBoxContainer/SidePanel/StartResearchButton

## 已发现门面列表容器。
@onready var storefront_list: VBoxContainer = $HBoxContainer/SidePanel/StorefrontScroll/StorefrontList

var _sequence_research: RegionResearchSequence = null
var _travel_target_block_id := ""
var _travel_target_storefront_id := ""
const RESEARCH_MODE_SELECTED_BLOCKS := 0
const RESEARCH_MODE_SEQUENTIAL := 1
const RESEARCH_FOCUS_LABELS := {
	ScheduleManager.RESEARCH_FOCUS_ALL: "同步调查（均分未完成项）",
	"population": "人口", "groups": "人群", "time": "时段",
	"spending": "消费", "demand": "业态需求", "competition": "竞争",
}


func _ready() -> void:
	map_canvas.setup(GameManager.all_city_regions, GameManager.all_blocks, GameManager.road_graph, GameManager.all_player_homes)
	map_canvas.selected_blocks_changed.connect(_on_selected_blocks_changed)
	map_canvas.storefront_clicked.connect(_on_storefront_clicked)
	clear_selection_button.pressed.connect(_on_clear_selection_pressed)
	travel_mode_option.item_selected.connect(func(_index: int): _refresh_travel_card())
	start_travel_button.pressed.connect(_on_start_travel_pressed)
	show_all_storefronts_button.hide()
	awareness_overlay_toggle.toggled.connect(_on_awareness_overlay_toggled)
	research_mode_option.item_selected.connect(_on_research_mode_selected)
	research_focus_option.item_selected.connect(_on_research_focus_selected)
	start_research_button.pressed.connect(_on_start_research_pressed)
	ScheduleManager.schedule_changed.connect(_on_schedule_changed)
	ScheduleManager.action_interrupt.connect(_on_action_interrupt)
	ScheduleManager.hour_effect_applied.connect(_on_action_progress_applied)
	TimeManager.clock_updated.connect(_on_clock_updated)
	EventManager.notice_raised.connect(_on_event_notice_raised)

	research_mode_option.clear()
	research_mode_option.add_item("调查所选区块", RESEARCH_MODE_SELECTED_BLOCKS)
	research_mode_option.add_item("按顺序逛（自动前往）", RESEARCH_MODE_SEQUENTIAL)
	research_mode_option.tooltip_text = "按顺序逛会在完成当前区块后自动前往下一个选中区块。"
	research_focus_option.clear()
	research_focus_option.add_item("调研方式：同步调查（均分未完成项）")
	research_focus_option.set_item_metadata(0, ScheduleManager.RESEARCH_FOCUS_ALL)
	for focus in [["population", "人口"], ["groups", "人群"], ["time", "时段"], ["spending", "消费"], ["demand", "业态需求"], ["competition", "竞争"]]:
		research_focus_option.add_item("调研重点：" + str(focus[1]))
		research_focus_option.set_item_metadata(research_focus_option.item_count - 1, str(focus[0]))
	_sync_research_focus_option()

	_sequence_research = RegionResearchSequence.new()
	_sequence_research.changed.connect(_on_sequence_changed)
	_sequence_research.completed.connect(_on_sequence_completed)
	_sequence_research.failed.connect(_on_sequence_failed)

	instruction_label.text = "点击地图上的区块进行选择；再次点击已选区块可取消选择。选择调查方式后，点击“开始调查”。"
	ScheduleManager.set_selected_map_block_ids(map_canvas.selected_block_ids)
	refresh()


func refresh() -> void:
	_sync_research_focus_option()
	map_canvas.refresh_storefronts(GameManager.all_storefronts)
	_refresh_awareness_overlay()
	_refresh_report()
	_refresh_storefront_list()
	_refresh_research_controls()
	_refresh_travel_card()


func _on_selected_blocks_changed(block_ids: Array[String]) -> void:
	ScheduleManager.set_selected_map_block_ids(block_ids)
	_refresh_report()
	_refresh_research_controls()
	if block_ids.size() == 1:
		_travel_target_block_id = block_ids[0]
		_travel_target_storefront_id = ""
	_refresh_travel_card()


func _on_clear_selection_pressed() -> void:
	map_canvas.clear_block_selection()
	ScheduleManager.set_selected_map_block_ids([])
	status_label.text = "已清空区块选择"


func _on_show_all_storefronts_pressed() -> void:
	var newly_revealed := GameManager.reveal_all_storefronts()
	refresh()
	if newly_revealed.is_empty():
		status_label.text = "全部门面已显示。"
	else:
		status_label.text = "✅ 已显示 %d 个门面。" % newly_revealed.size()


func _on_awareness_overlay_toggled(_enabled: bool) -> void:
	_refresh_awareness_overlay()


func _refresh_awareness_overlay() -> void:
	var store := GameManager.get_active_store()
	if store == null or store.signed_storefront_id.is_empty():
		awareness_overlay_toggle.disabled = true
		awareness_overlay_toggle.button_pressed = false
		map_canvas.clear_awareness_overlay()
		return
	var storefront := GameManager.get_storefront(store.signed_storefront_id)
	var is_revealed := storefront != null
	awareness_overlay_toggle.disabled = not is_revealed
	if not is_revealed:
		awareness_overlay_toggle.button_pressed = false
		map_canvas.clear_awareness_overlay()
		return
	if awareness_overlay_toggle.button_pressed:
		map_canvas.set_awareness_overlay(storefront, store.awareness_by_block)
	else:
		map_canvas.clear_awareness_overlay()


func _on_start_research_pressed() -> void:
	var selected_blocks := map_canvas.get_selected_blocks()
	var block_ids := _get_incomplete_block_ids(selected_blocks)
	var start_check := _get_research_start_check(block_ids)
	if not bool(start_check.get("can", false)):
		start_research_button.disabled = true
		start_research_button.tooltip_text = str(start_check.get("reason", ""))
		status_label.text = "⚠ " + str(start_check.get("reason", "无法开始调查"))
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


func _on_research_focus_selected(index: int) -> void:
	ScheduleManager.set_region_research_focus(str(research_focus_option.get_item_metadata(index)))
	_refresh_report()
	_refresh_research_controls()


func _sync_research_focus_option() -> void:
	for index in range(research_focus_option.item_count):
		if str(research_focus_option.get_item_metadata(index)) == ScheduleManager.selected_research_focus:
			research_focus_option.select(index)
			return


func _on_schedule_changed() -> void:
	_sync_research_focus_option()
	_refresh_report()
	_refresh_storefront_list()
	_refresh_research_controls()
	if ScheduleManager.current_action == null and not ScheduleManager.completed_entries_today.is_empty():
		var last_entry: ScheduledActionEntry = ScheduleManager.completed_entries_today.back()


func _on_clock_updated(_hour: int, _minute: int, _second: int, _period_label: String) -> void:
	map_canvas.queue_redraw()
	_refresh_research_controls()
	_refresh_travel_card()


func _on_action_interrupt(reason_code: String, reason: String) -> void:
	if reason_code != "energy_insufficient":
		return
	status_label.text = "⚠ " + reason
	_refresh_research_controls()


func _on_action_progress_applied(action_id: String, _elapsed_hours: float, _progress_ratio: float, _effect_mult: float) -> void:
	if action_id == "region_research":
		_refresh_report()
		_refresh_research_controls()


func _on_sequence_changed() -> void:
	_refresh_report()
	_refresh_research_controls()


func _on_sequence_completed() -> void:
	status_label.text = "✅ 你沿着安排走完了所有选中的区块，今天的街面观察已经收进记录。"
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
		status_label.text = "🏪 你在街面上认出了新的可看门面：%s。" % "、".join(names)


func _on_event_notice_raised(event: ActiveGameEvent) -> void:
	if event.scope != GameEventDefinition.Scope.PLAYER and event.scope != GameEventDefinition.Scope.BLOCK and event.scope != GameEventDefinition.Scope.CITY_REGION:
		return
	status_label.text = "[\u53d1\u73b0] " + event.title + "\uff1a" + event.message
	refresh()


func _refresh_research_controls() -> void:
	var selected_blocks := map_canvas.get_selected_blocks()
	var block_ids := _get_incomplete_block_ids(selected_blocks)
	var start_check := _get_research_start_check(block_ids)
	var can_start := bool(start_check.get("can", false))
	var action_running := ScheduleManager.current_action != null and ScheduleManager.current_action.is_active
	var sequence_running := _sequence_research != null and _sequence_research.active
	research_mode_option.disabled = action_running or sequence_running
	start_research_button.disabled = not can_start or action_running or sequence_running
	start_research_button.text = "按顺序逛（进行中）" if sequence_running else "开始调查"
	start_research_button.tooltip_text = "" if can_start else str(start_check.get("reason", ""))
	if not can_start and not action_running and not sequence_running and not block_ids.is_empty():
		status_label.text = "⚠ " + str(start_check.get("reason", "无法开始调查"))


func _get_incomplete_block_ids(selected_blocks: Array[BlockData]) -> Array[String]:
	var block_ids: Array[String] = []
	for block in selected_blocks:
		if not GameManager.is_block_research_complete(block.id):
			block_ids.append(block.id)
	return block_ids


func _get_research_start_check(block_ids: Array[String]) -> Dictionary:
	if block_ids.is_empty():
		return {"can": false, "reason": "所选区块都已经完全了解"}
	var energy_check := ScheduleManager.get_region_research_start_energy_check()
	if not bool(energy_check.get("can", false)):
		return energy_check
	if research_mode_option.get_selected_id() == RESEARCH_MODE_SEQUENTIAL:
		return {"can": true, "reason": ""}
	return ScheduleManager.can_schedule_action("region_research", TimeManager.get_current_hour_int(), "", block_ids)


func _on_storefront_clicked(storefront_id: String) -> void:
	var storefront := GameManager.get_storefront(storefront_id)
	if storefront != null:
		_travel_target_block_id = storefront.block_id
		_travel_target_storefront_id = storefront.id
		_refresh_travel_card()
	storefront_details_requested.emit(storefront_id)


func _refresh_travel_card() -> void:
	if travel_mode_option.item_count == 0:
		for mode in MovementConfig.TRAVEL_MODES:
			travel_mode_option.add_item(MovementConfig.get_mode_name(mode))
			travel_mode_option.set_item_metadata(travel_mode_option.item_count - 1, mode)
	if _travel_target_block_id.is_empty():
		travel_target_label.text = "选择一个区块或门面后，可比较出行方式。"
		start_travel_button.disabled = true
		return
	var target := GameManager.get_block(_travel_target_block_id)
	var mode := str(travel_mode_option.get_item_metadata(travel_mode_option.selected))
	var quote := ScheduleManager.get_travel_quote(_travel_target_block_id, mode)
	var target_name := target.name if target != null else _travel_target_block_id
	if not _travel_target_storefront_id.is_empty():
		var storefront := GameManager.get_storefront(_travel_target_storefront_id)
		if storefront != null: target_name = storefront.name + "（" + target_name + "）"
	travel_target_label.text = "目标：%s\n%s｜距离 %.1f｜%.2f 小时｜精力 %.1f｜费用 ¥%.0f%s" % [target_name, MovementConfig.get_mode_name(mode), float(quote.get("distance", 0.0)), float(quote.get("hours", 0.0)), float(quote.get("energy_cost", 0.0)), float(quote.get("cost", 0.0)), "" if bool(quote.get("can", false)) else "\n不可出发：" + str(quote.get("reason", ""))]
	start_travel_button.disabled = not bool(quote.get("can", false))
	start_travel_button.text = "前往：" + MovementConfig.get_mode_name(mode)


func _on_start_travel_pressed() -> void:
	var mode := str(travel_mode_option.get_item_metadata(travel_mode_option.selected))
	var result := ScheduleManager.start_travel(_travel_target_block_id, mode, _travel_target_storefront_id)
	status_label.text = ("✅ " if bool(result.get("can", false)) else "⚠ ") + str(result.get("reason", "无法出发"))
	_refresh_travel_card()


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
		if not GameManager.is_block_research_complete(block.id):
			has_incomplete_block = true
		var progress_parts: Array[String] = []
		for focus_id in GameManager.BLOCK_RESEARCH_FOCUSES:
			progress_parts.append("%s %.0f%%" % [str(RESEARCH_FOCUS_LABELS.get(focus_id, focus_id)), GameManager.get_block_research_progress(block.id, focus_id)])
		lines.append("• %s：%s" % [block.name, " | ".join(progress_parts)])
	lines.append("")
	lines.append("当前调研方式：%s" % str(RESEARCH_FOCUS_LABELS.get(ScheduleManager.selected_research_focus, ScheduleManager.selected_research_focus)))

	if _sequence_research != null and _sequence_research.active:
		var current_sequence_block := _sequence_research.get_current_block_id()
		var sequence_block := GameManager.get_block(current_sequence_block)
		if sequence_block != null:
			lines.append("")
			lines.append("按顺序逛：正在考察「%s」" % sequence_block.name)

	lines.append("")
	for intel_block in selected_blocks:
		for intel_line in StorefrontIntelPresenter.describe_block(intel_block, GameManager.player_state):
			lines.append(intel_line)
		lines.append("")
	report_label.text = "\n".join(lines)
	var action_running := ScheduleManager.current_action != null and ScheduleManager.current_action.is_active
	var start_check := _get_research_start_check(_get_incomplete_block_ids(selected_blocks))
	start_research_button.disabled = not bool(start_check.get("can", false)) or action_running or (_sequence_research != null and _sequence_research.active)


## 遍历所有已发现门面，维持当前地图页的选址/尽调功能。
func _refresh_storefront_list() -> void:
	for child in storefront_list.get_children():
		child.queue_free()
	for storefront in GameManager.all_storefronts:
		storefront_list.add_child(_build_storefront_row(storefront))
	return

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
	var visible_box := VBoxContainer.new()
	var visible_display := StorefrontIntelPresenter.describe_storefront(storefront, GameManager.player_state)
	var visible_label := Label.new()
	visible_label.text = "%s（%s）" % [storefront.name, str(visible_display.get("occupancy", ""))]
	visible_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	visible_box.add_child(visible_label)
	var visible_details := Button.new()
	visible_details.text = "查看门面"
	visible_details.pressed.connect(func(): storefront_details_requested.emit(storefront.id))
	visible_box.add_child(visible_details)
	visible_box.add_child(HSeparator.new())
	return visible_box
	var box := VBoxContainer.new()

	var name_label := Label.new()
	var npc_store := GameManager.get_npc_store_for_storefront(storefront.id)
	var occupancy_text := "转让中" if npc_store != null and npc_store.transfer_state == "offered" else ("已开店" if storefront.is_occupied else "空门面")
	var occupant_text := "｜经营者：%s" % storefront.occupant_name if storefront.is_occupied and not storefront.occupant_name.is_empty() else ""
	name_label.text = "%s（%s%s）" % [storefront.name, occupancy_text, occupant_text]
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var details_btn := Button.new()
	details_btn.text = "查看门面"
	details_btn.pressed.connect(func(): storefront_details_requested.emit(storefront.id))
	row.add_child(details_btn)

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


func _on_contact_landlord_pressed(storefront: StorefrontData) -> void:
	var store := GameManager.store_state
	if store == null:
		status_label.text = "⚠ 请先创建开店企划，再联系空门面的房东"
		return
	if store.is_open:
		status_label.text = "⚠ 当前店铺已开业，不能为它更换或谈判新门面"
		return
	var selected := GameManager.select_storefront(storefront.id)
	if not bool(selected.get("success", false)):
		status_label.text = "⚠ " + str(selected.get("reason", "无法选定门面"))
		return
	var result := ScheduleManager.start_action_now("landlord_negotiation")
	status_label.text = ("✅ " if bool(result.get("can", false)) else "⚠ ") + str(result.get("reason", ""))
	refresh()
