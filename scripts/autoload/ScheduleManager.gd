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


func _on_hour_tick(day: int, hour: int) -> void:
	if hour == 0:
		GameManager.player_state.start_new_day()
		today_schedule.clear()
		completed_entries_today.clear()
		operating_hours_today = 0
		supervising_hours_today = 0
		day_schedule_ended.emit(day - 1)

	var supervised_id := GameManager.player_state.supervising_store_id
	var supervised_store: Store = GameManager.get_store(supervised_id) if supervised_id != "" else null

	if TimeManager.is_store_actually_operating():
		operating_hours_today += 1

	if supervised_store != null and _is_store_operating_at(TimeManager.get_current_hour_int(), supervised_store):
		supervising_hours_today += 1


func can_schedule_action(
		action_id: String,
		start_hour: int,
		target_id: String = "",
		target_ids: Array[String] = []
) -> Dictionary:
	var action := ScheduleActionData.get_action(action_id)
	if action == null:
		return {"can": false, "reason_code": "invalid_action", "reason": "行动不存在"}

	if action.requires_character_created and not GameManager.player_state.is_character_created:
		return {"can": false, "reason_code": "no_character", "reason": "请先完成人物创建"}

	if start_hour < action.allowed_hour_range.x or \
			(start_hour + action.duration_hours) > action.allowed_hour_range.y:
		return {
			"can": false,
			"reason_code": "outside_allowed_hours",
			"reason": "%s仅可在%02d:00至%02d:00之间安排" % [
				action.name, action.allowed_hour_range.x, action.allowed_hour_range.y
			]
		}

	if today_schedule.has_conflict(start_hour, action.duration_hours):
		return {"can": false, "reason_code": "time_conflict", "reason": "该时间已被其他行动占用，或超出当天24点"}

	var precondition := _check_preconditions(action, start_hour, target_id, target_ids)
	if not precondition.can:
		return precondition

	return {"can": true, "reason_code": "", "reason": ""}


func _check_preconditions(
		action: ActionDefinition,
		start_hour: int,
		target_id: String = "",
		target_ids: Array[String] = []
) -> Dictionary:
	## 行动目标不一定是Store：
	## region_research → Block ID列表（Phase 2）
	## deep_inspection → storefront_id
	## 只有真正依赖Store状态的行动才解析Store并要求其存在。
	if action.action_effect_type == "region_research":
		if target_ids.is_empty():
			return {"can": false, "reason_code": "no_blocks_selected", "reason": "请先在地图上选择至少一个区块"}
		for block_id in target_ids:
			var block := GameManager.get_block(block_id)
			if block == null:
				return {"can": false, "reason_code": "block_not_found", "reason": "调查区块不存在：%s" % block_id}
			if GameManager.get_block_understanding(block_id) >= 100.0:
				return {"can": false, "reason_code": "block_already_understood", "reason": "所选区块已完全了解：%s" % block.name}

	var requires_store: bool = (
		action.requires_open_store
		or action.requires_region_selected
		or action.requires_selected_category
		or action.requires_today_has_settled
		or action.requires_store_operating_hour
		or action.action_effect_type == "store_supervision"
	)

	var state: Store = null
	if requires_store:
		state = GameManager.get_store(target_id) if target_id != "" else GameManager.store_state
		if state == null:
			return {"can": false, "reason_code": "no_store", "reason": "没有可操作的店铺，请先完成开店"}

	if action.requires_inspected_storefront:
		if target_id.is_empty():
			return {"can": false, "reason_code": "storefront_not_inspected", "reason": "请先选择需要勘验的门面"}
		var storefront := GameManager.get_storefront(target_id)
		if storefront == null:
			return {"can": false, "reason_code": "storefront_not_found", "reason": "目标门面不存在"}
		var diligence_state: String = GameManager.get_storefront_diligence(target_id)
		if diligence_state == "not_viewed":
			return {"can": false, "reason_code": "storefront_not_inspected", "reason": "请先完成初步看铺，再进行完整尽调"}
		if diligence_state == "full_diligence":
			return {"can": false, "reason_code": "storefront_already_diligent", "reason": "该门面已经完成完整尽调"}

	if action.requires_open_store and not state.is_open:
		return {"can": false, "reason_code": "store_not_open", "reason": "尚未开业，无法安排「%s」" % action.name}

	if action.requires_region_selected and state.selected_region_id == "":
		return {"can": false, "reason_code": "no_region", "reason": "请先选定区域"}

	if action.requires_selected_category and state.category_slots.is_empty():
		return {"can": false, "reason_code": "no_category", "reason": "请先选择经营品类"}

	if action.requires_today_has_settled and not _today_has_settled(state):
		return {"can": false, "reason_code": "no_business_today", "reason": "今天尚未发生任何营业，无法收档复盘"}

	if action.requires_store_operating_hour:
		var check_hour := start_hour
		var end_hour := start_hour + action.duration_hours
		while check_hour < end_hour:
			if not _is_store_operating_at(check_hour, state):
				var next_open := _next_operating_hour_after(check_hour, state)
				var reason := "当前店铺在此时段不营业"
				if next_open >= 0:
					reason += "，下次营业时间为 %02d:00" % next_open
				return {"can": false, "reason_code": "store_not_operating", "reason": reason}
			check_hour += 1

	return {"can": true, "reason_code": "", "reason": ""}

