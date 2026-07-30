class_name StoreCategorySlot
extends RefCounted

var category_id: String
var has_key_staff: bool = false
var strategy: String = "standard"
var allocated_area: float = 0.0
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
		"has_key_staff": has_key_staff,
		"strategy": strategy,
		"allocated_area": allocated_area,
		"product_configs": pcs,
	}

static func from_dict(data: Dictionary) -> StoreCategorySlot:
	var s := StoreCategorySlot.new()
	s.category_id = data.get("category_id", "")
	s.has_key_staff = data.get("has_key_staff", false)
	s.strategy = data.get("strategy", "standard")
	s.allocated_area = data.get("allocated_area", 0.0)
	var raw: Array = data.get("product_configs", [])
	for pd in raw:
		s.product_configs.append(StoreProductConfig.from_dict(pd))
	return s
