class_name GameData

const DATA_DIR := "res://data/"

static func get_regions() -> Array[RegionData]:
	var raw: Array = _load_json_array(DATA_DIR + "regions.json")
	var list: Array[RegionData] = []
	for entry in raw:
		var r: RegionData = RegionData.new()
		r.id = entry.get("id", "")
		r.name = entry.get("name", "")
		r.radiation_population = entry.get("radiation_population", 0)
		r.population_density = entry.get("population_density", "medium")
		r.primary_groups = _to_string_array(entry.get("primary_groups", []))
		r.secondary_groups = _to_string_array(entry.get("secondary_groups", []))
		r.spending_power = entry.get("spending_power", "medium")
		r.dwell_time = entry.get("dwell_time", "medium")
		r.traffic_sources = _to_string_array(entry.get("traffic_sources", []))
		r.competition_level = entry.get("competition_level", "medium")
		r.rent_baseline = entry.get("rent_baseline", "medium")
		var traffic_raw: Array = entry.get("hourly_foot_traffic_by_hour", [])
		var traffic_typed: Array[int] = []
		for v in traffic_raw:
			traffic_typed.append(int(v))
		while traffic_typed.size() < 24:
			traffic_typed.append(0)
		r.hourly_foot_traffic_by_hour = traffic_typed
		r.weekend_modifier = entry.get("weekend_modifier", 1.0)
		r.notes = entry.get("notes", "")
		r.research_cost = float(entry.get("research_cost", 800.0))
		list.append(r)
	return list

static func get_city_regions() -> Array[CityRegionData]:
	var raw := _load_json_array("res://data/city_regions.json")
	var result: Array[CityRegionData] = []

	for item in raw:
		var region := CityRegionData.new()
		region.id = str(item.get("id", ""))
		region.name = str(item.get("name", ""))
		region.region_type = str(item.get("region_type", "urban"))
		region.tier = int(item.get("tier", 1))
		region.map_bounds = _dict_to_rect2(item.get("map_bounds", {}))
		region.background_population = int(item.get("background_population", 0))
		region.density_band = str(item.get("density_band", "medium"))

		var raw_modifiers: Dictionary = item.get("location_modifiers", {})
		region.location_modifiers = {
			"rent_baseline": float(raw_modifiers.get("rent_baseline", 1.0)),
			"traffic_baseline": float(raw_modifiers.get("traffic_baseline", 1.0)),
			"competition_baseline": float(raw_modifiers.get("competition_baseline", 1.0)),
			"spending_power_baseline": float(raw_modifiers.get("spending_power_baseline", 1.0)),
			"development_potential": float(raw_modifiers.get("development_potential", 1.0)),
		}

		region.weekend_activity_modifier = float(item.get("weekend_activity_modifier", 1.0))

		var raw_tags: Array = item.get("tags", [])
		var typed_tags: Array[String] = []
		for tag in raw_tags:
			typed_tags.append(str(tag))
		region.tags = typed_tags

		region.notes = str(item.get("notes", ""))
		result.append(region)

	return result


