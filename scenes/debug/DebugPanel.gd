extends PanelContainer
## 调试面板：一键切换6个验收场景，支持连续推进多日，支持"忽略门面品类限制"开关。

signal scenario_applied

@onready var scenario_a_btn: Button = $VBox/ScenarioGrid/ScenarioA
@onready var scenario_b_btn: Button = $VBox/ScenarioGrid/ScenarioB
@onready var scenario_c_btn: Button = $VBox/ScenarioGrid/ScenarioC
@onready var scenario_d_btn: Button = $VBox/ScenarioGrid/ScenarioD
@onready var scenario_e_btn: Button = $VBox/ScenarioGrid/ScenarioE
@onready var scenario_f_btn: Button = $VBox/ScenarioGrid/ScenarioF
@onready var ignore_category_check: CheckBox = $VBox/IgnoreCategoryCheck
@onready var advance_days_spin: SpinBox = $VBox/AdvanceRow/AdvanceDaysSpin
@onready var advance_days_btn: Button = $VBox/AdvanceRow/AdvanceDaysButton
@onready var reset_btn: Button = $VBox/ResetButton
@onready var status_label: Label = $VBox/StatusLabel

func _ready() -> void:
	scenario_a_btn.pressed.connect(func(): _apply_scenario("A"))
	scenario_b_btn.pressed.connect(func(): _apply_scenario("B"))
	scenario_c_btn.pressed.connect(func(): _apply_scenario("C"))
	scenario_d_btn.pressed.connect(func(): _apply_scenario("D"))
	scenario_e_btn.pressed.connect(func(): _apply_scenario("E"))
	scenario_f_btn.pressed.connect(func(): _apply_scenario("F"))
	ignore_category_check.toggled.connect(_on_ignore_category_toggled)
	advance_days_btn.pressed.connect(_on_advance_days_pressed)
	reset_btn.pressed.connect(_on_reset_pressed)

func _apply_scenario(scenario_id: String) -> void:
	GameManager.apply_debug_scenario(scenario_id)
	status_label.text = "已应用场景 %s" % scenario_id
	scenario_applied.emit()

func _on_ignore_category_toggled(pressed: bool) -> void:
	GameManager.debug_ignore_category_restriction = pressed
	status_label.text = "忽略门面品类限制：%s" % ("开启" if pressed else "关闭")

func _on_advance_days_pressed() -> void:
	var days := int(advance_days_spin.value)
	var slots_to_run := days * SettlementConfig.SLOT_ORDER.size()
	for i in range(slots_to_run):
		GameManager.run_settlement()
		GameManager.advance_time_only()
	status_label.text = "已连续推进 %d 天（%d 个时段）" % [days, slots_to_run]
	scenario_applied.emit()

func _on_reset_pressed() -> void:
	GameManager.store_state.reset_to_defaults()
	GameManager.debug_ignore_category_restriction = false
	ignore_category_check.button_pressed = false
	status_label.text = "已重置门店状态"
	scenario_applied.emit()
