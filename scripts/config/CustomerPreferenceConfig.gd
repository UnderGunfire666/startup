class_name CustomerPreferenceConfig

## Category defaults keep the first pass data-driven without requiring eighty
## product records. PRODUCT_OVERRIDES may later refine individual products.
const GROUPS := ["student", "office_worker", "worker", "family_household", "high_spend_household"]
const CATEGORY_GROUPS := {
	"breakfast": ["student", "office_worker", "worker"],
	"fried_skewers": ["student", "worker"], "rice_bowls": ["office_worker", "worker", "student"],
	"noodles": ["office_worker", "worker", "student"], "burgers": ["student", "office_worker"],
	"hotpot": ["family_household", "office_worker"], "home_cooking": ["family_household", "worker"],
	"barbecue": ["student", "worker"], "sichuan": ["family_household", "office_worker"],
	"western": ["office_worker", "high_spend_household"], "milk_tea": ["student", "office_worker"],
	"bakery": ["family_household", "office_worker"], "ice_cream": ["student", "family_household"],
	"coffee": ["office_worker", "student"], "chinese_dessert": ["family_household", "student"],
}
const CATEGORY_SPENDING := {
	"western": "high", "coffee": "medium", "hotpot": "medium", "sichuan": "medium",
	"rice_bowls": "medium", "noodles": "low", "breakfast": "low", "fried_skewers": "low",
	"milk_tea": "low", "bakery": "medium", "ice_cream": "low", "barbecue": "medium",
	"home_cooking": "medium", "burgers": "low", "chinese_dessert": "medium",
}
const CATEGORY_HOURS := {
	"breakfast": [Vector2i(5, 10)], "fried_skewers": [Vector2i(11, 14), Vector2i(17, 24)],
	"rice_bowls": [Vector2i(10, 21)], "noodles": [Vector2i(7, 22)], "burgers": [Vector2i(8, 23)],
	"hotpot": [Vector2i(11, 23)], "home_cooking": [Vector2i(10, 22)], "barbecue": [Vector2i(16, 24)],
	"sichuan": [Vector2i(10, 22)], "western": [Vector2i(10, 22)], "milk_tea": [Vector2i(9, 23)],
	"bakery": [Vector2i(7, 21)], "ice_cream": [Vector2i(10, 22)], "coffee": [Vector2i(7, 21)],
	"chinese_dessert": [Vector2i(10, 22)],
}
const PRODUCT_OVERRIDES := {}

static func get_profile(category: CategoryData, product: ProductData) -> Dictionary:
	var category_id := category.id if category != null else ""
	var profile := {
		"preferred_groups": CATEGORY_GROUPS.get(category_id, GROUPS),
		"spending_tier": CATEGORY_SPENDING.get(category_id, "medium"),
		"quality_bias": 0.0,
		"time_ranges": CATEGORY_HOURS.get(category_id, []),
	}
	if product != null and PRODUCT_OVERRIDES.has(product.id):
		for key in PRODUCT_OVERRIDES[product.id]:
			profile[key] = PRODUCT_OVERRIDES[product.id][key]
	return profile

static func get_group_affinity(profile: Dictionary, group_id: String) -> float:
	return 1.0 if group_id in profile.get("preferred_groups", []) else 0.35

static func get_time_affinity(profile: Dictionary, hour: int) -> float:
	var ranges: Array = profile.get("time_ranges", [])
	if ranges.is_empty():
		return 1.0
	for raw_range in ranges:
		if raw_range is Vector2i and hour >= raw_range.x and hour < raw_range.y:
			return 1.0
	return 0.55

static func get_spending_affinity(target_tier: String, block_tier: String) -> float:
	var levels := {"low": 0, "medium": 1, "high": 2}
	var delta: int = abs(int(levels.get(target_tier, 1)) - int(levels.get(block_tier, 1)))
	return 1.0 if delta == 0 else (0.72 if delta == 1 else 0.38)
