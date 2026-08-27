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
@onready var root_box: VBoxContainer = $VBox
var decision_box: VBoxContainer
var interrupt_box: VBoxContainer

const CUSTOMER_FEED_MAX_LINES: int = 20

func _ready() -> void:
	interrupt_box = VBoxContainer.new()
	interrupt_box.name = "InterruptBox"
	root_box.add_child(interrupt_box)
	root_box.move_child(interrupt_box, customer_feed.get_parent().get_index())
	decision_box = VBoxContainer.new()
	decision_box.name = "DecisionBox"
	root_box.add_child(decision_box)
	root_box.move_child(decision_box, customer_feed.get_parent().get_index())
	EventManager.decision_raised.connect(func(_event: ActiveGameEvent) -> void: _refresh_decisions())
	EventManager.interrupt_raised.connect(func(_event: ActiveGameEvent) -> void: _refresh_interrupts())
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
	EventManager.notice_raised.connect(_on_event_notice_raised)
	refresh_display()

func _refresh_decisions() -> void:
	for child in decision_box.get_children(): child.queue_free()
	var store := GameManager.store_state
	if store == null: return
	for event in EventManager.pending_decisions:
		if event.store_id != store.id: continue
		var label := Label.new()
		label.text = "[\u51b3\u7b56] " + event.title + "\uff1a" + event.message
		decision_box.add_child(label)
		for option in event.options:
			var button := Button.new()
			var option_id: String = str(option.get("id", ""))
			button.text = str(option.get("label", option_id))
			button.pressed.connect(_on_decision_option_pressed.bind(event.event_id, option_id))
			decision_box.add_child(button)


func _refresh_interrupts() -> void:
	for child in interrupt_box.get_children(): child.queue_free()
	var store := GameManager.store_state
	if store == null:
		return
	for event in EventManager.pending_interrupts:
		if event.store_id != store.id:
			continue
		var label := Label.new()
		label.text = "[\u7d27\u6025] " + event.title + "\uff1a" + event.message
		interrupt_box.add_child(label)
		var button := Button.new()
		button.text = "\u786e\u8ba4\u5e76\u67e5\u770b\u5f71\u54cd"
		button.pressed.connect(_on_interrupt_acknowledged.bind(event.event_id))
		interrupt_box.add_child(button)


func _on_decision_option_pressed(event_id: String, option_id: String) -> void:
	EventManager.resolve_decision(event_id, option_id)
	_refresh_decisions()


func _on_interrupt_acknowledged(event_id: String) -> void:
	EventManager.resolve_interrupt(event_id)
	_refresh_interrupts()

func _on_owner_present_toggled(pressed: bool) -> void:
	var store := GameManager.store_state
	if store == null:
		return
	GameManager.set_player_store_presence(store, pressed)
	_append_business_log("你走到柜台前，准备和店里一起接住接下来的客人" if pressed else "你离开了柜台，把接下来的节奏交还给店里")
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
		_append_business_log("卷帘门推开，店里的第一段营业时间开始了")
	refresh_display()

func _on_close_business_pressed() -> void:
	var result := GameManager.close_business()
	open_status_label.text = str(result.get("reason", ""))
	if bool(result.get("success", false)):
		_append_business_log("最后一盏灯留在店里，今天的营业暂时收了尾")
	refresh_display()

func _on_customer_event(product_name: String, purchased: bool, reason: String, event_game_seconds: float) -> void:
	var event_line := Label.new()
	var time_text := _format_event_time(event_game_seconds)
	event_line.text = "%s  %s" % [time_text, (product_name + "：一位顾客带着它离开了柜台") if purchased else (product_name + "：" + reason)]
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
	if decision_box != null:
		_refresh_decisions()
	if interrupt_box != null:
		_refresh_interrupts()
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
	var awareness := 0.0
	var offline_awareness_text := ""
	var destination_sources_text := ""
	var storefront := GameManager.get_storefront(store.selected_storefront_id)
	if storefront != null:
		for block in GameManager.all_blocks:
			if block.has_map_point(storefront.map_position):
				awareness = float(store.awareness_by_block.get(block.id, 0.0))
				break
		var coverage_ratios := StorefrontInfluenceCalculator.get_covered_block_ratios(storefront, GameManager.all_blocks)
		var coverage_parts: Array[String] = []
		for raw_block_id in coverage_ratios.keys():
			var block := GameManager.get_block(str(raw_block_id))
			if block != null:
				coverage_parts.append("%s %.0f%%" % [block.name, float(coverage_ratios[raw_block_id]) * 100.0])
		offline_awareness_text = "\n\u7ebf\u4e0b\u5f71\u54cd\u8303\u56f4\uff1a%.0f  |  \u66dd\u5149\u4fee\u6b63\uff1a%.2f  |  \u8986\u76d6\u533a\u5757\uff1a%s" % [storefront.awareness_radius, storefront.awareness_exposure_modifier, "\u3001".join(coverage_parts)]
		var source_parts: Array[String] = []
		for source in GameManager.get_destination_visitor_sources(store, storefront):
			var source_block := GameManager.get_block(str(source.get("block_id", "")))
			if source_block != null:
				source_parts.append("%s(\u77e5\u540d%.1f, \u9884\u4f30%.1f)" % [source_block.name, float(source.get("awareness", 0.0)), float(source.get("estimated_visitors", 0.0))])
		destination_sources_text = "\n\u8de8\u533a\u76ee\u7684\u6027\u5ba2\u6d41\u6765\u6e90\uff1a" + ("\u3001".join(source_parts) if not source_parts.is_empty() else "\u6682\u65e0")
	live_metrics_label.text = "%s\n\u5230\u5e97\uff1a%d -> \u60f3\u4e0b\u5355\uff1a%d -> \u6210\u4ea4\uff1a%d  |  \u6392\u961f\u79bb\u5f00\uff1a%d  |  \u7f3a\u8d27\u6d41\u5931\uff1a%d\n\u6240\u5728\u533a\u5757\u77e5\u540d\u5ea6\uff1a%.1f / 100  |  \u5e97\u94fa\u53e3\u7891\uff1a%.1f / 100%s%s\n\u5e73\u5747\u51fa\u9910\uff1a%s  |  \u5e73\u5747\u7b49\u5f85\uff1a%s  |  \u6700\u957f\u7b49\u5f85\uff1a%s" % [title, metrics.visitors, metrics.intended_orders, metrics.orders, metrics.queue_left, metrics.inventory_left, awareness, store.reputation, offline_awareness_text, destination_sources_text, _format_live_seconds(avg_service), _format_live_seconds(avg_wait), _format_live_seconds(float(metrics.max_wait))]


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


func _on_event_notice_raised(event: ActiveGameEvent) -> void:
	var store := GameManager.store_state
	if store == null or event.scope != GameEventDefinition.Scope.STORE or event.store_id != store.id:
		return
	_append_business_log("[\u4e8b\u4ef6] " + event.title + "\uff1a" + event.message)

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
