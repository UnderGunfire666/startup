extends Node

## GameManager.gd 顶部signal区新增
signal active_store_changed(store_id: String)
signal store_plan_updated(store_id: String)
signal storefronts_discovered(storefront_ids: Array[String])

var player_state: PlayerState = PlayerState.new()
var last_settlement_error: String = ""

var current_storefront: StorefrontData = null

var all_storefronts: Array[StorefrontData] = []
var all_categories: Array[CategoryData] = []
var all_products: Array[ProductData] = []
var all_ingredients: Array[IngredientData] = []
var all_equipment: Array[EquipmentData] = []
var all_employee_candidates: Array[EmployeeCandidateData] = []

var all_city_regions: Array[CityRegionData] = []
var all_blocks: Array[BlockData] = []
var road_graph: RoadGraph = RoadGraph.new()

## ── 多店重构阶段1 ────────────────────────────────────────────
var stores: Array[Store] = []
var active_store_id: String = ""

var _next_store_sequence: int = 0

var active_simulations: Array[Dictionary] = []  # {sim, params, category, product_template, inventory_limit, product_count, store_id}

## 兼容属性：绝大多数现有代码沿用"store_state.xxx"的写法不用改，
## 它永远指向"当前激活的那家店"。角色创建完成前，stores为空，
## 这个属性会返回null——调用方必须自己判空（本文件已把所有内部
## 调用点补上了null-guard，见下方各函数）。
var store_state: Store:
	get:
		return get_active_store()


func _ready() -> void:
	all_storefronts = GameData.get_storefronts()
	all_categories  = GameData.get_categories()
	all_products    = GameData.get_products()
	all_ingredients = GameData.get_ingredients()
	all_equipment = GameData.get_equipment()
	all_employee_candidates = GameData.get_employee_candidates()

	all_city_regions = GameData.get_city_regions()
	all_blocks = GameData.get_blocks()
	road_graph = GameData.get_road_graph()
	_build_runtime_road_links()


func _build_runtime_road_links() -> void:
	for block in all_blocks:
		if not block.road_entry_node_id.is_empty() and road_graph.nodes.has(block.road_entry_node_id):
			continue
		var node_id := "entry_" + block.id
		if not road_graph.nodes.has(node_id):
			var node := RoadNode.new()
			node.id = node_id
			node.position = block.center_position
			road_graph.add_node(node)
		block.road_entry_node_id = node_id
	for index in range(1, all_blocks.size()):
		var segment := RoadSegment.new()
		segment.id = "link_" + all_blocks[index - 1].id + "_" + all_blocks[index].id
		segment.from_node_id = all_blocks[index - 1].road_entry_node_id
		segment.to_node_id = all_blocks[index].road_entry_node_id
		road_graph.add_segment(segment)
	for storefront in all_storefronts:
		if not storefront.road_segment_id.is_empty():
			continue
		var nearest_id := ""
		var nearest_distance := INF
		for segment in road_graph.segments:
			var from_node: RoadNode = road_graph.nodes.get(segment.from_node_id, null)
			var to_node: RoadNode = road_graph.nodes.get(segment.to_node_id, null)
			if from_node == null or to_node == null:
				continue
			var distance := minf(storefront.map_position.distance_to(from_node.position), storefront.map_position.distance_to(to_node.position))
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_id = segment.id
		storefront.road_segment_id = nearest_id


func create_character(data: Dictionary) -> Dictionary:
	if get_open_stores().size() > 0:
		return {
			"success": false,
			"reason": "有店铺已开业，不能重新创建角色",
		}

	var player_name := str(data.get("player_name", "")).strip_edges()
	var gender := str(data.get("gender", ""))
	var age := int(data.get("age", 0))
	var difficulty_id := str(data.get("difficulty_id", ""))
	var trait_ids_raw: Array = data.get("trait_ids", [])

	if player_name.is_empty():
		return {"success": false, "reason": "请输入创业者姓名"}

	if gender not in ["male", "female"]:
		return {"success": false, "reason": "请选择性别"}

	if age not in CharacterCreationData.get_all_ages():
		return {"success": false, "reason": "请选择20至58岁之间的年龄"}

	var difficulty := CharacterCreationData.get_difficulty(difficulty_id)
	if difficulty.is_empty():
		return {"success": false, "reason": "请选择难度"}

	var trait_ids: Array[String] = []
	var chosen_types: Dictionary = {}

	for raw_trait_id in trait_ids_raw:
		var trait_id := str(raw_trait_id)
		var trait_data := CharacterCreationData.get_trait(trait_id)

		if trait_data == null:
			return {
				"success": false,
				"reason": "存在无效特质：%s" % trait_id,
			}

		if trait_data.trait_type in chosen_types:
			return {
				"success": false,
				"reason": "每种特质类型只能选择一个",
			}

		chosen_types[trait_data.trait_type] = true
		trait_ids.append(trait_id)

	var bracket := CharacterCreationData.get_age_bracket(age)
	var used_points := 0
	for trait_id in trait_ids:
		var trait_data := CharacterCreationData.get_trait(trait_id)
		used_points += trait_data.point_cost

	var remaining_points := int(bracket.trait_points) - used_points
	if remaining_points < 0:
		return {
			"success": false,
			"reason": "特质点不足，还需要 %d 点" % abs(remaining_points),
		}

	## 创建角色会开启全新开局，不能保留此前的调研、门面、品类和库存状态。
	player_state = PlayerState.new()
	current_storefront = null
	last_settlement_error = ""

	player_state.apply_character_setup({
		"player_name": player_name,
		"gender": gender,
		"age": age,
		"difficulty_id": difficulty_id,
		"preset_id": str(data.get("preset_id", "")),
		"starting_cash": float(difficulty.starting_cash),
		"trait_ids": trait_ids,
	})

	## 创建角色不再自动开店。"有角色"和"有开店企划"是两件事：
	## 角色创建完成后玩家名下没有任何店铺，必须去"我的店铺"主动新建一个
	## 企划（create_new_store()），才能开始选区域/门面/品类这些准备工作。
	stores = []
	active_store_id = ""

	TimeManager.reset()

	ScheduleManager.reset_for_new_game()

	return {
		"success": true,
		"reason": "创业者「%s」已创建，初始资金 ¥%.0f" % [
			player_state.player_name,
			player_state.cash,
		],
	}


func create_new_store(store_name: String = "") -> Dictionary:
	if not player_state.is_character_created:
		return {"success": false, "reason": "请先完成人物创建"}

	var new_store := Store.new()
	new_store.id = _generate_unique_id("store")
	new_store.name = store_name if not store_name.is_empty() else "新店铺%d" % (stores.size() + 1)
	new_store.pre_open_stage = Store.PreOpenStage.REGION_RESEARCH

	stores.append(new_store)
	active_store_id = new_store.id
	_sync_data_objects()
	active_store_changed.emit(active_store_id)

	return {"success": true, "reason": "已创建新店铺「%s」" % new_store.name, "store_id": new_store.id}


func switch_active_store(store_id: String) -> Dictionary:
	var store := get_store(store_id)
	if store == null:
		return {"success": false, "reason": "店铺不存在"}

	active_store_id = store_id
	_sync_data_objects()
	active_store_changed.emit(active_store_id)
	return {"success": true, "reason": "已切换到「%s」" % store.name}

## 决定②：一个门面不能被两家店同时占用（占用中或已签约都算）。
func is_storefront_occupied(storefront_id: String, excluding_store_id: String = "") -> bool:
	for s in stores:
		if s.id == excluding_store_id:
			continue
		if s.selected_storefront_id == storefront_id or s.signed_storefront_id == storefront_id:
			return true
	return false


# ── 多店管理API ─────────────────────────────────────────────

func get_active_store() -> Store:
	return get_store(active_store_id)


func get_store(id: String) -> Store:
	for s in stores:
		if s.id == id: return s
	return null


func get_open_stores() -> Array[Store]:
	var result: Array[Store] = []
	for s in stores:
		if s.is_open:
			result.append(s)
	return result


func get_city_region(id: String) -> CityRegionData:
	for r in all_city_regions:
		if r.id == id: return r
	return null


# ── 区块了解度 (玩家层) ────────────────────────────────────────

func get_block(id: String) -> BlockData:
	for b in all_blocks:
		if b.id == id: return b
	return null


func get_block_understanding(block_id: String) -> float:
	return player_state.get_block_understanding(block_id)


func advance_block_understanding(block_id: String, delta: float) -> Dictionary:
	if block_id.is_empty():
		return {"success": false, "reason": "区块 ID 为空"}

	var current := get_block_understanding(block_id)
	var next_value := clampf(current + delta, 0.0, 100.0)
	player_state.block_understanding[block_id] = next_value

	if current < SpatialConfig.BLOCK_UNDERSTANDING_INITIAL_SURVEY \
			and next_value >= SpatialConfig.BLOCK_UNDERSTANDING_INITIAL_SURVEY:
		_discover_storefronts_in_block(block_id)

	return {"success": true, "reason": "", "new_value": next_value}

