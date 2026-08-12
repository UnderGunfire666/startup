class_name StoreProductConfig
extends RefCounted

var product_id: String
var custom_price: float = -1.0
var inventory_units: int = 50

func get_effective_price(product_template: ProductData) -> float:
	if custom_price >= 0.0:
		return custom_price
	return product_template.average_price

func to_dict() -> Dictionary:
	return {
		"product_id": product_id,
		"custom_price": custom_price,
		"inventory_units": inventory_units,
	}

static func from_dict(data: Dictionary) -> StoreProductConfig:
	var c := StoreProductConfig.new()
	c.product_id = data.get("product_id", "")
	c.custom_price = data.get("custom_price", -1.0)
	c.inventory_units = data.get("inventory_units", 50)
	return c
