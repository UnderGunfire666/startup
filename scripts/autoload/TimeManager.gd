extends Node
## 全局统一时钟：从角色创建完成后就开始存在，默认暂停。
## 同时驱动"玩家排程行动"（未来由 ScheduleManager 监听 hour_advanced 信号）
## 和"店铺自动经营模拟"（复用 GameManager.begin/advance/finalize_slot_simulation，
## 不改一行结算公式）。
##
## 四个营业时段现在对应真实、不连续的时钟窗口：
##   深夜(midnight) 00:00-05:00 ｜ 清晨(dawn) 05:00-09:00
##   午间(noon)     12:00-14:00 ｜ 晚夜(night) 18:00-24:00
## 09:00-12:00、14:00-18:00 是全店铺不营业的空档，这是既有设计的自然延伸，
## 不是缺陷。

enum Speed { PAUSED = 0, X1 = 1, X2 = 2, X5 = 5 }

const GAME_SECONDS_PER_REAL_SECOND_AT_X1: float = 120.0
const DAY_SECONDS: float = 86400.0

## 每个营业时段在真实时钟上的起始小时（终点 = 起始 + SettlementConfig.SLOT_HOURS[slot]）。
const SLOT_START_HOUR: Dictionary = {
	"midnight": 0,
	"dawn": 5,
	"noon": 12,
	"night": 18,
}

signal clock_updated(hour: int, minute: int, second: int, period_label: String)
signal customer_event(product_name: String, purchased: bool, reason: String)
signal slot_completed(day: int, slot: String, results: Array)
signal day_completed(day: int, summary: Dictionary)
## 供未来的排程/行动系统监听：每当整点小时数变化时触发一次。
## 与 slot_completed 不同，这个信号在营业与非营业时段都会触发。
signal hour_advanced(day: int, hour: int)

var speed: int = Speed.PAUSED
var current_day: int = 1

var total_game_seconds: float = 0.0
var active_slot_id: String = ""   # "" 表示当前处于空档，不营业
var slot_elapsed_seconds: float = 0.0

var _simulation_active: bool = false
var _last_emitted_hour: int = -1
var _last_emitted_day: int = -1

func _ready() -> void:
	_emit_clock()

func _process(delta: float) -> void:
	if speed == Speed.PAUSED:
		return
	if not GameManager.player_state.is_character_created:
		return
	_advance(delta * GAME_SECONDS_PER_REAL_SECOND_AT_X1 * float(speed))


func set_speed(new_speed: int) -> void:
	speed = new_speed
	_emit_clock()


## 开始全新一局时调用（GameManager.create_character() 里会触发），
## 清空所有计时状态，回到第1天00:00、暂停状态。
func reset() -> void:
	speed = Speed.PAUSED
	current_day = 1
	total_game_seconds = 0.0
	active_slot_id = ""
	slot_elapsed_seconds = 0.0
	_simulation_active = false
	_last_emitted_hour = -1
	_last_emitted_day = -1
	_emit_clock()


func get_hour_of_day() -> float:
	return fposmod(total_game_seconds, DAY_SECONDS) / 3600.0


## 供排程系统查询"此刻店铺是否处于营业时段"，不代表店铺真的开业，
## 还需要额外检查 GameManager.store_state.is_open。
func get_active_slot_id() -> String:
	return active_slot_id


func is_store_actually_operating() -> bool:
	return active_slot_id != "" and GameManager.store_state.is_open


func _advance(game_delta: float) -> void:
	var guard_iterations := 0
	while game_delta > 0.0001 and guard_iterations < 10000:
		guard_iterations += 1

		var day_start: float = floor(total_game_seconds / DAY_SECONDS) * DAY_SECONDS
		var hour_now: float = (total_game_seconds - day_start) / 3600.0
		var boundary_hour: float = _next_boundary_hour(hour_now)
		var boundary_abs: float = day_start + boundary_hour * 3600.0
		var step: float = minf(game_delta, boundary_abs - total_game_seconds)
		step = maxf(step, 0.0)

		_tick_active_slot(step)
		total_game_seconds += step
		game_delta -= step

		_after_time_advance()

		if step <= 0.0001:
			break


