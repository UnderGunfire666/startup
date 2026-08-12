class_name PlayerState
extends RefCounted

## ── 角色身份 ─────────────────────────────────────────────

var is_character_created: bool = false
var player_name: String = ""
var gender: String = ""
var age: int = 20
var difficulty_id: String = "normal"
var selected_preset_id: String = ""

## ── 角色资源 ─────────────────────────────────────────────

var cash: float = SettlementConfig.INITIAL_CASH
var stress: float = SettlementConfig.INITIAL_STRESS

var max_energy: float = 100.0
var energy: float = 100.0
var daily_energy_recovery_rate: float = 1.0

## 年龄提供的原始点数，以及最终已选择的特质。
var base_trait_points: int = 0
var selected_trait_ids: Array[String] = []

var work_hours_today: float = 0.0
var fatigue_state: String = "normal"
var energy_debt: float = 0.0

## ── 空间系统知识(玩家层，不因开店数量而分裂，多店重构阶段1迁移自Store) ──
var region_intel_levels: Dictionary = {}
var region_intel_progress: Dictionary = {}
var block_understanding: Dictionary = {}
var storefront_diligence: Dictionary = {}
var survey_areas: Array[SurveyAreaState] = []
var focused_city_region_id: String = ""

## 玩家当前所在区块。空字符串表示尚未定位到城市地图区块；Phase 6移动系统建立后，
## 所有跨区块移动都必须从这个状态出发并消耗游戏时间。
var current_block_id: String = ""

## 玩家当前亲自坐镇在哪家店，同一时刻只能坐镇一家；空字符串=不在任何店坐镇。
var supervising_store_id: String = ""

func reset_to_defaults() -> void:
	is_character_created = false
	player_name = ""
	gender = ""
	age = 20
	difficulty_id = "normal"
	selected_preset_id = ""

	cash = SettlementConfig.INITIAL_CASH
	stress = SettlementConfig.INITIAL_STRESS

	max_energy = 100.0
	energy = 100.0
	daily_energy_recovery_rate = 1.0

	base_trait_points = 0
	selected_trait_ids.clear()
	current_block_id = ""
	supervising_store_id = ""


func get_used_trait_points() -> int:
	var total := 0
	for trait_id in selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data != null:
			total += trait_data.point_cost
	return total


func get_remaining_trait_points() -> int:
	return base_trait_points - get_used_trait_points()


func has_trait(trait_id: String) -> bool:
	return trait_id in selected_trait_ids


func get_selected_trait_for_type(trait_type: String) -> String:
	for trait_id in selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data != null and trait_data.trait_type == trait_type:
			return trait_id
	return ""

func get_region_intel_level(city_region_id: String) -> int:
	return int(region_intel_levels.get(city_region_id, 0))


func get_region_intel_progress(city_region_id: String) -> float:
	return float(region_intel_progress.get(city_region_id, 0.0))


func get_block_understanding(block_id: String) -> float:
	return float(block_understanding.get(block_id, 0.0))


func get_storefront_diligence(storefront_id: String) -> String:
	return str(storefront_diligence.get(storefront_id, "not_viewed"))


func get_survey_area(id: String) -> SurveyAreaState:
	for area in survey_areas:
		if area.id == id:
			return area
	return null


func add_survey_area(area: SurveyAreaState) -> void:
	if area == null or area.id.is_empty():
		return
	for i in range(survey_areas.size()):
		if survey_areas[i].id == area.id:
			survey_areas[i] = area
			return
	survey_areas.append(area)


func remove_survey_area(id: String) -> bool:
	for i in range(survey_areas.size()):
		if survey_areas[i].id == id:
			survey_areas.remove_at(i)
			return true
	return false


func set_current_block(block_id: String) -> bool:
	if block_id.is_empty():
		current_block_id = ""
		return true

	var block := GameManager.get_block(block_id)
	if block == null:
		return false

	current_block_id = block_id
	return true

## 用于后续接入调研、行动、谈判与经营结算。
## 对数值型 effect 采用“加总”规则；倍率类字段由调用方自行约定默认值。
func get_trait_modifier(effect_key: String, default_value: float = 0.0) -> float:
	var value := default_value
	for trait_id in selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data == null:
			continue
		if trait_data.effects.has(effect_key):
			value += float(trait_data.effects[effect_key])
	return value


func get_trait_multiplier(effect_key: String, default_value: float = 1.0) -> float:
	var value := default_value
	for trait_id in selected_trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		if trait_data == null:
			continue
		if trait_data.effects.has(effect_key):
			value *= float(trait_data.effects[effect_key])
	return value


func apply_character_setup(data: Dictionary) -> void:
	var bracket: Dictionary = CharacterCreationData.get_age_bracket(int(data.age))
	var selected_ids: Array[String] = []

	for trait_id in data.get("trait_ids", []):
		selected_ids.append(str(trait_id))

	is_character_created = true
	player_name = str(data.player_name).strip_edges()
	gender = str(data.gender)
	age = int(data.age)
	difficulty_id = str(data.difficulty_id)
	selected_preset_id = str(data.get("preset_id", ""))

	cash = float(data.starting_cash)
	stress = SettlementConfig.INITIAL_STRESS

	base_trait_points = int(bracket.trait_points)
	selected_trait_ids = selected_ids
	current_block_id = ""

	var energy_bonus := get_trait_modifier("max_energy_add", 0.0)
	max_energy = maxf(1.0, float(bracket.max_energy) + energy_bonus)
	energy = max_energy
	daily_energy_recovery_rate = float(bracket.daily_energy_recovery_rate)


