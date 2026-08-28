class_name RoadGraph
extends RefCounted

var nodes: Dictionary = {}
var segments: Array[RoadSegment] = []

func add_node(node: RoadNode) -> bool:
	if node == null or node.id.is_empty() or nodes.has(node.id):
		return false
	nodes[node.id] = node
	return true

func add_segment(segment: RoadSegment) -> bool:
	if segment == null or segment.id.is_empty() or not nodes.has(segment.from_node_id) or not nodes.has(segment.to_node_id):
		return false
	segments.append(segment)
	return true

func get_shortest_distance(from_node_id: String, to_node_id: String) -> float:
	var path := get_shortest_path(from_node_id, to_node_id)
	if path.is_empty():
		return INF
	var distance := 0.0
	for index in range(1, path.size()):
		distance += (nodes[path[index - 1]] as RoadNode).position.distance_to((nodes[path[index]] as RoadNode).position)
	return distance


func get_shortest_path(from_node_id: String, to_node_id: String) -> Array[String]:
	if not nodes.has(from_node_id) or not nodes.has(to_node_id):
		return []
	if from_node_id == to_node_id:
		return [from_node_id]
	var distances: Dictionary = {from_node_id: 0.0}
	var previous: Dictionary = {}
	var pending: Dictionary = {from_node_id: true}
	while not pending.is_empty():
		var current_id := _pop_nearest(pending, distances)
		if current_id == to_node_id:
			var path: Array[String] = []
			var cursor := to_node_id
			while not cursor.is_empty():
				path.push_front(cursor)
				cursor = str(previous.get(cursor, ""))
			return path
		for segment in segments:
			var neighbor := ""
			if segment.from_node_id == current_id:
				neighbor = segment.to_node_id
			elif segment.to_node_id == current_id:
				neighbor = segment.from_node_id
			if neighbor.is_empty():
				continue
			var length := (nodes[segment.from_node_id] as RoadNode).position.distance_to((nodes[segment.to_node_id] as RoadNode).position)
			var candidate := float(distances[current_id]) + length
			if candidate < float(distances.get(neighbor, INF)):
				distances[neighbor] = candidate
				previous[neighbor] = current_id
				pending[neighbor] = true
	return []

func _pop_nearest(pending: Dictionary, distances: Dictionary) -> String:
	var best_id := ""
	var best_distance := INF
	for node_id in pending.keys():
		if float(distances.get(node_id, INF)) < best_distance:
			best_id = str(node_id)
			best_distance = float(distances[node_id])
	pending.erase(best_id)
	return best_id

func validate() -> Array[String]:
	var errors: Array[String] = []
	for segment in segments:
		if not nodes.has(segment.from_node_id) or not nodes.has(segment.to_node_id):
			errors.append("segment %s references a missing node" % segment.id)
	return errors
