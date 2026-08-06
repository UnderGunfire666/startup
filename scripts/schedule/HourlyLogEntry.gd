class_name HourlyLogEntry
extends RefCounted

var day: int = 0
var hour: int = 0
var action_id: String = ""
var action_name: String = ""
var action_status: String = "idle"   # idle/executing/completed/skipped/failed
var energy_before: float = 0.0
var energy_after: float = 0.0
var energy_debt_before: float = 0.0
var energy_debt_after: float = 0.0
var work_hours_before: float = 0.0
var work_hours_after: float = 0.0
var fatigue_before: String = "normal"
var fatigue_after: String = "normal"
var applied_energy_multiplier: float = 1.0
var applied_effect_multiplier: float = 1.0
var store_was_operating: bool = false
var player_supervising: bool = false
var warnings: Array[String] = []
var failure_reason: String = ""

func to_dict() -> Dictionary:
	return {
		"day": day, "hour": hour, "action_id": action_id, "action_name": action_name,
		"action_status": action_status,
		"energy_before": energy_before, "energy_after": energy_after,
		"energy_debt_before": energy_debt_before, "energy_debt_after": energy_debt_after,
		"work_hours_before": work_hours_before, "work_hours_after": work_hours_after,
		"fatigue_before": fatigue_before, "fatigue_after": fatigue_after,
		"applied_energy_multiplier": applied_energy_multiplier,
		"applied_effect_multiplier": applied_effect_multiplier,
		"store_was_operating": store_was_operating,
		"player_supervising": player_supervising,
		"warnings": warnings, "failure_reason": failure_reason,
	}
