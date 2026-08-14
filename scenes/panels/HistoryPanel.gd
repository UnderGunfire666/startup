extends PanelContainer

@onready var label: RichTextLabel = $MarginContainer/RichTextLabel


func _ready() -> void:
	refresh()


func refresh(_settlement_history: Array = []) -> void:
	var store: Store = GameManager.get_active_store()
	if store == null or store.daily_history.is_empty():
		label.text = "[color=gray]\u6682\u65e0\u8425\u4e1a\u5386\u53f2\u3002\u7ed3\u7b97\u540e\u8fd9\u91cc\u4f1a\u6309\u5929\u5c55\u793a\u5ba2\u6d41\u3001\u6392\u961f\u3001\u5e93\u5b58\u4e0e\u635f\u76ca\u3002[/color]"
		return

	var by_day: Dictionary = {}
	for entry in store.daily_history:
		var day := int(entry.get("day", 0))
		if not by_day.has(day):
			by_day[day] = _new_day_summary()
		_accumulate(by_day[day], entry)

	var days: Array = by_day.keys()
	days.sort()
	days.reverse()
	var blocks: Array[String] = []
	for day in days:
		blocks.append(_format_day(int(day), by_day[day]))
	label.text = "\n[color=gray]------------------------------------------------[/color]\n\n".join(blocks)
	label.scroll_to_line(0)


func _new_day_summary() -> Dictionary:
	return {
		"revenue": 0.0, "cost": 0.0, "profit": 0.0, "orders": 0,
		"visitors": 0, "intended_orders": 0, "lost_entry": 0, "lost_conversion": 0,
		"lost_queue": 0, "lost_inventory": 0, "wait_total": 0.0,
		"wait_max": 0.0, "service_total": 0.0, "service_count": 0,
		"open_slots": 0, "closed_slots": 0, "preparation_waste": {}, "spoilage": {},
	}


func _accumulate(total: Dictionary, entry: Dictionary) -> void:
	total.revenue += float(entry.get("revenue", 0.0))
	total.cost += float(entry.get("ingredient_cost", 0.0)) + float(entry.get("staff_cost", 0.0)) + float(entry.get("rent_cost", 0.0)) + float(entry.get("utility_cost", 0.0))
	total.profit += float(entry.get("profit", 0.0))
	_accumulate_ingredients(total.preparation_waste, entry.get("preparation_waste_ingredients", {}))
	_accumulate_ingredients(total.spoilage, entry.get("spoilage_ingredients", {}))
	if bool(entry.get("is_store_overhead", false)):
		return
	total.orders += int(entry.get("actual_orders", 0))
	total.visitors += int(entry.get("visitors", 0))
	total.intended_orders += int(entry.get("theoretical_orders", 0))
	total.lost_entry += int(entry.get("lost_no_entry", 0))
	total.lost_conversion += int(entry.get("lost_no_conversion", 0))
	total.lost_queue += int(entry.get("lost_capacity", 0))
	total.lost_inventory += int(entry.get("lost_inventory", 0))
	var orders := int(entry.get("actual_orders", 0))
	total.wait_total += float(entry.get("average_queue_wait_seconds", 0.0)) * orders
	total.wait_max = maxf(float(total.wait_max), float(entry.get("max_queue_wait_seconds", 0.0)))
	if float(entry.get("service_time_seconds", 0.0)) > 0.0:
		total.service_total += float(entry.get("service_time_seconds", 0.0))
		total.service_count += 1
	if bool(entry.get("is_open", false)):
		total.open_slots += 1
	else:
		total.closed_slots += 1


func _accumulate_ingredients(total: Dictionary, source: Dictionary) -> void:
	for ingredient_id in source:
		total[ingredient_id] = float(total.get(ingredient_id, 0.0)) + float(source[ingredient_id])


func _format_day(day: int, total: Dictionary) -> String:
	var conversion := float(total.orders) / float(total.visitors) if int(total.visitors) > 0 else 0.0
	var avg_wait := float(total.wait_total) / float(total.orders) if int(total.orders) > 0 else 0.0
	var avg_service := float(total.service_total) / float(total.service_count) if int(total.service_count) > 0 else 0.0
	var lines: Array[String] = []
	lines.append("[b]\u7b2c %d \u5929\u8425\u4e1a\u603b\u89c8[/b]" % day)
	lines.append("\u8425\u6536\uff1a%.2f  |  \u603b\u6210\u672c\uff1a%.2f  |  [b]\u5229\u6da6\uff1a%.2f[/b]  |  \u6210\u4ea4\uff1a%d \u5355" % [total.revenue, total.cost, total.profit, total.orders])
	lines.append("\u5ba2\u6d41\uff1a\u8fdb\u5e97 %d -> \u60f3\u4e0b\u5355 %d -> \u6210\u4ea4 %d\uff08\u5b9e\u9645\u8f6c\u5316 %.1f%%\uff09" % [total.visitors, total.intended_orders, total.orders, conversion * 100.0])
	lines.append("\u6d41\u5931\u539f\u56e0\uff1a\u672a\u8fdb\u5e97 %d\uff0c\u8fdb\u5e97\u540e\u672a\u4e0b\u5355 %d\uff0c\u6392\u961f\u8fc7\u4e45 %d\uff0c\u539f\u6599\u4e0d\u8db3 %d" % [total.lost_entry, total.lost_conversion, total.lost_queue, total.lost_inventory])
	lines.append("\u539f\u6599\u635f\u8017\uff1a\u5236\u4f5c %s  |  \u81ea\u7136\u8fc7\u671f %s" % [_format_ingredients(total.preparation_waste), _format_ingredients(total.spoilage)])
	lines.append("\u670d\u52a1\uff1a\u5e73\u5747\u51fa\u9910 %s\uff0c\u5e73\u5747\u7b49\u5f85 %s\uff0c\u6700\u957f\u7b49\u5f85 %s  |  \u6709\u6548\u8425\u4e1a\u8bb0\u5f55 %d \u6761" % [_format_seconds(avg_service), _format_seconds(avg_wait), _format_seconds(float(total.wait_max)), total.open_slots])
	return "\n".join(lines)


func _format_seconds(value: float) -> String:
	if value < 60.0:
		return "%.0f\u79d2" % value
	return "%.1f\u5206\u949f" % (value / 60.0)


func _format_ingredients(items: Dictionary) -> String:
	if items.is_empty():
		return "\u65e0"
	var parts: Array[String] = []
	for ingredient_id in items:
		var ingredient := GameManager.get_ingredient(str(ingredient_id))
		var name := ingredient.name if ingredient != null else str(ingredient_id)
		parts.append("%s %.2f" % [name, float(items[ingredient_id])])
	return "\u3001".join(parts)
