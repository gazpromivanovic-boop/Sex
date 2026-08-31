@tool
class_name GroundSnap
extends Node3D
## Сажает узел на поверхность лучом сверху вниз.
##
## Нужно там, где предмет ставят руками, а рельеф не плоский: записать в сцене
## точную высоту нельзя — она меняется при каждой пересборке пляжа, и стул то
## висит над песком, то тонет в нём по сиденье. Луч же всегда попадает в то,
## что реально есть в сцене.
##
## Скрипт вешается прямо на корень уже размещённой модели, поэтому свои
## коллайдеры из запроса приходится исключать: иначе луч упирается в собственную
## спинку и предмет подпрыгивает на свою же высоту.

## Насколько утопить в грунт после посадки. Ножки стула на песке проваливаются.
@export var sink: float = 0.02
@export var ray_from: float = 30.0
@export var ray_length: float = 80.0
## Довернуть по наклону поверхности. На песке заметно, на настиле не нужно.
@export var align_to_normal: bool = false
## Насколько сильно доворачивать, 0..1. Полное выравнивание кладёт предмет на
## склон плашмя, а мебель всё-таки стоит скорее вертикально.
@export var align_amount: float = 0.5


func _ready() -> void:
	# В редакторе не работаем, в отличие от Scatter и Row. Те добавляют детей без
	# owner, и в файл сцены дети не попадают. А тут двигается сам узел, который
	# сцене принадлежит: правка пометила бы сцену изменённой, сохранилась бы, и
	# при следующем открытии предмет поехал бы от уже сдвинутой высоты.
	if Engine.is_editor_hint():
		return
	# Ждём кадр физики: на первом кадре тела ещё не в дереве запросов, и луч
	# уходит в пустоту — предмет остаётся висеть на заданной вручную высоте.
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	if space == null:
		return

	var origin := global_position + Vector3.UP * ray_from
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + Vector3.DOWN * ray_length)
	query.exclude = _own_bodies()
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		push_warning("GroundSnap: под %s нет поверхности." % name)
		return

	global_position = (hit["position"] as Vector3) - Vector3.UP * sink
	if align_to_normal:
		var normal: Vector3 = hit["normal"]
		var tilt := Quaternion(Vector3.UP, normal.normalized())
		quaternion = Quaternion.IDENTITY.slerp(tilt, clampf(align_amount, 0.0, 1.0)) * quaternion


func _own_bodies() -> Array[RID]:
	var rids: Array[RID] = []
	var stack: Array[Node] = [self]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is CollisionObject3D:
			rids.append((node as CollisionObject3D).get_rid())
		stack.append_array(node.get_children())
	return rids
