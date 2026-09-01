extends Node

const MarketAllocatorScript = preload("res://scripts/spatial/MarketAllocator.gd")

## GameManager.gd 顶部signal区新增
signal active_store_changed(store_id: String)
signal store_plan_updated(store_id: String)
signal storefronts_discovered(storefront_ids: Array[String])

const BLOCK_RESEARCH_FOCUSES: Array[String] = ["population", "groups", "time", "spending", "demand", "competition"]

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
var all_player_homes: Array = []
var road_graph: RoadGraph = RoadGraph.new()
var _navigation_grid_cache: MapNavigationGrid = null

func get_navigation_grid() -> MapNavigationGrid:
	if _navigation_grid_cache == null:
		_navigation_grid_cache = MapNavigationGrid.build(road_graph, all_blocks, all_storefronts, all_player_homes)
	return _navigation_grid_cache


func invalidate_navigation_grid() -> void:
	_navigation_grid_cache = null

func get_block_at_map_cell(cell: Vector2i) -> BlockData:
	for block in all_blocks:
		if block.grid_cells.has(cell):
			return block
	return null

## ── 多店重构阶段1 ────────────────────────────────────────────
var stores: Array[Store] = []
## NPC businesses use the exact same Store data model, but never share the
## player's wallet, research, or character state.
var npc_stores: Array[Store] = []
var active_store_id: String = ""

var _next_store_sequence: int = 0

var active_simulations: Array[Dictionary] = []  # {store_id, service:CategoryServiceSimulator, params, category, products}
## Sorted by next arrival, then original simulation order for stable ties.
var _arrival_queue: Array[Dictionary] = []

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
	all_player_homes = GameData.get_player_homes()
	road_graph = GameData.get_road_graph()
	store_plan_updated.connect(func(_store_id: String) -> void: invalidate_navigation_grid())
	invalidate_navigation_grid()


func get_player_home(home_id: String) -> Dictionary:
	for home in all_player_homes:
		if str(home.get("id", "")) == home_id:
			return home
	return {}


func get_default_player_home() -> Dictionary:
	return all_player_homes[0] if not all_player_homes.is_empty() else {}


func _ensure_player_home() -> void:
	if not player_state.is_character_created:
		return
	var home: Dictionary = get_player_home(player_state.home_id)
	if home.is_empty():
		var preset := {}
		for candidate in CharacterCreationData.get_presets():
			if str(candidate.get("id", "")) == player_state.selected_preset_id:
				preset = candidate
				break
		home = get_player_home(str(preset.get("home_id", "")))
		if home.is_empty():
			home = get_default_player_home()
		if not home.is_empty():
			player_state.home_id = str(home.get("id", ""))
			if player_state.current_block_id.is_empty():
				player_state.set_home(home)
			elif player_state.current_map_position == Vector2.ZERO:
				var block := get_block(player_state.current_block_id)
				player_state.current_map_position = block.center_position if block != null else home.get("map_position", Vector2.ZERO)


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
	var preset_id := str(data.get("preset_id", ""))

	if player_name.is_empty():
		return {"success": false, "reason": "请输入创业者姓名"}

	if gender not in ["male", "female"]:
		return {"success": false, "reason": "请选择性别"}

	if age not in CharacterCreationData.get_all_ages():
		return {"success": false, "reason": "请选择20至58岁之间的年龄"}

	var difficulty := CharacterCreationData.get_difficulty(difficulty_id)
	if difficulty.is_empty():
		return {"success": false, "reason": "请选择难度"}
	var preset := {}
	for candidate in CharacterCreationData.get_presets():
		if str(candidate.get("id", "")) == preset_id:
			preset = candidate
			break
	var requested_home_id := str(data.get("home_id", ""))
	if not preset.is_empty():
		requested_home_id = str(preset.get("home_id", requested_home_id))
	var home: Dictionary = get_player_home(requested_home_id)
	if home.is_empty() and requested_home_id.is_empty():
		home = get_default_player_home()
	if home.is_empty():
		return {"success": false, "reason": "请选择有效的初始住宅"}

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
		"preset_id": preset_id,
		"starting_cash": float(difficulty.starting_cash),
		"trait_ids": trait_ids,
	})
	player_state.set_home(home)
	if not preset.is_empty():
		for vehicle_id in preset.get("starting_vehicles", []):
			player_state.owned_vehicles.append(str(vehicle_id))
	player_state.storefront_intel_seed = abs(hash("storefront-intel:%s:%d" % [player_name, age]))

	## 创建角色不再自动开店。"有角色"和"有开店企划"是两件事：
	## 角色创建完成后玩家名下没有任何店铺，必须去"我的店铺"主动新建一个
	## 企划（create_new_store()），才能开始选区域/门面/品类这些准备工作。
	stores = []
	npc_stores = []
	active_store_id = ""

	TimeManager.reset()
	_seed_npc_stores_if_needed()

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


func get_npc_store(id: String) -> Store:
	for store in npc_stores:
		if store.id == id:
			return store
	return null


func get_any_store(id: String) -> Store:
	var player_store := get_store(id)
	return player_store if player_store != null else get_npc_store(id)


func get_npc_store_for_storefront(storefront_id: String) -> Store:
	for store in npc_stores:
		if store.selected_storefront_id == storefront_id and store.transfer_state != "closed":
			return store
	return null


func get_all_open_stores() -> Array[Store]:
	var result: Array[Store] = []
	for store in stores:
		if store.is_open:
			result.append(store)
	for store in npc_stores:
		if store.is_open and store.transfer_state != "closed":
			result.append(store)
	return result


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


func get_block_research_progress(block_id: String, focus_id: String) -> float:
	return player_state.get_block_research_progress(block_id, focus_id)


func is_block_research_complete(block_id: String) -> bool:
	for focus_id in BLOCK_RESEARCH_FOCUSES:
		if get_block_research_progress(block_id, focus_id) < 100.0 - 0.0001:
			return false
	return true


func advance_block_research_progress(block_id: String, focus_id: String, delta: float) -> Dictionary:
	if block_id.is_empty():
		return {"success": false, "reason": "区块 ID 为空"}
	if not BLOCK_RESEARCH_FOCUSES.has(focus_id):
		return {"success": false, "reason": "未知调研重点"}
	var tracks: Dictionary = player_state.block_research_progress.get(block_id, {})
	var current := float(tracks.get(focus_id, 0.0))
	var next_value := clampf(current + delta, 0.0, 100.0)
	tracks[focus_id] = next_value
	player_state.block_research_progress[block_id] = tracks

	if focus_id == "population" and current < SpatialConfig.BLOCK_UNDERSTANDING_INITIAL_SURVEY \
			and next_value >= SpatialConfig.BLOCK_UNDERSTANDING_INITIAL_SURVEY:
		_discover_storefronts_in_block(block_id)

	return {"success": true, "reason": "", "new_value": next_value, "focus_id": focus_id}


## Legacy compatibility only. New gameplay must name the research focus.
func advance_block_understanding(block_id: String, delta: float) -> Dictionary:
	return advance_block_research_progress(block_id, "population", delta)

func _generate_unique_id(prefix: String) -> String:
	_next_store_sequence += 1
	return "%s_%d_%d" % [prefix, Time.get_ticks_msec(), _next_store_sequence]


func _seed_npc_stores_if_needed() -> void:
	if not npc_stores.is_empty():
		return
	for storefront in all_storefronts:
		if storefront.is_occupied:
			npc_stores.append(_make_seeded_npc_store(storefront))


