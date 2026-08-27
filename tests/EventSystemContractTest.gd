extends Node

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	print("========== Event System Contract Test ==========")
	_test_research_notice_effect_cooldown_and_save()
	_test_research_chain_journal_and_skip()
	_test_landlord_terms_chain_and_contract()
	_test_npc_store_transfer_chain()
	_test_player_block_event_definition_and_effect()
	_test_store_operating_event_modifier()
	_test_store_disruption_event_modifiers()
	_test_block_activity_modifier_and_trade_area()
	_test_city_region_activity_modifier_and_trade_area()
	_test_storefront_capture_event()
	_test_player_scoped_event_context_and_effects()
	_test_event_history_and_active_modifier_queries()
	_test_store_awareness_save()
	_test_awareness_growth_sources()
	_test_destination_visitors()
	_test_decision_queue()
	_test_event_time_policy_and_dismissal()
	_test_automatic_store_decision_trigger()
	_test_store_interrupt()
	_test_road_exposure_lookup()
	_test_destination_road_distance()
	_test_temporary_modifier_expiry()
	print("========== Test finished: %d passed / %d failed ==========" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _test_research_notice_effect_cooldown_and_save() -> void:
	GameManager.start_new_game()
	var created: Dictionary = GameManager.create_character({
		"player_name": "Event Tester", "gender": "female", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": [],
	})
	_assert_true(bool(created.get("success", false)), "character creation succeeds")
	var block := GameManager.get_block("block_w_school")
	_assert_true(block != null, "research test block exists")
	if block == null:
		return
	GameManager.player_state.block_understanding[block.id] = 10.0
	var received := {"count": 0, "event_id": ""}
	EventManager.notice_raised.connect(func(event: ActiveGameEvent) -> void:
		received["count"] = int(received.get("count", 0)) + 1
		received["event_id"] = event.event_id
	)
	var definition: GameEventDefinition = EventManager.definitions.get("research_local_tip", null)
	_assert_true(definition != null, "research discovery definition is registered")
	if definition == null:
		return
	var event := EventManager._activate(definition, block.id)
	_assert_true(event != null and not event.instance_id.is_empty() and event.scope == GameEventDefinition.Scope.BLOCK, "research discovery creates a uniquely identified block event")
	_assert_true(_event_options_include_descriptions(event), "research choices retain their narrative descriptions when activated")
	_assert_true(EventManager.pending_decisions.size() == 1 and EventManager.resolve_decision(event.instance_id, "record"), "research event requires and resolves a player choice")
	_assert_true(_has_research_journal_entry(block.id, "record"), "recording a research event writes the selected path to discovery history")
	_assert_true(int(received.get("count", 0)) == 1 and str(received.get("event_id", "")) == "research_local_tip", "interactive event is emitted to the global event UI")
	_assert_true(EventManager.try_research_discovery(block.id) == null, "event cooldown prevents an immediate repeat roll")
	var save_data := EventManager.to_save_dict()
	EventManager.reset_for_new_game()
	EventManager.apply_save_dict(save_data)
	_assert_true(EventManager.event_history.size() == 1, "resolved event history survives save round trip")
	_assert_true(EventManager.event_history[0].resolution == "selected", "event resolution state survives save round trip")
	_assert_true(not EventManager.cooldown_until.is_empty(), "event cooldown survives save round trip")


func _test_temporary_modifier_expiry() -> void:
	EventManager.reset_for_new_game()
	TimeManager.reset()
	EventManager.add_temporary_modifier(GameEventDefinition.Scope.BLOCK, "test_block", "visitor_multiplier_add", 0.25, 1.0)
	_assert_true(is_equal_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.BLOCK, "test_block", "visitor_multiplier_add"), 0.25), "active temporary modifier contributes its configured value")
	TimeManager.total_game_seconds += 3601.0
	_assert_true(is_zero_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.BLOCK, "test_block", "visitor_multiplier_add")), "expired temporary modifier no longer contributes")