func _generate_unique_id(prefix: String) -> String:
	_next_store_sequence += 1
	return "%s_%d_%d" % [prefix, Time.get_ticks_msec(), _next_store_sequence]

func _discover_storefronts_in_block(block_id: String) -> void:
	var block := get_block(block_id)
	if block == null:
		return

	var newly_discovered: Array[String] = []
	for storefront in all_storefronts:
		if storefront.city_region_id != block.city_region_id:
			continue
		if not block.has_map_point(storefront.map_position):
			continue
		if get_storefront_diligence(storefront.id) == "not_viewed":
			player_state.storefront_diligence[storefront.id] = "initial_viewing"
			newly_discovered.append(storefront.id)

	if not newly_discovered.is_empty():
		storefronts_discovered.emit(newly_discovered)


func reveal_all_storefronts() -> Array[String]:
	var newly_revealed: Array[String] = []
	for storefront in all_storefronts:
		if get_storefront_diligence(storefront.id) != "not_viewed":
			continue
		player_state.storefront_diligence[storefront.id] = "initial_viewing"
		newly_revealed.append(storefront.id)
	if not newly_revealed.is_empty():
		storefronts_discovered.emit(newly_revealed)
	return newly_revealed


# ── 门面尽调 (玩家层) ────────────────────────────────────────

func get_storefront_diligence(storefront_id: String) -> String:
	return player_state.get_storefront_diligence(storefront_id)


func get_storefront_diligence_progress(storefront_id: String) -> float:
	return player_state.get_storefront_diligence_progress(storefront_id)


func advance_storefront_diligence_progress(storefront_id: String, amount: float) -> Dictionary:
	if get_storefront(storefront_id) == null:
		return {"success": false, "reason": "门面不存在"}
	if get_storefront_diligence(storefront_id) == "not_viewed":
		return {"success": false, "reason": "请先完成初步看铺，再进行完整尽调"}
	return {
		"success": true,
		"progress": player_state.advance_storefront_diligence_progress(storefront_id, amount),
	}


func advance_storefront_diligence(storefront_id: String, target_state: String) -> Dictionary:
	if not SpatialConfig.is_valid_storefront_diligence_state(target_state):
		return {"success": false, "reason": "未知的尽调目标状态：%s" % target_state}

	var storefront := get_storefront(storefront_id)
	if storefront == null:
		return {"success": false, "reason": "门面不存在"}

	var current_state := get_storefront_diligence(storefront_id)

	if target_state == "initial_viewing":
		if current_state == "not_viewed":
			player_state.storefront_diligence[storefront_id] = "initial_viewing"
		return {"success": true, "reason": "已完成初步看铺"}

	if target_state == "full_diligence":
		if current_state == "not_viewed":
			return {"success": false, "reason": "请先完成初步看铺，再进行完整尽调"}
		player_state.storefront_diligence[storefront_id] = "full_diligence"
		player_state.storefront_diligence_progress[storefront_id] = 100.0
		return {"success": true, "reason": "已完成完整尽调"}

	return {"success": false, "reason": "不支持回退尽调状态"}


# ── 区域情报聚合 (玩家层) ────────────────────────────────────

func get_region_intel_level(city_region_id: String) -> int:
	return player_state.get_region_intel_level(city_region_id)


func recalculate_region_intel(city_region_id: String) -> void:
	var city_region := get_city_region(city_region_id)
	if city_region == null:
		return

	var region_blocks: Array[BlockData] = []
	for b in all_blocks:
		if b.city_region_id == city_region_id:
			region_blocks.append(b)

	if region_blocks.is_empty():
		return

	var total := 0.0
	for b in region_blocks:
		total += get_block_understanding(b.id)
	var average := total / float(region_blocks.size())

	## 经营时间加成：通过 Store 选定的门面解析 city_region_id（门面归属的唯一权威来源）。
	var days: Dictionary = {}
	for s in stores:
		if s.selected_storefront_id.is_empty():
			continue

		var storefront := get_storefront(s.selected_storefront_id)
		if storefront == null or storefront.city_region_id != city_region_id:
			continue

		for entry in s.daily_history:
			days[entry.get("day", -1)] = true
	var operating_days := days.size()

	var progress := clampf(average + float(operating_days), 0.0, 100.0)

	player_state.region_intel_progress[city_region_id] = progress
	player_state.region_intel_levels[city_region_id] = SpatialConfig.get_region_intel_level(progress)


# ── 调查区 (玩家层，仅作批量选区块的地图工具) ────────────────────

func create_survey_area(city_region_id: String, center_position: Vector2, radius: float) -> Dictionary:
	if not player_state.is_character_created:
		return {"success": false, "reason": "请先完成人物创建"}

	var city_region := get_city_region(city_region_id)
	if city_region == null:
		return {"success": false, "reason": "固定城市区域不存在"}

	if radius <= 0.0:
		return {"success": false, "reason": "调查半径必须大于 0"}

	var area := SurveyAreaState.new()
	area.id = _generate_unique_id("survey")
	area.name = "调查区_%s" % city_region.name
	area.city_region_id = city_region_id
	area.shape_type = "radius"
	area.center_position = center_position
	area.radius = radius
	area.created_day = TimeManager.current_day
	area.last_used_day = TimeManager.current_day

	SurveyAreaCalculator.rebuild_coverages(area, all_blocks)
	player_state.add_survey_area(area)

	return {"success": true, "reason": "已创建调查区", "survey_area_id": area.id}


func resize_survey_area(survey_area_id: String, new_radius: float) -> Dictionary:
	var area := player_state.get_survey_area(survey_area_id)
	if area == null:
		return {"success": false, "reason": "调查区不存在"}
	if new_radius <= 0.0:
		return {"success": false, "reason": "调查半径必须大于 0"}

	area.radius = new_radius
	SurveyAreaCalculator.rebuild_coverages(area, all_blocks)
	return {"success": true, "reason": "调查区范围已更新"}


func get_blocks_for_survey_area(survey_area_id: String) -> Array[BlockData]:
	var area := player_state.get_survey_area(survey_area_id)
	if area == null:
		return []
	return SurveyAreaCalculator.get_covered_blocks(area, all_blocks)


# ── 门面/品类/商品/原料查询 ─────────────────────────────────

func get_storefront(id: String) -> StorefrontData:
	for s in all_storefronts:
		if s.id == id: return s
	return null


func get_category(id: String) -> CategoryData:
	for c in all_categories:
		if c.id == id: return c
	return null


func get_product(id: String) -> ProductData:
	for p in all_products:
		if p.id == id: return p
	return null

func get_equipment(id: String) -> EquipmentData:
	for item in all_equipment:
		if item.id == id:
			return item
	return null

func get_employee_candidate(id: String) -> EmployeeCandidateData:
	for candidate in all_employee_candidates:
		if candidate.id == id:
			return candidate
	return null


func get_products_for_category(category_id: String) -> Array[ProductData]:
	var result: Array[ProductData] = []
	for p in all_products:
		if p.category_id == category_id or p.is_universal:
			result.append(p)
	return result


func get_ingredient(id: String) -> IngredientData:
	for i in all_ingredients:
		if i.id == id: return i
	return null


## 修复：store_state可能为null（角色创建完成前），加null-guard。
func get_ingredients_in_use() -> Array[IngredientData]:
	var result: Array[IngredientData] = []
	var store := store_state
	if store == null:
		return result

	var used_ids: Dictionary = {}
	for slot in store.category_slots:
		for pc in slot.product_configs:
			var product := get_product(pc.product_id)
			if product == null:
				continue
			for r in product.recipe:
				used_ids[r.ingredient_id] = true
	for id in used_ids.keys():
		var ing := get_ingredient(id)
		if ing != null:
			result.append(ing)
	return result


func get_ingredient_purchase_price(ingredient_id: String) -> float:
	var ingredient := get_ingredient(ingredient_id)
	if ingredient == null:
		return 0.0
	return ingredient.base_purchase_price


func get_product_unit_utility_cost(product: ProductData) -> float:
	return product.utility_cost_per_unit


func get_product_unit_ingredient_cost_for_store(
		store: Store,
		product: ProductData,
		consumption_multiplier: float = 1.0
) -> float:
	if store == null:
		return 0.0
	var total_cost := 0.0
	for recipe_item in product.recipe:
		var ingredient_id: String = recipe_item.get("ingredient_id", "")
		var quantity: float = float(recipe_item.get("quantity", 0.0))
		total_cost += quantity * maxf(1.0, consumption_multiplier) * store.get_ingredient_avg_cost(ingredient_id)
	return total_cost


