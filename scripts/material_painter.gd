@tool
class_name MaterialPainter
extends Node
## Назначает материал мешам по именам внутри импортированной сцены.
##
## Зачем не назначить материал прямо в .tscn: меши приходят из glb, и их узлы
## создаёт импортёр. Путь до них — деталь импорта, он меняется от суффиксов
## коллизии и настроек, и прописанный руками путь тихо перестаёт совпадать.
## Здесь узлы ищутся по имени, а имена задаём мы сами в сборочном скрипте.
##
## Материалы, которые нельзя собрать в Blender, — шейдерные. Песок, вода, снег:
## всё, что живёт процедурой, а не текстурой. Их и назначаем отсюда.
##
## Использование: положить узел внутрь сцены, указать target на корень
## импортированной модели, выбрать материал и перечислить имена мешей.

## Корень, внутри которого искать. Пусто — берём родителя.
@export_node_path("Node3D") var target: NodePath
@export var material: Material
## Имена мешей. Совпадение по началу имени: «Sand» покроет и «Sand_02».
@export var mesh_names: Array[String] = []
## Красить всё, кроме перечисленного, а не только перечисленное.
@export var invert: bool = false
## Галочка в инспекторе — перекрасить прямо в редакторе.
@export var repaint: bool = false:
	set(value):
		repaint = false
		if value:
			paint()

## Сколько мешей покрашено последним вызовом. Для проверки.
var painted: int = 0


func _ready() -> void:
	if not Engine.is_editor_hint():
		paint()


func paint() -> void:
	painted = 0
	if material == null:
		push_warning("MaterialPainter: материал не задан.")
		return
	var root: Node = get_parent()
	if not target.is_empty():
		var found := get_node_or_null(target)
		if found != null:
			root = found
	if root == null:
		return
	_walk(root)
	if painted == 0:
		push_warning("MaterialPainter: под %s не нашлось мешей из списка %s."
			% [root.name, mesh_names])


func _walk(node: Node) -> void:
	if node is MeshInstance3D and _matches(node.name):
		var mesh := node as MeshInstance3D
		mesh.material_override = material
		painted += 1
	for child in node.get_children():
		_walk(child)


func _matches(node_name: String) -> bool:
	var hit := false
	for prefix in mesh_names:
		if node_name.begins_with(prefix):
			hit = true
			break
	return hit != invert