func _test_research_chain_journal_and_skip() -> void:
	GameManager.start_new_game()
	var created := GameManager.create_character({
		"player_name": "Journal Tester", "gender": "male", "age": 28,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": ["market_instinct"],
	})
	_assert_true(bool(created.get("success", false)), "research journal character creation succeeds")
	var block := GameManager.get_block("block_w_school")
	if block == null:
		_assert_true(false, "research journal test block exists")
		return
	GameManager.player_state.discovery_history.clear()
	EventManager.reset_for_new_game()
	var definition: GameEventDefinition = EventManager.definitions.get("research_local_tip", null)
	var trace_event := EventManager._activate(definition, block.id) if definition != null else null
	_assert_true(trace_event != null and EventManager.resolve_decision(trace_event.instance_id, "trace"), "trait research route can be resolved")
	_assert_true(_has_research_journal_entry(block.id, "trace") and _has_discovery_id("research_result:research_trace_result"), "research chain records both the selected route and its result")

	GameManager.player_state.discovery_history.clear()
	var dismissed_event := EventManager._activate(definition, block.id) if definition != null else null
	_assert_true(dismissed_event != null and EventManager.dismiss_decision(dismissed_event.instance_id), "research event can be skipped directly")
	_assert_true(GameManager.player_state.discovery_history.is_empty(), "skipping research writes no discovery journal entry")


func _test_npc_store_transfer_chain() -> void:
	GameManager.start_new_game()
	var created := GameManager.create_character({
		"player_name": "NPC Transfer Tester", "gender": "female", "age": 47,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": ["negotiator"],
	})
	_assert_true(bool(created.get("success", false)), "NPC-transfer character creation succeeds")
	_assert_true(not GameManager.npc_stores.is_empty(), "occupied storefronts create full NPC stores")
	if GameManager.npc_stores.is_empty():
		return
	var npc_store: Store = GameManager.npc_stores[0]
	_assert_true(npc_store.is_open and not npc_store.category_slots.is_empty() and not npc_store.employees.is_empty() and not npc_store.equipment.is_empty(), "seeded NPC store has an operable menu, staff, and equipment")
	var restored := Store.from_save_dict(npc_store.to_save_dict())
	_assert_true(restored.owner_kind == "npc" and restored.selected_storefront_id == npc_store.selected_storefront_id and not restored.facade_layout.is_empty(), "NPC store state survives a store save round trip")
	npc_store.transfer_state = "offered"
	npc_store.transfer_record = {"asking_price": 100.0}
	GameManager.player_state.cash = 1000.0
	var opening := EventManager.start_npc_transfer_chain(npc_store.id)
	_assert_true(opening != null and opening.event_id == "npc_transfer_opening", "transfer notice opens a two-step chain")
	_assert_true(opening != null and EventManager.resolve_decision(opening.instance_id, "press"), "negotiator route enters the transfer terms")
	var terms: ActiveGameEvent = EventManager.pending_decisions[0] if not EventManager.pending_decisions.is_empty() else null
	_assert_true(terms != null and terms.event_id == "npc_transfer_press", "transfer chain reaches its second decision")
	_assert_true(terms != null and EventManager.resolve_decision(terms.instance_id, "take"), "transfer can convert the NPC store to a player store")
	_assert_true(GameManager.get_store(npc_store.id) != null and GameManager.get_npc_store(npc_store.id) == null, "taken-over NPC store joins the player's store list")


