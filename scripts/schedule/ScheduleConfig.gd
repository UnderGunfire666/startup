class_name ScheduleConfig

# ── 疲惫阈值（按当日已工作小时数判定，执行本小时前的累计值） ──
const FATIGUE_TIERS: Array[Dictionary] = [
	{"max_hours": 8.0,  "state": "normal",     "energy_mult": 1.00, "effect_mult": 1.00},
	{"max_hours": 10.0, "state": "tired",      "energy_mult": 1.25, "effect_mult": 0.90},
	{"max_hours": 12.0, "state": "overworked", "energy_mult": 1.60, "effect_mult": 0.75},
	{"max_hours": INF,  "state": "exhausted",  "energy_mult": 2.00, "effect_mult": 0.60},
]

const FATIGUE_STATE_NAMES: Dictionary = {
	"normal": "正常",
	"tired": "疲惫",
	"overworked": "过劳",
	"exhausted": "透支",
}

# ── 次日过劳遗留惩罚 ──
const OVERWORK_PENALTY_TIER1_HOURS: float = 10.0
const OVERWORK_PENALTY_TIER1_ENERGY: float = 10.0
const OVERWORK_PENALTY_TIER2_HOURS: float = 12.0
const OVERWORK_PENALTY_TIER2_ENERGY: float = 20.0

static func get_fatigue_tier(hours_worked_before_this_hour: float) -> Dictionary:
	for tier in FATIGUE_TIERS:
		if hours_worked_before_this_hour <= tier.max_hours:
			return tier
	return FATIGUE_TIERS[-1]

static func get_overwork_penalty(work_hours_today: float) -> float:
	if work_hours_today > OVERWORK_PENALTY_TIER2_HOURS:
		return OVERWORK_PENALTY_TIER2_ENERGY
	elif work_hours_today > OVERWORK_PENALTY_TIER1_HOURS:
		return OVERWORK_PENALTY_TIER1_ENERGY
	return 0.0
