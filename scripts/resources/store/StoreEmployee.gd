class_name StoreEmployee
extends RefCounted

var candidate_id: String = ""
var name: String = ""
var skills: Array[String] = []
var hourly_wage: float = 0.0
var skill_level: float = 1.0
var satisfaction: float = 70.0
var fatigue: float = 0.0
var work_hour_ranges: Array[Vector2i] = []

func is_scheduled_at_hour(hour: int) -> bool:
	for hour_range in work_hour_ranges:
		if hour >= hour_range.x and hour < hour_range.y:
			return true
	return false

func has_skill(skill: String) -> bool:
	return skill in skills

func to_dict() -> Dictionary:
	var ranges: Array = []
	for hour_range in work_hour_ranges:
		ranges.append([hour_range.x, hour_range.y])
	return {
		"candidate_id": candidate_id,
		"name": name,
		"skills": skills,
		"hourly_wage": hourly_wage,
		"skill_level": skill_level,
		"satisfaction": satisfaction,
		"fatigue": fatigue,
		"work_hour_ranges": ranges,
	}

static func from_dict(data: Dictionary) -> StoreEmployee:
	var employee := StoreEmployee.new()
	employee.candidate_id = str(data.get("candidate_id", ""))
	employee.name = str(data.get("name", ""))
	for skill in data.get("skills", []):
		employee.skills.append(str(skill))
	employee.hourly_wage = float(data.get("hourly_wage", 0.0))
	employee.skill_level = float(data.get("skill_level", 1.0))
	employee.satisfaction = float(data.get("satisfaction", 70.0))
	employee.fatigue = float(data.get("fatigue", 0.0))
	for raw_range in data.get("work_hour_ranges", []):
		if raw_range is Array and raw_range.size() >= 2:
			employee.work_hour_ranges.append(Vector2i(int(raw_range[0]), int(raw_range[1])))
	return employee
