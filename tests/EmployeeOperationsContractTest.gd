extends Node

var passed := 0
var failed := 0


func _ready() -> void:
	print("========== Employee Operations Contract Test ==========")
	_test_staffing_service_and_ingredient_waste()
	_test_customer_flow_queue_and_inventory()
	_test_shared_ingredient_reservation()
	print("========== Test finished: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _test_staffing_service_and_ingredient_waste() -> void:
	GameManager.start_new_game()
	ScheduleManager.reset_for_new_game()
	var character_result := GameManager.create_character({
		"player_name": "Operations Tester", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": [],
	})
	_assert_true(bool(character_result.get("success", false)), "character creation succeeds")
	var store_result := GameManager.create_new_store("Operations Test Store")
	_assert_true(bool(store_result.get("success", false)), "store creation succeeds")
	var store := GameManager.get_active_store()
	if store == null:
		_assert_true(false, "active store exists")
		return
	var category_result := GameManager.add_category_to_store("breakfast", ["P001"])
	_assert_true(bool(category_result.get("success", false)), "breakfast category can be configured")
	var category := GameManager.get_category("breakfast")
	var product := GameManager.get_product("P001")
	if category == null or product == null:
		_assert_true(false, "test category and product exist")
		return

	var initial_status := GameManager.get_category_staffing_status(store, category, 10)
	_assert_true(int(initial_status.scheduled) == 0 and int(initial_status.required) == 2,
		"breakfast requires two people and starts without scheduled staff")

	var owner_only_power := 0.85
	GameManager.player_state.supervising_store_id = store.id
	var owner_status := GameManager.get_category_staffing_status(store, category, 10)
	_assert_true(int(owner_status.scheduled) == 1,
		"supervising owner counts as one base worker")
	var owner_service := GameManager.get_product_service_seconds(category, product, owner_only_power)
	var owner_waste := GameManager.get_category_ingredient_consumption_multiplier(store, category, 10)

	var hire_result := GameManager.hire_employee("emp_004")
	_assert_true(bool(hire_result.get("success", false)), "matching breakfast employee can be hired")
	var schedule_result := GameManager.set_employee_work_hours("emp_004", [Vector2i(9, 17)])
	_assert_true(bool(schedule_result.get("success", false)), "matching employee can be scheduled")
	var staffed_status := GameManager.get_category_staffing_status(store, category, 10)
	var staffed_power := GameManager.get_category_staffing_power(store, category, 10)
	var staffed_service := GameManager.get_product_service_seconds(category, product, staffed_power)
	var staffed_waste := GameManager.get_category_ingredient_consumption_multiplier(store, category, 10)
	print("staffing: owner=%.2f service=%.1fs waste=x%.3f | staffed=%.2f service=%.1fs waste=x%.3f | people=%d/%d" % [owner_only_power, owner_service, owner_waste, staffed_power, staffed_service, staffed_waste, staffed_status.scheduled, staffed_status.required])
	_assert_true(int(staffed_status.scheduled) == int(staffed_status.required),
		"owner plus matching employee meets breakfast staffing recommendation")
	_assert_true(staffed_service < owner_service,
		"matching scheduled employee makes service faster")
	_assert_true(staffed_waste < owner_waste,
		"matching scheduled employee reduces preparation ingredient waste")


func _test_customer_flow_queue_and_inventory() -> void:
	var slow := CustomerSimulator.new()
	var fast := CustomerSimulator.new()
	slow.setup(0, 3600.0, 1.0, 120.0, 30.0, 10, 10.0, 2.0, 0.0)
	fast.setup(0, 3600.0, 1.0, 40.0, 30.0, 10, 10.0, 2.0, 0.0)
	for arrival in [0.0, 80.0, 160.0]:
		slow.process_arrival_at(arrival)
		fast.process_arrival_at(arrival)
	print("queue: slow served=%d abandoned=%d avg_wait=%.1fs | fast served=%d abandoned=%d avg_wait=%.1fs" % [slow.actual_orders, slow.rejected_queue_wait_count, slow.total_wait_seconds / maxf(1.0, slow.actual_orders), fast.actual_orders, fast.rejected_queue_wait_count, fast.total_wait_seconds / maxf(1.0, fast.actual_orders)])
	_assert_true(slow.rejected_queue_wait_count > 0,
		"slow service causes customers to abandon an overlong queue")
	_assert_true(fast.actual_orders == 3 and fast.rejected_queue_wait_count == 0,
		"faster service clears the same arrival flow without queue abandonment")

	var stock_limited := CustomerSimulator.new()
	stock_limited.setup(0, 3600.0, 1.0, 20.0, 300.0, 1, 10.0, 2.0, 0.0)
	stock_limited.process_arrival_at(0.0)
	stock_limited.process_arrival_at(60.0)
	_assert_true(stock_limited.actual_orders == 1 and stock_limited.rejected_inventory_count == 1,
		"insufficient raw materials reject orders independently of queue capacity")



func _test_shared_ingredient_reservation() -> void:
	var store := Store.new()
	store.set_ingredient_stock("flour", 1.0)
	var product := ProductData.new()
	product.recipe = [{"ingredient_id": "flour", "quantity": 1.0}]
	var reserve := store.try_reserve_product_ingredients.bind(product, 1, 1.0)
	var first_order := CustomerSimulator.new()
	var second_order := CustomerSimulator.new()
	first_order.setup(0, 3600.0, 1.0, 10.0, 300.0, 9999, 10.0, 2.0, 0.0, reserve)
	second_order.setup(0, 3600.0, 1.0, 10.0, 300.0, 9999, 10.0, 2.0, 0.0, reserve)
	first_order.process_arrival_at(10.0)
	second_order.process_arrival_at(20.0)
	_assert_true(first_order.actual_orders == 1 and second_order.rejected_inventory_count == 1 and is_zero_approx(store.get_ingredient_stock("flour")),
		"shared ingredient is atomically reserved by the first accepted order")


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