func _make_seeded_npc_store(storefront: StorefrontData) -> Store:
	var rng := RandomNumberGenerator.new()
	## Storefront id is intentionally the seed: starting/reloading a campaign
	## never rerolls a neighbourhood's competitors.
	rng.seed = int(hash("npc-store:" + storefront.id))
	var store := Store.new()
	store.id = "npc_" + storefront.id
	store.owner_kind = "npc"
	var names := ["陈", "林", "周", "许", "方", "杜", "叶", "宋"]
	var given_names := ["安", "宁", "遥", "澄", "川", "月", "岚", "禾"]
	store.owner_name = str(names[rng.randi_range(0, names.size() - 1)]) + str(given_names[rng.randi_range(0, given_names.size() - 1)])
	store.name = storefront.occupant_name if not storefront.occupant_name.is_empty() else "%s的小店" % store.owner_name
	store.selected_storefront_id = storefront.id
	store.signed_storefront_id = storefront.id
	store.is_open = true
	store.is_business_open = true
	store.pre_open_stage = Store.PreOpenStage.OPEN_FOR_BUSINESS
	store.operating_cash = rng.randf_range(18000.0, 48000.0)
	store.owner_stress = rng.randf_range(18.0, 52.0)
	store.lease_rent_multiplier = rng.randf_range(0.92, 1.12)
	store.lease_deposit_paid = storefront.get_monthly_rent_yuan() * float(rng.randi_range(1, 3))
	store.lease_end_day = TimeManager.current_day + rng.randi_range(365, 1095)
	store.business_hour_ranges = [Vector2i(rng.randi_range(7, 10), rng.randi_range(18, 23))]
	_seed_npc_traits(store, rng)
	var eligible_categories: Array[CategoryData] = []
	for candidate_category in all_categories:
		for product in all_products:
			if product.category_id == candidate_category.id:
				eligible_categories.append(candidate_category)
				break
	var category := eligible_categories[rng.randi_range(0, eligible_categories.size() - 1)] if not eligible_categories.is_empty() else null
	if category != null:
		var slot := StoreCategorySlot.new()
		slot.category_id = category.id
		for product in all_products:
			if product.category_id == category.id or product.is_universal:
				var config := StoreProductConfig.new()
				config.product_id = product.id
				config.custom_price = product.average_price * rng.randf_range(0.92, 1.12)
				config.inventory_units = 120
				slot.product_configs.append(config)
				for recipe_item in product.recipe:
					store.add_ingredient_stock(str(recipe_item.get("ingredient_id", "")), 240.0, 2.0)
				if slot.product_configs.size() >= 3:
					break
		store.category_slots.append(slot)
		for equipment_id in category.required_equipment_ids:
			var equipment := StoreEquipment.new()
			equipment.instance_id = "%s_eq_%d" % [store.id, store.equipment.size()]
			equipment.equipment_id = equipment_id
			store.equipment.append(equipment)
	if store.equipment.is_empty() and not all_equipment.is_empty():
		var fallback_equipment := StoreEquipment.new()
		fallback_equipment.instance_id = "%s_eq_0" % store.id
		fallback_equipment.equipment_id = all_equipment[0].id
		store.equipment.append(fallback_equipment)
	if not all_employee_candidates.is_empty():
		var employee_count := maxi(1, category.required_staff_count) if category != null else 1
		for employee_index in employee_count:
			var candidate := all_employee_candidates[rng.randi_range(0, all_employee_candidates.size() - 1)]
			var employee := StoreEmployee.new()
			employee.candidate_id = "%s_npc_%d" % [candidate.id, employee_index]
			employee.name = candidate.name
			employee.skills = candidate.skills.duplicate()
			if category != null and not category.required_staff.is_empty() and not employee.has_skill(category.required_staff):
				employee.skills.append(category.required_staff)
			employee.hourly_wage = candidate.hourly_wage
			employee.skill_level = candidate.skill_level
			employee.work_hour_ranges = store.business_hour_ranges.duplicate()
			store.employees.append(employee)
	_seed_npc_layout(store, storefront)
	return store


func _seed_npc_traits(store: Store, rng: RandomNumberGenerator) -> void:
	var used_types: Dictionary = {}
	var traits := CharacterCreationData.get_traits()
	for index in range(traits.size()):
		var swap_index := rng.randi_range(index, traits.size() - 1)
		var swap = traits[index]
		traits[index] = traits[swap_index]
		traits[swap_index] = swap
	for trait_data in traits:
		if used_types.has(trait_data.trait_type) or rng.randf() > 0.48:
			continue
		used_types[trait_data.trait_type] = true
		store.owner_trait_ids.append(trait_data.id)
		if store.owner_trait_ids.size() >= 3:
			break


func _seed_npc_layout(store: Store, storefront: StorefrontData) -> void:
	var geometry := StorefrontLayoutGeometry.from_storefront(storefront)
	var cell_index := 0
	for equipment in store.equipment:
		var placement := StoreFurniturePlacement.new()
		placement.instance_id = equipment.instance_id
		placement.equipment_id = equipment.equipment_id
		placement.cell = Vector2i(cell_index % geometry.grid_size.x, cell_index / geometry.grid_size.x)
		store.furniture_layout.append(placement)
		cell_index += 1
	var entrance := StoreFacadePlacement.new()
	entrance.type = "entrance"
	entrance.cell = geometry.get_default_entrance_cell(storefront.default_entrance_offset)
	store.facade_layout.append(entrance)
	store.facade_layout_initialized = true

func _discover_storefronts_in_block(block_id: String) -> void:
	## All storefronts are visible from the beginning. Research now improves the
	## account of a block rather than revealing map objects.
	return
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
	return []


func get_storefront_intel(storefront_id: String) -> Dictionary:
	return player_state.get_storefront_intel(storefront_id)


func visit_storefront(storefront_id: String) -> Dictionary:
	var storefront := get_storefront(storefront_id)
	if storefront == null:
		return {"success": false, "reason": "门面不存在"}
	if player_state.current_block_id != storefront.block_id:
		return {"success": false, "reason": "请先前往门面所在区块"}
	var intel := player_state.get_storefront_intel(storefront_id)
	var npc_store := get_npc_store_for_storefront(storefront_id)
	if bool(intel.get("visited", false)) and npc_store != null and npc_store.is_business_open and not bool(intel.get("visited_during_business_hours", false)):
		intel["visited_during_business_hours"] = true
		player_state.set_storefront_intel(storefront_id, intel)
		return {"success": true, "reason": "已在营业时到访，现可查看店内。"}
	if bool(intel.get("visited", false)):
		return {"success": true, "reason": "你已经到访过这间门面"}
	var previous_belief := StorefrontIntelPresenter.describe_storefront(storefront, player_state)
	intel["visited"] = true
	npc_store = get_npc_store_for_storefront(storefront_id)
	intel["visited_during_business_hours"] = bool(intel.get("visited_during_business_hours", false)) or (npc_store != null and npc_store.is_business_open)
	intel["menu_reviewed"] = bool(intel.get("menu_reviewed", false))
	intel["order_records"] = intel.get("order_records", [])
	intel["traffic_observations"] = intel.get("traffic_observations", [])
	var beliefs: Array = intel.get("belief_history", [])
	beliefs.append({"day": TimeManager.current_day, "hour": TimeManager.get_current_hour_int(), "before": previous_belief, "after": {"occupancy": "已开店" if storefront.is_occupied else "空门面", "area": storefront.area}, "message": "现场到访将先前的街面判断替换为核验记录。"})
	intel["belief_history"] = beliefs
	player_state.set_storefront_intel(storefront_id, intel)
	player_state.add_storefront_intel_history({"kind": "visit", "storefront_id": storefront_id, "day": TimeManager.current_day, "hour": TimeManager.get_current_hour_int(), "message": "现场到访核验了门面外观与占用状态。"})
	return {"success": true, "reason": "已记录现场所见"}


func record_storefront_arrival(storefront_id: String) -> Dictionary:
	var storefront := get_storefront(storefront_id)
	if storefront == null:
		return {"success": false, "reason": "门面不存在。"}
	var intel := player_state.get_storefront_intel(storefront_id)
	var npc_store := get_npc_store_for_storefront(storefront_id)
	var arrived_during_business := npc_store != null and npc_store.is_open and npc_store.is_business_open
	intel["visited"] = true
	intel["visited_during_business_hours"] = bool(intel.get("visited_during_business_hours", false)) or arrived_during_business
	intel["menu_reviewed"] = bool(intel.get("menu_reviewed", false))
	intel["order_records"] = intel.get("order_records", [])
	intel["traffic_observations"] = intel.get("traffic_observations", [])
	player_state.set_storefront_intel(storefront_id, intel)
	player_state.add_storefront_intel_history({"kind": "arrival", "storefront_id": storefront_id, "day": TimeManager.current_day, "hour": TimeManager.get_current_hour_int(), "business_open": arrived_during_business, "message": "抵达门面入口。"})
	return {"success": true, "business_open": arrived_during_business}


func review_storefront_menu(storefront_id: String) -> Dictionary:
	var storefront := get_storefront(storefront_id)
	var npc_store := get_npc_store_for_storefront(storefront_id)
	var intel := player_state.get_storefront_intel(storefront_id)
	if storefront == null or not bool(intel.get("visited", false)) or npc_store == null or not npc_store.is_business_open:
		return {"success": false, "reason": "到访营业中的店铺后才能查看菜单"}
	var menu: Array[Dictionary] = []
	for slot in npc_store.category_slots:
		for config in slot.product_configs:
			var product := get_product(config.product_id)
			if product != null:
				menu.append({"product_id": product.id, "name": product.name, "price": config.get_effective_price(product)})
	intel["menu_reviewed"] = true
	intel["menu"] = menu
	player_state.set_storefront_intel(storefront_id, intel)
	player_state.add_storefront_intel_history({"kind": "menu", "storefront_id": storefront_id, "day": TimeManager.current_day, "menu": menu, "message": "你抄下了店里的菜单和标价。"})
	return {"success": true, "reason": "菜单已记录", "menu": menu}


