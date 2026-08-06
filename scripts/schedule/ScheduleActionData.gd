class_name ScheduleActionData
extends RefCounted

static func get_actions() -> Array[ActionDefinition]:
	var list: Array[ActionDefinition] = []

	list.append(_make(
		"rest_short", "短暂休息", "行动", 1, 0.0,
		Vector2i(0, 24), false, "recover_energy", 10.0
	))

	list.append(_make(
		"sleep", "睡眠", "行动", 6, 0.0,
		Vector2i(0, 24), false, "recover_energy", 15.0
	))

	list.append(_make_work(
		"region_research", "区域调研", "调研", 2, 8.0,
		Vector2i(5, 24), "region_research",
		{"requires_region_selected": false}
	))

	list.append(_make_work(
		"storefront_inspection", "考察门面", "调研", 2, 10.0,
		Vector2i(9, 24), "storefront_inspection",
		{"requires_region_selected": true}
	))

	list.append(_make_work(
		"deep_inspection", "深度勘验", "调研", 3, 14.0,
		Vector2i(9, 18), "deep_inspection",
		{"requires_inspected_storefront": true}
	))

	list.append(_make_work(
		"landlord_negotiation", "与房东谈判", "调研", 1, 10.0,
		Vector2i(9, 22), "landlord_negotiation",
		{"requires_region_selected": true}
	))

	list.append(_make_work(
		"procurement", "采购/备货", "经营", 2, 9.0,
		Vector2i(5, 22), "procurement",
		{"requires_open_store": true, "requires_selected_category": true}
	))

	list.append(_make_work(
		"recruitment", "招聘面试", "经营", 2, 10.0,
		Vector2i(9, 22), "recruitment",
		{"requires_selected_category": true}
	))

	list.append(_make_work(
		"store_supervision", "亲自坐镇", "经营", 2, 12.0,
		Vector2i(0, 24), "store_supervision",
		{"requires_open_store": true, "requires_store_operating_hour": true}
	))

	list.append(_make_work(
		"closing_review", "收档复盘", "经营", 1, 7.0,
		Vector2i(0, 24), "closing_review",
		{"requires_open_store": true, "requires_today_has_settled": true}
	))

	list.append(_make_work(
		"business_planning", "经营规划", "经营", 1, 6.0,
		Vector2i(8, 24), "business_planning",
		{}
	))

	return list


static func get_action(action_id: String) -> ActionDefinition:
	for action in get_actions():
		if action.id == action_id:
			return action
	return null


static func _make(
		id: String, name: String, category: String,
		duration_hours: int, base_energy_cost_per_hour: float,
		allowed_hour_range: Vector2i, work_hour_counting: bool,
		effect_type: String, recovery_per_hour: float
) -> ActionDefinition:
	var a := ActionDefinition.new()
	a.id = id
	a.name = name
	a.category = category
	a.duration_hours = duration_hours
	a.base_energy_cost_per_hour = base_energy_cost_per_hour
	a.allowed_hour_range = allowed_hour_range
	a.work_hour_counting = work_hour_counting
	a.action_effect_type = effect_type
	a.energy_recovery_per_hour = recovery_per_hour
	a.requires_character_created = true
	return a


static func _make_work(
		id: String, name: String, category: String,
		duration_hours: int, base_energy_cost_per_hour: float,
		allowed_hour_range: Vector2i, effect_type: String,
		extra_requirements: Dictionary
) -> ActionDefinition:
	var a := _make(
		id, name, category, duration_hours, base_energy_cost_per_hour,
		allowed_hour_range, true, effect_type, 0.0
	)
	for key in extra_requirements:
		a.set(key, extra_requirements[key])
	return a
