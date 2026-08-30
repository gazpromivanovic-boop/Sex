extends SceneTree
## Прогон проекта без окна: собираем сцены, жмём кнопки за игрока и смотрим,
## что персонаж действительно ходит, бежит, стрейфит, разворачивается и прыгает.
## Запуск:  godot --headless --path . --script tools/validate.gd

var frames := 0
var main_node: Node = null
var player: CharacterBody3D
var tree_node: AnimationTree
var skel: Skeleton3D
var start_pos: Vector3
var peak_y := -100.0
var rest_probe: Node = null
var jump_shot_seen := false
var emote_pos := Vector3.ZERO
var emote_y := 0.0
var stair_pos := Vector3.ZERO
var fall_frames := 0


func _dump(node: Node, indent := 0) -> void:
	print("###T ", "  ".repeat(indent), "- ", node.name, " [", node.get_class(), "]")
	for c in node.get_children():
		_dump(c, indent + 1)


func _bone_y(bone: String) -> float:
	return (skel.global_transform * skel.get_bone_global_pose(skel.find_bone(bone))).origin.y


func _p(name: String) -> Variant:
	return tree_node.get("parameters/" + name)


func _clear_input() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right", "aim", "sprint", "jump"]:
		Input.action_release(a)


func _place(pos: Vector3, yaw_deg: float) -> void:
	_clear_input()
	player.velocity = Vector3.ZERO
	player.global_position = pos
	player.model_yaw = deg_to_rad(yaw_deg)
	player.yaw = deg_to_rad(yaw_deg)


func _initialize() -> void:
	rest_probe = (load("res://assets/models/player.glb") as PackedScene).instantiate()
	root.add_child(rest_probe)

	main_node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main_node)
	player = main_node.get_node("Player")
	tree_node = player.get_node("AnimationTree")
	skel = player.find_children("*", "Skeleton3D", true, false)[0]
	print("###1 main.tscn ok, level children=", main_node.get_node("Level").get_child_count())
	_dump(player)