func record_storefront_observation(storefront_id: String) -> Dictionary:
	var npc_store := get_npc_store_for_storefront(storefront_id)
	if npc_store == null:
		return {"success": false, "reason": "这里只有空门面，没有可观察的营业客流"}
	var summary := npc_store.get_day_summary(TimeManager.current_day)
	var metrics := get_store_operating_metrics(npc_store)
	var observation := {"day": TimeManager.current_day, "hour": TimeManager.get_current_hour_int(), "visitors": int(summary.get("actual_orders", 0)) + int(summary.get("lost_capacity", 0)), "orders": int(summary.get("actual_orders", 0)), "queue_left": int(summary.get("lost_capacity", 0)), "message": "这一小时的客流与排队情况已记入观察笔记。"}
	var intel := player_state.get_storefront_intel(storefront_id)
	observation["visitors"] = int(metrics.get("visitors", observation.get("visitors", 0)))
	observation["orders"] = int(metrics.get("orders", observation.get("orders", 0)))
	observation["queue_left"] = int(metrics.get("queue_left", observation.get("queue_left", 0)))
	observation["left"] = int(metrics.get("inventory_left", 0)) + int(metrics.get("queue_left", 0))
	var observations: Array = intel.get("traffic_observations", [])
	observations.append(observation)
	intel["traffic_observations"] = observations
	player_state.set_storefront_intel(storefront_id, intel)
	player_state.add_storefront_intel_history(observation.merged({"kind": "traffic", "storefront_id": storefront_id}))
	return {"success": true, "reason": observation.message}


## A player purchase is deliberately an external customer order: it never joins
## the natural market pool, but it does consume the NPC's stock and creates an
## ordinary settlement record for that store.
func order_storefront_product(storefront_id: String, product_id: String) -> Dictionary:
	var npc_store := get_npc_store_for_storefront(storefront_id)
	var intel := player_state.get_storefront_intel(storefront_id)
	if npc_store == null or not bool(intel.get("visited", false)) or not bool(intel.get("menu_reviewed", false)):
		return {"success": false, "reason": "请先到访并查看这间店的菜单"}
	if not npc_store.is_business_open:
		return {"success": false, "reason": "店铺此刻没有营业"}
	var selected_product: ProductData = null
	var selected_category: CategoryData = null
	var unit_price := 0.0
	for slot in npc_store.category_slots:
		for product_config in slot.product_configs:
			if product_config.product_id != product_id:
				continue
			selected_product = get_product(product_id)
			selected_category = get_category(slot.category_id)
			if selected_product != null:
				unit_price = product_config.get_effective_price(selected_product)
			break
		if selected_product != null:
			break
	if selected_product == null or selected_category == null:
		return {"success": false, "reason": "这份菜单已经换了，无法按原选项点单"}
	if player_state.cash + 0.001 < unit_price:
		return {"success": false, "reason": "现金不足，无法支付这份点单"}
	if not npc_store.try_reserve_product_ingredients(selected_product, 1, 1.0):
		return {"success": false, "reason": "店里刚好缺货，这次没有成交"}
	var hour := TimeManager.get_current_hour_int()
	var staffing_power := get_category_staffing_power(npc_store, selected_category, hour)
	var service_seconds := get_product_service_seconds(selected_category, selected_product, staffing_power)
	var ingredient_cost := get_product_unit_ingredient_cost_for_store(npc_store, selected_product)
	var utility_cost := get_product_unit_utility_cost(selected_product)
	var result := SettlementResult.new()
	result.day = TimeManager.current_day
	result.slot = "external_visit"
	result.category_id = selected_category.id
	result.category_name = selected_category.name
	result.product_id = selected_product.id
	result.product_name = selected_product.name
	result.actual_orders = 1
	result.visitors = 1
	result.business_open = true
	result.unit_price = unit_price
	result.service_time_seconds = service_seconds
	result.staffing_power = staffing_power
	result.revenue = unit_price
	result.ingredient_cost = ingredient_cost
	result.utility_cost = utility_cost
	result.profit = unit_price - ingredient_cost - utility_cost
	npc_store.apply_settlement(result)
	npc_store.apply_npc_financial_result(result)
	player_state.cash -= unit_price
	var record := {"day": TimeManager.current_day, "hour": hour, "product_id": selected_product.id, "product_name": selected_product.name, "price": unit_price, "service_seconds": service_seconds, "message": "你点了一份%s；价格与服务过程已记入到访记录。" % selected_product.name}
	var records: Array = intel.get("order_records", [])
	records.append(record)
	intel["order_records"] = records
	player_state.set_storefront_intel(storefront_id, intel)
	player_state.add_storefront_intel_history(record.merged({"kind": "order", "storefront_id": storefront_id}))
	return {"success": true, "reason": str(record.message), "record": record}


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
	if sf.is_occupied:
		return {"success": false, "reason": "该门面正在营业，只能联系店主了解经营情况"}

	## 决定②：门面占用校验。
	if is_storefront_occupied(storefront_id, store.id):
		return {"success": false, "reason": "该门面已被你名下其他店铺占用"}

	store.selected_storefront_id = storefront_id
	store.signed_storefront_id = ""
	store.pending_lease_offer.clear()
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
	var offer := store.pending_lease_offer
	if str(offer.get("storefront_id", "")) != storefront.id:
		return {"success": false, "reason": "请先完成与房东的谈判，取得该门面的有效报价"}
	var rent_multiplier := float(offer.get("rent_multiplier", 1.0))
	var deposit_months := int(offer.get("deposit_months", 0))
	var deposit := storefront.get_monthly_rent_yuan() * rent_multiplier * deposit_months
	if player_state.cash + 0.001 < deposit:
		return {"success": false, "reason": "现金不足，支付押金还差 %.0f 元" % (deposit - player_state.cash)}
	player_state.cash -= deposit
	store.signed_storefront_id = storefront.id
	store.lease_rent_multiplier = rent_multiplier
	store.lease_deposit_paid = deposit
	store.lease_free_rent_hours_remaining = float(offer.get("free_rent_hours", 0.0))
	store.pending_lease_offer.clear()
	_sync_data_objects()
	store_plan_updated.emit(store.id)
	return {"success": true, "reason": "已签约门面：「%s」，已支付押金 %.0f 元" % [storefront.name, deposit]}


func set_pending_lease_offer(store_id: String, storefront_id: String, rent_multiplier: float, deposit_months: int, free_rent_hours: float, source_option_id: String) -> bool:
	var store := get_store(store_id)
	if store == null or store.is_open or store.selected_storefront_id != storefront_id or storefront_id.is_empty():
		return false
	store.pending_lease_offer = {
		"storefront_id": storefront_id,
		"rent_multiplier": rent_multiplier,
		"deposit_months": deposit_months,
		"free_rent_hours": free_rent_hours,
		"source_option_id": source_option_id,
	}
	_sync_data_objects()
	store_plan_updated.emit(store.id)
	return true


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
	invalidate_navigation_grid()
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
	npc_stores = []
	invalidate_navigation_grid()
	TimeManager.reset()
	var source_storefronts := GameData.get_storefronts()
	for storefront in all_storefronts:
		## Data files are the canonical new-game occupancy state. Closed stores in
		## an old session must not leak into a fresh campaign.
		for source_storefront in source_storefronts:
			if source_storefront.id == storefront.id:
				storefront.is_occupied = source_storefront.is_occupied
				storefront.occupant_name = source_storefront.occupant_name
				break
	_seed_npc_stores_if_needed()
	active_store_id = ""
	player_state = PlayerState.new()
	current_storefront = null
	last_settlement_error = ""
	active_simulations.clear()
	_arrival_queue.clear()
	ScheduleManager.reset_for_new_game()
	EventManager.reset_for_new_game()


func begin_slot_simulation() -> void:
	active_simulations.clear()
	_arrival_queue.clear()
	_begin_slot_simulation_for_stores(get_all_open_stores())
	_rebuild_arrival_queue()


## Slot setup is intentionally global: natural demand is finite per
## block/group/category/hour, so stores must be collected before any service is
## created.  This also makes the allocation independent from store array order.
func _begin_slot_simulation_for_stores(candidate_stores: Array[Store]) -> void:
	var participants := _collect_market_participants(candidate_stores)
	if participants.is_empty():
		return
	_allocate_shared_market_pools(participants)
	for participant in participants:
		_create_category_service_simulation(participant)


