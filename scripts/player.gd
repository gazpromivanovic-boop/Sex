extends CharacterBody3D
## Контроллер персонажа для 3D-игры.
##
## Две камеры:
##   • от третьего лица через плечо (как в Fortnite) — SpringArm3D с боковым смещением,
##     сама отодвигается от стен;
##   • от первого лица — камера едет за костью головы, тело и ноги остаются видимыми,
##     прячется только голова (SkeletonModifier3D схлопывает её кость).
##
## Два режима движения:
##   • свободный — персонаж поворачивается туда, куда бежит;
##   • прицеливание (ПКМ) и вид от первого лица — персонаж всегда смотрит туда же,
##     куда камера, вбок работают strafe-анимации, разворот на месте проигрывается
##     анимациями TurnLeft / TurnRight.
##
## Эмоции: B — колесо выбора (как в Fortnite), 1–9 — быстрый запуск. Эмоция крутится
## по кругу, пока не нажмут Shift. Пока она играет, персонаж не ходит, не бегает и не
## прыгает — работает только камера.

# ─────────────────────────────────────────────────────────────── настройки

@export_group("Движение")
## Скорость обычной ходьбы, м/с. Совпадает со скоростью анимации Walk — ноги не скользят.
@export var walk_speed: float = 1.65
## Скорость бега (Shift), м/с. Анимация Sprint снята на 6.05 м/с.
@export var run_speed: float = 5.5
## Скорость в режиме прицеливания, м/с.
@export var aim_speed: float = 1.3
## Как быстро набирается скорость на земле.
@export var acceleration: float = 18.0
## Как быстро гасится скорость на земле, когда клавиши отпущены.
## Тормозим быстрее, чем разгоняемся, — так остановка читается чётко.
@export var ground_deceleration: float = 26.0
## Управление в воздухе: с какой силой доворачивается вектор скорости.
## Скорость при этом не гасится — инерция прыжка сохраняется.
@export var air_acceleration: float = 9.0
## Слабое сопротивление воздуха, когда в прыжке отпущены все клавиши.
@export var air_drag: float = 0.6
## Скорость доворота модели к нужному направлению.
@export var turn_speed: float = 11.0
## Высота прыжка при удержании пробела, м.
@export var jump_height: float = 1.15
## Высота прыжка при коротком нажатии, м: отпустил пробел — подъём обрезается.
## Слишком низкое значение ломает читаемость: анимация не успевает доиграть.
@export var min_jump_height: float = 0.7
## Множитель гравитации поверх значения из настроек проекта.
@export var gravity_scale: float = 2.0
## Во сколько раз тяжелее гравитация на падении. Взлёт остаётся прежним,
## поэтому прыжок ощущается резче, а не «залипает» в верхней точке.
@export var fall_gravity_scale: float = 1.4
## Предел скорости падения, м/с.
@export var terminal_velocity: float = 30.0
## Сколько времени после схода с края ещё разрешён прыжок (coyote time), сек.
@export var coyote_time: float = 0.12
## Сколько времени нажатие пробела ждёт приземления (jump buffer), сек.
## Нажал чуть раньше касания земли — прыжок всё равно случится.
@export var jump_buffer_time: float = 0.14
## Минимальная скорость, с которой разрешён прыжок, м/с. Прыжка с места нет:
## в паке под него только клип Jump с полусекундным приседанием и посадочным
## шагом, который ни во что игровое не укладывается. Прыгаем с шага и с бега.
@export var jump_min_speed: float = 0.8

@export_group("Ступеньки")
## Максимальная высота препятствия, на которое персонаж заходит сам —
## шагом, бегом и в падении. Ступеньки на уровне высотой 0.34 м.
@export var max_step_height: float = 0.45
## На сколько метров вперёд переставляется нога при заходе на ступеньку.
## У плоского дна (BodyCollider, форма CYLINDER) хватает пары сантиметров: оно
## ложится на проступь всей площадью, и контакт сразу считается полом. Круглому
## дну капсулы пришлось бы переставлять почти на треть радиуса, иначе она встаёт
## на кромку, а контакт с кромкой круче floor_max_angle — Godot считает его
## стеной и сталкивает персонажа обратно вниз.
@export var step_forward_reach: float = 0.05
## Насколько ровной должна быть площадка наверху, градусы. Отдельно от
## floor_max_angle и заметно строже: по тому порогу подходит и бок валуна, и
## персонаж лезет на камень, тут же с него соскальзывает и лезет снова — каждый
## кадр. У ступеньки лестницы наклон нулевой, ей запас не нужен.
@export var step_max_slope_deg: float = 25.0
## Предел замедления на лестнице. Само замедление считается по глубине проступи,
## это только страховка от слишком мелких ступеней.
@export var stair_speed_min: float = 0.55
## Разрешить заходить на ступеньку в воздухе на нисходящей ветке прыжка:
## так лестница берётся и с разбега с прыжком, а не только шагом.
@export var step_up_in_air: bool = true
## Как быстро камера и модель догоняют мгновенный подъём на ступеньку, 1/с.
@export var step_smooth_speed: float = 20.0
## Просадка камеры при жёстком приземлении, м.
@export var land_dip: float = 0.14
## Как быстро камера возвращается после просадки, 1/с.
@export var land_dip_recover: float = 8.0

@export_group("Камера")
@export var mouse_sensitivity: float = 0.0022
@export var pitch_min_deg: float = -80.0
@export var pitch_max_deg: float = 55.0
## Высота точки, вокруг которой вращается камера (уровень плеч).
@export var pivot_height: float = 1.45
## Боковое смещение камеры «через плечо».
@export var shoulder_offset: float = 0.55
## Дистанция камеры от персонажа.
@export var third_person_distance: float = 2.9
## Дистанция камеры при прицеливании.
@export var aim_distance: float = 1.7
@export var min_distance: float = 1.2
@export var max_distance: float = 6.0
## Запасная высота глаз, если в модели вдруг нет кости головы.
@export var eye_height: float = 1.63
@export var fov_default: float = 72.0
## Обзор в виде от первого лица. Шире, чем в третьем: с узким обзором
## собственная грудь закрывает ноги, когда смотришь вниз.
@export var fov_first_person: float = 88.0
@export var fov_aim: float = 55.0
@export var fov_sprint: float = 84.0

