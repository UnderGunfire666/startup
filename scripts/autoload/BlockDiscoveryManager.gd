extends Node

## Persistent, informational discoveries earned while the player is actively
## researching a block.  Definitions deliberately stay as plain dictionaries:
## map authors can add categories without changing save data or event effects.

signal discovery_recorded(record: Dictionary)

const TIER_THRESHOLDS: Array[float] = [25.0, 50.0, 75.0, 100.0]
const OCCASIONAL_CHANCE_PER_HOUR: float = 0.08
const MAX_HISTORY: int = 400

const GROUP_NAMES := {
	"student": "学生", "office_worker": "上班族", "worker": "产业工人",
	"family_household": "家庭住户", "high_spend_household": "高消费家庭",
}
const PERIOD_NAMES := {"morning": "早晨", "noon": "中午", "evening": "傍晚", "night": "夜间"}
const LEVEL_NAMES := {"low": "低", "medium": "中等", "high": "高"}

var _occasional_roll_hours: Dictionary = {}


func reset_for_new_game() -> void:
	_occasional_roll_hours.clear()


func evaluate_research(block_id: String, occasional_roll: float = -1.0) -> Array[Dictionary]:
	var block := GameManager.get_block(block_id)
	if block == null:
		return []
	var result: Array[Dictionary] = []
	var understanding := GameManager.get_block_understanding(block_id)
	var city_region := GameManager.get_city_region(block.city_region_id)

	_evaluate_static_discoveries(block, city_region, understanding, result)
	_evaluate_observed_discoveries(block, city_region, understanding, result)
	_evaluate_occasional_discovery(block, understanding, result, occasional_roll)
	return result


func _evaluate_static_discoveries(block: BlockData, city_region: CityRegionData, understanding: float, result: Array[Dictionary]) -> void:
	var capacity := PopulationSupplyCalculator.calculate_capacity_base(block)
	if capacity <= 100.0:
		_try_record_progressive(block, "population_sparse", "人口", understanding, result, _population_message("人烟较少", capacity))
	elif capacity >= 350.0:
		_try_record_progressive(block, "population_dense", "人口", understanding, result, _population_message("人流与常住规模较大", capacity))

	var capacities := PopulationSupplyCalculator.calculate_group_capacities(block)
	for group_id in SpatialConfig.POPULATION_GROUPS:
		var group_capacity := float(capacities.get(group_id, 0.0))
		if capacity > 0.0 and group_capacity / capacity >= 0.20 and group_capacity >= 12.0:
			_try_record_progressive(block, "group_" + group_id, "人群", understanding, result,
				_group_message(str(GROUP_NAMES.get(group_id, group_id)), group_capacity / capacity, group_capacity))

	var spend_tier := str(block.spending_profile.get("spend_potential_tier", "medium"))
	_try_record_progressive(block, "spending", "消费", understanding, result,
		_spending_message(spend_tier, float(block.spending_profile.get("price_sensitivity", 0.5)), float(block.spending_profile.get("quality_preference", 0.5))))

	if not block.business_demand_tags.is_empty():
		_try_record_progressive(block, "business_demand", "需求", understanding, result,
			_demand_message(block.business_demand_tags))

	var competition_level := str(block.competition_profile.get("competition_level", "medium"))
	var rent_pressure := str(block.competition_profile.get("rent_pressure", "medium"))
	_try_record_progressive(block, "competition", "竞争", understanding, result,
		_competition_message(competition_level, rent_pressure, str(block.competition_profile.get("rent_trend", "stable"))))


func _evaluate_observed_discoveries(block: BlockData, city_region: CityRegionData, understanding: float, result: Array[Dictionary]) -> void:
	var hour := TimeManager.get_current_hour_int()
	var period := SpatialConfig.get_period_for_hour(hour)
	var activity := PopulationSupplyCalculator.calculate_total_activity_supply(block, period, city_region, TimeManager.is_weekend())
	var capacity := PopulationSupplyCalculator.calculate_capacity_base(block)
	if capacity > 0.0 and activity / capacity >= 0.75:
		_try_record_progressive(block, "active_" + period, "时段", understanding, result,
			_activity_message(str(PERIOD_NAMES.get(period, period)), activity / capacity))

	## A deliberately narrow observation: it is only earned by witnessing a
	## weekday after-school window during active research, never from a static scan.
	if TimeManager.is_weekday() and hour >= 17 and hour < 19:
		var students := PopulationSupplyCalculator.calculate_group_activity_supply(
			block, "student", period, city_region, false)
		if students >= 12.0:
			_try_record_progressive(block, "student_after_school", "时段", understanding, result,
				_student_after_school_message(students))