func _next_boundary_hour(hour_now: float) -> float:
	var best: float = 24.0
	var next_int_hour: float = floor(hour_now) + 1.0
	if next_int_hour < best:
		best = next_int_hour

	for slot_id in SettlementConfig.SLOT_ORDER:
		var start: float = float(SLOT_START_HOUR[slot_id])
		var length: float = float(SettlementConfig.SLOT_HOURS[slot_id])
		var end: float = start + length
		if start > hour_now and start < best:
			best = start
		if end > hour_now and end < best:
			best = end

	return best


func _slot_at_hour(hour: float) -> String:
	for slot_id in SettlementConfig.SLOT_ORDER:
		var start: float = float(SLOT_START_HOUR[slot_id])
		var length: float = float(SettlementConfig.SLOT_HOURS[slot_id])
		var end: float = start + length
		if hour >= start and hour < end:
			return slot_id
	return ""


func _tick_active_slot(step: float) -> void:
	if active_slot_id == "" or not GameManager.store_state.is_open:
		return

	if not _simulation_active:
		_start_active_slot_simulation()

	slot_elapsed_seconds += step
	GameManager.advance_slot_simulation(slot_elapsed_seconds)


func _start_active_slot_simulation() -> void:
	GameManager.store_state.current_slot_index = SettlementConfig.SLOT_ORDER.find(active_slot_id)
	GameManager.begin_slot_simulation()
	for entry in GameManager.active_simulations:
		if entry.sim != null:
			entry.sim.customer_event.connect(
				func(purchased, reason): customer_event.emit(entry.product.name, purchased, reason))
	_simulation_active = true


func _after_time_advance() -> void:
	var target_hour: float = get_hour_of_day()
	var target_day: int = 1 + int(total_game_seconds / DAY_SECONDS)
	var new_slot: String = _slot_at_hour(target_hour)

	if new_slot != active_slot_id:
		_on_slot_transition(new_slot)

	if target_day != current_day:
		var finished_day := current_day
		current_day = target_day
		GameManager.store_state.current_day = current_day
		if GameManager.store_state.is_open:
			var summary := GameManager.store_state.get_day_summary(finished_day)
			day_completed.emit(finished_day, summary)

	var hour_int: int = int(target_hour)
	if hour_int != _last_emitted_hour or target_day != _last_emitted_day:
		_last_emitted_hour = hour_int
		_last_emitted_day = target_day
		hour_advanced.emit(current_day, hour_int)

	_emit_clock()


func _on_slot_transition(new_slot: String) -> void:
	if active_slot_id != "" and _simulation_active:
		var finished_slot := active_slot_id
		var finished_day := current_day
		var results := GameManager.finalize_slot_simulation()
		_simulation_active = false
		slot_completed.emit(finished_day, finished_slot, results)

	active_slot_id = new_slot
	slot_elapsed_seconds = 0.0

	if new_slot != "" and GameManager.store_state.is_open:
		_start_active_slot_simulation()


func _emit_clock() -> void:
	var seconds_in_day: float = fposmod(total_game_seconds, DAY_SECONDS)
	var total_seconds: int = int(seconds_in_day)
	var h := (total_seconds / 3600) % 24
	var m := (total_seconds / 60) % 60
	var s := total_seconds % 60
	clock_updated.emit(h, m, s, _period_label(h))


## 纯展示用的时段标签，现在与四个营业slot的真实时钟窗口完全对齐，
## 空档时段单独标注，方便玩家理解"为什么这会儿没生意"。
func _period_label(hour: int) -> String:
	if hour >= 0 and hour < 5: return "深夜"
	elif hour >= 5 and hour < 9: return "清晨"
	elif hour >= 9 and hour < 12: return "上午（空档）"
	elif hour >= 12 and hour < 14: return "午间"
	elif hour >= 14 and hour < 18: return "下午（空档）"
	else: return "晚夜"


func to_save_dict() -> Dictionary:
	return {
		"speed": speed,
		"current_day": current_day,
		"total_game_seconds": total_game_seconds,
	}


func apply_save_dict(data: Dictionary) -> void:
	speed = Speed.PAUSED
	current_day = int(data.get("current_day", 1))
	total_game_seconds = float(data.get("total_game_seconds", 0.0))
	active_slot_id = _slot_at_hour(get_hour_of_day())
	slot_elapsed_seconds = 0.0
	_simulation_active = false
	_last_emitted_hour = -1
	_last_emitted_day = -1
	_emit_clock()