## 结算后应用财务与压力变化。
## 口碑变化仍在 StoreState.apply_settlement() 中处理。
func apply_settlement(result: SettlementResult) -> void:
	cash += result.profit

	var stress_multiplier := get_trait_multiplier("stress_gain_mult", 1.0)
	stress = clampf(
		stress + result.stress_delta * stress_multiplier,
		0.0,
		100.0
	)

## 精力增减统一入口：正数优先偿还透支，负数超支记入energy_debt，不截断。
func apply_energy_delta(delta: float) -> void:
	if delta >= 0.0:
		var remaining := delta
		if energy_debt > 0.0:
			var pay := minf(energy_debt, remaining)
			energy_debt -= pay
			remaining -= pay
		energy = minf(max_energy, energy + remaining)
	else:
		var cost := -delta
		if energy >= cost:
			energy -= cost
		else:
			var overflow := cost - energy
			energy = 0.0
			energy_debt += overflow


## 每日结算：应用前一日过劳遗留惩罚，重置当日工作时长与疲惫状态。
func start_new_day() -> void:
	var penalty := ScheduleConfig.get_overwork_penalty(work_hours_today)
	if penalty > 0.0:
		apply_energy_delta(-penalty)
	work_hours_today = 0.0
	fatigue_state = "normal"

func _survey_areas_to_save_data() -> Array:
	var result: Array = []
	for area in survey_areas:
		result.append(area.to_save_dict())
	return result

func to_save_dict() -> Dictionary:
	return {
		"version": 3,
		"is_character_created": is_character_created,
		"player_name": player_name,
		"gender": gender,
		"age": age,
		"difficulty_id": difficulty_id,
		"selected_preset_id": selected_preset_id,

		"cash": cash,
		"stress": stress,

		"max_energy": max_energy,
		"energy": energy,
		"daily_energy_recovery_rate": daily_energy_recovery_rate,

		"base_trait_points": base_trait_points,
		"selected_trait_ids": selected_trait_ids,
		
		"region_intel_levels": region_intel_levels,
		"region_intel_progress": region_intel_progress,
		"block_understanding": block_understanding,
		"storefront_diligence": storefront_diligence,
		"survey_areas": _survey_areas_to_save_data(),
		"focused_city_region_id": focused_city_region_id,
		"current_block_id": current_block_id,
		"supervising_store_id": supervising_store_id,
	}


static func from_save_dict(data: Dictionary) -> PlayerState:
	var p := PlayerState.new()

	p.is_character_created = data.get("is_character_created", false)
	p.player_name = str(data.get("player_name", ""))
	p.gender = str(data.get("gender", ""))
	p.age = int(data.get("age", 20))
	p.difficulty_id = str(data.get("difficulty_id", "normal"))
	p.selected_preset_id = str(data.get("selected_preset_id", ""))

	p.cash = float(data.get("cash", SettlementConfig.INITIAL_CASH))
	p.stress = float(data.get("stress", SettlementConfig.INITIAL_STRESS))

	p.max_energy = float(data.get("max_energy", 100.0))
	p.energy = float(data.get("energy", p.max_energy))
	p.daily_energy_recovery_rate = float(data.get(
		"daily_energy_recovery_rate",
		1.0
	))

	p.base_trait_points = int(data.get("base_trait_points", 0))

	var raw_trait_ids: Array = data.get("selected_trait_ids", [])
	var typed_trait_ids: Array[String] = []
	for trait_id in raw_trait_ids:
		typed_trait_ids.append(str(trait_id))
	p.selected_trait_ids = typed_trait_ids
	
	p.region_intel_levels = data.get("region_intel_levels", {})
	p.region_intel_progress = data.get("region_intel_progress", {})
	p.block_understanding = data.get("block_understanding", {})
	p.storefront_diligence = data.get("storefront_diligence", {})
	p.focused_city_region_id = data.get("focused_city_region_id", "")
	p.current_block_id = str(data.get("current_block_id", ""))
	p.supervising_store_id = data.get("supervising_store_id", "")

	var survey_area_raw: Array = data.get("survey_areas", [])
	var survey_area_typed: Array[SurveyAreaState] = []
	for raw_area in survey_area_raw:
		if raw_area is Dictionary:
			survey_area_typed.append(SurveyAreaState.from_save_dict(raw_area))
	p.survey_areas = survey_area_typed
	return p

func get_required_region_familiarity() -> float:
	return clampf(
		RegionConfig.DEFAULT_OPEN_FAMILIARITY_THRESHOLD
			+ get_trait_modifier("region_familiarity_threshold_add", 0.0),
		0.0, 100.0
	)


func get_required_region_interest() -> float:
	return clampf(
		RegionConfig.DEFAULT_OPEN_INTEREST_THRESHOLD
			+ get_trait_modifier("region_interest_threshold_add", 0.0),
		0.0, 100.0
	)
