class_name DioramaCameraRig
extends Node3D
## Fixed orthographic diorama camera rig supporting True Isometric (-35.2644 deg)
## and 2:1 Dimetric (-30.0 deg) projections at 45 deg yaw.

enum ProjectionMode { TRUE_ISOMETRIC, DIMETRIC_2_1 }

const YAW_DEG: float = 45.0
const PITCH_TRUE_ISO_DEG: float = -35.26438968
const PITCH_DIMETRIC_2_1_DEG: float = -30.0
const DEFAULT_CAMERA_DISTANCE: float = 35.0
const MAX_FAR_CLIP: float = 80.0

var camera: Camera3D
var _room_dims: Vector3 = Vector3(12.0, 6.0, 12.0)
var _mode: ProjectionMode = ProjectionMode.TRUE_ISOMETRIC
var _margin: float = 0.10


func _init() -> void:
	_ensure_camera()


func _ensure_camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	var existing: Camera3D = get_node_or_null("DioramaCamera") as Camera3D
	if existing != null:
		camera = existing
	else:
		camera = Camera3D.new()
		camera.name = "DioramaCamera"
		add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.current = true
	return camera


static func get_pitch_deg(mode: ProjectionMode) -> float:
	match mode:
		ProjectionMode.DIMETRIC_2_1:
			return PITCH_DIMETRIC_2_1_DEG
		_:
			return PITCH_TRUE_ISO_DEG


static func mode_from_string(mode_name: String) -> ProjectionMode:
	if mode_name == "dimetric_2_1":
		return ProjectionMode.DIMETRIC_2_1
	return ProjectionMode.TRUE_ISOMETRIC


static func compute_ortho_size(
	room_dims: Vector3,
	mode: ProjectionMode,
	margin: float = 0.10,
	viewport_aspect: float = 16.0 / 9.0
) -> float:
	var pitch_rad: float = deg_to_rad(absf(get_pitch_deg(mode)))
	var ground_span: float = (room_dims.x + room_dims.z) * 0.7071067811865476
	var size_v: float = (1.0 + margin) * (ground_span * sin(pitch_rad) + room_dims.y * cos(pitch_rad))
	var size_h: float = (1.0 + margin) * (ground_span / maxf(viewport_aspect, 0.1))
	return maxf(size_v, size_h)


func configure_for_room(
	room_dims: Vector3,
	mode: ProjectionMode = ProjectionMode.TRUE_ISOMETRIC,
	margin: float = 0.10
) -> void:
	var cam: Camera3D = _ensure_camera()
	_room_dims = room_dims
	_mode = mode
	_margin = margin

	var pitch_deg: float = get_pitch_deg(mode)
	var center: Vector3 = Vector3(room_dims.x * 0.5, room_dims.y * 0.5, room_dims.z * 0.5)
	var euler_rad: Vector3 = Vector3(deg_to_rad(pitch_deg), deg_to_rad(YAW_DEG), 0.0)
	var cam_basis: Basis = Basis.from_euler(euler_rad, EULER_ORDER_YXZ)

	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_HEIGHT
	cam.current = true
	cam.rotation_degrees = Vector3(pitch_deg, YAW_DEG, 0.0)
	cam.position = center + cam_basis.z * DEFAULT_CAMERA_DISTANCE
	cam.size = compute_ortho_size(room_dims, mode, margin)
	cam.near = 0.5
	var max_dim: float = maxf(room_dims.x, maxf(room_dims.y, room_dims.z))
	cam.far = minf(MAX_FAR_CLIP, clampf(DEFAULT_CAMERA_DISTANCE + max_dim * 2.5, 45.0, 65.0))


func set_projection_mode(mode: ProjectionMode) -> void:
	configure_for_room(_room_dims, mode, _margin)


func get_projection_mode() -> ProjectionMode:
	return _mode


func get_camera_right_xz() -> Vector3:
	var cam: Camera3D = _ensure_camera()
	var basis: Basis = Basis.from_euler(
		Vector3(deg_to_rad(cam.rotation_degrees.x), deg_to_rad(cam.rotation_degrees.y), 0.0),
		EULER_ORDER_YXZ
	)
	var right: Vector3 = Vector3(basis.x.x, 0.0, basis.x.z)
	return right.normalized()


func get_camera_forward_xz() -> Vector3:
	var cam: Camera3D = _ensure_camera()
	var basis: Basis = Basis.from_euler(
		Vector3(deg_to_rad(cam.rotation_degrees.x), deg_to_rad(cam.rotation_degrees.y), 0.0),
		EULER_ORDER_YXZ
	)
	var forward: Vector3 = Vector3(-basis.z.x, 0.0, -basis.z.z)
	return forward.normalized()
