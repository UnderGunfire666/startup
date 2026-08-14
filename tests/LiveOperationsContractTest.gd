extends Node

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("========== Live Operations Contract Test ==========")
	_test_player_skills_are_multi_value_and_saved()
	_test_order_event_reports_completion_time()
	_test_presence_and_staffing_refresh_current_simulation()
	print("========== Test finished: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _test_player_skills_are_multi_value_and_saved() -> void:
	var player := PlayerState.new()
	_assert_true(player.add_work_skill("chef"), "player can learn a first work skill")
	_assert_true(player.add_work_skill("grill"), "player can learn more than one work skill")
	_assert_true(not player.add_work_skill("chef"), "duplicate player work skill is rejected")
	var restored := PlayerState.from_save_dict(player.to_save_dict())
	_assert_true(restored.has_work_skill("chef") and restored.has_work_skill("grill"), "player work skills survive save round trip")


func _test_order_event_reports_completion_time() -> void:
	var sim := CustomerSimulator.new()
	var event := {"purchased": false, "time": -1.0}
	sim.customer_event.connect(func(was_purchased: bool, _reason: String, time_seconds: float) -> void:
		event["purchased"] = was_purchased
		event["time"] = time_seconds
	)
	sim.setup(0, 3600.0, 1.0, 90.0, 300.0, 10, 10.0, 2.0, 0.0)
	sim.process_arrival_at(120.0)
	_assert_true(bool(event.get("purchased", false)), "customer event reports a completed sale")
	_assert_true(is_equal_approx(float(event.get("time", -1.0)), 210.0), "sale event time is service completion time, not arrival time")


func _test_presence_and_staffing_refresh_current_simulation() -> void:
	GameManager.start_new_game()
	var created: Dictionary = GameManager.create_character({
		"player_name": "Live Operations Tester", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": [],
	})
	_assert_true(bool(created.get("success", false)), "character creation succeeds")
	var store_result: Dictionary = GameManager.create_new_store("Live Operations Store")
	_assert_true(bool(store_result.get("success", false)), "store creation succeeds")
	var store := GameManager.get_active_store()
	var category := GameManager.get_category("breakfast")
	var product := GameManager.get_product("P001")
	if store == null or category == null or product == null:
		_assert_true(false, "test store, category and product exist")
		return

	store.is_open = true
	store.is_business_open = true
	var sim := CustomerSimulator.new()
	sim.setup(24, 3600.0, 1.0, 500.0, 300.0, 999, 10.0, 2.0, 0.0)
	GameManager.active_simulations = [{
		"store_id": store.id, "sim": sim, "category": category, "product": product,
		"product_count": 1, "params": {"visitors": 24},
	}]

	GameManager.set_player_store_presence(store, true)
	GameManager.refresh_active_store_staffing(store)
	var owner_service := sim.service_time_seconds
	_assert_true(owner_service > 0.0 and sim.arrival_rate_per_second > 0.0, "owner arrival immediately activates service and customer flow")

	GameManager.add_player_work_skill(category.required_staff)
	GameManager.refresh_active_store_staffing(store)
	_assert_true(sim.service_time_seconds < owner_service, "matching owner skill immediately improves service speed")

	var employee := StoreEmployee.new()
	employee.candidate_id = "live_test_employee"
	employee.skills.append(category.required_staff)
	employee.skill_level = 1.2
	employee.work_hour_ranges = [Vector2i(0, 24)]
	store.employees.append(employee)
	var skilled_owner_service := sim.service_time_seconds
	GameManager.refresh_active_store_staffing(store)
	_assert_true(sim.service_time_seconds < skilled_owner_service, "on-duty employee immediately improves active service speed")

	store.is_business_open = false
	GameManager.refresh_active_store_staffing(store)
	_assert_true(is_inf(sim.next_arrival_at) and is_zero_approx(sim.arrival_rate_per_second), "closing immediately stops future customer arrivals")
	store.is_business_open = true
	GameManager.refresh_active_store_staffing(store)
	_assert_true(sim.arrival_rate_per_second > 0.0 and not is_inf(sim.next_arrival_at), "reopening immediately resumes customer arrivals")
	GameManager.active_simulations.clear()


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
