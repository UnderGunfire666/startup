class_name MovementConfig

const WALK := "walk"
const BICYCLE := "bicycle"
const TRANSIT := "transit"
const CAR := "car"
const TRAVEL_MODES: Array[String] = [WALK, BICYCLE, TRANSIT, CAR]
const MODE_DATA := {
	WALK: {"name": "步行", "speed": 100.0, "energy_per_hour": 8.0, "cost_per_distance": 0.0, "vehicle": ""},
	BICYCLE: {"name": "骑行", "speed": 220.0, "energy_per_hour": 3.0, "cost_per_distance": 0.0, "vehicle": "bicycle"},
	TRANSIT: {"name": "公共交通", "speed": 260.0, "energy_per_hour": 1.0, "cost_per_distance": 0.60, "vehicle": ""},
	CAR: {"name": "开车", "speed": 360.0, "energy_per_hour": 2.0, "cost_per_distance": 0.90, "vehicle": "car"},
}

static func get_mode_data(mode: String) -> Dictionary:
	return MODE_DATA.get(mode, {}).duplicate(true)

static func get_mode_name(mode: String) -> String:
	return str(get_mode_data(mode).get("name", mode))

static func get_travel_quote(from_node_id: String, to_node_id: String, road_graph: RoadGraph, mode: String, owned_vehicles: Array[String], cash: float, energy: float) -> Dictionary:
	var mode_data := get_mode_data(mode)
	if mode_data.is_empty(): return {"can": false, "reason": "未知出行方式"}
	var required_vehicle := str(mode_data.get("vehicle", ""))
	if not required_vehicle.is_empty() and not owned_vehicles.has(required_vehicle): return {"can": false, "reason": "未拥有%s" % ("自行车" if required_vehicle == BICYCLE else "汽车")}
	var route: Array[String] = road_graph.get_shortest_path(from_node_id, to_node_id) if road_graph != null else []
	if route.is_empty(): return {"can": false, "reason": "道路网络未连通", "fallback": true}
	var distance := 0.0
	for index in range(1, route.size()): distance += (road_graph.nodes[route[index - 1]] as RoadNode).position.distance_to((road_graph.nodes[route[index]] as RoadNode).position)
	var hours := distance / float(mode_data.get("speed", 1.0))
	var cost := distance * float(mode_data.get("cost_per_distance", 0.0))
	var energy_cost := hours * float(mode_data.get("energy_per_hour", 0.0))
	if cash + 0.001 < cost: return {"can": false, "reason": "现金不足", "distance": distance, "hours": hours, "cost": cost, "energy_cost": energy_cost, "route_node_ids": route}
	if energy + 0.001 < energy_cost: return {"can": false, "reason": "精力不足", "distance": distance, "hours": hours, "cost": cost, "energy_cost": energy_cost, "route_node_ids": route}
	return {"can": true, "reason": "", "mode": mode, "distance": distance, "hours": hours, "cost": cost, "energy_cost": energy_cost, "route_node_ids": route, "fallback": false}

static func get_travel_hours(from_block: BlockData, to_block: BlockData, road_graph: RoadGraph = null) -> float:
	if from_block == null or to_block == null: return -1.0
	if from_block.id == to_block.id: return 0.0
	return float(get_travel_quote(from_block.road_entry_node_id, to_block.road_entry_node_id, road_graph, WALK, [], INF, INF).get("hours", -1.0))
