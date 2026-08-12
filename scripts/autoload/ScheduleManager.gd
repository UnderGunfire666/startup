extends Node

signal schedule_changed
signal hour_effect_applied(action_id: String, elapsed_hours: float, progress_ratio: float, effect_mult: float)
signal action_completed(action_id: String, elapsed_hours: float, duration_hours: int)
signal action_interrupt(reason_code: String, message: String)
signal day_schedule_ended(day: int)

var today_schedule: DaySchedule = DaySchedule.new()   # 只放"还没开始"的计划
var completed_entries_today: Array[ScheduledActionEntry] = []   # 今天已结束的（供日程列表/日结报告展示）
var current_action: CurrentActionState = null

var operating_hours_today: int = 0
var supervising_hours_today: int = 0


func _ready() -> void:
	TimeManager.hour_advanced.connect(_on_hour_tick)


func reset_for_new_game() -> void:
	today_schedule = DaySchedule.new()
	completed_entries_today.clear()
	current_action = null
	operating_hours_today = 0
	supervising_hours_today = 0


## ── 每小时触发一次：只负责"坐镇覆盖率"统计和跨天重置，不再驱动行动执行 ──
func _on_hour_tick(day: int, hour: int) -> void:
	if hour == 0:
		GameManager.player_state.start_new_day()
		today_schedule.clear()
		completed_entries_today.clear()
		operating_hours_today = 0
		supervising_hours_today = 0
		day_schedule_ended.emit(day - 1)

	if TimeManager.is_store_actually_operating():
		operating_hours_today += 1
		if GameManager.player_state.supervising_store_id == GameManager.active_store_id:
			supervising_hours_today += 1


## ── 排程校验（不变，仍然按小时寻址，因为"计划"本身就是按小时选起始点） ──

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

	## requires_inspected_storefront的旧检查已移除：
	## StoreState.inspected_storefront_ids字段已被storefront_diligence状态机取代，
	## 门面尽调的前置校验（比如"必须先初步看铺才能完整尽调"）改为在
	## GameManager.advance_storefront_diligence()内部于结算时校验，
	## 与region_research一直以来的校验方式（结算时校验，排程时不校验）保持一致。

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


func add_action_to_schedule(action_id: String, start_hour: int, target_id: String = "") -> Dictionary:
	var check := can_schedule_action(action_id, start_hour)
	if not check.can:
		return check
	var action := ScheduleActionData.get_action(action_id)
	var entry := today_schedule.add_entry(action_id, start_hour, action.duration_hours)
	entry.target_id = target_id
	schedule_changed.emit()
	return {"can": true, "reason_code": "", "reason": "已加入排程"}


func remove_action_from_schedule(hour: int) -> bool:
	var removed := today_schedule.remove_entry_at_hour(hour)
	if removed:
		schedule_changed.emit()
	return removed


## ── 单步模式：立即开始，不占用日历格子 ──────────────────────

func start_action_now(action_id: String, target_id: String = "") -> Dictionary:
	if current_action != null and current_action.is_active:
		return {"can": false, "reason_code": "already_running", "reason": "已经有一个行动正在进行，请先结束它"}

	var current_hour := int(TimeManager.get_hour_of_day())
	var check := can_schedule_action(action_id, current_hour)
	if not check.can:
		return check

	var action := ScheduleActionData.get_action(action_id)
	_begin_current_action(action_id, target_id, null)
	TimeManager.set_speed(TimeManager.Speed.X1)
	schedule_changed.emit()
	return {"can": true, "reason_code": "", "reason": "已开始「%s」" % action.name}


func stop_current_action() -> void:
	if current_action == null or not current_action.is_active:
		return
	var elapsed_hours: float = (TimeManager.total_game_seconds - current_action.start_game_seconds) / 3600.0
	_finalize_current_action(elapsed_hours)


## ── 每帧/每次时钟前进都调用：检查当前状态是否该结束，检查队列有没有到点的 ──

func tick() -> void:
	if current_action != null and current_action.is_active:
		var action := ScheduleActionData.get_action(current_action.action_id)
		var elapsed_hours: float = (TimeManager.total_game_seconds - current_action.start_game_seconds) / 3600.0
		if elapsed_hours >= float(action.duration_hours) - 0.0001:
			_finalize_current_action(float(action.duration_hours))
			return

	if current_action == null or not current_action.is_active:
		_check_and_start_planned_entry()


func _check_and_start_planned_entry() -> void:
	var current_hour := int(TimeManager.get_hour_of_day())
	for e in today_schedule.entries:
		if e.status != "pending":
			continue
		if current_hour >= e.get_end_hour():
			e.status = "failed"
			e.failure_reason = "错过了计划的时间窗口"
			completed_entries_today.append(e)
			today_schedule.entries.erase(e)
			continue
		if e.start_hour <= current_hour:
			today_schedule.entries.erase(e)
			_begin_current_action(e.action_id, e.target_id, e)
			return


func _begin_current_action(action_id: String, target_id: String, source_entry: ScheduledActionEntry) -> void:
	current_action = CurrentActionState.new()
	current_action.action_id = action_id
	current_action.target_id = target_id
	current_action.start_game_seconds = TimeManager.total_game_seconds
	current_action.work_hours_before = GameManager.player_state.work_hours_today
	current_action.source_entry = source_entry
	current_action.is_active = true

	var action := ScheduleActionData.get_action(action_id)
	if action.action_effect_type == "store_supervision":
		GameManager.player_state.supervising_store_id = GameManager.active_store_id


