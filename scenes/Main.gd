extends Control

@onready var config_panel: PanelContainer = $MarginContainer/Tabs/ConfigPanel
@onready var operation_panel: PanelContainer = $MarginContainer/Tabs/OperationPanel
@onready var category_manager_panel: PanelContainer = $MarginContainer/Tabs/CategoryManagerPanel
@onready var procurement_panel: PanelContainer = $MarginContainer/Tabs/ProcurementPanel
@onready var report_panel: PanelContainer = $MarginContainer/Tabs/ReportPanel
@onready var history_panel: PanelContainer = $MarginContainer/Tabs/HistoryPanel
@onready var debug_panel: PanelContainer = $MarginContainer/Tabs/DebugPanel

var settlement_history: Array[Dictionary] = []

func _ready() -> void:
	config_panel.config_applied.connect(_on_config_applied)
	category_manager_panel.category_changed.connect(_on_category_changed)
	procurement_panel.procurement_completed.connect(_on_procurement_completed)
	operation_panel.settlement_done.connect(_on_settlement_done)

	_refresh_all_panels()

func _on_config_applied() -> void:
	category_manager_panel.refresh()
	procurement_panel.refresh()
	_refresh_operation_panel()

func _on_category_changed() -> void:
	category_manager_panel.refresh()
	procurement_panel.refresh()
	_refresh_operation_panel()

func _on_procurement_completed() -> void:
	category_manager_panel.refresh()
	_refresh_operation_panel()

func _on_settlement_done(results: Array) -> void:
	for result in results:
		if result is SettlementResult:
			settlement_history.append(result.to_summary_dict())

	category_manager_panel.refresh()
	procurement_panel.refresh()
	_refresh_operation_panel()
	report_panel.display(results)
	_refresh_history_panel()

func _refresh_all_panels() -> void:
	category_manager_panel.refresh()
	procurement_panel.refresh()
	_refresh_operation_panel()
	_refresh_history_panel()

func _refresh_operation_panel() -> void:
	operation_panel.refresh_display()

func _refresh_history_panel() -> void:
	history_panel.refresh(settlement_history)
