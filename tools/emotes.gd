extends SceneTree
## Скриншоты системы эмоций: колесо выбора и несколько танцев.
## Запуск:  godot --path . --script tools/emotes.gd

var main_node: Node
var player: Node
var wheel: Control
var stage := 0
var ticks := 0
var guard := 0
var pending := ""
var shots := ["EmoteHipHop", "EmoteThriller", "EmoteTwerk", "EmoteNorthernSoul"]
var idx := 0


func _initialize() -> void:
	main_node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_node)
	player = main_node.get_node("Player")



func _shoot(name: String) -> void:
	pending = name
	stage += 1
	ticks = 0
	guard = 0
	paused = true


func _place() -> void:
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(0.5, 0.1, 3.0)
	player.model_yaw = deg_to_rad(150.0)
	player.yaw = deg_to_rad(150.0)
	player.pitch = deg_to_rad(-8.0)


func _physics_process(_delta: float) -> bool:
	if pending != "":
		return false
	ticks += 1
	guard += 1
	if guard > 3000:
		print("###EMO застряло на этапе ", stage)
		quit()
		return false

	match stage:
		0:
			_place()
			wheel = player._get_wheel()
			stage = 1
		1:
			if ticks > 30:
				wheel.open()
				wheel.handle_motion(Vector2(120.0, -95.0))
				stage = 2
		2:
			if ticks > 90:
				_shoot("emote_0_wheel.png")
		3:
			wheel.close_and_pick()
			stage = 4
		4:
			if idx >= shots.size():
				stage = 90
				return false
			player.start_emote(shots[idx])
			stage = 5
		5:
			# даём танцу разойтись, снимаем в середине клипа
			if ticks > 120:
				_shoot("emote_%d_%s.png" % [idx + 1, shots[idx].replace("Emote", "").to_lower()])
				stage = 6
		6:
			idx += 1
			stage = 4
		90:
			print("###EMO done")
			quit()
	return false


func _process(_delta: float) -> bool:
	if pending == "":
		return false
	root.get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://") + "../shots/" + pending)
	print("###EMO ", pending, " эмоция=", player.current_emote,
		" скорость=", snappedf(player.get_horizontal_speed(), 0.01))
	pending = ""
	paused = false
	return false
