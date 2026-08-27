extends Node

signal discovery_recorded(record: Dictionary)

const TIER_THRESHOLDS: Array[float] = [25.0, 50.0, 75.0, 100.0]
const OCCASIONAL_CHANCE_PER_HOUR := 0.08
const MAX_HISTORY := 400
const GROUP_NAMES := {"student": "学生", "office_worker": "上班族", "worker": "产业工人", "family_household": "家庭住户", "high_spend_household": "高消费家庭"}
const FOCUS_BY_DISCOVERY_PREFIX := {"population_": "population", "group_": "groups", "active_": "time", "student_after_school": "time", "spending": "spending", "business_demand": "demand", "competition": "competition"}

var _evaluation_time_override := -1.0


func reset_for_new_game() -> void:
	_evaluation_time_override = -1.0


func get_focus_for_discovery(discovery_id: String) -> String:
	for prefix in FOCUS_BY_DISCOVERY_PREFIX:
		if discovery_id.begins_with(prefix):
			return str(FOCUS_BY_DISCOVERY_PREFIX[prefix])
	return ""


func evaluate_research(block_id: String, occasional_roll: float = -1.0, observation_game_seconds: float = -1.0, observation_interval_seconds: float = 3600.0, focus_id: String = "") -> Array[Dictionary]:
	var block := GameManager.get_block(block_id)
	if block == null:
		return []
	var observed_at := TimeManager.total_game_seconds if observation_game_seconds < 0.0 else observation_game_seconds
	var previous_override := _evaluation_time_override
	_evaluation_time_override = observed_at
	var result: Array[Dictionary] = []
	var progress := GameManager.get_block_research_progress(block_id, focus_id) if not focus_id.is_empty() else 100.0
	if focus_id == "population":
		_evaluate_population(block, progress, result)
	elif focus_id == "groups":
		_evaluate_groups(block, progress, result)
	elif focus_id == "time":
		_evaluate_time(block, progress, result, observed_at)
	elif focus_id == "spending":
		_try_progressive(block, "spending", "消费", progress, result, _spending_messages())
	elif focus_id == "demand":
		if not block.business_demand_tags.is_empty():
			_try_progressive(block, "business_demand", "业态需求", progress, result, _business_demand_messages(block.business_demand_tags))
	elif focus_id == "competition":
		_try_progressive(block, "competition", "竞争", progress, result, _competition_messages())
	elif focus_id.is_empty():
		# Compatibility path for direct legacy calls and migration tests.
		var legacy_progress := GameManager.get_block_understanding(block_id)
		_evaluate_population(block, legacy_progress, result)
		_evaluate_groups(block, legacy_progress, result)
		_evaluate_time(block, legacy_progress, result, observed_at)
		_try_progressive(block, "spending", "消费", legacy_progress, result, _spending_messages())
		if not block.business_demand_tags.is_empty():
			_try_progressive(block, "business_demand", "业态需求", legacy_progress, result, _business_demand_messages(block.business_demand_tags))
		_try_progressive(block, "competition", "竞争", legacy_progress, result, _competition_messages())
	_evaluate_occasional(block, result, occasional_roll, observation_interval_seconds)
	_evaluation_time_override = previous_override
	return result


func _spending_messages() -> Array[String]:
	return _four(
		"同一排橱窗前，有人先问价再离开，也有人宁愿多绕半条街去挑更合心意的东西。这里的花钱方式显然有自己的脾气。",
		"你开始听见顾客在价格之外谈起分量、质感和省不省事；他们不是只想买到东西，而是在挑一种值得的感觉。",
		"把几次停留和交谈摊开看，街区对便宜、品质与便利的取舍已经有了清晰的方向。",
		"消费偏好已经足够完整地浮出水面；下一步该想的不是迎合所有人，而是谁会真正为你的选择停下。"
	)


func _business_demand_messages(tags: Array[String]) -> Array[String]:
	var tag_text := "、".join(tags)
	return _four(
		"几次问路和闲聊里，总有人提起“附近要是有一家就好了”。这些抱怨还很零散，却指向同一种没被满足的日常。",
		"同一类问询反复出现，连附近店主都习惯性地把顾客指向更远的街口。需求不再只是猜测，而是正在门前绕路。",
		"反复被提起的方向是：%s。它们未必都是机会，但已经足够值得带着问题去看。" % tag_text,
		"关于这片街区在寻找什么，线索已经收束为：%s。剩下的难题是，谁能用合适的方式把它接住。" % tag_text
	)


func _competition_messages() -> Array[String]:
	return _four(
		"街口相邻的招牌几乎没有空过；这条街显然不缺想分一杯羹的人。",
		"你注意到商户的出价、营业时间和招呼客人的方式正在彼此试探。",
		"把几家店的习惯拼在一起后，谁在抢谁的生意终于有了轮廓。",
		"关于竞争的零碎观察已经能连成一张可供判断的街区草图。"
	)


