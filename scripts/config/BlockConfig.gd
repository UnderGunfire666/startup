class_name BlockConfig
## 区块类型/等级的默认数值模板：基础密度、等级系数、默认时段曲线、
## 默认人群权重。BlockData可以直接用这些默认值初始化，也可以在编辑器里
## 手工覆盖单个区块的具体字段——这里只是"没特别配置时用什么"。
##
## 本类不做任何容量计算，容量公式在 PopulationSupplyCalculator 中实现，
## 保持"配置数据"和"计算逻辑"分离，方便你后续单独调数值而不动公式。

# ── 类型基础密度：不同类型区块的人口/岗位密度基准 ──────────
const BASE_DENSITY: Dictionary = {
	"school": 1.0,
	"office": 1.0,
	"commercial": 0.8,
	"industrial": 0.9,
	"residential": 0.6,
}

# ── 等级系数：同类型下，等级越高单位面积承载力越强 ──────────
# 注意：不是线性翻倍，等级越高，边际增幅递减，避免"更大更高级=无限膨胀"。
const TIER_MULTIPLIER: Dictionary = {
	"school":      {1: 1.0, 2: 1.4, 3: 2.0},
	"office":      {1: 1.0, 2: 1.5, 3: 2.2},
	"commercial":  {1: 1.0, 2: 1.6, 3: 2.4},
	"industrial":  {1: 1.0, 2: 1.5, 3: 2.0},
	"residential": {1: 1.0, 2: 1.5, 3: 1.9},
}

# ── 默认时段活跃曲线：早/午/晚/夜相对活跃系数 ───────────────
# 键结构：DEFAULT_ACTIVE_TIME_PROFILE[block_type][tier] = {period: value}
const DEFAULT_ACTIVE_TIME_PROFILE: Dictionary = {
	"school": {
		1: {"morning": 1.2, "noon": 0.8, "evening": 0.6, "night": 0.1},
		2: {"morning": 1.2, "noon": 0.8, "evening": 0.6, "night": 0.1},
		3: {"morning": 0.8, "noon": 1.2, "evening": 1.2, "night": 0.5},
	},
	"office": {
		1: {"morning": 1.0, "noon": 1.3, "evening": 1.0, "night": 0.3},
		2: {"morning": 1.0, "noon": 1.3, "evening": 1.0, "night": 0.3},
		3: {"morning": 1.0, "noon": 1.3, "evening": 1.0, "night": 0.3},
	},
	"commercial": {
		1: {"morning": 0.8, "noon": 1.0, "evening": 1.2, "night": 0.6},
		2: {"morning": 0.6, "noon": 1.2, "evening": 1.4, "night": 0.8},
		3: {"morning": 0.6, "noon": 1.2, "evening": 1.4, "night": 0.8},
	},
	"industrial": {
		1: {"morning": 1.0, "noon": 1.2, "evening": 1.0, "night": 0.2},
		2: {"morning": 1.0, "noon": 1.2, "evening": 1.0, "night": 0.2},
		3: {"morning": 1.0, "noon": 1.2, "evening": 1.0, "night": 0.6},
	},
	"residential": {
		1: {"morning": 1.1, "noon": 0.6, "evening": 1.3, "night": 0.4},
		2: {"morning": 1.1, "noon": 0.6, "evening": 1.3, "night": 0.4},
		3: {"morning": 0.9, "noon": 0.7, "evening": 1.3, "night": 0.6},
	},
}

# ── 默认人群供给权重：键结构同上，值为五类人群权重，总和=1 ────
const DEFAULT_GROUP_WEIGHTS: Dictionary = {
	"school": {
		1: {"student": 0.60, "office_worker": 0.15, "worker": 0.0, "family_household": 0.25, "high_spend_household": 0.0},
		2: {"student": 0.68, "office_worker": 0.17, "worker": 0.0, "family_household": 0.15, "high_spend_household": 0.0},
		3: {"student": 0.75, "office_worker": 0.15, "worker": 0.03, "family_household": 0.05, "high_spend_household": 0.02},
	},
	"office": {
		1: {"student": 0.0, "office_worker": 0.85, "worker": 0.10, "family_household": 0.03, "high_spend_household": 0.02},
		2: {"student": 0.0, "office_worker": 0.88, "worker": 0.05, "family_household": 0.02, "high_spend_household": 0.05},
		3: {"student": 0.0, "office_worker": 0.65, "worker": 0.30, "family_household": 0.02, "high_spend_household": 0.03},
	},
	"commercial": {
		1: {"student": 0.15, "office_worker": 0.30, "worker": 0.15, "family_household": 0.35, "high_spend_household": 0.05},
		2: {"student": 0.15, "office_worker": 0.25, "worker": 0.10, "family_household": 0.35, "high_spend_household": 0.15},
		3: {"student": 0.10, "office_worker": 0.25, "worker": 0.05, "family_household": 0.30, "high_spend_household": 0.30},
	},
	"industrial": {
		1: {"student": 0.0, "office_worker": 0.10, "worker": 0.85, "family_household": 0.05, "high_spend_household": 0.0},
		2: {"student": 0.0, "office_worker": 0.15, "worker": 0.80, "family_household": 0.05, "high_spend_household": 0.0},
		3: {"student": 0.0, "office_worker": 0.22, "worker": 0.70, "family_household": 0.06, "high_spend_household": 0.02},
	},
	"residential": {
		1: {"student": 0.05, "office_worker": 0.05, "worker": 0.0, "family_household": 0.85, "high_spend_household": 0.05},
		2: {"student": 0.05, "office_worker": 0.05, "worker": 0.0, "family_household": 0.70, "high_spend_household": 0.20},
		3: {"student": 0.05, "office_worker": 0.05, "worker": 0.0, "family_household": 0.45, "high_spend_household": 0.45},
	},
}

