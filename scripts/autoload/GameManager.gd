extends Node

## GameManager.gd 顶部signal区新增
signal active_store_changed(store_id: String)

var player_state: PlayerState = PlayerState.new()
var last_settlement_error: String = ""

var current_region: RegionData = null
var current_storefront: StorefrontData = null

var all_regions: Array[RegionData] = []
var all_storefronts: Array[StorefrontData] = []
var all_categories: Array[CategoryData] = []
var all_products: Array[ProductData] = []
var all_ingredients: Array[IngredientData] = []

var all_city_regions: Array[CityRegionData] = []
var all_blocks: Array[BlockData] = []

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
	all_regions     = GameData.get_regions()
	all_storefronts = GameData.get_storefronts()
	all_categories  = GameData.get_categories()
	all_products    = GameData.get_products()
	all_ingredients = GameData.get_ingredients()

	all_city_regions = GameData.get_city_regions()
	all_blocks = GameData.get_blocks()


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
	current_region = null
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


func get_region(id: String) -> RegionData:
	for r in all_regions:
		if r.id == id: return r
	return null


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

	for storefront in all_storefronts:
		if storefront.city_region_id != block.city_region_id:
			continue
		if not block.map_bounds.has_point(storefront.map_position):
			continue
		if get_storefront_diligence(storefront.id) == "not_viewed":
			player_state.storefront_diligence[storefront.id] = "initial_viewing"


# ── 门面尽调 (玩家层) ────────────────────────────────────────

func get_storefront_diligence(storefront_id: String) -> String:
	return player_state.get_storefront_diligence(storefront_id)


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

	## 经营时间加成：遍历玩家名下所有店铺，只统计"选定区域=当前查询区域"
	## 的那些店铺的营业天数——多店化后这里天然变精确了，不再需要近似算法
	## （backlog 任务 3 已随本次重构一并解决）。
	var days: Dictionary = {}
	for s in stores:
		if s.selected_region_id != city_region_id:
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


func get_products_for_category(category_id: String) -> Array[ProductData]:
	var result: Array[ProductData] = []
	for p in all_products:
		if p.category_id == category_id:
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


func get_product_unit_ingredient_cost_for_store(store: Store, product: ProductData) -> float:
	if store == null:
		return 0.0
	var total_cost := 0.0
	for recipe_item in product.recipe:
		var ingredient_id: String = recipe_item.get("ingredient_id", "")
		var quantity: float = float(recipe_item.get("quantity", 0.0))
		total_cost += quantity * store.get_ingredient_avg_cost(ingredient_id)
	return total_cost


# ── 选址（对"当前激活店铺"操作） ───────────────────────────────

func select_region(region_id: String) -> Dictionary:
	if not player_state.is_character_created:
		return {"success": false, "reason": "请先完成人物创建"}

	var store := get_active_store()
	if store == null:
		return {"success": false, "reason": "当前没有激活的店铺"}

	if store.is_open:
		return {"success": false, "reason": "门店已开业，不能更换区域"}

	var region := get_region(region_id)
	if region == null:
		return {"success": false, "reason": "区域不存在"}

	store.selected_region_id = region_id
	store.selected_storefront_id = ""
	store.signed_storefront_id = ""
	current_region = region
	current_storefront = null

	return {"success": true, "reason": "已选定区域：「%s」" % region.name}


func get_storefronts_for_region(region_id: String) -> Array[StorefrontData]:
	var result: Array[StorefrontData] = []
	for s in all_storefronts:
		if s.region_id == region_id:
			result.append(s)
	return result


func select_storefront(storefront_id: String) -> Dictionary:
	var store := get_active_store()
	if store == null:
		return {"success": false, "reason": "当前没有激活的店铺"}

	if store.is_open:
		return {"success": false, "reason": "门店已开业，不能更换门面"}

	if store.selected_region_id == "":
		return {"success": false, "reason": "请先选定区域"}

	var sf := get_storefront(storefront_id)
	if sf == null:
		return {"success": false, "reason": "门面不存在"}

	if sf.region_id != store.selected_region_id:
		return {"success": false, "reason": "该门面不属于当前选定区域"}

	## 选址必须建立在玩家完成完整尽调的知识基础上。
	## initial_viewing 只代表门面已被发现/初步看铺，不足以落实到企划。
	if get_storefront_diligence(storefront_id) != "full_diligence":
		return {"success": false, "reason": "请先完成该门面的完整尽调后再选定"}

	## 决定②：门面占用校验。
	if is_storefront_occupied(storefront_id, store.id):
		return {"success": false, "reason": "该门面已被你名下其他店铺占用"}

	store.selected_storefront_id = storefront_id
	store.category_slots.clear()
	_sync_data_objects()

	return {"success": true, "reason": "已选定门面：「%s」" % sf.name}


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
		current_region = null
		current_storefront = null
		return
	current_region = get_region(store.selected_region_id)
	current_storefront = get_storefront(store.selected_storefront_id)


