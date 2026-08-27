extends Node

signal notice_raised(event: ActiveGameEvent)
signal decision_raised(event: ActiveGameEvent)
signal interrupt_raised(event: ActiveGameEvent)
signal event_finalized(event: ActiveGameEvent)

const RESEARCH_DISCOVERY_CHANCE_PER_HOUR: float = 0.25
const PLAYER_BLOCK_EVENT_CHANCE_PER_HOUR: float = 0.15
const BLOCK_ACTIVITY_EVENT_CHANCE_PER_HOUR: float = 0.08
const CITY_REGION_ACTIVITY_EVENT_CHANCE_PER_HOUR: float = 0.03
const STOREFRONT_EVENT_CHANCE_PER_HOUR: float = 0.03
const STORE_DECISION_CHANCE_PER_HOUR: float = 0.04
const STORE_OPERATING_EVENT_CHANCE_PER_HOUR: float = 0.12
const STORE_INTERRUPT_CHANCE_PER_HOUR: float = 0.02
const STORE_DISRUPTION_EVENT_CHANCE_PER_HOUR: float = 0.08
const PLAYER_PERSONAL_EVENT_CHANCE_PER_HOUR: float = 0.10
const MAX_EVENT_HISTORY: int = 120

var definitions: Dictionary = {}
var event_history: Array[ActiveGameEvent] = []
var cooldown_until: Dictionary = {}
var last_roll_hour_by_key: Dictionary = {}
var temporary_modifiers: Array[TemporaryModifier] = []
var pending_decisions: Array[ActiveGameEvent] = []
var pending_interrupts: Array[ActiveGameEvent] = []
var _next_instance_sequence := 0

func _ready() -> void:
	_register_research_discoveries()
	_register_player_block_events()
	_register_player_personal_events()
	_register_block_activity_events()
	_register_city_region_activity_events()
	_register_storefront_events()
	_register_store_operating_events()
	_register_landlord_terms_chain()
	_register_npc_transfer_chain()
	TimeManager.hour_advanced.connect(_on_hour_advanced)

func reset_for_new_game() -> void:
	event_history.clear()
	cooldown_until.clear()
	last_roll_hour_by_key.clear()
	temporary_modifiers.clear()
	pending_decisions.clear()
	pending_interrupts.clear()
	_next_instance_sequence = 0
	BlockDiscoveryManager.reset_for_new_game()


## Discoveries own their permanent history in PlayerState. This only forwards a
## lightweight notice through the existing UI notification channel.
func raise_discovery_notice(title: String, message: String, block_id: String) -> ActiveGameEvent:
	var event := ActiveGameEvent.new()
	event.event_id = "block_discovery"
	_next_instance_sequence += 1
	event.instance_id = "%s:%d" % [event.event_id, _next_instance_sequence]
	event.target_id = block_id
	event.title = title
	event.message = message
	event.started_game_seconds = TimeManager.total_game_seconds
	_append_history(event)
	TimeManager.set_speed(TimeManager.Speed.X1)
	notice_raised.emit(event)
	return event

func try_research_discovery(block_id: String, focus_id: String = "population") -> ActiveGameEvent:
	var block := GameManager.get_block(block_id)
	if block == null:
		return null
	var definition: GameEventDefinition = definitions.get("research_local_tip", null)
	if definition == null or GameManager.get_block_research_progress(block_id, focus_id) < definition.minimum_understanding:
		return null
	var now_hour: int = int(floor(TimeManager.total_game_seconds / 3600.0))
	var roll_key := definition.id + ":" + block_id
	if int(last_roll_hour_by_key.get(roll_key, -1)) == now_hour:
		return null
	last_roll_hour_by_key[roll_key] = now_hour
	if float(cooldown_until.get(roll_key, 0.0)) > TimeManager.total_game_seconds or randf() > RESEARCH_DISCOVERY_CHANCE_PER_HOUR:
		return null
	return _activate(definition, block_id)


func start_landlord_terms_chain(store_id: String) -> ActiveGameEvent:
	var store := GameManager.get_store(store_id)
	if store == null or store.selected_storefront_id.is_empty() or not store.pending_lease_offer.is_empty():
		return null
	var definition: GameEventDefinition = definitions.get("landlord_terms_opening", null)
	if definition == null:
		return null
	return _activate(definition, store.id, store.id, "", "", {"storefront_id": store.selected_storefront_id})


func start_npc_transfer_chain(npc_store_id: String) -> ActiveGameEvent:
	var store := GameManager.get_npc_store(npc_store_id)
	if store == null or store.transfer_state != "offered":
		return null
	var definition: GameEventDefinition = definitions.get("npc_transfer_opening", null)
	if definition == null:
		return null
	return _activate(definition, store.selected_storefront_id, "", "", "npc_transfer", {"npc_store_id": store.id, "storefront_id": store.selected_storefront_id})


func has_pending_landlord_terms_for_store(store_id: String) -> bool:
	for event in pending_decisions:
		if event.store_id == store_id and event.chain_id == "landlord_terms":
			return true
	return false


func try_player_block_event() -> ActiveGameEvent:
	var block_id := GameManager.player_state.current_block_id
	var block := GameManager.get_block(block_id)
	if block == null:
		return null
	var definition: GameEventDefinition = definitions.get("block_street_observation", null)
	if definition == null or not _matches_context(definition, block):
		return null
	var now_hour: int = int(floor(TimeManager.total_game_seconds / 3600.0))
	var roll_key := definition.id + ":" + block_id
	if int(last_roll_hour_by_key.get(roll_key, -1)) == now_hour:
		return null
	last_roll_hour_by_key[roll_key] = now_hour
	if float(cooldown_until.get(roll_key, 0.0)) > TimeManager.total_game_seconds or randf() > PLAYER_BLOCK_EVENT_CHANCE_PER_HOUR:
		return null
	return _activate(definition, block_id)


