extends SceneTree
## Финальная проверка вида от первого лица (камера привязана к кости головы):
##  A/B — работает ли скрытие головы (hide вкл/выкл);
##  C/D — видно ли собственные ноги при взгляде вниз стоя и на ходу
##        (это и был баг «проваливаюсь сквозь модельку»);
##  E   — бег с взглядом вниз, самый тяжёлый случай для наезда корпуса;
##  F   — взгляд вверх, не лезет ли что-то в кадр.

var main_node: Node
var player: Node
var stage := 0
var ticks := 0
var guard := 0
var pending := ""

const ACTIONS := ["move_forward", "move_back", "move_left", "move_right",
	"aim", "sprint", "jump"]


func _initialize() -> void:
	main_node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_node)
	player = main_node.get_node("Player")
	main_node.get_node("HUD").visible = false


func _hold(list: Array) -> void:
	for a in ACTIONS:
		if a in list:
			Input.action_press(a)
		else:
			Input.action_release(a)


func _shoot(name: String) -> void:
	pending = name
	stage += 1
	ticks = 0
	guard = 0
	paused = true


func _reset(pitch_deg: float, keys: Array) -> void:
	_hold([])
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.1, 6.0)
	player.model_yaw = 0.0
	player.yaw = 0.0
	player.pitch = deg_to_rad(pitch_deg)
	if not player.first_person:
		player.first_person = true
		player._apply_view()
	_hold(keys)


## Насколько камера утоплена в корпус: расстояние от камеры до оси тела в плане.
func _report() -> String:
	var cam: Vector3 = player.cam_first.global_position
	var body: Vector3 = player.global_position
	var flat := Vector2(cam.x - body.x, cam.z - body.z).length()
	var txt := " глаза y=%.2f вынос=%.3f м" % [cam.y - body.y, flat]
	var sk = player.skeleton
	if sk != null and player.head_bone >= 0:
		var head: Vector3 = (sk.global_transform
			* sk.get_bone_global_pose(player.head_bone)).origin
		txt += " до кости головы=%.3f м" % cam.distance_to(head)
	return txt


func _physics_process(_delta: float) -> bool:
	if pending != "":
		return false
	ticks += 1
	guard += 1
	if guard > 3000:
		print("###FIN застряло на этапе ", stage)
		quit()
		return false

	match stage:
		0:
			_reset(-20.0, [])
			player.head_hider.hide_bone = true
			stage = 1
		1:
			if ticks > 40:
				_shoot("fin_A_head_hidden.png")
		2:
			player.head_hider.hide_bone = false
			stage = 3
		3:
			if ticks > 25:
				_shoot("fin_B_head_visible.png")
		4:
			player.head_hider.hide_bone = true
			_reset(-75.0, [])
			stage = 5
		5:
			if ticks > 30:
				_shoot("fin_C_look_down_standing.png")
		6:
			_reset(-75.0, ["move_forward"])
			stage = 7
		7:
			if player.get_horizontal_speed() > 1.5 and ticks > 45:
				_shoot("fin_D_look_down_walking.png")
		8:
			_reset(-70.0, ["move_forward", "sprint"])
			stage = 9
		9:
			if player.get_horizontal_speed() > 5.0 and ticks > 60:
				_shoot("fin_E_look_down_sprint.png")
		10:
			_reset(40.0, [])
			stage = 11
		11:
			if ticks > 30:
				_shoot("fin_F_look_up.png")
		12:
			print("###FIN done")
			quit()
	return false


func _process(_delta: float) -> bool:
	if pending == "":
		return false
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://") + "../shots/" + pending)
	print("###FIN ", pending, " hide=", player.head_hider.hide_bone,
		" скорость=", snappedf(player.get_horizontal_speed(), 0.01), _report())
	pending = ""
	paused = false
	return false
