class_name SpatialConfig
## 空间系统的枚举与全局常量。

# ── 城市区位类型 ──────────────────────────────────────────
const CITY_REGION_TYPES: Array[String] = ["urban", "suburban", "town"]

# ── 区块类型 ──────────────────────────────────────────────
const BLOCK_TYPES: Array[String] = [
	"school", "office", "commercial", "industrial", "residential",
	"mixed", "tourism", "public_green",
]

# ── 区块/区位等级，统一用1/2/3 ───────────────────────────
const MIN_TIER: int = 1
const MAX_TIER: int = 3

# ── 五类核心人群 ──────────────────────────────────────────
const POPULATION_GROUPS: Array[String] = [
	"student",
	"office_worker",
	"worker",
	"family_household",
	"high_spend_household",
]

# ── 四个时段 ──────────────────────────────────────────────
const TIME_PERIODS: Array[String] = ["morning", "noon", "evening", "night"]

const HOUR_TO_PERIOD: Dictionary = {
	6: "morning", 7: "morning", 8: "morning", 9: "morning", 10: "morning",
	11: "noon", 12: "noon", 13: "noon",
	14: "evening", 15: "evening", 16: "evening", 17: "evening",
	18: "evening", 19: "evening", 20: "evening", 21: "evening",
	22: "night", 23: "night", 0: "night", 1: "night",
	2: "night", 3: "night", 4: "night", 5: "night",
}

# ── 区块了解度四档阈值（0-100，单一数值，不分层存储） ─────────
const BLOCK_UNDERSTANDING_DISCOVERED: float = 0.0
const BLOCK_UNDERSTANDING_INITIAL_SURVEY: float = 25.0
const BLOCK_UNDERSTANDING_MARKET_RESEARCH: float = 50.0
const BLOCK_UNDERSTANDING_DEEP_MASTERY: float = 75.0

const BLOCK_UNDERSTANDING_TIERS: Array[String] = [
	"discovered", "initial_survey", "market_research", "deep_mastery",
]

# ── 区域情报等级门槛（0-3级，由聚合进度值0-100换算） ──────────
const REGION_INTEL_LEVEL_THRESHOLDS: Array[float] = [10.0, 40.0, 70.0]

# ── 门面尽调状态机 ────────────────────────────────────────
const STOREFRONT_DILIGENCE_STATES: Array[String] = [
	"not_viewed", "initial_viewing", "full_diligence",
]

## 经营时"每单成交"给所在区块带来的了解度增量，默认给一个较小值。
## 具体数值请按你的游戏节奏调整。
const OPERATING_UNDERSTANDING_PER_ORDER: float = 0.05

static func get_period_for_hour(hour: int) -> String:
	return HOUR_TO_PERIOD.get(hour, "night")


static func is_valid_block_type(block_type: String) -> bool:
	return block_type in BLOCK_TYPES


static func is_valid_tier(tier: int) -> bool:
	return tier >= MIN_TIER and tier <= MAX_TIER


static func is_valid_population_group(group_id: String) -> bool:
	return group_id in POPULATION_GROUPS


static func make_empty_group_weights() -> Dictionary:
	var d := {}
	for g in POPULATION_GROUPS:
		d[g] = 0.0
	return d


static func make_empty_time_profile() -> Dictionary:
	var d := {}
	for t in TIME_PERIODS:
		d[t] = 1.0
	return d


static func get_block_understanding_tier(value: float) -> String:
	if value >= BLOCK_UNDERSTANDING_DEEP_MASTERY:
		return "deep_mastery"
	if value >= BLOCK_UNDERSTANDING_MARKET_RESEARCH:
		return "market_research"
	if value >= BLOCK_UNDERSTANDING_INITIAL_SURVEY:
		return "initial_survey"
	return "discovered"


static func get_region_intel_level(progress: float) -> int:
	var level := 0
	for threshold in REGION_INTEL_LEVEL_THRESHOLDS:
		if progress >= threshold:
			level += 1
	return level


static func is_valid_storefront_diligence_state(state: String) -> bool:
	return state in STOREFRONT_DILIGENCE_STATES