@export_group("Анимация")
## Скорость, с которой сняты анимации ходьбы и стрейфа (м/с) — из неё считается темп шага.
@export var anim_walk_reference: float = 1.64
## То же самое для анимации бега.
@export var anim_sprint_reference: float = 6.05
@export var anim_speed_min: float = 0.6
@export var anim_speed_max: float = 1.6
## Подгонять темп анимации прыжка под реальное время полёта. Без подгонки клип
## живёт своей жизнью: персонаж успевает приземлиться, пока анимация ещё
## готовится к отрыву.
@export var fit_jump_anim: bool = true
## Предел темпа анимации прыжка, чтобы клип не мелькал.
@export var jump_anim_max_speed: float = 3.4
## Во сколько раз ускорить анимацию прыжка, если подгонка выключена.
@export var run_jump_anim_speed: float = 1.3
## Момент клипа RunJump, когда стопы отрываются от пола, сек. Всё, что раньше, —
## подготовка к отрыву; в игре отрыв мгновенный, поэтому она срезается.
@export var run_jump_takeoff_time: float = 0.10
## Момент клипа RunJump, когда стопы снова касаются пола, сек. По нему и считается
## темп: касание в анимации должно совпасть с касанием в физике.
@export var run_jump_land_time: float = 0.60
## На сколько градусов должна разойтись камера и корпус, чтобы включился разворот на месте.
@export var turn_in_place_angle: float = 50.0

@export_group("Позы")
## Файлы поз в том же порядке, в каком их листает C. Клипы скачаны с Mixamo и
## лежат отдельными FBX: они переносятся на наш скелет при запуске, см.
## scripts/clip_importer.gd.
@export var pose_files: Array[String] = [
	"res://assets/animations/sitting_idle.fbx",
	"res://assets/animations/sitting_pose.fbx",
]
## Насколько кость утоплена в теле, м. Опорные кости — таза и кистей — лежат
## внутри меша, поэтому землёй для них считается уровень чуть ниже самой кости:
## иначе поза «стоит» на костях и висит над поверхностью.
@export var pose_ground_offset: float = 0.10
## И сколько добавить сверх этого каждой позе отдельно, м. Общей поправки не
## хватает: кость — это центр сустава, и лежащее тело опирается не костью, а
## спиной, до которой ещё половина толщины корпуса. Сидящее — куда меньше.
@export var pose_sink: Array[float] = [0.0, 0.10]
## Доворот модели в позе, градусы по осям, по значению на каждую позу.
## Обычно нужен ноль: clip_importer сам считает поправку на разницу рестовых поз.
## Это запас на случай, если клип снят настолько иначе, что расчёта не хватило —
## угол можно добить прямо в инспекторе, глядя в игру.
@export var pose_tilt: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]

@export_group("Плавание")
## Клипы плавания. Как и позы, они лежат отдельными FBX и переносятся на скелет
## при запуске — сведение в player.glb требует Blender.
@export var swim_files: Array[String] = [
	"res://assets/animations/treading_water.fbx",
	"res://assets/animations/swimming.fbx",
	"res://assets/animations/swimming_to_edge.fbx",
]
## На какой глубине персонаж отрывается от дна и плывёт. Меряется от подошв,
## поэтому 1.35 — это примерно по плечи: рост модели 1.79.
@export var swim_enter_depth: float = 1.35
## И на какой встаёт обратно на ноги. Порог ниже входного намеренно: с одним
## порогом на его границе персонаж дёргается между шагом и гребком каждый кадр.
@export var swim_exit_depth: float = 1.05
@export var swim_speed: float = 3.6
@export var swim_accel: float = 7.0
## Насколько тело утоплено, когда держится на воде. Голова должна остаться над
## поверхностью, поэтому меньше роста (модель 1.79). При 1.30 персонаж торчал из
## воды по пояс. Раньше к этому добавлялась поправка на расхождение: старый
## шейдер поднимал поверхность волной выше плоскости меша, а расчёт про волну не
## знал. С Ocean3D расхождения нет — высота берётся та же, что рисуется.
@export var float_depth: float = 1.48
## И насколько — когда висит на месте и перебирает руками. Глубже, чем на ходу:
## в этой позе тело стоит вертикально, руки разведены на уровне груди, и при
## общей глубине они оставались над водой — человек будто стоял по пояс.
@export var float_depth_idle: float = 1.75
## Жёсткость выталкивания к поверхности.
@export var buoyancy: float = 5.0
## Предел вертикальной скорости на плаву: выше него выталкивание не разгоняет.
## Без предела пружина на большой глубине выстреливает тело свечой из воды.
@export var swim_vertical: float = 1.6

@export_group("Эмоции")
## Скорость указателя в колесе эмоций.
@export var wheel_pointer_speed: float = 1.0
## Плавность остановки, когда эмоция запускается на бегу.
@export var emote_brake: float = 26.0

@export_group("Вид от первого лица")
## Прятать голову, чтобы она не загораживала камеру изнутри.
## Тело, руки и ноги при этом остаются видимыми.
@export var hide_head_in_first_person: bool = true
## Кость головы в скелете модели. К ней привязана камера первого лица.
@export var head_bone_name: String = "Head"
## Насколько поднять камеру над началом кости головы (до уровня глаз).
@export var eye_bone_up: float = 0.09
## Насколько вынести камеру вперёд от кости — на лицо.
@export var eye_bone_forward: float = 0.12
## Дополнительный вынос вперёд, когда смотришь вниз: иначе камера остаётся
## над воротом и в кадр лезет изнанка корпуса вместо собственных ног.
@export var eye_down_forward: float = 0.18
## С какого наклона вниз начинает работать этот вынос, градусы.
@export var eye_down_start_deg: float = 25.0
## Сглаживание слежения за костью, 1/с. Больше — жёстче держится за голову.
@export var eye_follow: float = 25.0

# ─────────────────────────────────────────────────────────────── узлы

@onready var model: Node3D = $Model
@onready var cam_yaw: Node3D = $CameraPivot
@onready var cam_pitch: Node3D = $CameraPivot/CameraPitch
@onready var spring_arm: SpringArm3D = $CameraPivot/CameraPitch/SpringArm3D
@onready var cam_third: Camera3D = $CameraPivot/CameraPitch/SpringArm3D/ThirdPersonCamera
@onready var cam_first: Camera3D = $CameraPivot/CameraPitch/FirstPersonCamera
@onready var anim_tree: AnimationTree = $AnimationTree

# ─────────────────────────────────────────────────────────────── состояние

