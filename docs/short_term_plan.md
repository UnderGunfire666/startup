# 短期开发计划：稳定地图旅行与 5 倍速运行基线

> 更新于 2026-09-02。本计划是当前唯一的短期执行顺序；新功能先暂停扩张，优先把地图数据、契约测试和持续运行性能收敛为可重复验证的基线。

## 当前结论

最近一轮已经完成以下能力：

- 12 个区块使用显式 `internal_road_cells`，导航只允许经过完整外部道路面、内部道路、住宅专用格和门面入口。
- 3 处玩家住宅已独立建模；出生点保留在住宅格，不会落到内部道路上。
- 地图编辑器可编辑内部道路与住宅，并处理 `roads.json`、`blocks.json`、`storefronts.json`、`player_homes.json` 四份数据。
- 旅行途中停止会结算到路线上的下一已到达格；区块调研会在内部道路及紧邻外部道路上确定性随机行走和停顿。
- 抵达门面即记录到访；营业中抵达可永久解锁只读店内视图，其他到访至少解锁门头。地图详情显示店名、营业时段、当前状态与可靠倒计时。
- 静态地图与玩家动态图层已分离；导航网、路线、入口和标签布局已缓存；普通 UI 的时钟刷新最多 10Hz；经营动态使用固定容量节点池。

当前验证结果：P0、P1 已完成。正式地图、地图编辑器四文件工作流和 UI 事件状态均恢复全绿；`PlayerMovementContractTest` 为 103/103，`UIStateContractTest` 为 34/34，`MapAuthoringToolContractTest` 为 42/42，`MapTravelPerformanceContractTest` 为 22/22，真实窗口 `MapTravelRealtimeAcceptance` 为 14/14。旅行、地图展示、调研、存档与道路图重点契约同步通过。

## P0：恢复全绿验证基线（已完成）

### 1. 修复正式地图数据校验（已完成）

- 输出 `MapDataValidator` 对正式四份空间 JSON 的完整错误明细。
- 修正数据或验证器中不一致的入口、连通性、占格或归属规则；不恢复“整块普通格可走”的兼容回退。
- 保证每个住宅入口和门面入口均与内部道路相邻且可由完整道路网络到达。
- `block_se_office` 新增入口道路格 `(35,35)`，将 `sf_se_lunch` 的南侧入口连接至既有内部道路；`PlayerMovementContractTest` 已全绿。

### 2. 更新过时的 UI 事件契约（已完成）

- 将 `UIStateContractTest` 从旧的两个决策按钮改为当前事件定义驱动的四选项断言。
- 验证按钮文本、可用性、选项效果和事件完成状态，而不是硬编码旧界面结构。
- 经营面板现在与全局事件弹窗一致：显示全部选项，禁用特性锁定项并展示锁定原因；既有事件选择与效果规则未改变。

### P0 完成标准

- Godot 无头脚本扫描与主场景启动无解析或编译错误。
- 地图、移动、旅行、调研、门面、布局、存档、事件、UI 状态和实时经营相关契约全部通过。
- `git diff --check` 无格式错误。

## P1：建立 5 倍速持续运行性能验收（已完成）

### 3. 增加可重复的性能回归场景（已完成）

- 固定地图、路线、随机种子和经营配置，分别以 1、2、5 倍速执行同一段至少 30 秒真实时间的移动。
- 记录静态地图绘制次数、动态图层绘制次数、导航网构建次数、对象/节点数量和分帧时间摘要。
- 断言静态绘制次数不随移动帧数增长，导航缓存没有按时钟重建，经营动态节点数保持固定。
- 比较相同游戏时刻的玩家插值位置，以及最终到达时间、位置、精力、费用、订单顺序、库存与收入，确保优化不改变权威结果。
- `MapTravelPerformanceContractTest` 以 1800 个 60 FPS 等价帧覆盖 30 秒持续移动，并输出首尾批次耗时作为诊断信息；耗时不设硬件相关阈值。
- 当前基线为：静态地图重绘 0 次、动态图层持续刷新、路线缓存构建 1 次、导航网重建 0 次、场景节点数 `192 → 192`；1/2/5 倍速权威结果一致。

### 4. 完成真实渲染性能验收（已完成）

- 在地图页以 5 倍速连续移动至少 30 秒，同时保持玩家店铺经营模拟运行。
- 使用 Godot Profiler 对比移动开始后 0–5 秒与 20–30 秒的帧时间、节点数和热点；不得出现随运行时长持续恶化。
- 覆盖停止行动、重新出发、切换地图选择、读档和调研步行，确认所有缓存正确失效。
- `MapTravelRealtimeAcceptance` 使用 Windows OpenGL 渲染器、60 FPS 上限和 5 倍速运行 30 秒，自动保持玩家店铺经营并在远端门面间重新出发。
- 实测 1801 帧：前 5 秒平均 `16.649ms`、后 10 秒平均 `16.666ms`，P95 为 `16.680ms → 16.687ms`；静态重绘 0、导航重建 0、节点 `273 → 273`，玩家店铺订单 `0 → 518`。
- 停止/选择、连续调研、读档及道路报价分别由对应契约回归保护；未出现约 5 秒后逐步加重的帧时恶化。

### P1 完成标准

- 5 倍速持续移动无约 5 秒后逐步加重的可感知卡顿。
- 性能回归场景可重复运行，并能在静态层误重绘、导航误重建或 UI 节点增长时失败。
- 1/2/5 倍速下的权威游戏结果一致。

## P2：空间数据工作流收尾（已完成）

### 5. 固化编辑器与运行时往返

