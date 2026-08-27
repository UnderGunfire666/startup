extends Node

signal schedule_changed
signal hour_effect_applied(action_id: String, elapsed_hours: float, progress_ratio: float, effect_mult: float)
signal action_completed(action_id: String, elapsed_hours: float, duration_hours: int)
signal action_interrupt(reason_code: String, message: String)
signal day_schedule_ended(day: int)
signal map_block_selection_changed(block_ids: Array[String])

var today_schedule: DaySchedule = DaySchedule.new()
var completed_entries_today: Array[ScheduledActionEntry] = []
var current_action: CurrentActionState = null
const RESEARCH_FOCUS_ALL := "all"
var selected_research_focus: String = RESEARCH_FOCUS_ALL
## A stable X1 simulation quantum used by both UI availability and launch checks.
const REGION_RESEARCH_START_QUANTUM_GAME_SECONDS := 2.0
const REGION_RESEARCH_DISCOVERY_MIN_INTERVAL_SECONDS := 8.0 * 60.0
const REGION_RESEARCH_DISCOVERY_MAX_INTERVAL_SECONDS := 18.0 * 60.0

var operating_hours_today: int = 0
var supervising_hours_today: int = 0
## 地图面板的瞬时选择，仅作为行动目标，不属于存档或玩家知识。
var selected_map_block_ids: Array[String] = []

func _ready() -> void:
	TimeManager.hour_advanced.connect(_on_hour_tick)

func reset_for_new_game() -> void:
	today_schedule = DaySchedule.new()
	completed_entries_today.clear()
	current_action = null
	selected_research_focus = RESEARCH_FOCUS_ALL
	operating_hours_today = 0
	supervising_hours_today = 0
	selected_map_block_ids.clear()
	map_block_selection_changed.emit([])


func set_selected_map_block_ids(block_ids: Array[String]) -> void:
	var valid_ids: Array[String] = []
	for block_id in block_ids:
		if not valid_ids.has(block_id) and GameManager.get_block(block_id) != null:
			valid_ids.append(block_id)
	if selected_map_block_ids == valid_ids:
		return
	selected_map_block_ids = valid_ids
	map_block_selection_changed.emit(selected_map_block_ids.duplicate())


func get_selected_move_target_id() -> String:
	return selected_map_block_ids[0] if not selected_map_block_ids.is_empty() else ""

func _on_hour_tick(day: int, hour: int) -> void:
	if current_action != null and current_action.is_active and current_action.continuous_mode:
		_advance_continuous_action_to_elapsed()

	if hour == 0:
		if current_action != null and current_action.is_active and current_action.continuous_mode:
			_finalize_current_action(current_action.applied_hours)
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
	if action.action_effect_type == "move_to_block" and target_id.is_empty():
		target_id = get_selected_move_target_id()
	if action.action_effect_type == "move_to_block" and target_id.is_empty():
		return {"can": false, "reason_code": "no_move_target", "reason": "请先在地图上选择要前往的区块"}

	var duration_hours := _get_effective_duration_hours(action, target_ids, start_hour, target_id)
	if action.action_effect_type == "move_to_block" and target_id == GameManager.player_state.current_block_id:
		return {"can": true, "reason_code": "", "reason": "已经位于目标区块", "duration_hours": 0.0}

	var duration_for_schedule := int(ceil(duration_hours))
	if duration_for_schedule < 0:
		return {"can": false, "reason_code": "invalid_duration", "reason": "行动耗时无效"}

	if action.action_effect_type != "region_research":
		if start_hour < action.allowed_hour_range.x or (start_hour + duration_for_schedule) > action.allowed_hour_range.y:
			return {"can": false, "reason_code": "outside_allowed_hours", "reason": "%s仅可在%02d:00至%02d:00之间安排" % [action.name, action.allowed_hour_range.x, action.allowed_hour_range.y]}
	else:
		if start_hour < action.allowed_hour_range.x or start_hour >= action.allowed_hour_range.y:
			return {"can": false, "reason_code": "outside_allowed_hours", "reason": "%s仅可在%02d:00至%02d:00之间开始" % [action.name, action.allowed_hour_range.x, action.allowed_hour_range.y]}

	if duration_for_schedule > 0 and today_schedule.has_conflict(start_hour, duration_for_schedule):
		return {"can": false, "reason_code": "time_conflict", "reason": "该时间已被其他行动占用，或超出当天24点"}
	var precondition := _check_preconditions(action, start_hour, target_id, target_ids, true)
	if not precondition.can:
		return precondition
	return {
		"can": true,
		"reason_code": "",
		"reason": "",
		"duration_hours": duration_hours,
	}

