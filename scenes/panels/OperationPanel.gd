extends PanelContainer

signal settlement_done(results: Array)
signal day_ended(day: int, summary: Dictionary)
signal store_opened

@onready var opening_checklist: VBoxContainer = $VBox/OpeningPrepBox/OpeningChecklist
@onready var open_store_button: Button = $VBox/OpeningPrepBox/OpenStoreButton
@onready var opening_status_label: Label = $VBox/OpeningPrepBox/OpeningStatusLabel
@onready var opening_prep_box: VBoxContainer = $VBox/OpeningPrepBox
@onready var business_start_option: OptionButton = $VBox/OpeningPrepBox/BusinessHoursRow/BusinessStartOption
@onready var business_end_option: OptionButton = $VBox/OpeningPrepBox/BusinessHoursRow/BusinessEndOption
@onready var save_business_hours_button: Button = $VBox/OpeningPrepBox/BusinessHoursRow/SaveBusinessHoursButton
@onready var business_hours_label: Label = $VBox/OpeningPrepBox/BusinessHoursRow/BusinessHoursLabel
@onready var open_business_button: Button = $VBox/BusinessControlRow/OpenBusinessButton
@onready var close_business_button: Button = $VBox/BusinessControlRow/CloseBusinessButton
@onready var open_status_label: Label = $VBox/OpenStatusLabel
@onready var live_metrics_label: Label = $VBox/LiveMetricsLabel
@onready var cash_label: Label = $VBox/StatsGrid/CashLabel
@onready var inventory_label: Label = $VBox/StatsGrid/InventoryLabel
@onready var reputation_label: Label = $VBox/StatsGrid/ReputationLabel
@onready var stress_label: Label = $VBox/StatsGrid/StressLabel
@onready var owner_present_check: CheckBox = $VBox/OwnerRow/OwnerPresentCheck
@onready var customer_feed: VBoxContainer = $VBox/CustomerFeedScroll/CustomerFeed

const CUSTOMER_FEED_MAX_LINES: int = 20

func _ready() -> void:
	for hour in range(25):
		business_start_option.add_item("%02d:00" % hour)
		business_end_option.add_item("%02d:00" % hour)
	business_hours_label.text = "\u8425\u4e1a\u65f6\u95f4"
	save_business_hours_button.text = "\u4fdd\u5b58\u8425\u4e1a\u65f6\u95f4"
	open_business_button.text = "\u5f00\u95e8\u8425\u4e1a"
	close_business_button.text = "\u5173\u95e8\u6b47\u4e1a"
	open_store_button.pressed.connect(_on_open_store_pressed)
	save_business_hours_button.pressed.connect(_on_save_business_hours_pressed)
	open_business_button.pressed.connect(_on_open_business_pressed)
	close_business_button.pressed.connect(_on_close_business_pressed)
	owner_present_check.toggled.connect(_on_owner_present_toggled)
	TimeManager.slot_completed.connect(_on_slot_completed)
	TimeManager.day_completed.connect(_on_day_completed)
	TimeManager.clock_updated.connect(_on_clock_updated)
	TimeManager.customer_event.connect(_on_customer_event)
	refresh_display()

func _on_owner_present_toggled(pressed: bool) -> void:
	var store := GameManager.store_state
	if store == null:
		return
	GameManager.set_player_store_presence(store, pressed)
	_append_business_log("\u73a9\u5bb6" + ("\u5230\u5e97\u5c97\u4f4d" if pressed else "\u79bb\u5e97\u4e0b\u73ed"))
	_refresh_live_metrics(store)

func _on_open_store_pressed() -> void:
	var result := GameManager.open_store()
	opening_status_label.text = ("✅ " if result.success else "⚠ ") + result.reason
	refresh_display()
	if result.success:
		store_opened.emit()

func _on_save_business_hours_pressed() -> void:
	var result := GameManager.set_store_business_hours([
		Vector2i(business_start_option.selected, business_end_option.selected)
	])
	opening_status_label.text = str(result.get("reason", ""))
	refresh_display()

func _on_open_business_pressed() -> void:
	var result := GameManager.open_business()
	open_status_label.text = str(result.get("reason", ""))
	if bool(result.get("success", false)):
		_append_business_log("\u5f00\u95e8\u8425\u4e1a")
	refresh_display()

func _on_close_business_pressed() -> void:
	var result := GameManager.close_business()
	open_status_label.text = str(result.get("reason", ""))
	if bool(result.get("success", false)):
		_append_business_log("\u5173\u95e8\u6b47\u4e1a")
	refresh_display()