func _evaluate_population(block: BlockData, progress: float, result: Array[Dictionary]) -> void:
	var capacity := PopulationSupplyCalculator.calculate_capacity_base(block)
	if capacity <= 100.0:
		_try_progressive(block, "population_sparse", "人口", progress, result, _four("午后的街面留得住风，却留不住多少脚步；这里的安静不像偶然。", "你开始分辨出零散住户与短暂停留者的节奏，他们很少在同一时刻出现。", "几次计数后，街区能承接的人数大致落在 %d 左右，比第一眼看上去更受限。" % roundi(capacity), "关于人群规模的判断已经足够完整，接下来该看他们何时、为何出门。"))
	elif capacity >= 350.0:
		_try_progressive(block, "population_dense", "人口", progress, result, _four("人行道很少真正空下来，连等红灯的人群都像在替这片街区续一口气。", "你连续几次回来，发现这里的热闹不是偶发，而是一种稳定的日常。", "计数逐渐收敛：街区大约能承接 %d 人的规模，足以让细小差异变得重要。" % roundi(capacity), "关于人群规模的判断已经足够完整，接下来该看他们何时、为何出门。"))


func _evaluate_groups(block: BlockData, progress: float, result: Array[Dictionary]) -> void:
	var total := PopulationSupplyCalculator.calculate_capacity_base(block)
	var capacities := PopulationSupplyCalculator.calculate_group_capacities(block)
	var groups: Array[String] = []
	for raw_id in SpatialConfig.POPULATION_GROUPS:
		var id := str(raw_id)
		if total > 0.0 and float(capacities.get(id, 0.0)) / total >= 0.20 and float(capacities.get(id, 0.0)) >= 12.0:
			groups.append(id)
	groups.sort_custom(func(a: String, b: String) -> bool: return float(capacities.get(a, 0.0)) > float(capacities.get(b, 0.0)))
	var unlocked_tier := _get_unlocked_tier(progress)
	if groups.is_empty() or unlocked_tier <= 0:
		return

	var discovery_state: Dictionary = GameManager.player_state.block_discovery_progress.get(block.id, {})
	var has_any_group_discovery := false
	for key in discovery_state.keys():
		if str(key).begins_with("group_"):
			has_any_group_discovery = true
			break

	## The first observation is always the principal group's first fact.
	if not has_any_group_discovery:
		_record_group_tier(block, groups[0], 1, capacities, total, result)
		return

	var candidates: Array[Dictionary] = []
	for group_id in groups:
		var known_tier := _get_highest_tier(block.id, "group_" + group_id)
		var next_tier := known_tier + 1
		if next_tier <= unlocked_tier and next_tier <= TIER_THRESHOLDS.size():
			candidates.append({"group_id": group_id, "tier": next_tier, "weight": float(capacities.get(group_id, 0.0))})
	if candidates.is_empty():
		return

	var selected := _choose_weighted_group_candidate(candidates)
	_record_group_tier(block, str(selected.get("group_id", "")), int(selected.get("tier", 0)), capacities, total, result)


func _choose_weighted_group_candidate(candidates: Array[Dictionary], roll: float = -1.0) -> Dictionary:
	var total_weight := 0.0
	for candidate in candidates:
		total_weight += maxf(0.0, float(candidate.get("weight", 0.0)))
	if total_weight <= 0.0:
		return candidates[0]
	var target := (randf() if roll < 0.0 else clampf(roll, 0.0, 0.999999)) * total_weight
	for candidate in candidates:
		target -= maxf(0.0, float(candidate.get("weight", 0.0)))
		if target <= 0.0:
			return candidate
	return candidates.back()


func _record_group_tier(block: BlockData, group_id: String, tier: int, capacities: Dictionary, total: float, result: Array[Dictionary]) -> void:
	if group_id.is_empty() or tier < 1 or tier > TIER_THRESHOLDS.size():
		return
	var ratio := float(capacities.get(group_id, 0.0)) / maxf(0.0001, total)
	var group_name := str(GROUP_NAMES.get(group_id, group_id))
	var messages := _four("在路口、窗口和长椅旁，%s的身影反复出现。" % group_name, "他们不是偶尔经过；%s正在悄悄决定这条街什么时候有生意可做。" % group_name, "把几次观察摊开看，%s约占这里人群的 %.0f%%，已经不是可以忽略的背景。" % [group_name, ratio * 100.0], "按现有线索推算，%s的潜在规模约为 %d；这是一群值得继续理解、而非只用标签概括的人。" % [group_name, roundi(float(capacities.get(group_id, 0.0)))])
	_record(block, "group_" + group_id, "人群", tier, messages[tier - 1], false, result)


