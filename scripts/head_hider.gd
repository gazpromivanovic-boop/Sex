extends SkeletonModifier3D
class_name HeadHider
## Прячет голову, схлопывая её кость в точку.
##
## Нужно для вида от первого лица: камера стоит на уровне глаз, тело и ноги
## остаются видимыми, а голова не загораживает обзор изнутри. Работает как
## SkeletonModifier3D — то есть уже после того, как AnimationTree разложил позу,
## иначе анимация каждый кадр возвращала бы кость на место.

## Имя кости, которую схлопываем.
@export var bone_name: String = "Head"
## Включено ли скрытие прямо сейчас.
@export var hide_bone: bool = false:
	set(value):
		hide_bone = value
		_cached_bone = -2          # пересчитать индекс при следующем кадре
## Во сколько раз ужать кость. Ноль ставить не стоит — вырожденная матрица.
@export var shrink: float = 0.002

var _cached_bone: int = -2
## Счётчик срабатываний — нужен автопроверке в tools/validate.gd.
var calls: int = 0


func _process_modification_with_delta(_delta: float) -> void:
	_apply()


func _process_modification() -> void:
	_apply()


func _apply() -> void:
	calls += 1
	if not hide_bone:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if _cached_bone == -2:
		_cached_bone = skeleton.find_bone(bone_name)
	if _cached_bone < 0:
		return
	skeleton.set_bone_pose_scale(_cached_bone, Vector3(shrink, shrink, shrink))
