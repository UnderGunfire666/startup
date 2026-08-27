class_name StorefrontPopup
extends PopupPanel

signal layout_requested(storefront_id: String, store: Store, read_only: bool)

var _storefront_id := ""
var _body: VBoxContainer

func _ready() -> void:
	close_requested.connect(hide)

func open_for_storefront(storefront_id: String) -> void:
	_storefront_id = storefront_id
	_refresh()
	popup_centered(Vector2i(540, 520))
	move_to_foreground()

func _refresh() -> void:
	if _body == null:
		_body = $Margin/VBox/Scroll/Body
	for child in _body.get_children():
		child.queue_free()
	var storefront := GameManager.get_storefront(_storefront_id)
	if storefront == null:
		return
	var intel := GameManager.get_storefront_intel(_storefront_id)
	var display := StorefrontIntelPresenter.describe_storefront(storefront, GameManager.player_state)
	var visited := bool(display.get("visited", false))
	$Margin/VBox/Title.text = storefront.name + " · " + str(display.get("occupancy", ""))
	_add_text(storefront.notes)
	_add_text(str(display.get("area", "")) + "\n" + str(display.get("appearance", "")))
	if not visited:
		_add_text("街上能看见的只到这里；亲自到访后，才能核对门面状况与实际营业情况。")
		_add_scheduled_button("到访门面（1 小时）", "visit_storefront", _storefront_id)
		return

	var store := GameManager.store_state
	if storefront.is_occupied:
		var npc_store := GameManager.get_npc_store_for_storefront(_storefront_id)
		if npc_store == null:
			_add_text("现场没有找到仍在营业的店铺。")
			return
		_add_text("现场核验：" + str(display.get("occupancy", "")) + ("；经营者：" + str(display.get("occupant_name", "")) if not str(display.get("occupant_name", "")).is_empty() else ""))
		var view_layout := Button.new()
		view_layout.text = "查看店内布局与门头"
		view_layout.pressed.connect(func(): layout_requested.emit(_storefront_id, npc_store, true))
		_body.add_child(view_layout)
		var menu := Button.new()
		menu.text = "查看菜单"
		menu.disabled = not npc_store.is_business_open
		menu.pressed.connect(func():
			GameManager.review_storefront_menu(_storefront_id)
			_refresh()
		)
		_body.add_child(menu)
		if bool(intel.get("menu_reviewed", false)):
			for menu_entry in intel.get("menu", []):
				var order := Button.new()
				order.text = "点单：%s（%.0f 元，1 小时）" % [str(menu_entry.get("name", "商品")), float(menu_entry.get("price", 0.0))]
				var check := ScheduleManager.can_schedule_action("order_storefront", TimeManager.get_current_hour_int(), _storefront_id)
				order.disabled = not bool(check.get("can", false)) or (ScheduleManager.current_action != null and ScheduleManager.current_action.is_active)
				order.tooltip_text = str(check.get("reason", ""))
				var product_id := str(menu_entry.get("product_id", ""))
				order.pressed.connect(func(): ScheduleManager.start_action_now("order_storefront", _storefront_id, [], {"product_id": product_id}))
				_body.add_child(order)
		_add_scheduled_button("观察客流（1 小时）", "observe_storefront", _storefront_id)
		if npc_store.transfer_state == "offered":
			var transfer := Button.new()
			transfer.text = "联系店主谈转让"
			transfer.pressed.connect(func():
				EventManager.start_npc_transfer_chain(npc_store.id)
				hide()
			)
			_body.add_child(transfer)
		else:
			var owner := Button.new()
			owner.text = "联系店主了解经营情况（访谈事件链待制作）"
			owner.disabled = true
			_body.add_child(owner)
		return

	var select := Button.new()
	select.text = "选为开店企划门面"
	select.disabled = store == null or store.is_open
	select.pressed.connect(func():
		GameManager.select_storefront(_storefront_id)
		_refresh()
	)
	_body.add_child(select)
	var selected := store != null and store.selected_storefront_id == _storefront_id
	if selected:
		_add_scheduled_button("与房东谈判（1 小时）", "landlord_negotiation", "")
	var layout := Button.new()
	layout.text = "店面布局与门头"
	layout.disabled = not selected
	layout.pressed.connect(func(): layout_requested.emit(_storefront_id, store, false))
	_body.add_child(layout)

func _add_scheduled_button(label: String, action_id: String, target_id: String) -> void:
	var button := Button.new()
	button.text = label
	var check := ScheduleManager.can_schedule_action(action_id, TimeManager.get_current_hour_int(), target_id)
	button.disabled = not bool(check.get("can", false)) or (ScheduleManager.current_action != null and ScheduleManager.current_action.is_active)
	button.tooltip_text = str(check.get("reason", ""))
	button.pressed.connect(func():
		ScheduleManager.start_action_now(action_id, target_id)
		_refresh()
	)
	_body.add_child(button)

func _add_text(value: String) -> void:
	var label := Label.new()
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)
