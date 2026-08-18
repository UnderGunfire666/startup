class_name ActiveGameEvent
extends RefCounted

var event_id: String = ""
var scope: int = GameEventDefinition.Scope.PLAYER
var interaction: int = GameEventDefinition.Interaction.NOTICE
var target_id: String = ""
var store_id: String = ""
var title: String = ""
var message: String = ""
var started_game_seconds: float = 0.0
var effects: Array[Dictionary] = []
var options: Array[Dictionary] = []

func to_save_dict() -> Dictionary:
	return {
		"event_id": event_id, "scope": scope, "interaction": interaction,
		"target_id": target_id, "store_id": store_id, "title": title,
		"message": message, "started_game_seconds": started_game_seconds,
		"effects": effects,
		"options": options,
	}

static func from_save_dict(data: Dictionary) -> ActiveGameEvent:
	var event := ActiveGameEvent.new()
	event.event_id = str(data.get("event_id", ""))
	event.scope = int(data.get("scope", GameEventDefinition.Scope.PLAYER))
	event.interaction = int(data.get("interaction", GameEventDefinition.Interaction.NOTICE))
	event.target_id = str(data.get("target_id", ""))
	event.store_id = str(data.get("store_id", ""))
	event.title = str(data.get("title", ""))
	event.message = str(data.get("message", ""))
	event.started_game_seconds = float(data.get("started_game_seconds", 0.0))
	for effect in data.get("effects", []):
		if effect is Dictionary:
			event.effects.append(effect)
	for option in data.get("options", []):
		if option is Dictionary:
			event.options.append(option)
	return event
