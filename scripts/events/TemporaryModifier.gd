class_name TemporaryModifier
extends RefCounted

var scope: int = GameEventDefinition.Scope.PLAYER
var target_id: String = ""
var key: String = ""
var value: float = 0.0
var expires_game_seconds: float = 0.0

func is_active(now_seconds: float) -> bool:
	return expires_game_seconds <= 0.0 or now_seconds < expires_game_seconds

func to_save_dict() -> Dictionary:
	return {"scope": scope, "target_id": target_id, "key": key, "value": value, "expires_game_seconds": expires_game_seconds}

static func from_save_dict(data: Dictionary) -> TemporaryModifier:
	var modifier := TemporaryModifier.new()
	modifier.scope = int(data.get("scope", GameEventDefinition.Scope.PLAYER))
	modifier.target_id = str(data.get("target_id", ""))
	modifier.key = str(data.get("key", ""))
	modifier.value = float(data.get("value", 0.0))
	modifier.expires_game_seconds = float(data.get("expires_game_seconds", 0.0))
	return modifier