func try_player_personal_event(roll: float = -1.0) -> ActiveGameEvent:
	var block := GameManager.get_block(GameManager.player_state.current_block_id)
	var definition: GameEventDefinition = definitions.get("player_local_refreshment", null)
	if block == null or definition == null or not _matches_context(definition, block):
		return null
	var selected_roll := randf() if roll < 0.0 else clampf(roll, 0.0, 1.0)
	if selected_roll > PLAYER_PERSONAL_EVENT_CHANCE_PER_HOUR:
		return null
	var now_hour: int = int(floor(TimeManager.total_game_seconds / 3600.0))
	var roll_key := definition.id + ":player"
	if int(last_roll_hour_by_key.get(roll_key, -1)) == now_hour:
		return null
	last_roll_hour_by_key[roll_key] = now_hour
	if float(cooldown_until.get(roll_key, 0.0)) > TimeManager.total_game_seconds:
		return null
	return _activate(definition, "player")


func try_store_operating_events() -> void:
	var processed_block_ids: Dictionary = {}
	var processed_city_region_ids: Dictionary = {}
	var processed_storefront_ids: Dictionary = {}
	for store in GameManager.get_open_stores():
		if store == null or not store.is_business_open:
			continue
		var storefront := GameManager.get_storefront(store.selected_storefront_id)
		if storefront != null and not storefront.city_region_id.is_empty() and not processed_city_region_ids.has(storefront.city_region_id):
			processed_city_region_ids[storefront.city_region_id] = true
			try_city_region_activity_event(storefront.city_region_id)
		if storefront != null and not processed_storefront_ids.has(storefront.id):
			processed_storefront_ids[storefront.id] = true
			try_storefront_event(storefront.id)
		var block: BlockData = GameManager._get_block_for_storefront(storefront) if storefront != null else null
		if block != null and not processed_block_ids.has(block.id):
			processed_block_ids[block.id] = true
			try_block_activity_event(block.id)
		try_store_operating_event_for_store(store)


func try_block_activity_event(block_id: String, roll: float = -1.0) -> ActiveGameEvent:
	var block := GameManager.get_block(block_id)
	var definition: GameEventDefinition = definitions.get("block_local_activity", null)
	if block == null or definition == null:
		return null
	if not definition.allowed_block_types.is_empty() and not definition.allowed_block_types.has(block.block_type):
		return null
	var selected_roll := randf() if roll < 0.0 else clampf(roll, 0.0, 1.0)
	if selected_roll > BLOCK_ACTIVITY_EVENT_CHANCE_PER_HOUR:
		return null
	var now_hour: int = int(floor(TimeManager.total_game_seconds / 3600.0))
	var roll_key := definition.id + ":" + block.id
	if int(last_roll_hour_by_key.get(roll_key, -1)) == now_hour:
		return null
	last_roll_hour_by_key[roll_key] = now_hour
	if float(cooldown_until.get(roll_key, 0.0)) > TimeManager.total_game_seconds:
		return null
	return _activate(definition, block.id)


func try_city_region_activity_event(city_region_id: String, roll: float = -1.0) -> ActiveGameEvent:
	var city_region := GameManager.get_city_region(city_region_id)
	var definition: GameEventDefinition = definitions.get("city_region_commercial_festival", null)
	if city_region == null or definition == null:
		return null
	var selected_roll := randf() if roll < 0.0 else clampf(roll, 0.0, 1.0)
	if selected_roll > CITY_REGION_ACTIVITY_EVENT_CHANCE_PER_HOUR:
		return null
	var now_hour: int = int(floor(TimeManager.total_game_seconds / 3600.0))
	var roll_key := definition.id + ":" + city_region.id
	if int(last_roll_hour_by_key.get(roll_key, -1)) == now_hour:
		return null
	last_roll_hour_by_key[roll_key] = now_hour
	if float(cooldown_until.get(roll_key, 0.0)) > TimeManager.total_game_seconds:
		return null
	return _activate(definition, city_region.id)


func try_storefront_event(storefront_id: String, roll: float = -1.0) -> ActiveGameEvent:
	var storefront := GameManager.get_storefront(storefront_id)
	var definition: GameEventDefinition = definitions.get("storefront_visibility_obstruction", null)
	if storefront == null or definition == null:
		return null
	var selected_roll := randf() if roll < 0.0 else clampf(roll, 0.0, 1.0)
	if selected_roll > STOREFRONT_EVENT_CHANCE_PER_HOUR:
		return null
	var now_hour: int = int(floor(TimeManager.total_game_seconds / 3600.0))
	var roll_key := definition.id + ":" + storefront.id
	if int(last_roll_hour_by_key.get(roll_key, -1)) == now_hour:
		return null
	last_roll_hour_by_key[roll_key] = now_hour
	if float(cooldown_until.get(roll_key, 0.0)) > TimeManager.total_game_seconds:
		return null
	return _activate(definition, storefront.id)


func try_store_operating_event_for_store(store: Store, roll: float = -1.0) -> ActiveGameEvent:
	if store == null or not store.is_open or not store.is_business_open or _has_pending_decision_for_store(store.id) or _has_pending_interrupt_for_store(store.id):
		return null
	var selected_roll := randf() if roll < 0.0 else clampf(roll, 0.0, 1.0)
	var definition: GameEventDefinition = null
	if selected_roll <= STORE_DECISION_CHANCE_PER_HOUR:
		definition = definitions.get("store_activity_partnership", null)
	elif selected_roll <= STORE_DECISION_CHANCE_PER_HOUR + STORE_OPERATING_EVENT_CHANCE_PER_HOUR:
		definition = definitions.get("store_neighborhood_activity", null)
	elif selected_roll <= STORE_DECISION_CHANCE_PER_HOUR + STORE_OPERATING_EVENT_CHANCE_PER_HOUR + STORE_INTERRUPT_CHANCE_PER_HOUR:
		definition = definitions.get("store_equipment_failure", null)
	elif selected_roll <= STORE_DECISION_CHANCE_PER_HOUR + STORE_OPERATING_EVENT_CHANCE_PER_HOUR + STORE_INTERRUPT_CHANCE_PER_HOUR + STORE_DISRUPTION_EVENT_CHANCE_PER_HOUR:
		definition = definitions.get("store_service_disruption", null)
	if definition == null:
		return null
	var now_hour: int = int(floor(TimeManager.total_game_seconds / 3600.0))
	var roll_key := definition.id + ":" + store.id
	if int(last_roll_hour_by_key.get(roll_key, -1)) == now_hour:
		return null
	last_roll_hour_by_key[roll_key] = now_hour
	if float(cooldown_until.get(roll_key, 0.0)) > TimeManager.total_game_seconds:
		return null
	return _activate(definition, store.id, store.id)


