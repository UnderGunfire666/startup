extends PanelContainer

signal settlement_done(results: Array)
signal day_ended(day: int, summary: Dictionary)

@onready var opening_checklist: VBoxContainer = $VBox/OpeningPrepBox/OpeningChecklist
@onready var open_store_button: Button = $VBox/OpeningPrepBox/OpenStoreButton
@onready var opening_status_label: Label = $VBox/OpeningPrepBox/OpeningStatusLabel
@onready var opening_prep_box: VBoxContainer = $VBox/OpeningPrepBox
@onready var clock_label: Label = $VBox/ClockLabel
@onready var pause_button: Button = $VBox/SpeedRow/PauseButton
@onready var speed1_button: Button = $VBox/SpeedRow/Speed1Button
@onready var speed2_button: Button = $VBox/SpeedRow/Speed2Button
@onready var speed5_button: Button = $VBox/SpeedRow/Speed5Button
@onready var day_label: Label = $VBox/DayLabel
@onready var slot_label: Label = $VBox/SlotLabel
@onready var open_status_label: Label = $VBox/OpenStatusLabel
@onready var cash_label: Label = $VBox/StatsGrid/CashLabel
@onready var inventory_label: Label = $VBox/StatsGrid/InventoryLabel
@onready var reputation_label: Label = $VBox/StatsGrid/ReputationLabel
@onready var stress_label: Label = $VBox/StatsGrid/StressLabel
@onready var owner_present_check: CheckBox = $VBox/OwnerRow/OwnerPresentCheck
@onready var customer_feed: VBoxContainer = $VBox/CustomerFeedScroll/CustomerFeed

const CUSTOMER_FEED_MAX_LINES: int = 20

func _ready() -> void:
	open_store_button.pressed.connect(_on_open_store_pressed)
	owner_present_check.toggled.connect(_on_owner_present_toggled)
	pause_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.PAUSED))
	speed1_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X1))
	speed2_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X2))
	speed5_button.toggled.connect(func(pressed: bool):
		if pressed: TimeManager.set_speed(TimeManager.Speed.X5))
	TimeManager.clock_updated.connect(_on_clock_updated)
	TimeManager.slot_completed.connect(_on_slot_completed)
	TimeManager.day_completed.connect(_on_day_completed)
	TimeManager.customer_event.connect(_on_customer_event)
	_update_speed_button_states()
	refresh_display()

func _on_owner_present_toggled(pressed: bool) -> void:
	var store := GameManager.store_state
	if store == null:
		return
	GameManager.player_state.supervising_store_id = store.id if pressed else ""

func _on_open_store_pressed() -> void:
	var result := GameManager.open_store()
	opening_status_label.text = ("✅ " if result.success else "⚠ ") + result.reason
	refresh_display()

func _on_clock_updated(hour: int, minute: int, second: int, period_label: String) -> void:
	clock_label.text = "%02d:%02d:%02d ｜ %s" % [hour, minute, second, period_label]

func _on_customer_event(product_name: String, purchased: bool, reason: String) -> void:
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

func _update_speed_button_states() -> void:
	pause_button.button_pressed = TimeManager.speed == TimeManager.Speed.PAUSED
	speed1_button.button_pressed = TimeManager.speed == TimeManager.Speed.X1
	speed2_button.button_pressed = TimeManager.speed == TimeManager.Speed.X2
	speed5_button.button_pressed = TimeManager.speed == TimeManager.Speed.X5

func refresh_display() -> void:
	var state := GameManager.store_state
	var has_character: bool = GameManager.player_state.is_character_created
	var has_store: bool = state != null
	pause_button.disabled = not has_character
	speed1_button.disabled = not has_character
	speed2_button.disabled = not has_character
	speed5_button.disabled = not has_character

	if not has_character:
		day_label.text = "尚未创建角色"
		open_status_label.text = "⚠ 请先创建角色"
		cash_label.text = ""
		inventory_label.text = ""
		reputation_label.text = ""
		stress_label.text = ""
		opening_prep_box.visible = false
		owner_present_check.button_pressed = false
		return

	if not has_store:
		day_label.text = "第 %d 天" % TimeManager.current_day
		open_status_label.text = "尚未创建开店企划，请前往「我的店铺」创建"
		cash_label.text = "现金：%.0f 元" % GameManager.player_state.cash
		inventory_label.text = ""
		reputation_label.text = ""
		stress_label.text = "压力：%.1f / 100" % GameManager.player_state.stress
		opening_prep_box.visible = false
		owner_present_check.button_pressed = false
		return

	_refresh_opening_prep()
	_update_speed_button_states()
	owner_present_check.button_pressed = (GameManager.player_state.supervising_store_id == state.id)
	day_label.text = "第 %d 天" % TimeManager.current_day

	if state.category_slots.is_empty():
		open_status_label.text = "⚠ 门店尚未添加任何品类（请前往品类管理面板添加）"
	else:
		var open_names: Array[String] = []
		var closed_names: Array[String] = []
		for slot in state.category_slots:
			var cat := GameManager.get_category(slot.category_id)
			if cat == null:
				continue
			if slot.is_open_at_hour(TimeManager.get_current_hour_int()):
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
	inventory_label.text = "库存：%d 单位" % state.get_total_inventory_across_slots()
	reputation_label.text = "口碑：%.1f / 100" % state.reputation
	stress_label.text = "压力：%.1f / 100" % GameManager.player_state.stress

func _refresh_opening_prep() -> void:
	var state := GameManager.store_state
	for child in opening_checklist.get_children():
		child.queue_free()
	if state == null or state.is_open:
		opening_prep_box.visible = false
		return
	opening_prep_box.visible = true
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
