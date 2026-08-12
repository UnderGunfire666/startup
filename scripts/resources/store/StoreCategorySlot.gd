class_name StoreCategorySlot
extends RefCounted

var category_id: String
var has_key_staff: bool = false

## 玩家为这个店铺实例配置的实际营业时间段，多段，覆盖0-23的任意小时区间。
var open_hour_ranges: Array[Vector2i] = []

var allocated_area: float = 0.0
var product_configs: Array[StoreProductConfig] = []

func is_open_at_hour(hour: int) -> bool:
	for r in open_hour_ranges:
		if hour >= r.x and hour < r.y:
			return true
	return false

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
	var ranges: Array = []
	for r in open_hour_ranges:
		ranges.append([r.x, r.y])
	return {
		"category_id": category_id,
		"has_key_staff": has_key_staff,
		"open_hour_ranges": ranges,
		"allocated_area": allocated_area,
		"product_configs": pcs,
	}

static func from_dict(data: Dictionary) -> StoreCategorySlot:
	var s := StoreCategorySlot.new()
	s.category_id = data.get("category_id", "")
	s.has_key_staff = data.get("has_key_staff", false)
	var raw_ranges: Array = data.get("open_hour_ranges", [])
	var typed_ranges: Array[Vector2i] = []
	for r in raw_ranges:
		if r is Array and r.size() >= 2:
			typed_ranges.append(Vector2i(int(r[0]), int(r[1])))
	s.open_hour_ranges = typed_ranges
	s.allocated_area = data.get("allocated_area", 0.0)
	var raw: Array = data.get("product_configs", [])
	for pd in raw:
		s.product_configs.append(StoreProductConfig.from_dict(pd))
	return s
