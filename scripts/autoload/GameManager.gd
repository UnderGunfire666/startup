extends Node

var store_state: StoreState = StoreState.new()
var debug_ignore_category_restriction: bool = false

var current_region: RegionData = null
var current_storefront: StorefrontData = null
var current_category: CategoryData = null
var current_product: ProductData = null

var all_regions: Array[RegionData] = []
var all_storefronts: Array[StorefrontData] = []
var all_categories: Array[CategoryData] = []
var all_products: Array[ProductData] = []

## 供 UI 显示错误原因用
var last_settlement_error: String = ""

func _ready() -> void:
	all_regions     = GameData.get_regions()
	all_storefronts = GameData.get_storefronts()
	all_categories  = GameData.get_categories()
	all_products    = GameData.get_products()

func get_region(id: String) -> RegionData:
	for r in all_regions:
		if r.id == id: return r
	return null

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

func get_storefronts_for_region(region_id: String) -> Array[StorefrontData]:
	var result: Array[StorefrontData] = []
	for s in all_storefronts:
		if s.region_id == region_id:
			result.append(s)
	return result

func get_products_for_category(category_id: String) -> Array[ProductData]:
	var result: Array[ProductData] = []
	for p in all_products:
		if p.category_id == category_id:
			result.append(p)
	return result

func run_settlement() -> SettlementResult:
	last_settlement_error = ""

	if current_region == null:
		last_settlement_error = "未选择有效区域（请先点击「应用配置」或调试场景按钮）"
	elif current_storefront == null:
		last_settlement_error = "未选择有效门面"
	elif current_category == null:
		last_settlement_error = "未选择有效品类"
	elif current_product == null:
		last_settlement_error = "未选择有效主产品"

	if last_settlement_error != "":
		push_error("GameManager: " + last_settlement_error)
		return null

	var result := SettlementEngine.calculate(
		current_region,
		current_storefront,
		current_category,
		current_product,
		store_state,
		store_state.get_current_slot(),
		store_state.current_day,
		debug_ignore_category_restriction
	)
	store_state.apply_settlement(result)
	return result

func advance_time_only() -> void:
	store_state.advance_slot()

func apply_debug_scenario(scenario_id: String) -> void:
	store_state.reset_to_defaults()
	match scenario_id:
		"A":
			store_state.selected_region_id            = "A001"
			store_state.selected_storefront_id        = "S003"
			store_state.selected_category_id          = "fast_food"
			store_state.selected_primary_product_id   = "P005"
			store_state.has_key_staff                 = true
			store_state.strategy                      = "standard"
			store_state.inventory_units               = 100
		"B":
			store_state.selected_region_id            = "A002"
			store_state.selected_storefront_id        = "S001"
			store_state.selected_category_id          = "beverage_dessert"
			store_state.selected_primary_product_id   = "P007"
			store_state.has_key_staff                 = true
			store_state.strategy                      = "standard"
			store_state.inventory_units               = 100
		"C":
			store_state.selected_region_id            = "A001"
			store_state.selected_storefront_id        = "S003"
			store_state.selected_category_id          = "beverage_dessert"
			store_state.selected_primary_product_id   = "P008"
			store_state.has_key_staff                 = false
			store_state.strategy                      = "standard"
			store_state.inventory_units               = 100
			debug_ignore_category_restriction         = true
		"D":
			store_state.selected_region_id            = "A002"
			store_state.selected_storefront_id        = "S001"
			store_state.selected_category_id          = "breakfast"
			store_state.selected_primary_product_id   = "P001"
			store_state.has_key_staff                 = false
			store_state.strategy                      = "standard"
			store_state.inventory_units               = 100
		"E":
			store_state.selected_region_id            = "A001"
			store_state.selected_storefront_id        = "S003"
			store_state.selected_category_id          = "fast_food"
			store_state.selected_primary_product_id   = "P005"
			store_state.has_key_staff                 = false
			store_state.strategy                      = "standard"
			store_state.inventory_units               = 100
		"F":
			store_state.selected_region_id            = "A001"
			store_state.selected_storefront_id        = "S003"
			store_state.selected_category_id          = "fast_food"
			store_state.selected_primary_product_id   = "P005"
			store_state.has_key_staff                 = true
			store_state.strategy                      = "standard"
			store_state.inventory_units               = 5

	_sync_data_objects()

func _sync_data_objects() -> void:
	current_region     = get_region(store_state.selected_region_id)
	current_storefront = get_storefront(store_state.selected_storefront_id)
	current_category   = get_category(store_state.selected_category_id)
	current_product     = get_product(store_state.selected_primary_product_id)