var yaw: float = 0.0                  ## поворот камеры по горизонтали
var pitch: float = 0.0                ## наклон камеры
var model_yaw: float = 0.0            ## куда сейчас смотрит корпус
var shoulder_side: float = 1.0        ## 1 = правое плечо, -1 = левое
var current_offset: float = 0.55
var target_distance: float = 3.2
var first_person: bool = false
var aiming: bool = false
var turning_in_place: bool = false
var sprinting: bool = false           ## бежим ли сейчас (для анимации и обзора)
var swimming: bool = false            ## персонаж на плаву
var swim_node: AnimationNodeAnimation ## узел дерева для клипа плавания
var _water: Node3D                    ## запасная плоскость воды, ищется по группе
var _ocean: Node                      ## автозагрузка Ocean3D, если она есть
var _swim_ready: bool = false
var move_dir: Vector3 = Vector3.ZERO  ## куда просят идти, в мировых осях
var move_amount: float = 0.0          ## насколько отклонён стик, 0..1
var was_on_floor: bool = true
var coyote_timer: float = 0.0
var jump_buffer_timer: float = 0.0    ## сколько ещё ждёт нажатый заранее прыжок
var _jump_held: bool = false          ## пробел ещё держат с момента отрыва
var _base_gravity: float = 19.6       ## гравитация с учётом gravity_scale
var _fall_speed: float = 0.0          ## с какой скоростью падали — для просадки камеры
var _step_top: Vector3 = Vector3.ZERO ## куда переставить тело при заходе на ступеньку
var _visual_y: float = 0.0            ## сглаженная высота для камеры и модели
var _visual_offset: float = 0.0
var _step_lag: Vector3 = Vector3.ZERO ## насколько картинка отстаёт после переноса вперёд
var _pose_lift: float = 0.0           ## сдвиг модели, чтобы поза легла на опору
var _pose_tilt: Vector3 = Vector3.ZERO ## текущий доворот позы, градусы
var _stair_cycle: float = 0.0         ## оценка глубины проступи по прошлым ступенькам
var _stair_shift: float = 0.0         ## сколько дистанции подарил последний перенос
var _stair_travel: float = 0.0        ## пройдено с прошлого захода на ступеньку
var _stair_factor: float = 1.0        ## текущее замедление на лестнице
var target_speed: float = 0.0         ## к какой скорости сейчас разгоняемся — для HUD
var step_count: int = 0               ## сколько раз зашли на ступеньку — для HUD
var _land_dip: float = 0.0
var anim_player: AnimationPlayer
var skeleton: Skeleton3D
var head_hider: HeadHider
var emoting: bool = false             ## сейчас играет эмоция
var posing: bool = false              ## персонаж сидит или лежит
var pose_index: int = -1              ## какая поза сейчас, -1 — стоим
var pose_node: AnimationNodeAnimation ## узел дерева, которому подменяем клип позы
var available_poses: Array = []
var _fp_before_pose: bool = false
var current_emote: String = ""
var emote_wheel: Control              ## радиальное меню, ищется по группе
var emote_node: AnimationNodeAnimation  ## узел дерева, которому подменяем клип
var available_emotes: Array = []
var _air_in_emote: float = 0.0
var _fp_before_emote: bool = false
var head_bone: int = -1
var _eye_local: Vector3 = Vector3.ZERO   ## голова относительно тела, сглаженная
var _eye_ready: bool = false

const LOOPING_ANIMS := ["Idle", "Walk", "StrafeLeft", "StrafeRight", "Sprint"]

## Порядок здесь = порядок перебора клавишей C.
const POSES := [
	{"id": "PoseSit", "title": "сидит"},
	{"id": "PoseLie", "title": "полулёжа"},
]

## Порядок здесь = порядок секторов в колесе и цифр 1–9.
const EMOTES := [
	{"id": "EmoteHipHop", "title": "Хип-хоп"},
	{"id": "EmoteSalsa", "title": "Сальса"},
	{"id": "EmoteJazz", "title": "Джаз"},
	{"id": "EmoteTwist", "title": "Твист"},
	{"id": "EmoteStep", "title": "Степ"},
	{"id": "EmoteSnake", "title": "Змейка"},
	{"id": "EmoteNorthernSoul", "title": "Сев. соул"},
	{"id": "EmoteThriller", "title": "Триллер"},
	{"id": "EmoteTwerk", "title": "Твёрк"},
]

signal emote_changed(id: String)
signal pose_changed(title: String)

# ─────────────────────────────────────────────────────────────── запуск


func _ready() -> void:
	# считаем до _setup_animation: из неё темп прыжка подгоняется под время полёта
	_base_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * gravity_scale
	_setup_animation()
	_setup_head_hider()
	_setup_poses()
	_setup_swim()
	_setup_emotes()

	model_yaw = rotation.y
	yaw = rotation.y
	rotation = Vector3.ZERO          # корпус не крутим — крутим только модель и камеру
	model.rotation.y = model_yaw
	cam_yaw.position.y = pivot_height
	target_distance = third_person_distance
	current_offset = shoulder_offset

	_visual_y = global_position.y
	# спуск с той же ступеньки, на которую умеем заходить: иначе на лестнице вниз
	# персонаж отрывается от пола и сыплется короткими падениями
	floor_snap_length = maxf(floor_snap_length, max_step_height + 0.1)

	spring_arm.add_excluded_object(get_rid())
	_apply_view()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Находит AnimationPlayer внутри импортированной модели и цепляет к нему AnimationTree.
## Пути ищутся поиском, а не хардкодом, — модель можно заменить на свою.
func _setup_animation() -> void:
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		push_warning("В модели нет AnimationPlayer — анимации выключены.")
		return
	anim_player = found[0]

	# glTF импортируется без зацикливания, включаем его вручную
	for anim_name in anim_player.get_animation_list():
		var anim := anim_player.get_animation(anim_name)
		if anim == null:
			continue
		if anim_name in LOOPING_ANIMS or anim_name.begins_with("Emote"):
			# эмоции крутятся по кругу, пока игрок сам их не прекратит
			anim.loop_mode = Animation.LOOP_LINEAR
		else:
			anim.loop_mode = Animation.LOOP_NONE

	# AnimationTree ищет дорожки анимаций относительно своего root_node,
	# поэтому его нужно направить на корень импортированной модели.
	var anim_root: Node = anim_player.get_node_or_null(anim_player.root_node)
	if anim_root != null:
		anim_tree.root_node = anim_tree.get_path_to(anim_root)
	anim_tree.anim_player = anim_tree.get_path_to(anim_player)
	anim_tree.active = true
	_fit_jump_anims()


