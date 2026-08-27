class_name DemandPatternCalculator

## Deterministic recurring demand. It deliberately contains no random state so
## save/load and report forecasts agree for the same day and hour.
static func get_group_multiplier(block: BlockData, group_id: String, day: int, hour: int) -> float:
	if block == null:
		return 1.0
	var weekday := TimeManager.is_weekday(day)
	var multiplier := 1.0
	if group_id == "student" and block.block_type == "school":
		if weekday and hour >= 17 and hour < 19:
			multiplier *= 1.65
		elif weekday and hour >= 7 and hour < 9:
			multiplier *= 1.20
	if group_id == "office_worker" and block.block_type == "office":
		if weekday and hour >= 11 and hour < 14:
			multiplier *= 1.35
		elif weekday and hour >= 17 and hour < 19:
			multiplier *= 1.18
	if group_id == "family_household" and (block.block_type == "residential" or block.block_type == "commercial") and hour >= 17 and hour < 21:
		multiplier *= 1.18
	return multiplier

static func get_forecast_summary(block: BlockData, day: int, hour: int) -> Dictionary:
	var groups := {}
	for group_id in SpatialConfig.POPULATION_GROUPS:
		groups[group_id] = get_group_multiplier(block, group_id, day, hour)
	return {"day": day, "hour": hour, "groups": groups}
