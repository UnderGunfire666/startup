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
		push_error("GameData: 数据文件不存在 -> %s" % path)
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	var text := file.get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("GameData: JSON解析失败 -> %s" % path)
		return []
	if typeof(parsed) != TYPE_ARRAY:
		push_error("GameData: 顶层结构应为数组 -> %s" % path)
		return []
	return parsed

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