func _evaluate_occasional_discovery(block: BlockData, understanding: float, result: Array[Dictionary], forced_roll: float) -> void:
	var discovery_id := "occasional_local_tip"
	if _get_highest_tier(block.id, discovery_id) > 0:
		return
	var absolute_hour := int(floor(TimeManager.total_game_seconds / 3600.0))
	if int(_occasional_roll_hours.get(block.id, -1)) == absolute_hour:
		return
	_occasional_roll_hours[block.id] = absolute_hour
	var roll := randf() if forced_roll < 0.0 else clampf(forced_roll, 0.0, 1.0)
	if roll > OCCASIONAL_CHANCE_PER_HOUR:
		return
	var message := "路遇一位熟悉附近的大爷：这片街区的变化，往往比地图上看起来更快。"
	_try_record(block, discovery_id, "偶发线索", 1, message, true, result)


func _try_record_progressive(block: BlockData, discovery_id: String, category: String, understanding: float, result: Array[Dictionary], messages: Array[String]) -> void:
	var unlocked_tier := 0
	for index in range(TIER_THRESHOLDS.size()):
		if understanding >= TIER_THRESHOLDS[index]:
			unlocked_tier = index + 1
	if unlocked_tier <= 0:
		return
	var known_tier := _get_highest_tier(block.id, discovery_id)
	for tier in range(known_tier + 1, unlocked_tier + 1):
		_try_record(block, discovery_id, category, tier, messages[tier - 1], false, result)


func _try_record(block: BlockData, discovery_id: String, category: String, tier: int, message: String, occasional: bool, result: Array[Dictionary]) -> void:
	if tier <= _get_highest_tier(block.id, discovery_id):
		return
	var record := {
		"block_id": block.id,
		"block_name": block.name,
		"discovery_id": discovery_id,
		"category": category,
		"tier": tier,
		"message": message,
		"occasional": occasional,
		"day": TimeManager.current_day,
		"weekday": TimeManager.get_weekday_name(),
		"hour": TimeManager.get_current_hour_int(),
		"game_seconds": TimeManager.total_game_seconds,
	}
	var by_block: Dictionary = GameManager.player_state.block_discovery_progress.get(block.id, {})
	by_block[discovery_id] = tier
	GameManager.player_state.block_discovery_progress[block.id] = by_block
	GameManager.player_state.discovery_history.append(record)
	while GameManager.player_state.discovery_history.size() > MAX_HISTORY:
		GameManager.player_state.discovery_history.pop_front()
	discovery_recorded.emit(record)
	EventManager.raise_discovery_notice("发现：" + block.name, message, block.id)
	result.append(record)


func _get_highest_tier(block_id: String, discovery_id: String) -> int:
	var by_block: Dictionary = GameManager.player_state.block_discovery_progress.get(block_id, {})
	return int(by_block.get(discovery_id, 0))


func _population_message(summary: String, capacity: float) -> Array[String]:
	return ["你发现这里%s。" % summary, "这里的常驻与活动承载规模并不均衡。", "观察到约 %d 的人口承载规模。" % roundi(capacity), "人口规模约为 %d，适合据此判断基础客源。" % roundi(capacity)]


func _group_message(group_name: String, ratio: float, capacity: float) -> Array[String]:
	return ["你发现这里常能见到%s。" % group_name, "%s似乎是此处的重要人群。" % group_name, "%s约占当地人群的 %.0f%%。" % [group_name, ratio * 100.0], "%s的潜在规模约为 %d。" % [group_name, roundi(capacity)]]


func _activity_message(period_name: String, ratio: float) -> Array[String]:
	return ["你发现%s这里会热闹起来。" % period_name, "%s的人流有明显变化。" % period_name, "%s的活跃度高于日常。" % period_name, "%s活动供给约为基础规模的 %.0f%%。" % [period_name, ratio * 100.0]]


func _student_after_school_message(students: float) -> Array[String]:
	return ["你发现工作日傍晚常有学生经过。", "工作日 17 点后，学生人流开始明显增多。", "工作日 17–19 点会出现集中的放学人流。", "工作日 17–19 点，学生活动规模约为 %d。" % roundi(students)]


func _spending_message(spend_tier: String, price_sensitivity: float, quality_preference: float) -> Array[String]:
	var tier_name := str(LEVEL_NAMES.get(spend_tier, "中等"))
	return ["你发现这里的消费气质偏%s。" % tier_name, "顾客对价格与品质有稳定偏好。", "这里的消费潜力为%s。" % tier_name, "价格敏感 %.0f%%，品质偏好 %.0f%%。" % [price_sensitivity * 100.0, quality_preference * 100.0]]


func _demand_message(tags: Array[String]) -> Array[String]:
	var joined := "、".join(tags)
	return ["你发现这里有明确的消费缺口。", "附近居民会反复寻找特定服务。", "这里偏好的业态包括：%s。" % joined, "需求标签已确认：%s。" % joined]


func _competition_message(competition: String, rent: String, trend: String) -> Array[String]:
	return ["你发现这里的竞争环境值得留意。", "同类商户与成本压力正在影响街区。", "竞争%s，租金压力%s。" % [LEVEL_NAMES.get(competition, competition), LEVEL_NAMES.get(rent, rent)], "竞争%s、租金%s，租金趋势为%s。" % [LEVEL_NAMES.get(competition, competition), LEVEL_NAMES.get(rent, rent), trend]]
