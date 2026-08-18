extends Node

signal notice_raised(event: ActiveGameEvent)
signal decision_raised(event: ActiveGameEvent)
signal interrupt_raised(event: ActiveGameEvent)

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

func _ready() -> void:
	_register_research_discoveries()
	_register_player_block_events()
	_register_player_personal_events()
	_register_block_activity_events()
	_register_city_region_activity_events()
	_register_storefront_events()
	_register_store_operating_events()
	TimeManager.hour_advanced.connect(_on_hour_advanced)

func reset_for_new_game() -> void:
	event_history.clear()
	cooldown_until.clear()
	last_roll_hour_by_key.clear()
	temporary_modifiers.clear()
	pending_decisions.clear()
	pending_interrupts.clear()

func try_research_discovery(block_id: String) -> ActiveGameEvent:
	var block := GameManager.get_block(block_id)
	if block == null:
		return null
	var definition: GameEventDefinition = definitions.get("research_local_tip", null)
	if definition == null or GameManager.get_block_understanding(block_id) < definition.minimum_understanding:
		return null
	var now_hour: int = int(floor(TimeManager.total_game_seconds / 3600.0))
	var roll_key := definition.id + ":" + block_id
	if int(last_roll_hour_by_key.get(roll_key, -1)) == now_hour:
		return null
	last_roll_hour_by_key[roll_key] = now_hour
	if float(cooldown_until.get(roll_key, 0.0)) > TimeManager.total_game_seconds or randf() > RESEARCH_DISCOVERY_CHANCE_PER_HOUR:
		return null
	return _activate(definition, block_id)


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

func _activate(definition: GameEventDefinition, target_id: String, store_id: String = "") -> ActiveGameEvent:
	var event := ActiveGameEvent.new()
	event.event_id = definition.id
	event.scope = definition.scope
	event.interaction = definition.interaction
	event.target_id = target_id
	event.store_id = store_id
	event.title = definition.title
	event.message = definition.message
	event.started_game_seconds = TimeManager.total_game_seconds
	event.effects = definition.effects.duplicate(true)
	event.options = definition.options.duplicate(true)
	if event.interaction == GameEventDefinition.Interaction.DECISION:
		pending_decisions.append(event)
		decision_raised.emit(event)
	elif event.interaction == GameEventDefinition.Interaction.INTERRUPT:
		EventEffectResolver.apply(event)
		pending_interrupts.append(event)
		TimeManager.set_speed(TimeManager.Speed.PAUSED)
		interrupt_raised.emit(event)
	else:
		EventEffectResolver.apply(event)
		_append_history(event)
	var cooldown_key := definition.id + ":" + target_id
	cooldown_until[cooldown_key] = TimeManager.total_game_seconds + definition.cooldown_hours * 3600.0
	notice_raised.emit(event)
	return event

func resolve_decision(event_id: String, option_id: String) -> bool:
	for index in range(pending_decisions.size()):
		var event := pending_decisions[index]
		if event.event_id != event_id:
			continue
		for option in event.options:
			if str(option.get("id", "")) == option_id:
				event.effects.clear()
				for effect in option.get("effects", []):
					if effect is Dictionary:
						event.effects.append(effect)
				EventEffectResolver.apply(event)
				pending_decisions.remove_at(index)
				_append_history(event)
				return true
	return false


func resolve_interrupt(event_id: String) -> bool:
	for index in range(pending_interrupts.size()):
		var event := pending_interrupts[index]
		if event.event_id != event_id:
			continue
		pending_interrupts.remove_at(index)
		_append_history(event)
		return true
	return false

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
	}

func apply_save_dict(data: Dictionary) -> void:
	reset_for_new_game()
	var saved_cooldowns: Dictionary = data.get("cooldown_until", {})
	var saved_last_roll_hours: Dictionary = data.get("last_roll_hour_by_key", {})
	cooldown_until = saved_cooldowns.duplicate(true)
	last_roll_hour_by_key = saved_last_roll_hours.duplicate(true)
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
	if not pending_interrupts.is_empty():
		TimeManager.set_speed(TimeManager.Speed.PAUSED)

