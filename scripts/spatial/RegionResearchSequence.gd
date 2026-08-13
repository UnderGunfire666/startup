class_name RegionResearchSequence
extends RefCounted
## Phase 7：按顺序调查多个区块。
## 每个区块必须先完全了解，才会移动到下一个区块；移动本身消耗游戏时间。

signal changed
signal completed
signal failed(reason_code: String, reason: String)

var block_ids: Array[String] = []
var current_index: int = 0
var active: bool = false
var expected_action_id: String = ""

func _init() -> void:
	ScheduleManager.schedule_changed.connect(_on_schedule_changed)
	ScheduleManager.action_interrupt.connect(_on_action_interrupt)

func start(selected_block_ids: Array[String]) -> Dictionary:
	if active:
		return {"can": false, "reason_code": "sequence_already_running", "reason": "按顺序调查已经在进行"}
	if selected_block_ids.is_empty():
		return {"can": false, "reason_code": "no_blocks_selected", "reason": "请先选择至少一个区块"}
	if ScheduleManager.current_action != null and ScheduleManager.current_action.is_active:
		return {"can": false, "reason_code": "already_running", "reason": "已有行动正在进行"}
	block_ids.clear()
	for block_id in selected_block_ids:
		var block := GameManager.get_block(block_id)
		if block == null:
			return {"can": false, "reason_code": "block_not_found", "reason": "调查区块不存在：%s" % block_id}
		if GameManager.get_block_understanding(block_id) < 100.0:
			block_ids.append(block_id)

	if block_ids.is_empty():
		return {"can": false, "reason_code": "all_blocks_complete", "reason": "所选区块都已经完全了解"}
	if GameManager.player_state.current_block_id.is_empty():
		## 首次从地图启动路线时，首个选中的区块就是玩家明确选择的初始位置。
		GameManager.player_state.set_current_block(block_ids[0])

	current_index = 0
	expected_action_id = ""
	active = true
	changed.emit()
	_advance()
	return {"can": true, "reason_code": "", "reason": "已开始按顺序调查", "block_ids": block_ids.duplicate()}

func cancel() -> void:
	active = false
	expected_action_id = ""
	block_ids.clear()
	current_index = 0
	changed.emit()

func get_current_block_id() -> String:
	if not active or current_index < 0 or current_index >= block_ids.size():
		return ""
	return block_ids[current_index]

func _advance() -> void:
	if not active:
		return
	if ScheduleManager.current_action != null and ScheduleManager.current_action.is_active:
		return

	while current_index < block_ids.size() and GameManager.get_block_understanding(block_ids[current_index]) >= 100.0:
		current_index += 1

	if current_index >= block_ids.size():
		active = false
		expected_action_id = ""
		changed.emit()
		completed.emit()
		return

	var target_id := block_ids[current_index]
	var current_location := GameManager.player_state.current_block_id
	var result: Dictionary
	if current_location != target_id:
		expected_action_id = "move_to_block"
		result = ScheduleManager.start_action_now("move_to_block", target_id)
	else:
		expected_action_id = "region_research"
		result = ScheduleManager.start_action_now("region_research", "", [target_id])

	if not bool(result.get("can", false)):
		active = false
		expected_action_id = ""
		failed.emit(str(result.get("reason_code", "sequence_action_failed")), str(result.get("reason", "按顺序调查无法继续")))
		changed.emit()
		return
	changed.emit()

func _on_schedule_changed() -> void:
	if not active or expected_action_id.is_empty():
		return
	if ScheduleManager.current_action != null and ScheduleManager.current_action.is_active:
		return
	if ScheduleManager.completed_entries_today.is_empty():
		return

	var last_entry: ScheduledActionEntry = ScheduleManager.completed_entries_today.back()
	if last_entry.action_id != expected_action_id:
		return

	if expected_action_id == "region_research":
		var target_id := block_ids[current_index] if current_index < block_ids.size() else ""
		if target_id.is_empty() or GameManager.get_block_understanding(target_id) < 100.0:
			active = false
			expected_action_id = ""
			failed.emit("research_stopped", "当前区块尚未完全了解，按顺序调查已停止")
			changed.emit()
			return
		current_index += 1

	expected_action_id = ""
	changed.emit()
	_advance()

func _on_action_interrupt(reason_code: String, reason: String) -> void:
	if not active:
		return
	active = false
	expected_action_id = ""
	failed.emit(reason_code, reason)
	changed.emit()
