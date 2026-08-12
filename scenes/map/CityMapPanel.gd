extends Control
## 地图页：框选调查区→触发"区域调研"行动提升区块了解度→
## 了解度达标后自动发现门面→对发现的门面做深度勘验→
## 勘验完成后可以"选定此门面"落实到当前企划（激活店铺）上。
##
## 本版修正：
## - 原来的"推进基础/市场/深度尽调"三个按钮调用的GameManager.advance_survey()/
##   get_survey_report()在真实GameManager.gd里根本不存在，一点就崩。
##   区块了解度的推进统一改为通过ScheduleManager.start_action_now("region_research", ...)
##   触发真正的"区域调研"行动（会消耗时间/精力，效果由ScheduleManager结算时应用）。
## - 新增"已发现门面"列表：显示当前城市区域里已经进入initial_viewing/
##   full_diligence状态的门面，提供"深度勘验"和"选定此门面"两个操作。
##   "选定此门面"会调用GameManager.select_region()+select_storefront()，
##   对象是当前激活的店铺（企划）——如果玩家还没创建企划，会提示先去
##   "我的店铺"新建。

@onready var map_canvas: CityMapCanvas = $HBoxContainer/MapScrollContainer/MapCanvas
@onready var instruction_label: Label = $HBoxContainer/SidePanel/InstructionLabel
@onready var report_label: Label = $HBoxContainer/SidePanel/ReportScroll/ReportLabel
@onready var status_label: Label = $HBoxContainer/SidePanel/StatusLabel

## 原来的三个"推进调查"按钮，现在只保留一个，改绑到区域调研行动。
@onready var start_research_button: Button = $HBoxContainer/SidePanel/AdvanceBasicButton

## 新增：已发现门面列表容器。如果你的CityMapPanel.tscn里还没有这个节点，
## 需要在SidePanel下新建一个ScrollContainer+VBoxContainer，命名如下。
@onready var storefront_list: VBoxContainer = $HBoxContainer/SidePanel/StorefrontScroll/StorefrontList

var _selected_survey_area_id: String = ""


func _ready() -> void:
	map_canvas.setup(GameManager.all_city_regions, GameManager.all_blocks)
	map_canvas.survey_drag_finished.connect(_on_survey_drag_finished)
	map_canvas.survey_drag_rejected.connect(_on_survey_drag_rejected)
	map_canvas.survey_area_clicked.connect(_on_survey_area_clicked)

	start_research_button.text = "开始区域调研（消耗时间）"
	start_research_button.pressed.connect(_on_start_research_pressed)

	instruction_label.text = "在地图上按住鼠标拖拽以框选调查区；点击已有调查区圆圈可查看进度。调研会消耗时间，需要去'行动'或'日程'页排程，这里点按钮是快捷单步触发。"
	refresh()


func refresh() -> void:
	map_canvas.refresh_survey_areas(GameManager.player_state.survey_areas)
	_refresh_report()
	_refresh_storefront_list()


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


## 用ScheduleManager真正触发"区域调研"行动，而不是直接改数值。
## target_id = 调查区id，效果由ScheduleManager._apply_region_research_effect()结算时应用。
func _on_start_research_pressed() -> void:
	if _selected_survey_area_id.is_empty():
		status_label.text = "⚠ 请先框选或点击一个调查区"
		return

	var result: Dictionary = ScheduleManager.start_action_now("region_research", _selected_survey_area_id)
	status_label.text = ("✅ " if result.get("can", false) else "⚠ ") + str(result.get("reason", ""))


func _refresh_report() -> void:
	if _selected_survey_area_id.is_empty():
		report_label.text = "尚未选择调查区。"
		return

	var area := GameManager.player_state.get_survey_area(_selected_survey_area_id)
	if area == null:
		report_label.text = "⚠ 调查区不存在"
		return

	var lines: Array[String] = []
	lines.append("调查区：%s" % area.name)

	var city_region := GameManager.get_city_region(area.city_region_id)
	lines.append("所属城市区域：%s（情报等级 %d）" % [
		city_region.name if city_region != null else "未知",
		GameManager.get_region_intel_level(area.city_region_id),
	])
	lines.append("")

	var blocks := GameManager.get_blocks_for_survey_area(_selected_survey_area_id)
	if blocks.is_empty():
		lines.append("该调查区未覆盖任何区块。")
	else:
		lines.append("覆盖区块了解度：")
		for block in blocks:
			lines.append("  %s：%.0f%%" % [block.name, GameManager.get_block_understanding(block.id)])

	report_label.text = "\n".join(lines)


