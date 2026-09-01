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
@onready var character_status_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/PlayerPanel/PlayerSubTabs/CharacterStatusPanel
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
@onready var employee_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs/EmployeePanel
@onready var day_end_panel: PopupPanel = \
	$DayEndPanel
@onready var map_panel: Control = \
	$MarginContainer/RootVBox/MainTabs/MapPanel
@onready var discovery_panel: DiscoveryPanel = \
	$MarginContainer/RootVBox/MainTabs/DiscoveryPanel
@onready var store_list_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/StorePanel/StoreSubTabs/StoreListPanel
@onready var interior_layout_panel: Control = $InteriorLayoutPanel
@onready var event_popup: EventPopup = $EventPopup
@onready var storefront_popup: StorefrontPopup = $StorefrontPopup

var settlement_history: Array[Dictionary] = []

func _ready() -> void:
	_setup_tab_titles()
	store_sub_tabs.set_tab_title(6, "\u5458\u5de5\u4e0e\u6392\u73ed")
	character_creation_panel.character_created.connect(_on_character_created)
	character_status_panel.visibility_changed.connect(func() -> void:
		if character_status_panel.is_visible_in_tree():
			_refresh_character_panel())
	TimeManager.clock_updated.connect(_on_clock_updated)
	ScheduleManager.schedule_changed.connect(_on_schedule_changed)
	category_manager_panel.category_changed.connect(_on_category_changed)
	employee_panel.employee_changed.connect(_on_employee_changed)
	procurement_panel.procurement_completed.connect(_on_procurement_completed)
	store_list_panel.setup_requested.connect(_on_store_setup_requested)
	store_list_panel.procurement_requested.connect(_on_procurement_requested)
	map_panel.storefront_interior_requested.connect(_on_storefront_interior_requested)
	map_panel.storefront_details_requested.connect(storefront_popup.open_for_storefront)
	storefront_popup.layout_requested.connect(_on_storefront_interior_requested)
	operation_panel.settlement_done.connect(_on_settlement_done)
	operation_panel.store_opened.connect(_on_store_opened)
	operation_panel.day_ended.connect(_on_day_ended)
	save_load_bar.data_changed.connect(_on_data_changed)
	GameManager.active_store_changed.connect(_on_active_store_changed)
	GameManager.store_plan_updated.connect(_on_store_plan_updated)
	BlockDiscoveryManager.discovery_recorded.connect(func(_record: Dictionary) -> void: discovery_panel.refresh())
	EventManager.notice_raised.connect(func(event: ActiveGameEvent) -> void:
		if event.interaction == GameEventDefinition.Interaction.NOTICE:
			event_popup.enqueue(event)
	)
	EventManager.decision_raised.connect(event_popup.enqueue)
	EventManager.interrupt_raised.connect(event_popup.enqueue)
	_refresh_all_panels()

func _setup_tab_titles() -> void:
	main_tabs.set_tab_title(0, "个人")
	main_tabs.set_tab_title(1, "店铺")
	main_tabs.set_tab_title(2, "地图")
	main_tabs.set_tab_title(3, "发现")
	player_sub_tabs.set_tab_title(0, "创建角色")
	player_sub_tabs.set_tab_title(1, "当前角色")
	store_sub_tabs.set_tab_title(0, "我的店铺")
	store_sub_tabs.set_tab_title(1, "营业")
	store_sub_tabs.set_tab_title(2, "品类商品")
	store_sub_tabs.set_tab_title(3, "进货")
	store_sub_tabs.set_tab_title(4, "结算报告")
	store_sub_tabs.set_tab_title(5, "历史统计")

func _on_character_created() -> void:
	settlement_history.clear()
	_refresh_all_panels()
	main_tabs.current_tab = 0
	player_sub_tabs.current_tab = 1


func _on_clock_updated(_hour: int, _minute: int, _second: int, _period_label: String) -> void:
	if character_status_panel.is_visible_in_tree() or character_creation_panel.is_visible_in_tree():
		_refresh_character_panel()


func _on_schedule_changed() -> void:
	if character_status_panel.is_visible_in_tree() or character_creation_panel.is_visible_in_tree():
		_refresh_character_panel()

func _refresh_all_panels() -> void:
	_refresh_character_panel()
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()
	_refresh_history_panel()
	_refresh_employee_panel()
	_refresh_map_panel()
	_refresh_discovery_panel()
	store_list_panel.refresh()

func _on_active_store_changed(_store_id: String) -> void:
	_refresh_all_panels()


func _on_store_plan_updated(_store_id: String) -> void:
	_refresh_all_panels()


func _on_store_setup_requested() -> void:
	main_tabs.current_tab = 1
	store_sub_tabs.current_tab = 2
	_refresh_category_panel()


func _on_procurement_requested() -> void:
	main_tabs.current_tab = 1
	store_sub_tabs.current_tab = 3
	_refresh_procurement_panel()


func _on_store_opened() -> void:
	_on_procurement_requested()

func _on_storefront_interior_requested(storefront_id: String, store: Store = null, read_only: bool = false, facade_only: bool = false) -> void:
	interior_layout_panel.open_for_storefront(storefront_id, store, read_only, facade_only)

func _on_config_applied() -> void:
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()

func _on_category_changed() -> void:
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()

func _on_employee_changed() -> void:
	_refresh_employee_panel()
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
	_refresh_map_panel()

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
	var has_character := GameManager.player_state.is_character_created
	if has_character:
		player_sub_tabs.set_tab_hidden(1, false)
		character_status_panel.refresh()
		player_sub_tabs.current_tab = 1
		player_sub_tabs.set_tab_hidden(0, true)
	else:
		player_sub_tabs.set_tab_hidden(0, false)
		character_creation_panel.refresh()
		player_sub_tabs.current_tab = 0
		player_sub_tabs.set_tab_hidden(1, true)
func _refresh_map_panel() -> void:
	map_panel.refresh()
func _refresh_discovery_panel() -> void:
	discovery_panel.refresh()
func _refresh_category_panel() -> void:
	category_manager_panel.refresh()
func _refresh_procurement_panel() -> void:
	procurement_panel.refresh()
func _refresh_operation_panel() -> void:
	operation_panel.refresh_display()
func _refresh_history_panel() -> void:
	history_panel.refresh(settlement_history)
func _refresh_employee_panel() -> void:
	employee_panel.refresh()