func _register_research_discoveries() -> void:
	var definition := GameEventDefinition.new()
	definition.id = "research_local_tip"
	definition.scope = GameEventDefinition.Scope.BLOCK
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.trigger_kind = "region_research"
	definition.cooldown_hours = 3.0
	definition.minimum_understanding = 5.0
	definition.title = "\u8c03\u7814\u610f\u5916\u53d1\u73b0"
	definition.message = "\u4f60\u4ece\u5f53\u5730\u4eba\u53e3\u4e2d\u83b7\u5f97\u4e86\u989d\u5916\u7ebf\u7d22\uff0c\u8be5\u533a\u5757\u7684\u4e86\u89e3\u5ea6\u5c0f\u5e45\u63d0\u5347\u3002"
	definition.effects = [{"type": "block_understanding_add", "amount": 3.0}]
	definitions[definition.id] = definition

	var disruption := GameEventDefinition.new()
	disruption.id = "store_service_disruption"
	disruption.scope = GameEventDefinition.Scope.STORE
	disruption.interaction = GameEventDefinition.Interaction.NOTICE
	disruption.trigger_kind = "store_operating_hour"
	disruption.cooldown_hours = 8.0
	disruption.title = "\u7a81\u53d1\u5fd9\u4e71"
	disruption.message = "\u672c\u65f6\u6bb5\u51fa\u73b0\u4e34\u65f6\u4eba\u624b\u4e0d\u7545\uff0c\u63a5\u4e0b\u6765 2 \u5c0f\u65f6\u7684\u51fa\u9910\u6548\u7387\u548c\u4e0b\u5355\u8f6c\u5316\u4f1a\u53d7\u5f71\u54cd\u3002"
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
	definition.message = "\u4f60\u4ece\u9644\u8fd1\u884c\u4eba\u4e0e\u5546\u6237\u4e2d\u53d1\u73b0\u4e86\u4e00\u6761\u7ecf\u8425\u7ebf\u7d22\uff0c\u5bf9\u8be5\u533a\u5757\u7684\u4e86\u89e3\u66f4\u6df1\u4e86\u3002"
	definition.effects = [{"type": "block_understanding_add", "amount": 1.0}]
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
	definition.message = "\u8c03\u7814\u9014\u4e2d\u5f97\u5230\u672c\u5730\u5c0f\u5403\u5e97\u7684\u53cb\u5584\u62db\u5f85\uff0c\u7cbe\u529b\u5f97\u5230\u6062\u590d\u3002"
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
	definition.message = "\u672c\u533a\u5757\u6b63\u5728\u4e3e\u884c\u4e34\u65f6\u6d3b\u52a8\uff0c\u63a5\u4e0b\u6765 3 \u5c0f\u65f6\u7684\u672c\u5730\u81ea\u7136\u5ba2\u6d41\u5c06\u63d0\u9ad8\u3002"
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
	definition.message = "\u8be5\u57ce\u5e02\u533a\u57df\u6b63\u5728\u4e3e\u529e\u4e34\u65f6\u6d3b\u52a8\uff0c\u63a5\u4e0b\u6765 3 \u5c0f\u65f6\u7684\u672c\u5730\u81ea\u7136\u5ba2\u6d41\u5c06\u63d0\u9ad8\u3002"
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
	definition.message = "\u95e8\u5e97\u524d\u65b9\u51fa\u73b0\u4e34\u65f6\u65bd\u5de5\u4e0e\u56f4\u6321\uff0c\u63a5\u4e0b\u6765 2 \u5c0f\u65f6\u7684\u95e8\u9762\u53ef\u89c1\u5ea6\u5c06\u4e0b\u964d\u3002"
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
	interrupt.message = "\u95e8\u5e97\u6709\u8bbe\u5907\u7a81\u53d1\u6545\u969c\uff0c\u5df2\u6682\u505c\u65f6\u95f4\u3002\u5f53\u524d\u51fa\u9910\u6548\u7387\u5c06\u6682\u65f6\u964d\u4f4e\u3002"
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
	decision.message = "\u9644\u8fd1\u4e3b\u529e\u65b9\u9080\u8bf7\u672c\u5e97\u52a0\u5165\u6d3b\u52a8\u3002"
	decision.options = [
		{"id": "accept", "label": "\u63a5\u53d7\u5408\u4f5c", "effects": [{"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE, "key": "natural_visitors_multiplier_add", "value": 0.15, "duration_hours": 2.0}]},
		{"id": "decline", "label": "\u6682\u4e0d\u53c2\u4e0e", "effects": []},
	]
	definitions[decision.id] = decision
	var definition := GameEventDefinition.new()
	definition.id = "store_neighborhood_activity"
	definition.scope = GameEventDefinition.Scope.STORE
	definition.interaction = GameEventDefinition.Interaction.NOTICE
	definition.trigger_kind = "store_operating_hour"
	definition.cooldown_hours = 8.0
	definition.title = "\u5468\u8fb9\u6d3b\u52a8\u5e26\u6765\u4eba\u6c14"
	definition.message = "\u9644\u8fd1\u6b63\u6709\u4e34\u65f6\u6d3b\u52a8\uff0c\u672c\u5e97\u5728\u63a5\u4e0b\u6765 2 \u5c0f\u65f6\u7684\u81ea\u7136\u5ba2\u6d41\u5c06\u5c0f\u5e45\u63d0\u9ad8\u3002"
	definition.effects = [{
		"type": "temporary_modifier", "scope": GameEventDefinition.Scope.STORE,
		"key": "natural_visitors_multiplier_add", "value": 0.20, "duration_hours": 2.0,
	}]
	definitions[definition.id] = definition


func _on_hour_advanced(_day: int, _hour: int) -> void:
	_prune_expired_modifiers()
	if GameManager.player_state.is_character_created:
		try_player_block_event()
		try_player_personal_event()
		try_store_operating_events()
