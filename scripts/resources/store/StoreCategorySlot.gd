class_name StoreCategorySlot
extends RefCounted

var category_id: String

## 玩家为这个店铺实例配置的实际营业时间段，多段，覆盖0-23的任意小时区间。
var product_configs: Array[StoreProductConfig] = []

func has_product(product_id: String) -> bool:
	for pc in product_configs:
		if pc.product_id == product_id:
			return true
	return false

func get_product_config(product_id: String) -> StoreProductConfig:
	for pc in product_configs:
		if pc.product_id == product_id:
			return pc
	return null

func get_total_inventory() -> int:
	var total := 0
	for pc in product_configs:
		total += pc.inventory_units
	return total

func to_dict() -> Dictionary:
	var pcs: Array = []
	for pc in product_configs:
		pcs.append(pc.to_dict())
	return {
		"category_id": category_id,
		"product_configs": pcs,
	}

static func from_dict(data: Dictionary) -> StoreCategorySlot:
	var s := StoreCategorySlot.new()
	s.category_id = data.get("category_id", "")
	var raw: Array = data.get("product_configs", [])
	for pd in raw:
		s.product_configs.append(StoreProductConfig.from_dict(pd))
	return s