func _finalize_current_action(elapsed_hours: float) -> void:
	var action := ScheduleActionData.get_action(current_action.action_id)
	var player := GameManager.player_state

	## 目标失效检查：不追溯撤销已经发生的效果，只是提前收尾并记录原因。
	var precondition := _check_preconditions(action, int(TimeManager.get_hour_of_day()))

	var segments := ScheduleConfig.split_duration_by_fatigue_tiers(
		current_action.work_hours_before, elapsed_hours)

	var total_cost := 0.0
	var total_recovery := 0.0
	var weighted_effect_mult := 0.0

	for seg in segments:
		if action.energy_recovery_per_hour > 0.0:
			total_recovery += action.energy_recovery_per_hour * seg.hours
		else:
			total_cost += action.base_energy_cost_per_hour * seg.hours * seg.energy_mult
		weighted_effect_mult += seg.effect_mult * seg.hours

	if elapsed_hours > 0.0:
		weighted_effect_mult /= elapsed_hours

	if action.energy_recovery_per_hour > 0.0:
		player.apply_energy_delta(total_recovery)
	else:
		player.apply_energy_delta(-total_cost)

	if action.work_hour_counting:
		player.work_hours_today += elapsed_hours
	player.fatigue_state = ScheduleConfig.get_fatigue_tier(player.work_hours_today).state

	if action.action_effect_type == "store_supervision":
		GameManager.player_state.supervising_store_id = ""

	var final_status := "completed"
	var failure_reason := ""

	if not precondition.can:
		final_status = "failed"
		failure_reason = precondition.reason
	else:
		match action.effect_scaling:
			"proportional":
				var progress_ratio := elapsed_hours / float(action.duration_hours)
				hour_effect_applied.emit(action.id, elapsed_hours, progress_ratio, weighted_effect_mult)

				if current_action.target_id != "":
					var effect_result := _apply_understanding_effect(
						action.action_effect_type, current_action.target_id, elapsed_hours
					)
					if not effect_result.is_empty() and not effect_result.success:
						final_status = "failed"
						failure_reason = effect_result.reason
			"binary":
				if elapsed_hours >= float(action.duration_hours) - 0.0001:
					action_completed.emit(action.id, elapsed_hours, action.duration_hours)

	## 记录这次执行结果，供UI/日结报告展示。
	var record: ScheduledActionEntry = current_action.source_entry
	if record == null:
		record = ScheduledActionEntry.new()
		record.action_id = current_action.action_id
		record.start_hour = int((current_action.start_game_seconds / 3600.0) as float) % 24
		record.duration_hours = action.duration_hours
	record.target_id = current_action.target_id
	record.hours_completed = elapsed_hours
	record.status = final_status
	record.failure_reason = failure_reason
	completed_entries_today.append(record)

	current_action = null

	if player.energy <= 0.0 and player.energy_debt > 0.0:
		action_interrupt.emit("energy_exhausted", "精力已耗尽，当前处于透支状态")

	if today_schedule.entries.is_empty():
		TimeManager.set_speed(TimeManager.Speed.PAUSED)
	## 否则保持当前速度，让时间继续流逝，下一次tick()会自动接上排程队列里的下一项。

	schedule_changed.emit()


## ── 三层了解度行动效果分发 ─────────────────────────────────
## target_id的含义按行动类型不同：
## region_research → survey_area_id（玩家在地图上框选的调查范围）
## storefront_inspection / deep_inspection → storefront_id

func _apply_understanding_effect(effect_type: String, target_id: String, elapsed_hours: float) -> Dictionary:
	match effect_type:
		"region_research":
			return _apply_region_research_effect(target_id, elapsed_hours)
		"deep_inspection":
			return GameManager.advance_storefront_diligence(target_id, "full_diligence")
		_:
			return {}


func _apply_region_research_effect(survey_area_id: String, elapsed_hours: float) -> Dictionary:
	var survey_area := GameManager.player_state.get_survey_area(survey_area_id)
	if survey_area == null:
		return {"success": false, "reason": "调查范围不存在，请先在地图上框选区域"}

	var gain := RegionConfig.FAMILIARITY_GAIN_PER_HOUR * elapsed_hours
	var applied := false

	for coverage in survey_area.block_coverages:
		if coverage.combined_weight <= 0.0:
			continue
		GameManager.advance_block_understanding(coverage.block_id, gain * coverage.combined_weight)
		applied = true

	if not applied:
		return {"success": false, "reason": "调查范围未命中任何区块"}

	GameManager.recalculate_region_intel(survey_area.city_region_id)
	survey_area.last_used_day = TimeManager.current_day

	return {"success": true, "reason": "调查进度已更新"}


## ── 动态判定辅助（不变） ──────────────────────────────────

func _is_store_operating_at(hour: int) -> bool:
	if not GameManager.store_state.is_open:
		return false
	for cat_slot in GameManager.store_state.category_slots:
		if cat_slot.is_open_at_hour(hour):
			return true
	return false


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
