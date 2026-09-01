@tool
class_name Scatter
extends Node3D
## Разбрасывает готовые сцены по поверхности: камни по пляжу, коряги, что угодно.
##
## Место каждой копии находится лучом сверху вниз, а не расчётом по формуле
## рельефа. Формула живёт в сборочном скрипте Blender, до неё из игры не
## дотянуться, и любая правка рельефа рассинхронизировала бы расстановку. Луч же
## всегда попадает в то, что реально есть в сцене.
##
## Раскладка детерминированная: один и тот же seed даёт одну и ту же картину.
## Случайная при каждом запуске сцена мешает — нельзя ни поправить, ни повторить.

## Что разбрасываем. Берётся по кругу со случайным выбором.
@export var scenes: Array[PackedScene] = []
@export var count: int = 40
@export var seed_value: int = 12345
## Оставлять ли копиям физические тела. Валуну и бревну коллизия нужна, траве,
## гальке и доскам настила — нет: игрок цепляется за них, и экран дёргается.
@export var collision: bool = true


@export_group("Где")
## Прямоугольник в плоскости XZ, в котором ищем места, метры.
@export var area: Vector2 = Vector2(90.0, 70.0)
@export var area_center: Vector3 = Vector3.ZERO
## Сверху какой высоты пускать луч и на сколько вниз.
@export var ray_from: float = 60.0
@export var ray_length: float = 140.0
## Не ставить ниже этой высоты — там вода.
@export var min_height: float = -0.2
## И не выше этой. Луч попадает и в настил пирса тоже, а камни на досках не нужны.
@export var max_height: float = 1000.0
## И не ставить круче этого наклона: на отвесной стене камень не лежит.
@export var max_slope_deg: float = 38.0
## Круг вокруг центра, внутри которого не ставим: там пирс и постройки.
@export var keep_clear: float = 0.0

@export_group("Вид")
@export var scale_range: Vector2 = Vector2(0.7, 1.5)
## Насколько утапливать в грунт: камень, лежащий ровно на поверхности, выглядит
## приклеенным.
@export var sink: float = 0.18
@export var tilt_deg: float = 12.0

@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if value:
			build()

var placed: int = 0


## Строим и в редакторе тоже: без этого в 3D-виде на месте разбросанного пусто,
## и уровень невозможно собирать глазами. Дети добавляются без owner, поэтому в
## файл сцены они не попадают и не раздувают его тысячей узлов.
func _ready() -> void:
	# Луч можно пускать только когда физический мир уже собран: на первом кадре
	# тела ещё не попали в дерево запросов, и intersect_ray отдаёт пусто —
	# расстановка молча даёт ноль объектов. Ждём кадр физики.
	await get_tree().physics_frame
	build()



func build() -> void:
	for child in get_children():
		child.queue_free()
	placed = 0
	if scenes.is_empty():
		push_warning("Scatter: не заданы сцены.")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	var tries := 0
	while placed < count and tries < count * 30:
		tries += 1
		var x := area_center.x + rng.randf_range(-area.x * 0.5, area.x * 0.5)
		var z := area_center.z + rng.randf_range(-area.y * 0.5, area.y * 0.5)
		if keep_clear > 0.0 and Vector2(x - area_center.x, z - area_center.z).length() < keep_clear:
			continue

		var from := Vector3(x, area_center.y + ray_from, z)
		var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * ray_length)
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		var point: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		if point.y < min_height or point.y > max_height:
			continue
		if rad_to_deg(normal.angle_to(Vector3.UP)) > max_slope_deg:
			continue

		var inst := scenes[rng.randi() % scenes.size()].instantiate() as Node3D
		if not collision:
			Props.strip_collision(inst)
		add_child(inst)
		inst.global_position = point - Vector3.UP * sink
		var s := rng.randf_range(scale_range.x, scale_range.y)
		inst.scale = Vector3(s, s, s)
		inst.rotation = Vector3(
			deg_to_rad(rng.randf_range(-tilt_deg, tilt_deg)),
			rng.randf_range(0.0, TAU),
			deg_to_rad(rng.randf_range(-tilt_deg, tilt_deg)))
		placed += 1
