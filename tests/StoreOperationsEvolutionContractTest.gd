extends Node

var passed := 0
var failed := 0

func _ready() -> void:
	_test_group_order_summary()
	_test_shared_category_queue()
	_test_category_order_stream_selects_product()
	_test_finite_market_allocation()
	_test_market_pool_prerequisites()
	_test_market_pool_allocation_is_order_independent()
	_test_store_overhead_breakdown()
	_test_periodic_demand_is_deterministic()
	_test_menu_preferences_have_stable_fallback()
	print("========== Store operations evolution: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)

func _expect(value: bool, label: String) -> void:
	if value:
		passed += 1
		print("PASS: " + label)
	else:
		failed += 1
		print("FAIL: " + label)

func _test_group_order_summary() -> void:
	var sim := CustomerSimulator.new()
	sim.setup(2, 3600.0, 0.0, 10.0, 300.0, 9, 10.0, 1.0, 0.2, Callable(), {"student": {"visitors": 2, "conversion_rate": 1.0}})
	sim.process_arrival_at(1.0)
	var summary: Dictionary = sim.group_summary.get("student", {})
	_expect(int(summary.get("visitors", 0)) == 1 and int(summary.get("actual_orders", 0)) == 1, "orders retain their population-group summary")

func _test_shared_category_queue() -> void:
	var category_service := CategoryServiceSimulator.new("coffee")
	var queue := category_service.get_shared_state()
	var first := CustomerSimulator.new()
	var second := CustomerSimulator.new()
	first.setup(0, 3600.0, 1.0, 120.0, 30.0, 9, 10.0, 1.0, 0.0, Callable(), {}, queue)
	second.setup(0, 3600.0, 1.0, 120.0, 30.0, 9, 10.0, 1.0, 0.0, Callable(), {}, queue)
	first.process_arrival_at(0.0)
	second.process_arrival_at(1.0)
	_expect(first.actual_orders == 1 and second.rejected_queue_wait_count == 1, "same-category products share one service queue")

func _test_store_overhead_breakdown() -> void:
	var result := SettlementResult.new()
	result.is_store_overhead = true
	result.lease_cost = 10.0
	result.category_occupancy_cost = 2.0
	result.operating_equipment_cost = 3.0
	result.storage_equipment_cost = 0.0
	result.scheduled_wage_cost = 4.0
	var summary := result.to_summary_dict()
	_expect(bool(summary.get("is_store_overhead", false))
		and is_equal_approx(float(summary.get("lease_cost", 0.0)), 10.0)
		and is_equal_approx(float(summary.get("category_occupancy_cost", 0.0)), 2.0)
		and is_equal_approx(float(summary.get("operating_equipment_cost", 0.0)), 3.0)
		and is_equal_approx(float(summary.get("scheduled_wage_cost", 0.0)), 4.0),
		"hourly store overhead retains its cost-source breakdown")

func _reserve_for_category_test() -> bool:
	return true

func _test_category_order_stream_selects_product() -> void:
	var product := ProductData.new()
	product.id = "stream_test"
	product.name = "Stream test"
	product.average_price = 12.0
	var service := CategoryServiceSimulator.new("coffee")
	service.setup("coffee", 1, {"student": {"visitors": 1, "conversion_rate": 1.0}}, [{
		"product": product, "profile": {"weight_by_group": {"student": 1.0}, "price_rejection_rate_by_group": {"student": 0.0}},
		"service_seconds": 10.0, "inventory_limit": 1, "unit_ingredient_cost": 2.0,
		"unit_utility_cost": 0.5, "reserve_ingredients": Callable(self, "_reserve_for_category_test"),
	}], 300.0)
	service.next_arrival_at = 1.0
	service.process_next_arrival_if_due(1.0)
	var ledger: CustomerSimulator = service.product_ledgers.get("stream_test", null)
	_expect(ledger != null and ledger.actual_orders == 1 and is_equal_approx(ledger.revenue, 12.0), "category order stream selects a product and writes its product ledger")

func _test_finite_market_allocation() -> void:
	var allocation := MarketAllocator.allocate_finite_pool(10, {"a": 3.0, "b": 1.0})
	var assigned := int(allocation.allocations.get("a", 0)) + int(allocation.allocations.get("b", 0))
	_expect(assigned <= 10 and int(allocation.allocations.get("a", 0)) > int(allocation.allocations.get("b", 0)), "finite market allocation caps total visitors and follows weights")

func _test_market_pool_prerequisites() -> void:
	var key_a := MarketAllocator.make_pool_key("city", "block", "student", "coffee", 2, 9)
	var key_b := MarketAllocator.make_pool_key("city", "block", "student", "coffee", 2, 9)
	var near := MarketAllocator.calculate_participant_weight({"is_operating": true, "offers_category": true, "distance": 10.0, "reputation": 80.0})
	var far := MarketAllocator.calculate_participant_weight({"is_operating": true, "offers_category": true, "distance": 900.0, "reputation": 20.0})
	var pool := MarketAllocator.describe_pool(20, 0.25, {"near": near, "far": far})
	var assigned := int(pool.allocations.get("near", 0)) + int(pool.allocations.get("far", 0))
	_expect(key_a == key_b and near > far and int(pool.external_competition_loss) == 5 and assigned <= int(pool.remaining_supply), "market pool key, competition deduction and participant weights are deterministic")


func _test_market_pool_allocation_is_order_independent() -> void:
	var first := MarketAllocator.describe_pool(11, 0.25, {"store_b": 1.0, "store_a": 1.0})
	var second := MarketAllocator.describe_pool(11, 0.25, {"store_a": 1.0, "store_b": 1.0})
	var first_total := int(first.allocations.get("store_a", 0)) + int(first.allocations.get("store_b", 0))
	_expect(first.allocations == second.allocations
		and first.external_competition_losses == second.external_competition_losses
		and first_total == int(first.remaining_supply), "shared market allocation is exact and independent from participant insertion order")

func _test_periodic_demand_is_deterministic() -> void:
	var block := BlockData.new()
	block.block_type = "school"
	var a := DemandPatternCalculator.get_group_multiplier(block, "student", 1, 17)
	var b := DemandPatternCalculator.get_group_multiplier(block, "student", 1, 17)
	var weekend := DemandPatternCalculator.get_group_multiplier(block, "student", 6, 17)
	_expect(is_equal_approx(a, b) and a > 1.0 and is_equal_approx(weekend, 1.0), "weekday school dismissal demand is deterministic and weekend-safe")

func _test_menu_preferences_have_stable_fallback() -> void:
	var category := CategoryData.new()
	category.id = "coffee"
	var product := ProductData.new()
	product.id = "unknown_product"
	var profile := CustomerPreferenceConfig.get_profile(category, product)
	_expect(CustomerPreferenceConfig.get_group_affinity(profile, "office_worker") > CustomerPreferenceConfig.get_group_affinity(profile, "worker"), "category defaults provide a stable product fallback")