func _evaluate_time(block: BlockData, progress: float, result: Array[Dictionary], observed_at: float) -> void:
	var hour := _hour_at(observed_at)
	var city_region := GameManager.get_city_region(block.city_region_id)
	var period := SpatialConfig.get_period_for_hour(hour)
	var activity := PopulationSupplyCalculator.calculate_total_activity_supply(block, period, city_region, _weekend_at(observed_at))
	var capacity := PopulationSupplyCalculator.calculate_capacity_base(block)
	if not _weekend_at(observed_at) and hour >= 17 and hour < 19:
		var students := PopulationSupplyCalculator.calculate_group_activity_supply(block, "student", period, city_region, false)
		if students >= 12.0:
			_try_progressive(block, "student_after_school", "时段", progress, result, _four("放学铃声过去不久，背着书包的学生便开始从几条小路汇到这里。", "过了 17 点，原本松散的脚步突然有了方向，学生们把街面推热了一截。", "你确认了这不是巧合：工作日 17–19 点，放学人流会把这里短暂地改写。", "这段窗口里大约会涌过 %d 名学生；他们来得快，也不会无缘无故停留。" % roundi(students)))
			return
	if capacity > 0.0 and activity / capacity >= 0.75:
		_try_progressive(block, "active_" + period, "时段", progress, result, _four("到了%s，店门前的空隙开始被脚步填满，街区像刚被唤醒。" % period, "%s的变化不只在人数：等人、停步和绕路的行为都明显多了。" % period, "你连续观察后确认，%s的活跃度确实高于平常，值得专门安排。" % period, "这一时段的活动供给约为基础规模的 %.0f%%；知道它何时出现，比只知道它存在更有用。" % [period, activity / capacity * 100.0]))


func _evaluate_occasional(block: BlockData, result: Array[Dictionary], forced_roll: float, interval_seconds: float) -> void:
	if _get_highest_tier(block.id, "occasional_local_tip") > 0:
		return
	var chance := 1.0 - pow(1.0 - OCCASIONAL_CHANCE_PER_HOUR, maxf(0.0, interval_seconds) / 3600.0)
	var roll := randf() if forced_roll < 0.0 else clampf(forced_roll, 0.0, 1.0)
	if roll <= chance:
		_record(block, "occasional_local_tip", "偶发线索", 1, "等红灯时，一位当地人顺口提起这条街“真正有意思的时段”。话说得不多，却留下了一根值得回头追的线头。", true, result)


func _try_progressive(block: BlockData, discovery_id: String, category: String, progress: float, result: Array[Dictionary], messages: Array[String]) -> void:
	var target_tier := _get_unlocked_tier(progress)
	var known := _get_highest_tier(block.id, discovery_id)
	if known < target_tier:
		_record(block, discovery_id, category, known + 1, messages[known], false, result)


func _get_unlocked_tier(progress: float) -> int:
	var target_tier := 0
	for index in range(TIER_THRESHOLDS.size()):
		if progress >= TIER_THRESHOLDS[index]:
			target_tier = index + 1
	return target_tier


func _record(block: BlockData, discovery_id: String, category: String, tier: int, message: String, occasional: bool, result: Array[Dictionary]) -> void:
	var record_time := _evaluation_time_override if _evaluation_time_override >= 0.0 else TimeManager.total_game_seconds
	var day := 1 + int(record_time / TimeManager.DAY_SECONDS)
	var record := {"block_id": block.id, "block_name": block.name, "discovery_id": discovery_id, "category": category, "tier": tier, "message": message, "occasional": occasional, "day": day, "weekday": TimeManager.get_weekday_name(day), "hour": _hour_at(record_time), "minute": int(fposmod(record_time, 3600.0) / 60.0), "game_seconds": record_time}
	var by_block: Dictionary = GameManager.player_state.block_discovery_progress.get(block.id, {})
	by_block[discovery_id] = tier
	GameManager.player_state.block_discovery_progress[block.id] = by_block
	GameManager.player_state.discovery_history.append(record)
	while GameManager.player_state.discovery_history.size() > MAX_HISTORY: GameManager.player_state.discovery_history.pop_front()
	discovery_recorded.emit(record)
	EventManager.raise_discovery_notice("发现：" + block.name, message, block.id)
	result.append(record)


func _get_highest_tier(block_id: String, discovery_id: String) -> int:
	return int((GameManager.player_state.block_discovery_progress.get(block_id, {}) as Dictionary).get(discovery_id, 0))


func _hour_at(seconds: float) -> int:
	return int(fposmod(seconds, TimeManager.DAY_SECONDS) / 3600.0)


func _weekend_at(seconds: float) -> bool:
	return TimeManager.is_weekend(1 + int(seconds / TimeManager.DAY_SECONDS))


func _four(a: String, b: String, c: String, d: String) -> Array[String]:
	return [a, b, c, d]
