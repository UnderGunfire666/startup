extends Node
## 排程与每小时执行的核心逻辑层。监听 TimeManager.hour_advanced，
## 不重写店铺结算，只在必要时读取/设置 GameManager.store_state.owner_present。

signal schedule_changed
signal hour_executed(log_entry: HourlyLogEntry)
signal action_interrupt(reason_code: String, message: String)
signal day_schedule_ended(day: int)

var today_schedule: DaySchedule = DaySchedule.new()
var hourly_log: Array[HourlyLogEntry] = []
var last_completed_day: int = 0


func _ready() -> void:
	TimeManager.hour_advanced.connect(_on_hour_advanced)


func reset_for_new_game() -> void:
	today_schedule = DaySchedule.new()
	hourly_log.clear()
	last_completed_day = 0


## ── 排程校验（纯逻辑，UI直接调用） ──────────────────────

func can_schedule_action(action_id: String, start_hour: int) -> Dictionary:
	var action := ScheduleActionData.get_action(action_id)
	if action == null:
		return {"can": false, "reason_code": "invalid_action", "reason": "行动不存在"}

	if action.requires_character_created and not GameManager.player_state.is_character_created:
		return {"can": false, "reason_code": "no_character", "reason": "请先完成人物创建"}

	if start_hour < action.allowed_hour_range.x or \
			(start_hour + action.duration_hours) > action.allowed_hour_range.y:
		return {
			"can": false, "reason_code": "outside_allowed_hours",
			"reason": "%s仅可在%02d:00至%02d:00之间安排" % [
				action.name, action.allowed_hour_range.x, action.allowed_hour_range.y
			]
		}

	if today_schedule.has_conflict(start_hour, action.duration_hours):
		return {"can": false, "reason_code": "time_conflict", "reason": "该时间已被其他行动占用，或超出当天24点"}

	var precondition := _check_preconditions(action, start_hour)
	if not precondition.can:
		return precondition

	return {"can": true, "reason_code": "", "reason": ""}


func _check_preconditions(action: ActionDefinition, start_hour: int) -> Dictionary:
	var state := GameManager.store_state

	if action.requires_open_store and not state.is_open:
		return {"can": false, "reason_code": "store_not_open", "reason": "尚未开业，无法安排「%s」" % action.name}

	if action.requires_region_selected and state.selected_region_id == "":
		return {"can": false, "reason_code": "no_region", "reason": "请先选定区域"}

	if action.requires_inspected_storefront and state.inspected_storefront_ids.is_empty():
		return {"can": false, "reason_code": "not_inspected", "reason": "目标门面尚未完成实地考察"}

	if action.requires_selected_category and state.category_slots.is_empty():
		return {"can": false, "reason_code": "no_category", "reason": "请先选择经营品类"}

	if action.requires_today_has_settled and not _today_has_settled():
		return {"can": false, "reason_code": "no_business_today", "reason": "今天尚未发生任何营业，无法收档复盘"}

	if action.requires_store_operating_hour:
		var check_hour := start_hour
		var end_hour := start_hour + action.duration_hours
		while check_hour < end_hour:
			if not _is_store_operating_at(check_hour):
				var next_open := _next_operating_hour_after(check_hour)
				var reason := "当前店铺在此时段不营业"
				if next_open >= 0:
					reason += "，下次营业时间为 %02d:00" % next_open
				return {"can": false, "reason_code": "store_not_operating", "reason": reason}
			check_hour += 1

	return {"can": true, "reason_code": "", "reason": ""}


func add_action_to_schedule(action_id: String, start_hour: int) -> Dictionary:
	var check := can_schedule_action(action_id, start_hour)
	if not check.can:
		return check
	var action := ScheduleActionData.get_action(action_id)
	today_schedule.add_entry(action_id, start_hour, action.duration_hours)
	schedule_changed.emit()
	return {"can": true, "reason_code": "", "reason": "已加入排程"}


func remove_action_from_schedule(hour: int) -> bool:
	var removed := today_schedule.remove_entry_at_hour(hour)
	if removed:
		schedule_changed.emit()
	return removed


## ── 动态判定辅助 ─────────────────────────────────────────

## 判断给定小时是否落在"至少一个已配置品类真正营业"的窗口内。
## 完全复用现有 SettlementEngine 的营业判定思路（品类的 default_open_slots/
## preferred_slots/strategy），不重写判定逻辑，只是换成按小时查询。
func _is_store_operating_at(hour: int) -> bool:
	if not GameManager.store_state.is_open:
		return false
	var slot_id := _slot_id_at_hour(hour)
	if slot_id == "":
		return false
	for cat_slot in GameManager.store_state.category_slots:
		var cat := GameManager.get_category(cat_slot.category_id)
		if cat == null:
			continue
		var active_slots: Array = []
		match cat_slot.strategy:
			"standard": active_slots = cat.default_open_slots
			"extend":   active_slots = SettlementConfig.SLOT_ORDER
			"shorten":  active_slots = cat.preferred_slots
		if slot_id in active_slots:
			return true
	return false


