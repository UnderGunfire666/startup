extends PanelContainer
## 经营控制面板：显示当前天/时段/实时钟表/门店内各品类营业状态/现金/库存/口碑/压力。
## 时间不再由玩家手动点击推进，而是由 TimeManager 按所选倍速自动流逝，
## 到达时段边界时自动结算并通过信号通知本面板刷新。
## 结算结果依然是数组（门店可含多个品类/多个商品实例）。
## 当自动完成的是一天的最后一个时段（night）时，TimeManager 会额外
## 广播 day_completed，本面板转发为 day_ended 信号，供 Main.gd 弹出日结面板。
##
## 多店重构修正：
## - GameManager.store_state 在角色创建完成前是null，凡是用到的地方都加了null判断。
## - owner_present 字段已从Store迁移到PlayerState.supervising_store_id，
##   勾选框现在反映"玩家是否正坐镇在当前激活的这家店"。
## - current_day 死字段已清理，改用 TimeManager.current_day。

signal settlement_done(results: Array)
signal day_ended(day: int, summary: Dictionary)

@onready var opening_checklist: VBoxContainer = $VBox/OpeningPrepBox/OpeningChecklist
@onready var open_store_button: Button = $VBox/OpeningPrepBox/OpenStoreButton
@onready var opening_status_label: Label = $VBox/OpeningPrepBox/OpeningStatusLabel
@onready var opening_prep_box: VBoxContainer = $VBox/OpeningPrepBox

@onready var clock_label: Label       = $VBox/ClockLabel
@onready var pause_button: Button     = $VBox/SpeedRow/PauseButton
@onready var speed1_button: Button    = $VBox/SpeedRow/Speed1Button
@onready var speed2_button: Button    = $VBox/SpeedRow/Speed2Button
@onready var speed5_button: Button    = $VBox/SpeedRow/Speed5Button

@onready var day_label: Label         = $VBox/DayLabel
@onready var slot_label: Label        = $VBox/SlotLabel
@onready var open_status_label: Label = $VBox/OpenStatusLabel
@onready var cash_label: Label        = $VBox/StatsGrid/CashLabel
@onready var inventory_label: Label   = $VBox/StatsGrid/InventoryLabel
@onready var reputation_label: Label  = $VBox/StatsGrid/ReputationLabel
@onready var stress_label: Label      = $VBox/StatsGrid/StressLabel
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
	pause_button.button_pressed  = TimeManager.speed == TimeManager.Speed.PAUSED
	speed1_button.button_pressed = TimeManager.speed == TimeManager.Speed.X1
	speed2_button.button_pressed = TimeManager.speed == TimeManager.Speed.X2
	speed5_button.button_pressed = TimeManager.speed == TimeManager.Speed.X5

func refresh_display() -> void:
	var state := GameManager.store_state
	if state == null:
		day_label.text = "尚未创建角色"
		open_status_label.text = "⚠ 请先完成人物创建"
		cash_label.text = ""
		inventory_label.text = ""
		reputation_label.text = ""
		stress_label.text = ""
		opening_prep_box.visible = false
		owner_present_check.button_pressed = false
		pause_button.disabled = true
		speed1_button.disabled = true
		speed2_button.disabled = true
		speed5_button.disabled = true
		return

	_refresh_opening_prep()
	_update_speed_button_states()

	owner_present_check.button_pressed = (GameManager.player_state.supervising_store_id == state.id)

	day_label.text  = "第 %d 天" % TimeManager.current_day

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

		var t := ""
		if not open_names.is_empty():
			t += "✅ 营业：%s" % ", ".join(open_names)
		if not closed_names.is_empty():
			if t != "":
				t += "  "
			t += "⛔ 不营业：%s" % ", ".join(closed_names)
		open_status_label.text = t

	cash_label.text       = "现金：%.0f 元" % GameManager.player_state.cash
	inventory_label.text = "库存：%d 单位" % state.get_total_inventory_across_slots()
	reputation_label.text = "口碑：%.1f / 100" % state.reputation
	stress_label.text     = "压力：%.1f / 100" % GameManager.player_state.stress

	var speed_controls_enabled := GameManager.player_state.is_character_created
	pause_button.disabled  = not speed_controls_enabled
	speed1_button.disabled = not speed_controls_enabled
	speed2_button.disabled = not speed_controls_enabled
	speed5_button.disabled = not speed_controls_enabled

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
