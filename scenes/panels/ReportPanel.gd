extends PanelContainer

@onready var label: RichTextLabel = $MarginContainer/RichTextLabel

func _ready() -> void:
	_show_empty_message(
		"尚无结算记录。请在经营控制面板点击「推进到下一时段并结算」。"
	)

func display(results: Array) -> void:
	if results.is_empty():
		_show_empty_message("本时段没有可展示的结算记录。")
		return

	var product_results: Array[SettlementResult] = []
	var overhead_results: Array[SettlementResult] = []

	for r in results:
		if not (r is SettlementResult):
			continue
		if r.is_store_overhead:
			overhead_results.append(r)
		else:
			product_results.append(r)

	var blocks: Array[String] = []

	var grouped := _group_by_category(product_results)
	for category_id in grouped.order:
		blocks.append(_format_category_block(grouped.map[category_id]))

	for r in overhead_results:
		blocks.append(_format_overhead_block(r))

	if blocks.is_empty():
		label.text = "[color=gray]本时段没有有效的结算记录。[/color]"
	else:
		label.text = "\n[color=gray]────────────────────[/color]\n\n".join(blocks)
	label.scroll_to_line(0)


func _show_empty_message(message: String) -> void:
	label.text = "[color=gray]%s[/color]" % message
	label.scroll_to_line(0)


## 按品类分组，保留首次出现的顺序
func _group_by_category(list: Array[SettlementResult]) -> Dictionary:
	var order: Array[String] = []
	var map: Dictionary = {}
	for r in list:
		if not map.has(r.category_id):
			map[r.category_id] = []
			order.append(r.category_id)
		map[r.category_id].append(r)
	return {"order": order, "map": map}


## 生成单个品类的聚合报告（品类汇总 + 各商品明细）
func _format_category_block(items: Array) -> String:
	var first: SettlementResult = items[0]
	var slot_name: String = SettlementConfig.SLOT_NAMES.get(first.slot, first.slot)

	if not first.is_open:
		var text := "[color=orange]⛔ 第%d天 · 「%s」 %s — 本时段不营业[/color]\n" % [
			first.day, first.category_name, slot_name
		]
		text += first.not_open_reason + "\n"
		return text

	var text := "[b]═══ 第%d天 · 「%s」 %s 结算报告 ═══[/b]\n\n" % [
		first.day, first.category_name, slot_name
	]

	var sum_reachable := 0.0
	var sum_visitors := 0
	var sum_theoretical := 0
	var sum_capacity := 0
	var sum_inventory_limit := 0
	var sum_actual := 0
	var sum_lost_no_entry := 0
	var sum_lost_no_conv := 0
	var sum_lost_capacity := 0
	var sum_lost_inventory := 0
	var sum_revenue := 0.0
	var sum_ingredient := 0.0
	var sum_staff := 0.0
	var sum_utility := 0.0
	var sum_waste := 0.0
	var sum_profit := 0.0
	var sum_rep_delta := 0.0
	var sum_stress_delta := 0.0

	for r in items:
		sum_reachable += r.reachable_traffic
		sum_visitors += r.visitors
		sum_theoretical += r.theoretical_orders
		sum_capacity += r.slot_capacity
		sum_inventory_limit += r.inventory_limit
		sum_actual += r.actual_orders
		sum_lost_no_entry += r.lost_no_entry
		sum_lost_no_conv += r.lost_no_conversion
		sum_lost_capacity += r.lost_capacity
		sum_lost_inventory += r.lost_inventory
		sum_revenue += r.revenue
		sum_ingredient += r.ingredient_cost
		sum_staff += r.staff_cost
		sum_utility += r.utility_cost
		sum_waste += r.waste_cost
		sum_profit += r.profit
		sum_rep_delta += r.reputation_delta
		sum_stress_delta += r.stress_delta

	text += "[b]【品类客流汇总】[/b]\n"
	text += "可触达人流：%.0f 人 → 进店 %d 人\n" % [sum_reachable, sum_visitors]
	text += "理论订单：%d 单 | 接待上限：%d 单 | 原材料上限：%d 单\n" % [
		sum_theoretical, sum_capacity, sum_inventory_limit
	]
	text += "[b]实际订单合计：%d 单[/b]\n\n" % sum_actual

	if sum_lost_no_entry + sum_lost_no_conv + sum_lost_capacity + sum_lost_inventory > 0:
		text += "[b]【未成交原因】[/b]\n"
		text += "未进店：%d 人 | 进店未下单：%d 人\n" % [sum_lost_no_entry, sum_lost_no_conv]
		if sum_lost_capacity > 0:
			text += "[color=orange]容量不足损失：%d 单[/color]\n" % sum_lost_capacity
		if sum_lost_inventory > 0:
			text += "[color=red]原材料不足损失：%d 单[/color]\n" % sum_lost_inventory
		text += "\n"

	text += "[b]【品类财务汇总】[/b]\n"
	text += "营业收入：+%.0f 元\n" % sum_revenue
	text += "食材成本：-%.0f 元\n" % sum_ingredient
	text += "员工成本：-%.0f 元\n" % sum_staff
	text += "水电成本：-%.0f 元\n" % sum_utility
	text += "库存损耗：-%.0f 元\n" % sum_waste

	var profit_color := "green" if sum_profit >= 0.0 else "red"
	text += "[color=%s][b]品类利润合计：%+.0f 元[/b][/color]\n\n" % [profit_color, sum_profit]

	text += "[b]【状态变化】[/b]\n"
	var rep_color := "green" if sum_rep_delta >= 0.0 else "red"
	text += "口碑：[color=%s]%+.1f[/color]  压力：%+.1f\n\n" % [
		rep_color, sum_rep_delta, sum_stress_delta
	]

	text += "[b]【商品明细】[/b]\n"
	for r in items:
		var p_color := "green" if r.profit >= 0.0 else "red"
		text += "- %s：订单%d单 | 收入%.0f元 | [color=%s]利润%+.0f元[/color]\n" % [
			r.product_name, r.actual_orders, r.revenue, p_color, r.profit
		]
		if not r.top_negative.is_empty():
			text += "  ⚠ %s\n" % "；".join(r.top_negative.slice(0, 2))

	return text


## 生成门店整体固定成本的精简报告（跳过与商品经营无关的字段）
func _format_overhead_block(r: SettlementResult) -> String:
	var slot_name: String = SettlementConfig.SLOT_NAMES.get(r.slot, r.slot)
	var text := "[b]═══ 第%d天 · %s · %s ═══[/b]\n\n" % [r.day, r.category_name, slot_name]

	text += "租金：-%.0f 元\n" % r.rent_cost
	text += "水电：-%.0f 元\n" % r.utility_cost

	var total := r.rent_cost + r.utility_cost
	text += "[color=red][b]固定成本合计：-%.0f 元[/b][/color]\n" % total

	return text
