extends PanelContainer

signal category_changed

@onready var category_list: VBoxContainer = $VBox/ContentSplit/CategoryScroll/CategoryContent/CategoryList
@onready var parent_dropdown: OptionButton = $VBox/ContentSplit/CategoryScroll/CategoryContent/ParentDropdown
@onready var child_dropdown: OptionButton = $VBox/ContentSplit/CategoryScroll/CategoryContent/ChildDropdown
@onready var specific_product_list: VBoxContainer = $VBox/ContentSplit/CategoryScroll/CategoryContent/SpecificProductList
@onready var universal_product_list: VBoxContainer = $VBox/ContentSplit/CategoryScroll/CategoryContent/UniversalProductList
@onready var add_button: Button = $VBox/ContentSplit/CategoryScroll/CategoryContent/AddButton
@onready var equipment_summary: Label = $VBox/ContentSplit/EquipmentScroll/EquipmentContent/EquipmentSummary
@onready var equipment_list: VBoxContainer = $VBox/ContentSplit/EquipmentScroll/EquipmentContent/EquipmentList
@onready var status_label: Label = $VBox/StatusLabel
@onready var title_label: Label = $VBox/TitleLabel
@onready var current_label: Label = $VBox/ContentSplit/CategoryScroll/CategoryContent/CurrentLabel
@onready var select_label: Label = $VBox/ContentSplit/CategoryScroll/CategoryContent/SelectLabel
@onready var specific_header: Label = $VBox/ContentSplit/CategoryScroll/CategoryContent/SpecificHeader
@onready var equipment_title: Label = $VBox/ContentSplit/EquipmentScroll/EquipmentContent/EquipmentTitle

var _parent_names: Array[String] = []
var _child_categories: Array[CategoryData] = []
var _selected_category: CategoryData = null
var _product_checkboxes: Array[CheckBox] = []

func _ready() -> void:
	title_label.text = _text_from_codepoints([0x54c1, 0x7c7b, 0x4e0e, 0x8bbe, 0x5907])
	current_label.text = _text_from_codepoints([0x5df2, 0x6dfb, 0x52a0, 0x54c1, 0x7c7b])
	select_label.text = _text_from_codepoints([0x6dfb, 0x52a0, 0x54c1, 0x7c7b])
	specific_header.text = _text_from_codepoints([0x4e8c, 0x7ea7, 0x54c1, 0x7c7b, 0x5546, 0x54c1])
	add_button.text = _text_from_codepoints([0x6dfb, 0x52a0, 0x54c1, 0x7c7b, 0x548c, 0x5df2, 0x52fe, 0x9009, 0x5546, 0x54c1])
	equipment_title.text = _text_from_codepoints([0x8bbe, 0x5907, 0x8d2d, 0x7f6e])
	parent_dropdown.item_selected.connect(_on_parent_selected)
	child_dropdown.item_selected.connect(_on_child_selected)
	add_button.pressed.connect(_on_add_pressed)
	refresh()

func refresh() -> void:
	_clear_children(category_list)
	_clear_product_checklists()
	_clear_children(equipment_list)
	_parent_names.clear()
	_child_categories.clear()
	_selected_category = null
	parent_dropdown.clear()
	child_dropdown.clear()
	var store := GameManager.store_state
	if store == null:
		status_label.text = "\u8bf7\u5148\u521b\u5efa\u5e76\u6fc0\u6d3b\u5f00\u5e97\u4f01\u5212\u3002"
		parent_dropdown.disabled = true
		child_dropdown.disabled = true
		add_button.disabled = true
		equipment_summary.text = "\u8bbe\u5907\uff1a\u6682\u65e0\u6d3b\u8dc3\u5f00\u5e97\u4f01\u5212\u3002"
		return
	parent_dropdown.disabled = store.is_open
	child_dropdown.disabled = store.is_open
	add_button.disabled = store.is_open
	var parents: Dictionary = {}
	for category in GameManager.all_categories:
		parents[category.parent_category] = true
	for parent_name in parents.keys():
		_parent_names.append(str(parent_name))
	_parent_names.sort()
	parent_dropdown.add_item("\u9009\u62e9\u4e00\u7ea7\u54c1\u7c7b")
	for parent_name in _parent_names:
		parent_dropdown.add_item(parent_name)
	_refresh_category_list(store)
	_refresh_equipment_panel(store)
	_add_universal_products()

