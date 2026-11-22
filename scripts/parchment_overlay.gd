## Drives the parchment post-process quad.
## Feeds the sun direction (in view space) to the shader every frame so the
## normal-based tone bands follow the real light, and toggles the effect with Tab.
extends MeshInstance3D

@export var sun: DirectionalLight3D

var _material: ShaderMaterial


func _ready() -> void:
	_material = material_override as ShaderMaterial


func _process(_delta: float) -> void:
	if _material == null:
		return
	var cam := get_viewport().get_camera_3d()
	if sun == null or cam == null:
		return
	# Direction *towards* the light, expressed in the camera's view space,
	# which is the space the normal buffer uses.
	# A DirectionalLight3D shines along its -Z, so the light lies towards +Z.
	var to_light := sun.global_transform.basis.z
	var view_dir := cam.global_transform.basis.inverse() * to_light
	_material.set_shader_parameter("light_dir_view", view_dir)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		visible = not visible
