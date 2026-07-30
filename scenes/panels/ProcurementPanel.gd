extends PanelContainer

signal procurement_completed

@onready var cash_label: Label = $MarginContainer/VBox/CashLabel
@onready var ingredient_list: VBoxContainer = $MarginContainer/VBox/IngredientScroll/IngredientList
@onready var total_label: Label = $MarginContainer/VBox/TotalLabel
@onready var purchase_button: Button = $MarginContainer/VBox/PurchaseButton
@onready var status_label: Label = $MarginContainer/VBox/StatusLabel

var _quantity_inputs: Dictionary = {}
var _line_totals: Dictionary = {}

func _ready() -> void:
	purchase_button.pressed.connect(_on_purchase_pressed)
	refresh()

func refresh() -> void:
	_clear_ingredient_rows()
	_quantity_inputs.clear()
	_line_totals.clear()

	cash_label.text = "当前现金：¥%.0f" % GameManager.store_state.cash
	status_label.text = ""

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

	var stock := GameManager.store_state.get_ingredient_stock(ingredient.id)
	var stock_label := Label.new()
	stock_label.text = "库存 %.2f" % stock
	stock_label.custom_minimum_size = Vector2(95, 0)
	top_row.add_child(stock_label)

	var avg_cost := GameManager.store_state.get_ingredient_avg_cost(ingredient.id)
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

	if total > GameManager.store_state.cash:
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
