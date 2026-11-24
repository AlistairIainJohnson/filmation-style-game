@tool
extends EditorScenePostImport
## Post-import hygiene for normalized Filmation GLBs: enforces clean shadow/GI settings
## and prevents orthographic LOD popping on architectural meshes.


func _post_import(scene: Node) -> Object:
	_process_node(scene)
	return scene


func _process_node(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst: MeshInstance3D = node as MeshInstance3D
		mesh_inst.layers = 1
		mesh_inst.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
		mesh_inst.visibility_range_end = 0.0
		mesh_inst.lod_bias = 1.0
	for child: Node in node.get_children():
		_process_node(child)
