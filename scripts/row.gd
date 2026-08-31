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
## Разворот каждой копии, градусы. Доска настила лежит длинной стороной поперёк
## пирса, а ряд идёт вдоль — без этого её пришлось бы разворачивать в модели.
@export var base_rotation: Vector3 = Vector3.ZERO

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


func _ready() -> void:
	if not Engine.is_editor_hint():
		build()


func build() -> void:
	for child in get_children():
		child.queue_free()
	if scene == null:
		push_warning("Row: сцена не задана.")
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in count:
		var inst := scene.instantiate() as Node3D
		add_child(inst)
		inst.position = Vector3(
			rng.randf_range(-jitter.x, jitter.x),
			rng.randf_range(-jitter.y, jitter.y),
			i * spacing)
		inst.rotation = Vector3(
			deg_to_rad(base_rotation.x + rng.randf_range(-roll_jitter, roll_jitter)),
			deg_to_rad(base_rotation.y + rng.randf_range(-yaw_jitter, yaw_jitter)),
			deg_to_rad(base_rotation.z))
