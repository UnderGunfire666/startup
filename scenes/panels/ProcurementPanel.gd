extends PanelContainer

signal procurement_completed

@onready var cash_label: Label = $MarginContainer/VBox/CashLabel
@onready var ingredient_list: VBoxContainer = $MarginContainer/VBox/IngredientScroll/IngredientList
@onready var total_label: Label = $MarginContainer/VBox/TotalLabel
@onready var purchase_button: Button = $MarginContainer/VBox/PurchaseButton
@onready var status_label: Label = $MarginContainer/VBox/StatusLabel
@onready var inventory_forecast_label: Label = $MarginContainer/VBox/InventoryForecastLabel
@onready var purchase_history_label: Label = $MarginContainer/VBox/PurchaseHistoryLabel

var _quantity_inputs: Dictionary = {}
var _line_totals: Dictionary = {}

func _ready() -> void:
	purchase_button.pressed.connect(_on_purchase_pressed)
	refresh()

func refresh() -> void:
	_clear_ingredient_rows()
	_quantity_inputs.clear()
	_line_totals.clear()

	var player := GameManager.player_state
	cash_label.text = "当前现金：¥%.0f" % player.cash
	status_label.text = ""
	inventory_forecast_label.text = ""
	purchase_history_label.text = ""

	if not player.is_character_created:
		status_label.text = "请先创建角色。"
		purchase_button.disabled = true
		_update_total_label()
		return

	if GameManager.store_state == null:
		purchase_history_label.text = ""
		status_label.text = "请先在「我的店铺」创建开店企划。"
		purchase_button.disabled = true
		_update_total_label()
		return
	if GameManager.store_state.signed_storefront_id.is_empty() or GameManager.store_state.category_slots.is_empty():
		_refresh_purchase_history(GameManager.store_state)
		status_label.text = "请先签约门面并确定至少一个品类后再采购。"
		purchase_button.disabled = true
		_update_total_label()
		return

	var ingredients := GameManager.get_ingredients_in_use()
	if ingredients.is_empty():
		var empty_label := Label.new()
		empty_label.text = "尚未添加有配方的商品。请先在品类管理中添加品类和商品。"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ingredient_list.add_child(empty_label)
		purchase_button.disabled = true
		_update_total_label()
		return

	purchase_button.disabled = false
	_refresh_purchase_history(GameManager.store_state)
	var estimated_orders := GameManager.get_estimated_orders_supported(GameManager.store_state)
	inventory_forecast_label.text = "\u5e93\u5b58\u9884\u4f30\uff1a\u6309\u5f53\u524d\u5546\u54c1\u5747\u8861\u9500\u552e\u53ef\u652f\u6491\u7ea6 %d \u5355\uff08\u5df2\u8ba1\u5165\u9ed8\u8ba4\u5236\u4f5c\u635f\u8017\uff09" % estimated_orders
	for ingredient in ingredients:
		ingredient_list.add_child(_build_ingredient_row(ingredient))
	_update_total_label()

func _clear_ingredient_rows() -> void:
	for child in ingredient_list.get_children():
		child.queue_free()

func _build_ingredient_row(ingredient: IngredientData) -> Control:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(top_row)
	var name_label := Label.new()
	name_label.text = "%s（%s）" % [ingredient.name, ingredient.unit]
	name_label.custom_minimum_size = Vector2(105, 0)
	top_row.add_child(name_label)

	var store := GameManager.store_state
	var stock := store.get_ingredient_stock(ingredient.id)
	var stock_label := Label.new()
	stock_label.text = "库存 %.2f" % stock
	stock_label.custom_minimum_size = Vector2(95, 0)
	top_row.add_child(stock_label)

	var spoilage_ratio := float(GameManager.get_ingredient_spoilage_ratios(store).get(ingredient.id, 0.0))
	var storage_label := Label.new()
	storage_label.text = "\u4fdd\u5b58\uff1a%s | \u6bcf\u65f6\u6bb5\u8fc7\u671f %.2f%%" % [_storage_condition_name(ingredient.storage_condition), spoilage_ratio * 100.0]
	storage_label.custom_minimum_size = Vector2(180, 0)
	top_row.add_child(storage_label)

	var avg_cost := store.get_ingredient_avg_cost(ingredient.id)
	var avg_cost_text := "暂无均价"
	if avg_cost > 0.0:
		avg_cost_text = "均价 ¥%.2f" % avg_cost
	var avg_cost_label := Label.new()
	avg_cost_label.text = avg_cost_text
	avg_cost_label.custom_minimum_size = Vector2(95, 0)
	top_row.add_child(avg_cost_label)

	var purchase_price := GameManager.get_ingredient_purchase_price(ingredient.id)
	var purchase_price_label := Label.new()
	purchase_price_label.text = "进价 ¥%.2f" % purchase_price
	purchase_price_label.custom_minimum_size = Vector2(100, 0)
	top_row.add_child(purchase_price_label)

	var bottom_row := HBoxContainer.new()
	bottom_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_child(bottom_row)
	var quantity_label := Label.new()
	quantity_label.text = "采购数量"
	quantity_label.custom_minimum_size = Vector2(105, 0)
	bottom_row.add_child(quantity_label)
	var quantity_input := SpinBox.new()
	quantity_input.custom_minimum_size = Vector2(120, 0)
	quantity_input.min_value = 0.0
	quantity_input.max_value = 999.0
	quantity_input.step = _get_purchase_step(ingredient.unit)
	quantity_input.allow_greater = true
	quantity_input.value = 0.0
	bottom_row.add_child(quantity_input)
	var line_total_label := Label.new()
	line_total_label.text = "小计 ¥0"
	line_total_label.custom_minimum_size = Vector2(150, 0)
	bottom_row.add_child(line_total_label)
	_quantity_inputs[ingredient.id] = quantity_input
	_line_totals[ingredient.id] = line_total_label
	quantity_input.value_changed.connect(func(_value: float) -> void:
		_update_line_total(ingredient.id)
		_update_total_label()
	)
	block.add_child(HSeparator.new())
	return block

