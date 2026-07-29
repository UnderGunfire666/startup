extends PanelContainer

signal settlement_done(result)

@onready var day_label: Label         = $VBox/DayLabel
@onready var slot_label: Label        = $VBox/SlotLabel
@onready var open_status_label: Label = $VBox/OpenStatusLabel
@onready var cash_label: Label        = $VBox/StatsGrid/CashLabel
@onready var inventory_label: Label   = $VBox/StatsGrid/InventoryLabel
@onready var reputation_label: Label  = $VBox/StatsGrid/ReputationLabel
@onready var stress_label: Label      = $VBox/StatsGrid/StressLabel
@onready var advance_button: Button   = $VBox/AdvanceButton

func _ready() -> void:
	advance_button.pressed.connect(_on_advance_pressed)
	refresh_display()

func _on_advance_pressed() -> void:
	var result := GameManager.run_settlement()
	if result == null:
		open_status_label.text = "⚠ 结算失败：%s" % GameManager.last_settlement_error
		settlement_done.emit(null)
		return
	GameManager.advance_time_only()
	refresh_display()
	settlement_done.emit(result)

func refresh_display() -> void:
	var state := GameManager.store_state
	day_label.text  = "第 %d 天" % state.current_day
	slot_label.text = "当前时段：%s" % SettlementConfig.SLOT_NAMES.get(
		state.get_current_slot(), state.get_current_slot())

	var cat := GameManager.current_category
	var open_slots: Array = []
	if cat != null:
		match state.strategy:
			"standard": open_slots = cat.default_open_slots
			"extend":   open_slots = SettlementConfig.SLOT_ORDER
			"shorten":  open_slots = cat.preferred_slots
	var will_open := state.get_current_slot() in open_slots
	if cat == null:
		open_status_label.text = "⚠ 尚未应用配置（请先选择区域/门面/品类/产品并点击「应用配置」，或使用调试场景按钮）"
	elif will_open:
		open_status_label.text = "✅ 本时段将营业（策略：%s）" % state.strategy
	else:
		open_status_label.text = "⛔ 本时段不营业（策略：%s，品类不在此时段营业）" % state.strategy

	cash_label.text       = "现金：%.0f 元" % state.cash
	inventory_label.text  = "库存：%d 单位" % state.inventory_units
	reputation_label.text = "口碑：%.1f / 100" % state.reputation
	stress_label.text     = "压力：%.1f / 100" % state.stress
