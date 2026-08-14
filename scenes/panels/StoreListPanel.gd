extends PanelContainer
## 多店重构阶段4：店铺列表/切换面板。
## 负责"看清楚玩家名下有哪几家店、哪家是营业中/筹备中、当前在看哪家"，
## 以及"切换激活店铺"和"开设新店铺"这两个动作。
##
## 不直接负责其余五个店铺子面板的刷新——那是Main.gd监听
## GameManager.active_store_changed信号后统一做的事，这个面板只管自己。

@onready var status_label: Label = $VBox/StatusLabel
@onready var store_list: VBoxContainer = $VBox/StoreScroll/StoreList
@onready var new_store_name_input: LineEdit = $VBox/NewStoreRow/NewStoreNameInput
@onready var create_button: Button = $VBox/NewStoreRow/CreateButton

signal setup_requested
signal procurement_requested


func _ready() -> void:
	create_button.pressed.connect(_on_create_pressed)
	GameManager.active_store_changed.connect(func(_store_id: String): refresh())
	GameManager.store_plan_updated.connect(func(_store_id: String): refresh())
	refresh()


func refresh() -> void:
	for child in store_list.get_children():
		child.queue_free()

	if not GameManager.player_state.is_character_created:
		status_label.text = "请先完成人物创建"
		create_button.disabled = true
		return

	create_button.disabled = false

	if GameManager.stores.is_empty():
		status_label.text = "你名下还没有任何店铺"
		return

	status_label.text = "共 %d 家店铺" % GameManager.stores.size()

	for store in GameManager.stores:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 6)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		var mark := "●" if store.id == GameManager.active_store_id else "○"
		var status_text := "营业中" if store.is_open else "筹备中"

		var name_label := Label.new()
		name_label.text = "%s  %s（%s）" % [mark, store.name, status_text]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)

		var switch_btn := Button.new()
		if store.id == GameManager.active_store_id:
			switch_btn.text = "当前查看"
			switch_btn.disabled = true
		else:
			switch_btn.text = "切换到这家店"
			switch_btn.pressed.connect(func():
				var result := GameManager.switch_active_store(store.id)
				status_label.text = result.get("reason", "")
			)
		row.add_child(switch_btn)

		card.add_child(row)
		var plan_label := Label.new()
		plan_label.text = _get_plan_summary(store)
		plan_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(plan_label)

		if store.id == GameManager.active_store_id and not store.is_open:
			if not store.selected_storefront_id.is_empty() and store.signed_storefront_id != store.selected_storefront_id:
				var sign_button := Button.new()
				sign_button.text = "确认签约门面"
				sign_button.pressed.connect(func() -> void:
					var result := GameManager.sign_selected_storefront()
					status_label.text = str(result.get("reason", ""))
				)
				card.add_child(sign_button)

			var setup_button := Button.new()
			setup_button.text = "配置品类与商品"
			setup_button.pressed.connect(func() -> void: setup_requested.emit())
			card.add_child(setup_button)

			if store.signed_storefront_id != "" and not store.category_slots.is_empty():
				var procurement_button := Button.new()
				procurement_button.text = "前往采购与补货"
				procurement_button.pressed.connect(func() -> void: procurement_requested.emit())
				card.add_child(procurement_button)

		store_list.add_child(card)
		store_list.add_child(HSeparator.new())


func _get_plan_summary(store: Store) -> String:
	var category_text := "已确定%d个子类" % store.category_slots.size() if not store.category_slots.is_empty() else "尚未确定品类"
	match store.pre_open_stage:
		Store.PreOpenStage.REGION_RESEARCH:
			return "开店企划：待调研并选定门面｜%s" % category_text
		Store.PreOpenStage.STOREFRONT_SELECTION:
			return "开店企划：待完成门面尽调并选定门面｜%s" % category_text
		Store.PreOpenStage.STORE_SETUP:
			var storefront := GameManager.get_storefront(store.selected_storefront_id)
			if storefront == null:
				return "开店企划：门面信息缺失，待重新选择"
			var signing_text := "已签约" if store.signed_storefront_id == storefront.id else "已选定，待签约"
			return "开店企划：门面「%s」｜%s｜%s｜员工为可选筹备项" % [storefront.name, signing_text, category_text]
		Store.PreOpenStage.OPEN_FOR_BUSINESS:
			return "开店企划：已开业"
		_:
			return "开店企划：待开始"


func _on_create_pressed() -> void:
	var new_name := new_store_name_input.text.strip_edges()
	var result := GameManager.create_new_store(new_name)
	status_label.text = result.get("reason", "")
	if result.get("success", false):
		new_store_name_input.text = ""