# ── 选址（对"当前激活店铺"操作） ───────────────────────────────
## 决定：选址不再需要"先选区域"这一步（RegionData/region_id体系已废弃）。
## 门面的city_region_id就是唯一权威归属来源，选定门面 = 直接落实到企划。

func select_storefront(storefront_id: String) -> Dictionary:
	if not player_state.is_character_created:
		return {"success": false, "reason": "请先完成人物创建"}

	var store := get_active_store()
	if store == null:
		return {"success": false, "reason": "当前没有激活的店铺"}

	if store.is_open:
		return {"success": false, "reason": "门店已开业，不能更换门面"}

	var sf := get_storefront(storefront_id)
	if sf == null:
		return {"success": false, "reason": "门面不存在"}

	## 决定②：门面占用校验。
	if is_storefront_occupied(storefront_id, store.id):
		return {"success": false, "reason": "该门面已被你名下其他店铺占用"}

	store.selected_storefront_id = storefront_id
	store.signed_storefront_id = ""
	store.pre_open_stage = Store.PreOpenStage.STORE_SETUP
	_sync_data_objects()
	store_plan_updated.emit(store.id)

	return {"success": true, "reason": "已选定门面：「%s」" % sf.name}


func sign_selected_storefront() -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "当前没有激活的开店企划"}
	if store.is_open:
		return {"success": false, "reason": "门店已开业，不能修改签约门面"}
	if store.selected_storefront_id.is_empty():
		return {"success": false, "reason": "请先选定门面"}
	var storefront := get_storefront(store.selected_storefront_id)
	if storefront == null:
		return {"success": false, "reason": "选定门面不存在"}
	store.signed_storefront_id = storefront.id
	_sync_data_objects()
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "已签约门面：「%s」" % storefront.name}


func calculate_purchase_total(cart: Dictionary) -> float:
	var total := 0.0
	for ingredient_id in cart:
		var quantity := float(cart[ingredient_id])
		if quantity <= 0.0:
			continue
		total += get_ingredient_purchase_price(ingredient_id) * quantity
	return total


## 修复：store_state可能为null，加null-guard。
func purchase_ingredients(cart: Dictionary) -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "当前没有激活的店铺"}
	if store.signed_storefront_id.is_empty() or store.category_slots.is_empty():
		return {"success": false, "reason": "请先签约门面并确定至少一个品类后再采购"}

	var total_cost := calculate_purchase_total(cart)

	if cart.is_empty():
		return {"success": false, "reason": "未选择任何原材料"}

	if total_cost <= 0.0:
		return {"success": false, "reason": "采购数量必须大于 0"}

	if player_state.cash < total_cost:
		return {
			"success": false,
			"reason": "现金不足，需要%.0f 元，当前仅有%.0f 元"
			% [total_cost, player_state.cash]
		}

	for ingredient_id in cart:
		var quantity := float(cart[ingredient_id])
		if quantity <= 0.0:
			continue

		var ingredient := get_ingredient(ingredient_id)
		if ingredient == null:
			return {"success": false, "reason": "原材料不存在：" + ingredient_id}

		var unit_price := get_ingredient_purchase_price(ingredient_id)
		store.add_ingredient_stock(
			ingredient_id,
			quantity,
			unit_price
		)

	player_state.cash -= total_cost
	store.purchase_history.append({
		"day": TimeManager.current_day,
		"hour": TimeManager.get_current_hour_int(),
		"minute": int((TimeManager.get_hour_of_day() - TimeManager.get_current_hour_int()) * 60.0),
		"items": cart.duplicate(),
		"total_cost": total_cost,
	})

	return {
		"success": true,
		"reason": "采购完成",
		"total_cost": total_cost
	}


## 修复：store_state可能为null，加null-guard，返回0.0。
func get_product_unit_ingredient_cost(product: ProductData) -> float:
	var store := store_state
	if store == null:
		return 0.0

	var total_cost := 0.0
	for recipe_item in product.recipe:
		var ingredient_id: String = recipe_item.get("ingredient_id", "")
		var quantity: float = float(recipe_item.get("quantity", 0.0))
		total_cost += quantity * store.get_ingredient_avg_cost(ingredient_id)

	return total_cost


## 修复：store_state可能为null，加null-guard，静默忽略。
func set_ingredient_stock(ingredient_id: String, amount: float) -> void:
	var store := store_state
	if store == null:
		return
	store.set_ingredient_stock(ingredient_id, amount)


func _sync_data_objects() -> void:
	var store := get_active_store()
	if store == null:
		current_storefront = null
		return
	current_storefront = get_storefront(store.selected_storefront_id)


# ── 品类添加/管理（对"当前激活店铺"操作） ───────────────────────

func get_category_options_for_current_store() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var store := store_state
	if store == null:
		return options
	for cat in all_categories:
		var already_added := store.has_category(cat.id)
		options.append({
			"category": cat,
			"already_added": already_added,
			"can_add": not already_added,
			"reason": "已添加" if already_added else "",
		})
	return options


func get_required_equipment_for_current_store() -> Array[EquipmentData]:
	var result: Array[EquipmentData] = []
	var seen: Dictionary = {}
	var store := store_state
	if store == null:
		return result
	for slot in store.category_slots:
		var category := get_category(slot.category_id)
		if category == null:
			continue
		var has_category_product := false
		for config in slot.product_configs:
			var product := get_product(config.product_id)
			if product != null and not product.is_universal:
				has_category_product = true
				break
		if not has_category_product:
			continue
		for equipment_id in category.required_equipment_ids:
			if seen.has(equipment_id):
				continue
			var item := get_equipment(equipment_id)
			if item != null:
				seen[equipment_id] = true
				result.append(item)
	return result


func get_missing_equipment_for_store(store: Store) -> Array[EquipmentData]:
	var result: Array[EquipmentData] = []
	if store == null:
		return result
	var seen: Dictionary = {}
	for slot in store.category_slots:
		var category := get_category(slot.category_id)
		if category == null:
			continue
		var has_category_product := false
		for config in slot.product_configs:
			var product := get_product(config.product_id)
			if product != null and not product.is_universal:
				has_category_product = true
				break
		if not has_category_product:
			continue
		for equipment_id in category.required_equipment_ids:
			if store.has_equipment(equipment_id) or seen.has(equipment_id):
				continue
			var item := get_equipment(equipment_id)
			if item != null:
				seen[equipment_id] = true
				result.append(item)
	return result


func get_missing_placed_equipment_for_store(store: Store) -> Array[EquipmentData]:
	var result: Array[EquipmentData] = []
	if store == null:
		return result
	var seen: Dictionary = {}
	for slot in store.category_slots:
		var category := get_category(slot.category_id)
		if category == null:
			continue
		var has_category_product := false
		for config in slot.product_configs:
			var product := get_product(config.product_id)
			if product != null and not product.is_universal:
				has_category_product = true
				break
		if not has_category_product:
			continue
		for equipment_id in category.required_equipment_ids:
			if StoreLayoutEffects.has_placed_equipment(store, equipment_id) or seen.has(equipment_id):
				continue
			var item := get_equipment(equipment_id)
			if item != null:
				seen[equipment_id] = true
				result.append(item)
	return result


func store_has_category_equipment(store: Store, category: CategoryData) -> bool:
	if store == null or category == null:
		return false
	var slot := store.get_slot_by_category(category.id)
	if slot == null:
		return false
	var has_category_product := false
	for config in slot.product_configs:
		var product := get_product(config.product_id)
		if product != null and not product.is_universal:
			has_category_product = true
			break
	if not has_category_product:
		return true
	for equipment_id in category.required_equipment_ids:
		if not StoreLayoutEffects.has_placed_equipment(store, equipment_id):
			return false
	return true


func get_equipment_used_area(store: Store) -> float:
	return store.get_equipment_used_area(all_equipment) if store != null else 0.0


func _get_layout_footprint_sizes() -> Dictionary:
	var footprints: Dictionary = {}
	for equipment in all_equipment:
		if equipment.area <= 1.3:
			footprints[equipment.id] = Vector2i(1, 1)
		elif equipment.area <= 2.5:
			footprints[equipment.id] = Vector2i(2, 1)
		else:
			footprints[equipment.id] = Vector2i(2, 2)
	return footprints


func get_equipment_hourly_utility_cost(store: Store) -> float:
	if store == null:
		return 0.0
	var total := 0.0
	var placed_ids := StoreLayoutEffects.get_placed_instance_ids(store)
	for owned in store.equipment:
		if not placed_ids.has(owned.instance_id):
			continue
		var item := get_equipment(owned.equipment_id)
		if item != null:
			total += item.hourly_utility_cost
	return total


