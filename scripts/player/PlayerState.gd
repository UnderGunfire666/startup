class_name PlayerState
extends RefCounted
## 玩家（人物）状态：资金与压力属于角色本身，不随门店的开设/更换而重置为0，
## 仅在选择出身（重新开局）时才会被出身模板初始化。

var cash: float = SettlementConfig.INITIAL_CASH
var stress: float = SettlementConfig.INITIAL_STRESS

func reset_to_defaults() -> void:
	cash = SettlementConfig.INITIAL_CASH
	stress = SettlementConfig.INITIAL_STRESS

## 结算后应用财务与压力变化。口碑变化不在这里处理，
## 口碑属于 StoreState.apply_settlement()。
func apply_settlement(result: SettlementResult) -> void:
	cash += result.profit
	stress = clampf(stress + result.stress_delta, 0.0, 100.0)

func to_save_dict() -> Dictionary:
	return {
		"cash": cash,
		"stress": stress,
	}

static func from_save_dict(data: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	p.cash = data.get("cash", SettlementConfig.INITIAL_CASH)
	p.stress = data.get("stress", SettlementConfig.INITIAL_STRESS)
	return p
