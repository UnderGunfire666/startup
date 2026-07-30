extends PanelContainer

signal category_changed

@onready var category_list: VBoxContainer = $VBox/CategoryList
@onready var add_dropdown: OptionButton = $VBox/AddRow/CategoryDropdown
@onready var product_checklist: VBoxContainer = $VBox/ProductCheckList
@onready var add_button: Button = $VBox/AddRow/AddButton
@onready var status_label: Label = $VBox/StatusLabel

var _pending_options: Array[Dictionary] = []
var _product_checkboxes: Array[CheckBox] = []

func _ready() -> void:
	add_dropdown.item_selected.connect(_on_category_dropdown_changed)
	add_button.pressed.connect(_on_add_pressed)
	refresh()

func refresh() -> void:
	_pending_options = GameManager.get_category_options_for_current_store()
	add_dropdown.clear()
	for opt in _pending_options:
		var cat: CategoryData = opt.category
		var label := "%s（面积%.0f㎡/装修%.0f元）" % [
			cat.name, cat.required_area, cat.setup_cost_wan * 10000.0]
		if opt.already_added:
			label += " [已添加，可补充商品]"
		elif not opt.can_add:
			label += " [不可添加：%s]" % opt.reason
		add_dropdown.add_item(label)
	if not _pending_options.is_empty():
		_on_category_dropdown_changed(0)
	_refresh_category_list()

	var is_open := GameManager.store_state.is_open
	add_dropdown.disabled = is_open
	add_button.disabled = is_open


func _on_category_dropdown_changed(idx: int) -> void:
	for cb in _product_checkboxes:
		cb.queue_free()
	_product_checkboxes.clear()
	if idx < 0 or idx >= _pending_options.size():
		return

	var opt := _pending_options[idx]
	var cat: CategoryData = opt.category
	var existing_slot: StoreCategorySlot = null
	if opt.already_added:
		existing_slot = GameManager.store_state.get_slot_by_category(cat.id)

	for p in GameManager.get_products_for_category(cat.id):
		var cb := CheckBox.new()
		var already_in_slot := existing_slot != null and existing_slot.has_product(p.id)
		cb.text = "%s（¥%.0f）%s" % [
			p.name, p.average_price, "[已在售]" if already_in_slot else ""]
		cb.set_meta("product_id", p.id)
		if already_in_slot:
			cb.button_pressed = true
			cb.disabled = true
		if GameManager.store_state.is_open:
			cb.disabled = true
		product_checklist.add_child(cb)
		_product_checkboxes.append(cb)


func _on_add_pressed() -> void:
	if GameManager.store_state.is_open:
		status_label.text = "⚠ 门店已开业，品类与商品配置已锁定"
		return

	var idx := add_dropdown.selected
	if idx < 0 or idx >= _pending_options.size():
		return
	var opt := _pending_options[idx]
	var cat: CategoryData = opt.category

	if opt.already_added:
		_add_products_to_existing_category(cat)
	else:
		_add_new_category(opt)


func _add_new_category(opt: Dictionary) -> void:
	if not opt.can_add:
		status_label.text = "⚠ %s" % opt.reason
		return
	var cat: CategoryData = opt.category
	var selected_ids: Array[String] = []
	for cb in _product_checkboxes:
		if cb.button_pressed:
			selected_ids.append(cb.get_meta("product_id"))
	if selected_ids.is_empty():
		status_label.text = "⚠ 请至少勾选一个商品"
		return
	var result := GameManager.add_category_to_store(cat.id, selected_ids)
	if result.success:
		status_label.text = "✅ 已添加「%s」（%d个商品）" % [cat.name, selected_ids.size()]
		refresh()
		category_changed.emit()
	else:
		status_label.text = "⚠ %s" % result.reason


