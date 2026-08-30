extends SceneTree
## Куда смотрит корпус в каждой анимации относительно самой модели.
## forward = up x right, right берём по бёдрам.

var main_node: Node
var player: Node
var skel: Skeleton3D
var model: Node3D
var ap: AnimationPlayer
var frames := 0
var names := []
var idx := 0


func _initialize() -> void:
	main_node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_node)
	print("### main=", main_node, " children=", main_node.get_children())


func _bone(n: String) -> Vector3:
	return (skel.global_transform * skel.get_bone_global_pose(skel.find_bone(n))).origin


func _body_yaw() -> float:
	var right := _bone("RightUpLeg") - _bone("LeftUpLeg")
	right.y = 0.0
	right = right.normalized()
	var fwd := Vector3.UP.cross(right)
	return rad_to_deg(atan2(-fwd.x, -fwd.z))     # в тех же единицах, что model_yaw


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		player = main_node.get_node_or_null("Player")
		print("### player=", player)
		skel = player.find_children("*", "Skeleton3D", true, false)[0]
		model = player.get_node("Model")
		ap = player.anim_player
	if frames == 10:
		names = ap.get_animation_list()
		# выключаем дерево, чтобы играть клипы напрямую
		player.get_node("AnimationTree").active = false
	if frames > 10 and idx < names.size():
		var n: String = names[idx]
		ap.play(n)
		ap.seek(ap.current_animation_length * 0.5, true)
		skel.force_update_all_bone_transforms()
		print("### %-12s корпус %7.1f°   модель %7.1f°   разница %7.1f°" % [
			n, _body_yaw(), rad_to_deg(model.rotation.y),
			rad_to_deg(wrapf(deg_to_rad(_body_yaw()) - model.rotation.y, -PI, PI))])
		idx += 1
	if idx >= names.size() and frames > 12:
		quit()
	return false