func _on_customer_event(product_name: String, purchased: bool, reason: String, event_game_seconds: float) -> void:
	var event_line := Label.new()
	var time_text := _format_event_time(event_game_seconds)
	event_line.text = "%s  %s" % [time_text, (product_name + "\uff1a\u6210\u4ea4\u4e00\u5355\uff08\u5b8c\u6210\uff09") if purchased else (product_name + "\uff1a" + reason)]
	customer_feed.add_child(event_line)
	while customer_feed.get_child_count() > CUSTOMER_FEED_MAX_LINES:
		var oldest_event := customer_feed.get_child(0)
		customer_feed.remove_child(oldest_event)
		oldest_event.queue_free()
	return
	var line := Label.new()
	if purchased:
		line.text = "🟢 %s：成交一单" % product_name
	else:
		line.text = "⚪ %s：%s" % [product_name, reason]
	customer_feed.add_child(line)
	while customer_feed.get_child_count() > CUSTOMER_FEED_MAX_LINES:
		var oldest := customer_feed.get_child(0)
		customer_feed.remove_child(oldest)
		oldest.queue_free()

func _on_slot_completed(_day: int, _slot: String, results: Array) -> void:
	if results.is_empty() and GameManager.last_settlement_error != "":
		open_status_label.text = "⚠ 结算失败：%s" % GameManager.last_settlement_error
		settlement_done.emit([])
		return
	refresh_display()
	settlement_done.emit(results)

func _on_day_completed(day: int, summary: Dictionary) -> void:
	day_ended.emit(day, summary)


func _on_clock_updated(_hour: int, _minute: int, _second: int, _period_label: String) -> void:
	_refresh_live_metrics(GameManager.store_state)

func refresh_display() -> void:
	var state := GameManager.store_state
	var has_character: bool = GameManager.player_state.is_character_created
	var has_store: bool = state != null
	if not has_character:
		open_status_label.text = "⚠ 请先创建角色"
		cash_label.text = ""
		inventory_label.text = ""
		reputation_label.text = ""
		stress_label.text = ""
		opening_prep_box.visible = false
		owner_present_check.button_pressed = false
		return

	if not has_store:
		open_status_label.text = "尚未创建开店企划，请前往「我的店铺」创建"
		cash_label.text = "现金：%.0f 元" % GameManager.player_state.cash
		inventory_label.text = ""
		reputation_label.text = ""
		stress_label.text = "压力：%.1f / 100" % GameManager.player_state.stress
		opening_prep_box.visible = false
		owner_present_check.button_pressed = false
		return

	_refresh_opening_prep()
	owner_present_check.button_pressed = (GameManager.player_state.supervising_store_id == state.id)
	open_business_button.visible = state.is_open
	close_business_button.visible = state.is_open
	open_business_button.disabled = state.is_business_open
	close_business_button.disabled = not state.is_business_open
	call_deferred("_refresh_business_status", state)
	call_deferred("_refresh_live_metrics", state)

	if state.category_slots.is_empty():
		open_status_label.text = "⚠ 门店尚未添加任何品类（请前往品类管理面板添加）"
	else:
		var open_names: Array[String] = []
		var closed_names: Array[String] = []
		for slot in state.category_slots:
			var cat := GameManager.get_category(slot.category_id)
			if cat == null:
				continue
			if state.is_business_open:
				open_names.append(cat.name)
			else:
				closed_names.append(cat.name)
		var text := ""
		if not open_names.is_empty():
			text += "✅ 营业：%s" % ", ".join(open_names)
		if not closed_names.is_empty():
			if text != "":
				text += "  "
			text += "⛔ 不营业：%s" % ", ".join(closed_names)
		open_status_label.text = text

	cash_label.text = "现金：%.0f 元" % GameManager.player_state.cash
	inventory_label.text = _get_ingredient_inventory_summary(state)
	reputation_label.text = "口碑：%.1f / 100" % state.reputation
	stress_label.text = "压力：%.1f / 100" % GameManager.player_state.stress


func _get_ingredient_inventory_summary(store: Store) -> String:
	var parts: Array[String] = []
	for ingredient in GameManager.get_ingredients_in_use():
		var amount := store.get_ingredient_stock(ingredient.id)
		parts.append("%s %.1f%s" % [ingredient.name, amount, ingredient.unit])
	return "原材料：" + ("、".join(parts) if not parts.is_empty() else "尚未配置配方")