func _collect_market_participants(candidate_stores: Array[Store]) -> Array[Dictionary]:
	var participants: Array[Dictionary] = []
	var hour := TimeManager.get_current_hour_int()
	var is_weekend := (TimeManager.current_day % 7) in SettlementConfig.WEEKEND_DAY_REMAINDERS
	var block_visitor_multipliers := _get_block_visitor_multipliers()
	for store in candidate_stores:
		if store == null or not store.is_open or not store.is_business_open:
			continue
		var storefront := get_storefront(store.selected_storefront_id)
		if storefront == null:
			continue
		var city_region := get_city_region(storefront.city_region_id)
		if city_region == null:
			continue
		var city_multiplier := _get_city_region_visitor_multiplier(city_region.id)
		for category_slot in store.category_slots:
			var category := get_category(category_slot.category_id)
			if category == null or category_slot.product_configs.is_empty() or not store_has_category_equipment(store, category):
				continue
			var staffing_power := get_category_staffing_power(store, category, hour)
			if staffing_power <= 0.0:
				continue
			var first_template := get_product(category_slot.product_configs[0].product_id)
			if first_template == null:
				continue
			var category_front: StorefrontData = storefront.duplicate()
			category_front.capture_modifier *= StoreLayoutEffects.get_capture_multiplier(store)
			var trade_area := TradeAreaCalculator.calculate_snapshot(category_front, category.id, first_template.id, hour, city_region, all_blocks, is_weekend, TradeAreaCalculator.DEFAULT_MAX_RADIUS, block_visitor_multipliers, city_multiplier, TimeManager.current_day)
			var params := SettlementEngine.calculate_params_from_trade_area(trade_area, category_front, category, first_template, store, player_state, hour, true, staffing_power)
			participants.append({
				"participant_id": "%s|%s" % [store.id, category.id],
				"store": store, "storefront": storefront, "category_front": category_front,
				"city_region": city_region, "category": category, "category_slot": category_slot,
				"first_template": first_template, "staffing_power": staffing_power,
				"trade_area": trade_area, "params": params,
				"block_visitor_multipliers": block_visitor_multipliers,
				"city_region_visitor_multiplier": city_multiplier,
				"allocated_groups": SpatialConfig.make_empty_group_weights(),
				"external_competition_loss": 0,
				"market_pool_remaining_supply": 0,
			})
	participants.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.participant_id) < str(b.participant_id))
	return participants


func _allocate_shared_market_pools(participants: Array[Dictionary]) -> void:
	var pools: Dictionary = {}
	var day := TimeManager.current_day
	var hour := TimeManager.get_current_hour_int()
	var is_weekend := (day % 7) in SettlementConfig.WEEKEND_DAY_REMAINDERS
	for participant in participants:
		var category: CategoryData = participant.category
		var city_region: CityRegionData = participant.city_region
		var competing_participants := _get_competing_market_participants(participant, participants)
		var competition_scope := _get_competition_scope_key(competing_participants)
		for block in all_blocks:
			if block == null or not block.is_valid() or block.city_region_id != city_region.id:
				continue
			var factors := TradeAreaCalculator.get_participant_market_factors(block, participant.category_front, category.id)
			if factors.is_empty():
				continue
			for group_id in SpatialConfig.POPULATION_GROUPS:
				var key := MarketAllocatorScript.make_pool_key(city_region.id, block.id, group_id, category.id, day, hour) + "|" + competition_scope
				if not pools.has(key):
					var group_supply := PopulationSupplyCalculator.calculate_activity_supply_by_group(block, SpatialConfig.get_period_for_hour(hour), city_region, is_weekend)
					var raw := float(group_supply.get(group_id, 0.0)) * DemandPatternCalculator.get_group_multiplier(block, group_id, day, hour)
					raw *= float(participant.block_visitor_multipliers.get(block.id, 1.0)) * float(participant.city_region_visitor_multiplier)
					raw *= SettlementConfig.TRAFFIC_SCALE_MULTIPLIER * category.base_entry_rate
					pools[key] = {"raw_supply": maxi(0, int(round(raw))), "external_competition_ratio": TradeAreaCalculator.get_external_competition_ratio(block, category.id), "weights": {}, "participants": {}}
				var pool: Dictionary = pools[key]
				for competitor in competing_participants:
					var competitor_factors := TradeAreaCalculator.get_participant_market_factors(block, competitor.category_front, category.id)
					if competitor_factors.is_empty():
						continue
					var weight_input := {
						"is_operating": true, "offers_category": true,
						"distance": competitor_factors.distance, "block_accessibility": competitor_factors.block_accessibility,
						"storefront_accessibility": competitor_factors.storefront_accessibility,
						"business_match": competitor_factors.business_match,
						"capture_modifier": competitor.category_front.flow_share * competitor.category_front.capture_modifier,
						"reputation": competitor.store.reputation,
						"awareness": maxf(float(competitor.store.awareness_by_block.get(block.id, 0.0)), float(player_state.brand_awareness_by_block.get(block.id, 0.0)) * 0.5),
						"store_offline_influence": competitor.store.offline_influence,
						"product_offline_influence": _get_category_menu_offline_influence(competitor.category_slot),
					}
					pool.weights[competitor.participant_id] = MarketAllocatorScript.calculate_participant_weight(weight_input)
					pool.participants[competitor.participant_id] = competitor
	for key in pools.keys():
		var pool: Dictionary = pools[key]
		var description := MarketAllocatorScript.describe_pool(int(pool.raw_supply), float(pool.external_competition_ratio), pool.weights)
		var parts := str(key).split("|")
		var group_id := str(parts[2])
		for participant_id in pool.participants.keys():
			var participant: Dictionary = pool.participants[participant_id]
			participant.allocated_groups[group_id] = float(participant.allocated_groups.get(group_id, 0.0)) + int(description.allocations.get(participant_id, 0))
			participant.external_competition_loss = int(participant.external_competition_loss) + int(description.external_competition_losses.get(participant_id, 0))
			participant.market_pool_remaining_supply = int(participant.market_pool_remaining_supply) + int(description.remaining_supply)