func get_region_research_minimum_start_energy() -> float:
	var action := ScheduleActionData.get_action("region_research")
	if action == null:
		return INF
	var fatigue_tier := ScheduleConfig.get_fatigue_tier(GameManager.player_state.work_hours_today)
	var energy_mult := float(fatigue_tier.get("energy_mult", 1.0))
	return action.base_energy_cost_per_hour * REGION_RESEARCH_START_QUANTUM_GAME_SECONDS / 3600.0 * energy_mult


func get_region_research_start_energy_check() -> Dictionary:
	var required_energy := get_region_research_minimum_start_energy()
	var player := GameManager.player_state
	var has_debt := player.energy_debt > 0.0
	var can_pay_quantum := player.energy >= required_energy
	if has_debt or not can_pay_quantum:
		return {
			"can": false,
			"reason_code": "energy_insufficient",
			"reason": "精力不足，无法开始调查",
			"required_energy": required_energy,
		}
	return {
		"can": true,
		"reason_code": "",
		"reason": "",
		"required_energy": required_energy,
	}


func _get_effective_duration_hours(
		action: ActionDefinition,
		target_ids: Array[String],
		start_hour: int = -1,
		target_id: String = ""
) -> float:
	if action.action_effect_type == "region_research":
		if start_hour >= 0:
			return float(maxi(1, action.allowed_hour_range.y - start_hour))
		return float(action.duration_hours)

	if action.action_effect_type == "move_to_block":
		return _get_move_to_block_duration_hours(target_id)
	if target_ids.is_empty():
		return float(action.duration_hours)

	var blocks: Array[BlockData] = []
	for block_id in target_ids:
		var block := GameManager.get_block(block_id)
		if block != null:
			blocks.append(block)
	return float(BlockConfig.get_research_duration_hours(action.duration_hours, blocks))

func _get_move_to_block_duration_hours(target_block_id: String) -> float:
	if target_block_id.is_empty():
		return -1.0
	var target_block := GameManager.get_block(target_block_id)
	if target_block == null:
		return -1.0
	var current_block_id := GameManager.player_state.current_block_id
	if current_block_id.is_empty():
		## 首次从地图选择目的地时，该目的地就是玩家明确选择的初始位置。
		return 0.0
	var current_block := GameManager.get_block(current_block_id)
	if current_block == null:
		return -1.0
	return MovementConfig.get_travel_hours(current_block, target_block, GameManager.road_graph)

func _check_preconditions(
		action: ActionDefinition,
		start_hour: int,
		target_id: String = "",
		target_ids: Array[String] = [],
		reject_completed_blocks: bool = false
) -> Dictionary:
	if action.action_effect_type == "move_to_block":
		if target_id.is_empty():
			return {"can": false, "reason_code": "no_move_target", "reason": "请先选择要前往的区块"}
		var move_target := GameManager.get_block(target_id)
		if move_target == null:
			return {"can": false, "reason_code": "block_not_found", "reason": "目标区块不存在：%s" % target_id}
		if GameManager.player_state.current_block_id == target_id:
			return {"can": true, "reason_code": "", "reason": "已经位于目标区块"}
		if GameManager.player_state.current_block_id.is_empty():
			return {"can": true, "reason_code": "", "reason": "将以目标区块作为初始位置"}

	if action.action_effect_type == "region_research":
		if target_ids.is_empty():
			return {"can": false, "reason_code": "no_blocks_selected", "reason": "请先在地图上选择至少一个区块"}
		var has_researchable_block := false
		for block_id in target_ids:
			var block := GameManager.get_block(block_id)
			if block == null:
				return {"can": false, "reason_code": "block_not_found", "reason": "调查区块不存在：%s" % block_id}
			if not GameManager.is_block_research_complete(block_id):
				has_researchable_block = true
			elif reject_completed_blocks:
				return {"can": false, "reason_code": "block_already_understood", "reason": "所选区块已完全了解：%s" % block.name}
		if not has_researchable_block:
			return {"can": false, "reason_code": "all_blocks_complete", "reason": "所选区块都已经完全了解"}
		var energy_check := get_region_research_start_energy_check()
		if not bool(energy_check.get("can", false)):
			return energy_check

		var current_block_id := GameManager.player_state.current_block_id
		if current_block_id.is_empty():
			return {"can": true, "reason_code": "", "reason": "将以首个调查区块作为初始位置"}
		if current_block_id != target_ids[0]:
			var current_block := GameManager.get_block(current_block_id)
			var target_block := GameManager.get_block(target_ids[0])
			var current_name := current_block.name if current_block != null else current_block_id
			var target_name := target_block.name if target_block != null else target_ids[0]
			return {"can": false, "reason_code": "player_not_at_target_block", "reason": "当前位于「%s」，请先前往「%s」" % [current_name, target_name]}

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

	if action.action_effect_type in ["visit_storefront", "observe_storefront", "order_storefront"]:
		var storefront := GameManager.get_storefront(target_id)
		if storefront == null:
			return {"can": false, "reason_code": "storefront_not_found", "reason": "目标门面不存在"}
		if GameManager.player_state.current_block_id != storefront.block_id:
			return {"can": false, "reason_code": "player_not_at_target_block", "reason": "请先前往门面所在区块"}
		var intel := GameManager.get_storefront_intel(target_id)
		if action.action_effect_type == "visit_storefront" and bool(intel.get("visited", false)):
			return {"can": false, "reason_code": "already_visited", "reason": "这间门面已经到访过"}
		if action.action_effect_type != "visit_storefront":
			if not bool(intel.get("visited", false)):
				return {"can": false, "reason_code": "storefront_not_visited", "reason": "请先到访这间门面"}
			var npc_store := GameManager.get_npc_store_for_storefront(target_id)
			if npc_store == null or not npc_store.is_business_open:
				return {"can": false, "reason_code": "storefront_not_operating", "reason": "这间门面当前没有可观察的营业店铺"}
			if action.action_effect_type == "order_storefront" and not bool(intel.get("menu_reviewed", false)):
				return {"can": false, "reason_code": "menu_not_reviewed", "reason": "请先查看菜单"}

	if action.requires_open_store and not state.is_open:
		return {"can": false, "reason_code": "store_not_open", "reason": "尚未开业，无法安排「%s」" % action.name}
	## requires_region_selected语义已从"已选定区域"(旧RegionData体系)改为
	## "已选定门面"（StorefrontData就是当前唯一的地理归属来源）。
	if action.requires_region_selected and state.selected_storefront_id == "":
		return {"can": false, "reason_code": "no_storefront", "reason": "请先选定门面"}
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
	return s.is_planned_open_at_hour(hour)

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
	var action := ScheduleActionData.get_action(action_id)
	if action != null and action.action_effect_type == "move_to_block" and target_id.is_empty():
		target_id = get_selected_move_target_id()
	var check := can_schedule_action(action_id, start_hour, target_id)
	if not check.can:
		return check
	var entry := today_schedule.add_entry(action_id, start_hour, int(ceil(float(check.duration_hours))))
	entry.target_id = target_id
	schedule_changed.emit()
	return {"can": true, "reason_code": "", "reason": "已加入排程"}

