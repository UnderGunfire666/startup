extends PanelContainer

signal employee_changed

@onready var title_label: Label = $VBox/TitleLabel
@onready var employed_list: VBoxContainer = $VBox/ContentSplit/StaffScroll/StaffContent/EmployedList
@onready var coverage_label: Label = $VBox/ContentSplit/StaffScroll/StaffContent/CoverageLabel
@onready var candidate_list: VBoxContainer = $VBox/ContentSplit/CandidateScroll/CandidateContent/CandidateList
@onready var status_label: Label = $VBox/StatusLabel

func _ready() -> void:
	title_label.text = "\u5458\u5de5\u4e0e\u6392\u73ed"
	refresh()

func refresh() -> void:
	_clear_children(employed_list)
	_clear_children(candidate_list)
	var store := GameManager.store_state
	if store == null:
		coverage_label.text = "\u8bf7\u5148\u521b\u5efa\u5e76\u6fc0\u6d3b\u5f00\u5e97\u4f01\u5212\u3002"
		return
	_refresh_coverage(store)
	_refresh_employed(store)
	_refresh_candidates(store)

func _refresh_coverage(store: Store) -> void:
	var rows: Array[String] = []
	for category_slot in store.category_slots:
		var category := GameManager.get_category(category_slot.category_id)
		if category == null or category.required_staff.is_empty():
			continue
		var skill := category.required_staff
		var status := GameManager.get_category_staffing_status(store, category, TimeManager.get_current_hour_int())
		var sufficient := int(status.scheduled) >= int(status.required)
		rows.append("%s\uff08%s\uff09\uff1a%d/%d \u4eba%s" % [category.name, skill, status.scheduled, status.required, "\uff08\u4eba\u624b\u5145\u8db3\uff09" if sufficient else "\uff08\u4eba\u624b\u4e0d\u8db3\uff0c\u51fa\u9910\u4e0e\u63a5\u5f85\u4f1a\u53d7\u9650\uff09"])
	coverage_label.text = "\u5f53\u524d\u65f6\u6bb5\u5c97\u4f4d\u8986\u76d6\uff08\u5e97\u4e3b\u5750\u9547\u4e5f\u8ba1 1 \u4eba\uff09\uff1a\n" + ("\n".join(rows) if not rows.is_empty() else "\u6682\u65e0")

func _refresh_employed(store: Store) -> void:
	var header := Label.new()
	header.text = "\u5df2\u96c7\u5458\u5de5"
	employed_list.add_child(header)
	if store.employees.is_empty():
		var empty := Label.new()
		empty.text = "\u6682\u65e0\u5458\u5de5\uff1b\u73a9\u5bb6\u4ecd\u53ef\u81ea\u884c\u7ecf\u8425\u3002"
		employed_list.add_child(empty)
		return
	for employee in store.employees:
		var card := VBoxContainer.new()
		var info := Label.new()
		info.text = "%s\uff5c%s\n%.0f \u5143/\u5c0f\u65f6 \u00b7 \u719f\u7ec3\u5ea6 %.0f%%" % [employee.name, "\u3001".join(employee.skills), employee.hourly_wage, employee.skill_level * 100.0]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(info)
		var row := HBoxContainer.new()
		var start := OptionButton.new()
		var ending := OptionButton.new()
		for hour in range(25):
			start.add_item("%02d:00" % hour)
			ending.add_item("%02d:00" % hour)
		var current_start := employee.work_hour_ranges[0].x if not employee.work_hour_ranges.is_empty() else 9
		var current_end := employee.work_hour_ranges[0].y if not employee.work_hour_ranges.is_empty() else 18
		start.select(current_start)
		ending.select(current_end)
		row.add_child(start)
		row.add_child(ending)
		var save_button := Button.new()
		save_button.text = "\u4fdd\u5b58\u6392\u73ed"
		save_button.pressed.connect(func() -> void:
			var ranges: Array[Vector2i] = [Vector2i(start.selected, ending.selected)]
			var result := GameManager.set_employee_work_hours(employee.candidate_id, ranges)
			status_label.text = str(result.get("reason", ""))
			refresh()
			employee_changed.emit()
		)
		row.add_child(save_button)
		card.add_child(row)
		employed_list.add_child(card)
		employed_list.add_child(HSeparator.new())

func _refresh_candidates(store: Store) -> void:
	var header := Label.new()
	header.text = "\u62db\u8058\u5019\u9009\u4eba"
	candidate_list.add_child(header)
	for candidate in GameManager.all_employee_candidates:
		var card := VBoxContainer.new()
		var already_hired := store.get_employee(candidate.id) != null
		var label := Label.new()
		label.text = "%s\uff5c%s\n\u65f6\u85aa %.0f \u5143 \u00b7 \u62db\u8058\u8d39 %.0f \u5143 \u00b7 \u719f\u7ec3\u5ea6 %.0f%%\n%s" % [candidate.name, "\u3001".join(candidate.skills), candidate.hourly_wage, candidate.recruitment_fee, candidate.skill_level * 100.0, candidate.notes]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(label)
		var hire_button := Button.new()
		hire_button.text = "\u5df2\u96c7\u4f63" if already_hired else "\u62db\u8058"
		hire_button.disabled = already_hired or GameManager.player_state.cash < candidate.recruitment_fee
		hire_button.pressed.connect(func() -> void:
			var result := GameManager.hire_employee(candidate.id)
			status_label.text = str(result.get("reason", ""))
			refresh()
			employee_changed.emit()
		)
		card.add_child(hire_button)
		candidate_list.add_child(card)
		candidate_list.add_child(HSeparator.new())

func _clear_children(container: Container) -> void:
	for child in container.get_children():
		child.queue_free()
