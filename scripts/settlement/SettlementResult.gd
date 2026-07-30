class_name SettlementResult
extends RefCounted

var slot: String = ""
var day: int = 0
var is_open: bool = true
var not_open_reason: String = ""
var missing_key_staff_active: bool = false

## 标记该记录是否为门店级固定成本合成记录（非具体商品结算）
var is_store_overhead: bool = false

# ── 归属标识（新增，供多品类门店的报告区分显示） ──────────
var category_id: String = ""
var category_name: String = ""
var product_id: String = ""
var product_name: String = ""

# ── 漏斗 ────────────────────────────────────────────────
var slot_foot_traffic: float = 0.0
var reachable_traffic: float = 0.0
var entry_rate: float = 0.0
var visitors: int = 0
var conversion_rate: float = 0.0
var theoretical_orders: int = 0
var slot_capacity: int = 0
var inventory_limit: int = 0
var actual_orders: int = 0

# ── 未成交分项 ───────────────────────────────────────────
var lost_no_entry: int = 0
var lost_no_conversion: int = 0
var lost_capacity: int = 0
var lost_inventory: int = 0

# ── 财务 ─────────────────────────────────────────────────
var revenue: float = 0.0
var ingredient_cost: float = 0.0
var staff_cost: float = 0.0
var rent_cost: float = 0.0
var utility_cost: float = 0.0
var waste_cost: float = 0.0
var profit: float = 0.0

# ── 状态变化 ─────────────────────────────────────────────
var reputation_delta: float = 0.0
var stress_delta: float = 0.0
var inventory_used: int = 0

# ── 修正来源日志 ─────────────────────────────────────────
## 每项：{label:String, value:float, is_positive:bool, phase:String}
var modifiers: Array[Dictionary] = []
var top_positive: Array[String] = []
var top_negative: Array[String] = []

func to_summary_dict() -> Dictionary:
	return {
		"day": day, "slot": slot,
		"category_id": category_id, "category_name": category_name,
		"product_id": product_id, "product_name": product_name,
		"is_open": is_open,
		"is_store_overhead": is_store_overhead,
		"actual_orders": actual_orders,
		"revenue": revenue,
		"ingredient_cost": ingredient_cost,
		"staff_cost": staff_cost,
		"rent_cost": rent_cost,
		"utility_cost": utility_cost,
		"waste_cost": waste_cost,
		"profit": profit,
		"reputation_delta": reputation_delta,
		"stress_delta": stress_delta,
		"lost_inventory": lost_inventory,
		"lost_capacity": lost_capacity,
		"entry_rate": entry_rate,
		"conversion_rate": conversion_rate,
		"top_positive": top_positive.duplicate(),
		"top_negative": top_negative.duplicate()
	}