func start_action_now(
		action_id: String,
		target_id: String = "",
		target_ids: Array[String] = [],
		context: Dictionary = {}
) -> Dictionary:
	if current_action != null and current_action.is_active:
		return {"can": false, "reason_code": "already_running", "reason": "已经有一个行动正在进行，请先结束它"}
	var action := ScheduleActionData.get_action(action_id)
	if action != null and action.action_effect_type == "deep_inspection" and GameManager.get_storefront_diligence_progress(target_id) >= 100.0 - 0.0001:
		return {"can": false, "reason_code": "storefront_already_diligent", "reason": "该门面已经完成完整尽调"}
	if action != null and action.action_effect_type == "move_to_block" and target_id.is_empty():
		target_id = get_selected_move_target_id()
	var current_hour := int(TimeManager.get_hour_of_day())
	var check := can_schedule_action(action_id, current_hour, target_id, target_ids)
	if not check.can:
		return check
	_begin_current_action(action_id, target_id, target_ids, null, current_hour, context)
	if action.action_effect_type == "move_to_block" and float(check.duration_hours) <= 0.0:
		_finalize_current_action(0.0)
		return {"can": true, "reason_code": "", "reason": "已位于目标区块，无需移动", "duration_hours": 0.0}
	TimeManager.set_speed(TimeManager.Speed.X1)
	schedule_changed.emit()
	if action.action_effect_type == "region_research":
		return {"can": true, "reason_code": "", "reason": "已开始「%s」，将持续调查直到区块全部了解、精力不足或到达 %02d:00" % [action.name, action.allowed_hour_range.y], "duration_hours": check.duration_hours}
	if action.action_effect_type == "deep_inspection":
		return {"can": true, "reason_code": "", "reason": "已开始「%s」，将持续勘验直到完成或精力不足" % action.name, "duration_hours": check.duration_hours}
	return {"can": true, "reason_code": "", "reason": "已开始「%s」，预计耗时 %.2f 小时" % [action.name, float(check.duration_hours)], "duration_hours": check.duration_hours}

func remove_action_from_schedule(hour: int) -> bool:
	var removed := today_schedule.remove_entry_at_hour(hour)
	if removed:
		schedule_changed.emit()
	return removed

