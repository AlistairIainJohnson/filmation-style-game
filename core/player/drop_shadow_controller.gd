class_name DropShadowController
extends Node3D
## Projects a soft radial drop shadow onto walkable geometry directly beneath
## the character using ShapeCast3D + Decal to clarify jump height under orthographic framing.

const WORLD_VISUAL_LAYER_MASK: int = 1
const WORLD_COLLISION_MASK: int = 1 | 4

@export var max_cast_distance: float = 8.0
@export var base_radius: float = 0.48
@export var max_fade_height: float = 2.5
@export var min_alpha: float = 0.20
@export var max_alpha: float = 0.78

var shape_cast: ShapeCast3D
var decal: Decal


func _init() -> void:
	_ensure_nodes()


func _ensure_nodes() -> void:
	if shape_cast == null or not is_instance_valid(shape_cast):
		shape_cast = ShapeCast3D.new()
		shape_cast.name = "GroundShapeCast"
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.26
		cyl.height = 0.06
		shape_cast.shape = cyl
		shape_cast.position = Vector3(0.0, 0.15, 0.0)
		shape_cast.target_position = Vector3(0.0, -max_cast_distance, 0.0)
		shape_cast.collision_mask = WORLD_COLLISION_MASK
		shape_cast.exclude_parent = true
		shape_cast.enabled = true
		add_child(shape_cast)

	if decal == null or not is_instance_valid(decal):
		decal = Decal.new()
		decal.name = "HeightShadowDecal"
		decal.cull_mask = WORLD_VISUAL_LAYER_MASK
		decal.size = Vector3(base_radius * 2.0, 0.45, base_radius * 2.0)
		decal.upper_fade = 0.05
		decal.lower_fade = 0.05
		decal.texture_albedo = _create_radial_shadow_texture()
		decal.modulate = Color(1.0, 1.0, 1.0, max_alpha)
		add_child(decal)


static func _create_radial_shadow_texture(tex_size: int = 64) -> ImageTexture:
	var img: Image = Image.create_empty(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var half: float = float(tex_size - 1) * 0.5
	for y: int in range(tex_size):
		for x: int in range(tex_size):
			var dx: float = (float(x) - half) / half
			var dy: float = (float(y) - half) / half
			var dist: float = sqrt(dx * dx + dy * dy)
			var falloff: float = clampf(1.0 - dist, 0.0, 1.0)
			var alpha: float = falloff * falloff
			img.set_pixel(x, y, Color(0.0, 0.0, 0.0, alpha))
	return ImageTexture.create_from_image(img)


func _physics_process(_delta: float) -> void:
	update_shadow()


func update_shadow() -> void:
	_ensure_nodes()
	if not is_inside_tree():
		return

	shape_cast.target_position = Vector3(0.0, -max_cast_distance, 0.0)
	shape_cast.force_shapecast_update()
	if shape_cast.is_colliding():
		var hit_y: float = -INF
		for i: int in range(shape_cast.get_collision_count()):
			var pt: Vector3 = shape_cast.get_collision_point(i)
			if pt.y > hit_y:
				hit_y = pt.y
		var height_above: float = maxf(0.0, global_position.y - hit_y)
		var t: float = clampf(height_above / max_fade_height, 0.0, 1.0)
		decal.visible = true
		decal.global_position = Vector3(global_position.x, hit_y + 0.02, global_position.z)
		var diam: float = lerpf(base_radius * 2.0, base_radius * 1.3, t)
		decal.size = Vector3(diam, 0.45, diam)
		decal.modulate = Color(1.0, 1.0, 1.0, lerpf(max_alpha, min_alpha, t))
	else:
		decal.visible = false
