@tool
class_name Row
extends Node3D
## Укладывает копии сцены рядом друг за другом: доски настила, сваи, ограда.
##
## Отличается от Scatter тем, что здесь порядок, а не случайность: шаг ровный,
## направление задано. Разброс луча для настила не годится — доски должны лежать
## встык, а не там, где попал луч.
##
## Небольшой разнобой всё же есть: одинаковые доски читаются напечатанными, и
## пары сантиметров сдвига хватает, чтобы настил выглядел собранным руками.

@export var scene: PackedScene
@export var count: int = 24
## Шаг между копиями вдоль оси Z узла, метры.
@export var spacing: float = 1.0
@export var seed_value: int = 991
## Оставлять ли копиям физические тела. Валуну и бревну коллизия нужна, траве,
## гальке и доскам настила — нет: игрок цепляется за них, и экран дёргается.
@export var collision: bool = true

## Разворот каждой копии, градусы. Доска настила лежит длинной стороной поперёк
## пирса, а ряд идёт вдоль — без этого её пришлось бы разворачивать в модели.
@export var base_rotation: Vector3 = Vector3.ZERO
## Прижимать каждую копию к земле лучом. Нужно на рельефе: ровный ряд по прямой
## там висит в воздухе на буграх и тонет во впадинах.
@export var snap_to_ground: bool = false
@export var snap_from: float = 30.0
@export var snap_length: float = 80.0

@export_group("Разнобой")
## Случайный сдвиг поперёк и вдоль, метры.
@export var jitter: Vector2 = Vector2(0.015, 0.01)
## Случайный поворот вокруг вертикали, градусы.
@export var yaw_jitter: float = 0.4
## И вокруг продольной оси — доски лежат не идеально плоско.
@export var roll_jitter: float = 0.6

@export var rebuild: bool = false:
	set(value):
		rebuild = false
		if value:
			build()


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
	if scene == null:
		push_warning("Row: сцена не задана.")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Сначала считаем все места, и только потом ставим копии. Луч, пущенный
	# после add_child, попадает в коллайдер уже поставленной копии — и в
	# собственный, и в соседский, — а ряд от этого ползёт вверх.
	var spots: Array[Vector3] = []
	var turns: Array[Vector3] = []
	for i in count:
		var world := global_transform * Vector3(
			rng.randf_range(-jitter.x, jitter.x),
			rng.randf_range(-jitter.y, jitter.y),
			i * spacing)
		spots.append(_drop(world) if snap_to_ground else world)
		turns.append(Vector3(
			deg_to_rad(base_rotation.x + rng.randf_range(-roll_jitter, roll_jitter)),
			deg_to_rad(base_rotation.y + rng.randf_range(-yaw_jitter, yaw_jitter)),
			deg_to_rad(base_rotation.z)))

	for i in spots.size():
		var inst := scene.instantiate() as Node3D
		if not collision:
			Props.strip_collision(inst)
		add_child(inst)
		inst.global_position = spots[i]
		inst.rotation = turns[i]


## Опускает точку на поверхность. Не нашлось поверхности — оставляем как есть:
## ряд в воздухе заметен и чинится, ряд, провалившийся в никуда, — нет.
func _drop(point: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	if space == null:
		return point
	var origin := point + Vector3.UP * snap_from
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + Vector3.DOWN * snap_length)
	var hit := space.intersect_ray(query)
	return hit["position"] if not hit.is_empty() else point