- 回归内部道路添加/删除限制、住宅创建/移动/扩展/删除、自动入口和对象互斥选中面板。
- 对四份空间 JSON 执行导入 → 导出 → 重载往返，确认坐标排序稳定且无字段丢失。
- 验证门面布局入口保存后，地图青蓝色入口边段、旅行目标及导航缓存同步更新。
- 验证旧存档的住宅位置和门面到访情报兼容：旧 `visited` 只开放门头，营业中再次抵达后才升级室内权限。

实现结果：四文件导出现在按对象 ID 与坐标稳定排序，并可由四份 JSON 内容直接重建、校验和再次导出；补齐了先前导入时遗漏的区块经营字段与门面业务字段。住宅支持独立拖动和缩减占格，所有修改在入口无效、越界、重叠或断连时原子回滚。对象选择、导入及文档切换会清理失效选择。新增契约覆盖四文件字节稳定往返、住宅编辑、内部道路回滚、入口导航/绘制缓存同步以及旧存档住宅与访问权限迁移。

验收结果（2026-09-03）：Bazzite 上使用 Godot `4.7.2.stable.flathub.ed1daf0bf`、OpenGL Compatibility 与 NVIDIA GeForce RTX 4070 SUPER 完成脚本扫描、主场景启动、28 个无头契约场景和真实窗口旅行验收，全部退出码为 0；`git diff --check` 同样通过。真实窗口共渲染 5394 帧并完成 3 次长途旅行，平均帧时 `5.538ms → 5.568ms`、P95 `5.699ms → 5.729ms`，静态重绘 0、导航重建 0、节点 `273 → 273`，玩家店铺订单 `0 → 518`。

### P2 完成标准

- 正式地图和编辑器导出数据均通过同一个 `MapDataValidator`。
- 住宅不成为跨区捷径，玩家出生格不是内部道路格。
- 编辑入口、导入地图或读档后，不残留旧导航路线或旧入口显示。

## 本轮不纳入

- 实时交通、拥堵、行人或逐个顾客地图寻路。
- 员工 AI、员工寻路或连续物理坐标存档。
- 新城区、地图内容扩量、墙体编辑和完整美术替换。
- 新的经营深度功能；这些工作在上述稳定性门槛完成后重新排序。

## 下一步

P2 稳定性门槛已在 Godot 4.7.2 的 Bazzite 原生环境全绿。下一工作切换为“经营深化方向排序”，在布局效率与动线、供应链深化、多店监管三项中选择一条形成独立计划，不并行展开。Windows 复跑保留为跨平台发布验证，不再阻塞 P2 功能收口。

Windows 验收入口：在仓库根目录运行 `powershell -ExecutionPolicy Bypass -File tools/run_p2_validation.ps1`。脚本会执行 28 个无头契约、主场景扫描及 30 秒真实窗口验收，并将逐项日志与 `summary.json` 写入 `.artifacts/p2-validation/<timestamp>/`；可通过 `-GodotPath` 覆盖默认引擎路径，或用 `-SkipRealtime` 只执行无头部分。

---

## 历史计划归档：范围化线下竞争与有限需求池（已完成）

- 同品类门店以双向判定的 `competition_radius` 建立竞争关系：其他门店在本店范围内，或本店在其他门店范围内，任一成立即竞争。
- 自然到店客流按区块、人群、品类、时段形成一次性有限池；竞争门店以距离修正后的门店影响力与菜单商品影响力共同分配，因此强店多卖会直接压缩同池其他门店的份额。
- 新增 `Store.offline_influence` 与 `ProductData.offline_influence`。商品影响力先汇总为该品类菜单的到店竞争权重，并用于店内商品选择。
- 目的性/营销带来的线上客流保持独立，不读取上述影响力或竞争范围。线上门店/商品竞争力列为后续功能。

本计划六项均已完成并通过既有契约验证。其后完成的事件文本叙事化模块记录于“后续完成模块”；本文档是实现状态、涉及文件与方法的独立交接记录。后续功能开发须由新的、明确排序的计划定义。

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

## 后续完成模块

### 事件文本叙事化 — 已完成

- **涉及文件：** `scripts/autoload/EventManager.gd`、`scripts/events/GameEventDefinition.gd`、`scenes/panels/EventPopup.gd`、`scripts/autoload/BlockDiscoveryManager.gd`、`scripts/settlement/CustomerSimulator.gd`、`scripts/settlement/CategoryServiceSimulator.gd`、`scenes/map/CityMapPanel.gd`、`scenes/panels/OperationPanel.gd`、`scripts/autoload/ScheduleManager.gd`。
- **实现方法：** 全局事件、调研链、特性限定选项、区块发现、行动中断、地图反馈、营业日志与顾客反馈均改为紧凑叙事文本；高频事件和顾客反馈使用文本变体。事件实例快照所选文案，因此历史与存档仍保持一致；事件效果、进度、结算与失败代码均未改变。
- **验证：** `tests/EventSystemContractTest.gd` 覆盖选项说明与事件文本变体；`tests/BlockDiscoveryContractTest.gd` 覆盖消费、需求、竞争发现文本及兼容调研路径复用。已执行 `git diff --check` 与 Godot 无头脚本扫描，未报告脚本解析错误。

## 验证依据

- **Godot 控制台可执行文件：** `D:\Programs\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64_console.exe`。后续无头契约测试与脚本扫描直接使用此路径。

- `tests/StoreOperationsEvolutionContractTest.gd` 覆盖固定成本拆分、客群订单摘要、菜单选择、共享队列与市场池分配。
- 已执行脚本扫描与现有契约测试；用户已确认全部通过。