func get_storage_equipment_hourly_utility_cost(store: Store) -> float:
	var total := 0.0
	if store == null:
		return total
	var placed_ids := StoreLayoutEffects.get_placed_instance_ids(store)
	for owned in store.equipment:
		if not placed_ids.has(owned.instance_id):
			continue
		var item := get_equipment(owned.equipment_id)
		if item != null and not item.storage_conditions.is_empty():
			total += item.hourly_utility_cost
	return total


func get_ingredient_spoilage_ratios(store: Store) -> Dictionary:
	var ratios: Dictionary = {}
	if store == null:
		return ratios
	var stock_by_condition: Dictionary = {}
	var capacity_by_condition: Dictionary = {}
	var best_multiplier_by_condition: Dictionary = {}
	for ingredient in all_ingredients:
		var condition := ingredient.storage_condition
		stock_by_condition[condition] = float(stock_by_condition.get(condition, 0.0)) + store.get_ingredient_stock(ingredient.id)
	var placed_ids := StoreLayoutEffects.get_placed_instance_ids(store)
	for owned in store.equipment:
		if not placed_ids.has(owned.instance_id):
			continue
		var equipment := get_equipment(owned.equipment_id)
		if equipment == null:
			continue
		for condition in equipment.storage_conditions:
			capacity_by_condition[condition] = float(capacity_by_condition.get(condition, 0.0)) + equipment.storage_capacity
			var current_best := float(best_multiplier_by_condition.get(condition, 1.0))
			best_multiplier_by_condition[condition] = minf(current_best, equipment.spoilage_multiplier)
	for ingredient in all_ingredients:
		var condition := ingredient.storage_condition
		var total_stock := float(stock_by_condition.get(condition, 0.0))
		var protected_share := minf(1.0, float(capacity_by_condition.get(condition, 0.0)) / total_stock) if total_stock > 0.0 else 0.0
		var protected_multiplier := float(best_multiplier_by_condition.get(condition, 1.0))
		var effective_multiplier := 1.0 - protected_share * (1.0 - protected_multiplier)
		ratios[ingredient.id] = SettlementConfig.INGREDIENT_SPOILAGE_RATIO_PER_OPEN_SLOT * effective_multiplier
	return ratios


func get_estimated_orders_supported(store: Store) -> int:
	if store == null:
		return 0
	var average_demand: Dictionary = {}
	var product_count := 0
	for category_slot in store.category_slots:
		for config in category_slot.product_configs:
			var product := get_product(config.product_id)
			if product == null or product.recipe.is_empty():
				continue
			product_count += 1
			for recipe_item in product.recipe:
				var ingredient_id := str(recipe_item.ingredient_id)
				average_demand[ingredient_id] = float(average_demand.get(ingredient_id, 0.0)) + float(recipe_item.quantity)
	if product_count <= 0 or average_demand.is_empty():
		return 0
	var supported := INF
	for ingredient_id in average_demand:
		var per_order := float(average_demand[ingredient_id]) / float(product_count) * (1.0 + SettlementConfig.PREPARATION_WASTE_RATIO)
		if per_order > 0.0:
			supported = minf(supported, floorf(store.get_ingredient_stock(ingredient_id) / per_order))
	return int(supported) if supported != INF else 0


func get_scheduled_staff_hourly_cost(store: Store, hour: int) -> float:
	if store == null:
		return 0.0
	var total := 0.0
	for employee in store.employees:
		if employee.is_scheduled_at_hour(hour):
			total += employee.hourly_wage
	return total


func get_staff_skill_coverage(store: Store, hour: int = -1) -> Dictionary:
	var coverage: Dictionary = {}
	if store == null:
		return coverage
	for slot in store.category_slots:
		var category := get_category(slot.category_id)
		if category == null or category.required_staff.is_empty():
			continue
		coverage[category.required_staff] = store.has_employee_with_skill(category.required_staff, hour)
	return coverage


func get_category_staffing_status(store: Store, category: CategoryData, hour: int) -> Dictionary:
	var required := maxi(1, category.required_staff_count) if category != null else 1
	var scheduled := 0
	if store == null or category == null:
		return {"required": required, "scheduled": scheduled, "ratio": 0.0}
	for employee in store.employees:
		if employee.is_scheduled_at_hour(hour) and employee.has_skill(category.required_staff):
			scheduled += 1
	if player_state.supervising_store_id == store.id:
		scheduled += 1
	return {
		"required": required,
		"scheduled": scheduled,
		"ratio": minf(1.0, float(scheduled) / float(required)),
	}


func get_category_staffing_power(store: Store, category: CategoryData, hour: int) -> float:
	if store == null or category == null:
		return 0.0
	var power := 0.0
	for employee in store.employees:
		if employee.is_scheduled_at_hour(hour) and employee.has_skill(category.required_staff):
			power += employee.skill_level
	if player_state.supervising_store_id == store.id:
		## The owner is a real worker. A matching professional skill improves
		## their contribution, while an untrained owner can still handle basic work.
		power += maxf(0.85, player_state.work_skill_level if player_state.has_work_skill(category.required_staff) else 0.0)
	return power


func get_category_ingredient_consumption_multiplier(store: Store, category: CategoryData, hour: int) -> float:
	var waste_ratio := SettlementConfig.PREPARATION_WASTE_RATIO
	if store == null or category == null:
		return 1.0 + waste_ratio
	for employee in store.employees:
		if not employee.is_scheduled_at_hour(hour) or not employee.has_skill(category.required_staff):
			continue
		var level := clampf(employee.skill_level, 0.5, 2.0)
		waste_ratio -= SettlementConfig.SKILLED_PREPARATION_WASTE_REDUCTION_PER_LEVEL * level
	if player_state.supervising_store_id == store.id and player_state.has_work_skill(category.required_staff):
		var player_level := clampf(player_state.work_skill_level, 0.5, 2.0)
		waste_ratio -= SettlementConfig.SKILLED_PREPARATION_WASTE_REDUCTION_PER_LEVEL * player_level
	waste_ratio = maxf(SettlementConfig.MIN_PREPARATION_WASTE_RATIO, waste_ratio)
	return 1.0 + waste_ratio


func get_product_service_seconds(category: CategoryData, product: ProductData, staffing_power: float) -> float:
	var base_seconds := 75.0
	match category.base_service_speed:
		"high":
			base_seconds = 45.0
		"slow":
			base_seconds = 120.0
	var complexity_multiplier := 1.0
	match product.complexity:
		"simple":
			complexity_multiplier = 0.8
		"complex":
			complexity_multiplier = 1.35
		"very_complex":
			complexity_multiplier = 1.7
	var speed_bonus := maxf(0.5, product.extra_service_speed_modifier)
	return maxf(10.0, base_seconds * complexity_multiplier / (maxf(0.1, staffing_power) * speed_bonus))


func hire_employee(candidate_id: String) -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "\u5f53\u524d\u6ca1\u6709\u6d3b\u8dc3\u7684\u5f00\u5e97\u4f01\u5212\u3002"}
	var candidate := get_employee_candidate(candidate_id)
	if candidate == null:
		return {"success": false, "reason": "\u62db\u8058\u5019\u9009\u4eba\u4e0d\u5b58\u5728\u3002"}
	if store.get_employee(candidate_id) != null:
		return {"success": false, "reason": "\u8be5\u5458\u5de5\u5df2\u5728\u672c\u5e97\u4efb\u804c\u3002"}
	if player_state.cash < candidate.recruitment_fee:
		return {"success": false, "reason": "\u73b0\u91d1\u4e0d\u8db3\uff0c\u8fd8\u9700 %.0f \u5143\u62db\u8058\u8d39\u3002" % (candidate.recruitment_fee - player_state.cash)}
	var employee := StoreEmployee.new()
	employee.candidate_id = candidate.id
	employee.name = candidate.name
	for skill in candidate.skills:
		employee.skills.append(skill)
	employee.hourly_wage = candidate.hourly_wage
	employee.skill_level = candidate.skill_level
	store.employees.append(employee)
	player_state.cash -= candidate.recruitment_fee
	TimeManager.refresh_current_store_staffing(store)
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "\u5df2\u62db\u8058%s\u3002" % employee.name}


func set_employee_work_hours(candidate_id: String, work_hour_ranges: Array[Vector2i]) -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "\u5f53\u524d\u6ca1\u6709\u6d3b\u8dc3\u7684\u5f00\u5e97\u4f01\u5212\u3002"}
	var employee := store.get_employee(candidate_id)
	if employee == null:
		return {"success": false, "reason": "\u5458\u5de5\u4e0d\u5728\u672c\u5e97\u4efb\u804c\u3002"}
	for hour_range in work_hour_ranges:
		if hour_range.x < 0 or hour_range.y > 24 or hour_range.y <= hour_range.x:
			return {"success": false, "reason": "\u6392\u73ed\u65f6\u95f4\u65e0\u6548\u3002"}
	var copied_ranges: Array[Vector2i] = []
	for hour_range in work_hour_ranges:
		copied_ranges.append(hour_range)
	employee.work_hour_ranges = copied_ranges
	TimeManager.refresh_current_store_staffing(store)
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "\u6392\u73ed\u5df2\u66f4\u65b0\u3002"}