func _get_purchase_step(unit: String) -> float:
	if unit == "个" or unit == "份":
		return 1.0
	return 0.5


func _storage_condition_name(condition: String) -> String:
	match condition:
		"refrigerated": return "\u51b7\u85cf"
		"frozen": return "\u51b7\u51bb"
		_: return "\u5e38\u6e29"


func _refresh_purchase_history(store: Store) -> void:
	if store == null or store.purchase_history.is_empty():
		purchase_history_label.text = "\u8fd1\u671f\u91c7\u8d2d\u8bb0\u5f55\uff1a\u6682\u65e0"
		return
	var lines: Array[String] = ["\u8fd1\u671f\u91c7\u8d2d\u8bb0\u5f55\uff1a"]
	var start := maxi(0, store.purchase_history.size() - 5)
	for index in range(store.purchase_history.size() - 1, start - 1, -1):
		var record: Dictionary = store.purchase_history[index]
		var item_parts: Array[String] = []
		var items: Dictionary = record.get("items", {})
		for ingredient_id in items.keys():
			var ingredient := GameManager.get_ingredient(str(ingredient_id))
			var name := ingredient.name if ingredient != null else str(ingredient_id)
			item_parts.append("%s %.2f" % [name, float(items[ingredient_id])])
		lines.append("\u7b2c%d\u5929 %02d:%02d  |  %s  |  %.2f\u5143" % [int(record.get("day", 1)), int(record.get("hour", 0)), int(record.get("minute", 0)), "\u3001".join(item_parts), float(record.get("total_cost", 0.0))])
	purchase_history_label.text = "\n".join(lines)

func _update_line_total(ingredient_id: String) -> void:
	if not _quantity_inputs.has(ingredient_id):
		return
	var quantity: float = _quantity_inputs[ingredient_id].value
	var price: float = GameManager.get_ingredient_purchase_price(ingredient_id)
	var line_total: float = quantity * price
	if _line_totals.has(ingredient_id):
		_line_totals[ingredient_id].text = "小计 ¥%.2f" % line_total

func _build_cart() -> Dictionary:
	var cart: Dictionary = {}
	for ingredient_id in _quantity_inputs:
		var quantity_input: SpinBox = _quantity_inputs[ingredient_id]
		var quantity: float = quantity_input.value
		if quantity > 0.0:
			cart[ingredient_id] = quantity
	return cart

func _update_total_label() -> void:
	var cart := _build_cart()
	var total: float = GameManager.calculate_purchase_total(cart)
	total_label.text = "本次采购合计：¥%.2f" % total
	if total > GameManager.player_state.cash:
		total_label.text += "  （现金不足）"

func _on_purchase_pressed() -> void:
	var cart := _build_cart()
	if cart.is_empty():
		status_label.text = "⚠ 请至少输入一种原材料的采购数量"
		return
	var result: Dictionary = GameManager.purchase_ingredients(cart)
	if not result.success:
		status_label.text = "⚠ %s" % result.reason
		return
	status_label.text = "✅ 采购完成，已支付 ¥%.2f" % float(result.total_cost)
	procurement_completed.emit()
	refresh()