func _on_parent_selected(index: int) -> void:
	_clear_product_checklists()
	_selected_category = null
	_child_categories.clear()
	child_dropdown.clear()
	child_dropdown.add_item("\u9009\u62e9\u4e8c\u7ea7\u54c1\u7c7b")
	if index <= 0 or index > _parent_names.size():
		child_dropdown.disabled = true
		add_button.disabled = true
		_add_universal_products()
		return
	var parent_name := _parent_names[index - 1]
	for category in GameManager.all_categories:
		if category.parent_category == parent_name:
			_child_categories.append(category)
	_child_categories.sort_custom(func(a: CategoryData, b: CategoryData): return a.name < b.name)
	for category in _child_categories:
		child_dropdown.add_item(category.name)
	child_dropdown.disabled = GameManager.store_state == null or GameManager.store_state.is_open
	add_button.disabled = true
	_add_universal_products()

func _on_child_selected(index: int) -> void:
	_clear_product_checklists()
	_selected_category = null
	if index <= 0 or index > _child_categories.size():
		_add_universal_products()
		add_button.disabled = true
		return
	_selected_category = _child_categories[index - 1]
	var store := GameManager.store_state
	var existing_slot: StoreCategorySlot = store.get_slot_by_category(_selected_category.id)
	for product in GameManager.all_products:
		if product.category_id == _selected_category.id and not product.is_universal:
			_add_product_checkbox(product, existing_slot, false)
	_add_universal_products(existing_slot)
	add_button.disabled = store.is_open

func _add_universal_products(existing_slot: StoreCategorySlot = null) -> void:
	var header := Label.new()
	header.text = "\u901a\u7528\u5546\u54c1\uff08\u4e0d\u9700\u54c1\u7c7b\u8bbe\u5907\uff09"
	universal_product_list.add_child(header)
	for product in GameManager.all_products:
		if product.is_universal:
			_add_product_checkbox(product, existing_slot, true)

func _add_product_checkbox(product: ProductData, existing_slot: StoreCategorySlot, universal: bool) -> void:
	var checkbox := CheckBox.new()
	var already_added := existing_slot != null and existing_slot.has_product(product.id)
	checkbox.text = "%s\uff08%.0f \u5143\uff09%s" % [product.name, product.average_price, " \u00b7 \u5df2\u6dfb\u52a0" if already_added else ""]
	checkbox.set_meta("product_id", product.id)
	checkbox.button_pressed = already_added
	checkbox.disabled = already_added or _selected_category == null or (GameManager.store_state != null and GameManager.store_state.is_open)
	if universal:
		universal_product_list.add_child(checkbox)
	else:
		specific_product_list.add_child(checkbox)
	_product_checkboxes.append(checkbox)

func _on_add_pressed() -> void:
	var store := GameManager.store_state
	if store == null or _selected_category == null:
		status_label.text = "\u8bf7\u5148\u9009\u62e9\u4e00\u7ea7\u548c\u4e8c\u7ea7\u54c1\u7c7b\u3002"
		return
	if store.is_open:
		status_label.text = "\u95e8\u5e97\u5df2\u5f00\u4e1a\uff0c\u54c1\u7c7b\u914d\u7f6e\u5df2\u9501\u5b9a\u3002"
		return
	var selected_ids: Array[String] = []
	for checkbox in _product_checkboxes:
		if checkbox.button_pressed and not checkbox.disabled:
			selected_ids.append(str(checkbox.get_meta("product_id")))
	if store.has_category(_selected_category.id):
		var added := 0
		for product_id in selected_ids:
			if GameManager.add_product_to_slot(_selected_category.id, product_id):
				added += 1
		status_label.text = "\u5df2\u6dfb\u52a0 %d \u4e2a\u5546\u54c1\u3002" % added if added > 0 else "\u8bf7\u52fe\u9009\u5c1a\u672a\u6dfb\u52a0\u7684\u5546\u54c1\u3002"
	else:
		var result := GameManager.add_category_to_store(_selected_category.id, selected_ids)
		status_label.text = result.reason if not result.success else "\u54c1\u7c7b\u5df2\u6dfb\u52a0\uff0c\u8bf7\u5728\u53f3\u4fa7\u914d\u9f50\u6240\u9700\u8bbe\u5907\u3002"
	refresh()
	category_changed.emit()

