class_name ScheduledActionEntry
extends RefCounted

var action_id: String = ""
var start_hour: int = 0
var duration_hours: int = 1
var status: String = "pending"   # pending/completed/skipped/failed
var failure_reason: String = ""
var hours_completed: float = 0.0
var target_id: String = ""

func get_end_hour() -> int:
	return start_hour + duration_hours

func covers_hour(hour: int) -> bool:
	return hour >= start_hour and hour < get_end_hour()

func to_dict() -> Dictionary:
	return {
		"action_id": action_id, "start_hour": start_hour,
		"duration_hours": duration_hours, "status": status,
		"failure_reason": failure_reason,
		"target_id": target_id,
	}

static func from_dict(data: Dictionary) -> ScheduledActionEntry:
	var e := ScheduledActionEntry.new()
	e.action_id = data.get("action_id", "")
	e.start_hour = data.get("start_hour", 0)
	e.duration_hours = data.get("duration_hours", 1)
	e.status = data.get("status", "pending")
	e.failure_reason = data.get("failure_reason", "")
	e.target_id = data.get("target_id","")
	return e
