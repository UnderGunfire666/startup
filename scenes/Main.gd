extends Control

@onready var main_tabs: TabContainer = \
	$MarginContainer/RootVBox/MainTabs
@onready var player_sub_tabs: TabContainer = \
	$MarginContainer/RootVBox/MainTabs/PlayerPanel/PlayerSubTabs
@onready var store_sub_tabs: TabContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs
@onready var save_load_bar: HBoxContainer = \
	$MarginContainer/RootVBox/SaveLoadBar
@onready var character_creation_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/PlayerPanel/PlayerSubTabs/CharacterCreationPanel
@onready var operation_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs/OperationPanel
@onready var category_manager_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs/CategoryManagerPanel
@onready var procurement_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs/ProcurementPanel
@onready var report_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs/ReportPanel
@onready var history_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs/HistoryPanel
@onready var day_end_panel: PopupPanel = \
	$DayEndPanel
@onready var action_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/ActionPanel
@onready var schedule_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/SchedulePanel
@onready var map_panel: Control = \
	$MarginContainer/RootVBox/MainTabs/MapPanel
@onready var store_list_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs/StoreListPanel

var settlement_history: Array[Dictionary] = []

func _ready() -> void:
	_setup_tab_titles()
	character_creation_panel.character_created.connect(_on_character_created)
	category_manager_panel.category_changed.connect(_on_category_changed)
	procurement_panel.procurement_completed.connect(_on_procurement_completed)
	operation_panel.settlement_done.connect(_on_settlement_done)
	operation_panel.day_ended.connect(_on_day_ended)
	save_load_bar.data_changed.connect(_on_data_changed)
	GameManager.active_store_changed.connect(_on_active_store_changed)
	_refresh_all_panels()

func _setup_tab_titles() -> void:
	main_tabs.set_tab_title(0, "个人")
	main_tabs.set_tab_title(1, "行动")
	main_tabs.set_tab_title(2, "日程")
	main_tabs.set_tab_title(3, "店铺")
	main_tabs.set_tab_title(4, "地图")
	player_sub_tabs.set_tab_title(0, "创建角色")
	store_sub_tabs.set_tab_title(0, "我的店铺")
	store_sub_tabs.set_tab_title(1, "营业")
	store_sub_tabs.set_tab_title(2, "品类商品")
	store_sub_tabs.set_tab_title(3, "进货")
	store_sub_tabs.set_tab_title(4, "结算报告")
	store_sub_tabs.set_tab_title(5, "历史统计")

func _on_character_created() -> void:
	settlement_history.clear()
	_refresh_all_panels()
	main_tabs.current_tab = 4

func _refresh_all_panels() -> void:
	_refresh_character_panel()
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()
	_refresh_history_panel()
	_refresh_action_panel()
	_refresh_schedule_panel()
	_refresh_map_panel()
	store_list_panel.refresh()

func _on_active_store_changed(_store_id: String) -> void:
	_refresh_all_panels()

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

func _on_day_ended(day: int, summary: Dictionary) -> void:
	day_end_panel.show_summary(day, summary)

func _on_data_changed() -> void:
	settlement_history.clear()
	var store := GameManager.store_state
	if store != null:
		settlement_history = store.daily_history.duplicate()
	report_panel.display([])
	_refresh_all_panels()

func _refresh_character_panel() -> void:
	character_creation_panel.refresh()
func _refresh_action_panel() -> void:
	action_panel.refresh()
func _refresh_schedule_panel() -> void:
	schedule_panel.refresh()
func _refresh_map_panel() -> void:
	map_panel.refresh()
func _refresh_category_panel() -> void:
	category_manager_panel.refresh()
func _refresh_procurement_panel() -> void:
	procurement_panel.refresh()
func _refresh_operation_panel() -> void:
	operation_panel.refresh_display()
func _refresh_history_panel() -> void:
	history_panel.refresh(settlement_history)