func _refresh_category_list(store: Store) -> void:
	for slot in store.category_slots:
		var category := GameManager.get_category(slot.category_id)
		if category == null:
			continue
		var has_category_product := false
		for config in slot.product_configs:
			var configured_product := GameManager.get_product(config.product_id)
			if configured_product != null and not configured_product.is_universal:
				has_category_product = true
				break
		var missing: Array[String] = []
		if has_category_product:
			for equipment_id in category.required_equipment_ids:
				if not store.has_equipment(equipment_id):
					var item := GameManager.get_equipment(equipment_id)
					missing.append(item.name if item != null else equipment_id)
		var state := "\u4ec5\u552e\u901a\u7528\u5546\u54c1" if not has_category_product else ("\u7f3a\u5c11\uff1a" + "\u3001".join(missing) if not missing.is_empty() else "\u8bbe\u5907\u5df2\u914d\u9f50")
		var header := Label.new()
		header.text = "[%s - %s] %s" % [category.parent_category, category.name, state]
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		category_list.add_child(header)
		for config in slot.product_configs:
			var product := GameManager.get_product(config.product_id)
			if product != null:
				var product_label := Label.new()
				product_label.text = "  - %s\uff08%.0f \u5143\uff09" % [product.name, config.get_effective_price(product)]
				category_list.add_child(product_label)
		category_list.add_child(HSeparator.new())

func _refresh_equipment_panel(store: Store) -> void:
	var storefront := GameManager.get_storefront(store.signed_storefront_id)
	var area_text := "\u8bf7\u5148\u7b7e\u7ea6\u95e8\u9762" if storefront == null else "\u5df2\u7528 %.1f / %.1f \u33a1" % [GameManager.get_equipment_used_area(store), storefront.area]
	equipment_summary.text = "\u8bbe\u5907\u5360\u5730\uff1a%s\n\u73b0\u91d1\uff1a%.0f \u5143" % [area_text, GameManager.player_state.cash]
	var required_ids: Dictionary = {}
	for item in GameManager.get_required_equipment_for_current_store():
		required_ids[item.id] = true
	for item in GameManager.all_equipment:
		var row := VBoxContainer.new()
		var owned := store.get_equipment_count(item.id)
		var state := "\u5df2\u62e5\u6709 %d \u53f0" % owned if owned > 0 else ("\u7ecf\u8425\u6240\u9700" if required_ids.has(item.id) else "\u53ef\u9009")
		var label := Label.new()
		var storage_text := ""
		if not item.storage_conditions.is_empty():
			var conditions: Array[String] = []
			for condition in item.storage_conditions:
				conditions.append(_storage_condition_name(condition))
			storage_text = "\n\u4fdd\u5b58\uff1a%s %.0f \u5355\u4f4d\uff0c\u8fc7\u671f\u901f\u5ea6 x%.2f" % ["\u3001".join(conditions), item.storage_capacity, item.spoilage_multiplier]
		label.text = "%s\uff5c%s\n%.0f \u5143 \u00b7 %.1f \u33a1 \u00b7 %.1f \u5143/\u5c0f\u65f6\n\u53ef\u64cd\u4f5c\u4eba\u5458\uff1a%s \u00b7 \u8010\u4e45\u5ea6\uff1a%d%s" % [item.name, state, item.price, item.area, item.hourly_utility_cost, "\u3001".join(item.operator_roles), item.max_durability, storage_text]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var button := Button.new()
		button.text = "\u8d2d\u4e70"
		button.disabled = storefront == null or GameManager.player_state.cash < item.price or (storefront != null and storefront.area - GameManager.get_equipment_used_area(store) < item.area)
		button.pressed.connect(func() -> void:
			var result := GameManager.purchase_equipment(item.id)
			status_label.text = str(result.get("reason", ""))
			refresh()
			category_changed.emit()
		)
		row.add_child(button)
		equipment_list.add_child(row)
		equipment_list.add_child(HSeparator.new())


func _storage_condition_name(condition: String) -> String:
	match condition:
		"refrigerated": return "\u51b7\u85cf"
		"frozen": return "\u51b7\u51bb"
		_: return "\u5e38\u6e29"

func _clear_product_checklists() -> void:
	_clear_children(specific_product_list)
	_clear_children(universal_product_list)
	_product_checkboxes.clear()

func _clear_children(container: Container) -> void:
	for child in container.get_children():
		child.queue_free()

func _text_from_codepoints(codepoints: Array[int]) -> String:
	var result := ""
	for codepoint in codepoints:
		result += char(codepoint)
	return result