func stop_current_action() -> void:
	if current_action == null or not current_action.is_active:
		return
	current_action.stopped_by_player = true
	var elapsed_hours: float = (TimeManager.total_game_seconds - current_action.start_game_seconds) / 3600.0
	if current_action.continuous_mode:
		_advance_continuous_action_to_elapsed(elapsed_hours)
		if current_action == null or not current_action.is_active:
			return
	_finalize_current_action(elapsed_hours)


func set_region_research_focus(focus_id: String) -> bool:
	if focus_id != RESEARCH_FOCUS_ALL and not GameManager.BLOCK_RESEARCH_FOCUSES.has(focus_id):
		return false
	selected_research_focus = focus_id
	if current_action != null and current_action.is_active and current_action.action_id == "region_research":
		current_action.research_focus = focus_id
		schedule_changed.emit()
	return true

func tick() -> void:
	if current_action != null and current_action.is_active:
		var elapsed_hours: float = (TimeManager.total_game_seconds - current_action.start_game_seconds) / 3600.0
		if current_action.continuous_mode:
			_advance_continuous_action_to_elapsed(elapsed_hours)
			if current_action == null or not current_action.is_active:
				return
			if current_action.action_id == "region_research" and TimeManager.get_current_hour_int() >= _get_region_research_end_hour():
				_finalize_current_action(current_action.applied_hours)
				return
		elif elapsed_hours >= current_action.duration_hours - 0.0001:
			_finalize_current_action(current_action.duration_hours)
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
			_begin_current_action(e.action_id, e.target_id, [], e, current_hour)
			return

func _begin_current_action(
		action_id: String,
		target_id: String,
		target_ids: Array[String],
		source_entry: ScheduledActionEntry,
	start_hour: int = -1,
	context: Dictionary = {}
) -> void:
	current_action = CurrentActionState.new()
	current_action.action_id = action_id
	current_action.target_id = target_id
	current_action.target_ids = target_ids.duplicate()
	current_action.start_game_seconds = TimeManager.total_game_seconds
	current_action.work_hours_before = GameManager.player_state.work_hours_today
	current_action.source_entry = source_entry
	current_action.is_active = true
	current_action.research_focus = selected_research_focus
	current_action.context = context.duplicate(true)

	var action := ScheduleActionData.get_action(action_id)
	if action.action_effect_type == "region_research" and GameManager.player_state.current_block_id.is_empty() and not target_ids.is_empty():
		GameManager.player_state.set_current_block(target_ids[0])
	if action.action_effect_type == "region_research":
		current_action.continuous_mode = true
		var research_start := start_hour if start_hour >= 0 else TimeManager.get_current_hour_int()
		current_action.duration_hours = float(maxi(1, action.allowed_hour_range.y - research_start))
		_schedule_next_region_research_discovery_check(TimeManager.total_game_seconds)
	elif action.action_effect_type == "deep_inspection":
		current_action.continuous_mode = true
		current_action.duration_hours = _get_effective_duration_hours(action, [], start_hour, target_id)
	elif action.action_effect_type == "move_to_block":
		current_action.duration_hours = _get_move_to_block_duration_hours(target_id)
		current_action.continuous_mode = false
	else:
		current_action.duration_hours = _get_effective_duration_hours(action, target_ids)
	if action.action_effect_type == "store_supervision":
		var supervised_store_id := target_id if target_id != "" else GameManager.active_store_id
		GameManager.player_state.supervising_store_id = supervised_store_id

func _get_region_research_end_hour() -> int:
	var action := ScheduleActionData.get_action("region_research")
	return action.allowed_hour_range.y if action != null else 24

func _get_region_research_required_hours(block: BlockData) -> float:
	if block == null:
		return 0.0
	var action := ScheduleActionData.get_action("region_research")
	if action == null:
		return 0.0
	var blocks: Array[BlockData] = [block]
	return float(BlockConfig.get_research_duration_hours(action.duration_hours, blocks))

func _get_region_research_hourly_gain(block: BlockData) -> float:
	var required_hours := _get_region_research_required_hours(block)
	if required_hours <= 0.0:
		return 0.0
	return 100.0 / required_hours


func _advance_continuous_action_to_elapsed(target_elapsed_hours: float = -1.0) -> void:
	if current_action == null or not current_action.is_active:
		return
	match current_action.action_id:
		"region_research":
			_advance_continuous_region_research_to_elapsed(target_elapsed_hours)
		"deep_inspection":
			_advance_continuous_deep_inspection_to_elapsed(target_elapsed_hours)