func purchase_equipment(equipment_id: String) -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "\u5f53\u524d\u6ca1\u6709\u6d3b\u8dc3\u7684\u5f00\u5e97\u4f01\u5212\u3002"}
	var storefront := get_storefront(store.signed_storefront_id)
	if storefront == null:
		return {"success": false, "reason": "\u8bf7\u5148\u7b7e\u7ea6\u95e8\u9762\u540e\u518d\u8d2d\u7f6e\u8bbe\u5907\u3002"}
	var item := get_equipment(equipment_id)
	if item == null:
		return {"success": false, "reason": "\u8bbe\u5907\u4e0d\u5b58\u5728\u3002"}
	if player_state.cash < item.price:
		return {"success": false, "reason": "\u73b0\u91d1\u4e0d\u8db3\uff0c\u8fd8\u9700 %.0f \u5143\u3002" % (item.price - player_state.cash)}
	var remaining_area := storefront.area - get_equipment_used_area(store)
	if remaining_area + 0.001 < item.area:
		return {"success": false, "reason": "\u95e8\u9762\u5269\u4f59\u9762\u79ef\u4e0d\u8db3\uff08\u8fd8\u5269 %.1f \u33a1\uff09" % maxf(0.0, remaining_area)}
	var owned := StoreEquipment.new()
	owned.instance_id = "equipment_%d_%d" % [Time.get_ticks_msec(), store.equipment.size()]
	owned.equipment_id = item.id
	owned.durability = item.max_durability
	store.equipment.append(owned)
	player_state.cash -= item.price
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "\u5df2\u8d2d\u7f6e%s\u3002" % item.name}
	var ignored_legacy_body := """
	var store := store_state
	if store == null:
		return {"success": false, "reason": "当前没有激活的开店企划"}
	var storefront := get_storefront(store.signed_storefront_id)
	if storefront == null:
		return {"success": false, "reason": "请先签约门面后再购置设备"}
	var item := get_equipment(equipment_id)
	if item == null:
		return {"success": false, "reason": "设备不存在"}
	if player_state.cash < item.price:
		return {"success": false, "reason": "现金不足，还需要 %.0f 元" % (item.price - player_state.cash)}
	var remaining_area := storefront.area - get_equipment_used_area(store)
	if remaining_area + 0.001 < item.area:
		return {"success": false, "reason": "门面剩余面积不足（还剩 %.1f㎡）" % maxf(0.0, remaining_area)}
	var owned := StoreEquipment.new()
	owned.equipment_id = item.id
	owned.durability = item.max_durability
	store.equipment.append(owned)
	player_state.cash -= item.price
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "已购置%s" % item.name}


	"""
func add_category_to_store(category_id: String, product_ids: Array[String]) -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "当前没有激活的开店企划"}
	var cat := get_category(category_id)
	if cat == null:
		return {"success": false, "reason": "品类不存在"}
	if store.has_category(category_id):
		return {"success": false, "reason": "该品类已添加"}
	if product_ids.is_empty():
		return {"success": false, "reason": "请至少选择一个商品"}
	var setup_cost := cat.setup_cost_wan * 10000.0
	if player_state.cash < setup_cost:
		return {"success": false, "reason": "现金不足，开设需要%.0f 元装修/设备投入" % setup_cost}

	var slot := StoreCategorySlot.new()
	slot.category_id = category_id
	for pid in product_ids:
		var product := get_product(pid)
		if product == null or (product.category_id != category_id and not product.is_universal):
			return {"success": false, "reason": "商品不属于该子类"}
		var pc := StoreProductConfig.new()
		pc.product_id = pid
		## 库存只由原材料决定；不再为商品创建虚假的成品库存。
		pc.inventory_units = 0
		slot.product_configs.append(pc)
	store.category_slots.append(slot)
	player_state.cash -= setup_cost
	return {"success": true, "reason": ""}


func add_product_to_slot(category_id: String, product_id: String) -> bool:
	var store := store_state
	if store == null:
		return false
	var slot := store.get_slot_by_category(category_id)
	if slot == null or slot.has_product(product_id):
		return false
	var pc := StoreProductConfig.new()
	pc.product_id = product_id
	## 库存只由原材料决定；不再为商品创建虚假的成品库存。
	pc.inventory_units = 0
	slot.product_configs.append(pc)
	return true


func remove_product_from_slot(category_id: String, product_id: String) -> bool:
	var store := store_state
	if store == null:
		return false
	var slot := store.get_slot_by_category(category_id)
	if slot == null:
		return false
	for i in range(slot.product_configs.size()):
		if slot.product_configs[i].product_id == product_id:
			slot.product_configs.remove_at(i)
			return true
	return false


func remove_category_from_store(category_id: String) -> bool:
	var store := store_state
	if store == null:
		return false
	for i in range(store.category_slots.size()):
		if store.category_slots[i].category_id == category_id:
			store.category_slots.remove_at(i)
			return true
	return false


func set_product_price_override(category_id: String, product_id: String, new_price: float) -> bool:
	var store := store_state
	if store == null:
		return false
	var slot := store.get_slot_by_category(category_id)
	if slot == null:
		return false
	var pc := slot.get_product_config(product_id)
	if pc == null:
		return false
	pc.custom_price = new_price
	return true


func set_product_inventory(category_id: String, product_id: String, new_units: int) -> bool:
	var store := store_state
	if store == null:
		return false
	var slot := store.get_slot_by_category(category_id)
	if slot == null:
		return false
	var pc := slot.get_product_config(product_id)
	if pc == null:
		return false
	pc.inventory_units = maxi(0, new_units)
	return true


func set_store_business_hours(business_hour_ranges: Array[Vector2i]) -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "\u5f53\u524d\u6ca1\u6709\u6d3b\u8dc3\u7684\u5f00\u5e97\u4f01\u5212\u3002"}
	if store.is_open:
		return {"success": false, "reason": "\u95e8\u5e97\u5df2\u5f00\u4e1a\uff0c\u8bf7\u4f7f\u7528\u5f00\u95e8\u6216\u5173\u95e8\u63a7\u5236\u5f53\u524d\u8425\u4e1a\u3002"}
	if business_hour_ranges.is_empty():
		return {"success": false, "reason": "\u8bf7\u81f3\u5c11\u8bbe\u7f6e\u4e00\u6bb5\u8425\u4e1a\u65f6\u95f4\u3002"}
	for hour_range in business_hour_ranges:
		if hour_range.x < 0 or hour_range.y > 24 or hour_range.y <= hour_range.x:
			return {"success": false, "reason": "\u8425\u4e1a\u65f6\u95f4\u65e0\u6548\u3002"}
	var copied_ranges: Array[Vector2i] = []
	for hour_range in business_hour_ranges:
		copied_ranges.append(hour_range)
	store.business_hour_ranges = copied_ranges
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "\u8425\u4e1a\u65f6\u95f4\u5df2\u8bbe\u7f6e\u3002"}


func open_business() -> Dictionary:
	var store := store_state
	if store == null or not store.is_open:
		return {"success": false, "reason": "\u95e8\u5e97\u5c1a\u672a\u5f00\u4e1a\u3002"}
	if store.is_business_open:
		return {"success": false, "reason": "\u95e8\u5e97\u5df2\u5904\u4e8e\u8425\u4e1a\u72b6\u6001\u3002"}
	store.is_business_open = true
	TimeManager.refresh_current_store_staffing(store)
	## 开门是明确的经营开始指令。读档后时间默认暂停，此处恢复一倍速，
	## 让门店立刻进入当前时段的模拟而非只改变界面文字。
	if TimeManager.speed == TimeManager.Speed.PAUSED:
		TimeManager.set_speed(TimeManager.Speed.X1)
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "\u5df2\u5f00\u95e8\u8425\u4e1a\uff0c\u65f6\u95f4\u5df2\u6062\u590d 1 \u500d\u901f\u3002"}


func close_business() -> Dictionary:
	var store := store_state
	if store == null or not store.is_open:
		return {"success": false, "reason": "\u95e8\u5e97\u5c1a\u672a\u5f00\u4e1a\u3002"}
	if not store.is_business_open:
		return {"success": false, "reason": "\u95e8\u5e97\u5df2\u5904\u4e8e\u5173\u95e8\u72b6\u6001\u3002"}
	store.is_business_open = false
	TimeManager.refresh_current_store_staffing(store)
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "\u5df2\u5173\u95e8\u6b47\u4e1a\u3002"}


