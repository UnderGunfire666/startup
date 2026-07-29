class_name GameData

# ── 区域 ─────────────────────────────────────────────────
static func get_regions() -> Array[RegionData]:
	var list: Array[RegionData] = []

	var a1: RegionData = RegionData.new()
	a1.id = "A001"
	a1.name = "东环智造园"
	a1.radiation_population = 50000
	a1.population_density = "medium"
	a1.primary_groups = ["worker", "logistics_driver"]
	a1.secondary_groups = ["night_shift_worker", "resident"]
	a1.spending_power = "low"
	a1.dwell_time = "low"
	a1.traffic_sources = ["work", "commute", "transit"]
	a1.competition_level = "medium"
	a1.rent_baseline = "low"
	a1.hourly_foot_traffic_by_slot = {"dawn": 600, "noon": 1200, "night": 700}
	a1.weekend_modifier = 1.0
	a1.notes = "平价快餐、小吃更适配；高客单饮品甜点较弱；低停留性"
	list.append(a1)

	var a2: RegionData = RegionData.new()
	a2.id = "A002"
	a2.name = "南城大学生活圈"
	a2.radiation_population = 50000
	a2.population_density = "high"
	a2.primary_groups = ["student", "family"]
	a2.secondary_groups = ["teacher", "office_worker"]
	a2.spending_power = "medium"
	a2.dwell_time = "medium"
	a2.traffic_sources = ["study", "residence", "shopping", "commute"]
	a2.competition_level = "high"
	a2.rent_baseline = "medium_high"
	a2.hourly_foot_traffic_by_slot = {"dawn": 450, "noon": 1100, "night": 1400}
	a2.weekend_modifier = 1.0
	a2.notes = "饮品甜点、小吃、平价快餐适配；竞争高；停留性中等"
	list.append(a2)

	return list


# ── 门面 ─────────────────────────────────────────────────
static func get_storefronts() -> Array[StorefrontData]:
	var list: Array[StorefrontData] = []

	var s1: StorefrontData = StorefrontData.new()
	s1.id = "S001"
	s1.name = "晨光街角档口"
	s1.region_id = "A002"
	s1.monthly_rent_wan = 0.85
	s1.area = 12
	s1.decoration_level = "good"
	s1.storefront_flow = "main"
	s1.flow_share = 0.50
	s1.supported_categories = ["breakfast", "snack", "beverage_dessert"]
	s1.equipment_condition = "normal"
	s1.hourly_capacity_base = 15
	s1.notes = "适合早餐与低油烟产品；主动线但面积小"
	list.append(s1)

	var s2: StorefrontData = StorefrontData.new()
	s2.id = "S002"
	s2.name = "旧影院后巷小馆"
	s2.region_id = "A002"
	s2.monthly_rent_wan = 1.15
	s2.area = 38
	s2.decoration_level = "poor"
	s2.storefront_flow = "hidden"
	s2.flow_share = 0.25
	s2.supported_categories = ["snack", "fast_food", "beverage_dessert"]
	s2.equipment_condition = "good"
	s2.hourly_capacity_base = 30
	s2.notes = "容量高但动线低；适合快餐或夜间小吃"
	list.append(s2)

	var s3: StorefrontData = StorefrontData.new()
	s3.id = "S003"
	s3.name = "工业园区路边摊"
	s3.region_id = "A001"
	s3.monthly_rent_wan = 0.45
	s3.area = 18
	s3.decoration_level = "normal"
	s3.storefront_flow = "secondary"
	s3.flow_share = 0.40
	s3.supported_categories = ["breakfast", "snack", "fast_food"]
	s3.equipment_condition = "normal"
	s3.hourly_capacity_base = 22
	s3.notes = "靠近园区主出入口；午间和夜班交接有稳定客流；不适合饮品甜点"
	list.append(s3)

	return list