func _advance_continuous_region_research_to_elapsed(target_elapsed_hours: float = -1.0) -> void:
	if current_action == null or not current_action.is_active or current_action.action_id != "region_research":
		return
	if target_elapsed_hours < 0.0:
		target_elapsed_hours = (TimeManager.total_game_seconds - current_action.start_game_seconds) / 3600.0
	var delta_hours := maxf(0.0, target_elapsed_hours - current_action.applied_hours)
	if delta_hours <= 0.0001:
		return
	if not _ensure_region_research_can_progress():
		_finalize_current_action(current_action.applied_hours)
		return

	var action := ScheduleActionData.get_action(current_action.action_id)
	if action == null:
		return

	var segments := ScheduleConfig.split_duration_by_fatigue_tiers(
		current_action.work_hours_before + current_action.applied_hours,
		delta_hours
	)
	var total_cost := 0.0
	var weighted_effect_mult := 0.0
	for seg in segments:
		total_cost += action.base_energy_cost_per_hour * seg.hours * seg.energy_mult
		weighted_effect_mult += seg.effect_mult * seg.hours

	if total_cost > GameManager.player_state.energy + 0.0001:
		## The current frame cannot be paid in full. This is an exhaustion stop,
		## so consume the unusable remainder without creating energy debt. Leaving
		## a small positive remainder here would make the map enable research again.
		GameManager.player_state.apply_energy_delta(-GameManager.player_state.energy)
		_finalize_current_action(current_action.applied_hours)
		action_interrupt.emit("energy_insufficient", "笔记上的字开始重影，你已经无法从街面再辨出新的线索；这次调查只能先停在这里。")
		return

	GameManager.player_state.apply_energy_delta(-total_cost)
	GameManager.player_state.work_hours_today += delta_hours
	GameManager.player_state.fatigue_state = ScheduleConfig.get_fatigue_tier(GameManager.player_state.work_hours_today).state

	if delta_hours > 0.0:
		weighted_effect_mult /= delta_hours
		hour_effect_applied.emit(action.id, delta_hours, 1.0, weighted_effect_mult)
		var block_effect_result := _advance_region_research_with_discovery_checks(delta_hours)
		if not block_effect_result.success:
			_finalize_current_action(current_action.applied_hours)
			return
		current_action.applied_hours += delta_hours
		schedule_changed.emit()

	if _all_region_research_blocks_complete(current_action.target_ids):
		_finalize_current_action(current_action.applied_hours)
		return
	if TimeManager.get_current_hour_int() >= _get_region_research_end_hour():
		_finalize_current_action(current_action.applied_hours)


func _schedule_next_region_research_discovery_check(after_game_seconds: float) -> void:
	if current_action == null:
		return
	current_action.next_discovery_check_game_seconds = after_game_seconds + randf_range(
		REGION_RESEARCH_DISCOVERY_MIN_INTERVAL_SECONDS,
		REGION_RESEARCH_DISCOVERY_MAX_INTERVAL_SECONDS)


func _advance_region_research_with_discovery_checks(delta_hours: float) -> Dictionary:
	if current_action == null:
		return {"success": false, "reason": "没有进行中的区域调研"}
	var start_time := current_action.start_game_seconds + current_action.applied_hours * 3600.0
	var end_time := start_time + delta_hours * 3600.0
	var cursor := start_time
	while cursor < end_time - 0.0001:
		if current_action.next_discovery_check_game_seconds <= cursor + 0.0001:
			_schedule_next_region_research_discovery_check(cursor)
		var check_time := current_action.next_discovery_check_game_seconds
		var segment_end := minf(end_time, check_time)
		var segment_hours := (segment_end - cursor) / 3600.0
		var check_interval_seconds := maxf(0.0, segment_end - cursor)
		var progress_result: Dictionary = {"success": true, "advanced_focuses_by_block": {}}
		if segment_hours > 0.000001:
			progress_result = _apply_region_research_effect_continuous(current_action.target_ids, segment_hours, false)
			if not progress_result.success:
				return progress_result
		cursor = segment_end
		if cursor >= check_time - 0.0001:
			_evaluate_region_research_discoveries(progress_result.get("advanced_focuses_by_block", {}), check_time, check_interval_seconds)
			_schedule_next_region_research_discovery_check(check_time)
	return {"success": true, "reason": "区域调研进度已更新"}


func _evaluate_region_research_discoveries(advanced_focuses_by_block: Dictionary, check_time: float, interval_seconds: float) -> void:
	for block_id in advanced_focuses_by_block.keys():
		var focuses: Array = advanced_focuses_by_block[block_id]
		if focuses.is_empty():
			continue
		var focus_id := str(focuses.pick_random())
		BlockDiscoveryManager.evaluate_research(str(block_id), -1.0, check_time, interval_seconds, focus_id)
		EventManager.try_research_discovery(str(block_id), focus_id)


