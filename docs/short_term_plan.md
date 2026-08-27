# 短期开发计划（已完成）

本计划六项均已完成并通过既有契约验证。本文档是实现状态、涉及文件与方法的独立交接记录；后续开发须由新的、明确排序的计划定义。

## 1. 门店固定成本与商品变动成本 — 已完成

- **涉及文件：** `scripts/autoload/GameManager.gd`、`scripts/settlement/SettlementEngine.gd`、`scripts/settlement/SettlementResult.gd`、`scripts/store/Store.gd`
- **实现方法：** `GameManager.finalize_slot_simulation()` 每小时生成一条门店固定成本记录，拆分租金、品类占用、设备、仓储与排班工资；商品结算仅记录原料、单位水电等订单变动成本。

## 2. 五类人群保留到订单生成层 — 已完成

- **涉及文件：** `scripts/settlement/SettlementEngine.gd`、`scripts/settlement/CategoryServiceSimulator.gd`、`scripts/settlement/CustomerSimulator.gd`
- **实现方法：** 结算参数生成 `group_profiles`；品类/商品服务模拟器按客群抽取订单，并保留客群漏斗与订单汇总。

## 3. 消费能力、商品目标人群和偏好时段 — 已完成

- **涉及文件：** `scripts/config/CustomerPreferenceConfig.gd`、`scripts/settlement/SettlementEngine.gd`
- **实现方法：** `CustomerPreferenceConfig` 提供客群、消费层级和时段亲和度；结算层将其接入客流、转化率与价格拒绝率。

## 4. 菜单加权选择 — 已完成

- **涉及文件：** `scripts/settlement/CategoryServiceSimulator.gd`
- **实现方法：** `CategoryServiceSimulator._pick_product_option()` 按当前客群的 `weight_by_group` 在商品选项中执行加权选择。

## 5. 共享产能池 — 已完成

- **涉及文件：** `scripts/settlement/CategoryServiceSimulator.gd`、`scripts/autoload/GameManager.gd`
- **实现方法：** 每个店铺品类使用一个 `CategoryServiceSimulator` 到达流和 `next_service_available_at` 共享产能；商品保留独立结算账本。

## 6. 竞争门店和多店客流分配 — 已完成

- **涉及文件：** `scripts/autoload/GameManager.gd`、`scripts/spatial/MarketAllocator.gd`、`scripts/spatial/TradeAreaCalculator.gd`
- **实现方法：** `GameManager.begin_slot_simulation()` 先全局收集参与者，再按区块×客群×品类共享市场池分配自然客流；`MarketAllocator` 负责外部竞争扣减与确定性整数分配。

## 验证依据

- `tests/StoreOperationsEvolutionContractTest.gd` 覆盖固定成本拆分、客群订单摘要、菜单选择、共享队列与市场池分配。
- 已执行脚本扫描与现有契约测试；用户已确认全部通过。