func _test_landlord_terms_chain_and_contract() -> void:
	GameManager.start_new_game()
	var created := GameManager.create_character({
		"player_name": "Lease Tester", "gender": "female", "age": 47,
		"difficulty_id": "normal", "preset_id": "", "trait_ids": ["negotiator"],
	})
	_assert_true(bool(created.get("success", false)), "lease-chain character creation succeeds")
	var store_result := GameManager.create_new_store("Lease Test Store")
	_assert_true(bool(store_result.get("success", false)), "lease-chain store creation succeeds")
	if GameManager.all_storefronts.is_empty():
		_assert_true(false, "lease-chain storefront exists")
		return
	var storefront: StorefrontData = null
	for candidate in GameManager.all_storefronts:
		if not candidate.is_occupied:
			storefront = candidate
			break
	if storefront == null:
		_assert_true(false, "lease-chain empty storefront exists")
		return
	var occupied_storefront: StorefrontData = null
	for candidate in GameManager.all_storefronts:
		if candidate.is_occupied:
			occupied_storefront = candidate
			break
	_assert_true(occupied_storefront != null and not bool(GameManager.select_storefront(occupied_storefront.id).get("success", false)), "occupied storefront cannot be selected as a lease candidate")
	GameManager.advance_storefront_diligence(storefront.id, "initial_viewing")
	_assert_true(bool(GameManager.select_storefront(storefront.id).get("success", false)), "discovered empty storefront can be selected before deep inspection")
	EventManager.reset_for_new_game()
	var root := EventManager.start_landlord_terms_chain(GameManager.active_store_id)
	_assert_true(root != null and root.event_id == "landlord_terms_opening", "landlord negotiation starts the opening node")
	_assert_true(root != null and EventManager.resolve_decision(root.instance_id, "exchange"), "negotiator trait unlocks the exchange route")
	var terms: ActiveGameEvent = EventManager.pending_decisions[0] if not EventManager.pending_decisions.is_empty() else null
	_assert_true(terms != null and terms.event_id == "landlord_terms_exchange", "trait route reaches a second decision node")
	_assert_true(terms != null and EventManager.resolve_decision(terms.instance_id, "low_rent"), "second decision records a lease offer")
	var store := GameManager.store_state
	_assert_true(is_equal_approx(float(store.pending_lease_offer.get("rent_multiplier", 0.0)), 0.9) and int(store.pending_lease_offer.get("deposit_months", 0)) == 3, "low-rent offer stores its contract terms")
	var saved_store := Store.from_save_dict(store.to_save_dict())
	_assert_true(is_equal_approx(float(saved_store.pending_lease_offer.get("rent_multiplier", 0.0)), 0.9), "pending lease offer survives store save round trip")
	var cash_before := GameManager.player_state.cash
	var sign_result := GameManager.sign_selected_storefront()
	var expected_deposit := storefront.get_monthly_rent_yuan() * 0.9 * 3.0
	_assert_true(bool(sign_result.get("success", false)) and is_equal_approx(cash_before - GameManager.player_state.cash, expected_deposit), "signing deducts the negotiated deposit")
	_assert_true(is_equal_approx(store.lease_rent_multiplier, 0.9) and is_zero_approx(store.lease_free_rent_hours_remaining), "signing locks the rent multiplier and free-rent term")


func _test_store_operating_event_modifier() -> void:
	EventManager.reset_for_new_game()
	var definition: GameEventDefinition = EventManager.definitions.get("store_neighborhood_activity", null)
	_assert_true(definition != null and definition.scope == GameEventDefinition.Scope.STORE, "store operating event is registered with store scope")
	if definition == null:
		return
	var event := EventManager._activate(definition, "store_test_001", "store_test_001")
	_assert_true(event.store_id == "store_test_001" and event.target_id == "store_test_001", "store event retains its explicit store id")
	_assert_true(is_equal_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.STORE, "store_test_001", "natural_visitors_multiplier_add"), 0.20), "store event adds the configured temporary natural visitor modifier")


func _test_player_block_event_definition_and_effect() -> void:
	EventManager.reset_for_new_game()
	var block := GameManager.get_block("block_w_school")
	_assert_true(block != null, "player block event test block exists")
	if block == null:
		return
	GameManager.player_state.current_block_id = block.id
	GameManager.player_state.block_understanding[block.id] = 20.0
	var definition: GameEventDefinition = EventManager.definitions.get("block_street_observation", null)
	_assert_true(definition != null and definition.interaction == GameEventDefinition.Interaction.NOTICE, "player block event is registered as a non-blocking notice")
	if definition == null:
		return
	var event := EventManager._activate(definition, block.id)
	_assert_true(event != null and event.target_id == block.id, "player block event explicitly targets the current block")
	_assert_true(is_equal_approx(GameManager.get_block_research_progress(block.id, "competition"), 1.0), "player block event grants only its configured small competition insight")
	_assert_true(EventManager.try_player_block_event() == null, "player block event cooldown prevents immediate repetition")


