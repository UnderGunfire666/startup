extends Control
## 建议位置：res://scenes/map/CityMapPanel.gd
## v4变更：不再用测试按钮直接调advance_block_understanding()，
## 改为通过ScheduleManager.start_action_now()真实触发region_research/
## deep_inspection行动（走真正的时间/精力成本）。storefront_inspection
## 暂不提供触发入口——见对话中说明，它已经被自动发现机制取代。

@onready var map_canvas: CityMapCanvas = $HBoxContainer/MapScrollContainer/MapCanvas
@onready var instruction_label: Label = $HBoxContainer/SidePanel/InstructionLabel
@onready var report_label: Label = $HBoxContainer/SidePanel/ReportScroll/ReportLabel
@onready var advance_basic_button: Button = $HBoxContainer/SidePanel/AdvanceBasicButton
@onready var status_label: Label = $HBoxContainer/SidePanel/StatusLabel
@onready var storefront_info_label: Label = $HBoxContainer/SidePanel/StorefrontInfoLabel
@onready var deep_inspection_button: Button = $HBoxContainer/SidePanel/DeepInspectionButton

var _selected_survey_area_id: String = ""
var _selected_storefront_id: String = ""


func _ready() -> void:
	map_canvas.setup(GameManager.all_city_regions, GameManager.all_blocks)
	map_canvas.survey_drag_finished.connect(_on_survey_drag_finished)
	map_canvas.survey_drag_rejected.connect(_on_survey_drag_rejected)
	map_canvas.survey_area_clicked.connect(_on_survey_area_clicked)
	map_canvas.storefront_clicked.connect(_on_storefront_clicked)

	## 唯一保留的按钮：真正发起region_research行动，target_id=当前选中的调查区。
	advance_basic_button.text = "开始区域调研（占用当前行动）"
	advance_basic_button.pressed.connect(_on_start_region_research_pressed)

	deep_inspection_button.pressed.connect(_on_start_deep_inspection_pressed)
	deep_inspection_button.disabled = true

	instruction_label.text = "拖拽(起点终点连线=直径)框选调查范围；点击已发现的门面标记可查看尽调信息。"
	refresh()


func refresh() -> void:
	map_canvas.refresh_survey_areas(GameManager.player_state.survey_areas)
	map_canvas.refresh_storefronts(GameManager.all_storefronts)
	_refresh_report()
	_refresh_storefront_info()


func _on_survey_drag_finished(city_region_id: String, center: Vector2, radius: float) -> void:
	var result: Dictionary = GameManager.create_survey_area(city_region_id, center, radius)
	status_label.text = ("✅ " if result.get("success", false) else "⚠ ") + str(result.get("reason", ""))

	if result.get("success", false):
		_selected_survey_area_id = str(result.get("survey_area_id", ""))
		refresh()


func _on_survey_drag_rejected(reason: String) -> void:
	status_label.text = "⚠ %s" % reason


func _on_survey_area_clicked(survey_area_id: String) -> void:
	_selected_survey_area_id = survey_area_id
	_refresh_report()


func _on_storefront_clicked(storefront_id: String) -> void:
	_selected_storefront_id = storefront_id
	_refresh_storefront_info()


func _on_start_region_research_pressed() -> void:
	if _selected_survey_area_id.is_empty():
		status_label.text = "⚠ 请先框选或点击一个调查区"
		return

	## 真正走ScheduleManager，占用当前行动槏位、消耗精力，
	## target_id=调查区id，效果由ScheduleManager._apply_region_research_effect()处理。
	var result: Dictionary = ScheduleManager.start_action_now("region_research", _selected_survey_area_id)
	status_label.text = ("✅ " if result.get("can", false) else "⚠ ") + str(result.get("reason", ""))


func _on_start_deep_inspection_pressed() -> void:
	if _selected_storefront_id.is_empty():
		status_label.text = "⚠ 请先点击地图上的一个门面"
		return

	var result: Dictionary = ScheduleManager.start_action_now("deep_inspection", _selected_storefront_id)
	status_label.text = ("✅ " if result.get("can", false) else "⚠ ") + str(result.get("reason", ""))
	_refresh_storefront_info()


func _refresh_report() -> void:
	if _selected_survey_area_id.is_empty():
		report_label.text = "尚未选择调查区。"
		return

	var blocks := GameManager.get_blocks_for_survey_area(_selected_survey_area_id)
	if blocks.is_empty():
		report_label.text = "该调查区未命中任何区块。"
		return

	var lines: Array[String] = []
	for block in blocks:
		var understanding := GameManager.get_block_understanding(block.id)
		var block_report := SurveyReportBuilder.build_block_report(block, understanding)
		lines.append("【%s】了解度 %.0f (%s)" % [
			str(block_report.get("name", "")),
			understanding,
			str(block_report.get("tier", "")),
		])

	report_label.text = "\n".join(lines)


func _refresh_storefront_info() -> void:
	if _selected_storefront_id.is_empty():
		storefront_info_label.text = "尚未选择门面。"
		deep_inspection_button.disabled = true
		return

	var storefront := GameManager.get_storefront(_selected_storefront_id)
	var diligence := GameManager.get_storefront_diligence(_selected_storefront_id)
	var report := SurveyReportBuilder.build_storefront_report(storefront, diligence)

	if not report.get("success", false):
		storefront_info_label.text = "⚠ %s" % str(report.get("reason", ""))
		deep_inspection_button.disabled = true
		return

	var lines: Array[String] = []
	lines.append("门面：%s（%s）" % [str(report.get("name", "")), str(report.get("diligence_label", ""))])

	if report.has("monthly_rent_yuan"):
		lines.append("月租：¥%.0f ｜ 面积：%.0f㎡ ｜ 装修：%s" % [
			float(report.get("monthly_rent_yuan", 0.0)),
			float(report.get("area", 0.0)),
			str(report.get("decoration_level", "")),
		])
		lines.append(str(report.get("inspection_summary", "")))

	if report.has("deep_inspection_summary"):
		lines.append("完整尽调：%s" % str(report.get("deep_inspection_summary", "")))

	storefront_info_label.text = "\n".join(lines)
	deep_inspection_button.disabled = (diligence != "initial_viewing")