func _has_pending_decision_for_store(store_id: String) -> bool:
	for event in pending_decisions:
		if event.store_id == store_id:
			return true
	return false


func _has_pending_interrupt_for_store(store_id: String) -> bool:
	for event in pending_interrupts:
		if event.store_id == store_id:
			return true
	return false

func _activate(definition: GameEventDefinition, target_id: String, store_id: String = "", parent_instance_id: String = "", chain_id: String = "", context: Dictionary = {}) -> ActiveGameEvent:
	var event := ActiveGameEvent.new()
	event.event_id = definition.id
	_next_instance_sequence += 1
	event.instance_id = "%s:%d" % [definition.id, _next_instance_sequence]
	event.chain_id = chain_id if not chain_id.is_empty() else (definition.chain_id if not definition.chain_id.is_empty() else definition.id)
	event.node_id = definition.node_id if not definition.node_id.is_empty() else definition.id
	event.parent_instance_id = parent_instance_id
	event.scope = definition.scope
	event.interaction = definition.interaction
	event.target_id = target_id
	event.store_id = store_id
	event.context = context.duplicate(true)
	event.title = definition.title
	event.message = _select_event_message(definition)
	event.started_game_seconds = TimeManager.total_game_seconds
	event.effects = definition.effects.duplicate(true)
	event.options = _snapshot_options(definition.options, event.context)
	event.resume_speed = TimeManager.speed if TimeManager.speed != TimeManager.Speed.PAUSED else TimeManager.Speed.X1
	if event.interaction == GameEventDefinition.Interaction.DECISION:
		pending_decisions.append(event)
		TimeManager.set_speed(TimeManager.Speed.PAUSED)
		decision_raised.emit(event)
	elif event.interaction == GameEventDefinition.Interaction.INTERRUPT:
		EventEffectResolver.apply(event)
		pending_interrupts.append(event)
		TimeManager.set_speed(TimeManager.Speed.PAUSED)
		interrupt_raised.emit(event)
	else:
		EventEffectResolver.apply(event)
		_append_history(event)
		TimeManager.set_speed(TimeManager.Speed.X1)
		if not event.parent_instance_id.is_empty():
			BlockDiscoveryManager.record_interactive_research_result(event)
	var cooldown_key := definition.id + ":" + target_id
	cooldown_until[cooldown_key] = TimeManager.total_game_seconds + definition.cooldown_hours * 3600.0
	notice_raised.emit(event)
	return event


func _select_event_message(definition: GameEventDefinition) -> String:
	var variants := definition.message_variants.duplicate()
	variants.append(definition.message)
	variants = variants.filter(func(value: String) -> bool: return not value.strip_edges().is_empty())
	return str(variants.pick_random()) if not variants.is_empty() else ""


func _snapshot_options(options: Array[Dictionary], context: Dictionary = {}) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for raw_option in options:
		var option := raw_option.duplicate(true)
		var all_traits: Array = option.get("required_all_traits", [])
		var any_traits: Array = option.get("required_any_traits", [])
		var excluded_traits: Array = option.get("excluded_traits", [])
		var available := true
		for trait_id in all_traits:
			if not GameManager.player_state.has_trait(str(trait_id)):
				available = false
		if not any_traits.is_empty():
			available = false
			for trait_id in any_traits:
				if GameManager.player_state.has_trait(str(trait_id)):
					available = true
		for trait_id in excluded_traits:
			if GameManager.player_state.has_trait(str(trait_id)):
				available = false
		if option.has("transfer_price_multiplier"):
			var npc_store := GameManager.get_npc_store(str(context.get("npc_store_id", "")))
			var required_cash := float(npc_store.transfer_record.get("asking_price", 0.0)) * float(option.get("transfer_price_multiplier", 1.0)) if npc_store != null else INF
			if GameManager.player_state.cash < required_cash:
				available = false
				option["locked_reason"] = "现金不足以接手这间店"
		option["available"] = available
		if not available and str(option.get("locked_reason", "")).is_empty():
			option["locked_reason"] = "需要特定角色特性"
		snapshot.append(option)
	return snapshot

func resolve_decision(instance_id: String, option_id: String) -> bool:
	for index in range(pending_decisions.size()):
		var event := pending_decisions[index]
		## event_id remains accepted for old UI/tests; new callers must use the
		## unique instance ID so simultaneous chains cannot resolve each other.
		if event.instance_id != instance_id and event.event_id != instance_id:
			continue
		for option in event.options:
			if str(option.get("id", "")) == option_id:
				if not bool(option.get("available", true)):
					return false
				event.selected_option_id = option_id
				event.resolution = "selected"
				event.effects.clear()
				for effect in option.get("effects", []):
					if effect is Dictionary:
						event.effects.append(effect)
				EventEffectResolver.apply(event)
				pending_decisions.remove_at(index)
				BlockDiscoveryManager.record_interactive_research_choice(event, option)
				_append_history(event)
				var next_node_id := str(option.get("next_node_id", ""))
				if not next_node_id.is_empty():
					var next_definition: GameEventDefinition = definitions.get(next_node_id, null)
					if next_definition != null:
						_activate(next_definition, event.target_id, event.store_id, event.instance_id, event.chain_id, event.context)
				_resume_after_event(event)
				event_finalized.emit(event)
				return true
	return false


func dismiss_decision(instance_id: String) -> bool:
	for index in range(pending_decisions.size()):
		var event := pending_decisions[index]
		if event.instance_id != instance_id and event.event_id != instance_id:
			continue
		event.resolution = "dismissed"
		pending_decisions.remove_at(index)
		_append_history(event)
		_resume_after_event(event)
		event_finalized.emit(event)
		return true
	return false


