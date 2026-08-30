extends SceneTree
## Делает скриншоты игры без участия человека (для проверки сборки).
##
## Переходы между кадрами привязаны не ко времени, а к состоянию персонажа
## (набрал скорость / пробежал столько-то метров / завис в прыжке): программный
## рендер идёт медленнее реального времени, и любой таймер по кадрам врёт.
## В момент съёмки дерево ставится на паузу, иначе за время отрисовки кадра
## физика успевает утащить персонажа на десятки метров.
##
## Запуск:  godot --path . --script tools/shoot.gd

var main_node: Node
var player: Node
var stage := 0
var ticks := 0
var guard := 0
var mark := Vector3.ZERO
var pending := ""
var jumped := false

const ACTIONS := ["move_forward", "move_back", "move_left", "move_right",
	"aim", "sprint", "jump"]


func _initialize() -> void:
	main_node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_node)
	player = main_node.get_node("Player")


func _hold(list: Array) -> void:
	for a in ACTIONS:
		if a in list:
			Input.action_press(a)
		else:
			Input.action_release(a)


func _place(pos: Vector3, yaw_deg: float, pitch_deg: float) -> void:
	_hold([])
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.model_yaw = deg_to_rad(yaw_deg)
	player.yaw = deg_to_rad(yaw_deg)
	player.pitch = deg_to_rad(pitch_deg)
	mark = pos
	ticks = 0


func _view(first: bool, shoulder: float) -> void:
	player.shoulder_side = shoulder
	if player.first_person != first:
		player.first_person = first
		player._apply_view()


func _travelled() -> float:
	return Vector2(player.global_position.x - mark.x, player.global_position.z - mark.z).length()


func _next(name: String) -> void:
	pending = name
	stage += 1
	ticks = 0
	guard = 0
	paused = true          # замораживаем мир, пока кадр не отрисуется


func _physics_process(_delta: float) -> bool:
	if pending != "":
		return false                       # ждём, пока кадр действительно отрисуется
	ticks += 1
	guard += 1
	if guard > 4000:
		print("###SHOT прервано на этапе ", stage)
		quit()
		return false

	match stage:
		0:
			_place(Vector3(1.0, 0.1, 2.0), 170.0, -6.0)
			_view(false, 1.0)
			stage = 1
		1:
			if ticks > 25:
				_next("01_third_person_idle.png")
		2:
			_place(Vector3(-16.0, 0.2, 17.0), -60.0, -7.0)
			_hold(["move_forward", "sprint"])
			stage = 3
		3:
			if player.get_horizontal_speed() > 5.2 and _travelled() > 2.5:
				_next("02_sprint.png")
		4:
			_place(Vector3(1.0, 0.1, 8.0), 182.0, -4.0)
			_hold(["aim"])
			stage = 5
		5:
			if ticks > 35:
				_next("03_aim_over_shoulder.png")
		6:
			_place(Vector3(12.75, 0.1, 9.0), 0.0, -2.0)
			_view(true, 1.0)
			stage = 7
		7:
			if ticks > 25:
				_next("04_first_person.png")
		8:
			_place(Vector3(-14.0, 0.2, 1.5), 180.0, -11.0)
			_view(false, -1.0)
			_hold(["move_forward", "sprint"])
			jumped = false
			stage = 9
		9:
			if not jumped and _travelled() > 3.5:
				jumped = true
				_hold(["move_forward", "sprint", "jump"])
			elif jumped and not player.is_on_floor() and player.velocity.y < 1.5:
				_hold(["move_forward", "sprint"])
				_next("05_running_jump.png")
		10:
			print("###SHOT done")
			quit()
	return false


func _process(_delta: float) -> bool:
	if pending == "":
		return false
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://") + "../shots/" + pending)
	print("###SHOT ", pending, " pos=", player.global_position.snappedf(0.01),
		" speed=", snappedf(player.get_horizontal_speed(), 0.01),
		" y=", snappedf(player.global_position.y, 0.01))
	pending = ""
	paused = false      # этап уже переключён в _next(), здесь только снимаем
	return false
