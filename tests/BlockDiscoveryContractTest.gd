extends Node

var _passed := 0
var _failed := 0


func _ready() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	GameManager.create_character({
		"player_name": "发现测试", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": [],
	})
	_test_week_calendar()
	_test_authored_block_profiles()
	_test_progressive_and_persistent_discovery()
	_test_weighted_group_event_pool()
	_test_observed_after_school_window()
	_test_active_period_discovery_formatting()
	_test_non_hourly_observation_timestamp()
	_test_narrative_focus_messages()
	_test_occasional_discovery()
	_test_legacy_player_state()
	print("========== 区块发现契约：%d 通过 / %d 失败 ==========" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _expect(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
		print("✓ %s" % description)
	else:
		_failed += 1
		print("✗ %s" % description)


func _test_week_calendar() -> void:
	_expect(TimeManager.get_day_of_week(1) == 1 and TimeManager.is_weekday(5), "第 1–5 天属于工作日")
	_expect(TimeManager.get_day_of_week(6) == 6 and TimeManager.is_weekend(7), "第 6–7 天属于周末")
	_expect(TimeManager.get_day_of_week(8) == 1, "周历按七天循环且不改变绝对日期")


func _test_authored_block_profiles() -> void:
	_expect(not GameManager.all_blocks.is_empty(), "blocks.json 可被加载为区块列表")
	var all_valid := true
	for block in GameManager.all_blocks:
		var total := 0.0
		for group_id in SpatialConfig.POPULATION_GROUPS:
			total += block.get_group_weight(group_id)
		all_valid = all_valid and SpatialConfig.is_valid_block_type(block.block_type) and is_equal_approx(total, 1.0)
	_expect(all_valid, "每个区块都具有有效且归一化的人群配置")


func _test_progressive_and_persistent_discovery() -> void:
	var block_id := "block_w_school"
	var block := GameManager.get_block(block_id)
	_expect(block != null and block.get_group_weight("student") > 0.0, "真实学校区块存在且拥有学生人群配置")
	if block == null:
		return
	GameManager.player_state.block_research_progress[block_id] = {"groups": 100.0}
	TimeManager.current_day = 1
	TimeManager.total_game_seconds = 12.0 * 3600.0
	var records := BlockDiscoveryManager.evaluate_research(block_id, 1.0, -1.0, 3600.0, "groups")
	var known: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(int(known.get("group_student", 0)) == 1, "单次观察只推进人群发现的一档")
	_expect(not records.is_empty() and GameManager.player_state.discovery_history.size() == records.size(), "每次解锁都写入持久时间线")
	var second := BlockDiscoveryManager.evaluate_research(block_id, 1.0, -1.0, 3600.0, "groups")
	_expect(not second.is_empty() and int((GameManager.player_state.block_discovery_progress.get(block_id, {}) as Dictionary).get("group_student", 0)) == 2, "后续观察只推进下一档，不重复同一档")
	var restored := PlayerState.from_save_dict(GameManager.player_state.to_save_dict())
	_expect(not restored.discovery_history.is_empty() and not restored.block_discovery_progress.is_empty(), "发现记录可随玩家状态保存和恢复")


func _test_weighted_group_event_pool() -> void:
	var block_id := "block_c_commercial"
	var block := GameManager.get_block(block_id)
	_expect(block != null, "多客群商业区块存在")
	if block == null:
		return
	GameManager.player_state.block_discovery_progress.erase(block_id)
	GameManager.player_state.discovery_history.clear()
	var first_result: Array[Dictionary] = []
	BlockDiscoveryManager._evaluate_groups(block, 100.0, first_result)
	var after_first: Dictionary = (GameManager.player_state.block_discovery_progress.get(block_id, {}) as Dictionary).duplicate()
	_expect(int(after_first.get("group_office_worker", 0)) == 1, "首次人群发现固定为最大合法客群的一档")

	var second_result: Array[Dictionary] = []
	BlockDiscoveryManager._evaluate_groups(block, 100.0, second_result)
	var after_second: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	var valid_next_tier := second_result.size() == 1
	if valid_next_tier:
		var discovery_id := str(second_result[0].get("discovery_id", ""))
		valid_next_tier = discovery_id.begins_with("group_") and int(after_second.get(discovery_id, 0)) == int(after_first.get(discovery_id, 0)) + 1
	_expect(valid_next_tier, "事件池只会抽取各客群合法的下一档")

	var candidates: Array[Dictionary] = [
		{"group_id": "office_worker", "tier": 2, "weight": 80.0},
		{"group_id": "family_household", "tier": 1, "weight": 20.0},
	]
	var early_pick := BlockDiscoveryManager._choose_weighted_group_candidate(candidates, 0.0)
	var late_pick := BlockDiscoveryManager._choose_weighted_group_candidate(candidates, 0.99)
	_expect(str(early_pick.get("group_id", "")) == "office_worker" and str(late_pick.get("group_id", "")) == "family_household", "加权抽取会让所有合法客群都有机会出现")
	var restored := PlayerState.from_save_dict(GameManager.player_state.to_save_dict())
	GameManager.player_state = restored
	var restored_before: Dictionary = (restored.block_discovery_progress.get(block_id, {}) as Dictionary).duplicate()
	var restored_result: Array[Dictionary] = []
	BlockDiscoveryManager._evaluate_groups(block, 100.0, restored_result)
	var restored_after: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	var continues_in_order := restored_result.size() == 1
	if continues_in_order:
		var discovery_id := str(restored_result[0].get("discovery_id", ""))
		continues_in_order = int(restored_after.get(discovery_id, 0)) == int(restored_before.get(discovery_id, 0)) + 1
	_expect(continues_in_order, "存档恢复后的人群事件池继续遵守逐档规则")


func _test_observed_after_school_window() -> void:
	var block_id := "block_w_school"
	GameManager.player_state.block_discovery_progress.erase(block_id)
	GameManager.player_state.discovery_history.clear()
	GameManager.player_state.block_research_progress[block_id] = {"time": 100.0}
	TimeManager.current_day = 1
	TimeManager.total_game_seconds = 16.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 1.0, -1.0, 3600.0, "time")
	var before: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(not before.has("student_after_school"), "17 点前不会发现放学人流")
	TimeManager.total_game_seconds = 17.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 1.0, -1.0, 3600.0, "time")
	var weekday: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(int(weekday.get("student_after_school", 0)) == 1, "工作日 17–19 点可发现学生放学规律")
	GameManager.player_state.block_discovery_progress.erase(block_id)
	TimeManager.current_day = 1
	TimeManager.total_game_seconds = 19.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 1.0, -1.0, 3600.0, "time")
	var after_window: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(not after_window.has("student_after_school"), "19 点起不再发现学生放学规律")
	GameManager.player_state.block_discovery_progress.erase(block_id)
	TimeManager.current_day = 6
	TimeManager.total_game_seconds = (6.0 - 1.0) * TimeManager.DAY_SECONDS + 17.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 1.0, -1.0, 3600.0, "time")
	var weekend: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(not weekend.has("student_after_school"), "周末同一时段不会触发工作日放学规律")