func _slot_id_at_hour(hour: int) -> String:
	for slot_id in SettlementConfig.SLOT_ORDER:
		var start: int = TimeManager.SLOT_START_HOUR[slot_id]
		var length: int = SettlementConfig.SLOT_HOURS[slot_id]
		if hour >= start and hour < start + length:
			return slot_id
	return ""


func _next_operating_hour_after(hour: int) -> int:
	for offset in range(1, 25):
		var h := (hour + offset) % 24
		if _is_store_operating_at(h):
			return h
	return -1


func _today_has_settled() -> bool:
	var day := TimeManager.current_day
	for entry in GameManager.store_state.daily_history:
		if entry.get("day", -1) == day:
			return true
	return false


## ── 每小时执行（核心） ───────────────────────────────────

func _on_hour_advanced(day: int, hour: int) -> void:
	if hour == 0:
		_handle_day_rollover(day)

	var player := GameManager.player_state
	var entry := today_schedule.get_entry_for_hour(hour)

	var log := HourlyLogEntry.new()
	log.day = day
	log.hour = hour
	log.energy_before = player.energy
	log.energy_debt_before = player.energy_debt
	log.work_hours_before = player.work_hours_today
	log.fatigue_before = player.fatigue_state
	log.store_was_operating = _is_store_operating_at(hour)

	if entry == null:
		log.action_status = "idle"
	else:
		_execute_hour_for_action(entry, log)

	player.fatigue_state = ScheduleConfig.get_fatigue_tier(player.work_hours_today).state

	log.energy_after = player.energy
	log.energy_debt_after = player.energy_debt
	log.work_hours_after = player.work_hours_today
	log.fatigue_after = player.fatigue_state

	hourly_log.append(log)
	hour_executed.emit(log)

	if player.energy <= 0.0 and player.energy_debt > 0.0 and entry != null:
		action_interrupt.emit("energy_exhausted", "精力已耗尽，当前处于透支状态")


func _execute_hour_for_action(entry: ScheduledActionEntry, log: HourlyLogEntry) -> void:
	var action := ScheduleActionData.get_action(entry.action_id)
	if action == null:
		entry.status = "failed"
		entry.failure_reason = "行动定义丢失"
		log.action_status = "failed"
		log.failure_reason = entry.failure_reason
		return

	log.action_id = action.id
	log.action_name = action.name

	## 行动仍然可能因为目标失效而在执行途中失败——重新校验一次前置条件，
	## 不自动替换为其他行动，只记录明确原因。
	var precondition := _check_preconditions(action, entry.start_hour)
	if not precondition.can:
		entry.status = "failed"
		entry.failure_reason = precondition.reason
		log.action_status = "failed"
		log.failure_reason = precondition.reason
		return

	var player := GameManager.player_state
	var tier := ScheduleConfig.get_fatigue_tier(player.work_hours_today)
	log.applied_energy_multiplier = tier.energy_mult
	log.applied_effect_multiplier = tier.effect_mult

	if action.energy_recovery_per_hour > 0.0:
		player.apply_energy_delta(action.energy_recovery_per_hour)
	else:
		var cost: float = action.base_energy_cost_per_hour * tier.energy_mult
		player.apply_energy_delta(-cost)

	if action.work_hour_counting:
		player.work_hours_today += 1.0

	if action.action_effect_type == "store_supervision":
		GameManager.store_state.owner_present = true
		log.player_supervising = true
	else:
		log.player_supervising = false

	entry.status = "completed"
	log.action_status = "executing"

	if entry.get_end_hour() - 1 == log.hour:
		_apply_completion_effect(action, entry)
		log.action_status = "completed"


## 行动最后一小时才触发"完成效果"——工作行动的实际业务效果
## （调研解锁、库存补充等）在这里统一分发，不按名字写if/else，
## 按 action_effect_type 分发，未接入的类型只广播信号供未来系统监听。
func _apply_completion_effect(action: ActionDefinition, _entry: ScheduledActionEntry) -> void:
	match action.action_effect_type:
		"store_supervision":
			pass  # 坐镇效果已在每小时里通过 owner_present 生效，无需额外收尾
		_:
			pass
	# 预留 hook：具体系统接入前，只广播完成事件。
	# ScheduleManagerActionCompleted 信号名故意区别于 hour_executed，避免UI重复处理。


func _handle_day_rollover(new_day: int) -> void:
	GameManager.player_state.start_new_day()
	today_schedule.clear()
	last_completed_day = new_day - 1
	day_schedule_ended.emit(last_completed_day)