func _refresh_business_status(store: Store) -> void:
	if store == null:
		return
	var status := "\u7b79\u5907\u4e2d" if not store.is_open else ("\u6b63\u5728\u8425\u4e1a" if store.is_business_open else "\u5df2\u5f00\u4e1a\u3001\u5f53\u524d\u5173\u95e8")
	open_status_label.text = status + "\uff1a\u8ba1\u5212\u8425\u4e1a\u65f6\u95f4 " + _get_business_hours_text(store)

func _get_business_hours_text(store: Store) -> String:
	var ranges: Array[String] = []
	for hour_range in store.business_hour_ranges:
		ranges.append("%02d:00-%02d:00" % [hour_range.x, hour_range.y])
	return "\u3001".join(ranges)


func _refresh_live_metrics(store: Store) -> void:
	if store == null or not store.is_open:
		live_metrics_label.text = ""
		return
	if not store.is_business_open:
		live_metrics_label.text = "\u5b9e\u65f6\u7ecf\u8425\uff1a\u5f53\u524d\u5173\u95e8\uff0c\u4e0d\u4f1a\u63a5\u5f85\u987e\u5ba2\u3002"
		return
	var metrics := GameManager.get_store_operating_metrics(store)
	var avg_service := float(metrics.service_total) / float(metrics.service_count) if int(metrics.service_count) > 0 else 0.0
	var avg_wait := float(metrics.wait_total) / float(metrics.orders) if int(metrics.orders) > 0 else 0.0
	var title := "\u5b9e\u65f6\u7ecf\u8425\uff08\u672c\u5c0f\u65f6\uff09" if metrics.source == "live" else "\u6700\u8fd1\u5b8c\u6210\u65f6\u6bb5"
	live_metrics_label.text = "%s\n\u5230\u5e97\uff1a%d -> \u60f3\u4e0b\u5355\uff1a%d -> \u6210\u4ea4\uff1a%d  |  \u6392\u961f\u79bb\u5f00\uff1a%d  |  \u7f3a\u8d27\u6d41\u5931\uff1a%d\n\u5e73\u5747\u51fa\u9910\uff1a%s  |  \u5e73\u5747\u7b49\u5f85\uff1a%s  |  \u6700\u957f\u7b49\u5f85\uff1a%s" % [title, metrics.visitors, metrics.intended_orders, metrics.orders, metrics.queue_left, metrics.inventory_left, _format_live_seconds(avg_service), _format_live_seconds(avg_wait), _format_live_seconds(float(metrics.max_wait))]


func _format_live_seconds(value: float) -> String:
	if value < 60.0:
		return "%.0f\u79d2" % value
	return "%.1f\u5206\u949f" % (value / 60.0)


func _append_business_log(message: String) -> void:
	var line := Label.new()
	line.text = _format_event_time(TimeManager.total_game_seconds) + "  " + message
	customer_feed.add_child(line)
	while customer_feed.get_child_count() > CUSTOMER_FEED_MAX_LINES:
		var oldest := customer_feed.get_child(0)
		customer_feed.remove_child(oldest)
		oldest.queue_free()


func _format_event_time(game_seconds: float) -> String:
	var seconds_in_day := fposmod(game_seconds, TimeManager.DAY_SECONDS)
	var total_seconds := int(seconds_in_day)
	return "D%d %02d:%02d" % [1 + int(game_seconds / TimeManager.DAY_SECONDS), total_seconds / 3600, (total_seconds / 60) % 60]

func _refresh_opening_prep() -> void:
	var state := GameManager.store_state
	for child in opening_checklist.get_children():
		child.queue_free()
	if state == null or state.is_open:
		opening_prep_box.visible = false
		return
	opening_prep_box.visible = true
	var business_range := state.business_hour_ranges[0] if not state.business_hour_ranges.is_empty() else Vector2i(9, 21)
	business_start_option.select(business_range.x)
	business_end_option.select(business_range.y)
	var readiness := GameManager.get_open_readiness()
	for check in readiness.checks:
		var row := HBoxContainer.new()
		var mark := Label.new()
		mark.text = "✅" if check.passed else "⬜"
		row.add_child(mark)
		var text_label := Label.new()
		text_label.text = check.label
		row.add_child(text_label)
		opening_checklist.add_child(row)
	open_store_button.disabled = not readiness.can_open
