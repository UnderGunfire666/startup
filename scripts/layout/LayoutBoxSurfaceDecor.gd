class_name LayoutBoxSurfaceDecor
extends RefCounted

## Adds visible-box decorations to the five exposed faces. The underside stays bare.


static func add_five_faces(instance: MeshInstance3D, box_size: Vector3, texture: Texture2D, side_color: Color) -> void:
	if instance == null or texture == null:
		return
	_add_textured_face(instance, "TopDecal", Vector2(box_size.x, box_size.z), Vector3(0.0, box_size.y * 0.5 + 0.008, 0.0), Vector3.ZERO, texture, 0.045)
	_add_textured_face(instance, "FrontDecal", Vector2(box_size.x, box_size.y), Vector3(0.0, 0.0, box_size.z * 0.5 + 0.008), Vector3(PI * 0.5, 0.0, 0.0), texture, 0.045)
	_add_colored_face(instance, "BackSurface", Vector2(box_size.x, box_size.y), Vector3(0.0, 0.0, -box_size.z * 0.5 - 0.008), Vector3(-PI * 0.5, 0.0, 0.0), side_color)
	_add_colored_face(instance, "LeftSurface", Vector2(box_size.z, box_size.y), Vector3(-box_size.x * 0.5 - 0.008, 0.0, 0.0), Vector3(0.0, 0.0, PI * 0.5), side_color)
	_add_colored_face(instance, "RightSurface", Vector2(box_size.z, box_size.y), Vector3(box_size.x * 0.5 + 0.008, 0.0, 0.0), Vector3(0.0, 0.0, -PI * 0.5), side_color)


static func _add_textured_face(parent: MeshInstance3D, face_name: String, face_size: Vector2, position: Vector3, rotation: Vector3, texture: Texture2D, padding: float) -> void:
	var fitted_rect := LayoutSpriteCatalog.fit_source_in_rect(texture.get_size(), Rect2(Vector2.ZERO, face_size), padding)
	if fitted_rect.size == Vector2.ZERO:
		return
	var face := _create_plane(face_name, fitted_rect.size, position, rotation)
	face.material_override = _create_material(Color.WHITE, texture)
	parent.add_child(face)


static func _add_colored_face(parent: MeshInstance3D, face_name: String, face_size: Vector2, position: Vector3, rotation: Vector3, color: Color) -> void:
	var face := _create_plane(face_name, face_size, position, rotation)
	face.material_override = _create_material(color)
	parent.add_child(face)


static func _create_plane(face_name: String, face_size: Vector2, position: Vector3, rotation: Vector3) -> MeshInstance3D:
	var face := MeshInstance3D.new()
	face.name = face_name
	var mesh := PlaneMesh.new()
	mesh.size = face_size
	face.mesh = mesh
	face.position = position
	face.rotation = rotation
	return face


static func _create_material(color: Color, texture: Texture2D = null) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.albedo_texture = texture
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	material.texture_repeat = false
	return material