func _test_store_disruption_event_modifiers() -> void:
	EventManager.reset_for_new_game()
	var definition: GameEventDefinition = EventManager.definitions.get("store_service_disruption", null)
	_assert_true(definition != null and definition.scope == GameEventDefinition.Scope.STORE, "store disruption event is registered with store scope")
	if definition == null:
		return
	var event := EventManager._activate(definition, "store_test_002", "store_test_002")
	_assert_true(not definition.message_variants.is_empty() and _event_uses_registered_message(event, definition), "recurring disruption snapshots one registered narrative variant")
	_assert_true(is_equal_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.STORE, "store_test_002", "service_time_multiplier_add"), 0.25), "disruption increases service time by its configured modifier")
	_assert_true(is_equal_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.STORE, "store_test_002", "conversion_rate_add"), -0.08), "disruption decreases conversion rate by its configured modifier")


func _test_block_activity_modifier_and_trade_area() -> void:
	EventManager.reset_for_new_game()
	var block := GameManager.get_block("block_w_school")
	var storefront := GameManager.get_storefront("sf_school_stationery")
	var category: CategoryData = GameManager.all_categories[0] if not GameManager.all_categories.is_empty() else null
	_assert_true(block != null and storefront != null and category != null, "block activity trade-area test data exists")
	if block == null or storefront == null or category == null:
		return
	var event := EventManager.try_block_activity_event(block.id, 0.0)
	_assert_true(event != null and event.scope == GameEventDefinition.Scope.BLOCK, "operating-area activity triggers a block-scoped event")
	_assert_true(is_equal_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.BLOCK, block.id, "natural_visitors_multiplier_add"), 0.25), "block activity applies its temporary natural-visitor modifier")
	_assert_true(is_equal_approx(float(GameManager._get_block_visitor_multipliers().get(block.id, 1.0)), 1.25), "active block modifier is forwarded to the operating traffic calculation")
	var city_region := GameManager.get_city_region(storefront.city_region_id)
	var baseline := TradeAreaCalculator.calculate_snapshot(storefront, category.id, "", 12, city_region, GameManager.all_blocks)
	var multipliers: Dictionary = {}
	for map_block in GameManager.all_blocks:
		multipliers[map_block.id] = 1.25
	var boosted := TradeAreaCalculator.calculate_snapshot(storefront, category.id, "", 12, city_region, GameManager.all_blocks, false, TradeAreaCalculator.DEFAULT_MAX_RADIUS, multipliers)
	_assert_true(boosted.total_effective_audience > baseline.total_effective_audience, "block visitor modifiers increase trade-area natural traffic without changing static map data")
	_assert_true(EventManager.try_block_activity_event(block.id, 0.0) == null, "block activity respects its cooldown")


func _test_city_region_activity_modifier_and_trade_area() -> void:
	EventManager.reset_for_new_game()
	var storefront := GameManager.get_storefront("sf_school_stationery")
	var category: CategoryData = GameManager.all_categories[0] if not GameManager.all_categories.is_empty() else null
	_assert_true(storefront != null and category != null, "city-region activity trade-area test data exists")
	if storefront == null or category == null:
		return
	var event := EventManager.try_city_region_activity_event(storefront.city_region_id, 0.0)
	_assert_true(event != null and event.scope == GameEventDefinition.Scope.CITY_REGION, "operating city region can trigger a region-scoped event")
	_assert_true(is_equal_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.CITY_REGION, storefront.city_region_id, "natural_visitors_multiplier_add"), 0.15), "city-region activity applies its temporary natural-visitor modifier")
	_assert_true(is_equal_approx(GameManager._get_city_region_visitor_multiplier(storefront.city_region_id), 1.15), "active city-region modifier is forwarded to the operating traffic calculation")
	_assert_true(is_equal_approx(GameManager._get_store_awareness_gain_multiplier(null, storefront), 1.25), "city-region activity also accelerates operating awareness growth")
	var city_region := GameManager.get_city_region(storefront.city_region_id)
	var baseline := TradeAreaCalculator.calculate_snapshot(storefront, category.id, "", 12, city_region, GameManager.all_blocks)
	var boosted := TradeAreaCalculator.calculate_snapshot(storefront, category.id, "", 12, city_region, GameManager.all_blocks, false, TradeAreaCalculator.DEFAULT_MAX_RADIUS, {}, 1.15)
	_assert_true(boosted.total_effective_audience > baseline.total_effective_audience, "city-region visitor modifier increases every local block contribution")