func _test_active_period_discovery_formatting() -> void:
	var found_active_period := false
	for block in GameManager.all_blocks:
		var city_region := GameManager.get_city_region(block.city_region_id)
		var capacity := PopulationSupplyCalculator.calculate_capacity_base(block)
		for hour in range(24):
			if hour >= 17 and hour < 19:
				continue
			var period := SpatialConfig.get_period_for_hour(hour)
			var activity := PopulationSupplyCalculator.calculate_total_activity_supply(block, period, city_region, false)
			if capacity <= 0.0 or activity / capacity < 0.75:
				continue
			GameManager.player_state.block_discovery_progress.erase(block.id)
			GameManager.player_state.discovery_history.clear()
			var observed_at := float(hour) * 3600.0
			var results: Array[Dictionary] = []
			for _tier in range(4):
				BlockDiscoveryManager._evaluate_time(block, 100.0, results, observed_at)
			found_active_period = not results.is_empty() and str(results.back().get("message", "")).contains("活动供给")
			break
		if found_active_period:
			break
	_expect(found_active_period, "高活跃时段发现可正确格式化比例叙事文本")


func _test_occasional_discovery() -> void:
	var block_id := "block_w_school"
	GameManager.player_state.block_discovery_progress.erase(block_id)
	GameManager.player_state.discovery_history.clear()
	GameManager.player_state.block_understanding[block_id] = 0.0
	TimeManager.current_day = 1
	TimeManager.total_game_seconds = 10.0 * 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 0.0)
	var known: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(int(known.get("occasional_local_tip", 0)) == 1, "偶发线索不受了解度门槛限制")
	TimeManager.total_game_seconds += 3600.0
	BlockDiscoveryManager.evaluate_research(block_id, 0.0)
	_expect(GameManager.player_state.discovery_history.size() == 1, "偶发线索永久去重")