func _advance_continuous_deep_inspection_to_elapsed(target_elapsed_hours: float = -1.0) -> void:
	if current_action == null or not current_action.is_active or current_action.action_id != "deep_inspection":
		return
	## 防御旧存档或浮点边界：100% 即使未及时写入尽调状态，也必须立即完成并停止。
	if GameManager.get_storefront_diligence_progress(current_action.target_id) >= 100.0 - 0.0001:
		if GameManager.get_storefront_diligence(current_action.target_id) != "full_diligence":
			GameManager.advance_storefront_diligence(current_action.target_id, "full_diligence")
		_finalize_current_action(current_action.applied_hours)
		return
	if target_elapsed_hours < 0.0:
		target_elapsed_hours = (TimeManager.total_game_seconds - current_action.start_game_seconds) / 3600.0
	var delta_hours := minf(
		maxf(0.0, target_elapsed_hours - current_action.applied_hours),
		maxf(0.0, current_action.duration_hours - current_action.applied_hours)
	)
	if delta_hours <= 0.0001:
		return

	var action := ScheduleActionData.get_action(current_action.action_id)
	if action == null:
		return
	var segments := ScheduleConfig.split_duration_by_fatigue_tiers(
		current_action.work_hours_before + current_action.applied_hours,
		delta_hours
	)
	var total_cost := 0.0
	var weighted_effect_mult := 0.0
	for seg in segments:
		total_cost += action.base_energy_cost_per_hour * seg.hours * seg.energy_mult
		weighted_effect_mult += seg.effect_mult * seg.hours
	if total_cost > GameManager.player_state.energy + 0.0001:
		_finalize_current_action(current_action.applied_hours)
		action_interrupt.emit("energy_insufficient", "你还没把门面细节逐一核完，注意力却已经撑不住了；深度勘验需要留到恢复之后。")
		return

	GameManager.player_state.apply_energy_delta(-total_cost)
	GameManager.player_state.work_hours_today += delta_hours
	GameManager.player_state.fatigue_state = ScheduleConfig.get_fatigue_tier(GameManager.player_state.work_hours_today).state
	current_action.applied_hours += delta_hours
	weighted_effect_mult /= delta_hours
	var gain_per_hour := 100.0 / maxf(0.0001, current_action.duration_hours)
	var progress_result := GameManager.advance_storefront_diligence_progress(
		current_action.target_id,
		gain_per_hour * delta_hours
	)
	hour_effect_applied.emit(action.id, delta_hours, 1.0, weighted_effect_mult)
	if not progress_result.success:
		_finalize_current_action(current_action.applied_hours)
		return
	if float(progress_result.progress) >= 100.0 - 0.0001:
		var completion_result := GameManager.advance_storefront_diligence(current_action.target_id, "full_diligence")
		if not completion_result.success:
			_finalize_current_action(current_action.applied_hours)
			return
		_finalize_current_action(current_action.applied_hours)
		return
	schedule_changed.emit()

func _all_region_research_blocks_complete(block_ids: Array[String]) -> bool:
	if block_ids.is_empty():
		return true
	for block_id in block_ids:
		if not GameManager.is_block_research_complete(block_id):
			return false
	return true


func _get_researchable_focuses(block_id: String, requested_focus: String) -> Array[String]:
	var focuses: Array[String] = []
	if requested_focus == RESEARCH_FOCUS_ALL:
		for focus_id in GameManager.BLOCK_RESEARCH_FOCUSES:
			if GameManager.get_block_research_progress(block_id, focus_id) < 100.0 - 0.0001:
				focuses.append(focus_id)
	elif GameManager.get_block_research_progress(block_id, requested_focus) < 100.0 - 0.0001:
		focuses.append(requested_focus)
	return focuses


func _ensure_region_research_can_progress() -> bool:
	if current_action == null or current_action.action_id != "region_research":
		return false
	for block_id in current_action.target_ids:
		if not _get_researchable_focuses(block_id, current_action.research_focus).is_empty():
			return true
	if current_action.research_focus != RESEARCH_FOCUS_ALL and not _all_region_research_blocks_complete(current_action.target_ids):
		_switch_region_research_to_all()
		return true
	return false


func _switch_region_research_to_all() -> void:
	if current_action == null or current_action.research_focus == RESEARCH_FOCUS_ALL:
		return
	current_action.research_focus = RESEARCH_FOCUS_ALL
	selected_research_focus = RESEARCH_FOCUS_ALL
	schedule_changed.emit()