func _test_storefront_capture_event() -> void:
	EventManager.reset_for_new_game()
	var storefront := GameManager.get_storefront("sf_school_stationery")
	_assert_true(storefront != null, "storefront capture event test data exists")
	if storefront == null:
		return
	var event := EventManager.try_storefront_event(storefront.id, 0.0)
	_assert_true(event != null and event.scope == GameEventDefinition.Scope.STOREFRONT, "operating storefront can trigger a storefront-scoped event")
	_assert_true(is_equal_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.STOREFRONT, storefront.id, "capture_multiplier_add"), -0.25), "storefront obstruction applies its temporary capture modifier")
	var baseline := SettlementEngine._calc_base_visitors_from_trade_area(_make_capture_test_trade_area(), storefront, GameManager.all_categories[0])
	var obstructed: StorefrontData = storefront.duplicate()
	obstructed.capture_modifier = storefront.capture_modifier * 0.75
	var reduced := SettlementEngine._calc_base_visitors_from_trade_area(_make_capture_test_trade_area(), obstructed, GameManager.all_categories[0])
	_assert_true(reduced < baseline, "storefront capture modifier reduces visitors without changing static traffic data")
	_assert_true(EventManager.try_storefront_event(storefront.id, 0.0) == null, "storefront event respects its cooldown")


func _test_player_scoped_event_context_and_effects() -> void:
	EventManager.reset_for_new_game()
	var block := GameManager.get_block("block_w_school")
	_assert_true(block != null, "player event context test data exists")
	if block == null:
		return
	var saved_seconds := TimeManager.total_game_seconds
	var saved_action: CurrentActionState = ScheduleManager.current_action
	var saved_energy := GameManager.player_state.energy
	var saved_stress := GameManager.player_state.stress
	GameManager.player_state.current_block_id = block.id
	GameManager.player_state.energy = 50.0
	GameManager.player_state.stress = 30.0
	TimeManager.total_game_seconds = floor(saved_seconds / TimeManager.DAY_SECONDS) * TimeManager.DAY_SECONDS + 12.0 * 3600.0
	ScheduleManager.current_action = CurrentActionState.new()
	ScheduleManager.current_action.action_id = "region_research"
	ScheduleManager.current_action.is_active = true
	var event := EventManager.try_player_personal_event(0.0)
	_assert_true(event != null and event.scope == GameEventDefinition.Scope.PLAYER, "eligible research context triggers a player-scoped event")
	_assert_true(is_equal_approx(GameManager.player_state.energy, 58.0) and is_equal_approx(GameManager.player_state.stress, 27.0), "player-scoped event applies bounded energy and stress effects")
	EventManager.reset_for_new_game()
	ScheduleManager.current_action = null
	_assert_true(EventManager.try_player_personal_event(0.0) == null, "player event requires its configured current action")
	ScheduleManager.current_action = CurrentActionState.new()
	ScheduleManager.current_action.action_id = "region_research"
	ScheduleManager.current_action.is_active = true
	TimeManager.total_game_seconds = floor(TimeManager.total_game_seconds / TimeManager.DAY_SECONDS) * TimeManager.DAY_SECONDS + 8.0 * 3600.0
	_assert_true(EventManager.try_player_personal_event(0.0) == null, "player event respects its configured time window")
	TimeManager.total_game_seconds = saved_seconds
	ScheduleManager.current_action = saved_action
	GameManager.player_state.energy = saved_energy
	GameManager.player_state.stress = saved_stress


