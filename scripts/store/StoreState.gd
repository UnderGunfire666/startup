class_name StoreState
extends RefCounted

# ── 配置 ────────────────────────────────────────────────
var selected_region_id: String = ""
var selected_storefront_id: String = ""
var selected_category_id: String = ""
var selected_primary_product_id: String = ""
## 预留接口，本轮不使用
var selected_product_ids: Array[String] = []
var has_key_staff: bool = false
var strategy: String = "standard"           # standard/extend/shorten
var owner_present: bool = false             # 亲自坐镇

# ── 运行状态 ─────────────────────────────────────────────
var cash: float = SettlementConfig.INITIAL_CASH
var inventory_units: int = SettlementConfig.INITIAL_INVENTORY
var inventory_capacity: int = 200
var reputation: float = SettlementConfig.INITIAL_REPUTATION
var stress: float = SettlementConfig.INITIAL_STRESS

# ── 时间 ─────────────────────────────────────────────────
var current_day: int = 1
var current_slot_index: int = 0             # 0=dawn,1=noon,2=night

# ── 统计（MVP成功判定用） ────────────────────────────────
var total_revenue: float = 0.0
var total_cost: float = 0.0
var total_orders: int = 0
var total_lost_inventory: int = 0
var total_lost_capacity: int = 0
var missing_key_staff_penalty_count: int = 0
var per_slot_stats: Dictionary = {}         # key="day_slot" → 结算摘要

# ── 历史记录 ─────────────────────────────────────────────
var daily_history: Array[Dictionary] = []  # 每时段结算的 summary dict

func get_current_slot() -> String:
	return SettlementConfig.SLOT_ORDER[current_slot_index]

func advance_slot() -> void:
	current_slot_index += 1
	if current_slot_index >= SettlementConfig.SLOT_ORDER.size():
		current_slot_index = 0
		current_day += 1
		stress = maxf(0.0, stress - SettlementConfig.STRESS_REST_PER_DAY)

func apply_settlement(result: SettlementResult) -> void:
	if not result.is_open:
		return
	cash += result.profit
	inventory_units -= result.inventory_used
	inventory_units = maxi(0, inventory_units)
	reputation = clampf(reputation + result.reputation_delta, 0.0, 100.0)
	stress = clampf(stress + result.stress_delta, 0.0, 100.0)

	total_revenue += result.revenue
	total_cost += result.ingredient_cost + result.staff_cost \
				+ result.rent_cost + result.waste_cost
	total_orders += result.actual_orders
	total_lost_inventory += result.lost_inventory
	total_lost_capacity += result.lost_capacity
	if not has_key_staff and result.missing_key_staff_active:
		missing_key_staff_penalty_count += 1

	daily_history.append(result.to_summary_dict())
	if daily_history.size() > 200:
		daily_history.pop_front()

func reset_to_defaults() -> void:
	cash = SettlementConfig.INITIAL_CASH
	inventory_units = SettlementConfig.INITIAL_INVENTORY
	inventory_capacity = 200
	reputation = SettlementConfig.INITIAL_REPUTATION
	stress = SettlementConfig.INITIAL_STRESS
	current_day = 1
	current_slot_index = 0
	total_revenue = 0.0; total_cost = 0.0; total_orders = 0
	total_lost_inventory = 0; total_lost_capacity = 0
	missing_key_staff_penalty_count = 0
	daily_history.clear()