# ── 品类添加/管理（对"当前激活店铺"操作） ───────────────────────

func get_category_options_for_current_store() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	var store := store_state
	if store == null or current_storefront == null:
		return options
	var available_area := store.get_available_area(current_storefront)
	for cat in all_categories:
		var supported: bool = cat.id in current_storefront.supported_categories
		if not supported:
			continue
		var already_added := store.has_category(cat.id)
		var fits := cat.required_area <= available_area
		var can_add := supported and not already_added and fits
		var reason := ""
		if already_added:
			reason = "已添加"
		elif not fits:
			reason = "面积不足（需%.0f㎡，剩余%.0f㎡）" % [cat.required_area, available_area]
		options.append({
			"category": cat,
			"already_added": already_added,
			"can_add": can_add,
			"reason": reason,
		})
	return options


func add_category_to_store(category_id: String, product_ids: Array[String],
		has_key_staff: bool = false, open_hour_ranges: Array[Vector2i] = []) -> Dictionary:
	var store := store_state
	if store == null or current_storefront == null:
		return {"success": false, "reason": "尚未选择门面"}
	var cat := get_category(category_id)
	if cat == null:
		return {"success": false, "reason": "品类不存在"}
	if store.has_category(category_id):
		return {"success": false, "reason": "该品类已添加"}
	if product_ids.is_empty():
		return {"success": false, "reason": "请至少选择一个商品"}
	if category_id not in current_storefront.supported_categories:
		return {"success": false, "reason": "门面不支持该品类"}
	var available := store.get_available_area(current_storefront)
	if cat.required_area > available:
		return {"success": false, "reason": "面积不足（需%.0f㎡，剩余%.0f㎡）" % [cat.required_area, available]}
	var setup_cost := cat.setup_cost_wan * 10000.0
	if player_state.cash < setup_cost:
		return {"success": false, "reason": "现金不足，开设需要%.0f 元装修/设备投入" % setup_cost}

	var slot := StoreCategorySlot.new()
	slot.category_id = category_id
	slot.has_key_staff = has_key_staff
	slot.open_hour_ranges = open_hour_ranges if not open_hour_ranges.is_empty() else cat.suggested_open_hour_ranges.duplicate()
	slot.allocated_area = cat.required_area
	for pid in product_ids:
		var pc := StoreProductConfig.new()
		pc.product_id = pid
		pc.inventory_units = SettlementConfig.INITIAL_INVENTORY
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
	pc.inventory_units = SettlementConfig.INITIAL_INVENTORY
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
			store.category_slots[i].product_configs.remove_at(i)
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


func set_category_open_hours(category_id: String, open_hour_ranges: Array[Vector2i]) -> bool:
	var store := store_state
	if store == null:
		return false
	var slot := store.get_slot_by_category(category_id)
	if slot == null:
		return false
	slot.open_hour_ranges = open_hour_ranges
	return true


func set_category_key_staff(category_id: String, has_staff: bool) -> bool:
	var store := store_state
	if store == null:
		return false
	var slot := store.get_slot_by_category(category_id)
	if slot == null:
		return false
	slot.has_key_staff = has_staff
	return true


func set_category_area(category_id: String, new_area: float) -> Dictionary:
	var store := store_state
	if store == null or current_storefront == null:
		return {"success": false, "reason": "当前没有激活的店铺", "clamped_area": 0.0}

	var cat := get_category(category_id)
	var slot := store.get_slot_by_category(category_id)
	if cat == null or slot == null:
		return {"success": false, "reason": "品类不存在", "clamped_area": 0.0}

	var other_area: float = store.get_used_area() - slot.allocated_area
	var max_area: float = current_storefront.area - other_area
	var min_area: float = cat.required_area

	if max_area < min_area:
		return {"success": false, "reason": "门店总面积不足以维持最低需求", "clamped_area": slot.allocated_area}

	var clamped: float = clampf(new_area, min_area, max_area)
	slot.allocated_area = clamped
	return {"success": true, "reason": "", "clamped_area": clamped}


# ── 开业 ────────────────────────────────────────────────