func _test_event_history_and_active_modifier_queries() -> void:
	EventManager.reset_for_new_game()
	var event := ActiveGameEvent.new()
	event.event_id = "history_test"
	event.scope = GameEventDefinition.Scope.PLAYER
	EventManager._append_history(event)
	_assert_true(EventManager.get_recent_events(1, GameEventDefinition.Scope.PLAYER).size() == 1, "event history query returns recent events by scope")
	_assert_true(EventManager.get_recent_events(0).is_empty(), "event history query accepts a zero result limit")
	EventManager.add_temporary_modifier(GameEventDefinition.Scope.PLAYER, "player", "test_modifier", 0.5, 1.0)
	_assert_true(EventManager.get_active_modifiers(GameEventDefinition.Scope.PLAYER, "player").size() == 1, "active modifier query returns only matching live modifiers")
	for index in range(EventManager.MAX_EVENT_HISTORY + 5):
		var history_event := ActiveGameEvent.new()
		history_event.event_id = "history_cap_%d" % index
		EventManager._append_history(history_event)
	_assert_true(EventManager.event_history.size() == EventManager.MAX_EVENT_HISTORY, "event history remains bounded for long-running saves")


func _make_capture_test_trade_area() -> TradeAreaSnapshot:
	var trade_area := TradeAreaSnapshot.new()
	trade_area.total_effective_audience = 1000.0
	return trade_area

func _test_store_awareness_save() -> void:
	var store := Store.new()
	store.awareness_by_block["block_test"] = 4.5
	store.last_awareness_update = {"day": 3, "coverage_ratios": {"block_test": 0.5}, "total_gain": 0.25}
	var restored := Store.from_save_dict(store.to_save_dict())
	_assert_true(is_equal_approx(float(restored.awareness_by_block.get("block_test", 0.0)), 4.5), "store awareness by block survives save round trip")
	_assert_true(int(restored.last_awareness_update.get("day", 0)) == 3 and is_equal_approx(float(restored.last_awareness_update.get("total_gain", 0.0)), 0.25), "latest awareness update snapshot survives save round trip")


func _test_awareness_growth_sources() -> void:
	var storefront := GameManager.get_storefront("sf_school_stationery")
	_assert_true(storefront != null, "awareness growth test storefront exists")
	if storefront == null:
		return
	var local_block := GameManager._get_block_for_storefront(storefront)
	_assert_true(local_block != null, "awareness growth test storefront belongs to a block")
	if local_block == null:
		return
	var store := Store.new()
	var exposure_snapshot := GameManager._apply_store_awareness_growth(store, storefront, [], 0)
	var exposure_awareness := float(store.awareness_by_block.get(local_block.id, 0.0))
	_assert_true(exposure_awareness > 0.0, "road exposure grows local awareness even without orders")
	_assert_true(float(exposure_snapshot.get("exposure_base_gain", 0.0)) > 0.0 and is_zero_approx(float(exposure_snapshot.get("word_of_mouth_base_gain", -1.0))), "awareness snapshot separates exposure from zero-order word of mouth")
	var result := SettlementResult.new()
	result.is_open = true
	result.actual_orders = 10
	result.average_queue_wait_seconds = 0.0
	result.reputation_delta = 0.4
	var word_of_mouth_snapshot := GameManager._apply_store_awareness_growth(store, storefront, [result], result.actual_orders)
	_assert_true(float(store.awareness_by_block.get(local_block.id, 0.0)) > exposure_awareness, "completed orders add word-of-mouth awareness")
	_assert_true(float(word_of_mouth_snapshot.get("word_of_mouth_base_gain", 0.0)) > 0.0 and not word_of_mouth_snapshot.get("coverage_ratios", {}).is_empty(), "awareness snapshot records covered blocks and completed-order word of mouth")
	var another_block_id := ""
	for block in GameManager.all_blocks:
		if block.id != local_block.id:
			another_block_id = block.id
			break
	_assert_true(float(store.awareness_by_block.get(another_block_id, 0.0)) > 0.0, "word of mouth spreads awareness beyond the storefront block")

