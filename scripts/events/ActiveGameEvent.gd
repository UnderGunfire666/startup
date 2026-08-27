class_name ActiveGameEvent
extends RefCounted

var event_id: String = ""
var instance_id: String = ""
var chain_id: String = ""
var node_id: String = ""
var parent_instance_id: String = ""
var selected_option_id: String = ""
## pending, selected, acknowledged, or dismissed. Kept in history so a
## dismissed choice is never mistaken for an applied option.
var resolution: String = "pending"
var resume_speed: int = TimeManager.Speed.X1
var scope: int = GameEventDefinition.Scope.PLAYER
var interaction: int = GameEventDefinition.Interaction.NOTICE
var target_id: String = ""
var store_id: String = ""
## Immutable chain data for targets more specific than a store or block.
var context: Dictionary = {}
var title: String = ""
var message: String = ""
var started_game_seconds: float = 0.0
var effects: Array[Dictionary] = []
var options: Array[Dictionary] = []

func to_save_dict() -> Dictionary:
	return {
		"event_id": event_id, "instance_id": instance_id, "chain_id": chain_id,
		"node_id": node_id, "parent_instance_id": parent_instance_id,
		"selected_option_id": selected_option_id, "resolution": resolution, "resume_speed": resume_speed,
		"scope": scope, "interaction": interaction,
		"target_id": target_id, "store_id": store_id, "context": context, "title": title,
		"message": message, "started_game_seconds": started_game_seconds,
		"effects": effects,
		"options": options,
	}

static func from_save_dict(data: Dictionary) -> ActiveGameEvent:
	var event := ActiveGameEvent.new()
	event.event_id = str(data.get("event_id", ""))
	event.instance_id = str(data.get("instance_id", event.event_id))
	event.chain_id = str(data.get("chain_id", ""))
	event.node_id = str(data.get("node_id", ""))
	event.parent_instance_id = str(data.get("parent_instance_id", ""))
	event.selected_option_id = str(data.get("selected_option_id", ""))
	event.resolution = str(data.get("resolution", "pending"))
	event.resume_speed = int(data.get("resume_speed", TimeManager.Speed.X1))
	event.scope = int(data.get("scope", GameEventDefinition.Scope.PLAYER))
	event.interaction = int(data.get("interaction", GameEventDefinition.Interaction.NOTICE))
	event.target_id = str(data.get("target_id", ""))
	event.store_id = str(data.get("store_id", ""))
	event.context = data.get("context", {}).duplicate(true) if data.get("context", {}) is Dictionary else {}
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
