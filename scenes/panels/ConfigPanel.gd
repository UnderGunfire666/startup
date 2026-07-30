extends PanelContainer
## 配置面板：选择区域/门面 + 是否亲自坐镇。
## 品类/产品/员工/策略的添加与调整已移交给 CategoryManagerPanel（多品类门店架构下，
## 一个门店可同时经营多个品类，不再适合在本面板里做单一品类的下拉选择）。

signal config_applied

@onready var region_option: OptionButton     = $VBox/RegionRow/RegionOption
@onready var storefront_option: OptionButton = $VBox/StorefrontRow/StorefrontOption
@onready var owner_present_check: CheckBox   = $VBox/OwnerRow/OwnerPresentCheck
@onready var apply_button: Button            = $VBox/ApplyButton
@onready var status_label: Label             = $VBox/StatusLabel

var _region_ids: Array[String] = []
var _storefront_ids: Array[String] = []

func _ready() -> void:
	_populate_regions()
	region_option.item_selected.connect(_on_region_selected)
	apply_button.pressed.connect(_on_apply_pressed)
	if region_option.item_count > 0:
		_on_region_selected(0)

func _populate_regions() -> void:
	region_option.clear()
	_region_ids.clear()
	for r in GameManager.all_regions:
		region_option.add_item("%s %s" % [r.id, r.name])
		_region_ids.append(r.id)

func _on_region_selected(idx: int) -> void:
	var region_id: String = _region_ids[idx]
	_populate_storefronts_for_region(region_id)

func _populate_storefronts_for_region(region_id: String) -> void:
	storefront_option.clear()
	_storefront_ids.clear()
	var list: Array[StorefrontData] = GameManager.get_storefronts_for_region(region_id)
	for s in list:
		storefront_option.add_item("%s %s (%s)" % [s.id, s.name, s.storefront_flow])
		_storefront_ids.append(s.id)
	if storefront_option.item_count == 0:
		status_label.text = "⚠ 该区域暂无门面数据"

func _on_apply_pressed() -> void:
	if region_option.selected < 0 or storefront_option.selected < 0:
		status_label.text = "⚠ 请完整选择区域/门面"
		return

	var state: StoreState = GameManager.store_state
	var new_storefront_id: String = _storefront_ids[storefront_option.selected]
	var storefront_changed: bool = state.selected_storefront_id != new_storefront_id

	state.selected_region_id     = _region_ids[region_option.selected]
	state.selected_storefront_id = new_storefront_id
	state.owner_present          = owner_present_check.button_pressed

	# 更换门面时，已添加的品类实例可能超出新门面面积/不受支持，直接清空并提示。
	if storefront_changed and not state.category_slots.is_empty():
		state.category_slots.clear()
		status_label.text = "✅ 配置已应用（已切换门面，原有品类已清空，请重新在品类管理面板添加）"
	else:
		status_label.text = "✅ 配置已应用"

	GameManager._sync_data_objects()
	config_applied.emit()