func _test_destination_visitors() -> void:
	var block := GameManager.get_block("block_w_school")
	_assert_true(block != null, "destination visitor test block exists")
	if block == null:
		return
	var outside_block: BlockData = null
	for candidate in GameManager.all_blocks:
		if candidate.city_region_id == block.city_region_id and candidate.id != block.id:
			outside_block = candidate
			break
	_assert_true(outside_block != null, "destination visitor test has another block in the same city")
	if outside_block == null:
		return
	var store := Store.new()
	store.reputation = 80.0
	store.awareness_by_block[block.id] = 100.0
	store.awareness_by_block[outside_block.id] = 100.0
	var storefront := StorefrontData.new()
	storefront.map_position = block.center_position
	storefront.city_region_id = block.city_region_id
	_assert_true(GameManager.get_destination_visitors(store, storefront, 1.0) > 0, "awareness and reputation create destination visitors")
	var sources := GameManager.get_destination_visitor_sources(store, storefront)
	var excludes_local := true
	for source in sources:
		if str(source.get("block_id", "")) == block.id:
			excludes_local = false
	_assert_true(excludes_local, "destination visitors exclude the storefront's own block")
	store.reputation = 0.0
	_assert_true(GameManager.get_destination_visitors(store, storefront, 1.0) == 0, "zero reputation prevents destination visitors")

func _test_decision_queue() -> void:
	EventManager.reset_for_new_game()
	var definition: GameEventDefinition = EventManager.definitions.get("store_activity_partnership", null)
	_assert_true(definition != null, "store activity partnership decision is registered")
	if definition == null:
		return
	_assert_true(_definition_options_include_descriptions(definition), "partnership choices define narrative descriptions")
	var event := EventManager._activate(definition, "store_decision_test", "store_decision_test")
	_assert_true(EventManager.pending_decisions.size() == 1, "decision event enters pending queue")
	_assert_true(EventManager.resolve_decision("store_activity_partnership", "accept"), "decision option can be resolved")
	_assert_true(EventManager.pending_decisions.is_empty() and EventManager.event_history.size() == 1, "resolved decision moves to event history")
	_assert_true(EventManager.get_modifier_total(GameEventDefinition.Scope.STORE, "store_decision_test", "natural_visitors_multiplier_add") > 0.0, "accepted partnership applies its store modifier")


func _test_event_time_policy_and_dismissal() -> void:
	EventManager.reset_for_new_game()
	TimeManager.set_speed(TimeManager.Speed.X5)
	var decision: GameEventDefinition = EventManager.definitions.get("store_activity_partnership", null)
	_assert_true(decision != null, "dismissal test decision is registered")
	if decision == null:
		return
	var event := EventManager._activate(decision, "store_dismiss_test", "store_dismiss_test")
	_assert_true(TimeManager.speed == TimeManager.Speed.PAUSED, "decision activation pauses time")
	_assert_true(EventManager.dismiss_decision(event.instance_id), "pending decision can be dismissed")
	_assert_true(event.resolution == "dismissed" and EventManager.pending_decisions.is_empty(), "dismissed decision records its distinct resolution")
	_assert_true(TimeManager.speed == TimeManager.Speed.X5 and is_zero_approx(EventManager.get_modifier_total(GameEventDefinition.Scope.STORE, "store_dismiss_test", "natural_visitors_multiplier_add")), "dismissing a decision restores speed without applying option effects")

	TimeManager.set_speed(TimeManager.Speed.PAUSED)
	var notice: GameEventDefinition = EventManager.definitions.get("store_neighborhood_activity", null)
	_assert_true(notice != null, "time policy notice is registered")
	if notice != null:
		EventManager._activate(notice, "store_notice_test", "store_notice_test")
		_assert_true(TimeManager.speed == TimeManager.Speed.X1, "non-interactive notice switches time to one-times speed")


func _test_automatic_store_decision_trigger() -> void:
	EventManager.reset_for_new_game()
	TimeManager.reset()
	var store := Store.new()
	store.id = "store_auto_decision_test"
	store.is_open = true
	store.is_business_open = true
	var closed_store := Store.new()
	closed_store.id = "store_closed_decision_test"
	_assert_true(EventManager.try_store_operating_event_for_store(closed_store, 0.0) == null, "store decision cannot trigger before the store opens")
	var event := EventManager.try_store_operating_event_for_store(store, 0.0)
	_assert_true(event != null and event.event_id == "store_activity_partnership", "operating store can naturally trigger the partnership decision")
	_assert_true(EventManager.pending_decisions.size() == 1, "naturally triggered decision enters the store pending queue")
	var save_data := EventManager.to_save_dict()
	EventManager.reset_for_new_game()
	EventManager.apply_save_dict(save_data)
	_assert_true(EventManager.pending_decisions.size() == 1 and EventManager.pending_decisions[0].store_id == store.id, "pending operating decision survives save round trip")
	_assert_true(EventManager.try_store_operating_event_for_store(store, 0.0) == null, "store with a pending decision cannot receive another operating event")
	_assert_true(EventManager.resolve_decision("store_activity_partnership", "decline"), "naturally triggered decision can be resolved")
	TimeManager.total_game_seconds += 3601.0
	_assert_true(EventManager.try_store_operating_event_for_store(store, 0.0) == null, "resolved decision respects its cooldown before it can recur")