func resolve_interrupt(instance_id: String) -> bool:
	for index in range(pending_interrupts.size()):
		var event := pending_interrupts[index]
		if event.instance_id != instance_id and event.event_id != instance_id:
			continue
		event.resolution = "acknowledged"
		pending_interrupts.remove_at(index)
		_append_history(event)
		_resume_after_event(event)
		event_finalized.emit(event)
		return true
	return false


func acknowledge_notice(instance_id: String) -> bool:
	for event in event_history:
		if event.instance_id == instance_id:
			event.resolution = "acknowledged"
			event_finalized.emit(event)
			return true
	return false


func _resume_after_event(event: ActiveGameEvent) -> void:
	if pending_decisions.is_empty() and pending_interrupts.is_empty() and TimeManager.speed == TimeManager.Speed.PAUSED:
		TimeManager.set_speed(event.resume_speed)

func add_temporary_modifier(scope: int, target_id: String, key: String, value: float, duration_hours: float) -> void:
	if key.is_empty():
		return
	var modifier := TemporaryModifier.new()
	modifier.scope = scope
	modifier.target_id = target_id
	modifier.key = key
	modifier.value = value
	modifier.expires_game_seconds = TimeManager.total_game_seconds + maxf(0.0, duration_hours) * 3600.0
	temporary_modifiers.append(modifier)

func get_modifier_total(scope: int, target_id: String, key: String) -> float:
	var total := 0.0
	for modifier in temporary_modifiers:
		if modifier.is_active(TimeManager.total_game_seconds) and modifier.scope == scope and modifier.target_id == target_id and modifier.key == key:
			total += modifier.value
	return total


func _matches_context(definition: GameEventDefinition, block: BlockData) -> bool:
	if definition == null or block == null:
		return false
	if not definition.allowed_block_types.is_empty() and not definition.allowed_block_types.has(block.block_type):
		return false
	if not definition.required_block_tags.is_empty():
		var tag_matches := false
		for tag in definition.required_block_tags:
			if block.tags.has(tag):
				tag_matches = true
				break
		if not tag_matches:
			return false
	var current_hour := TimeManager.get_current_hour_int()
	if not definition.allowed_hours.is_empty() and not definition.allowed_hours.has(current_hour):
		return false
	if definition.required_action_ids.is_empty() and definition.required_action_effect_types.is_empty():
		return true
	var action := ScheduleManager.current_action
	if action == null or not action.is_active:
		return false
	if not definition.required_action_ids.is_empty() and not definition.required_action_ids.has(action.action_id):
		return false
	if not definition.required_action_effect_types.is_empty():
		var action_definition := ScheduleActionData.get_action(action.action_id)
		if action_definition == null or not definition.required_action_effect_types.has(action_definition.action_effect_type):
			return false
	return true


func _append_history(event: ActiveGameEvent) -> void:
	if event == null:
		return
	event_history.append(event)
	while event_history.size() > MAX_EVENT_HISTORY:
		event_history.pop_front()


func _prune_expired_modifiers() -> void:
	for index in range(temporary_modifiers.size() - 1, -1, -1):
		if not temporary_modifiers[index].is_active(TimeManager.total_game_seconds):
			temporary_modifiers.remove_at(index)


func get_recent_events(limit: int = 20, scope: int = -1, target_id: String = "") -> Array[ActiveGameEvent]:
	var result: Array[ActiveGameEvent] = []
	if limit <= 0:
		return result
	for index in range(event_history.size() - 1, -1, -1):
		var event := event_history[index]
		if scope >= 0 and event.scope != scope:
			continue
		if not target_id.is_empty() and event.target_id != target_id:
			continue
		result.append(event)
		if result.size() >= limit:
			break
	return result


func get_active_modifiers(scope: int = -1, target_id: String = "") -> Array[TemporaryModifier]:
	_prune_expired_modifiers()
	var result: Array[TemporaryModifier] = []
	for modifier in temporary_modifiers:
		if scope >= 0 and modifier.scope != scope:
			continue
		if not target_id.is_empty() and modifier.target_id != target_id:
			continue
		result.append(modifier)
	return result

func to_save_dict() -> Dictionary:
	var history: Array = []
	var modifiers: Array = []
	var pending: Array = []
	var interrupts: Array = []
	for event in event_history:
		history.append(event.to_save_dict())
	for event in pending_decisions:
		pending.append(event.to_save_dict())
	for event in pending_interrupts:
		interrupts.append(event.to_save_dict())
	for modifier in temporary_modifiers:
		if modifier.is_active(TimeManager.total_game_seconds):
			modifiers.append(modifier.to_save_dict())
	return {
		"event_history": history,
		"pending_decisions": pending,
		"pending_interrupts": interrupts,
		"cooldown_until": cooldown_until.duplicate(true),
		"last_roll_hour_by_key": last_roll_hour_by_key.duplicate(true),
		"temporary_modifiers": modifiers,
		"next_instance_sequence": _next_instance_sequence,
	}

func apply_save_dict(data: Dictionary) -> void:
	reset_for_new_game()
	var saved_cooldowns: Dictionary = data.get("cooldown_until", {})
	var saved_last_roll_hours: Dictionary = data.get("last_roll_hour_by_key", {})
	cooldown_until = saved_cooldowns.duplicate(true)
	last_roll_hour_by_key = saved_last_roll_hours.duplicate(true)
	_next_instance_sequence = int(data.get("next_instance_sequence", 0))
	for raw_event in data.get("event_history", []):
		if raw_event is Dictionary:
			event_history.append(ActiveGameEvent.from_save_dict(raw_event))
	for raw_event in data.get("pending_decisions", []):
		if raw_event is Dictionary:
			pending_decisions.append(ActiveGameEvent.from_save_dict(raw_event))
	for raw_event in data.get("pending_interrupts", []):
		if raw_event is Dictionary:
			pending_interrupts.append(ActiveGameEvent.from_save_dict(raw_event))
	for raw_modifier in data.get("temporary_modifiers", []):
		if raw_modifier is Dictionary:
			temporary_modifiers.append(TemporaryModifier.from_save_dict(raw_modifier))
	while event_history.size() > MAX_EVENT_HISTORY:
		event_history.pop_front()
	_prune_expired_modifiers()
	if not pending_interrupts.is_empty() or not pending_decisions.is_empty():
		TimeManager.set_speed(TimeManager.Speed.PAUSED)