func _process(_delta: float) -> bool:
	frames += 1

	if frames == 2:
		start_pos = player.global_position

	if frames == 5 and rest_probe != null:
		var sk2: Skeleton3D = rest_probe.find_children("*", "Skeleton3D", true, false)[0]
		var lo := 999.0
		var hi := -999.0
		for i in sk2.get_bone_count():
			var y: float = (sk2.global_transform * sk2.get_bone_global_pose(i)).origin.y
			lo = minf(lo, y)
			hi = maxf(hi, y)
		print("###1 REST поза покоя, y: ", snappedf(lo, 0.001), " .. ", snappedf(hi, 0.001))
		for bn in ["Hips", "Head", "LeftFoot"]:
			print("###1 REST ", bn, " -> ", (sk2.global_transform
				* sk2.get_bone_global_pose(sk2.find_bone(bn))).origin.snappedf(0.001))
		rest_probe.queue_free()
		rest_probe = null

	if frames == 20:
		var ap: AnimationPlayer = player.anim_player
		print("###2 анимации: ", ap.get_animation_list())
		var loops := {}
		for n in ap.get_animation_list():
			loops[n] = ap.get_animation(n).loop_mode
		print("###2 зацикливание: ", loops)
		print("###2 стойка: on_floor=", player.is_on_floor(),
			" pos=", player.global_position.snappedf(0.01),
			" head_y=", snappedf(_bone_y("Head"), 0.01),
			" foot_y=", snappedf(_bone_y("LeftFoot"), 0.01))
		print("###2 материал=", skel.get_node("Body").get_surface_override_material(0))
		print("###2 время полёта=", snappedf(player.air_time(), 0.001), " с; темп Jump=",
			snappedf(_p("JumpSpeed/scale"), 0.001), " RunJump=",
			snappedf(_p("RunJumpSpeed/scale"), 0.001),
			" (клипы начинаются с отрыва, касание должно совпасть с полётом)")
		# таз не должен уезжать в сторону от капсулы ни в одной анимации
		var arm_scale: float = skel.get_parent().scale.x
		for n in ap.get_animation_list():
			var anim := ap.get_animation(n)
			for ti in anim.get_track_count():
				if anim.track_get_type(ti) != Animation.TYPE_POSITION_3D:
					continue
				if not str(anim.track_get_path(ti)).ends_with(":Hips"):
					continue
				var mx := 0.0
				var mz := 0.0
				for ki in anim.track_get_key_count(ti):
					var v: Vector3 = anim.track_get_key_value(ti, ki)
					mx = maxf(mx, absf(v.x) * arm_scale)
					mz = maxf(mz, absf(v.z) * arm_scale)
				print("###2 таз %-12s смещение по горизонтали: x=%.3f м z=%.3f м" % [n, mx, mz])
		Input.action_press("move_forward")

	if frames == 120:
		print("###3 ходьба: сместился=", (player.global_position - start_pos).snappedf(0.01),
			" speed=", snappedf(player.get_horizontal_speed(), 0.01),
			" blend=", (_p("Locomotion/blend_position") as Vector2).snappedf(0.01),
			" tempo=", snappedf(_p("Speed/scale"), 0.001),
			" foot_y=", snappedf(_bone_y("LeftFoot"), 0.01))
		Input.action_release("move_forward")
		Input.action_press("move_right")

	if frames == 190:
		print("###4 свободный режим, вправо: blend=",
			(_p("Locomotion/blend_position") as Vector2).snappedf(0.01),
			" корпус=", snappedf(rad_to_deg(player.model_yaw), 0.1), "°")
		Input.action_release("move_right")
		Input.action_press("aim")
		Input.action_press("move_right")

	if frames == 260:
		print("###5 прицел, стрейф: blend=",
			(_p("Locomotion/blend_position") as Vector2).snappedf(0.01),
			" корпус=", snappedf(rad_to_deg(player.model_yaw), 0.1), "°")
		_place(Vector3(-2.0, 0.2, 15.0), 0.0)
		Input.action_press("move_forward")
		Input.action_press("sprint")

	if frames == 400:
		print("###6 спринт: speed=", snappedf(player.get_horizontal_speed(), 0.01),
			" run_blend=", snappedf(_p("RunBlend/blend_amount"), 0.001),
			" tempo=", snappedf(_p("Speed/scale"), 0.001),
			" blend=", (_p("Locomotion/blend_position") as Vector2).snappedf(0.01))
		Input.action_press("jump")

	if frames == 425:
		Input.action_release("jump")        # держим до верхней точки: высота полная

	if frames == 404:
		print("###6 прыжок с разбега: RunJump=", _p("RunJumpShot/active"),
			" Jump=", _p("JumpShot/active"), " vel_y=", snappedf(player.velocity.y, 0.01))

	if frames == 440:
		print("###6 после приземления: on_floor=", player.is_on_floor(),
			" RunJump=", _p("RunJumpShot/active"))
		_place(Vector3(0.0, 0.2, 6.0), 0.0)
		Input.action_press("aim")
		player.yaw = deg_to_rad(140.0)

	if frames == 500:
		print("###7 разворот на месте: TurnLeft=", _p("TurnLeftShot/active"),
			" TurnRight=", _p("TurnRightShot/active"),
			" turning=", player.turning_in_place,
			" корпус=", snappedf(rad_to_deg(player.model_yaw), 0.1), "°")

	if frames == 560:
		print("###7 доворот закончен: корпус=", snappedf(rad_to_deg(player.model_yaw), 0.1),
			"° turning=", player.turning_in_place)
		_place(Vector3(0.0, 0.2, 6.0), 0.0)
		Input.action_press("jump")

	if frames == 563:
		print("###8 прыжок с места запущен: Jump=", _p("JumpShot/active"),
			" RunJump=", _p("RunJumpShot/active"))

	if frames == 590:
		Input.action_release("jump")        # отпускаем после верхней точки — не обрезаем

	if frames > 560 and frames < 640:
		peak_y = maxf(peak_y, player.global_position.y)
		if _p("JumpShot/active"):
			jump_shot_seen = true

	if frames == 640:
		print("###8 анимация прыжка с места отработала: ", jump_shot_seen)
		print("###8 высота прыжка=", snappedf(peak_y, 0.01),
			" сейчас y=", snappedf(player.global_position.y, 0.01),
			" on_floor=", player.is_on_floor())
		player.first_person = true
		player._apply_view()
		_place(Vector3(0.0, 0.2, 6.0), 0.0)   # дадим приземлиться перед замером

	if frames == 665:
		var cam1: Camera3D = player.get_node("CameraPivot/CameraPitch/FirstPersonCamera")
		var body: MeshInstance3D = skel.get_node("Body")
		var hh = player.head_hider
		print("###9 модификатор головы: ", hh, " active=", (hh.active if hh != null else "нет"),
			" вызовов=", (hh.calls if hh != null else -1),
			" hide=", (hh.hide_bone if hh != null else "-"))
		# счётчик вызовов показывает, что модификатор реально крутится каждый кадр;
		# сам результат виден только на рендере (tools/fpv.gd, кадры fin_A / fin_B)
		var hb := skel.find_bone("Head")
		var head_pos: Vector3 = (skel.global_transform * skel.get_bone_global_pose(hb)).origin
		print("###9 первое лицо: current=", cam1.current, " top_level=", cam1.top_level,
			" глаза y=", snappedf(cam1.global_position.y - player.global_position.y, 0.01),
			" тело видно=", body.visible, " тень=", body.cast_shadow)
		print("###9 камера относительно кости головы: ",
			(cam1.global_position - head_pos).snappedf(0.001),
			" расстояние=", snappedf(cam1.global_position.distance_to(head_pos), 0.001), " м")
		# взгляд вниз: камера должна выехать вперёд за грудь, иначе в кадре изнанка корпуса
		var f_level: float = player._eye_forward()
		player.pitch = deg_to_rad(player.pitch_min_deg)
		var f_down: float = player._eye_forward()
		player.pitch = 0.0
		print("###9 вынос камеры вперёд: прямо=", snappedf(f_level, 0.001),
			" вниз=", snappedf(f_down, 0.001), " м, в капсулу (0.32) влезает=",
			f_down < 0.32)
		print("###9 HUD: ", main_node.get_node("HUD/Status").text.replace("\n", " | "))

	# ─────────────────────────────── эмоции
	if frames == 700:
		player.first_person = true          # проверим, что эмоция вышибет FPS-вид
		player._apply_view()
		_place(Vector3(0.0, 0.2, 6.0), 0.0)
		var ap2: AnimationPlayer = player.anim_player
		var emo := []
		for e in player.available_emotes:
			emo.append("%s(loop=%s)" % [e["id"], ap2.get_animation(str(e["id"])).loop_mode])
		print("###11 эмоций доступно: ", player.available_emotes.size(), " -> ", emo)
		print("###11 узел подмены клипа: ", player.emote_node, " колесо: ", player._get_wheel())

	if frames == 720:
		player.start_emote("EmoteHipHop")
		emote_pos = player.global_position
		Input.action_press("move_forward")
		Input.action_press("move_right")

	if frames == 780:
		print("###12 первое лицо выключилось эмоцией: ", not player.first_person)
		print("###12 в эмоции: emoting=", player.emoting,
			" клип=", player.current_emote,
			" EmoteShot=", _p("EmoteShot/active"),
			" скорость=", snappedf(player.get_horizontal_speed(), 0.01),
			" сдвинулся на=", snappedf(player.global_position.distance_to(emote_pos), 0.001), " м")
		emote_y = player.global_position.y
		Input.action_press("jump")

	if frames == 800:
		Input.action_release("jump")

	if frames == 830:
		print("###12 прыжок в эмоции заблокирован: dy=",
			snappedf(player.global_position.y - emote_y, 0.001),
			" on_floor=", player.is_on_floor(), " эмоция жива=", player.emoting)
		player.start_emote("EmoteThriller")

	if frames == 860:
		print("###13 смена эмоции на лету: клип=", player.current_emote,
			" EmoteShot=", _p("EmoteShot/active"))
		Input.action_press("sprint")

	if frames == 864:
		Input.action_release("sprint")

	if frames == 890:
		print("###13 Shift прекратил эмоцию: emoting=", player.emoting,
			" клип=", player.current_emote,
			" вид вернулся в первое лицо=", player.first_person)
		player.first_person = false
		player._apply_view()
		_place(Vector3(0.0, 0.2, 6.0), 0.0)
		emote_pos = player.global_position
		Input.action_press("move_forward")

	if frames == 960:
		print("###14 движение вернулось: скорость=",
			snappedf(player.get_horizontal_speed(), 0.01),
			" сдвинулся на=", snappedf(player.global_position.distance_to(emote_pos), 0.01), " м")
		_clear_input()

	if frames == 980:
		var w = player._get_wheel()
		w.open()
		w.handle_motion(Vector2(0.0, -160.0))

	if frames == 990:
		var w = player._get_wheel()
		print("###15 колесо: открыто=", w.opened, " подсвечен сектор=", w.hovered)
		var picked: String = w.close_and_pick()
		print("###15 выбор «вверх» дал: ", picked, " (ожидали ",
			player.available_emotes[0]["id"], ")")

	# ─────────────────────────────── лестница: шагом, бегом и в прыжке
	# Лестница из пяти ступеней по 0.34 м стоит на x=-8, z от 2.35 до -1.15,
	# наверху площадка с полом на y=1.7.
	if frames == 1000:
		_place(Vector3(-8.0, 0.2, 3.0), 0.0)
		stair_pos = player.global_position
		Input.action_press("move_forward")

	if frames == 1210:
		print("###16 лестница шагом: y=", snappedf(player.global_position.y, 0.01),
			" (ждём 1.7) z=", snappedf(player.global_position.z, 0.01),
			" on_floor=", player.is_on_floor(),
			" поднялся на=", snappedf(player.global_position.y - stair_pos.y, 0.01), " м")
		_place(Vector3(-8.0, 0.2, 6.0), 0.0)
		Input.action_press("move_forward")
		Input.action_press("sprint")

	if frames == 1330:
		print("###17 лестница бегом: y=", snappedf(player.global_position.y, 0.01),
			" (ждём 1.7) скорость=", snappedf(player.get_horizontal_speed(), 0.01),
			" (бег не должен сбиваться в ноль на ступенях)")
		_place(Vector3(-8.0, 0.2, 5.0), 0.0)
		Input.action_press("move_forward")
		Input.action_press("sprint")

	if frames == 1360:
		Input.action_press("jump")          # прыгаем на лестницу с разбега

	if frames == 1364:
		Input.action_release("jump")

	if frames == 1460:
		print("###18 лестница в прыжке: y=", snappedf(player.global_position.y, 0.01),
			" (ждём 1.7) on_floor=", player.is_on_floor())
		_clear_input()

	if frames == 1480:
		# спуск: с лестницы вниз персонаж должен идти по полу, а не сыпаться
		_place(Vector3(-8.0, 1.75, -2.0), 180.0)
		stair_pos = player.global_position
		fall_frames = 0
		Input.action_press("move_forward")

	if frames > 1490 and frames < 1650 and not player.is_on_floor():
		fall_frames += 1

	if frames == 1650:
		print("###19 лестница вниз: y=", snappedf(player.global_position.y, 0.01),
			" кадров в воздухе=", fall_frames, " (ждём около нуля)")
		_clear_input()

	if frames >= 1680:
		print("###20 OK, ", frames, " кадров, без ошибок")
		quit()
	return false
