extends PanelContainer
## 配置面板：选择区域/门面/品类/产品/员工/策略/库存/坐镇
## 只负责收集玩家输入并写入 GameManager.store_state，不做任何结算计算。

signal config_applied

@onready var region_option: OptionButton   = $VBox/RegionRow/RegionOption
@onready var storefront_option: OptionButton = $VBox/StorefrontRow/StorefrontOption
@onready var category_option: OptionButton  = $VBox/CategoryRow/CategoryOption
@onready var product_option: OptionButton   = $VBox/ProductRow/ProductOption
@onready var key_staff_check: CheckBox      = $VBox/StaffRow/KeyStaffCheck
@onready var strategy_option: OptionButton  = $VBox/StrategyRow/StrategyOption
@onready var inventory_spin: SpinBox        = $VBox/InventoryRow/InventorySpin
@onready var owner_present_check: CheckBox  = $VBox/OwnerRow/OwnerPresentCheck
@onready var apply_button: Button           = $VBox/ApplyButton
@onready var status_label: Label            = $VBox/StatusLabel

var _region_ids: Array[String] = []
var _storefront_ids: Array[String] = []
var _category_ids: Array[String] = []
var _product_ids: Array[String] = []

func _ready() -> void:
	_populate_regions()
	_populate_categories()
	region_option.item_selected.connect(_on_region_selected)
	category_option.item_selected.connect(_on_category_selected)
	apply_button.pressed.connect(_on_apply_pressed)
	_populate_strategy_options()
	# 初始联动
	if region_option.item_count > 0:
		_on_region_selected(0)
	if category_option.item_count > 0:
		_on_category_selected(0)

func _populate_regions() -> void:
	region_option.clear()
	_region_ids.clear()
	for r in GameManager.all_regions:
		region_option.add_item("%s %s" % [r.id, r.name])
		_region_ids.append(r.id)

func _populate_categories() -> void:
	category_option.clear()
	_category_ids.clear()
	for c in GameManager.all_categories:
		category_option.add_item(c.name)
		_category_ids.append(c.id)

func _populate_strategy_options() -> void:
	strategy_option.clear()
	strategy_option.add_item("标准 standard")
	strategy_option.add_item("延长 extend")
	strategy_option.add_item("缩短 shorten")

func _on_region_selected(idx: int) -> void:
	var region_id: String = _region_ids[idx]
	_populate_storefronts_for_region(region_id)

func _populate_storefronts_for_region(region_id: String) -> void:
	storefront_option.clear()
	_storefront_ids.clear()
	var list := GameManager.get_storefronts_for_region(region_id)
	for s in list:
		storefront_option.add_item("%s %s (%s)" % [s.id, s.name, s.storefront_flow])
		_storefront_ids.append(s.id)
	if storefront_option.item_count == 0:
		status_label.text = "⚠ 该区域暂无门面数据"

func _on_category_selected(idx: int) -> void:
	var category_id: String = _category_ids[idx]
	_populate_products_for_category(category_id)

func _populate_products_for_category(category_id: String) -> void:
	product_option.clear()
	_product_ids.clear()
	var list := GameManager.get_products_for_category(category_id)
	for p in list:
		product_option.add_item("%s %s (%.0f元)" % [p.id, p.name, p.average_price])
		_product_ids.append(p.id)

func _strategy_index_to_id(idx: int) -> String:
	match idx:
		0: return "standard"
		1: return "extend"
		2: return "shorten"
	return "standard"

func _on_apply_pressed() -> void:
	if region_option.selected < 0 or storefront_option.selected < 0 \
	or category_option.selected < 0 or product_option.selected < 0:
		status_label.text = "⚠ 请完整选择区域/门面/品类/产品"
		return

	var state := GameManager.store_state
	state.selected_region_id            = _region_ids[region_option.selected]
	state.selected_storefront_id        = _storefront_ids[storefront_option.selected]
	state.selected_category_id          = _category_ids[category_option.selected]
	state.selected_primary_product_id   = _product_ids[product_option.selected]
	state.has_key_staff                 = key_staff_check.button_pressed
	state.strategy                      = _strategy_index_to_id(strategy_option.selected)
	state.inventory_units                = int(inventory_spin.value)
	state.owner_present                  = owner_present_check.button_pressed

	GameManager._sync_data_objects()

	# 门面/品类适配预检查（提示而非阻断，实际结算由 SettlementEngine 判定）
	var sf := GameManager.current_storefront
	var cat := GameManager.current_category
	if sf != null and cat != null and cat.id not in sf.supported_categories \
	and not GameManager.debug_ignore_category_restriction:
		status_label.text = "⚠ 门面[%s]不支持品类[%s]，正常模式下将不营业" \
			% [sf.name, cat.name]
	else:
		status_label.text = "✅ 配置已应用"

	config_applied.emit()