func _add_products_to_existing_category(cat: CategoryData) -> void:
	var newly_selected_ids: Array[String] = []
	for cb in _product_checkboxes:
		if cb.disabled:
			continue
		if cb.button_pressed:
			newly_selected_ids.append(cb.get_meta("product_id"))

	if newly_selected_ids.is_empty():
		status_label.text = "⚠ 请勾选至少一个尚未添加的新商品"
		return

	var added_count := 0
	for pid in newly_selected_ids:
		if GameManager.add_product_to_slot(cat.id, pid):
			added_count += 1

	if added_count > 0:
		status_label.text = "✅ 已为「%s」补充%d个商品" % [cat.name, added_count]
		refresh()
		category_changed.emit()
	else:
		status_label.text = "⚠ 补充商品失败"


func _refresh_category_list() -> void:
	for child in category_list.get_children():
		child.queue_free()
	for slot in GameManager.store_state.category_slots:
		var cat := GameManager.get_category(slot.category_id)
		if cat == null:
			continue
		category_list.add_child(_build_category_block(cat, slot))


func _build_category_block(cat: CategoryData, slot: StoreCategorySlot) -> Control:
	var block := VBoxContainer.new()

	var header := Label.new()
	header.text = "【%s】面积%.0f㎡" % [cat.name, slot.allocated_area]
	block.add_child(header)

	for pc in slot.product_configs:
		var product := GameManager.get_product(pc.product_id)
		if product == null:
			continue
		block.add_child(_build_product_row(cat, product, pc))

	var remove_cat_btn := Button.new()
	remove_cat_btn.text = "移除整个品类"
	remove_cat_btn.size_flags_horizontal = 0
	if GameManager.store_state.is_open:
		remove_cat_btn.disabled = true
		remove_cat_btn.text = "门店已开业，无法移除"
	remove_cat_btn.pressed.connect(func():
		GameManager.remove_category_from_store(cat.id)
		refresh()
		category_changed.emit()
	)
	block.add_child(remove_cat_btn)
	block.add_child(HSeparator.new())
	return block


func _build_product_row(cat: CategoryData, product: ProductData,
		pc: StoreProductConfig) -> Control:
	var vrow := VBoxContainer.new()

	var name_label := Label.new()
	name_label.text = product.name
	vrow.add_child(name_label)

	var row := HBoxContainer.new()

	var price_edit := SpinBox.new()
	price_edit.custom_minimum_size = Vector2(80, 0)
	price_edit.min_value = 1.0
	price_edit.max_value = 999.0
	price_edit.step = 1.0
	price_edit.value = pc.get_effective_price(product)
	row.add_child(price_edit)

	var margin_label := Label.new()
	margin_label.text = "毛利%.0f%%(建议%.0f%%)" % [
		product.get_actual_margin_rate(pc.get_effective_price(product)) * 100.0,
		product.suggested_margin_rate * 100.0]
	row.add_child(margin_label)

	price_edit.value_changed.connect(func(v):
		GameManager.set_product_price_override(cat.id, product.id, v)
		margin_label.text = "毛利%.0f%%(建议%.0f%%)" % [
			product.get_actual_margin_rate(v) * 100.0,
			product.suggested_margin_rate * 100.0]
		category_changed.emit()
	)

	var remove_btn := Button.new()
	remove_btn.text = "移除商品"
	remove_btn.size_flags_horizontal = 0
	if GameManager.store_state.is_open:
		remove_btn.disabled = true
	remove_btn.pressed.connect(func():
		GameManager.remove_product_from_slot(cat.id, product.id)
		refresh()
		category_changed.emit()
	)
	row.add_child(remove_btn)

	vrow.add_child(row)

	var recipe_label := Label.new()
	var recipe_parts: Array[String] = []
	for r in product.recipe:
		var ing := GameManager.get_ingredient(r.ingredient_id)
		if ing != null:
			recipe_parts.append("%s%.2f%s" % [ing.name, r.quantity, ing.unit])
	recipe_label.text = "配方: " + ", ".join(recipe_parts) if not recipe_parts.is_empty() else "无配方(不限量)"
	vrow.add_child(recipe_label)

	return vrow