func _get_competing_market_participants(participant: Dictionary, all_participants: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var pending: Array[Dictionary] = [participant]
	var seen: Dictionary = {}
	while not pending.is_empty():
		var current: Dictionary = pending.pop_back()
		var current_id := str(current.participant_id)
		if seen.has(current_id):
			continue
		seen[current_id] = true
		result.append(current)
		for other in all_participants:
			if other.category.id != participant.category.id or seen.has(str(other.participant_id)):
				continue
			if MarketAllocatorScript.storefronts_are_in_competition(current.storefront, other.storefront):
				pending.append(other)
	return result


func _get_competition_scope_key(participants: Array[Dictionary]) -> String:
	var ids: Array[String] = []
	for participant in participants:
		ids.append(str(participant.participant_id))
	ids.sort()
	return ",".join(ids)


func _get_category_menu_offline_influence(category_slot: StoreCategorySlot) -> float:
	if category_slot == null or category_slot.product_configs.is_empty():
		return 1.0
	var total := 0.0
	var count := 0
	for config in category_slot.product_configs:
		var product := get_product(config.product_id)
		if product == null:
			continue
		total += maxf(0.0, product.offline_influence)
		count += 1
	return total / float(count) if count > 0 else 1.0


func _create_category_service_simulation(participant: Dictionary) -> void:
	var store: Store = participant.store
	var storefront: StorefrontData = participant.storefront
	var category: CategoryData = participant.category
	var category_slot = participant.category_slot
	var params: Dictionary = participant.params
	var group_profiles: Dictionary = params.get("group_profiles", {}).duplicate(true)
	## Trade-area external flow remains available to reports, but only explicit
	## destination visitors may enter an order stream outside the natural pools.
	group_profiles.erase("external")
	var visitors := 0
	for group_id in SpatialConfig.POPULATION_GROUPS:
		var profile: Dictionary = group_profiles.get(group_id, {"conversion_rate": float(params.get("conversion_rate", 0.0)), "price_rejection_rate": 0.0})
		profile.visitors = maxi(0, int(participant.allocated_groups.get(group_id, 0)))
		group_profiles[group_id] = profile
		visitors += int(profile.visitors)
	var destination_visitors := get_destination_visitors(store, storefront)
	if destination_visitors > 0:
		group_profiles["external"] = {"visitors": destination_visitors, "conversion_rate": float(params.get("conversion_rate", 0.0)), "price_rejection_rate": 0.0}
		visitors += destination_visitors
	params.group_profiles = group_profiles
	params.visitors = visitors
	params.natural_visitors = visitors - destination_visitors
	params.destination_visitors = destination_visitors
	params.market_pool_remaining_supply = int(participant.market_pool_remaining_supply)
	params.market_pool_share = float(params.natural_visitors) / float(params.market_pool_remaining_supply) if int(params.market_pool_remaining_supply) > 0 else 0.0
	params.lost_external_competition = int(participant.external_competition_loss)
	var options: Array[Dictionary] = []
	var products: Array[Dictionary] = []
	var consumption := get_category_ingredient_consumption_multiplier(store, category, TimeManager.get_current_hour_int())
	for config in category_slot.product_configs:
		var template := get_product(config.product_id)
		if template == null:
			continue
		var product: ProductData = template.duplicate()
		product.average_price = config.get_effective_price(template)
		var profile := CustomerPreferenceConfig.get_profile(category, product)
		var group_weights := {}
		var price_rates := {}
		for group_id in SpatialConfig.POPULATION_GROUPS:
			group_weights[group_id] = CustomerPreferenceConfig.get_group_affinity(profile, group_id) * CustomerPreferenceConfig.get_time_affinity(profile, TimeManager.get_current_hour_int()) * maxf(0.0, product.offline_influence) / pow(maxf(1.0, product.average_price), 0.12)
			price_rates[group_id] = float(group_profiles.get(group_id, {}).get("price_rejection_rate", 0.0))
		group_weights["external"] = 1.0
		price_rates["external"] = 0.0
		profile["weight_by_group"] = group_weights
		profile["price_rejection_rate_by_group"] = price_rates
		var limit := store.get_max_produceable_by_ingredients(template, consumption)
		options.append({"product": product, "profile": profile, "service_seconds": get_product_service_seconds(category, product, float(participant.staffing_power)), "inventory_limit": limit, "unit_ingredient_cost": get_product_unit_ingredient_cost_for_store(store, template, consumption), "unit_utility_cost": get_product_unit_utility_cost(template), "reserve_ingredients": _reserve_product_ingredients.bind(store, template, consumption)})
		products.append({"product": product, "product_template": template, "inventory_limit": limit, "ingredient_consumption_multiplier": consumption})
	var service := CategoryServiceSimulator.new(category.id)
	service.setup(category.id, visitors, group_profiles, options, SettlementConfig.CUSTOMER_MAX_QUEUE_WAIT_SECONDS)
	active_simulations.append({"store_id": store.id, "store": store, "service": service, "params": params, "category": category, "products": products})


func _begin_slot_simulation_for_store(store: Store) -> void:
	_begin_slot_simulation_for_stores([store])
	return
	var storefront := get_storefront(store.selected_storefront_id)
	if storefront == null or store.category_slots.is_empty():
		return
	var city_region := get_city_region(storefront.city_region_id)
	if city_region == null:
		return

	var hour := TimeManager.get_current_hour_int()
	var is_weekend := (TimeManager.current_day % 7) in SettlementConfig.WEEKEND_DAY_REMAINDERS
	var active_product_count := 0
	var active_category_count := 0
	for category_slot in store.category_slots:
		var slot_category := get_category(category_slot.category_id)
		if slot_category == null or category_slot.product_configs.is_empty():
			continue
		if not store_has_category_equipment(store, slot_category):
			continue
		if get_category_staffing_power(store, slot_category, hour) <= 0.0:
			continue
		active_product_count += category_slot.product_configs.size()
		active_category_count += 1
	if active_product_count <= 0:
		return
	# Category-level order streams. A category gets one candidate flow regardless
	# of its menu size; products are selected only when a customer arrives.
	var block_visitor_multipliers := _get_block_visitor_multipliers()
	var city_region_visitor_multiplier := _get_city_region_visitor_multiplier(city_region.id)
	for cat_slot in store.category_slots:
		var category := get_category(cat_slot.category_id)
		if category == null or cat_slot.product_configs.is_empty() or not store_has_category_equipment(store, category):
			continue
		var staffing_power := get_category_staffing_power(store, category, hour)
		if staffing_power <= 0.0:
			continue
		var first_template := get_product(cat_slot.product_configs[0].product_id)
		if first_template == null:
			continue
		var category_front := storefront.duplicate()
		category_front.capture_modifier *= StoreLayoutEffects.get_capture_multiplier(store)
		var trade_area := TradeAreaCalculator.calculate_snapshot(category_front, category.id, first_template.id, hour, city_region, all_blocks, is_weekend, TradeAreaCalculator.DEFAULT_MAX_RADIUS, block_visitor_multipliers, city_region_visitor_multiplier, TimeManager.current_day)
		var category_params := SettlementEngine.calculate_params_from_trade_area(trade_area, category_front, category, first_template, store, player_state, hour, store.is_business_open, staffing_power)
		var competition_mod := maxf(0.01, trade_area.average_competition_modifier)
		category_params.lost_external_competition = maxi(0, int(round(float(category_params.get("visitors", 0)) / competition_mod)) - int(category_params.get("visitors", 0)))
		var category_share := 1.0 / float(maxi(1, active_category_count))
		category_params.visitors = maxi(0, int(round(float(category_params.get("visitors", 0)) * category_share)))
		category_params.visitors += get_destination_visitors(store, storefront, category_share)
		var options: Array[Dictionary] = []
		var products: Array[Dictionary] = []
		var weighted_sensitivity := 0.5
		var weighted_tier := "medium"
		var contribution_total := 0.0
		var sensitivity_total := 0.0
		var tier_weights := {"low": 0.0, "medium": 0.0, "high": 0.0}
		for contribution in trade_area.block_contributions:
			var weight := float(contribution.get("contribution", 0.0))
			var spending: Dictionary = contribution.get("spending_profile", {})
			contribution_total += weight
			sensitivity_total += weight * float(spending.get("price_sensitivity", 0.5))
			var tier := str(spending.get("spend_potential_tier", "medium"))
			tier_weights[tier] = float(tier_weights.get(tier, 0.0)) + weight
		if contribution_total > 0.0:
			weighted_sensitivity = sensitivity_total / contribution_total
			for tier in tier_weights:
				if float(tier_weights[tier]) > float(tier_weights[weighted_tier]): weighted_tier = tier
		var consumption := get_category_ingredient_consumption_multiplier(store, category, hour)
		for config in cat_slot.product_configs:
			var template := get_product(config.product_id)
			if template == null: continue
			var product: ProductData = template.duplicate()
			product.average_price = config.get_effective_price(template)
			var profile := CustomerPreferenceConfig.get_profile(category, product)
			var group_weights := {}
			var price_rates := {}
			for group_id in SpatialConfig.POPULATION_GROUPS:
				group_weights[group_id] = CustomerPreferenceConfig.get_group_affinity(profile, group_id) * CustomerPreferenceConfig.get_time_affinity(profile, hour) / pow(maxf(1.0, product.average_price), 0.12)
				var spend_fit := CustomerPreferenceConfig.get_spending_affinity(str(profile.get("spending_tier", "medium")), weighted_tier)
				price_rates[group_id] = clampf((1.0 - spend_fit) * (0.25 + weighted_sensitivity * 0.5), 0.0, 0.6)
			profile["weight_by_group"] = group_weights
			profile["price_rejection_rate_by_group"] = price_rates
			var limit := store.get_max_produceable_by_ingredients(template, consumption)
			var service_seconds := get_product_service_seconds(category, product, staffing_power)
			options.append({"product": product, "profile": profile, "service_seconds": service_seconds, "inventory_limit": limit, "unit_ingredient_cost": get_product_unit_ingredient_cost_for_store(store, template, consumption), "unit_utility_cost": get_product_unit_utility_cost(template), "reserve_ingredients": _reserve_product_ingredients.bind(store, template, consumption)})
			products.append({"product": product, "product_template": template, "inventory_limit": limit, "ingredient_consumption_multiplier": consumption})
		var service := CategoryServiceSimulator.new(category.id)
		service.setup(category.id, int(category_params.get("visitors", 0)), category_params.get("group_profiles", {}), options, SettlementConfig.CUSTOMER_MAX_QUEUE_WAIT_SECONDS)
		active_simulations.append({"store_id": store.id, "service": service, "params": category_params, "category": category, "products": products})
	return
	var menu_shares := _get_active_menu_shares(store, hour)
	for cat_slot in store.category_slots:
		var category := get_category(cat_slot.category_id)
		if category == null or cat_slot.product_configs.is_empty():
			continue
		if not store_has_category_equipment(store, category):
			continue
		var category_service := CategoryServiceSimulator.new(category.id)
		var category_service_queue := category_service.get_shared_state()

		var product_count: int = cat_slot.product_configs.size()
		var staffing_power := get_category_staffing_power(store, category, hour)
		var ingredient_consumption_multiplier := get_category_ingredient_consumption_multiplier(store, category, hour)

		for pc in cat_slot.product_configs:
			var product_template := get_product(pc.product_id)
			if product_template == null:
				continue
			var product_share := float(menu_shares.get(_get_menu_share_key(category.id, product_template.id), 0.0))
			if product_share <= 0.0:
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
				city_region_visitor_multiplier, TimeManager.current_day)

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
				var service_seconds := get_product_service_seconds(category, product_instance, staffing_power) * maxf(0.1, 1.0 + service_time_multiplier_add)
				var reserve_ingredients := _reserve_product_ingredients.bind(
					store, product_template, ingredient_consumption_multiplier)
				sim.setup(params.visitors, 3600.0, params.conversion_rate,
					service_seconds, SettlementConfig.CUSTOMER_MAX_QUEUE_WAIT_SECONDS, entry.inventory_limit,
					product_instance.average_price, unit_ingredient_cost, unit_utility_cost,
					reserve_ingredients, params.get("group_profiles", {}), category_service_queue)
				entry.sim = sim
				entry.category_service = category_service

			active_simulations.append(entry)


