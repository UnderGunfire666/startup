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

@onready var region_research_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/PlayerPanel/PlayerSubTabs/RegionResearchPanel

@onready var storefront_panel: PanelContainer = \
	$MarginContainer/RootVBox/MainTabs/PlayerPanel/PlayerSubTabs/StorefrontPanel

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

var settlement_history: Array[Dictionary] = []


func _ready() -> void:
	_setup_tab_titles()

	character_creation_panel.character_created.connect(_on_character_created)
	region_research_panel.region_selected.connect(_on_region_selected)
	storefront_panel.storefront_selected.connect(_on_storefront_selected)
	category_manager_panel.category_changed.connect(_on_category_changed)
	procurement_panel.procurement_completed.connect(_on_procurement_completed)
	operation_panel.settlement_done.connect(_on_settlement_done)
	operation_panel.day_ended.connect(_on_day_ended)
	save_load_bar.data_changed.connect(_on_data_changed)
	_refresh_all_panels()


## 节点名统一使用英文以保证 $ 路径稳定，中文标题在此处集中设置，
## 方便以后调整文案而不用动场景树结构。
func _setup_tab_titles() -> void:
	main_tabs.set_tab_title(0, "个人")
	main_tabs.set_tab_title(1, "店铺")

	player_sub_tabs.set_tab_title(0, "创建角色")
	player_sub_tabs.set_tab_title(1, "区域调研")
	player_sub_tabs.set_tab_title(2, "门面选择")

	store_sub_tabs.set_tab_title(0, "营业")
	store_sub_tabs.set_tab_title(1, "品类商品")
	store_sub_tabs.set_tab_title(2, "进货")
	store_sub_tabs.set_tab_title(3, "结算报告")
	store_sub_tabs.set_tab_title(4, "历史统计")


func _on_character_created() -> void:
	settlement_history.clear()

	_refresh_character_panel()
	_refresh_region_panel()
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()
	_refresh_history_panel()

	## 创建完成后，进入区域调研。
	player_sub_tabs.current_tab = 1

func _on_region_selected() -> void:
	storefront_panel.refresh()
	_refresh_operation_panel()
	player_sub_tabs.current_tab = 2

func _on_storefront_selected() -> void:
	category_manager_panel.refresh()
	_refresh_operation_panel()
	# 门面选好后自动切到店铺面板，引导玩家开始配置品类
	main_tabs.current_tab = 1
	store_sub_tabs.current_tab = 1

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


func _on_day_ended(day: int, summary: Dictionary) -> void:
	day_end_panel.show_summary(day, summary)


## 读取存档或开始新开局后触发：整局状态可能被完全替换，
## 需要重建 settlement_history 并刷新全部面板，避免残留旧局的显示。
func _on_data_changed() -> void:
	settlement_history = GameManager.store_state.daily_history.duplicate()
	report_panel.display([])
	_refresh_all_panels()


func _refresh_all_panels() -> void:
	_refresh_character_panel()
	_refresh_region_panel()
	storefront_panel.refresh()
	_refresh_category_panel()
	_refresh_procurement_panel()
	_refresh_operation_panel()
	_refresh_history_panel()


func _refresh_character_panel() -> void:
	character_creation_panel.refresh()

func _refresh_category_panel() -> void:
	category_manager_panel.refresh()


func _refresh_procurement_panel() -> void:
	procurement_panel.refresh()


func _refresh_operation_panel() -> void:
	operation_panel.refresh_display()


func _refresh_history_panel() -> void:
	history_panel.refresh(settlement_history)