func _register_research_discoveries() -> void:
	var definition := GameEventDefinition.new()
	definition.id = "research_local_tip"
	definition.scope = GameEventDefinition.Scope.BLOCK
	definition.interaction = GameEventDefinition.Interaction.DECISION
	definition.trigger_kind = "region_research"
	definition.cooldown_hours = 3.0
	definition.minimum_understanding = 5.0
	definition.title = "\u8c03\u7814\u610f\u5916\u53d1\u73b0"
	definition.message = "巷口卖早点的阿姨说，午后这里从不缺人；修车铺的老板却摆手，说那些人只是匆匆路过。两种说法都像是真的，只是各自漏掉了一段时间。你得决定，这条线索值不值得再追。"
	definition.message_variants = ["公交站旁的保安说，傍晚总有人在这里绕一圈；便利店店员却记得，他们从没真正进过店门。两人都说得笃定，像是在描述两条不同的街。你得先弄清，是谁看漏了哪一段。"]
	definition.options = [
		{"id": "record", "label": "先把矛盾记进笔记", "description": "不急着站队；保留线索，但要把判断留到下一次观察。", "effects": [{"type": "block_research_progress_add", "focus_id": "demand", "amount": 1.0}]},
		{"id": "trace", "label": "顺着那拨人追过去", "description": "凭直觉抓住不合常理的流向；或许能找到客流真正停下来的理由。", "required_all_traits": ["market_instinct"], "locked_reason": "需要特性：市场嗅觉", "next_node_id": "research_trace_result", "effects": []},
		{"id": "verify", "label": "把说法拆开逐项核验", "description": "宁愿多花时间做计数，也不让一段热闹的印象替你下结论。", "required_all_traits": ["information_isolated"], "locked_reason": "需要特性：信息闭塞", "next_node_id": "research_verify_result", "effects": []},
	]
	definitions[definition.id] = definition
	_register_chain_result("research_trace_result", "人流去向", "你跟着那群人穿过路口，才发现他们并非被店招吸引，而是在等一条准点到站的通勤线。车门一开，脚步就像被谁拧紧了发条；真正值得盯住的是这段短促却稳定的空档。", [{"type": "block_research_progress_add", "focus_id": "demand", "amount": 4.0}])
	_register_chain_result("research_verify_result", "核验记录", "你把两人的说法按时段写在纸上，又在路边站了一会儿。矛盾没有消失，却露出了边界：热闹只属于某些钟点，其余时间的街面安静得能听见卷帘门响。", [{"type": "block_research_progress_add", "focus_id": "time", "amount": 3.0}])

	var disruption := GameEventDefinition.new()
	disruption.id = "store_service_disruption"
	disruption.scope = GameEventDefinition.Scope.STORE
	disruption.interaction = GameEventDefinition.Interaction.NOTICE
	disruption.trigger_kind = "store_operating_hour"
	disruption.cooldown_hours = 8.0
	disruption.title = "\u7a81\u53d1\u5fd9\u4e71"
	disruption.message = "后场像被人突然抽走了一张椅子：有人在补货，有人被顾客拦住问单，剩下的人只能互相接住漏下来的工作。点单台前的队伍还在往前挪，但每一次停顿都会让犹豫的顾客多看一眼别处。接下来的这阵忙乱，得靠店里自己熬过去。"
	disruption.message_variants = ["一张临时请假的消息让后场的节奏断了半拍，备料台和点单台同时开始叫人。员工尽力把话说得轻松，顾客却已经听得出等待正在变长。这段时间里，每一次失误都会被排队的人看见。"]
	disruption.effects = [
		{"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE,
			"key": "service_time_multiplier_add", "value": 0.25, "duration_hours": 2.0},
		{"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE,
			"key": "conversion_rate_add", "value": -0.08, "duration_hours": 2.0},
	]
	definitions[disruption.id] = disruption


func _register_player_block_events() -> void:
	var definition := GameEventDefinition.new()
	definition.id = "block_street_observation"
	definition.scope = GameEventDefinition.Scope.BLOCK
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.trigger_kind = "player_block_hour"
	definition.cooldown_hours = 6.0
	definition.title = "\u8857\u533a\u89c2\u5bdf"
	definition.message = "你在路边多站了几分钟。外卖骑手总在同一扇侧门前掉头，隔壁店主也把招牌朝着相反方向擦得格外仔细。没人特意解释，但街区的竞争关系在这些小动作里露出了一角。"
	definition.message_variants = ["对街店员在午后悄悄换了价签，隔壁咖啡店却把最显眼的桌子留空。你没听见谁谈生意，但每个人都像是在等同一批客人先做选择。"]
	definition.effects = [{"type": "block_research_progress_add", "focus_id": "competition", "amount": 1.0}]
	definitions[definition.id] = definition


func _register_player_personal_events() -> void:
	var definition := GameEventDefinition.new()
	definition.id = "player_local_refreshment"
	definition.scope = GameEventDefinition.Scope.PLAYER
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.trigger_kind = "player_action_hour"
	definition.cooldown_hours = 6.0
	definition.allowed_block_types = ["school", "office", "commercial"]
	definition.allowed_hours = [10, 11, 12, 13, 14, 15, 16]
	definition.required_action_effect_types = ["region_research"]
	definition.title = "\u8857\u533a\u8865\u7ed9"
	definition.message = "你在记满涂改痕迹的本子前停了太久，隔壁小吃店老板把一杯热饮推到你手边，只说“这条街下午容易犯困”。短暂的热气和闲聊让脚步重新轻下来；离开时，你已经能再看一会儿人群了。"
	definition.message_variants = ["一阵雨把你和几位路人挤进同一处屋檐下，有人顺手递来纸巾，也聊起附近店铺的坏脾气。雨停时，你没多得到一份报告，却重新找回了继续走下去的劲头。"]
	definition.effects = [
		{"type": "player_energy_add", "amount": 8.0},
		{"type": "player_stress_add", "amount": -3.0},
	]
	definitions[definition.id] = definition