func set_category_area(category_id: String, new_area: float) -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "当前没有激活的店铺", "clamped_area": 0.0}
	var slot := store.get_slot_by_category(category_id)
	if slot == null:
		return {"success": false, "reason": "品类不存在", "clamped_area": 0.0}
	## 品类不再占用或限制门面面积，保留接口仅兼容旧调用。
	return {"success": true, "reason": "", "clamped_area": 0.0}


# ── 开业 ────────────────────────────────────────────────

func get_open_readiness() -> Dictionary:
	var checks: Array[Dictionary] = []
	var store := store_state

	var has_storefront := store != null and not store.signed_storefront_id.is_empty()
	checks.append({
		"label": "已签约门面",
		"passed": has_storefront,
	})

	var has_category := store != null and not store.category_slots.is_empty()
	checks.append({
		"label": "已添加至少一个经营品类",
		"passed": has_category,
	})

	var missing_equipment := get_missing_placed_equipment_for_store(store)
	var has_required_equipment := missing_equipment.is_empty()
	var missing_names: Array[String] = []
	for item in missing_equipment:
		missing_names.append(item.name)
	checks.append({
		"label": "已摆放经营商品所需设备" + ("" if has_required_equipment else "（未摆放：" + "、".join(missing_names) + "）"),
		"passed": has_required_equipment,
	})
	var storefront := get_storefront(store.signed_storefront_id) if store != null else null
	var geometry := StorefrontLayoutGeometry.from_storefront(storefront) if storefront != null else null
	var entrance_exists := StoreLayoutEffects.has_entrance(store, geometry)
	var entrance_clear := StoreLayoutEffects.has_clear_entrance(store, geometry, _get_layout_footprint_sizes())
	checks.append({"label": "已设置门面入口", "passed": entrance_exists})
	checks.append({"label": "入口内侧保持净空", "passed": entrance_clear})

	var can_open: bool = has_storefront and has_category and has_required_equipment and entrance_exists and entrance_clear

	return {
		"can_open": can_open,
		"checks": checks,
	}


func open_store() -> Dictionary:
	var store := store_state
	if store == null:
		return {"success": false, "reason": "当前没有激活的店铺"}
	if store.is_open:
		return {"success": false, "reason": "门店已经开业"}
	if store.pre_open_stage != Store.PreOpenStage.STORE_SETUP:
		return {"success": false, "reason": "当前筹备阶段不能开业"}
	var readiness := get_open_readiness()
	if not readiness.can_open:
		return {"success": false, "reason": "开业条件尚未全部满足，请查看开业清单"}
	store.is_open = true
	store.pre_open_stage = Store.PreOpenStage.OPEN_FOR_BUSINESS
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "门店已开业！"}


## 开始全新一局：完全重建门店与玩家状态，不保留任何选择/进度/存档影响。
func start_new_game() -> void:
	stores = []
	active_store_id = ""
	player_state = PlayerState.new()
	current_storefront = null
	last_settlement_error = ""
	active_simulations.clear()
	TimeManager.reset()
	ScheduleManager.reset_for_new_game()
	EventManager.reset_for_new_game()


func begin_slot_simulation() -> void:
	active_simulations.clear()
	for store in get_open_stores():
		_begin_slot_simulation_for_store(store)


func _begin_slot_simulation_for_store(store: Store) -> void:
	var storefront := get_storefront(store.selected_storefront_id)
	if storefront == null or store.category_slots.is_empty():
		return
	var city_region := get_city_region(storefront.city_region_id)
	if city_region == null:
		return

	var hour := TimeManager.get_current_hour_int()
	var is_weekend := (TimeManager.current_day % 7) in SettlementConfig.WEEKEND_DAY_REMAINDERS
	var active_product_count := 0
	for category_slot in store.category_slots:
		var slot_category := get_category(category_slot.category_id)
		if slot_category == null or category_slot.product_configs.is_empty():
			continue
		if not store_has_category_equipment(store, slot_category):
			continue
		if get_category_staffing_power(store, slot_category, hour) <= 0.0:
			continue
		active_product_count += category_slot.product_configs.size()
	if active_product_count <= 0:
		return
	var block_visitor_multipliers := _get_block_visitor_multipliers()
	var city_region_visitor_multiplier := _get_city_region_visitor_multiplier(city_region.id)

	for cat_slot in store.category_slots:
		var category := get_category(cat_slot.category_id)
		if category == null or cat_slot.product_configs.is_empty():
			continue
		if not store_has_category_equipment(store, category):
			continue

		var product_count: int = cat_slot.product_configs.size()
		var product_share := 1.0 / float(active_product_count)
		var staffing_power := get_category_staffing_power(store, category, hour)
		var ingredient_consumption_multiplier := get_category_ingredient_consumption_multiplier(store, category, hour)

		for pc in cat_slot.product_configs:
			var product_template := get_product(pc.product_id)
			if product_template == null:
				continue

			var scaled_storefront: StorefrontData = storefront.duplicate()
			scaled_storefront.flow_share = storefront.flow_share * product_share
			var capture_modifier_add := EventManager.get_modifier_total(
				GameEventDefinition.Scope.STOREFRONT, storefront.id, "capture_multiplier_add")
			scaled_storefront.capture_modifier = maxf(0.0, storefront.capture_modifier * (1.0 + capture_modifier_add) * StoreLayoutEffects.get_capture_multiplier(store))

			var product_instance: ProductData = product_template.duplicate()
			product_instance.average_price = pc.get_effective_price(product_template)
			product_instance.recipe = product_template.recipe

			var trade_area := TradeAreaCalculator.calculate_snapshot(
				scaled_storefront, category.id, product_template.id, hour,
				city_region, all_blocks, is_weekend,
				TradeAreaCalculator.DEFAULT_MAX_RADIUS, block_visitor_multipliers,
				city_region_visitor_multiplier)

			var params: Dictionary = SettlementEngine.calculate_params_from_trade_area(
				trade_area, scaled_storefront, category, product_instance,
				store, player_state, hour, store.is_business_open, staffing_power)
			params.layout_capture_multiplier = StoreLayoutEffects.get_capture_multiplier(store)
			var visitor_multiplier_add := EventManager.get_modifier_total(
				GameEventDefinition.Scope.STORE, store.id, "natural_visitors_multiplier_add")
			if visitor_multiplier_add != 0.0:
				params.visitors = maxi(0, int(round(float(params.visitors) * (1.0 + visitor_multiplier_add))))
			params.visitors += get_destination_visitors(store, storefront, product_share)
			var conversion_rate_add := EventManager.get_modifier_total(
				GameEventDefinition.Scope.STORE, store.id, "conversion_rate_add")
			if conversion_rate_add != 0.0:
				params.conversion_rate = clampf(float(params.conversion_rate) + conversion_rate_add, 0.0, 1.0)

			var entry := {
				"store_id": store.id, "sim": null, "params": params, "category": category,
				"product": product_instance, "product_template": product_template,
				"inventory_limit": 0, "product_count": product_count,
				"ingredient_consumption_multiplier": ingredient_consumption_multiplier,
			}

			var available_units := 0
			var unit_ingredient_cost := 0.0
			var unit_utility_cost := 0.0
			if params.is_open:
				available_units = store.get_max_produceable_by_ingredients(product_template, ingredient_consumption_multiplier)
				unit_ingredient_cost = get_product_unit_ingredient_cost_for_store(store, product_template, ingredient_consumption_multiplier)
				unit_utility_cost = get_product_unit_utility_cost(product_template)
				entry.inventory_limit = available_units
			## 当前可制作份数完全由原材料库存决定，不再受旧成品库存限制。
			entry.inventory_limit = available_units

			if params.is_open:
				var sim := CustomerSimulator.new()
				var service_time_multiplier_add := EventManager.get_modifier_total(
					GameEventDefinition.Scope.STORE, store.id, "service_time_multiplier_add")
				var service_seconds := get_product_service_seconds(category, product_instance, staffing_power) * product_count * maxf(0.1, 1.0 + service_time_multiplier_add)
				var reserve_ingredients := _reserve_product_ingredients.bind(
					store, product_template, ingredient_consumption_multiplier)
				sim.setup(params.visitors, 3600.0, params.conversion_rate,
					service_seconds, SettlementConfig.CUSTOMER_MAX_QUEUE_WAIT_SECONDS, entry.inventory_limit,
					product_instance.average_price, unit_ingredient_cost, unit_utility_cost,
					reserve_ingredients)
				entry.sim = sim

			active_simulations.append(entry)


func advance_slot_simulation(elapsed_seconds: float) -> void:
	## 所有商品共用一个按到达时间排序的订单流；这样共享原料由真实先后顺序竞争。
	while true:
		var next_entry: Dictionary = {}
		var earliest_arrival := INF
		for entry in active_simulations:
			var sim: CustomerSimulator = entry.get("sim", null)
			if sim == null or sim.next_arrival_at > elapsed_seconds or sim.next_arrival_at > sim.slot_duration_seconds:
				continue
			if sim.next_arrival_at < earliest_arrival:
				earliest_arrival = sim.next_arrival_at
				next_entry = entry
		if next_entry.is_empty():
			break
		var next_sim: CustomerSimulator = next_entry.get("sim", null)
		if next_sim == null or not next_sim.process_next_arrival_if_due(elapsed_seconds):
			break