func _finalize_current_action(elapsed_hours: float) -> void:
	if current_action == null or not current_action.is_active:
		return
	var action := ScheduleActionData.get_action(current_action.action_id)
	var player := GameManager.player_state
	var is_continuous_action := current_action.continuous_mode
	var precondition := _check_preconditions(
		action,
		int(TimeManager.get_hour_of_day()),
		current_action.target_id,
		current_action.target_ids,
		false
	)

	var final_status := "stopped" if current_action.stopped_by_player else "completed"
	var failure_reason := "玩家手动停止行动" if current_action.stopped_by_player else ""

	if is_continuous_action:
		elapsed_hours = minf(elapsed_hours, current_action.applied_hours)
	else:
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

		if precondition.can:
			match action.effect_scaling:
				"proportional":
					var progress_ratio := 0.0
					if current_action.duration_hours > 0.0:
						progress_ratio = elapsed_hours / current_action.duration_hours
					hour_effect_applied.emit(action.id, elapsed_hours, progress_ratio, weighted_effect_mult)
					if action.action_effect_type == "move_to_block":
						if current_action.target_id != "" and GameManager.get_block(current_action.target_id) != null:
							GameManager.player_state.set_current_block(current_action.target_id)
					elif action.action_effect_type == "region_research":
						var block_effect_result := _apply_region_research_effect(current_action.target_ids, elapsed_hours)
						if not block_effect_result.is_empty() and not block_effect_result.success:
							final_status = "failed"
							failure_reason = block_effect_result.reason
					elif current_action.target_id != "":
						var effect_result := _apply_understanding_effect(action.action_effect_type, current_action.target_id, elapsed_hours)
						if not effect_result.is_empty() and not effect_result.success:
							final_status = "failed"
							failure_reason = effect_result.reason
				"binary":
					if elapsed_hours >= current_action.duration_hours - 0.0001:
						action_completed.emit(action.id, elapsed_hours, int(current_action.duration_hours))

	## 深度勘验抵达 100% 后会先写入完整尽调，再在这里收尾；这不是失败。
	if current_action.action_id == "deep_inspection" and GameManager.get_storefront_diligence(current_action.target_id) == "full_diligence":
		precondition = {"can": true, "reason_code": "", "reason": ""}
		final_status = "completed"
		failure_reason = ""
	if current_action.action_id == "region_research" and _all_region_research_blocks_complete(current_action.target_ids):
		final_status = "completed"
		failure_reason = ""
	if not precondition.can and not (current_action.action_id == "region_research" and _all_region_research_blocks_complete(current_action.target_ids)):
		final_status = "failed"
		failure_reason = precondition.reason

	var record: ScheduledActionEntry = current_action.source_entry
	if record == null:
		record = ScheduledActionEntry.new()
	record.action_id = current_action.action_id
	record.start_hour = int((current_action.start_game_seconds / 3600.0) as float) % 24
	record.duration_hours = int(ceil(current_action.duration_hours))
	record.target_id = current_action.target_id
	record.hours_completed = elapsed_hours
	record.status = final_status
	record.failure_reason = failure_reason
	completed_entries_today.append(record)
	if final_status == "completed" and not current_action.stopped_by_player and current_action.action_id == "landlord_negotiation":
		EventManager.start_landlord_terms_chain(GameManager.active_store_id)
	elif final_status == "completed" and not current_action.stopped_by_player:
		var storefront_result: Dictionary = {}
		match current_action.action_id:
			"visit_storefront":
				storefront_result = GameManager.visit_storefront(current_action.target_id)
			"observe_storefront":
				storefront_result = GameManager.record_storefront_observation(current_action.target_id)
			"order_storefront":
				storefront_result = GameManager.order_storefront_product(current_action.target_id, str(current_action.context.get("product_id", "")))
		if not storefront_result.is_empty() and not bool(storefront_result.get("success", false)):
			final_status = "failed"
			failure_reason = str(storefront_result.get("reason", "行动未能完成"))
		record.status = final_status
		record.failure_reason = failure_reason
	current_action = null

	if player.energy <= 0.0 and player.energy_debt > 0.0:
		action_interrupt.emit("energy_exhausted", "今天能挤出的精力已经用尽，连下一步该看什么都开始模糊。继续硬撑只会让判断失去分寸。")
	## 所有行动的结束都是时间流逝的明确停止点，包括玩家手动结束。
	TimeManager.set_speed(TimeManager.Speed.PAUSED)
	schedule_changed.emit()

func _apply_understanding_effect(effect_type: String, target_id: String, elapsed_hours: float) -> Dictionary:
	match effect_type:
		"deep_inspection":
			return GameManager.advance_storefront_diligence(target_id, "full_diligence")
		_:
			return {}