static func get_blocks() -> Array[BlockData]:
	var raw := _load_json_array("res://data/blocks.json")
	var result: Array[BlockData] = []

	for item in raw:
		var block := BlockData.new()
		block.id = str(item.get("id", ""))
		block.name = str(item.get("name", ""))
		block.city_region_id = str(item.get("city_region_id", ""))
		block.map_bounds = _dict_to_rect2(item.get("map_bounds", {}))
		block.center_position = _dict_to_vector2(item.get("center_position", {}))
		block.block_type = str(item.get("block_type", "residential"))
		block.tier = int(item.get("tier", 1))
		block.area = float(item.get("area", 100.0))
		block.development_factor = float(item.get("development_factor", 1.0))
		block.accessibility = float(item.get("accessibility", 0.8))

		var raw_time_profile: Dictionary = item.get("active_time_profile", {})
		var time_profile := SpatialConfig.make_empty_time_profile()
		for period in SpatialConfig.TIME_PERIODS:
			time_profile[period] = float(raw_time_profile.get(period, 1.0))
		block.active_time_profile = time_profile

		var raw_weights: Dictionary = item.get("group_supply_weights", {})
		var group_weights := SpatialConfig.make_empty_group_weights()
		for group_id in SpatialConfig.POPULATION_GROUPS:
			group_weights[group_id] = float(raw_weights.get(group_id, 0.0))
		block.group_supply_weights = group_weights

		var raw_spending: Dictionary = item.get("spending_profile", {})
		block.spending_profile = {
			"price_sensitivity": float(raw_spending.get("price_sensitivity", 0.5)),
			"quality_preference": float(raw_spending.get("quality_preference", 0.5)),
			"spend_potential_tier": str(raw_spending.get("spend_potential_tier", "medium")),
		}

		var raw_demand_tags: Array = item.get("business_demand_tags", [])
		var typed_demand_tags: Array[String] = []
		for tag in raw_demand_tags:
			typed_demand_tags.append(str(tag))
		block.business_demand_tags = typed_demand_tags

		var raw_competition: Dictionary = item.get("competition_profile", {})
		block.competition_profile = {
			"competition_level": str(raw_competition.get("competition_level", "medium")),
			"rent_pressure": str(raw_competition.get("rent_pressure", "medium")),
			"rent_trend": str(raw_competition.get("rent_trend", "stable")),
			"business_risk": str(raw_competition.get("business_risk", "medium")),
			"external_attraction": float(raw_competition.get("external_attraction", 0.0)),
		}

		var raw_tags: Array = item.get("tags", [])
		var typed_tags: Array[String] = []
		for tag in raw_tags:
			typed_tags.append(str(tag))
		block.tags = typed_tags

		block.notes = str(item.get("notes", ""))
		result.append(block)

	return result

static func get_storefronts() -> Array[StorefrontData]:
	var raw: Array = _load_json_array(DATA_DIR + "storefronts.json")
	var list: Array[StorefrontData] = []
	for entry in raw:
		var s: StorefrontData = StorefrontData.new()
		s.id = entry.get("id", "")
		s.name = entry.get("name", "")
		s.region_id = entry.get("region_id", "")
		s.monthly_rent_wan = entry.get("monthly_rent_wan", 1.0)
		s.area = entry.get("area", 20)
		s.decoration_level = entry.get("decoration_level", "normal")
		s.storefront_flow = entry.get("storefront_flow", "main")
		s.flow_share = entry.get("flow_share", 0.4)
		s.supported_categories = _to_string_array(entry.get("supported_categories", []))
		s.equipment_condition = entry.get("equipment_condition", "normal")
		s.hourly_capacity_base = entry.get("hourly_capacity_base", 20)
		s.notes = entry.get("notes", "")

		## 空间系统新增字段：city_region_id留空时，
		## GameManager.begin_slot_simulation()会自动回退旧的calculate_params()路径。
		s.city_region_id = entry.get("city_region_id", "")
		var raw_position: Dictionary = entry.get("map_position", {})
		s.map_position = Vector2(
			raw_position.get("x", 0.0),
			raw_position.get("y", 0.0)
		)
		s.capture_modifier = entry.get("capture_modifier", 1.0)
		s.accessibility_modifier = entry.get("accessibility_modifier", 1.0)

		list.append(s)
	return list