func advance_slot_simulation(elapsed_seconds: float) -> void:
	_advance_arrival_queue(elapsed_seconds)


func _advance_slot_simulation_legacy(elapsed_seconds: float) -> void:
	## 所有商品共用一个按到达时间排序的订单流；这样共享原料由真实先后顺序竞争。
	while true:
		var next_entry: Dictionary = {}
		var earliest_arrival := INF
		for entry in active_simulations:
			var service: CategoryServiceSimulator = entry.get("service", null)
			if service != null:
				if service.next_arrival_at <= elapsed_seconds and service.next_arrival_at <= service.slot_duration_seconds and service.next_arrival_at < earliest_arrival:
					earliest_arrival = service.next_arrival_at
					next_entry = entry
				continue
			var sim: CustomerSimulator = entry.get("sim", null)
			if sim == null or sim.next_arrival_at > elapsed_seconds or sim.next_arrival_at > sim.slot_duration_seconds:
				continue
			if sim.next_arrival_at < earliest_arrival:
				earliest_arrival = sim.next_arrival_at
				next_entry = entry
		if next_entry.is_empty():
			break
		var next_service: CategoryServiceSimulator = next_entry.get("service", null)
		if next_service != null:
			if not next_service.process_next_arrival_if_due(elapsed_seconds): break
			continue
		var next_sim: CustomerSimulator = next_entry.get("sim", null)
		if next_sim == null or not next_sim.process_next_arrival_if_due(elapsed_seconds):
			break
		var category_service: CategoryServiceSimulator = next_entry.get("category_service", null)
		if category_service != null:
			category_service.sync_from_state(next_sim.shared_service_state)


func _advance_arrival_queue(elapsed_seconds: float) -> void:
	while not _arrival_queue.is_empty():
		var next_entry: Dictionary = _arrival_queue[0]
		if _get_entry_next_arrival(next_entry) > elapsed_seconds:
			break
		_arrival_queue.pop_front()
		var next_service: CategoryServiceSimulator = next_entry.get("service", null)
		if next_service != null:
			if not next_service.process_next_arrival_if_due(elapsed_seconds):
				_reinsert_arrival_entry(next_entry)
				break
			_reinsert_arrival_entry(next_entry)
			continue
		var next_sim: CustomerSimulator = next_entry.get("sim", null)
		if next_sim == null or not next_sim.process_next_arrival_if_due(elapsed_seconds):
			_reinsert_arrival_entry(next_entry)
			break
		var category_service: CategoryServiceSimulator = next_entry.get("category_service", null)
		if category_service != null:
			category_service.sync_from_state(next_sim.shared_service_state)
		_reinsert_arrival_entry(next_entry)


func _rebuild_arrival_queue() -> void:
	_arrival_queue.clear()
	for index in range(active_simulations.size()):
		var entry := active_simulations[index]
		entry["_simulation_order"] = index
		if _entry_has_pending_arrival(entry):
			_arrival_queue.append(entry)
	_arrival_queue.sort_custom(_arrival_entry_less)


func _reinsert_arrival_entry(entry: Dictionary) -> void:
	if not _entry_has_pending_arrival(entry):
		return
	var low := 0
	var high := _arrival_queue.size()
	while low < high:
		var middle := floori(float(low + high) * 0.5)
		if _arrival_entry_less(entry, _arrival_queue[middle]):
			high = middle
		else:
			low = middle + 1
	_arrival_queue.insert(low, entry)


func _entry_has_pending_arrival(entry: Dictionary) -> bool:
	var service: CategoryServiceSimulator = entry.get("service", null)
	if service != null:
		return service.next_arrival_at <= service.slot_duration_seconds
	var sim: CustomerSimulator = entry.get("sim", null)
	return sim != null and sim.next_arrival_at <= sim.slot_duration_seconds


func _get_entry_next_arrival(entry: Dictionary) -> float:
	var service: CategoryServiceSimulator = entry.get("service", null)
	if service != null:
		return service.next_arrival_at
	var sim: CustomerSimulator = entry.get("sim", null)
	return sim.next_arrival_at if sim != null else INF


func _arrival_entry_less(a: Dictionary, b: Dictionary) -> bool:
	var a_time := _get_entry_next_arrival(a)
	var b_time := _get_entry_next_arrival(b)
	if a_time != b_time:
		return a_time < b_time
	return int(a.get("_simulation_order", 0)) < int(b.get("_simulation_order", 0))


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
	var awareness_blocks: Dictionary = store.awareness_by_block.duplicate()
	for brand_block_id in player_state.brand_awareness_by_block:
		awareness_blocks[brand_block_id] = maxf(float(awareness_blocks.get(brand_block_id, 0.0)), float(player_state.brand_awareness_by_block.get(brand_block_id, 0.0)) * 0.5)
	for block_id in awareness_blocks.keys():
		var awareness := float(awareness_blocks.get(block_id, 0.0))
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


## Retained only while the legacy product-stream block below is removed in a
## follow-up cleanup; the live slot path never reads menu shares.
func _get_menu_share_key(category_id: String, product_id: String) -> String:
	return category_id + ":" + product_id