# ── 调研时间 ─────────────────────────────────────────────
# 以 area=100 的区块作为基准。使用平方根缩放，避免面积翻倍导致调查时间也机械翻倍，
# 同时保证大区块明确比小区块更耗时。Phase 3 只改变一次调查行动的总时长，
# 了解度增益公式仍保持现有规则；Phase 4 再改为持续调查/剩余了解度驱动。
const SURVEY_BASE_AREA: float = 100.0
const SURVEY_AREA_TIME_EXPONENT: float = 0.5
const SURVEY_MIN_DURATION_HOURS: int = 1

static func get_research_duration_hours(base_duration_hours: int, blocks: Array[BlockData]) -> int:
	if blocks.is_empty():
		return base_duration_hours

	var max_duration := float(base_duration_hours)
	for block in blocks:
		if block == null:
			continue
		var area := maxf(block.area, 1.0)
		var multiplier := pow(area / SURVEY_BASE_AREA, SURVEY_AREA_TIME_EXPONENT)
		var duration := float(base_duration_hours) * multiplier
		max_duration = maxf(max_duration, duration)

	return maxi(SURVEY_MIN_DURATION_HOURS, ceili(max_duration))

static func get_base_density(block_type: String) -> float:
	return float(BASE_DENSITY.get(block_type, 0.5))

static func get_tier_multiplier(block_type: String, tier: int) -> float:
	var by_type: Dictionary = TIER_MULTIPLIER.get(block_type, {})
	return float(by_type.get(tier, 1.0))

static func get_default_time_profile(block_type: String, tier: int) -> Dictionary:
	var by_type: Dictionary = DEFAULT_ACTIVE_TIME_PROFILE.get(block_type, {})
	var profile: Dictionary = by_type.get(tier, {})
	if profile.is_empty():
		return SpatialConfig.make_empty_time_profile()
	return profile.duplicate()

static func get_default_group_weights(block_type: String, tier: int) -> Dictionary:
	var by_type: Dictionary = DEFAULT_GROUP_WEIGHTS.get(block_type, {})
	var weights: Dictionary = by_type.get(tier, {})
	if weights.is_empty():
		return SpatialConfig.make_empty_group_weights()
	return weights.duplicate()

static func apply_defaults_to_block(block: BlockData, overwrite_existing: bool = false) -> void:
	if not SpatialConfig.is_valid_block_type(block.block_type):
		push_warning("BlockConfig: 未知block_type[%s]，无法应用默认模板" % block.block_type)
		return
	if not SpatialConfig.is_valid_tier(block.tier):
		push_warning("BlockConfig: 非法tier[%d]，无法应用默认模板" % block.tier)
		return

	var time_is_empty := _is_time_profile_default(block.active_time_profile)
	if overwrite_existing or time_is_empty:
		block.active_time_profile = get_default_time_profile(block.block_type, block.tier)

	var weights_is_empty := _is_group_weights_empty(block.group_supply_weights)
	if overwrite_existing or weights_is_empty:
		block.group_supply_weights = get_default_group_weights(block.block_type, block.tier)

static func _is_time_profile_default(profile: Dictionary) -> bool:
	for period in SpatialConfig.TIME_PERIODS:
		if absf(float(profile.get(period, 1.0)) - 1.0) > 0.001:
			return false
	return true

static func _is_group_weights_empty(weights: Dictionary) -> bool:
	for g in SpatialConfig.POPULATION_GROUPS:
		if float(weights.get(g, 0.0)) > 0.001:
			return false
	return true
