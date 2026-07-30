extends Control

@onready var origin_selection_panel: PanelContainer = \
	$MarginContainer/Tabs/OriginSelectionPanel

@onready var region_research_panel: PanelContainer = \
	$MarginContainer/Tabs/RegionResearchPanel

@onready var storefront_panel: PanelContainer = \
	$MarginContainer/Tabs/StorefrontPanel

@onready var operation_panel: PanelContainer = \
	$MarginContainer/Tabs/OperationPanel

@onready var category_manager_panel: PanelContainer = \
	$MarginContainer/Tabs/CategoryManagerPanel

@onready var procurement_panel: PanelContainer = \
	$MarginContainer/Tabs/ProcurementPanel

@onready var report_panel: PanelContainer = \
	$MarginContainer/Tabs/ReportPanel

@onready var history_panel: PanelContainer = \
	$MarginContainer/Tabs/HistoryPanel

@onready var debug_panel: PanelContainer = \
	$MarginContainer/Tabs/DebugPanel

var settlement_history: Array[Dictionary] = []


func _ready() -> void:
	origin_selection_panel.origin_selected.connect(_on_origin_selected)
	region_research_panel.region_selected.connect(_on_region_selected)
	storefront_panel.storefront_selected.connect(_on_storefront_selected)
	category_manager_panel.category_changed.connect(_on_category_changed)
	procurement_panel.procurement_completed.connect(_on_procurement_completed)
	operation_panel.settlement_done.connect(_on_settlement_done)
	_refresh_all_panels()


func _on_origin_selected() -> void:
	settlement_history.clear()

	_refresh_origin_panel()
	_refresh_region_panel()
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()
	_refresh_history_panel()

func _on_region_selected() -> void:
	storefront_panel.refresh()

func _on_storefront_selected() -> void:
	category_manager_panel.refresh()

func _refresh_region_panel() -> void:
	region_research_panel.refresh()

func _on_config_applied() -> void:
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()


func _on_category_changed() -> void:
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()


func _on_procurement_completed() -> void:
	_refresh_category_panel()
	_refresh_operation_panel()


func _on_settlement_done(results: Array) -> void:
	for result in results:
		if result is SettlementResult:
			settlement_history.append(result.to_summary_dict())

	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()

	report_panel.display(results)
	_refresh_history_panel()


func _refresh_all_panels() -> void:
	_refresh_origin_panel()
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()
	_refresh_history_panel()


func _refresh_origin_panel() -> void:
	origin_selection_panel.refresh()

func _refresh_category_panel() -> void:
	category_manager_panel.refresh()


func _refresh_procurement_panel() -> void:
	procurement_panel.refresh()


func _refresh_operation_panel() -> void:
	operation_panel.refresh_display()


func _refresh_history_panel() -> void:
	history_panel.refresh(settlement_history)