func _register_block_activity_events() -> void:
	var definition := GameEventDefinition.new()
	definition.id = "block_local_activity"
	definition.scope = GameEventDefinition.Scope.BLOCK
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.trigger_kind = "block_activity_hour"
	definition.cooldown_hours = 6.0
	definition.title = "\u533a\u5757\u4e34\u65f6\u6d3b\u52a8"
	definition.message = "临时舞台的音响刚试过一轮，摊主们已经把小灯串挂上了树。原本只是路过的人开始放慢脚步，孩子拖着大人往围栏里钻。街面会在接下来的几小时里比平常更愿意停留。"
	definition.message_variants = ["有人把折叠桌搬到路边，第一串试吃的香味已经飘过斑马线。附近住户本来只打算下楼买东西，却被不断围拢的人群留住了脚步。街区的空闲会在这阵热闹里变得格外珍贵。"]
	definition.effects = [{
		"type": "temporary_modifier", "scope": GameEventDefinition.Scope.BLOCK,
		"key": "natural_visitors_multiplier_add", "value": 0.25, "duration_hours": 3.0,
	}]
	definitions[definition.id] = definition


func _register_city_region_activity_events() -> void:
	var definition := GameEventDefinition.new()
	definition.id = "city_region_commercial_festival"
	definition.scope = GameEventDefinition.Scope.CITY_REGION
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.trigger_kind = "city_region_activity_hour"
	definition.cooldown_hours = 10.0
	definition.title = "\u5546\u5708\u7279\u522b\u6d3b\u52a8"
	definition.message = "商圈入口的横幅一夜之间挂满了整条路，志愿者正把地图递给第一次来的访客。人群从主街向周边巷子散开，连平日只认熟客的小店都有人驻足张望。热闹会持续一阵，也会让更多人记住这里。"
	definition.message_variants = ["从地铁口出来的人手里都多了一张活动单页，导航声和招呼声一路把他们带进商圈深处。今天的客人未必知道每家店卖什么，却愿意为一点新鲜感绕个弯。这里正在被一群陌生人重新丈量。"]
	definition.effects = [{
		"type": "temporary_modifier", "scope": GameEventDefinition.Scope.CITY_REGION,
		"key": "natural_visitors_multiplier_add", "value": 0.15, "duration_hours": 3.0,
	}, {
		"type": "temporary_modifier", "scope": GameEventDefinition.Scope.CITY_REGION,
		"key": "awareness_gain_multiplier_add", "value": 0.25, "duration_hours": 3.0,
	}]
	definitions[definition.id] = definition


func _register_storefront_events() -> void:
	var definition := GameEventDefinition.new()
	definition.id = "storefront_visibility_obstruction"
	definition.scope = GameEventDefinition.Scope.STOREFRONT
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.trigger_kind = "storefront_activity_hour"
	definition.cooldown_hours = 8.0
	definition.title = "\u95e8\u5934\u4e34\u65f6\u906e\u6321"
	definition.message = "施工围挡在门前合上，电钻声把招牌后的那点光也盖住了。熟客还能从缝隙里认出店门，第一次经过的人却多半只会以为这里暂时歇业。围挡拆开前，门面得靠已经知道它的人撑住。"
	definition.message_variants = ["施工队把材料堆在了最显眼的位置，门口只剩一条窄得让人犹豫的通道。招牌还在原处，但从远处看去像被临时借走了声音。直到工程收尾前，新客很难一眼确认这里仍在营业。"]
	definition.effects = [{
		"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STOREFRONT,
		"key": "capture_multiplier_add", "value": -0.25, "duration_hours": 2.0,
	}]
	definitions[definition.id] = definition