func _get_active_menu_shares(store: Store, hour: int) -> Dictionary:
	var weights: Dictionary = {}
	var total := 0.0
	if store == null:
		return weights
	for slot in store.category_slots:
		var category := get_category(slot.category_id)
		if category == null or not store_has_category_equipment(store, category) or get_category_staffing_power(store, category, hour) <= 0.0:
			continue
		for config in slot.product_configs:
			var product := get_product(config.product_id)
			if product == null:
				continue
			var profile := CustomerPreferenceConfig.get_profile(category, product)
			var weight := maxf(0.1, CustomerPreferenceConfig.get_time_affinity(profile, hour) / pow(maxf(1.0, config.get_effective_price(product)), 0.12))
			weights[_get_menu_share_key(category.id, product.id)] = weight
			total += weight
	if total > 0.0001:
		for key in weights:
			weights[key] = float(weights[key]) / total
	return weights


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
		var category_service: CategoryServiceSimulator = entry.get("service", null)
		if category_service != null:
			has_live_entry = true
			if not store.is_business_open:
				category_service.arrival_rate_per_second = 0.0
				category_service.next_arrival_at = INF
				continue
			var category_for_service: CategoryData = entry.get("category", null)
			if category_for_service == null or get_category_staffing_power(store, category_for_service, hour) <= 0.0:
				category_service.arrival_rate_per_second = 0.0
				category_service.next_arrival_at = INF
				continue
			if category_service.arrival_rate_per_second <= 0.0:
				category_service.arrival_rate_per_second = float(entry.get("params", {}).get("visitors", 0)) / 3600.0
				category_service._schedule_next_arrival(TimeManager.total_game_seconds - floor(TimeManager.total_game_seconds / 3600.0) * 3600.0)
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
		if power <= 0.0:
			sim.arrival_rate_per_second = 0.0
			sim.next_arrival_at = INF
			continue
		if sim.arrival_rate_per_second <= 0.0:
			var params: Dictionary = entry.get("params", {})
			sim.arrival_rate_per_second = float(params.get("visitors", 0)) / 3600.0
			sim._schedule_next_arrival(TimeManager.total_game_seconds - floor(TimeManager.total_game_seconds / 3600.0) * 3600.0)
		sim.service_time_seconds = get_product_service_seconds(category, product, power)
	if not has_live_entry and store.is_business_open:
		_begin_slot_simulation_for_store(store)
	_rebuild_arrival_queue()


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
		var store: Store = entry.get("store", get_any_store(entry.store_id))
		if store == null:
			continue
		var category_service: CategoryServiceSimulator = entry.get("service", null)
		if category_service != null:
			var category: CategoryData = entry.get("category", null)
			var products: Array = entry.get("products", [])
			for product_index in products.size():
				var product_entry: Dictionary = products[product_index]
				var product: ProductData = product_entry.get("product", null)
				var template: ProductData = product_entry.get("product_template", null)
				if category == null or product == null or template == null: continue
				var ledger: CustomerSimulator = category_service.product_ledgers.get(product.id, null)
				var result := SettlementEngine.finalize_from_simulation(entry.params, hour, day, category, product, int(product_entry.get("inventory_limit", 0)), ledger)
				if product_index == 0:
					result.group_summary = category_service.group_summary.duplicate(true)
					result.lost_no_menu = category_service.lost_no_menu
					result.lost_price_rejection = category_service.lost_price_rejection
					result.lost_capacity = category_service.lost_capacity
					result.lost_inventory = category_service.lost_inventory
					result.lost_external_competition = int(entry.params.get("lost_external_competition", 0))
				result.ingredient_consumption_multiplier = float(product_entry.get("ingredient_consumption_multiplier", 1.0))
				result.preparation_waste_ingredients = store.get_preparation_waste_for_orders(template, result.actual_orders, result.ingredient_consumption_multiplier)
				store.apply_settlement(result)
				if store.owner_kind == "npc": store.apply_npc_financial_result(result)
				else: player_state.apply_settlement(result)
				results.append(result)
				if not results_by_store.has(store.id): results_by_store[store.id] = []
				results_by_store[store.id].append(result)
			if bool(entry.params.get("is_open", false)): operating_store_ids[store.id] = true
			continue

		var result: SettlementResult
		if entry.sim != null:
			result = SettlementEngine.finalize_from_simulation(
				entry.params, hour, day, entry.category, entry.product,
				entry.inventory_limit, entry.sim)

			result.ingredient_consumption_multiplier = float(entry.get("ingredient_consumption_multiplier", 1.0))
			result.preparation_waste_ingredients = store.get_preparation_waste_for_orders(
				entry.product_template, result.actual_orders, result.ingredient_consumption_multiplier)
		else:
			result = SettlementEngine.finalize_from_simulation(
				entry.params, hour, day, entry.category, entry.product, 0, null)

		store.apply_settlement(result)
		if store.owner_kind == "npc": store.apply_npc_financial_result(result)
		else: player_state.apply_settlement(result)
		results.append(result)

		if not results_by_store.has(store.id):
			results_by_store[store.id] = []
		results_by_store[store.id].append(result)
		if bool(entry.params.get("is_open", false)):
			operating_store_ids[store.id] = true

	var spoilage_by_store: Dictionary = {}
	for open_store in get_all_open_stores():
		spoilage_by_store[open_store.id] = open_store.apply_ingredient_spoilage(
			get_ingredient_spoilage_ratios(open_store))

	## Fixed costs are accrued once for every opened store, independent of the
	## number of products, active staff, or completed orders in this hour.
	for open_store in get_all_open_stores():
		var fixed_store_id := open_store.id
		var fixed_storefront := get_storefront(open_store.selected_storefront_id)
		var base_lease_cost := fixed_storefront.get_monthly_rent_yuan() / 30.0 / 24.0 if fixed_storefront != null else 0.0
		var lease_cost := base_lease_cost * open_store.lease_rent_multiplier
		if open_store.is_business_open and open_store.lease_free_rent_hours_remaining > 0.0:
			lease_cost = 0.0
			open_store.lease_free_rent_hours_remaining = maxf(0.0, open_store.lease_free_rent_hours_remaining - 1.0)
		var category_cost := _get_store_category_hourly_occupancy_cost(open_store)
		var is_operating := operating_store_ids.has(fixed_store_id)
		var fixed_utility := get_equipment_hourly_utility_cost(open_store) if is_operating else get_storage_equipment_hourly_utility_cost(open_store)
		var fixed_wages := get_scheduled_staff_hourly_cost(open_store, hour) if open_store.is_business_open else 0.0
		var fixed_overhead := SettlementResult.new()
		fixed_overhead.day = day
		fixed_overhead.slot = "%02d:00" % hour
		fixed_overhead.is_open = open_store.is_business_open
		fixed_overhead.is_store_overhead = true
		fixed_overhead.product_name = "Store fixed costs"
		fixed_overhead.rent_cost = lease_cost + category_cost
		fixed_overhead.utility_cost = fixed_utility
		fixed_overhead.staff_cost = fixed_wages
		fixed_overhead.lease_cost = lease_cost
		fixed_overhead.category_occupancy_cost = category_cost
		fixed_overhead.operating_equipment_cost = fixed_utility if is_operating else 0.0
		fixed_overhead.storage_equipment_cost = fixed_utility if not is_operating else 0.0
		fixed_overhead.scheduled_wage_cost = fixed_wages
		fixed_overhead.spoilage_ingredients = spoilage_by_store.get(fixed_store_id, {})
		fixed_overhead.profit = -(fixed_overhead.rent_cost + fixed_utility + fixed_wages)
		open_store.apply_settlement(fixed_overhead)
		if open_store.owner_kind == "npc": open_store.apply_npc_financial_result(fixed_overhead)
		else: player_state.apply_settlement(fixed_overhead)
		results.append(fixed_overhead)
		if not results_by_store.has(fixed_store_id):
			results_by_store[fixed_store_id] = []
		results_by_store[fixed_store_id].append(fixed_overhead)

	for store_id in results_by_store.keys():
		var settled_store := get_any_store(store_id)
		if settled_store != null and settled_store.owner_kind == "player":
			_apply_operating_understanding_gain(settled_store, results_by_store[store_id], hour, day)

	if hour == 23:
		_run_npc_daily_operations(day)

	active_simulations.clear()
	_arrival_queue.clear()
	return results


func _get_store_category_hourly_occupancy_cost(store: Store) -> float:
	var total := 0.0
	if store == null:
		return total
	for slot in store.category_slots:
		var category := get_category(slot.category_id)
		if category != null:
			total += category.extra_rent_wan * 10000.0 / 30.0 / 24.0
	return total


func _run_npc_daily_operations(day: int) -> void:
	for store in npc_stores:
		if store.owner_kind != "npc" or store.transfer_state == "closed":
			continue
		var summary := store.get_day_summary(day)
		var profit := float(summary.get("profit", 0.0))
		store.consecutive_loss_days = store.consecutive_loss_days + 1 if profit < 0.0 else 0
		store.owner_stress = clampf(store.owner_stress + (-profit / 350.0), 0.0, 100.0)
		_npc_restock_and_adjust(store, day, profit)
		if store.lease_end_day >= 0 and day >= store.lease_end_day:
			_close_npc_store(store, "lease_expired")
			continue
		if store.transfer_state == "none" and store.consecutive_loss_days >= 3 and _should_offer_npc_transfer(store, day, profit):
			store.transfer_state = "offered"
			store.transfer_record = {"offered_day": day, "asking_price": _get_npc_transfer_price(store), "reason": "sustained_loss"}
			continue
		if store.operating_cash <= 0.0 and profit < 0.0:
			_close_npc_store(store, "insolvent")


func _npc_restock_and_adjust(store: Store, day: int, profit: float) -> void:
	if store.operating_cash <= 0.0:
		store.is_business_open = false
		return
	var restock_budget := minf(store.operating_cash * 0.18, 5000.0)
	if store.has_owner_trait("anxious"):
		restock_budget *= 0.75
	if store.has_owner_trait("negotiator"):
		restock_budget *= 1.08
	for slot in store.category_slots:
		for config in slot.product_configs:
			var product := get_product(config.product_id)
			if product == null:
				continue
			for recipe_item in product.recipe:
				var ingredient_id := str(recipe_item.get("ingredient_id", ""))
				if ingredient_id.is_empty() or restock_budget <= 0.0:
					continue
				var amount := minf(120.0, restock_budget / 2.0)
				store.add_ingredient_stock(ingredient_id, amount, 2.0)
				restock_budget -= amount * 2.0
				store.operating_cash -= amount * 2.0
	if profit < 0.0:
		for slot in store.category_slots:
			for config in slot.product_configs:
				if config.custom_price > 0.0:
					config.custom_price *= 1.02 if store.has_owner_trait("negotiator") else 0.99
		if not store.business_hour_ranges.is_empty() and store.consecutive_loss_days >= 2:
			var current_range := store.business_hour_ranges[0]
			if current_range.y - current_range.x > 6:
				store.business_hour_ranges[0] = Vector2i(current_range.x + 1, current_range.y)
				for employee in store.employees:
					employee.work_hour_ranges = store.business_hour_ranges.duplicate()
	store.is_business_open = store.operating_cash > 0.0