func _apply_region_research_effect(block_ids: Array[String], elapsed_hours: float) -> Dictionary:
	if block_ids.is_empty():
		return {"success": false, "reason": "没有选择调查区块"}
	if current_action != null and current_action.action_id == "region_research":
		return _apply_region_research_effect_continuous(block_ids, elapsed_hours)

	var gain := RegionConfig.FAMILIARITY_GAIN_PER_HOUR * elapsed_hours
	var applied := false
	var affected_city_regions: Dictionary = {}
	for block_id in block_ids:
		var block := GameManager.get_block(block_id)
		if block == null:
			continue
		var current := GameManager.get_block_research_progress(block_id, current_action.research_focus)
		if current >= 100.0:
			continue
		GameManager.advance_block_research_progress(block_id, current_action.research_focus, gain)
		BlockDiscoveryManager.evaluate_research(block_id, -1.0, -1.0, 3600.0, current_action.research_focus)
		EventManager.try_research_discovery(block_id)
		affected_city_regions[block.city_region_id] = true
		applied = true

	if not applied:
		return {"success": false, "reason": "所选区块均已完全了解或不存在"}
	for city_region_id in affected_city_regions.keys():
		GameManager.recalculate_region_intel(str(city_region_id))
	return {"success": true, "reason": "所选区块调查进度已更新"}

func _apply_region_research_effect_continuous(block_ids: Array[String], elapsed_hours: float, evaluate_discoveries: bool = true) -> Dictionary:
	if block_ids.is_empty():
		return {"success": false, "reason": "没有选择调查区块"}

	var active_blocks: Array[BlockData] = []
	var affected_city_regions: Dictionary = {}
	for block_id in block_ids:
		var block := GameManager.get_block(block_id)
		if block == null:
			continue
		if not _get_researchable_focuses(block_id, current_action.research_focus).is_empty():
			active_blocks.append(block)

	if active_blocks.is_empty():
		return {"success": false, "reason": "所选区块均已完全了解或不存在"}

	## 调查能力按仍可推进的区块平均分配。同步模式再将每个区块的份额均分给其
	## 未完成方面；完成方面的份额会在同一区块内即时重新分配。
	var throughput_per_hour := 0.0
	for block in active_blocks:
		throughput_per_hour += _get_region_research_hourly_gain(block)
	var remaining_work: float = throughput_per_hour * elapsed_hours
	var advanced_focuses_by_block: Dictionary = {}
	while remaining_work > 0.0001 and not active_blocks.is_empty():
		var share: float = remaining_work / float(active_blocks.size())
		var used_work: float = 0.0
		for block in active_blocks:
			var advanced: Dictionary = _apply_block_research_work(block.id, share, current_action.research_focus)
			used_work += float(advanced.get("used_work", 0.0))
			var advanced_focuses: Array[String] = advanced.get("focuses", [])
			if not advanced_focuses.is_empty():
				advanced_focuses_by_block[block.id] = advanced_focuses
			if evaluate_discoveries:
				var focus_id: String = str(advanced_focuses.pick_random()) if not advanced_focuses.is_empty() else ""
				if not focus_id.is_empty():
					BlockDiscoveryManager.evaluate_research(block.id, -1.0, -1.0, 3600.0, focus_id)
					EventManager.try_research_discovery(block.id, focus_id)
			affected_city_regions[block.city_region_id] = true
		if used_work <= 0.0001:
			break
		remaining_work -= used_work
		for index in range(active_blocks.size() - 1, -1, -1):
			if _get_researchable_focuses(active_blocks[index].id, current_action.research_focus).is_empty():
				active_blocks.remove_at(index)
		if active_blocks.is_empty() and remaining_work > 0.0001 \
				and current_action.research_focus != RESEARCH_FOCUS_ALL \
				and not _all_region_research_blocks_complete(block_ids):
			_switch_region_research_to_all()
			for block_id in block_ids:
				var remaining_block: BlockData = GameManager.get_block(block_id)
				if remaining_block != null and not _get_researchable_focuses(block_id, current_action.research_focus).is_empty():
					active_blocks.append(remaining_block)
	for city_region_id in affected_city_regions.keys():
		GameManager.recalculate_region_intel(str(city_region_id))
	return {"success": true, "reason": "所选区块调查进度已更新", "advanced_focuses_by_block": advanced_focuses_by_block}


func _apply_block_research_work(block_id: String, work: float, requested_focus: String) -> Dictionary:
	var remaining_work := maxf(0.0, work)
	var advanced_focuses: Array[String] = []
	while remaining_work > 0.0001:
		var focuses := _get_researchable_focuses(block_id, requested_focus)
		if focuses.is_empty():
			break
		var share := remaining_work / float(focuses.size())
		var smallest_remaining := INF
		for focus_id in focuses:
			smallest_remaining = minf(smallest_remaining, 100.0 - GameManager.get_block_research_progress(block_id, focus_id))
		var gain := minf(share, smallest_remaining)
		if gain <= 0.0001:
			break
		for focus_id in focuses:
			GameManager.advance_block_research_progress(block_id, focus_id, gain)
			if not advanced_focuses.has(focus_id):
				advanced_focuses.append(focus_id)
		remaining_work -= gain * float(focuses.size())
	return {"used_work": work - remaining_work, "focuses": advanced_focuses}