## Сколько персонаж реально висит в воздухе: подъём под gravity_scale плюс
## падение под более тяжёлой fall_gravity_scale.
func air_time() -> float:
	var rise: float = sqrt(2.0 * jump_height / _base_gravity)
	var fall: float = sqrt(2.0 * jump_height / (_base_gravity * fall_gravity_scale))
	return rise + fall


## Подгоняет клипы прыжка под физику: приседание перед отрывом срезается, а темп
## берётся такой, чтобы касание земли в анимации совпало с касанием в игре.
func _fit_jump_anims() -> void:
	_fit_jump_clip("RunJumpAnim", "parameters/RunJumpSpeed/scale", "RunJump",
		run_jump_takeoff_time, run_jump_land_time, run_jump_anim_speed)


func _fit_jump_clip(node_name: String, scale_path: String, clip: String,
		takeoff: float, land: float, fallback: float) -> void:
	var speed := fallback
	var air := air_time()
	if fit_jump_anim and anim_player != null and anim_player.has_animation(clip) and air > 0.01:
		var node: AnimationNodeAnimation = _blend_tree_node(node_name) as AnimationNodeAnimation
		if node != null and land > takeoff and "start_offset" in node:
			# начинаем клип сразу с отрыва: физика подбрасывает тело мгновенно,
			# приседать в воздухе персонажу уже поздно
			node.start_offset = takeoff
			speed = (land - takeoff) / air
		else:
			# обрезка недоступна — подгоняем так, чтобы совпало хотя бы касание
			speed = land / air
		speed = clampf(speed, 0.4, jump_anim_max_speed)
	anim_tree.set(scale_path, speed)


func _blend_tree_node(node_name: String) -> AnimationNode:
	if anim_tree == null or not (anim_tree.tree_root is AnimationNodeBlendTree):
		return null
	var tree: AnimationNodeBlendTree = anim_tree.tree_root
	return tree.get_node(node_name) if tree.has_node(node_name) else null


## Вешает на скелет модификатор, который схлопывает голову в виде от первого лица.
## Узел создаётся кодом, чтобы в сцене не было жёстких путей внутрь импортированной модели.
func _setup_head_hider() -> void:
	var found := model.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	skeleton = found[0]
	head_bone = skeleton.find_bone(head_bone_name)
	head_hider = HeadHider.new()
	head_hider.name = "HeadHider"
	head_hider.bone_name = head_bone_name
	skeleton.add_child(head_hider)


## Готовит позы: переносит клипы из отдельных FBX на наш скелет и запоминает
## узел дерева, которому будем подменять клип. Клипы Mixamo лежат в проекте как
## есть — сведение их в player.glb требует Blender, а перенос делается кодом.
func _setup_poses() -> void:
	pose_node = _blend_tree_node("PoseAnim") as AnimationNodeAnimation
	available_poses.clear()
	if anim_player == null or skeleton == null or pose_node == null:
		return
	for i in POSES.size():
		if i >= pose_files.size():
			break
		var scene: PackedScene = load(pose_files[i]) as PackedScene
		if scene == null:
			push_warning("Не нашёлся файл позы: %s" % pose_files[i])
			continue
		if ClipImporter.add_clip(anim_player, skeleton, scene, str(POSES[i]["id"])):
			available_poses.append(POSES[i])


## Сажает или укладывает персонажа. Пока он в позе, движение выключено —
## работает только камера, как и в эмоции.
func set_pose(index: int) -> void:
	if pose_node == null or index < 0 or index >= available_poses.size():
		return
	if emoting:
		stop_emote()
	if not posing:
		_fp_before_pose = first_person
	if first_person:
		# из своей головы поза не читается, показываем со стороны
		first_person = false
		_apply_view()
	pose_index = index
	pose_node.animation = str(available_poses[index]["id"])
	posing = true
	turning_in_place = false
	_air_in_emote = 0.0
	_fire("parameters/PoseShot/request")
	pose_changed.emit(str(available_poses[index]["title"]))