func _should_offer_npc_transfer(store: Store, day: int, profit: float) -> bool:
	var chance := 0.08 + float(store.consecutive_loss_days) * 0.035
	chance += maxf(0.0, store.owner_stress - 50.0) / 250.0
	chance += maxf(0.0, -profit) / 12000.0
	chance += 0.07 if store.has_owner_trait("anxious") else 0.0
	chance -= 0.05 if store.has_owner_trait("stress_resistant") else 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(hash("transfer:%s:%d" % [store.id, day]))
	return rng.randf() < clampf(chance, 0.0, 0.75)


func _get_npc_transfer_price(store: Store) -> float:
	var assets := 0.0
	for equipment in store.equipment:
		var definition := get_equipment(equipment.equipment_id)
		assets += definition.price * 0.45 if definition != null else 0.0
	return maxf(2000.0, assets + store.operating_cash * 0.15 + store.reputation * 35.0)


func _close_npc_store(store: Store, reason: String) -> void:
	store.is_open = false
	store.is_business_open = false
	store.transfer_state = "closed"
	store.transfer_record["closed_reason"] = reason
	store.transfer_record["closed_day"] = TimeManager.current_day
	store.owner_kind = "archived_npc"
	var storefront := get_storefront(store.selected_storefront_id)
	if storefront != null:
		storefront.is_occupied = false
		storefront.occupant_name = ""


func take_over_npc_store(npc_store_id: String, price_multiplier: float = 1.0) -> Dictionary:
	var store := get_npc_store(npc_store_id)
	if store == null or store.transfer_state != "offered":
		return {"success": false, "reason": "这间店目前没有可接手的转让报价"}
	var price := float(store.transfer_record.get("asking_price", 0.0)) * maxf(0.1, price_multiplier)
	if player_state.cash < price:
		return {"success": false, "reason": "现金不足以接手这间店"}
	player_state.cash -= price
	store.owner_kind = "player"
	store.owner_name = player_state.player_name
	store.owner_trait_ids = []
	store.transfer_state = "none"
	store.transfer_record["taken_over_day"] = TimeManager.current_day
	var storefront := get_storefront(store.selected_storefront_id)
	if storefront != null:
		storefront.is_occupied = true
		storefront.occupant_name = player_state.player_name
	npc_stores.erase(store)
	stores.append(store)
	active_store_id = store.id
	_sync_data_objects()
	active_store_changed.emit(active_store_id)
	return {"success": true, "reason": "已接手 %s" % store.name, "store_id": store.id}


## backlog任务4：经营数据反哺区块了解度。现在按"这次结算属于哪家店"分别计算，
## 不再依赖current_storefront这个单一指针。
func _apply_operating_understanding_gain(store: Store, results: Array, settled_hour: int = -1, settled_day: int = -1) -> void:
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

	store.last_awareness_update = _apply_store_awareness_growth(store, storefront, results, total_orders, settled_hour, settled_day)

	if total_orders <= 0:
		return

	var gain := float(total_orders) * SpatialConfig.OPERATING_UNDERSTANDING_PER_ORDER
	advance_block_research_progress(block.id, "spending", gain * 0.5)
	advance_block_research_progress(block.id, "demand", gain * 0.5)
	recalculate_region_intel(block.city_region_id)


func _apply_store_awareness_growth(store: Store, storefront: StorefrontData, results: Array, total_orders: int, settled_hour: int = -1, settled_day: int = -1) -> Dictionary:
	if store == null or storefront == null:
		return {}
	var local_block := _get_block_for_storefront(storefront)
	if local_block == null:
		return {}
	## 只要实际营业，门面所在道路带来的曝光就会累积；它不依赖本时段是否成交。
	var awareness_gain_multiplier := _get_store_awareness_gain_multiplier(store, storefront) * StoreLayoutEffects.get_awareness_multiplier(store)
	var coverage_ratios := StorefrontInfluenceCalculator.get_covered_block_ratios(storefront, all_blocks)
	var exposure_gain := get_storefront_road_exposure(storefront) * storefront.awareness_exposure_modifier * 0.05 * awareness_gain_multiplier
	var exposure_by_block := _apply_offline_awareness_to_covered_blocks(store, storefront, coverage_ratios, exposure_gain)
	var word_of_mouth_gain := 0.0
	var word_of_mouth_by_block: Dictionary = {}
	if total_orders <= 0:
		return _make_awareness_update_snapshot(store, storefront, local_block, coverage_ratios, exposure_gain, 0.0, exposure_by_block, word_of_mouth_by_block, awareness_gain_multiplier, settled_hour, settled_day)

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
	word_of_mouth_gain = float(total_orders) * 0.02 * memorable_service_multiplier * reputation_memory_multiplier * storefront.awareness_exposure_modifier * awareness_gain_multiplier
	word_of_mouth_by_block = _apply_offline_awareness_to_covered_blocks(store, storefront, coverage_ratios, word_of_mouth_gain)
	return _make_awareness_update_snapshot(store, storefront, local_block, coverage_ratios, exposure_gain, word_of_mouth_gain, exposure_by_block, word_of_mouth_by_block, awareness_gain_multiplier, settled_hour, settled_day)


func _apply_offline_awareness_to_covered_blocks(store: Store, storefront: StorefrontData, coverage_ratios: Dictionary, base_gain: float) -> Dictionary:
	var applied: Dictionary = {}
	if base_gain <= 0.0:
		return applied
	for raw_block_id in coverage_ratios.keys():
		var block_id := str(raw_block_id)
		var block := get_block(block_id)
		if block == null or block.city_region_id != storefront.city_region_id:
			continue
		var gain := _add_store_awareness(store, block_id, base_gain * float(coverage_ratios.get(raw_block_id, 0.0)))
		if gain > 0.0:
			applied[block_id] = gain
	return applied


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


func _add_store_awareness(store: Store, block_id: String, gain: float) -> float:
	if store == null or block_id.is_empty() or gain <= 0.0:
		return 0.0
	var before := float(store.awareness_by_block.get(block_id, 0.0))
	var after := clampf(before + gain, 0.0, 100.0)
	store.awareness_by_block[block_id] = after
	var applied := after - before
	if applied > 0.0:
		var brand_before := float(player_state.brand_awareness_by_block.get(block_id, 0.0))
		player_state.brand_awareness_by_block[block_id] = clampf(brand_before + applied * 0.35, 0.0, 100.0)
	return applied


func _make_awareness_update_snapshot(store: Store, storefront: StorefrontData, local_block: BlockData, coverage_ratios: Dictionary, exposure_gain: float, word_of_mouth_gain: float, exposure_by_block: Dictionary, word_of_mouth_by_block: Dictionary, gain_multiplier: float, settled_hour: int, settled_day: int) -> Dictionary:
	var current_awareness: Dictionary = {}
	for raw_block_id in coverage_ratios.keys():
		var block_id := str(raw_block_id)
		current_awareness[block_id] = float(store.awareness_by_block.get(block_id, 0.0))
	var total_gain := 0.0
	for gain in exposure_by_block.values():
		total_gain += float(gain)
	for gain in word_of_mouth_by_block.values():
		total_gain += float(gain)
	return {
		"day": settled_day if settled_day >= 1 else TimeManager.current_day,
		"hour": settled_hour if settled_hour >= 0 else TimeManager.get_current_hour_int(),
		"storefront_id": storefront.id, "local_block_id": local_block.id,
		"coverage_ratios": coverage_ratios.duplicate(true), "current_awareness": current_awareness,
		"exposure_base_gain": exposure_gain, "word_of_mouth_base_gain": word_of_mouth_gain,
		"exposure_by_block": exposure_by_block.duplicate(true), "word_of_mouth_by_block": word_of_mouth_by_block.duplicate(true),
		"total_gain": total_gain, "awareness_radius": storefront.awareness_radius,
		"awareness_exposure_modifier": storefront.awareness_exposure_modifier,
		"gain_multiplier": gain_multiplier,
		"destination_sources": get_destination_visitor_sources(store, storefront),
	}


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