func get_storefront_road_exposure(storefront: StorefrontData) -> float:
	if storefront == null:
		return 0.0
	for segment in road_graph.segments:
		if segment.id == storefront.road_segment_id:
			return maxf(0.0, segment.exposure)
	return 0.0


func _get_block_visitor_multipliers() -> Dictionary:
	var multipliers: Dictionary = {}
	for block in all_blocks:
		var modifier_add := EventManager.get_modifier_total(
			GameEventDefinition.Scope.BLOCK, block.id, "natural_visitors_multiplier_add")
		if modifier_add != 0.0:
			multipliers[block.id] = maxf(0.0, 1.0 + modifier_add)
	return multipliers


func _get_city_region_visitor_multiplier(city_region_id: String) -> float:
	var modifier_add := EventManager.get_modifier_total(
		GameEventDefinition.Scope.CITY_REGION, city_region_id, "natural_visitors_multiplier_add")
	return maxf(0.0, 1.0 + modifier_add)


func get_destination_visitors(store: Store, storefront: StorefrontData, product_share: float = 1.0) -> int:
	var total := 0.0
	for source in get_destination_visitor_sources(store, storefront, product_share):
		total += float(source.get("estimated_visitors", 0.0))
	return maxi(0, int(round(total)))


func get_destination_visitor_sources(store: Store, storefront: StorefrontData, product_share: float = 1.0) -> Array[Dictionary]:
	var sources: Array[Dictionary] = []
	if store == null or storefront == null or store.reputation <= 0.0:
		return sources
	var local_block := _get_block_for_storefront(storefront)
	for block_id in store.awareness_by_block.keys():
		var awareness := float(store.awareness_by_block.get(block_id, 0.0))
		var block := get_block(str(block_id))
		# The host block belongs to the natural-visitor funnel. Destination
		# visitors must originate in other blocks to avoid double counting.
		if awareness <= 0.0 or block == null or (local_block != null and block.id == local_block.id):
			continue
		var distance := get_block_to_storefront_road_distance(block, storefront)
		var distance_factor := 1.0 / (1.0 + distance / 800.0)
		var reputation_conversion := clampf(store.reputation / 100.0, 0.0, 1.0)
		sources.append({
			"block_id": block.id,
			"awareness": awareness,
			"distance": distance,
			"distance_factor": distance_factor,
			"estimated_visitors": awareness / 100.0 * reputation_conversion * 12.0 * distance_factor * product_share,
		})
	return sources


func get_block_to_storefront_road_distance(block: BlockData, storefront: StorefrontData) -> float:
	if block == null or storefront == null:
		return INF
	var best := INF
	if road_graph.nodes.has(block.road_entry_node_id):
		for segment in road_graph.segments:
			if segment.id != storefront.road_segment_id:
				continue
			best = minf(best, road_graph.get_shortest_distance(block.road_entry_node_id, segment.from_node_id))
			best = minf(best, road_graph.get_shortest_distance(block.road_entry_node_id, segment.to_node_id))
	if is_inf(best):
		return storefront.map_position.distance_to(block.center_position)
	return best


func _reserve_product_ingredients(
		store: Store,
		product: ProductData,
		consumption_multiplier: float
) -> bool:
	return store != null and store.try_reserve_product_ingredients(
		product, 1, consumption_multiplier)


func set_player_store_presence(store: Store, present: bool) -> void:
	if store == null:
		return
	player_state.supervising_store_id = store.id if present else ""
	TimeManager.refresh_current_store_staffing(store)
	store_plan_updated.emit(store.id)


func add_player_work_skill(skill_id: String) -> bool:
	var added := player_state.add_work_skill(skill_id)
	if added and store_state != null:
		TimeManager.refresh_current_store_staffing(store_state)
		store_plan_updated.emit(store_state.id)
	return added


func refresh_active_store_staffing(store: Store) -> void:
	var has_live_entry := false
	var hour := TimeManager.get_current_hour_int()
	for entry in active_simulations:
		if str(entry.get("store_id", "")) != store.id:
			continue
		var sim: CustomerSimulator = entry.get("sim", null)
		if sim == null:
			continue
		has_live_entry = true
		if not store.is_business_open:
			sim.arrival_rate_per_second = 0.0
			sim.next_arrival_at = INF
			continue
		var category: CategoryData = entry.get("category", null)
		var product: ProductData = entry.get("product", null)
		if category == null or product == null:
			continue
		var power := get_category_staffing_power(store, category, hour)
		var product_count := maxi(1, int(entry.get("product_count", 1)))
		if power <= 0.0:
			sim.arrival_rate_per_second = 0.0
			sim.next_arrival_at = INF
			continue
		if sim.arrival_rate_per_second <= 0.0:
			var params: Dictionary = entry.get("params", {})
			sim.arrival_rate_per_second = float(params.get("visitors", 0)) / 3600.0
			sim._schedule_next_arrival(TimeManager.total_game_seconds - floor(TimeManager.total_game_seconds / 3600.0) * 3600.0)
		sim.service_time_seconds = get_product_service_seconds(category, product, power) * product_count
	if not has_live_entry and store.is_business_open:
		_begin_slot_simulation_for_store(store)


func get_store_operating_metrics(store: Store) -> Dictionary:
	var metrics := _new_operating_metrics()
	if store == null:
		return metrics
	var has_live_simulation := false
	for entry in active_simulations:
		if entry.get("store_id", "") != store.id:
			continue
		var sim: CustomerSimulator = entry.get("sim", null)
		if sim == null:
			continue
		has_live_simulation = true
		metrics.visitors += sim.visitors_so_far
		metrics.intended_orders += sim.converted_count
		metrics.orders += sim.actual_orders
		metrics.queue_left += sim.rejected_capacity_count
		metrics.inventory_left += sim.rejected_inventory_count
		metrics.service_total += sim.service_time_seconds
		metrics.service_count += 1
		metrics.wait_total += sim.total_wait_seconds
		metrics.max_wait = maxf(float(metrics.max_wait), sim.max_wait_seconds)
	if has_live_simulation:
		metrics.source = "live"
		return metrics

	var latest_day := -1
	var latest_slot := ""
	for entry in store.daily_history:
		if bool(entry.get("is_store_overhead", false)) or not bool(entry.get("is_open", false)):
			continue
		var day := int(entry.get("day", -1))
		var slot := str(entry.get("slot", ""))
		if day > latest_day or (day == latest_day and slot > latest_slot):
			latest_day = day
			latest_slot = slot
	if latest_day < 0:
		return metrics
	for entry in store.daily_history:
		if bool(entry.get("is_store_overhead", false)) or int(entry.get("day", -1)) != latest_day or str(entry.get("slot", "")) != latest_slot:
			continue
		metrics.visitors += int(entry.get("visitors", 0))
		metrics.intended_orders += int(entry.get("theoretical_orders", 0))
		metrics.orders += int(entry.get("actual_orders", 0))
		metrics.queue_left += int(entry.get("lost_capacity", 0))
		metrics.inventory_left += int(entry.get("lost_inventory", 0))
		metrics.service_total += float(entry.get("service_time_seconds", 0.0))
		metrics.service_count += 1 if float(entry.get("service_time_seconds", 0.0)) > 0.0 else 0
		metrics.wait_total += float(entry.get("average_queue_wait_seconds", 0.0)) * int(entry.get("actual_orders", 0))
		metrics.max_wait = maxf(float(metrics.max_wait), float(entry.get("max_queue_wait_seconds", 0.0)))
	metrics.source = "last"
	return metrics


func _new_operating_metrics() -> Dictionary:
	return {
		"source": "none", "visitors": 0, "intended_orders": 0, "orders": 0,
		"queue_left": 0, "inventory_left": 0, "service_total": 0.0,
		"service_count": 0, "wait_total": 0.0, "max_wait": 0.0,
	}