func get_open_readiness() -> Dictionary:
	var checks: Array[Dictionary] = []
	var store := store_state

	var has_storefront := current_storefront != null
	checks.append({
		"label": "已签约门面",
		"passed": has_storefront,
	})

	var has_category := store != null and not store.category_slots.is_empty()
	checks.append({
		"label": "已添加至少一个经营品类",
		"passed": has_category,
	})

	var has_inventory := store != null and store.get_total_inventory_across_slots() > 0
	checks.append({
		"label": "已备货（至少一个商品有库存）",
		"passed": has_inventory,
	})

	var can_open: bool = has_storefront and has_category and has_inventory

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
	var readiness := get_open_readiness()
	if not readiness.can_open:
		return {"success": false, "reason": "开业条件尚未全部满足，请查看开业清单"}
	store.is_open = true
	return {"success": true, "reason": "门店已开业！"}


## 开始全新一局：完全重建门店与玩家状态，不保留任何选择/进度/存档影响。
func start_new_game() -> void:
	stores = []
	active_store_id = ""
	player_state = PlayerState.new()
	current_region = null
	current_storefront = null


func begin_slot_simulation() -> void:
	active_simulations.clear()
	for store in get_open_stores():
		_begin_slot_simulation_for_store(store)


func _begin_slot_simulation_for_store(store: Store) -> void:
	var region := get_region(store.selected_region_id)
	var storefront := get_storefront(store.selected_storefront_id)
	if region == null or storefront == null or store.category_slots.is_empty():
		return

	var hour := TimeManager.get_current_hour_int()
	var total_area: float = storefront.area

	for cat_slot in store.category_slots:
		var category := get_category(cat_slot.category_id)
		if category == null or cat_slot.product_configs.is_empty():
			continue

		var area_share: float = cat_slot.allocated_area / total_area
		var product_count: int = cat_slot.product_configs.size()

		for pc in cat_slot.product_configs:
			var product_template := get_product(pc.product_id)
			if product_template == null:
				continue

			var scaled_storefront: StorefrontData = storefront.duplicate()
			scaled_storefront.hourly_capacity_base = int(round(
				storefront.hourly_capacity_base * area_share / product_count))
			scaled_storefront.flow_share = storefront.flow_share / product_count

			var product_instance: ProductData = product_template.duplicate()
			product_instance.average_price = pc.get_effective_price(product_template)
			product_instance.recipe = product_template.recipe

			var params: Dictionary = SettlementEngine.calculate_params(
				region, scaled_storefront, category, product_instance,
				store, player_state, hour, cat_slot.open_hour_ranges, cat_slot.has_key_staff)

			var entry := {
				"store_id": store.id, "sim": null, "params": params, "category": category,
				"product": product_instance, "product_template": product_template,
				"inventory_limit": 0, "product_count": product_count,
			}

			if params.is_open:
				var available_units := store.get_max_produceable_by_ingredients(product_template)
				var unit_ingredient_cost := get_product_unit_ingredient_cost_for_store(store, product_template)
				var unit_utility_cost := get_product_unit_utility_cost(product_template)
				entry.inventory_limit = mini(available_units, pc.inventory_units)

				var sim := CustomerSimulator.new()
				sim.setup(params.visitors, 3600.0, params.conversion_rate,
					params.slot_capacity, entry.inventory_limit,
					product_instance.average_price, unit_ingredient_cost, unit_utility_cost)
				entry.sim = sim

			active_simulations.append(entry)


func advance_slot_simulation(elapsed_seconds: float) -> void:
	for entry in active_simulations:
		if entry.sim != null:
			entry.sim.advance(elapsed_seconds)


func finalize_slot_simulation() -> Array[SettlementResult]:
	var results: Array[SettlementResult] = []
	var results_by_store: Dictionary = {}  # store_id -> Array[SettlementResult]，供了解度反哺用
	var hour := TimeManager.get_current_hour_int()
	var day := TimeManager.current_day

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

			store.consume_ingredients(entry.product_template, result.actual_orders)
		else:
			result = SettlementEngine.finalize_from_simulation(
				entry.params, hour, day, entry.category, entry.product, 0, null)

		store.apply_settlement(result)
		player_state.apply_settlement(result)
		results.append(result)

		if not results_by_store.has(store.id):
			results_by_store[store.id] = []
		results_by_store[store.id].append(result)

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

	if total_orders <= 0:
		return

	var gain := float(total_orders) * SpatialConfig.OPERATING_UNDERSTANDING_PER_ORDER
	advance_block_understanding(block.id, gain)
	recalculate_region_intel(block.city_region_id)


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
		if b.map_bounds.has_point(storefront.map_position):
			return b
	return null
