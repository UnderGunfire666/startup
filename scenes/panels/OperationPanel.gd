extends PanelContainer
## 经营控制面板：显示当前天/时段/门店内各品类营业状态/现金/库存/口碑/压力
## 提供"推进到下一时段并结算"按钮。结算结果现在是数组（门店可含多个品类）。

signal settlement_done(results: Array)

@onready var day_label: Label         = $VBox/DayLabel
@onready var slot_label: Label        = $VBox/SlotLabel
@onready var open_status_label: Label = $VBox/OpenStatusLabel
@onready var cash_label: Label        = $VBox/StatsGrid/CashLabel
@onready var inventory_label: Label   = $VBox/StatsGrid/InventoryLabel
@onready var reputation_label: Label  = $VBox/StatsGrid/ReputationLabel
@onready var stress_label: Label      = $VBox/StatsGrid/StressLabel
@onready var owner_present_check: CheckBox = $VBox/OwnerRow/OwnerPresentCheck
@onready var advance_button: Button   = $VBox/AdvanceButton

func _ready() -> void:
	advance_button.pressed.connect(_on_advance_pressed)
	owner_present_check.button_pressed = GameManager.store_state.owner_present
	owner_present_check.toggled.connect(_on_owner_present_toggled)
	refresh_display()

func _on_owner_present_toggled(pressed: bool) -> void:
	GameManager.store_state.owner_present = pressed

func _on_advance_pressed() -> void:
	var results: Array = GameManager.run_settlement()
	if results.is_empty() and GameManager.last_settlement_error != "":
		open_status_label.text = "⚠ 结算失败：%s" % GameManager.last_settlement_error
		settlement_done.emit([])
		return
	GameManager.advance_time_only()
	refresh_display()
	settlement_done.emit(results)

func refresh_display() -> void:
	var state := GameManager.store_state
	day_label.text  = "第 %d 天" % state.current_day
	slot_label.text = "当前时段：%s" % SettlementConfig.SLOT_NAMES.get(
		state.get_current_slot(), state.get_current_slot())

	if state.category_slots.is_empty():
		open_status_label.text = "⚠ 门店尚未添加任何品类（请前往品类管理面板添加）"
	else:
		var open_names: Array[String] = []
		var closed_names: Array[String] = []
		for slot in state.category_slots:
			var cat := GameManager.get_category(slot.category_id)
			if cat == null:
				continue
			var open_slots: Array = []
			match slot.strategy:
				"standard": open_slots = cat.default_open_slots
				"extend":   open_slots = SettlementConfig.SLOT_ORDER
				"shorten":  open_slots = cat.preferred_slots
			if state.get_current_slot() in open_slots:
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

	cash_label.text       = "现金：%.0f 元" % state.cash
	inventory_label.text = "库存：%d 单位" % state.get_total_inventory_across_slots()
	reputation_label.text = "口碑：%.1f / 100" % state.reputation
	stress_label.text     = "压力：%.1f / 100" % state.stress
