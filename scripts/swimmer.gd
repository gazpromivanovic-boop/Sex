class_name Swimmer
extends Node3D
## Водит модель по кольцу и включает её собственный клип плавания.
##
## Вешается прямо на корень импортированной модели. Кольцо, а не маршрут из
## точек: под водой некуда идти и не от чего уворачиваться, а замкнутая петля не
## требует ни разметки в сцене, ни логики разворота в конце пути. Наклонённая и
## сбитая по фазе, она читается свободным кружением, а не каруселью.
##
## Клип берётся тот, что пришёл с моделью: у присланных черепахи и ската цикл
## плавания уже внутри, свой делать незачем.

## Полуоси кольца в плане, метры. Разные — чтобы путь был овалом, а не циркулем.
@export var radius: Vector2 = Vector2(14.0, 9.0)
## Круг за столько секунд.
@export var period: float = 26.0
## Сдвиг по кругу, 0..1. Двум копиям с одинаковой фазой не разойтись.
@export var phase: float = 0.0
## Наклон кольца, градусы: путь идёт не строго горизонтально.
@export var tilt_deg: float = 8.0

@export_group("Покачивание")
## Насколько всплывает и опускается сверх наклона кольца, метры.
@export var bob: float = 0.8
@export var bob_period: float = 11.0
## Крен в поворотах, градусы. Без него разворот выглядит как у автобуса.
@export var bank_deg: float = 14.0

@export_group("Клип")
## Имя анимации. Пусто — берём первую подходящую из модели.
@export var clip: String = ""
## Разброс скорости клипа: одинаковые копии машут плавниками в такт и выдают
## себя копиями.
@export var speed_jitter: float = 0.15
## Модель может смотреть не туда, куда её ставит look_at. Доворот, градусы.
@export var facing_offset_deg: float = 0.0

var _origin: Vector3
var _scale: Vector3 = Vector3.ONE
var _time: float = 0.0
var _player: AnimationPlayer


func _ready() -> void:
	_origin = position
	# look_at собирает базис заново и масштаб при этом теряется, поэтому держим
	# его отдельно и возвращаем после каждого доворота.
	_scale = scale
	_player = _find_player(self)
	if _player != null:
		var clip_name := clip if clip != "" else _pick_clip(_player)
		if clip_name != "":
			var anim := _player.get_animation(clip_name)
			if anim != null:
				anim.loop_mode = Animation.LOOP_LINEAR
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(get_path())
			_player.speed_scale = 1.0 + rng.randf_range(-speed_jitter, speed_jitter)
			_player.play(clip_name)
			# Стартуем с произвольного места клипа: иначе все копии машут
			# синхронно, даже разойдясь по кругу.
			_player.seek(rng.randf() * anim.length, true)
	else:
		push_warning("Swimmer: у %s нет AnimationPlayer, плыть будет молча." % name)

	_time = phase * period
	_place()


func _process(delta: float) -> void:
	_time += delta
	_place()


func _place() -> void:
	var a := TAU * _time / maxf(period, 0.01)
	var here := _ring(a)
	# Направление берём из точки чуть впереди по кругу, а не из разницы с
	# прошлым кадром: разница на медленном ходу тонет в дрожании и модель рыскает.
	var ahead := _ring(a + 0.06)
	position = here
	var forward := ahead - here
	if forward.length() > 0.0001:
		look_at(global_position + forward, Vector3.UP)
		rotate_object_local(Vector3.UP, deg_to_rad(facing_offset_deg))
		rotate_object_local(Vector3.FORWARD, deg_to_rad(-bank_deg))
		scale = _scale


func _ring(a: float) -> Vector3:
	var flat := Vector3(cos(a) * radius.x, 0.0, sin(a) * radius.y)
	# Наклон кольца: то же кольцо, положенное набок, даёт подъём и снижение без
	# отдельной анимации по высоте.
	flat.y = sin(a) * radius.y * tan(deg_to_rad(tilt_deg))
	flat.y += sin(TAU * _time / maxf(bob_period, 0.01)) * bob
	return _origin + flat


func _find_player(node: Node) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var found := _find_player(child)
		if found != null:
			return found
	return null


## Первый клип, который похож на движение. RESET служебный, его заводить нельзя.
func _pick_clip(player: AnimationPlayer) -> String:
	var best := ""
	var longest := 0.0
	for candidate in player.get_animation_list():
		if candidate == "RESET":
			continue
		var anim := player.get_animation(candidate)
		if anim != null and anim.length > longest:
			longest = anim.length
			best = candidate
	return best
