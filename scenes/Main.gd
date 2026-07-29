extends Control

@onready var config_panel: PanelContainer    = $RootVBox/TopRow/ConfigPanel
@onready var operation_panel: PanelContainer = $RootVBox/TopRow/OperationPanel
@onready var debug_panel: PanelContainer     = $RootVBox/TopRow/DebugPanel
@onready var report_panel: PanelContainer    = $RootVBox/BottomScroll/BottomRow/ReportPanel
@onready var history_panel: PanelContainer   = $RootVBox/BottomScroll/BottomRow/HistoryPanel

func _ready() -> void:
	config_panel.config_applied.connect(_on_config_applied)
	operation_panel.settlement_done.connect(_on_settlement_done)
	debug_panel.scenario_applied.connect(_on_debug_scenario_applied)
	_refresh_all()

func _on_config_applied() -> void:
	operation_panel.refresh_display()

func _on_settlement_done(result: SettlementResult) -> void:
	if result == null:
		report_panel.display(null)
		return
	report_panel.display(result)
	history_panel.refresh(GameManager.store_state.daily_history)
	operation_panel.refresh_display()

func _on_debug_scenario_applied() -> void:
	operation_panel.refresh_display()
	history_panel.refresh(GameManager.store_state.daily_history)
	report_panel.display(null)

func _refresh_all() -> void:
	operation_panel.refresh_display()
	history_panel.refresh(GameManager.store_state.daily_history)
