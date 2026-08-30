@tool
class_name BodyCollider
extends CollisionShape3D
## Единая сборка формы столкновений по габаритам модели.
##
## Вешается на CollisionShape3D любого тела — персонажа, ящика, платформы — и
## строит форму по тому, что реально видно: обмеряет меши и (если модель со
## скелетом) кости в позе покоя, а потом кладёт низ формы ровно в начало
## координат тела. Габариты больше не приходится вбивать руками и держать
## в голове при замене модели.
##
## Форма по умолчанию — цилиндр, и это принципиально. У капсулы круглое дно:
## рядом с краем площадки она опирается на кромку, ось уезжает за край на
## величину до радиуса, тело приподнимается — и персонаж стоит в воздухе, не
## касаясь ногами пола. Плоское дно ложится на поверхность целиком, поэтому
## высота стояния всегда одна и та же, а с площадки персонаж сходит тогда,
## когда с неё сходит его след.
##
## Пример на ящике:
##     Crate (StaticBody3D)
##      ├─ Mesh (MeshInstance3D)
##      └─ Shape (CollisionShape3D + этот скрипт, kind = BOX)
## Форма соберётся по мешу сама.

enum Kind {
	CYLINDER,  ## плоское дно, скруглённый бок — для всего, что ходит
	CAPSULE,   ## круглое дно: легче скользит по неровностям, но всплывает на кромках
	BOX,       ## коробка по габаритам — для ящиков, платформ, стен
}

## Что обмерять. Пусто — берём тело целиком, то есть родителя этой формы.
@export_node_path("Node3D") var visual_root: NodePath

@export_group("Форма")
@export var kind: Kind = Kind.CYLINDER
## Радиус в метрах. 0 — считать по габаритам. У персонажа задаётся руками:
## по габаритам вышел бы размах рук, а нужен след, который тело оставляет на полу.
@export var radius: float = 0.0
## Высота в метрах. 0 — считать по габаритам.
@export var height: float = 0.0

@export_group("Посадка")
## Опустить модель так, чтобы её низ лёг в начало координат тела. После этого
## global_position тела — это точка, которой оно стоит на земле.
@export var align_bottom_to_origin: bool = true
## Учитывать кости скелета, а не только меши. У модели со скинингом габариты
## меша считаются по позе привязки и могут не совпадать с тем, что видно.
@export var measure_bones: bool = true
## Предохранитель: посадка не сдвинет модель дальше, чем на столько метров.
## Габариты меша со скинингом движок иногда отдаёт в системе координат привязки,
## и без предела такая ошибка утащила бы модель за пределы уровня.
@export var max_align_shift: float = 0.35
## Поставить галочку в инспекторе, чтобы пересобрать форму прямо в редакторе.
@export var refit: bool = false:
	set(value):
		refit = false
		if value:
			fit()

## Габариты, по которым собрана форма, в системе координат тела. Для отладки.
var measured := AABB()


func _ready() -> void:
	if not Engine.is_editor_hint():
		fit()


## Обмеряет модель и пересобирает форму. Можно звать в любой момент — например,
## после того как телу подменили модель.
func fit() -> void:
	var body := get_parent() as Node3D
	if body == null:
		push_warning("BodyCollider: форма должна лежать внутри тела (Node3D).")
		return
	var root := body
	if not visual_root.is_empty():
		var found := get_node_or_null(visual_root) as Node3D
		if found != null:
			root = found

	var bounds := _measure(root, body)
	if bounds.size.y <= 0.0:
		push_warning("BodyCollider: под %s нечего обмерять — форма оставлена как есть."
			% root.name)
		return

	if align_bottom_to_origin and root != body:
		# сдвигаем саму модель, а не форму: так начало координат тела совпадает
		# с точкой опоры, и вся математика вокруг (камера, ступеньки) считает
		# высоту от земли, а не от произвольной точки внутри модели
		if absf(bounds.position.y) > max_align_shift:
			push_warning("BodyCollider: низ %s оказался на %.2f м от начала координат — "
				% [root.name, bounds.position.y]
				+ "это больше max_align_shift, посадка пропущена.")
		else:
			root.position.y -= bounds.position.y
			bounds.position.y = 0.0
	measured = bounds
	_build(bounds)


## Собирает габариты всего видимого под root в системе координат тела.
func _measure(root: Node3D, body: Node3D) -> AABB:
	var to_body := body.global_transform.affine_inverse()
	var bounds := AABB()
	var started := false

	for node in _descendants(root):
		var points: Array[Vector3] = []
		if node is VisualInstance3D:
			var local: AABB = (node as VisualInstance3D).get_aabb()
			var xf := to_body * node.global_transform
			for i in 8:
				points.append(xf * local.get_endpoint(i))
		elif measure_bones and node is Skeleton3D:
			# поза покоя, а не текущая: результат не должен зависеть от того,
			# какой кадр анимации успел проиграться до сборки
			var skel := node as Skeleton3D
			var xf := to_body * skel.global_transform
			for b in skel.get_bone_count():
				points.append(xf * skel.get_bone_global_rest(b).origin)
		for p in points:
			if started:
				bounds = bounds.expand(p)
			else:
				bounds = AABB(p, Vector3.ZERO)
				started = true
	return bounds


func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = [root]
	for child in root.get_children():
		out.append_array(_descendants(child))
	return out


func _build(bounds: AABB) -> void:
	var centre := bounds.get_center()
	var bottom := bounds.position.y
	var r: float = radius if radius > 0.0 else maxf(bounds.size.x, bounds.size.z) * 0.5
	var h: float = height if height > 0.0 else bounds.size.y

	match kind:
		Kind.CYLINDER:
			var cylinder := CylinderShape3D.new()
			cylinder.radius = maxf(r, 0.01)
			cylinder.height = maxf(h, 0.02)
			shape = cylinder
			position = Vector3(centre.x, bottom + cylinder.height * 0.5, centre.z)
		Kind.CAPSULE:
			var capsule := CapsuleShape3D.new()
			capsule.radius = maxf(r, 0.01)
			capsule.height = maxf(h, capsule.radius * 2.0)
			shape = capsule
			position = Vector3(centre.x, bottom + capsule.height * 0.5, centre.z)
		Kind.BOX:
			var box := BoxShape3D.new()
			box.size = bounds.size.max(Vector3.ONE * 0.02)
			shape = box
			position = centre
