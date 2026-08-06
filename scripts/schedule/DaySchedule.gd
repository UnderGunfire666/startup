class_name DaySchedule
extends RefCounted

var entries: Array[ScheduledActionEntry] = []

func get_entry_for_hour(hour: int) -> ScheduledActionEntry:
	for e in entries:
		if e.covers_hour(hour):
			return e
	return null

func has_conflict(start_hour: int, duration_hours: int) -> bool:
	var end_hour := start_hour + duration_hours
	if end_hour > 24:
		return true
	for e in entries:
		if start_hour < e.get_end_hour() and end_hour > e.start_hour:
			return true
	return false

func add_entry(action_id: String, start_hour: int, duration_hours: int) -> ScheduledActionEntry:
	var e := ScheduledActionEntry.new()
	e.action_id = action_id
	e.start_hour = start_hour
	e.duration_hours = duration_hours
	entries.append(e)
	entries.sort_custom(func(a, b): return a.start_hour < b.start_hour)
	return e

func remove_entry_at_hour(hour: int) -> bool:
	for i in range(entries.size()):
		if entries[i].covers_hour(hour):
			entries.remove_at(i)
			return true
	return false

func clear() -> void:
	entries.clear()

func to_dict() -> Dictionary:
	var list: Array = []
	for e in entries:
		list.append(e.to_dict())
	return {"entries": list}

static func from_dict(data: Dictionary) -> DaySchedule:
	var s := DaySchedule.new()
	var raw: Array = data.get("entries", [])
	for ed in raw:
		s.entries.append(ScheduledActionEntry.from_dict(ed))
	return s