## Поднимает персонажа обратно в стойку.
func stand_up() -> void:
	if not posing:
		return
	posing = false
	pose_index = -1
	if _fp_before_pose and not first_person:
		first_person = true
		_apply_view()
	_fp_before_pose = false
	_fire("parameters/PoseShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	pose_changed.emit("")


## C листает позы по кругу, Shift возвращает в стойку.
##
## В воде позы выключены: клипы сидения и лежания рассчитаны на опору под тазом,
## а поправка на грунт ищет пол лучом — на плаву пола нет, и поза уезжает.
func _handle_pose_input() -> void:
	if available_poses.is_empty() or swimming:
		return
	if posing and Input.is_action_just_pressed("sprint"):
		stand_up()
	elif Input.is_action_just_pressed("pose_cycle"):
		set_pose((pose_index + 1) % available_poses.size())


## Переносит клипы плавания и находит поверхность воды.
##
## Воду ищем двумя путями и ни один не требуем. Сначала автозагрузка Ocean3D:
## она отдаёт высоту волны в конкретной точке, и тело качается ровно на той
## воде, которую видно. Если её нет — плоскость из группы «water». Ни того ни
## другого (на полигоне воды нет вовсе) — плавание просто выключено. Жёсткая
## зависимость от аддона тут не нужна: контроллер один на все сцены.
func _setup_swim() -> void:
	_ocean = get_node_or_null("/root/Ocean")
	_water = get_tree().get_first_node_in_group("water") as Node3D
	if anim_player == null or skeleton == null:
		return
	var names := ["SwimTread", "SwimForward", "SwimToEdge"]
	var loops := [true, true, false]
	var loaded := 0
	for i in names.size():
		if i >= swim_files.size():
			break
		var scene: PackedScene = load(swim_files[i]) as PackedScene
		if scene == null:
			push_warning("Не нашёлся клип плавания: %s" % swim_files[i])
			continue
		if ClipImporter.add_clip(anim_player, skeleton, scene, names[i], loops[i]):
			loaded += 1
	_swim_ready = loaded >= 2 and (_ocean != null or _water != null)


## Высота поверхности воды над точкой. Далеко ниже всего — воды тут нет.
func water_level_at(x: float, z: float) -> float:
	if _ocean != null:
		return _ocean.get_height(x, z)
	if _water != null:
		return _water.global_position.y
	return -1000.0


## Глубина под подошвами: больше нуля — стоим в воде.
func water_depth() -> float:
	return water_level_at(global_position.x, global_position.z) - global_position.y


## Пока плывём: гравитации нет, тело выталкивается к поверхности, движение идёт
## от камеры. Прыжок и прицел выключены — грести и целиться одновременно нельзя.
func _swim_physics(delta: float) -> void:
	aiming = false
	sprinting = false
	_read_move_input()

	var target := move_dir * swim_speed * move_amount
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	horizontal = horizontal.move_toward(target, swim_accel * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# Выталкивание: тянем тело к уровню, на котором голова над водой. Пружиной, а
	# не жёсткой установкой высоты — иначе на волне персонажа дёргает.
	# Всплытие по пробелу убрано: оно спорило с выталкиванием и выбрасывало тело
	# над поверхностью, а на границе с мелководьем ещё и переключало плавание на
	# шаг и обратно каждый кадр. Держаться на воде — задача выталкивания.
	# Глубина посадки зависит от того, гребём мы или висим: те же руки, что на
	# ходу режут поверхность, на месте должны быть в воде.
	var stroke: float = anim_tree.get("parameters/SwimBlend/blend_amount")
	var sink := lerpf(float_depth_idle, float_depth, clampf(stroke, 0.0, 1.0))
	var want := water_level_at(global_position.x, global_position.z) - sink
	var lift := (want - global_position.y) * buoyancy
	velocity.y = clampf(lift, -swim_vertical * 2.5, swim_vertical * 2.5)

	move_and_slide()

	if move_amount > 0.1:
		model_yaw = rotate_toward(model_yaw, atan2(-move_dir.x, -move_dir.z),
			turn_speed * 0.6 * delta)

	# гребём тем сильнее, чем быстрее плывём
	var speed := Vector2(velocity.x, velocity.z).length()
	var blend: float = anim_tree.get("parameters/SwimBlend/blend_amount")
	anim_tree.set("parameters/SwimBlend/blend_amount",
		lerpf(blend, clampf(speed / maxf(swim_speed, 0.01), 0.0, 1.0),
			clampf(delta * 6.0, 0.0, 1.0)))
	target_speed = swim_speed


func _enter_water() -> void:
	swimming = true
	turning_in_place = false
	if emoting:
		stop_emote()
	stand_up()
	_fire("parameters/SwimShot/request")


func _leave_water() -> void:
	swimming = false
	_fire("parameters/SwimShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Готовит слой эмоций: узел дерева, которому будем подменять клип, и колесо выбора.
func _setup_emotes() -> void:
	if anim_tree != null and anim_tree.tree_root is AnimationNodeBlendTree:
		var tree: AnimationNodeBlendTree = anim_tree.tree_root
		if tree.has_node("EmoteAnim"):
			emote_node = tree.get_node("EmoteAnim")

	available_emotes.clear()
	for e in EMOTES:
		if anim_player != null and anim_player.has_animation(str(e["id"])):
			available_emotes.append(e)
		else:
			push_warning("Нет анимации эмоции: %s" % e["id"])

	_get_wheel()


## Колесо живёт в HUD, а он попадает в дерево позже игрока, поэтому ищем лениво
## и запоминаем найденное.
func _get_wheel() -> Control:
	if emote_wheel == null or not is_instance_valid(emote_wheel):
		emote_wheel = get_tree().get_first_node_in_group("emote_wheel")
		if emote_wheel != null:
			emote_wheel.emotes = available_emotes
	return emote_wheel


## Запускает эмоцию. Пока она играет, персонаж стоит на месте.
func start_emote(id: String) -> void:
	if anim_tree == null or emote_node == null:
		return
	var known := false
	for e in available_emotes:
		if e["id"] == id:
			known = true
			break
	if not known:
		return
	if posing:
		stand_up()
	current_emote = id
	emote_node.animation = id
	if not emoting:
		_fp_before_emote = first_person
	if first_person:
		# танец смотрится со стороны, изнутри головы это каша
		first_person = false
		_apply_view()
	emoting = true
	_air_in_emote = 0.0
	turning_in_place = false
	anim_tree.set("parameters/EmoteShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	emote_changed.emit(current_emote)


## Прекращает эмоцию и возвращает управление.
func stop_emote() -> void:
	if not emoting:
		return
	emoting = false
	current_emote = ""
	if _fp_before_emote and not first_person:
		first_person = true
		_apply_view()
	if anim_tree != null:
		anim_tree.set("parameters/EmoteShot/request",
			AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	emote_changed.emit("")


# ─────────────────────────────────────────────────────────────── ввод


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if emote_wheel != null and is_instance_valid(emote_wheel) and emote_wheel.opened:
			# колесо открыто — мышь водит указатель, а не камеру
			emote_wheel.handle_motion(event.relative * wheel_pointer_speed)
		else:
			yaw -= event.relative.x * mouse_sensitivity
			pitch -= event.relative.y * mouse_sensitivity
			pitch = clampf(pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))


	if event.is_action_pressed("toggle_view") and not emoting:
		# во время эмоции вид от первого лица заблокирован
		first_person = not first_person
		_apply_view()
	if event.is_action_pressed("swap_shoulder"):
		shoulder_side = -shoulder_side
	if event.is_action_pressed("zoom_in"):
		third_person_distance = clampf(third_person_distance - 0.4, min_distance, max_distance)
	if event.is_action_pressed("zoom_out"):
		third_person_distance = clampf(third_person_distance + 0.4, min_distance, max_distance)
	if event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = (
			Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
			else Input.MOUSE_MODE_CAPTURED
		)


func _apply_view() -> void:
	if first_person:
		_eye_ready = false          # чтобы камера не прилетала из старой точки
	cam_first.current = first_person
	cam_third.current = not first_person
	# тело видно всегда — от первого лица убирается только голова
	if head_hider != null:
		head_hider.hide_bone = first_person and hide_head_in_first_person
	view_changed.emit(first_person)


signal view_changed(is_first_person: bool)

# ─────────────────────────────────────────────────────────────── физика


func _physics_process(delta: float) -> void:
	_handle_emote_input()
	_handle_pose_input()
	if emoting or posing:
		_locked_physics(delta)
		return
	# Плавание перехватывает управление целиком: ходить, прыгать и целиться на
	# плаву нечем, а гравитация заменяется выталкиванием.
	if _swim_ready:
		var depth := water_depth()
		if swimming and depth < swim_exit_depth:
			_leave_water()
		elif not swimming and depth > swim_enter_depth:
			_enter_water()
		if swimming:
			_swim_physics(delta)
			was_on_floor = is_on_floor()
			_update_animation(delta)
			return

	aiming = Input.is_action_pressed("aim")
	var on_floor := is_on_floor()

	_read_move_input()
	_update_jump(delta, on_floor)
	target_speed = _desired_speed(delta)
	_accelerate(delta, on_floor)

	_fall_speed = maxf(0.0, -velocity.y)
	_move_with_steps(delta)

	if is_on_floor() and not was_on_floor:
		_on_landed()
	was_on_floor = is_on_floor()

	_update_facing(delta, aiming or first_person)
	_update_animation(delta)


## Читает WASD или стик и переводит в мировое направление относительно камеры.
func _read_move_input() -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	move_amount = clampf(input.length(), 0.0, 1.0)
	move_dir = (Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)).normalized()
	# спринт только вперёд: вбок и назад под него нет анимации
	sprinting = (Input.is_action_pressed("sprint") and not aiming
		and move_amount > 0.1 and input.y < -0.4)


## Coyote time прощает прыжок, нажатый уже после схода с края, jump buffer —
## нажатый ещё в воздухе перед касанием земли. Гравитация на падении тяжелее,
## чем на взлёте, а отпущенный на взлёте пробел обрезает подъём.
func _update_jump(delta: float, on_floor: bool) -> void:
	coyote_timer = coyote_time if on_floor else coyote_timer - delta
	jump_buffer_timer -= delta
	if Input.is_action_just_pressed("jump"):
		jump_buffer_timer = jump_buffer_time

	if not on_floor:
		var gravity := _base_gravity
		if velocity.y <= 0.0:
			gravity *= fall_gravity_scale
		elif _jump_held and not Input.is_action_pressed("jump"):
			velocity.y = minf(velocity.y, sqrt(2.0 * _base_gravity * min_jump_height))
			_jump_held = false
		velocity.y = maxf(velocity.y - gravity * delta, -terminal_velocity)

	# с места не прыгаем: под это в паке нет годной анимации
	if (jump_buffer_timer > 0.0 and coyote_timer > 0.0
			and get_horizontal_speed() > jump_min_speed):
		velocity.y = sqrt(2.0 * _base_gravity * jump_height)
		jump_buffer_timer = 0.0
		coyote_timer = 0.0
		_jump_held = true
		_fire("parameters/RunJumpShot/request")


## К какой скорости стремимся: режим, отклонение стика и поправка на лестницу.
func _desired_speed(delta: float) -> float:
	var speed := walk_speed
	if aiming:
		speed = aim_speed
	elif sprinting:
		speed = run_speed
	# на геймпаде половина отклонения стика = половина скорости
	return speed * move_amount * _stair_slowdown(delta)


func _accelerate(delta: float, on_floor: bool) -> void:
	var moving := move_amount > 0.1
	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target := move_dir * target_speed
	if on_floor:
		horizontal = horizontal.move_toward(target,
			(acceleration if moving else ground_deceleration) * delta)
	elif moving:
		# в воздухе доворачиваем вектор скорости, но не гасим его: разбег
		# перед прыжком не должен теряться от того, что зажата другая клавиша
		var steered := horizontal.move_toward(target, air_acceleration * delta)
		var keep := maxf(steered.length(), minf(horizontal.length(), target_speed))
		if steered.length() > 0.001:
			steered = steered.normalized() * keep
		horizontal = steered
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, air_drag * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z


## Перенос на ступеньку добавляет дистанцию, которую персонаж не прошёл ногами.
## Гасить её разовым торможением нельзя — между ступенями получается «тормоз-
## рывок-тормоз». Вместо этого идём по всей лестнице ровно медленнее: подарок
## составляет одну и ту же долю проступи независимо от скорости, поэтому
## коэффициент 1 − подарок/проступь одинаково верен и шагом, и бегом, и в прицеле.
## Глубина проступи не задаётся числом, а измеряется по пройденному между
## ступеньками: на одиночном пороге замедления не будет вовсе.
func _stair_slowdown(delta: float) -> float:
	_stair_travel += Vector2(velocity.x, velocity.z).length() * delta
	var wanted := 1.0
	if _stair_cycle > 0.01 and _stair_travel < _stair_cycle:
		wanted = clampf(1.0 - _stair_shift / _stair_cycle, stair_speed_min, 1.0)
	_stair_factor = lerpf(_stair_factor, wanted, clampf(delta * 10.0, 0.0, 1.0))
	return _stair_factor


## Гасит анимации прыжка и просаживает камеру тем сильнее, чем жёстче удар.
func _on_landed() -> void:
	_jump_held = false
	_fire("parameters/RunJumpShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	_land_dip = land_dip * clampf((_fall_speed - 4.0) / 10.0, 0.0, 1.0)


## Двигает тело и, если путь перегородила ступенька не выше max_step_height,
## переставляет персонажа на неё. Скорость при этом сохраняется, поэтому лестница
## одинаково берётся шагом, бегом и на нисходящей ветке прыжка.
func _move_with_steps(delta: float) -> void:
	var start := global_transform
	var wanted := Vector3(velocity.x, 0.0, velocity.z) * delta
	var floor_before := is_on_floor()
	var vel_before := velocity

	move_and_slide()

	if max_step_height <= 0.0 or wanted.length() < 0.0005:
		return
	if velocity.y > 0.01:
		return                                  # взлетаем — подсаживать не надо
	if not (floor_before or is_on_floor() or step_up_in_air):
		return
	var gained := global_position - start.origin
	if Vector2(gained.x, gained.z).length() > Vector2(wanted.x, wanted.z).length() * 0.98:
		return                                  # прошли почти всё, что хотели, — это не упор
	if not _blocked_by_wall(wanted):
		return                                  # путь перегородил не отвес, а склон

	if not _find_step_top(start, wanted):
		return
	# Перенос вперёд мгновенный: картинке он возвращается через _step_lag, чтобы
	# не было рывка, а скорости — через ровное замедление в _stair_slowdown.
	var shift := Vector3(_step_top.x - global_position.x, 0.0, _step_top.z - global_position.z)
	_stair_shift = Vector2(shift.x, shift.z).length()
	_stair_cycle = clampf(_stair_travel + _stair_shift, _stair_shift * 1.5, 3.0)
	_stair_travel = 0.0
	_step_lag = (_step_lag - shift).limit_length(step_forward_reach * 2.0)
	step_count += 1
	global_position = _step_top
	velocity.x = vel_before.x                   # скольжение вдоль стены отменяем
	velocity.z = vel_before.z
	velocity.y = 0.0
	apply_floor_snap()


## Упёрлись ли мы в отвес, стоящий поперёк движения. Смотрим сами столкновения,
## а не is_on_wall(): по флагу пологий пандус и подступь лестницы не различить
## настолько надёжно, а лишний заход на склон даёт дёрганье.
func _blocked_by_wall(motion: Vector3) -> bool:
	var dir := Vector2(motion.x, motion.z).normalized()
	for i in get_slide_collision_count():
		var normal := get_slide_collision(i).get_normal()
		if normal.angle_to(Vector3.UP) <= floor_max_angle:
			continue                            # это пол или проходимый склон
		if Vector2(normal.x, normal.z).normalized().dot(-dir) > 0.3:
			return true
	return false


## Ищет площадку на верху ступеньки: поднять — пронести вперёд — опустить.
## Результат кладёт в _step_top. Пологий склон сюда не попадает: по нему тело
## и так едет само, а вот отвесная подступь лестницы move_and_slide останавливает.
func _find_step_top(from: Transform3D, motion: Vector3) -> bool:
	var up := Vector3.UP * max_step_height
	if test_move(from, up):
		return false                            # подняться не даёт потолок
	var raised := from.translated(up)
	# Переносим ногу на фиксированное расстояние, а не на пройденный за кадр
	# отрезок: у самой ступеньки скорость уже сбита, отрезок близок к нулю, и
	# капсула встала бы на кромку, откуда её сталкивает обратно вниз.
	var reach := motion.normalized() * maxf(motion.length(), step_forward_reach)
	if test_move(raised, reach):
		return false                            # на высоте ступеньки всё та же стена

	# опускаемся на найденную площадку настоящим движением: так позиция
	# получается ровно та, в которой тело потом и стоит
	var restore := global_transform
	global_transform = raised.translated(reach)
	var hit := move_and_collide(Vector3.DOWN * (max_step_height + 0.05))
	_step_top = global_position
	global_transform = restore

	if hit == null:
		return false                            # под ногой пусто: это край, а не ступенька
	if hit.get_normal().angle_to(Vector3.UP) > deg_to_rad(step_max_slope_deg):
		return false                            # площадка покатая: встать не выйдет
	return _step_top.y - from.origin.y > 0.005


## Клавиши эмоций опрашиваются, а не ловятся событиями: так они срабатывают,
## даже если событие перехватил интерфейс.
func _handle_emote_input() -> void:
	var wheel := _get_wheel()
	if wheel != null:
		if Input.is_action_just_pressed("emote_wheel"):
			wheel.open()
		elif Input.is_action_just_released("emote_wheel"):
			var picked: String = wheel.close_and_pick()
			if picked != "":
				start_emote(picked)
	for i in available_emotes.size():
		if i < 9 and Input.is_action_just_pressed("emote_%d" % (i + 1)):
			start_emote(str(available_emotes[i]["id"]))
	if emoting and Input.is_action_just_pressed("sprint"):
		stop_emote()


## Пока играет эмоция или персонаж сидит: ходьба, бег, прыжок и прицел выключены,
## корпус не поворачивается. Гравитация работает — если пол исчез, поза снимается.
func _locked_physics(delta: float) -> void:
	aiming = false
	sprinting = false
	if not is_on_floor():
		velocity.y = maxf(velocity.y - _base_gravity * fall_gravity_scale * delta, -terminal_velocity)
	velocity.x = move_toward(velocity.x, 0.0, emote_brake * delta)
	velocity.z = move_toward(velocity.z, 0.0, emote_brake * delta)
	move_and_slide()

	if is_on_floor():
		_air_in_emote = 0.0
	else:
		_air_in_emote += delta
		if _air_in_emote > 0.35:
			stop_emote()
			stand_up()

	_update_animation(delta)


## Поворот корпуса: в свободном режиме — по направлению бега,
## в режиме прицела — вслед за камерой, с анимацией разворота на месте.
func _update_facing(delta: float, strafe_mode: bool) -> void:
	var moving := move_amount > 0.1
	var target := model_yaw

	if strafe_mode:
		target = yaw
		var diff := wrapf(target - model_yaw, -PI, PI)
		if moving:
			turning_in_place = false
		elif not turning_in_place and absf(diff) > deg_to_rad(turn_in_place_angle):
			turning_in_place = true
			_fire("parameters/TurnLeftShot/request" if diff > 0.0 else "parameters/TurnRightShot/request")
		elif turning_in_place and absf(diff) < deg_to_rad(4.0):
			turning_in_place = false
		if not moving and not turning_in_place:
			target = model_yaw          # стоим — корпус не крутится за мышкой
	elif moving:
		target = atan2(-move_dir.x, -move_dir.z)

	var rate := turn_speed
	if turning_in_place:
		rate = 6.0
	model_yaw = rotate_toward(model_yaw, target, rate * delta)
	model.rotation.y = model_yaw


func _update_animation(delta: float) -> void:
	if anim_player == null:
		return
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var local := flat.rotated(Vector3.UP, -model_yaw)
	# blend_position: x — вбок, y — вперёд (модель смотрит в -Z)
	var blend := Vector2(local.x, -local.z) / maxf(walk_speed, 0.01)
	if blend.length() > 1.0:
		blend = blend.normalized()

	var k := clampf(delta * 12.0, 0.0, 1.0)
	var current: Vector2 = anim_tree.get("parameters/Locomotion/blend_position")
	anim_tree.set("parameters/Locomotion/blend_position", current.lerp(blend, k))

	var speed := flat.length()

	# доля бега: 0 — шаг, 1 — спринт. В прицеле бега нет.
	var run_target := 0.0
	if not aiming and speed > walk_speed:
		run_target = clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.01), 0.0, 1.0)
		# бежим только вперёд — вбок и назад спринт-анимация не подходит
		run_target *= clampf(blend.y, 0.0, 1.0)
	var run_now: float = anim_tree.get("parameters/RunBlend/blend_amount")
	run_now = lerpf(run_now, run_target, k)
	anim_tree.set("parameters/RunBlend/blend_amount", run_now)

	# темп подгоняется под реальную скорость, чтобы ноги не скользили
	var reference := lerpf(anim_walk_reference, anim_sprint_reference, run_now)
	var scale := 1.0
	if speed > 0.1:
		scale = clampf(speed / maxf(reference, 0.01), anim_speed_min, anim_speed_max)
	anim_tree.set("parameters/Speed/scale", scale)


func _fire(path: String, request: int = AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE) -> void:
	if anim_tree != null and anim_tree.active:
		anim_tree.set(path, request)


# ─────────────────────────────────────────────────────────────── камера


## Камера первого лица привязана к кости головы: она едет вместе с моделью, поэтому
## корпус на ходу больше не наезжает на камеру. Поворот при этом остаётся за мышью —
## если брать и поворот кости, картинка мотается вместе с анимацией.
func _update_eye_camera(delta: float) -> void:
	if not first_person:
		return
	# Сглаживаем не мировую позицию, а смещение головы относительно тела: иначе
	# камера отстаёт от персонажа при падении и на разгоне.
	var local_head: Vector3
	if skeleton != null and head_bone >= 0:
		# сглаживание ступеньки уже сидит в model.position.y, поэтому кость
		# приходит с ним; отдельно добавлять _visual_offset не нужно
		var head := skeleton.global_transform * skeleton.get_bone_global_pose(head_bone)
		local_head = head.origin - global_position
	else:
		local_head = Vector3.UP * (eye_height - eye_bone_up + _visual_offset)
	if _eye_ready:
		local_head = _eye_local.lerp(local_head, clampf(1.0 - exp(-eye_follow * delta), 0.0, 1.0))
	_eye_local = local_head
	_eye_ready = true
	var flat_forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	cam_first.global_position = (global_position + _eye_local
		+ Vector3.UP * (eye_bone_up - _land_dip) + flat_forward * _eye_forward())
	cam_first.global_rotation = Vector3(pitch, yaw, 0.0)


## Чем ниже опущен взгляд, тем дальше камера выносится вперёд от лица: у самого
## ворота обзор вниз перекрыт грудью, и видно изнанку меша, а не свои ноги.
func _eye_forward() -> float:
	var span: float = maxf(1.0, -pitch_min_deg - eye_down_start_deg)
	var t: float = clampf((-rad_to_deg(pitch) - eye_down_start_deg) / span, 0.0, 1.0)
	return eye_bone_forward + eye_down_forward * ease(t, 0.65)


## Заход на ступеньку переставляет тело вверх за один кадр — физически верно, но
## глазу это рывок. Камера и модель догоняют новую высоту за пару кадров, поэтому
## лестница читается как подъём. Тот же сглаживатель гасит и спуск со ступеньки.
func _update_step_smoothing(delta: float) -> void:
	var y := global_position.y
	if not is_on_floor() or absf(y - _visual_y) > max_step_height + 0.3:
		_visual_y = y                       # в полёте и на большом перепаде — без сглаживания
	else:
		_visual_y = lerpf(_visual_y, y, clampf(1.0 - exp(-step_smooth_speed * delta), 0.0, 1.0))
	_visual_offset = _visual_y - y
	_step_lag = _step_lag.lerp(Vector3.ZERO, clampf(1.0 - exp(-step_smooth_speed * delta), 0.0, 1.0))
	_land_dip = lerpf(_land_dip, 0.0, clampf(1.0 - exp(-land_dip_recover * delta), 0.0, 1.0))

	# доворот ставим до замера подъёма: подъём считается по костям, а они едут
	# вместе с моделью
	var tilt := Vector3.ZERO
	if posing and pose_index >= 0 and pose_index < pose_tilt.size():
		tilt = pose_tilt[pose_index]
	_pose_tilt = _pose_tilt.lerp(tilt, clampf(delta * 8.0, 0.0, 1.0))
	model.rotation = Vector3(deg_to_rad(_pose_tilt.x),
		model_yaw + deg_to_rad(_pose_tilt.y), deg_to_rad(_pose_tilt.z))

	var lift: float = _pose_ground_shift() if posing or absf(_pose_lift) > 0.001 else 0.0
	_pose_lift = lerpf(_pose_lift, lift, clampf(delta * 10.0, 0.0, 1.0))

	# корпус не повёрнут (крутится только модель), поэтому мировой сдвиг = локальный
	model.position = Vector3(_step_lag.x, _visual_offset + _pose_lift, _step_lag.z)
	cam_yaw.position = Vector3(_step_lag.x, pivot_height + _visual_offset - _land_dip, _step_lag.z)


## Сажает позу на опору. Физическое тело остаётся цилиндром и под позу
## подстроиться не может, поэтому подгоняем саму модель: находим самую нижнюю
## кость и сдвигаем модель так, чтобы она встала на уровень пола, утопленная
## внутрь тела на pose_ground_offset. Сдвиг работает в обе стороны — поза может
## и провалиться под пол, и повиснуть над ним, и оба случая лечатся одинаково.
## Опорной становится та кость, что ниже всех: сидя это таз и кисти, лёжа — бок.
func _pose_ground_shift() -> float:
	if skeleton == null:
		return 0.0
	# текущий сдвиг вычитаем, иначе он подмешается в замер и накрутит сам себя
	var base := global_position.y + _pose_lift
	var lowest := INF
	for b in skeleton.get_bone_count():
		var bone_y: float = (skeleton.global_transform
			* skeleton.get_bone_global_pose(b)).origin.y
		lowest = minf(lowest, bone_y - base)
	if is_inf(lowest):
		return 0.0
	var extra: float = 0.0
	if pose_index >= 0 and pose_index < pose_sink.size():
		extra = pose_sink[pose_index]
	return clampf(-(pose_ground_offset + extra) - lowest, -0.6, 0.6)


func _process(delta: float) -> void:
	_update_step_smoothing(delta)
	_update_camera(delta)


func _update_camera(delta: float) -> void:
	cam_yaw.rotation.y = yaw
	cam_pitch.rotation.x = pitch
	_update_eye_camera(delta)

	# плавное смещение «через плечо» и дистанция
	var wanted_offset := shoulder_offset * shoulder_side
	if first_person:
		wanted_offset = 0.0
	current_offset = lerpf(current_offset, wanted_offset, clampf(delta * 10.0, 0.0, 1.0))
	spring_arm.position.x = current_offset

	target_distance = aim_distance if aiming else third_person_distance
	spring_arm.spring_length = lerpf(spring_arm.spring_length, target_distance, clampf(delta * 10.0, 0.0, 1.0))

	var wanted_fov := fov_first_person if first_person else fov_default
	if aiming:
		wanted_fov = fov_aim
	elif sprinting and get_horizontal_speed() > 3.0:
		wanted_fov = fov_sprint + (8.0 if first_person else 0.0)
	var cam := cam_first if first_person else cam_third
	cam.fov = lerpf(cam.fov, wanted_fov, clampf(delta * 8.0, 0.0, 1.0))


## Скорость по горизонтали — для HUD.
func get_horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()