func finalize_slot_simulation(finished_hour: int = -1, finished_day: int = -1) -> Array[SettlementResult]:
	var results: Array[SettlementResult] = []
	var results_by_store: Dictionary = {}  # store_id -> Array[SettlementResult]，供了解度反哺用
	var operating_store_ids: Dictionary = {}
	var hour := finished_hour if finished_hour >= 0 else TimeManager.get_current_hour_int()
	var day := finished_day if finished_day >= 1 else TimeManager.current_day

	for entry in active_simulations:
		var store := get_store(entry.store_id)
		if store == null:
			continue

		var result: SettlementResult
		if entry.sim != null:
			result = SettlementEngine.finalize_from_simulation(
				entry.params, hour, day, entry.category, entry.product,
				entry.inventory_limit, entry.sim)

			var extra_upkeep: float = (entry.category.extra_rent_wan * 10000.0) / 30.0 / 24.0 / entry.product_count
			result.rent_cost += extra_upkeep
			result.profit -= extra_upkeep

			result.ingredient_consumption_multiplier = float(entry.get("ingredient_consumption_multiplier", 1.0))
			result.preparation_waste_ingredients = store.get_preparation_waste_for_orders(
				entry.product_template, result.actual_orders, result.ingredient_consumption_multiplier)
		else:
			result = SettlementEngine.finalize_from_simulation(
				entry.params, hour, day, entry.category, entry.product, 0, null)

		store.apply_settlement(result)
		player_state.apply_settlement(result)
		results.append(result)

		if not results_by_store.has(store.id):
			results_by_store[store.id] = []
		results_by_store[store.id].append(result)
		if bool(entry.params.get("is_open", false)):
			operating_store_ids[store.id] = true

	var spoilage_by_store: Dictionary = {}
	for open_store in get_open_stores():
		spoilage_by_store[open_store.id] = open_store.apply_ingredient_spoilage(
			get_ingredient_spoilage_ratios(open_store))

	for store_id in operating_store_ids.keys():
		var operating_store := get_store(store_id)
		if operating_store == null:
			continue
		var equipment_utility := get_equipment_hourly_utility_cost(operating_store)
		var staff_wages := get_scheduled_staff_hourly_cost(operating_store, hour)
		var spoiled_ingredients: Dictionary = spoilage_by_store.get(store_id, {})
		if equipment_utility <= 0.0 and staff_wages <= 0.0 and spoiled_ingredients.is_empty():
			continue
		var overhead := SettlementResult.new()
		overhead.day = day
		overhead.slot = "%02d:00" % hour
		overhead.is_open = true
		overhead.is_store_overhead = true
		overhead.product_name = "\u95e8\u5e97\u56fa\u5b9a\u6210\u672c"
		overhead.utility_cost = equipment_utility
		overhead.staff_cost = staff_wages
		overhead.spoilage_ingredients = spoiled_ingredients
		overhead.profit = -(equipment_utility + staff_wages)
		operating_store.apply_settlement(overhead)
		player_state.apply_settlement(overhead)
		results.append(overhead)
		results_by_store[store_id].append(overhead)

	for open_store in get_open_stores():
		if operating_store_ids.has(open_store.id):
			continue
		var spoiled_ingredients: Dictionary = spoilage_by_store.get(open_store.id, {})
		if spoiled_ingredients.is_empty():
			continue
		var spoilage_result := SettlementResult.new()
		spoilage_result.day = day
		spoilage_result.slot = "%02d:00" % hour
		spoilage_result.is_store_overhead = true
		spoilage_result.product_name = "\u539f\u6599\u8fc7\u671f"
		spoilage_result.spoilage_ingredients = spoiled_ingredients
		spoilage_result.utility_cost = get_storage_equipment_hourly_utility_cost(open_store)
		spoilage_result.profit = -spoilage_result.utility_cost
		open_store.apply_settlement(spoilage_result)
		results.append(spoilage_result)
		if not results_by_store.has(open_store.id):
			results_by_store[open_store.id] = []
		results_by_store[open_store.id].append(spoilage_result)

	for store_id in results_by_store.keys():
		_apply_operating_understanding_gain(get_store(store_id), results_by_store[store_id])

	active_simulations.clear()
	return results


## backlog任务4：经营数据反哺区块了解度。现在按"这次结算属于哪家店"分别计算，
## 不再依赖current_storefront这个单一指针。
func _apply_operating_understanding_gain(store: Store, results: Array) -> void:
	if store == null:
		return
	var storefront := get_storefront(store.selected_storefront_id)
	if storefront == null or storefront.city_region_id.is_empty():
		return

	var block := _get_block_for_storefront(storefront)
	if block == null:
		return

	var total_orders := 0
	for result in results:
		if result.is_open:
			total_orders += result.actual_orders

	_apply_store_awareness_growth(store, storefront, results, total_orders)

	if total_orders <= 0:
		return

	var gain := float(total_orders) * SpatialConfig.OPERATING_UNDERSTANDING_PER_ORDER
	advance_block_understanding(block.id, gain)
	recalculate_region_intel(block.city_region_id)


func _apply_store_awareness_growth(store: Store, storefront: StorefrontData, results: Array, total_orders: int) -> void:
	if store == null or storefront == null or _get_block_for_storefront(storefront) == null:
		return
	## 只要实际营业，门面所在道路带来的曝光就会累积；它不依赖本时段是否成交。
	var awareness_gain_multiplier := _get_store_awareness_gain_multiplier(store, storefront) * StoreLayoutEffects.get_awareness_multiplier(store)
	var coverage_ratios := StorefrontInfluenceCalculator.get_covered_block_ratios(storefront, all_blocks)
	var exposure_gain := get_storefront_road_exposure(storefront) * storefront.awareness_exposure_modifier * 0.05 * awareness_gain_multiplier
	_apply_offline_awareness_to_covered_blocks(store, storefront, coverage_ratios, exposure_gain)
	if total_orders <= 0:
		return

	var total_wait_seconds := 0.0
	var total_reputation_delta := 0.0
	for result in results:
		if not result.is_open or result.actual_orders <= 0:
			continue
		total_wait_seconds += result.average_queue_wait_seconds * float(result.actual_orders)
		total_reputation_delta += result.reputation_delta
	var average_wait_seconds := total_wait_seconds / float(total_orders)
	var memorable_service_multiplier := 1.0 + absf(total_reputation_delta) * 0.4 + minf(average_wait_seconds / 600.0, 0.35)
	var reputation_memory_multiplier := 1.0 + absf(store.reputation - SettlementConfig.INITIAL_REPUTATION) / 50.0
	var word_of_mouth_gain := float(total_orders) * 0.02 * memorable_service_multiplier * reputation_memory_multiplier * storefront.awareness_exposure_modifier * awareness_gain_multiplier
	_apply_offline_awareness_to_covered_blocks(store, storefront, coverage_ratios, word_of_mouth_gain)


func _apply_offline_awareness_to_covered_blocks(store: Store, storefront: StorefrontData, coverage_ratios: Dictionary, base_gain: float) -> void:
	if base_gain <= 0.0:
		return
	for raw_block_id in coverage_ratios.keys():
		var block_id := str(raw_block_id)
		var block := get_block(block_id)
		if block == null or block.city_region_id != storefront.city_region_id:
			continue
		_add_store_awareness(store, block_id, base_gain * float(coverage_ratios.get(raw_block_id, 0.0)))


func _get_store_awareness_gain_multiplier(store: Store, storefront: StorefrontData) -> float:
	if storefront == null:
		return 1.0
	var modifier_add := EventManager.get_modifier_total(
		GameEventDefinition.Scope.CITY_REGION, storefront.city_region_id, "awareness_gain_multiplier_add")
	modifier_add += EventManager.get_modifier_total(
		GameEventDefinition.Scope.STOREFRONT, storefront.id, "awareness_gain_multiplier_add")
	if store != null:
		modifier_add += EventManager.get_modifier_total(
			GameEventDefinition.Scope.STORE, store.id, "awareness_gain_multiplier_add")
	return maxf(0.0, 1.0 + modifier_add)


func _add_store_awareness(store: Store, block_id: String, gain: float) -> void:
	if store == null or block_id.is_empty() or gain <= 0.0:
		return
	store.awareness_by_block[block_id] = clampf(
		float(store.awareness_by_block.get(block_id, 0.0)) + gain, 0.0, 100.0)


## 供多店场景使用：按天汇总"所有营业中店铺"的结算数据。
## 阶段4做真正的"逐店日终"UI之前，先用这个汇总版本保证day_completed信号
## 的数据形状不变，DayEndPanel不用跟着改。
func get_day_summary_all_stores(day: int) -> Dictionary:
	var combined := {
		"revenue": 0.0, "ingredient_cost": 0.0, "staff_cost": 0.0,
		"rent_cost": 0.0, "utility_cost": 0.0, "waste_cost": 0.0,
		"profit": 0.0, "actual_orders": 0,
		"reputation_delta": 0.0, "stress_delta": 0.0,
		"lost_inventory": 0, "lost_capacity": 0,
	}
	var any_open := false
	for store in stores:
		if not store.is_open:
			continue
		any_open = true
		var s := store.get_day_summary(day)
		for key in combined.keys():
			combined[key] += s.get(key, 0)
	return combined if any_open else {}


func _get_block_for_storefront(storefront: StorefrontData) -> BlockData:
	for b in all_blocks:
		if b.city_region_id != storefront.city_region_id:
			continue
		if b.has_map_point(storefront.map_position):
			return b
	return null