# ── 品类 ─────────────────────────────────────────────────
static func get_categories() -> Array[CategoryData]:
	var list: Array[CategoryData] = []

	var breakfast: CategoryData = CategoryData.new()
	breakfast.id = "breakfast"
	breakfast.name = "早餐类"
	breakfast.base_entry_rate = 0.025
	breakfast.default_open_slots = ["dawn"]
	breakfast.preferred_groups = ["student", "office_worker", "worker", "commute"]
	breakfast.preferred_spending_power = ["low", "medium"]
	breakfast.preferred_slots = ["dawn"]
	breakfast.base_service_speed = "high"
	breakfast.key_staff_type = "none"
	breakfast.missing_key_staff_capacity_penalty = 0.0
	breakfast.missing_key_staff_conversion_penalty = 0.0
	breakfast.missing_key_staff_reputation_penalty = 0.0
	breakfast.allowed_strategies = ["standard", "extend", "shorten"]
	list.append(breakfast)

	var snack: CategoryData = CategoryData.new()
	snack.id = "snack"
	snack.name = "小吃类"
	snack.base_entry_rate = 0.030
	snack.default_open_slots = ["noon", "night"]
	snack.preferred_groups = ["student", "worker", "night_shift_worker"]
	snack.preferred_spending_power = ["low", "medium"]
	snack.preferred_slots = ["noon", "night"]
	snack.base_service_speed = "high"
	snack.key_staff_type = "none"
	snack.missing_key_staff_capacity_penalty = 0.0
	snack.missing_key_staff_conversion_penalty = 0.0
	snack.missing_key_staff_reputation_penalty = 0.0
	snack.allowed_strategies = ["standard", "extend", "shorten"]
	list.append(snack)

	var fast_food: CategoryData = CategoryData.new()
	fast_food.id = "fast_food"
	fast_food.name = "快餐类"
	fast_food.base_entry_rate = 0.020
	fast_food.default_open_slots = ["noon", "night"]
	fast_food.preferred_groups = ["worker", "student", "office_worker", "family"]
	fast_food.preferred_spending_power = ["low", "medium"]
	fast_food.preferred_slots = ["noon", "night"]
	fast_food.base_service_speed = "medium"
	fast_food.key_staff_type = "chef"
	fast_food.missing_key_staff_capacity_penalty = 0.20
	fast_food.missing_key_staff_conversion_penalty = 0.10
	fast_food.missing_key_staff_reputation_penalty = 2.0
	fast_food.allowed_strategies = ["standard", "extend", "shorten"]
	list.append(fast_food)

	var bev: CategoryData = CategoryData.new()
	bev.id = "beverage_dessert"
	bev.name = "饮品甜点类"
	bev.base_entry_rate = 0.025
	bev.default_open_slots = ["dawn", "noon", "night"]
	bev.preferred_groups = ["student", "family", "office_worker"]
	bev.preferred_spending_power = ["medium", "high"]
	bev.preferred_slots = ["noon", "night"]
	bev.base_service_speed = "high"
	bev.key_staff_type = "baker"
	bev.missing_key_staff_capacity_penalty = 0.15
	bev.missing_key_staff_conversion_penalty = 0.08
	bev.missing_key_staff_reputation_penalty = 1.5
	bev.allowed_strategies = ["standard", "extend", "shorten"]
	list.append(bev)

	return list


# ── 产品 ─────────────────────────────────────────────────
static func get_products() -> Array[ProductData]:
	var list: Array[ProductData] = []

	var p: ProductData

	p = ProductData.new(); p.id = "P001"; p.category_id = "breakfast"
	p.name = "豆浆油条"; p.target_groups = ["worker", "student", "commute"]
	p.preferred_slots = ["dawn"]; p.price_tier = "low"; p.average_price = 8.0
	p.ingredient_cost_ratio = 0.35; p.complexity = "simple"; p.differentiation = "normal"
	list.append(p)

	p = ProductData.new(); p.id = "P002"; p.category_id = "breakfast"
	p.name = "煎饼卷饼"; p.target_groups = ["worker", "student", "office_worker"]
	p.preferred_slots = ["dawn"]; p.price_tier = "low"; p.average_price = 11.0
	p.ingredient_cost_ratio = 0.38; p.complexity = "normal"; p.differentiation = "special"
	list.append(p)

	p = ProductData.new(); p.id = "P003"; p.category_id = "snack"
	p.name = "炸串"; p.target_groups = ["student", "worker", "night_shift_worker"]
	p.preferred_slots = ["night"]; p.price_tier = "low"; p.average_price = 16.0
	p.ingredient_cost_ratio = 0.40; p.complexity = "normal"; p.differentiation = "normal"
	list.append(p)

	p = ProductData.new(); p.id = "P004"; p.category_id = "snack"
	p.name = "麻辣拌"; p.target_groups = ["student", "worker"]
	p.preferred_slots = ["noon", "night"]; p.price_tier = "medium"; p.average_price = 24.0
	p.ingredient_cost_ratio = 0.42; p.complexity = "normal"; p.differentiation = "special"
	list.append(p)

	p = ProductData.new(); p.id = "P005"; p.category_id = "fast_food"
	p.name = "盖浇饭"; p.target_groups = ["worker", "student", "office_worker"]
	p.preferred_slots = ["noon", "night"]; p.price_tier = "medium"; p.average_price = 22.0
	p.ingredient_cost_ratio = 0.40; p.complexity = "normal"; p.differentiation = "normal"
	list.append(p)

	p = ProductData.new(); p.id = "P006"; p.category_id = "fast_food"
	p.name = "卤味饭"; p.target_groups = ["worker", "student", "family"]
	p.preferred_slots = ["noon", "night"]; p.price_tier = "medium"; p.average_price = 26.0
	p.ingredient_cost_ratio = 0.42; p.complexity = "normal"; p.differentiation = "special"
	list.append(p)

	p = ProductData.new(); p.id = "P007"; p.category_id = "beverage_dessert"
	p.name = "奶茶"; p.target_groups = ["student", "family"]
	p.preferred_slots = ["noon", "night"]; p.price_tier = "medium"; p.average_price = 18.0
	p.ingredient_cost_ratio = 0.30; p.complexity = "simple"; p.differentiation = "normal"
	list.append(p)

	p = ProductData.new(); p.id = "P008"; p.category_id = "beverage_dessert"
	p.name = "现烤面包"; p.target_groups = ["student", "family", "office_worker"]
	p.preferred_slots = ["dawn", "noon"]; p.price_tier = "medium"; p.average_price = 15.0
	p.ingredient_cost_ratio = 0.35; p.complexity = "normal"; p.differentiation = "special"
	list.append(p)

	return list