func _test_store_interrupt() -> void:
	EventManager.reset_for_new_game()
	TimeManager.reset()
	TimeManager.set_speed(TimeManager.Speed.X1)
	var store := Store.new()
	store.id = "store_interrupt_test"
	store.is_open = true
	store.is_business_open = true
	var event := EventManager.try_store_operating_event_for_store(store, 0.17)
	_assert_true(event != null and event.interaction == GameEventDefinition.Interaction.INTERRUPT, "operating store can trigger an interrupt event")
	_assert_true(TimeManager.speed == TimeManager.Speed.PAUSED and EventManager.pending_interrupts.size() == 1, "interrupt pauses time and enters the pending queue")
	var save_data := EventManager.to_save_dict()
	EventManager.reset_for_new_game()
	TimeManager.set_speed(TimeManager.Speed.X1)
	EventManager.apply_save_dict(save_data)
	_assert_true(EventManager.pending_interrupts.size() == 1 and TimeManager.speed == TimeManager.Speed.PAUSED, "pending interrupt survives save round trip and keeps time paused")
	_assert_true(EventManager.resolve_interrupt("store_equipment_failure"), "interrupt can be acknowledged")
	_assert_true(EventManager.pending_interrupts.is_empty() and EventManager.event_history.back().event_id == "store_equipment_failure", "acknowledged interrupt moves to event history")

func _test_road_exposure_lookup() -> void:
	var storefront := GameManager.get_storefront("sf_school_stationery")
	_assert_true(storefront != null, "road exposure test storefront exists")
	if storefront == null:
		return
	_assert_true(GameManager.get_storefront_road_exposure(storefront) > 0.0, "storefront reads exposure from its road segment")

func _test_destination_road_distance() -> void:
	var block := GameManager.get_block("block_w_school")
	var storefront := GameManager.get_storefront("sf_school_stationery")
	_assert_true(block != null and storefront != null, "road distance test data exists")
	if block != null and storefront != null:
		_assert_true(GameManager.get_block_to_storefront_road_distance(block, storefront) > 0.0, "destination distance resolves through the road graph")


func _event_options_include_descriptions(event: ActiveGameEvent) -> bool:
	if event == null:
		return false
	for option in event.options:
		if str(option.get("description", "")).strip_edges().is_empty():
			return false
	return not event.options.is_empty()


func _definition_options_include_descriptions(definition: GameEventDefinition) -> bool:
	if definition == null:
		return false
	for option in definition.options:
		if str(option.get("description", "")).strip_edges().is_empty():
			return false
	return not definition.options.is_empty()


func _event_uses_registered_message(event: ActiveGameEvent, definition: GameEventDefinition) -> bool:
	if event == null or event.message.is_empty():
		return false
	return event.message == definition.message or definition.message_variants.has(event.message)


func _has_research_journal_entry(block_id: String, option_id: String) -> bool:
	for record in GameManager.player_state.discovery_history:
		if str(record.get("block_id", "")) == block_id and str(record.get("discovery_id", "")) == "research_event:research_local_tip" and str(record.get("option_id", "")) == option_id:
			return true
	return false


func _has_discovery_id(discovery_id: String) -> bool:
	for record in GameManager.player_state.discovery_history:
		if str(record.get("discovery_id", "")) == discovery_id:
			return true
	return false


func _assert_true(condition: bool, message: String) -> void:
	if condition:
		passed += 1
		print("PASS: " + message)
	else:
		failed += 1
		print("FAIL: " + message)