static func get_categories() -> Array[CategoryData]:
	var raw: Array = _load_json_array(DATA_DIR + "categories.json")
	var list: Array[CategoryData] = []
	for entry in raw:
		var c: CategoryData = CategoryData.new()
		c.id = entry.get("id", "")
		c.name = entry.get("name", "")
		c.base_entry_rate = entry.get("base_entry_rate", 0.02)
		c.suggested_open_hour_ranges = _to_vector2i_array(entry.get("suggested_open_hours", []))
		c.preferred_groups = _to_string_array(entry.get("preferred_groups", []))
		c.preferred_spending_power = _to_string_array(entry.get("preferred_spending_power", []))
		c.base_service_speed = entry.get("base_service_speed", "medium")
		c.key_staff_type = entry.get("key_staff_type", "none")
		c.missing_key_staff_capacity_penalty = entry.get("missing_key_staff_capacity_penalty", 0.0)
		c.missing_key_staff_conversion_penalty = entry.get("missing_key_staff_conversion_penalty", 0.0)
		c.missing_key_staff_reputation_penalty = entry.get("missing_key_staff_reputation_penalty", 0.0)
		c.required_area = entry.get("required_area", 10.0)
		c.setup_cost_wan = entry.get("setup_cost_wan", 0.3)
		c.extra_rent_wan = entry.get("extra_rent_wan", 0.15)
		list.append(c)
	return list

static func get_products() -> Array[ProductData]:
	var raw: Array = _load_json_array(DATA_DIR + "products.json")
	var list: Array[ProductData] = []
	for entry in raw:
		var p: ProductData = ProductData.new()
		p.id = entry.get("id", "")
		p.category_id = entry.get("category_id", "")
		p.name = entry.get("name", "")
		p.target_groups = _to_string_array(entry.get("target_groups", []))
		p.preferred_hour_ranges = _to_vector2i_array(entry.get("preferred_hours", []))
		p.price_tier = entry.get("price_tier", "medium")
		p.average_price = entry.get("average_price", 15.0)
		p.ingredient_cost_per_unit = entry.get("ingredient_cost_per_unit", 3.0)
		p.utility_cost_per_unit = entry.get("utility_cost_per_unit", 0.5)
		p.suggested_margin_rate = entry.get("suggested_margin_rate", 0.6)
		p.complexity = entry.get("complexity", "normal")
		p.differentiation = entry.get("differentiation", "normal")
		p.extra_service_speed_modifier = entry.get("extra_service_speed_modifier", 1.0)
		p.notes = entry.get("notes", "")
		var recipe_raw: Array = entry.get("recipe", [])
		var recipe_typed: Array[Dictionary] = []
		for r in recipe_raw:
			recipe_typed.append({
				"ingredient_id": r.get("ingredient_id", ""),
				"quantity": r.get("quantity", 0.0),
			})
		p.recipe = recipe_typed
		list.append(p)
	return list

static func get_ingredients() -> Array[IngredientData]:
	var raw: Array = _load_json_array(DATA_DIR + "ingredients.json")
	var list: Array[IngredientData] = []
	for entry in raw:
		var i: IngredientData = IngredientData.new()
		i.id = entry.get("id", "")
		i.name = entry.get("name", "")
		i.unit = entry.get("unit", "")
		i.base_purchase_price = entry.get("base_purchase_price", 0.0)
		i.notes = entry.get("notes", "")
		list.append(i)
	return list
# ── 工具函数 ──────────────────────────────────────────────
static func _load_json_array(path: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("GameData: 文件不存在 %s" % path)
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)

	if parsed == null or typeof(parsed) != TYPE_ARRAY:
		push_error("GameData: JSON解析失败或格式不是数组 %s" % path)
		return []

	return parsed


static func _dict_to_rect2(raw: Dictionary) -> Rect2:
	return Rect2(
		float(raw.get("x", 0.0)),
		float(raw.get("y", 0.0)),
		float(raw.get("w", 0.0)),
		float(raw.get("h", 0.0))
	)

static func _dict_to_vector2(raw: Dictionary) -> Vector2:
	return Vector2(
		float(raw.get("x", 0.0)),
		float(raw.get("y", 0.0))
	)

static func _to_string_array(raw: Array) -> Array[String]:
	var result: Array[String] = []
	for x in raw:
		result.append(str(x))
	return result

## ── 工具函数：把 [[start,end],[start,end],...] 转成 Array[Vector2i] ──
static func _to_vector2i_array(raw: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pair in raw:
		if pair is Array and pair.size() >= 2:
			result.append(Vector2i(int(pair[0]), int(pair[1])))
	return result