## 遍历当前选中调查区覆盖到的所有区块，找出已经被发现（storefront_diligence
## 不是not_viewed）的门面，列出来供玩家做深度勘验或选定开店。
func _refresh_storefront_list() -> void:
	for child in storefront_list.get_children():
		child.queue_free()

	if _selected_survey_area_id.is_empty():
		return

	var blocks := GameManager.get_blocks_for_survey_area(_selected_survey_area_id)
	var block_ids: Dictionary = {}
	for block in blocks:
		block_ids[block.id] = true

	var discovered: Array[StorefrontData] = []
	for storefront in GameManager.all_storefronts:
		if GameManager.get_storefront_diligence(storefront.id) == "not_viewed":
			continue
		var block := _find_block_for_storefront(storefront)
		if block == null or not block_ids.has(block.id):
			continue
		discovered.append(storefront)

	if discovered.is_empty():
		var empty_label := Label.new()
		empty_label.text = "该调查区暂未发现门面（区块了解度需要达到一定程度才会发现）。"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		storefront_list.add_child(empty_label)
		return

	for storefront in discovered:
		storefront_list.add_child(_build_storefront_row(storefront))


## 本地实现"门面属于哪个区块"，不依赖GameManager的私有方法，
## 逻辑和GameManager._get_block_for_storefront()一致：同城市区域+
## map_bounds命中门面的map_position。
func _find_block_for_storefront(storefront: StorefrontData) -> BlockData:
	for block in GameManager.all_blocks:
		if block.city_region_id != storefront.city_region_id:
			continue
		if block.map_bounds.has_point(storefront.map_position):
			return block
	return null


func _build_storefront_row(storefront: StorefrontData) -> Control:
	var box := VBoxContainer.new()

	var diligence := GameManager.get_storefront_diligence(storefront.id)
	var diligence_text: String = {
		"initial_viewing": "初步看铺",
		"full_diligence": "完整尽调",
	}.get(diligence, diligence)

	var name_label := Label.new()
	name_label.text = "%s（%s ｜ 状态：%s）" % [storefront.name, storefront.notes, diligence_text]
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(name_label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	if diligence == "initial_viewing":
		var deep_btn := Button.new()
		deep_btn.text = "深度勘验"
		deep_btn.pressed.connect(func():
			var result := ScheduleManager.start_action_now("deep_inspection", storefront.id)
			status_label.text = ("✅ " if result.get("can", false) else "⚠ ") + str(result.get("reason", ""))
		)
		row.add_child(deep_btn)

	var select_btn := Button.new()
	select_btn.text = "选定此门面（落实到当前企划）"
	select_btn.pressed.connect(func(): _on_select_storefront_pressed(storefront))
	row.add_child(select_btn)

	box.add_child(row)
	box.add_child(HSeparator.new())
	return box


## 把这家门面落实到"当前激活的企划"（也就是GameManager.store_state）上：
## 先选定它所属的旧版区域(region_id)，再选定门面本身。
## 如果玩家还没有任何企划（store_state为null），提示去"我的店铺"新建。
func _on_select_storefront_pressed(storefront: StorefrontData) -> void:
	var store := GameManager.store_state
	if store == null:
		status_label.text = "⚠ 你还没有开店企划，请先去'我的店铺'新建一个"
		return

	if store.is_open:
		status_label.text = "⚠ 当前企划对应的店铺已经开业，不能更换门面"
		return

	var region_result := GameManager.select_region(storefront.region_id)
	if not region_result.get("success", false):
		status_label.text = "⚠ %s" % region_result.get("reason", "")
		return

	var storefront_result := GameManager.select_storefront(storefront.id)
	status_label.text = ("✅ " if storefront_result.get("success", false) else "⚠ ") + str(storefront_result.get("reason", ""))

	if storefront_result.get("success", false):
		refresh()