func _test_non_hourly_observation_timestamp() -> void:
	var block_id := "block_w_school"
	GameManager.player_state.block_discovery_progress.erase(block_id)
	GameManager.player_state.discovery_history.clear()
	GameManager.player_state.block_research_progress[block_id] = {"time": 100.0}
	var observed_at := 17.0 * 3600.0 + 13.0 * 60.0
	var records := BlockDiscoveryManager.evaluate_research(block_id, 1.0, observed_at, 10.0 * 60.0, "time")
	var known: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	_expect(int(known.get("student_after_school", 0)) == 1, "17:xx 的非整点观察可发现学生放学规律")
	var all_have_minute := not records.is_empty()
	for record in records:
		all_have_minute = all_have_minute and int(record.get("minute", -1)) == 13 and is_equal_approx(float(record.get("game_seconds", 0.0)), observed_at)
	_expect(all_have_minute, "发现记录保存实际观察分钟和游戏时间")


func _test_narrative_focus_messages() -> void:
	var block := GameManager.get_block("block_w_school")
	_expect(block != null, "叙事发现测试区块存在")
	if block == null:
		return
	var all_messages: Array[String] = []
	all_messages.append_array(BlockDiscoveryManager._spending_messages())
	all_messages.append_array(BlockDiscoveryManager._business_demand_messages(["餐饮", "日常服务"]))
	all_messages.append_array(BlockDiscoveryManager._competition_messages())
	var messages_are_complete := all_messages.size() == 12
	for message in all_messages:
		messages_are_complete = messages_are_complete and message.length() >= 20 and not message.contains("已完成记录")
	_expect(messages_are_complete, "消费、需求与竞争发现均提供四级叙事文本")

	GameManager.player_state.block_discovery_progress.erase(block.id)
	GameManager.player_state.discovery_history.clear()
	GameManager.player_state.block_research_progress[block.id] = {"spending": 25.0}
	var focused_records := BlockDiscoveryManager.evaluate_research(block.id, 1.0, -1.0, 3600.0, "spending")
	var focused_message := _find_discovery_message(focused_records, "spending")
	_expect(BlockDiscoveryManager._spending_messages().has(focused_message), "专项调研使用消费叙事文本")

	GameManager.player_state.block_discovery_progress.erase(block.id)
	GameManager.player_state.discovery_history.clear()
	GameManager.player_state.block_research_progress.erase(block.id)
	GameManager.player_state.block_understanding[block.id] = 25.0
	var legacy_records := BlockDiscoveryManager.evaluate_research(block.id, 1.0)
	var legacy_message := _find_discovery_message(legacy_records, "spending")
	_expect(BlockDiscoveryManager._spending_messages().has(legacy_message), "兼容调研路径复用相同的消费叙事文本")


func _find_discovery_message(records: Array[Dictionary], discovery_id: String) -> String:
	for record in records:
		if str(record.get("discovery_id", "")) == discovery_id:
			return str(record.get("message", ""))
	return ""


func _test_legacy_player_state() -> void:
	var restored := PlayerState.from_save_dict({"player_name": "旧存档", "block_understanding": {"a": 25.0}})
	_expect(restored.discovery_history.is_empty() and restored.block_discovery_progress.is_empty(), "旧存档缺少发现字段时安全初始化为空")