func _register_store_operating_events() -> void:
	var interrupt := GameEventDefinition.new()
	interrupt.id = "store_equipment_failure"
	interrupt.scope = GameEventDefinition.Scope.STORE
	interrupt.interaction = GameEventDefinition.Interaction.INTERRUPT
	interrupt.trigger_kind = "store_operating_hour"
	interrupt.cooldown_hours = 12.0
	interrupt.title = "\u8bbe\u5907\u6545\u969c"
	interrupt.message = "后场先是一声闷响，随后设备的指示灯一盏接一盏熄了下去。员工把做到一半的订单端在手里，前台已经有人探头问还要等多久。你按下暂停，不是为了让故障消失，而是为了决定这段混乱该怎样被记住。"
	interrupt.message_variants = ["设备忽然发出一阵不该有的金属摩擦声，接着把整条操作台逼得安静下来。有人去找工具，有人守着没出完的单子，前台的笑容也开始变得费力。时间停住了，但门店里的等待没有。"]
	interrupt.effects = [{
		"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE,
		"key": "service_time_multiplier_add", "value": 0.40, "duration_hours": 1.0,
	}]
	definitions[interrupt.id] = interrupt
	var decision := GameEventDefinition.new()
	decision.id = "store_activity_partnership"
	decision.scope = GameEventDefinition.Scope.STORE
	decision.interaction = GameEventDefinition.Interaction.DECISION
	decision.trigger_kind = "store_operating_hour"
	decision.cooldown_hours = 8.0
	decision.title = "\u9644\u8fd1\u6d3b\u52a8\u8054\u52a8"
	decision.message = "活动主办方在收摊前找到你，手里夹着一叠还没盖章的宣传单。他们想把店名放进路线图，也希望你在最忙的时段配合接住人群。机会就在眼前，但谁来承担临时加码的麻烦，仍有得谈。"
	decision.options = [
		{"id": "accept", "label": "点头，把名字放上路线图", "description": "先抓住眼前的人气；店里需要准备好迎接一段更密集的来客。", "effects": [{"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE, "key": "natural_visitors_multiplier_add", "value": 0.15, "duration_hours": 2.0}]},
		{"id": "decline", "label": "礼貌谢绝，守住原来的节奏", "description": "不把临时承诺压到员工身上；这次热闹也会从门前经过。", "effects": []},
		{"id": "terms", "label": "把合作拆成可以交换的条件", "description": "不急着答应，先谈清双方各让什么；谈得久一点，却可能留下更稳的空间。", "required_all_traits": ["negotiator"], "locked_reason": "需要特性：谈判老手", "effects": [{"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE, "key": "natural_visitors_multiplier_add", "value": 0.10, "duration_hours": 3.0}]},
		{"id": "written", "label": "请他们把承诺写下来再答复", "description": "把当场的压力移到纸面上；少一点即兴让步，也少一分临时热闹。", "required_all_traits": ["socially_awkward"], "locked_reason": "需要特性：不善交际", "effects": [{"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE, "key": "conversion_rate_add", "value": 0.03, "duration_hours": 1.0}]},
	]
	definitions[decision.id] = decision
	var definition := GameEventDefinition.new()
	definition.id = "store_neighborhood_activity"
	definition.scope = GameEventDefinition.Scope.STORE
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.trigger_kind = "store_operating_hour"
	definition.cooldown_hours = 8.0
	definition.title = "\u5468\u8fb9\u6d3b\u52a8\u5e26\u6765\u4eba\u6c14"
	definition.message = "隔壁街的活动刚散场，几拨人沿着店门前的路慢慢走回来。有人停下看菜单，有人只是躲进来避一避人潮；无论如何，门口比平常多了一点犹豫和好奇。接下来的几个小时，店里会比往常更有机会接住这些脚步。"
	definition.message_variants = ["人群从附近的活动场地散出来，先是几个人停在橱窗前，接着便有人回头叫同伴一起看看。未必每个人都准备消费，但他们暂时有了时间，也有了走进陌生店门的理由。"]
	definition.effects = [{
		"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE,
		"key": "natural_visitors_multiplier_add", "value": 0.20, "duration_hours": 2.0,
	}]
	definitions[definition.id] = definition


func _register_chain_result(id: String, title: String, message: String, effects: Array[Dictionary]) -> void:
	var definition := GameEventDefinition.new()
	definition.id = id
	definition.scope = GameEventDefinition.Scope.BLOCK
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.title = title
	definition.message = message
	definition.effects = effects
	definitions[id] = definition


func _register_landlord_terms_chain() -> void:
	_register_landlord_decision("landlord_terms_opening", "房东临时改口", "房东把原先的报价单压在茶杯下面，说刚才有人也问过这个门面。她的语气很轻，像是在等你先替这句话找理由。桌上的钥匙就在手边，但每一把都还没有真正交到你手里。", [
		{"id": "review", "label": "请她把每一项费用写清楚", "description": "把模糊的压力还原成能逐条判断的条件。", "next_node_id": "landlord_terms_review", "effects": []},
		{"id": "exchange", "label": "不先还价，先问她最在乎什么", "description": "不急着碰数字，试着找出可以交换的风险。", "required_all_traits": ["negotiator"], "locked_reason": "需要特性：谈判老手", "next_node_id": "landlord_terms_exchange", "effects": []},
		{"id": "written", "label": "请她把报价发成书面文本", "description": "把当场的压力留在门外，让每一项让步都写清楚。", "required_all_traits": ["socially_awkward"], "locked_reason": "需要特性：不善交际", "next_node_id": "landlord_terms_written", "effects": []},
		{"id": "leave", "label": "合上本子，今天不作承诺", "description": "暂时放下这扇门，也放下现在就必须决定的压力。", "next_node_id": "landlord_terms_walkaway", "effects": []},
	])
	_register_landlord_decision("landlord_terms_review", "逐项报价", "她把租金、押金和交付日期逐行圈出来，没有再加一句“这是最低价”。纸面上的条件不讨喜，却没有藏着第二层意思。", [
		_lease_option("standard", "按原方案签下，把变量留给经营", "接受稳定、清楚的基准条件。", "landlord_terms_standard_result", 1.0, 2, 0.0),
		{"id": "leave", "label": "把报价还给她，继续找别的门面", "description": "不让一份平稳的合同替你做最后决定。", "next_node_id": "landlord_terms_walkaway", "effects": []},
	])
	_register_landlord_decision("landlord_terms_exchange", "交换条件", "你没有立刻碰她报出的数字，只问她最怕的是什么。房东看着空置门面承认，她更在意租客能否稳定落脚。谈判终于从“能不能便宜”变成了“谁替谁承担风险”。", [
		_lease_option("low_rent", "多交一笔押金，换更低的长期月租", "把更多现金压在今天，换往后每个月轻一点。", "landlord_terms_low_rent_result", 0.9, 3, 0.0),
		_lease_option("buffer", "多交一笔押金，换两周开业免租", "把缓冲留给开业最混乱的日子。", "landlord_terms_buffer_result", 1.0, 3, 336.0),
		{"id": "leave", "label": "表示条件不合适，今天到此为止", "description": "不为一扇门承诺自己承受不起的风险。", "next_node_id": "landlord_terms_walkaway", "effects": []},
	])
	_register_landlord_decision("landlord_terms_written", "纸面往来", "邮件里没有催促的眼神，只有逐条列出的数字和一个等待回复的光标。少出的前期现金，终究会在别处被标上价。", [
		_lease_option("low_deposit", "接受略高月租，换更低的押金", "保留启动资金，但把压力挪到每个月的账单上。", "landlord_terms_low_deposit_result", 1.05, 1, 0.0),
		_lease_option("free_month", "接受更高月租，换首月营业免租", "让开业有喘息时间，代价是之后每月更重。", "landlord_terms_free_month_result", 1.1, 1, 720.0),
		{"id": "leave", "label": "不回复这份报价，继续寻找", "description": "不让纸面上的清楚掩盖条件本身的重量。", "next_node_id": "landlord_terms_walkaway", "effects": []},
	])
	_register_landlord_result("landlord_terms_standard_result", "基准报价已记录", "房东收起笔，把两份相同的条款推到你面前。没有额外的让步，也没有藏起来的附页。这份报价已经记录下来；确认签约时，再决定是否把钥匙拿走。")
	_register_landlord_result("landlord_terms_low_rent_result", "低租约报价已记录", "她点头收下更高的押金承诺，终于把月租那一行划低。你替未来的每个月争来一点空间，也把更多现金留在了今天。报价已经记录下来。")
	_register_landlord_result("landlord_terms_buffer_result", "开业缓冲报价已记录", "房东把免租期写在补充条款最上方，提醒你它只会从真正营业时开始计算。你买下的不是便宜，而是一段能把开业节奏理顺的时间。报价已经记录下来。")
	_register_landlord_result("landlord_terms_low_deposit_result", "低押金报价已记录", "回复邮件很快到了：她愿意少收一笔押金，但月租不会替你忘记这份让步。前期资金能留在手里，往后的账本会记得这次选择。报价已经记录下来。")
	_register_landlord_result("landlord_terms_free_month_result", "首月免租报价已记录", "她同意把首月营业免租写进条款，随后把月租数字抬高了一格。最难的开业阶段会有一段喘息，但它并没有消失，只是被安排到了以后。报价已经记录下来。")
	_register_landlord_result("landlord_terms_walkaway", "谈判暂时结束", "房东没有挽留，只把钥匙重新收进抽屉。你没有失去一间店，只是没有把自己绑在今天的条件上。这个门面仍可更换，但尚未形成可签约的报价。")


func _lease_option(id: String, label: String, description: String, result_node_id: String, rent_multiplier: float, deposit_months: int, free_rent_hours: float) -> Dictionary:
	return {"id": id, "label": label, "description": description, "next_node_id": result_node_id, "effects": [{"type": "store_lease_offer", "rent_multiplier": rent_multiplier, "deposit_months": deposit_months, "free_rent_hours": free_rent_hours}]}


func _register_npc_transfer_chain() -> void:
	_register_transfer_decision("npc_transfer_opening", "门头上的转让告示", "褪色的告示被胶带贴在玻璃内侧。店主没有急着介绍生意，只说自己已经撑得太久；桌上的账本、钥匙和还没到期的租约，都在等一个新的去处。", [
		{"id": "review", "label": "先翻看账本和租约", "description": "把店里的热闹与亏损都摆到同一张桌上，再决定是否接手。", "next_node_id": "npc_transfer_review", "effects": []},
		{"id": "press", "label": "先问他真正急着摆脱什么", "description": "不急着谈价格，试着找出对方最难继续承担的风险。", "required_all_traits": ["negotiator"], "locked_reason": "需要特性：谈判老手", "next_node_id": "npc_transfer_press", "effects": []},
		{"id": "leave", "label": "把告示留在原处", "description": "不让一间疲惫的店替你做出承诺。", "next_node_id": "npc_transfer_leave", "effects": []},
	])
	_register_transfer_decision("npc_transfer_review", "把旧账摊开", "账本边缘沾着油渍，近几周的亏损被一笔笔圈了出来。设备和员工还在，租约也没有立刻到期；问题不是这家店有没有价值，而是你愿不愿意接下它没走完的路。", [
		{"id": "take", "label": "按账面条件接手整间店", "description": "连同现有资产、员工、库存和剩余租约一起承担。", "transfer_price_multiplier": 1.0, "next_node_id": "npc_transfer_success", "effects": [{"type": "npc_transfer_takeover", "price_multiplier": 1.0}]},
		{"id": "leave", "label": "合上账本，暂不接手", "description": "把风险留回原来的经营者手中。", "next_node_id": "npc_transfer_leave", "effects": []},
	])
	_register_transfer_decision("npc_transfer_press", "把压力换成条件", "对方沉默了很久，承认最怕的不是少拿一点钱，而是下个月的租金和员工的去处。你争到了一点价格空间，也必须接下更完整、更难回头的承诺。", [
		{"id": "take", "label": "以较低价格接手，保留原班人马", "description": "省下一笔收购款，但接下员工与租约的全部延续。", "transfer_price_multiplier": 0.86, "next_node_id": "npc_transfer_success", "effects": [{"type": "npc_transfer_takeover", "price_multiplier": 0.86}]},
		{"id": "leave", "label": "承认条件仍不合适", "description": "不把谈出来的让步误认为风险已经消失。", "next_node_id": "npc_transfer_leave", "effects": []},
	])
	_register_transfer_result("npc_transfer_success", "钥匙换了主人", "对方把钥匙推到你这边，像终于允许自己离开一段拖得太久的日子。门头、账本、库存和还在等排班的员工现在都归你处理；这不是一间新店，而是一段正在继续的经营。")
	_register_transfer_result("npc_transfer_leave", "转让没有成交", "店主把告示重新抚平在玻璃上。你没有替他解决问题，也没有把它变成自己的问题；这间店仍会按它自己的账本继续走下去。")


func _register_transfer_decision(id: String, title: String, message: String, options: Array[Dictionary]) -> void:
	var definition := GameEventDefinition.new()
	definition.id = id
	definition.title = title
	definition.message = message
	definition.interaction = GameEventDefinition.Interaction.DECISION
	definition.chain_id = "npc_transfer"
	definition.options = options
	definitions[id] = definition


func _register_transfer_result(id: String, title: String, message: String) -> void:
	var definition := GameEventDefinition.new()
	definition.id = id
	definition.title = title
	definition.message = message
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.chain_id = "npc_transfer"
	definitions[id] = definition


func _register_landlord_decision(id: String, title: String, message: String, options: Array[Dictionary]) -> void:
	var definition := GameEventDefinition.new()
	definition.id = id
	definition.chain_id = "landlord_terms"
	definition.node_id = id
	definition.scope = GameEventDefinition.Scope.STORE
	definition.interaction = GameEventDefinition.Interaction.DECISION
	definition.title = title
	definition.message = message
	definition.options = options
	definitions[id] = definition


func _register_landlord_result(id: String, title: String, message: String) -> void:
	var definition := GameEventDefinition.new()
	definition.id = id
	definition.chain_id = "landlord_terms"
	definition.node_id = id
	definition.scope = GameEventDefinition.Scope.STORE
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.title = title
	definition.message = message
	definitions[id] = definition


func _on_hour_advanced(_day: int, _hour: int) -> void:
	_prune_expired_modifiers()
	if GameManager.player_state.is_character_created:
		try_player_block_event()
		try_player_personal_event()
		try_store_operating_events()
