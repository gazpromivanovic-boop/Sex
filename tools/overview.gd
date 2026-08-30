extends SceneTree
## Общий вид уровня — примерно то, что видно в 3D-вьюпорте редактора.

var frames := 0
var main_node: Node
var cam: Camera3D


func _initialize() -> void:
	main_node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_node)
	main_node.get_node("HUD").visible = false
	cam = Camera3D.new()
	main_node.add_child(cam)
	cam.position = Vector3(21, 16, 27)
	cam.fov = 50.0
	cam.far = 400.0


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 10:
		cam.look_at(Vector3(-2.0, 1.0, -2.0))
		cam.make_current()
		print("###CAM active=", root.get_camera_3d(), " pos=", root.get_camera_3d().global_position)
	if frames == 60:
		root.get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://") + "../shots/00_level_overview.png")
		print("###SHOT overview from ", root.get_camera_3d().global_position)
		quit()
	return false