func _is_store_operating_at(hour: int, store: Store = null) -> bool:
	var s := store if store != null else GameManager.store_state
	if s == null or not s.is_open:
		return false
	for cat_slot in s.category_slots:
		if cat_slot.is_open_at_hour(hour):
			return true
	return false


func _next_operating_hour_after(hour: int, store: Store = null) -> int:
	var s := store if store != null else GameManager.store_state
	for offset in range(1, 25):
		var h := (hour + offset) % 24
		if _is_store_operating_at(h, s):
			return h
	return -1


func _today_has_settled(store: Store = null) -> bool:
	var s := store if store != null else GameManager.store_state
	if s == null:
		return false
	var day := TimeManager.current_day
	for entry in s.daily_history:
		if entry.get("day", -1) == day:
			return true
	return false

func add_action_to_schedule(action_id: String, start_hour: int, target_id: String = "") -> Dictionary:
	var check := can_schedule_action(action_id, start_hour, target_id)
	if not check.can:
		return check
	var action := ScheduleActionData.get_action(action_id)
	var entry := today_schedule.add_entry(action_id, start_hour, action.duration_hours)
	entry.target_id = target_id
	schedule_changed.emit()
	return {"can": true, "reason_code": "", "reason": "已加入排程"}


func start_action_now(
		action_id: String,
		target_id: String = "",
		target_ids: Array[String] = []
) -> Dictionary:
	if current_action != null and current_action.is_active:
		return {"can": false, "reason_code": "already_running", "reason": "已经有一个行动正在进行，请先结束它"}

	var current_hour := int(TimeManager.get_hour_of_day())
	var check := can_schedule_action(action_id, current_hour, target_id, target_ids)
	if not check.can:
		return check

	var action := ScheduleActionData.get_action(action_id)
	_begin_current_action(action_id, target_id, target_ids, null)
	TimeManager.set_speed(TimeManager.Speed.X1)
	schedule_changed.emit()
	return {"can": true, "reason_code": "", "reason": "已开始「%s」" % action.name}

func remove_action_from_schedule(hour: int) -> bool:
	var removed := today_schedule.remove_entry_at_hour(hour)
	if removed:
		schedule_changed.emit()
	return removed


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
			_begin_current_action(e.action_id, e.target_id, [], e)
			return


func _begin_current_action(
		action_id: String,
		target_id: String,
		target_ids: Array[String],
		source_entry: ScheduledActionEntry
) -> void:
	current_action = CurrentActionState.new()
	current_action.action_id = action_id
	current_action.target_id = target_id
	current_action.target_ids = target_ids.duplicate()
	current_action.start_game_seconds = TimeManager.total_game_seconds
	current_action.work_hours_before = GameManager.player_state.work_hours_today
	current_action.source_entry = source_entry
	current_action.is_active = true

	var action := ScheduleActionData.get_action(action_id)
	if action.action_effect_type == "store_supervision":
		var supervised_store_id := target_id if target_id != "" else GameManager.active_store_id
		GameManager.player_state.supervising_store_id = supervised_store_id

func _finalize_current_action(elapsed_hours: float) -> void:
	var action := ScheduleActionData.get_action(current_action.action_id)
	var player := GameManager.player_state

	## 目标失效检查：不追溯撤销已经发生的效果，只是提前收尾并记录原因。
	var precondition := _check_preconditions(
		action,
		int(TimeManager.get_hour_of_day()),
		current_action.target_id,
		current_action.target_ids
	)

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

				if action.action_effect_type == "region_research":
					var block_effect_result := _apply_region_research_effect(
						current_action.target_ids, elapsed_hours
					)
					if not block_effect_result.is_empty() and not block_effect_result.success:
						final_status = "failed"
						failure_reason = block_effect_result.reason
				elif current_action.target_id != "":
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
## region_research → Phase 2 使用target_ids中的Block ID
## storefront_inspection / deep_inspection → storefront_id

func _apply_understanding_effect(effect_type: String, target_id: String, elapsed_hours: float) -> Dictionary:
	match effect_type:
		"deep_inspection":
			return GameManager.advance_storefront_diligence(target_id, "full_diligence")
		_:
			return {}


func _apply_region_research_effect(block_ids: Array[String], elapsed_hours: float) -> Dictionary:
	if block_ids.is_empty():
		return {"success": false, "reason": "没有选择调查区块"}

	var gain := RegionConfig.FAMILIARITY_GAIN_PER_HOUR * elapsed_hours
	var applied := false
	var affected_city_regions: Dictionary = {}

	for block_id in block_ids:
		var block := GameManager.get_block(block_id)
		if block == null:
			continue
		var current := GameManager.get_block_understanding(block_id)
		if current >= 100.0:
			continue
		GameManager.advance_block_understanding(block_id, gain)
		affected_city_regions[block.city_region_id] = true
		applied = true

	if not applied:
		return {"success": false, "reason": "所选区块均已完全了解或不存在"}

	for city_region_id in affected_city_regions.keys():
		GameManager.recalculate_region_intel(str(city_region_id))

	return {"success": true, "reason": "所选区块调查进度已更新"}
