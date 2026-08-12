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
		if hours_worked_before_this_hour < tier.max_hours:
			return tier
	return FATIGUE_TIERS[-1]

static func get_overwork_penalty(work_hours_today: float) -> float:
	if work_hours_today > OVERWORK_PENALTY_TIER2_HOURS:
		return OVERWORK_PENALTY_TIER2_ENERGY
	elif work_hours_today > OVERWORK_PENALTY_TIER1_HOURS:
		return OVERWORK_PENALTY_TIER1_ENERGY
	return 0.0

## 把一段连续时长(小时)按8/10/12这三个疲惫阈值切成若干段，
## 每段用当时对应的疲惫倍率，不再依赖"按小时tick"这个颗粒度。
## work_hours_before：这段开始前，当天已经累计的工作小时数（不含这段）。
static func split_duration_by_fatigue_tiers(
		work_hours_before: float, duration_hours: float
) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var remaining := duration_hours
	var cursor := work_hours_before
	var thresholds := [8.0, 10.0, 12.0]

	while remaining > 0.0001:
		var tier := get_fatigue_tier(cursor)
		var next_threshold := INF
		for t in thresholds:
			if t > cursor and t < next_threshold:
				next_threshold = t

		var segment_len: float = remaining
		if next_threshold < INF:
			segment_len = minf(remaining, next_threshold - cursor)
		segment_len = maxf(segment_len, 0.0001)

		segments.append({
			"hours": segment_len,
			"energy_mult": tier.energy_mult,
			"effect_mult": tier.effect_mult,
		})

		cursor += segment_len
		remaining -= segment_len

	return segments
